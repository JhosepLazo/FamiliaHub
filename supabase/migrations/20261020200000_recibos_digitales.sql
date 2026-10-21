-- Recibos digitales: cuando llega por correo el recibo digital de SEDAPAL, Luz del Sur o Cálidda, un script
-- en el Gmail de la familia envía el número de suministro, el monto y el vencimiento, y FamiliaHub confirma
-- solo el recibo del mes. Nunca se adivina: si algo no cuadra, el recibo queda pendiente como antes.

create type public.estado_recibo_digital as enum ('EN_ESPERA', 'CONFIRMADO', 'REVISAR', 'IGNORADO');

create table public.recibos_digitales (
	id uuid primary key default gen_random_uuid(),
	mensaje_id text not null unique check (char_length(mensaje_id) between 1 and 200),
	proveedor_codigo text not null check (proveedor_codigo in ('SEDAPAL', 'LUZ_DEL_SUR', 'CALIDDA')),
	suministros text[] not null check (cardinality(suministros) between 1 and 10),
	monto numeric(12,2) not null check (monto > 0 and monto <= 100000),
	fecha_vencimiento date not null,
	estado public.estado_recibo_digital not null default 'EN_ESPERA',
	detalle text check (char_length(detalle) <= 300),
	familia_id uuid references public.familias(id) on delete cascade,
	concepto_id uuid references public.conceptos_pago(id) on delete set null,
	recibo_id uuid references public.recibos(id) on delete set null,
	intentos smallint not null default 0,
	created_at timestamptz not null default now(),
	procesado_at timestamptz
);

create index idx_recibos_digitales_en_espera on public.recibos_digitales(created_at) where estado = 'EN_ESPERA';
create index idx_recibos_digitales_familia on public.recibos_digitales(familia_id, created_at desc);
create index idx_recibos_digitales_concepto on public.recibos_digitales(concepto_id) where concepto_id is not null;
create index idx_recibos_digitales_recibo on public.recibos_digitales(recibo_id) where recibo_id is not null;

alter table public.recibos_digitales enable row level security;
revoke all on table public.recibos_digitales from anon, authenticated;

-- Los administradores pueden ver qué recibos digitales llegaron y qué pasó con cada uno.
create policy recibos_digitales_select_admin
on public.recibos_digitales
for select
to authenticated
using (familia_id is not null and app_private.es_admin(familia_id, (select auth.uid())));

grant select on public.recibos_digitales to authenticated;

create or replace function app_private.recibo_digital_digitos(p_valor text)
returns text
language sql
immutable
set search_path = ''
as $$
	select regexp_replace(coalesce(p_valor, ''), '\D', '', 'g');
$$;

create or replace function app_private.recibo_digital_cerrar(
	p_id uuid,
	p_estado public.estado_recibo_digital,
	p_detalle text,
	p_recibo_id uuid default null
)
returns void
language sql
security definer
set search_path = ''
as $$
	update public.recibos_digitales
	set estado = p_estado,
		detalle = left(p_detalle, 300),
		recibo_id = coalesce(p_recibo_id, recibo_id),
		procesado_at = case when p_estado = 'EN_ESPERA' then null else now() end
	where id = p_id;
$$;

-- Intenta aplicar una lectura pendiente. Solo confirma si el suministro coincide exactamente con un servicio
-- del proveedor, el vencimiento es razonable, hay un recibo de ese mes esperando monto y el monto no se
-- aleja demasiado del último confirmado.
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
		and app_private.recibo_digital_digitos(cs.identificador_valor) in (
			select app_private.recibo_digital_digitos(s) from unnest(v_lectura.suministros) as s
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

-- Job horario: vuelve a intentar las lecturas que llegaron antes de que existiera el recibo del mes.
create or replace function app_private.aplicar_recibos_digitales_en_espera()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_id uuid;
	v_total integer := 0;
begin
	update public.recibos_digitales
	set estado = 'IGNORADO',
		detalle = 'Pasaron 45 días sin recibo del mes para aplicarlo.',
		procesado_at = now()
	where estado = 'EN_ESPERA'
		and created_at < now() - interval '45 days';

	for v_id in
		select id
		from public.recibos_digitales
		where estado = 'EN_ESPERA'
		order by created_at
		limit 100
	loop
		perform app_private.aplicar_recibo_digital(v_id);
		v_total := v_total + 1;
	end loop;

	return v_total;
end;
$$;

create or replace function public.registrar_recibo_digital(
	p_mensaje_id text,
	p_proveedor text,
	p_suministros text[],
	p_monto numeric,
	p_fecha_vencimiento date
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select app_private.registrar_recibo_digital_impl(p_mensaje_id, p_proveedor, p_suministros, p_monto, p_fecha_vencimiento); $$;

revoke all on function app_private.recibo_digital_digitos(text) from public, anon, authenticated, service_role;
revoke all on function app_private.recibo_digital_cerrar(uuid, public.estado_recibo_digital, text, uuid) from public, anon, authenticated, service_role;
revoke all on function app_private.aplicar_recibo_digital(uuid) from public, anon, authenticated, service_role;
revoke all on function app_private.aplicar_recibos_digitales_en_espera() from public, anon, authenticated, service_role;
revoke all on function app_private.registrar_recibo_digital_impl(text, text, text[], numeric, date) from public, anon, authenticated;
revoke all on function public.registrar_recibo_digital(text, text, text[], numeric, date) from public, anon, authenticated;

grant execute on function app_private.registrar_recibo_digital_impl(text, text, text[], numeric, date) to service_role;
grant execute on function public.registrar_recibo_digital(text, text, text[], numeric, date) to service_role;

do $$
begin
	perform cron.unschedule('familiahub-recibos-digitales');
exception
	when others then
		null;
end
$$;

select cron.schedule(
	'familiahub-recibos-digitales',
	'20 * * * *',
	$$select app_private.aplicar_recibos_digitales_en_espera();$$
);
