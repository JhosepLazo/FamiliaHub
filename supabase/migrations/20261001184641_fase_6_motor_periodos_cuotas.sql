create or replace function app_private.fecha_vencimiento_mes(
	p_anio smallint,
	p_mes smallint,
	p_dia smallint
)
returns date
language sql
immutable
set search_path = ''
as $$
	select make_date(
		p_anio,
		p_mes,
		least(
			p_dia::int,
			extract(day from (make_date(p_anio, p_mes, 1) + interval '1 month - 1 day'))::int
		)
	);
$$;

create or replace function app_private.registrar_evento_financiero(
	p_familia_id uuid,
	p_entidad text,
	p_entidad_id uuid,
	p_evento text,
	p_detalle jsonb,
	p_usuario_id uuid
)
returns void
language sql
security definer
set search_path = ''
as $$
	insert into public.eventos_financieros (
		familia_id,
		entidad,
		entidad_id,
		evento,
		detalle,
		usuario_id
	)
	values (
		p_familia_id,
		p_entidad,
		p_entidad_id,
		p_evento,
		coalesce(p_detalle, '{}'::jsonb),
		p_usuario_id
	);
$$;

revoke all on function app_private.registrar_evento_financiero(uuid, text, uuid, text, jsonb, uuid) from public, anon, authenticated;

