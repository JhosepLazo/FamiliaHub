-- Recibos digitales más robustos y vigilados:
-- 1. Si el correo muestra el suministro oculto ("****4567"), se reconoce por sus últimas cifras (al menos 4)
--    cuando coinciden con un solo servicio de ese proveedor.
-- 2. Si el recibo digital de un servicio no llega cuando normalmente ya debería estar, se avisa una sola vez
--    a los administradores en el grupo de WhatsApp (además del resumen diario de pendientes).

alter type public.tipo_aviso_whatsapp add value if not exists 'RECIBO_DIGITAL_FALTA';

create or replace function app_private.registrar_recibo_digital_impl(
	p_mensaje_id text,
	p_proveedor text,
	p_suministros text[],
	p_monto numeric,
	p_fecha_vencimiento date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_suministros text[];
	v_id uuid;
	v_resultado public.recibos_digitales%rowtype;
begin
	if nullif(trim(coalesce(p_mensaje_id, '')), '') is null or char_length(p_mensaje_id) > 200 then
		raise exception 'Falta el identificador del correo.';
	end if;

	if p_proveedor is null or p_proveedor not in ('SEDAPAL', 'LUZ_DEL_SUR', 'CALIDDA') then
		raise exception 'Proveedor no soportado.';
	end if;

	select array_agg(distinct s)
	into v_suministros
	from (
		select left(trim(valor), 30) as s
		from unnest(coalesce(p_suministros, '{}'::text[])) as valor
		where length(app_private.recibo_digital_digitos(valor)) >= 5
			-- Suministro oculto en el correo ("****4567"): llega como "*4567" y se compara por sus últimas cifras.
			or (left(trim(valor), 1) = '*' and length(app_private.recibo_digital_digitos(valor)) >= 4)
		limit 10
	) as candidatos;

	if v_suministros is null then
		raise exception 'Falta el número de suministro.';
	end if;

	if p_monto is null or p_monto <= 0 or p_monto > 100000 or round(p_monto, 2) <> p_monto then
		raise exception 'El monto debe ser mayor a cero y tener máximo dos decimales.';
	end if;

	if p_fecha_vencimiento is null then
		raise exception 'Falta la fecha de vencimiento.';
	end if;

	insert into public.recibos_digitales (mensaje_id, proveedor_codigo, suministros, monto, fecha_vencimiento)
	values (trim(p_mensaje_id), p_proveedor, v_suministros, p_monto, p_fecha_vencimiento)
	on conflict (mensaje_id) do nothing
	returning id into v_id;

	-- El mismo correo puede llegar dos veces: se responde con lo que ya se resolvió, sin aplicarlo de nuevo.
	if v_id is null then
		select * into v_resultado from public.recibos_digitales where mensaje_id = trim(p_mensaje_id);
		return jsonb_build_object('estado', v_resultado.estado, 'detalle', v_resultado.detalle, 'reciboId', v_resultado.recibo_id, 'repetido', true);
	end if;

	perform app_private.aplicar_recibo_digital(v_id);

	select * into v_resultado from public.recibos_digitales where id = v_id;
	return jsonb_build_object('estado', v_resultado.estado, 'detalle', v_resultado.detalle, 'reciboId', v_resultado.recibo_id, 'repetido', false);
end;
$$;


create or replace function app_private.aplicar_recibo_digital(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_lectura public.recibos_digitales%rowtype;
	v_conceptos uuid[];
	v_concepto_id uuid;
	v_familia_id uuid;
	v_recibo public.recibos%rowtype;
	v_anterior numeric;
	v_vencimiento date;
	v_hoy date := (timezone('America/Lima', now()))::date;
begin
	select *
	into v_lectura
	from public.recibos_digitales
	where id = p_id
	for update;

	if v_lectura.id is null or v_lectura.estado <> 'EN_ESPERA' then
		return;
	end if;

	update public.recibos_digitales set intentos = intentos + 1 where id = p_id;

	select array_agg(distinct c.id)
	into v_conceptos
	from public.cuentas_servicio cs
	inner join public.conceptos_pago c on c.id = cs.concepto_id and c.activo
	inner join public.proveedores p on p.id = c.proveedor_id and p.codigo = v_lectura.proveedor_codigo
	where cs.activo
		and length(app_private.recibo_digital_digitos(cs.identificador_valor)) >= 5
		and exists (
			select 1
			from unnest(v_lectura.suministros) as s
			where (left(s, 1) <> '*' and app_private.recibo_digital_digitos(s) = app_private.recibo_digital_digitos(cs.identificador_valor))
				-- Oculto ("*4567"): basta que el suministro registrado termine en esas cifras; si coincide con
				-- más de un servicio, la lectura queda para revisar (abajo).
				or (left(s, 1) = '*' and app_private.recibo_digital_digitos(cs.identificador_valor) like '%' || app_private.recibo_digital_digitos(s))
		);

	if v_conceptos is null then
		perform app_private.recibo_digital_cerrar(p_id, 'IGNORADO', 'Ningún servicio tiene registrado ese número de suministro para este proveedor.');
		return;
	end if;

	if cardinality(v_conceptos) > 1 then
		perform app_private.recibo_digital_cerrar(p_id, 'REVISAR', 'El número de suministro coincide con más de un servicio.');
		return;
	end if;

	v_concepto_id := v_conceptos[1];
	select familia_id into v_familia_id from public.conceptos_pago where id = v_concepto_id;
	update public.recibos_digitales set concepto_id = v_concepto_id, familia_id = v_familia_id where id = p_id;

	if v_lectura.fecha_vencimiento < v_hoy - 60 or v_lectura.fecha_vencimiento > v_hoy + 90 then
		perform app_private.recibo_digital_cerrar(p_id, 'REVISAR', 'La fecha de vencimiento del correo no es razonable.');
		return;
	end if;

	-- El recibo de FamiliaHub del mes del vencimiento o del anterior (un recibo puede vencer a inicios del mes siguiente).
	select r.*
	into v_recibo
	from public.recibos r
	inner join public.periodos pe on pe.id = r.periodo_id
	where r.concepto_id = v_concepto_id
		and r.estado <> 'ANULADO'
		and make_date(pe.anio, pe.mes, 1) between (date_trunc('month', v_lectura.fecha_vencimiento) - interval '1 month')::date
			and date_trunc('month', v_lectura.fecha_vencimiento)::date
	order by (r.estado = 'ESPERANDO_MONTO') desc, pe.anio desc, pe.mes desc
	limit 1
	for update of r;

	if v_recibo.id is null then
		if v_lectura.fecha_vencimiento + 10 < v_hoy then
			perform app_private.recibo_digital_cerrar(p_id, 'IGNORADO', 'No hubo recibo de ese mes para este servicio.');
		else
			perform app_private.recibo_digital_cerrar(p_id, 'EN_ESPERA', 'Esperando a que FamiliaHub cree el recibo del mes.');
		end if;
		return;
	end if;

	if v_recibo.estado <> 'ESPERANDO_MONTO' then
		perform app_private.recibo_digital_cerrar(p_id, 'IGNORADO', 'Ese recibo ya tenía el monto confirmado.', v_recibo.id);
		return;
	end if;

	select r.monto_base
	into v_anterior
	from public.recibos r
	where r.concepto_id = v_concepto_id
		and r.id <> v_recibo.id
		and r.estado <> 'ANULADO'
		and r.monto_confirmado_at is not null
		and r.monto_base is not null
	order by r.monto_confirmado_at desc
	limit 1;

	if v_anterior is not null and v_anterior > 0 and (v_lectura.monto > v_anterior * 3 or v_lectura.monto < v_anterior / 3) then
		perform app_private.recibo_digital_cerrar(
			p_id,
			'REVISAR',
			format('El monto S/ %s es muy distinto al anterior (S/ %s). Confírmalo en la app.', to_char(v_lectura.monto, 'FM999990.00'), to_char(v_anterior, 'FM999990.00')),
			v_recibo.id
		);
		return;
	end if;

	-- Mismos pasos que confirmar_monto_recibo_impl, sin exigir una sesión de administrador.
	begin
		v_vencimiento := case when v_recibo.tipo_vencimiento = 'DIA_FIJO' then v_recibo.fecha_vencimiento else v_lectura.fecha_vencimiento end;

		update public.recibos
		set monto_base = v_lectura.monto,
			fecha_vencimiento = v_vencimiento,
			fecha_limite_aporte = case
				when v_vencimiento is null then null
				else v_vencimiento - dias_anticipacion_aporte
			end,
			estado = case
				when v_vencimiento is not null and v_vencimiento < v_hoy then 'VENCIDO'::public.estado_recibo
				else 'PENDIENTE'::public.estado_recibo
			end,
			monto_confirmado_at = now(),
			updated_at = now()
		where id = v_recibo.id;

		perform app_private.crear_cuotas_recibo(v_recibo.id);

		perform app_private.registrar_evento_financiero(
			v_recibo.familia_id,
			'RECIBO',
			v_recibo.id,
			'MONTO_CONFIRMADO',
			jsonb_build_object('monto', v_lectura.monto, 'fecha_vencimiento', v_vencimiento, 'origen', 'RECIBO_DIGITAL'),
			null
		);

		perform app_private.recibo_digital_cerrar(p_id, 'CONFIRMADO', 'Monto confirmado automáticamente con el recibo digital.', v_recibo.id);
	exception
		when others then
			perform app_private.recibo_digital_cerrar(p_id, 'REVISAR', 'No se pudo confirmar: ' || sqlerrm, v_recibo.id);
	end;
end;
$$;


-- Fecha desde la que el recibo digital "ya debería haber llegado": 5 días antes del día en que venció el recibo
-- del mes anterior (los proveedores envían el recibo unos días antes del vencimiento), o el día 25 si no hay historial.
create or replace function app_private.recibo_digital_esperado_desde(p_recibo public.recibos)
returns date
language sql
stable
security definer
set search_path = ''
as $$
	select make_date(pe.anio, pe.mes, 1) + (
		least(
			28,
			greatest(
				1,
				coalesce(
					(
						select extract(day from anterior.fecha_vencimiento)::integer - 5
						from public.recibos anterior
						where anterior.concepto_id = (p_recibo).concepto_id
							and anterior.id <> (p_recibo).id
							and anterior.estado <> 'ANULADO'
							and anterior.fecha_vencimiento is not null
						order by anterior.fecha_vencimiento desc
						limit 1
					),
					25
				)
			)
		) - 1
	)
	from public.periodos pe
	where pe.id = (p_recibo).periodo_id;
$$;

create or replace function app_private.recibos_digitales_vigilar()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_hoy date := (timezone('America/Lima', now()))::date;
	v_fila record;
	v_recibo public.recibos%rowtype;
	v_admins record;
	v_avisados integer := 0;
begin
	for v_fila in
		select r.*, p.nombre as proveedor, cs.identificador_valor as suministro
		from public.recibos r
		inner join public.periodos pe on pe.id = r.periodo_id and pe.estado = 'ABIERTO'
		inner join public.conceptos_pago c on c.id = r.concepto_id and c.activo
		inner join public.proveedores p on p.id = c.proveedor_id and p.codigo in ('SEDAPAL', 'LUZ_DEL_SUR', 'CALIDDA')
		inner join public.cuentas_servicio cs on cs.concepto_id = c.id and cs.activo
		where r.estado = 'ESPERANDO_MONTO'
			and length(app_private.recibo_digital_digitos(cs.identificador_valor)) >= 5
			-- Solo el periodo del mes en curso.
			and make_date(pe.anio, pe.mes, 1) = date_trunc('month', v_hoy)::date
			-- Ninguna lectura de este servicio en los últimos 40 días (ni siquiera una para revisar).
			and not exists (
				select 1
				from public.recibos_digitales d
				where d.concepto_id = c.id
					and d.created_at > now() - interval '40 days'
			)
	loop
		select * into v_recibo from public.recibos where id = v_fila.id;
		if v_hoy < app_private.recibo_digital_esperado_desde(v_recibo) then
			continue;
		end if;

		select * into v_admins from app_private.whatsapp_menciones_admins(v_fila.familia_id);

		perform app_private.whatsapp_encolar(
			v_fila.familia_id,
			'RECIBO_DIGITAL_FALTA'::public.tipo_aviso_whatsapp,
			'RECIBO_DIGITAL_FALTA:' || v_fila.id,
			v_fila.id,
			array_to_string(array[
				'📭 *' || v_fila.nombre_concepto || ':* el recibo digital de ' || v_fila.proveedor || ' aún no llega (suministro ' || v_fila.suministro || ').',
				'Normalmente ya debería estar. Revisa el correo o registra el monto en FamiliaHub: {APP_URL}/recibos/' || v_fila.id,
				coalesce(v_admins.texto, 'Administradores') || case when coalesce(v_admins.cantidad, 1) > 1 then ', revísenlo.' else ', revísalo.' end
			], E'\n'),
			coalesce(v_admins.menciones, '{}'::text[]),
			now() + interval '20 hours'
		);
		v_avisados := v_avisados + 1;
	end loop;

	return v_avisados;
end;
$$;

revoke all on function app_private.recibo_digital_esperado_desde(public.recibos) from public, anon, authenticated, service_role;
revoke all on function app_private.recibos_digitales_vigilar() from public, anon, authenticated, service_role;

-- Una vez al día, a las 09:15 de Lima (14:15 UTC).
do $$
begin
	perform cron.unschedule('familiahub-recibos-digitales-vigilar');
exception
	when others then
		null;
end
$$;

select cron.schedule(
	'familiahub-recibos-digitales-vigilar',
	'15 14 * * *',
	$$select app_private.recibos_digitales_vigilar();$$
);