create or replace function app_private.calcular_cuotas(
	p_recibo_id uuid,
	p_monto numeric
)
returns table (
	miembro_id uuid,
	usuario_id uuid,
	nombre_miembro text,
	monto numeric
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
	v_tipo public.tipo_distribucion_concepto;
	v_reparto public.tipo_reparto_resto;
	v_centavos bigint;
	v_fijos_centavos bigint;
	v_resto_centavos bigint;
begin
	if p_monto is null or p_monto <= 0 or round(p_monto, 2) <> p_monto then
		raise exception 'El monto debe ser mayor a cero y tener máximo dos decimales.';
	end if;

	select tipo_distribucion, reparto_resto
	into v_tipo, v_reparto
	from public.recibos
	where id = p_recibo_id;

	if v_tipo is null then
		raise exception 'Recibo no encontrado.';
	end if;

	v_centavos := round(p_monto * 100)::bigint;

	if v_tipo = 'IGUAL' then
		return query
		with base as (
			select
				s.miembro_id,
				s.usuario_id,
				s.nombre_miembro,
				s.orden,
				row_number() over (order by s.orden, s.id) as rn,
				count(*) over () as total
			from public.recibo_participantes_snapshot s
			where s.recibo_id = p_recibo_id
		),
		calc as (
			select
				base.*,
				(v_centavos / total)::bigint as piso,
				(v_centavos % total)::bigint as resto
			from base
		)
		select
			calc.miembro_id,
			calc.usuario_id,
			calc.nombre_miembro,
			(
				(
					calc.piso
					+ case when calc.rn > calc.total - calc.resto then 1 else 0 end
				)::numeric / 100
			)::numeric(12,2)
		from calc
		order by calc.orden;
		return;
	end if;

	if v_tipo = 'PORCENTAJE' then
		return query
		with base as (
			select
				s.miembro_id,
				s.usuario_id,
				s.nombre_miembro,
				s.orden,
				(v_centavos::numeric * s.valor / 100) as exacto
			from public.recibo_participantes_snapshot s
			where s.recibo_id = p_recibo_id
				and s.modalidad = 'PORCENTAJE'
		),
		pisos as (
			select
				base.*,
				floor(base.exacto)::bigint as piso,
				base.exacto - floor(base.exacto) as fraccion
			from base
		),
		totales as (
			select coalesce(sum(piso), 0)::bigint as suma_pisos
			from pisos
		),
		ordenado as (
			select
				pisos.*,
				row_number() over (order by pisos.fraccion desc, pisos.orden, pisos.miembro_id) as prioridad,
				(v_centavos - totales.suma_pisos)::bigint as sobrantes
			from pisos
			cross join totales
		)
		select
			ordenado.miembro_id,
			ordenado.usuario_id,
			ordenado.nombre_miembro,
			(
				(
					ordenado.piso
					+ case when ordenado.prioridad <= ordenado.sobrantes then 1 else 0 end
				)::numeric / 100
			)::numeric(12,2)
		from ordenado
		order by ordenado.orden;
		return;
	end if;

	if v_tipo = 'MONTO_FIJO' then
		select coalesce(sum(round(s.valor * 100)::bigint), 0)
		into v_fijos_centavos
		from public.recibo_participantes_snapshot s
		where s.recibo_id = p_recibo_id
			and s.modalidad = 'MONTO_FIJO';

		if v_fijos_centavos <> v_centavos then
			raise exception 'Los montos fijos del snapshot no coinciden con el total del recibo.';
		end if;

		return query
		select
			s.miembro_id,
			s.usuario_id,
			s.nombre_miembro,
			round(s.valor, 2)::numeric(12,2)
		from public.recibo_participantes_snapshot s
		where s.recibo_id = p_recibo_id
			and s.modalidad = 'MONTO_FIJO'
		order by s.orden;
		return;
	end if;

	select coalesce(sum(round(s.valor * 100)::bigint), 0)
	into v_fijos_centavos
	from public.recibo_participantes_snapshot s
	where s.recibo_id = p_recibo_id
		and s.modalidad = 'MONTO_FIJO';

	v_resto_centavos := v_centavos - v_fijos_centavos;

	if v_resto_centavos <= 0 then
		raise exception 'El total del recibo debe superar la suma de montos fijos de la distribución mixta.';
	end if;

	return query
	select
		s.miembro_id,
		s.usuario_id,
		s.nombre_miembro,
		round(s.valor, 2)::numeric(12,2)
	from public.recibo_participantes_snapshot s
	where s.recibo_id = p_recibo_id
		and s.modalidad = 'MONTO_FIJO';

	if v_reparto = 'IGUAL' then
		return query
		with base as (
			select
				s.miembro_id,
				s.usuario_id,
				s.nombre_miembro,
				s.orden,
				row_number() over (order by s.orden, s.id) as rn,
				count(*) over () as total
			from public.recibo_participantes_snapshot s
			where s.recibo_id = p_recibo_id
				and s.modalidad = 'RESTO_IGUAL'
		),
		calc as (
			select
				base.*,
				(v_resto_centavos / total)::bigint as piso,
				(v_resto_centavos % total)::bigint as resto
			from base
		)
		select
			calc.miembro_id,
			calc.usuario_id,
			calc.nombre_miembro,
			(
				(
					calc.piso
					+ case when calc.rn > calc.total - calc.resto then 1 else 0 end
				)::numeric / 100
			)::numeric(12,2)
		from calc
		order by calc.orden;
		return;
	end if;

	return query
	with base as (
		select
			s.miembro_id,
			s.usuario_id,
			s.nombre_miembro,
			s.orden,
			(v_resto_centavos::numeric * s.valor / 100) as exacto
		from public.recibo_participantes_snapshot s
		where s.recibo_id = p_recibo_id
			and s.modalidad = 'RESTO_PORCENTAJE'
	),
	pisos as (
		select
			base.*,
			floor(base.exacto)::bigint as piso,
			base.exacto - floor(base.exacto) as fraccion
		from base
	),
	totales as (
		select coalesce(sum(piso), 0)::bigint as suma_pisos
		from pisos
	),
	ordenado as (
		select
			pisos.*,
			row_number() over (order by pisos.fraccion desc, pisos.orden, pisos.miembro_id) as prioridad,
			(v_resto_centavos - totales.suma_pisos)::bigint as sobrantes
		from pisos
		cross join totales
	)
	select
		ordenado.miembro_id,
		ordenado.usuario_id,
		ordenado.nombre_miembro,
		(
			(
				ordenado.piso
				+ case when ordenado.prioridad <= ordenado.sobrantes then 1 else 0 end
			)::numeric / 100
		)::numeric(12,2)
	from ordenado
	order by ordenado.orden;
end;
$$;

create or replace function app_private.actualizar_estado_cuota(p_cuota_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_asignado numeric;
	v_pagado numeric;
	v_pendiente numeric;
	v_estado public.estado_cuota;
begin
	select monto_asignado, monto_pagado, estado
	into v_asignado, v_pagado, v_estado
	from public.cuotas
	where id = p_cuota_id
	for update;

	if v_estado = 'ANULADA' then
		return;
	end if;

	select coalesce(sum(monto), 0)
	into v_pendiente
	from public.aportes
	where cuota_id = p_cuota_id
		and estado = 'POR_VALIDAR';

	update public.cuotas
	set estado = case
			when v_pagado >= v_asignado then 'PAGADA'::public.estado_cuota
			when v_pendiente > 0 then 'POR_VALIDAR'::public.estado_cuota
			when v_pagado > 0 then 'PARCIAL'::public.estado_cuota
			else 'PENDIENTE'::public.estado_cuota
		end,
		updated_at = now()
	where id = p_cuota_id;
end;
$$;

create or replace function app_private.actualizar_estado_recaudacion(p_recibo_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_asignado numeric;
	v_pagado numeric;
	v_estado public.estado_recaudacion;
begin
	select
		coalesce(sum(monto_asignado), 0),
		coalesce(sum(monto_pagado), 0)
	into v_asignado, v_pagado
	from public.cuotas
	where recibo_id = p_recibo_id
		and estado <> 'ANULADA';

	v_estado := case
		when v_asignado > 0 and v_pagado >= v_asignado then 'COMPLETA'::public.estado_recaudacion
		when v_pagado > 0 then 'PARCIAL'::public.estado_recaudacion
		else 'PENDIENTE'::public.estado_recaudacion
	end;

	update public.recibos
	set estado_recaudacion = v_estado,
		updated_at = now()
	where id = p_recibo_id;
end;
$$;

create or replace function app_private.intentar_cerrar_periodo(p_periodo_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_puede boolean;
begin
	select
		exists (
			select 1
			from public.recibos
			where periodo_id = p_periodo_id
				and estado <> 'ANULADO'
		)
		and not exists (
			select 1
			from public.recibos
			where periodo_id = p_periodo_id
				and estado <> 'ANULADO'
				and (
					estado <> 'PAGADO'
					or estado_recaudacion <> 'COMPLETA'
				)
		)
	into v_puede;

	if v_puede then
		update public.periodos
		set estado = 'COMPLETADO',
			completado_at = coalesce(completado_at, now()),
			cierre_tipo = coalesce(cierre_tipo, 'AUTOMATICO'),
			completado_por = case when cierre_tipo is null then null else completado_por end
		where id = p_periodo_id
			and estado = 'ABIERTO';
	end if;

	return v_puede;
end;
$$;

create or replace function app_private.crear_cuotas_recibo(p_recibo_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_familia_id uuid;
	v_monto numeric;
begin
	select familia_id, monto_total
	into v_familia_id, v_monto
	from public.recibos
	where id = p_recibo_id
	for update;

	if v_monto is null then
		raise exception 'El recibo todavía no tiene un monto confirmado.';
	end if;

	if exists (select 1 from public.cuotas where recibo_id = p_recibo_id) then
		raise exception 'Las cuotas de este recibo ya fueron creadas.';
	end if;

	insert into public.cuotas (
		familia_id,
		recibo_id,
		miembro_id,
		usuario_id,
		nombre_miembro,
		monto_asignado
	)
	select
		v_familia_id,
		p_recibo_id,
		c.miembro_id,
		c.usuario_id,
		c.nombre_miembro,
		c.monto
	from app_private.calcular_cuotas(p_recibo_id, v_monto) c;

	perform app_private.actualizar_estado_recaudacion(p_recibo_id);
end;
$$;

create or replace function app_private.crear_recibo_desde_concepto(
	p_periodo_id uuid,
	p_concepto_id uuid,
	p_fecha_referencia date
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_recibo_id uuid;
	v_familia_id uuid;
	v_anio smallint;
	v_mes smallint;
	v_metodo public.metodo_obtencion_monto;
	v_monto numeric;
	v_tipo_vencimiento public.tipo_vencimiento_concepto;
	v_dia smallint;
	v_fecha_vencimiento date;
	v_dias smallint;
begin
	select familia_id, anio, mes
	into v_familia_id, v_anio, v_mes
	from public.periodos
	where id = p_periodo_id;

	select metodo_obtencion, monto_fijo, tipo_vencimiento, dia_vencimiento, dias_anticipacion_aporte
	into v_metodo, v_monto, v_tipo_vencimiento, v_dia, v_dias
	from public.conceptos_pago
	where id = p_concepto_id
		and familia_id = v_familia_id
		and activo = true;

	if v_metodo is null then
		raise exception 'Concepto no disponible para el periodo.';
	end if;

	if v_tipo_vencimiento = 'DIA_FIJO' then
		v_fecha_vencimiento := app_private.fecha_vencimiento_mes(v_anio, v_mes, v_dia);
	end if;

	insert into public.recibos (
		familia_id,
		periodo_id,
		concepto_id,
		nombre_concepto,
		categoria_nombre,
		proveedor_nombre,
		tipo_servicio,
		frecuencia,
		metodo_obtencion,
		tipo_vencimiento,
		tipo_distribucion,
		reparto_resto,
		dias_anticipacion_aporte,
		monto_base,
		fecha_vencimiento,
		fecha_limite_aporte,
		estado,
		monto_confirmado_at
	)
	select
		c.familia_id,
		p_periodo_id,
		c.id,
		c.nombre,
		cat.nombre,
		p.nombre,
		p.tipo_servicio,
		c.frecuencia,
		c.metodo_obtencion,
		c.tipo_vencimiento,
		c.tipo_distribucion,
		c.reparto_resto,
		c.dias_anticipacion_aporte,
		case when c.metodo_obtencion = 'FIJO' then c.monto_fijo else null end,
		v_fecha_vencimiento,
		case when v_fecha_vencimiento is not null then v_fecha_vencimiento - c.dias_anticipacion_aporte else null end,
		case
			when c.metodo_obtencion <> 'FIJO' then 'ESPERANDO_MONTO'::public.estado_recibo
			when v_fecha_vencimiento is not null and v_fecha_vencimiento < p_fecha_referencia then 'VENCIDO'::public.estado_recibo
			else 'PENDIENTE'::public.estado_recibo
		end,
		case when c.metodo_obtencion = 'FIJO' then now() else null end
	from public.conceptos_pago c
	inner join public.categorias cat on cat.id = c.categoria_id
	inner join public.proveedores p on p.id = c.proveedor_id
	where c.id = p_concepto_id
	on conflict (periodo_id, concepto_id) do nothing
	returning id into v_recibo_id;

	if v_recibo_id is null then
		select id into v_recibo_id
		from public.recibos
		where periodo_id = p_periodo_id
			and concepto_id = p_concepto_id;
		return v_recibo_id;
	end if;

	insert into public.recibo_cuentas_snapshot (
		recibo_id,
		identificador_nombre,
		identificador_valor,
		alias
	)
	select
		v_recibo_id,
		coalesce(t.nombre, cs.identificador_nombre, 'Cuenta'),
		cs.identificador_valor,
		cs.alias
	from public.cuentas_servicio cs
	left join public.tipos_identificador_proveedor t on t.id = cs.tipo_identificador_id
	where cs.concepto_id = p_concepto_id
		and cs.activo = true;

	insert into public.recibo_participantes_snapshot (
		recibo_id,
		miembro_id,
		usuario_id,
		nombre_miembro,
		modalidad,
		valor,
		orden
	)
	select
		v_recibo_id,
		cp.miembro_id,
		m.usuario_id,
		coalesce(per.nombre, 'Integrante'),
		cp.modalidad,
		cp.valor,
		cp.orden
	from public.concepto_participantes cp
	inner join public.miembros_familia m on m.id = cp.miembro_id
	left join public.perfiles per on per.id = m.usuario_id
	where cp.concepto_id = p_concepto_id
		and m.estado = 'ACTIVO'
	order by cp.orden;

	if not exists (
		select 1
		from public.recibo_participantes_snapshot
		where recibo_id = v_recibo_id
	) then
		raise exception 'El concepto no tiene participantes activos.';
	end if;

	if v_metodo = 'FIJO' then
		perform app_private.crear_cuotas_recibo(v_recibo_id);
	end if;

	perform app_private.registrar_evento_financiero(
		v_familia_id,
		'RECIBO',
		v_recibo_id,
		'RECIBO_GENERADO',
		jsonb_build_object('periodo_id', p_periodo_id, 'concepto_id', p_concepto_id),
		null
	);

	return v_recibo_id;
end;
$$;

create or replace function app_private.sincronizar_periodos_impl(
	p_familia_id uuid default null,
	p_fecha date default (timezone('America/Lima', now()))::date
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_familia record;
	v_periodo_id uuid;
	v_concepto record;
	v_objetivo date := make_date(extract(year from p_fecha)::int, extract(month from p_fecha)::int, 1);
	v_inicio date;
	v_generados integer := 0;
begin
	for v_familia in
		select id
		from public.familias
		where activo = true
			and (p_familia_id is null or id = p_familia_id)
	loop
		insert into public.periodos (familia_id, anio, mes)
		values (
			v_familia.id,
			extract(year from p_fecha)::smallint,
			extract(month from p_fecha)::smallint
		)
		on conflict (familia_id, anio, mes) do nothing;

		select id
		into v_periodo_id
		from public.periodos
		where familia_id = v_familia.id
			and anio = extract(year from p_fecha)::smallint
			and mes = extract(month from p_fecha)::smallint;

		for v_concepto in
			select *
			from public.conceptos_pago
			where familia_id = v_familia.id
				and activo = true
		loop
			v_inicio := date_trunc('month', v_concepto.fecha_inicio_generacion)::date;

			if (
				v_concepto.frecuencia = 'MENSUAL'
				and v_objetivo >= v_inicio
			) or (
				v_concepto.frecuencia = 'ANUAL'
				and v_objetivo >= v_inicio
				and extract(month from v_objetivo) = extract(month from v_inicio)
			) or (
				v_concepto.frecuencia = 'UNICA'
				and v_objetivo = v_inicio
			) then
				if not exists (
					select 1
					from public.recibos
					where periodo_id = v_periodo_id
						and concepto_id = v_concepto.id
				) then
					perform app_private.crear_recibo_desde_concepto(
						v_periodo_id,
						v_concepto.id,
						p_fecha
					);
					v_generados := v_generados + 1;
				end if;
			end if;
		end loop;
	end loop;

	return v_generados;
end;
$$;

create or replace function app_private.procesar_ciclo_diario()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_fecha date := (timezone('America/Lima', now()))::date;
	v_periodo record;
begin
	perform app_private.sincronizar_periodos_impl(null, v_fecha);

	update public.recibos
	set estado = 'VENCIDO',
		updated_at = now()
	where estado = 'PENDIENTE'
		and fecha_vencimiento is not null
		and fecha_vencimiento < v_fecha;

	update public.recibos
	set estado = 'PENDIENTE',
		updated_at = now()
	where estado = 'VENCIDO'
		and fecha_vencimiento is not null
		and fecha_vencimiento >= v_fecha;

	for v_periodo in
		select id
		from public.periodos
		where estado = 'ABIERTO'
	loop
		perform app_private.intentar_cerrar_periodo(v_periodo.id);
	end loop;
end;
$$;

revoke all on function app_private.fecha_vencimiento_mes(smallint, smallint, smallint) from public, anon, authenticated;
revoke all on function app_private.calcular_cuotas(uuid, numeric) from public, anon, authenticated;
revoke all on function app_private.actualizar_estado_cuota(uuid) from public, anon, authenticated;
revoke all on function app_private.actualizar_estado_recaudacion(uuid) from public, anon, authenticated;
revoke all on function app_private.intentar_cerrar_periodo(uuid) from public, anon, authenticated;
revoke all on function app_private.crear_cuotas_recibo(uuid) from public, anon, authenticated;
revoke all on function app_private.crear_recibo_desde_concepto(uuid, uuid, date) from public, anon, authenticated;
revoke all on function app_private.sincronizar_periodos_impl(uuid, date) from public, anon;
revoke all on function app_private.procesar_ciclo_diario() from public, anon, authenticated, service_role;

grant execute on function app_private.sincronizar_periodos_impl(uuid, date) to authenticated;
