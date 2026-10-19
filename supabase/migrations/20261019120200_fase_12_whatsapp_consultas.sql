create or replace function app_private.whatsapp_emoji_servicio(p_tipo public.tipo_servicio)
returns text
language sql
immutable
set search_path = ''
as $$
	select case p_tipo
		when 'LUZ' then '💡'
		when 'AGUA' then '💧'
		when 'INTERNET' then '🌐'
		when 'GAS' then '🔥'
		else '🧾'
	end;
$$;

create or replace function app_private.whatsapp_unir(p_partes text[])
returns text
language sql
immutable
set search_path = ''
as $$
	select case
		when coalesce(cardinality(p_partes), 0) = 0 then null
		when cardinality(p_partes) = 1 then p_partes[1]
		else array_to_string(p_partes[1:cardinality(p_partes) - 1], ', ') || ' y ' || p_partes[cardinality(p_partes)]
	end;
$$;

create or replace function app_private.whatsapp_estado_recaudacion(
	p_estado public.estado_recaudacion,
	p_pagado numeric,
	p_total numeric
)
returns text
language sql
immutable
set search_path = ''
as $$
	select case
		when p_estado = 'COMPLETA' then 'completo'
		when coalesce(p_pagado, 0) > 0 and coalesce(p_total, 0) > 0
			then 'recaudando (' || round(p_pagado / p_total * 100)::int::text || '%)'
		else 'por recaudar'
	end;
$$;

create or replace function app_private.whatsapp_hace(p_dias integer)
returns text
language sql
immutable
set search_path = ''
as $$
	select case
		when p_dias is null or p_dias <= 0 then 'hoy'
		when p_dias = 1 then 'ayer'
		else 'hace ' || p_dias::text || ' días'
	end;
$$;

create or replace function app_private.whatsapp_deuda_usuario(
	p_familia_id uuid,
	p_usuario_id uuid,
	p_periodo_id uuid
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
	select coalesce(sum(q.saldo_pendiente), 0)
	from public.cuotas q
	inner join public.recibos r on r.id = q.recibo_id
	where q.familia_id = p_familia_id
		and q.usuario_id = p_usuario_id
		and r.periodo_id = p_periodo_id
		and q.estado <> 'ANULADA'
		and q.saldo_pendiente > 0;
$$;

create or replace function app_private.whatsapp_es_responsable(p_familia_id uuid, p_miembro_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
	select
		exists (
			select 1
			from public.configuracion_pago_familiar c
			where c.familia_id = p_familia_id
				and c.responsable_miembro_id = p_miembro_id
				and c.activo
		)
		or exists (
			select 1
			from public.configuracion_cobro_miembro c
			where c.familia_id = p_familia_id
				and c.miembro_id = p_miembro_id
				and c.activo
		)
		or exists (
			select 1
			from public.pagos_familiares pf
			where pf.familia_id = p_familia_id
				and pf.responsable_receptor_miembro_id = p_miembro_id
				and pf.estado = 'POR_VALIDAR'
		)
		or exists (
			select 1
			from public.aportes a
			where a.familia_id = p_familia_id
				and a.receptor_miembro_id = p_miembro_id
				and a.estado = 'POR_VALIDAR'
		);
$$;

create or replace function app_private.whatsapp_texto_resumen(p_familia_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
	v_periodo public.periodos%rowtype;
	v_moneda char(3);
	v_hoy date := app_private.whatsapp_ahora_local(p_familia_id)::date;
	v_total numeric;
	v_recibos integer;
	v_pagados integer;
	v_esperando integer;
	v_vencidos integer;
	v_recaudado numeric;
	v_falta numeric;
	v_proximos text[];
	v_pendientes text[];
	v_linea text;
begin
	select *
	into v_periodo
	from public.periodos
	where id = app_private.whatsapp_periodo_actual(p_familia_id);

	if v_periodo.id is null then
		return null;
	end if;

	select moneda
	into v_moneda
	from public.familias
	where id = p_familia_id;

	select
		coalesce(sum(r.monto_total) filter (where r.monto_total is not null), 0),
		count(*),
		count(*) filter (where r.estado = 'PAGADO'),
		count(*) filter (where r.estado = 'ESPERANDO_MONTO'),
		count(*) filter (where r.estado = 'VENCIDO')
	into v_total, v_recibos, v_pagados, v_esperando, v_vencidos
	from public.recibos r
	where r.periodo_id = v_periodo.id
		and r.estado <> 'ANULADO';

	select
		coalesce(sum(q.monto_pagado), 0),
		coalesce(sum(q.saldo_pendiente), 0)
	into v_recaudado, v_falta
	from public.cuotas q
	inner join public.recibos r on r.id = q.recibo_id
	where r.periodo_id = v_periodo.id
		and r.estado <> 'ANULADO'
		and q.estado <> 'ANULADA';

	select array_agg(x.nombre_concepto || ' ' || app_private.whatsapp_fecha(x.fecha_objetivo) order by x.fecha_objetivo, x.nombre_concepto)
	into v_proximos
	from (
		select
			r.nombre_concepto,
			coalesce(r.fecha_limite_aporte, r.fecha_vencimiento) as fecha_objetivo
		from public.recibos r
		where r.periodo_id = v_periodo.id
			and r.estado not in ('ANULADO', 'PAGADO')
			and coalesce(r.fecha_limite_aporte, r.fecha_vencimiento) >= v_hoy
			and exists (
				select 1
				from public.cuotas q
				where q.recibo_id = r.id
					and q.estado <> 'ANULADA'
					and q.saldo_pendiente > 0
			)
		order by fecha_objetivo, r.nombre_concepto
		limit 3
	) x;

	select array_agg(x.nombre || ' ' || app_private.whatsapp_monto(x.total, v_moneda) order by x.total desc, x.nombre)
	into v_pendientes
	from (
		select
			q.miembro_id,
			min(q.nombre_miembro) as nombre,
			sum(q.saldo_pendiente) as total
		from public.cuotas q
		inner join public.recibos r on r.id = q.recibo_id
		where r.periodo_id = v_periodo.id
			and r.estado <> 'ANULADO'
			and q.estado <> 'ANULADA'
			and q.saldo_pendiente > 0
		group by q.miembro_id
		order by total desc, nombre
		limit 5
	) x;

	if v_recibos = 0 then
		return '📊 *Resumen — ' || app_private.whatsapp_mes(v_periodo.anio, v_periodo.mes) || '*' || E'\n' || 'Aún no hay recibos este mes.';
	end if;

	v_linea := 'Recaudado ' || app_private.whatsapp_monto(v_recaudado, v_moneda);

	if v_total > 0 then
		v_linea := v_linea || ' de ' || app_private.whatsapp_monto(v_total, v_moneda)
			|| ' (' || round(v_recaudado / v_total * 100)::int::text || '%)';
	end if;

	if v_falta > 0 then
		v_linea := v_linea || ' · falta ' || app_private.whatsapp_monto(v_falta, v_moneda);
	end if;

	return array_to_string(array[
		'📊 *Resumen — ' || app_private.whatsapp_mes(v_periodo.anio, v_periodo.mes) || '*',
		v_linea,
		'Pagados a la empresa: ' || v_pagados::text || ' de ' || v_recibos::text,
		case when v_esperando > 0 then 'Esperando monto: ' || v_esperando::text end,
		case when v_vencidos > 0 then '⚠️ Vencidos: ' || v_vencidos::text end,
		case when v_proximos is not null then 'Próximos: ' || array_to_string(v_proximos, ' · ') end,
		case
			when v_pendientes is not null then 'Pendientes: ' || array_to_string(v_pendientes, ' · ')
			else 'Pendientes: nadie 🎉'
		end
	], E'\n');
end;
$$;

create or replace function app_private.whatsapp_cmd_deuda(
	p_familia_id uuid,
	p_usuario_id uuid,
	p_nombre text,
	p_moneda char(3)
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
	v_periodo public.periodos%rowtype;
	v_hoy date := app_private.whatsapp_ahora_local(p_familia_id)::date;
	v_debe numeric;
	v_lineas text[];
	v_validacion text[];
	v_anteriores numeric;
	v_partes text[];
begin
	select *
	into v_periodo
	from public.periodos
	where id = app_private.whatsapp_periodo_actual(p_familia_id);

	if v_periodo.id is null then
		return 'Aún no se generaron los recibos de este mes.';
	end if;

	with pendientes as (
		select
			q.estado,
			q.saldo_pendiente,
			r.nombre_concepto,
			coalesce(r.fecha_limite_aporte, r.fecha_vencimiento) as fecha_objetivo,
			coalesce(coalesce(r.fecha_limite_aporte, r.fecha_vencimiento) < v_hoy, false) as vencida
		from public.cuotas q
		inner join public.recibos r on r.id = q.recibo_id
		where q.familia_id = p_familia_id
			and q.usuario_id = p_usuario_id
			and r.periodo_id = v_periodo.id
			and q.estado <> 'ANULADA'
			and q.saldo_pendiente > 0
	)
	select
		coalesce(sum(saldo_pendiente), 0),
		array_agg(
			'• ' || nombre_concepto || ': ' || app_private.whatsapp_monto(saldo_pendiente, p_moneda)
			|| case
				when vencida then ' · ⚠️ venció ' || app_private.whatsapp_fecha(fecha_objetivo)
				when fecha_objetivo is not null then ' · aportar hasta ' || app_private.whatsapp_fecha(fecha_objetivo)
				else ''
			end
			order by vencida desc, fecha_objetivo asc nulls last, nombre_concepto
		) filter (where estado <> 'POR_VALIDAR'),
		array_agg(
			nombre_concepto || ' ' || app_private.whatsapp_monto(saldo_pendiente, p_moneda)
			order by vencida desc, fecha_objetivo asc nulls last, nombre_concepto
		) filter (where estado = 'POR_VALIDAR')
	into v_debe, v_lineas, v_validacion
	from pendientes;

	select coalesce(sum(q.saldo_pendiente), 0)
	into v_anteriores
	from public.cuotas q
	inner join public.recibos r on r.id = q.recibo_id
	inner join public.periodos p on p.id = r.periodo_id
	where q.familia_id = p_familia_id
		and q.usuario_id = p_usuario_id
		and p.id <> v_periodo.id
		and p.estado = 'ABIERTO'
		and (p.anio, p.mes) < (v_periodo.anio, v_periodo.mes)
		and r.estado <> 'ANULADO'
		and q.estado <> 'ANULADA'
		and q.saldo_pendiente > 0;

	if v_debe = 0 then
		v_partes := array[p_nombre || ', estás al día este mes. ✅'];
	else
		v_partes := array[
			p_nombre || ', debes ' || app_private.whatsapp_monto(v_debe, p_moneda) || ' este mes:',
			app_private.whatsapp_lista(v_lineas),
			case when v_validacion is not null then 'En validación: ' || array_to_string(v_validacion, ', ') end
		];
	end if;

	if v_anteriores > 0 then
		v_partes := v_partes || ('Además tienes ' || app_private.whatsapp_monto(v_anteriores, p_moneda) || ' de meses anteriores.');
	end if;

	if v_debe > 0 or v_anteriores > 0 then
		v_partes := v_partes || 'Paga desde {APP_URL}/pagar'::text;
	end if;

	return array_to_string(v_partes, E'\n');
end;
$$;

create or replace function app_private.whatsapp_cmd_vence(p_familia_id uuid, p_moneda char(3))
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
	v_periodo_id uuid := app_private.whatsapp_periodo_actual(p_familia_id);
	v_hoy date := app_private.whatsapp_ahora_local(p_familia_id)::date;
	v_vencidos text[];
	v_proximos text[];
begin
	with base as (
		select
			r.id,
			r.nombre_concepto,
			r.estado,
			r.monto_total,
			r.fecha_vencimiento,
			coalesce(r.fecha_limite_aporte, r.fecha_vencimiento) as fecha_objetivo,
			(
				select coalesce(sum(q.saldo_pendiente), 0)
				from public.cuotas q
				where q.recibo_id = r.id
					and q.estado <> 'ANULADA'
			) as falta
		from public.recibos r
		inner join public.periodos p on p.id = r.periodo_id
		where r.familia_id = p_familia_id
			and (p.id = v_periodo_id or p.estado = 'ABIERTO')
			and r.estado not in ('ANULADO', 'PAGADO')
	)
	select
		array_agg(
			'• ' || nombre_concepto || ': '
			|| case
				when monto_total is null then 'esperando monto (venció ' || app_private.whatsapp_fecha(fecha_vencimiento) || ')'
				when falta > 0 then 'falta ' || app_private.whatsapp_monto(falta, p_moneda) || ' (venció ' || app_private.whatsapp_fecha(fecha_objetivo) || ')'
				else 'recaudado, falta pagar a la empresa (venció ' || app_private.whatsapp_fecha(fecha_vencimiento) || ')'
			end
			order by fecha_objetivo, nombre_concepto
		) filter (where
			(monto_total is null and fecha_vencimiento < v_hoy)
			or (monto_total is not null and falta > 0 and fecha_objetivo < v_hoy)
			or (monto_total is not null and falta = 0 and estado = 'VENCIDO')
		),
		array_agg(
			'• ' || nombre_concepto || ': '
			|| case
				when monto_total is null then 'esperando monto (vence ' || app_private.whatsapp_fecha(fecha_vencimiento) || ')'
				when falta > 0 then 'falta ' || app_private.whatsapp_monto(falta, p_moneda) || ' (' || app_private.whatsapp_fecha(fecha_objetivo) || ')'
				else 'recaudado, falta pagar a la empresa (vence ' || app_private.whatsapp_fecha(fecha_vencimiento) || ')'
			end
			order by coalesce(case when monto_total is not null and falta > 0 then fecha_objetivo end, fecha_vencimiento), nombre_concepto
		) filter (where
			(monto_total is null and fecha_vencimiento between v_hoy and v_hoy + 7)
			or (monto_total is not null and falta > 0 and fecha_objetivo between v_hoy and v_hoy + 7)
			or (monto_total is not null and falta = 0 and estado <> 'VENCIDO' and fecha_vencimiento between v_hoy and v_hoy + 7)
		)
	into v_vencidos, v_proximos
	from base;

	if v_vencidos is null and v_proximos is null then
		if v_periodo_id is null then
			return 'Aún no se generaron los recibos de este mes.';
		end if;

		return 'No hay vencimientos en los próximos 7 días. ✅';
	end if;

	return array_to_string(array[
		case when v_vencidos is not null then '⚠️ Vencidos:' end,
		app_private.whatsapp_lista(v_vencidos),
		case when v_proximos is not null then '⏰ Próximos 7 días:' end,
		app_private.whatsapp_lista(v_proximos)
	], E'\n');
end;
$$;

create or replace function app_private.whatsapp_cmd_recibos(p_familia_id uuid, p_moneda char(3))
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
	v_periodo public.periodos%rowtype;
	v_lineas text[];
begin
	select *
	into v_periodo
	from public.periodos
	where id = app_private.whatsapp_periodo_actual(p_familia_id);

	if v_periodo.id is null then
		return 'Aún no se generaron los recibos de este mes.';
	end if;

	select array_agg(
		'• ' || x.nombre_concepto || ': '
		|| case
			when x.monto_total is null then 'esperando monto'
				|| case when x.fecha_vencimiento is not null then ' · vence ' || app_private.whatsapp_fecha(x.fecha_vencimiento) else '' end
			else app_private.whatsapp_monto(x.monto_total, p_moneda)
				|| ' · ' || app_private.whatsapp_estado_recaudacion(x.estado_recaudacion, x.pagado, x.monto_total)
				|| case
					when x.estado = 'PAGADO' then ' · pagado a la empresa'
					when x.estado = 'VENCIDO' then ' · ⚠️ vencido'
					when x.estado = 'REQUIERE_REVISION' then ' · en revisión'
					when x.fecha_objetivo is not null then ' · ' || app_private.whatsapp_fecha(x.fecha_objetivo)
					else ''
				end
		end
		order by x.fecha_limite_aporte asc nulls last, x.created_at
	)
	into v_lineas
	from (
		select
			r.*,
			coalesce(r.fecha_limite_aporte, r.fecha_vencimiento) as fecha_objetivo,
			(
				select coalesce(sum(q.monto_pagado), 0)
				from public.cuotas q
				where q.recibo_id = r.id
					and q.estado <> 'ANULADA'
			) as pagado
		from public.recibos r
		where r.periodo_id = v_periodo.id
			and r.estado <> 'ANULADO'
	) x;

	if v_lineas is null then
		return 'Aún no hay recibos en ' || app_private.whatsapp_mes(v_periodo.anio, v_periodo.mes) || '.';
	end if;

	return '🗓️ *' || app_private.whatsapp_mes(v_periodo.anio, v_periodo.mes) || '*' || E'\n' || app_private.whatsapp_lista(v_lineas);
end;
$$;

create or replace function app_private.whatsapp_cmd_recibo(
	p_familia_id uuid,
	p_moneda char(3),
	p_argumento text
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
	v_periodo_id uuid := app_private.whatsapp_periodo_actual(p_familia_id);
	v_busqueda text := app_private.whatsapp_normalizar(left(coalesce(p_argumento, ''), 60));
	v_patron text;
	v_ids uuid[];
	v_nombres text;
	v_recibo public.recibos%rowtype;
	v_pagado numeric;
	v_fechas text[];
	v_estado text;
	v_cuotas text[];
begin
	if v_periodo_id is null then
		return 'Aún no se generaron los recibos de este mes.';
	end if;

	if v_busqueda = '' then
		return 'Escribe el nombre del recibo. Por ejemplo: /recibo luz';
	end if;

	select array_agg(r.id order by r.nombre_concepto, r.created_at)
	into v_ids
	from public.recibos r
	where r.periodo_id = v_periodo_id
		and r.estado <> 'ANULADO'
		and app_private.whatsapp_normalizar(r.nombre_concepto) = v_busqueda;

	if v_ids is null then
		v_patron := '%' || replace(replace(replace(v_busqueda, '\', '\\'), '%', '\%'), '_', '\_') || '%';

		select array_agg(r.id order by r.nombre_concepto, r.created_at)
		into v_ids
		from public.recibos r
		where r.periodo_id = v_periodo_id
			and r.estado <> 'ANULADO'
			and (
				app_private.whatsapp_normalizar(r.nombre_concepto) like v_patron
				or app_private.whatsapp_normalizar(r.tipo_servicio::text) like v_patron
				or app_private.whatsapp_normalizar(r.proveedor_nombre) like v_patron
			);
	end if;

	if v_ids is null then
		select string_agg(r.nombre_concepto, ', ' order by r.fecha_limite_aporte asc nulls last, r.created_at)
		into v_nombres
		from public.recibos r
		where r.periodo_id = v_periodo_id
			and r.estado <> 'ANULADO';

		return 'No encontré "' || trim(left(coalesce(p_argumento, ''), 60)) || '" este mes.'
			|| case when v_nombres is not null then ' Recibos: ' || v_nombres || '.' else '' end;
	end if;

	if cardinality(v_ids) > 1 then
		select string_agg(r.nombre_concepto, ', ' order by r.nombre_concepto, r.created_at)
		into v_nombres
		from public.recibos r
		where r.id = any(v_ids);

		return 'Encontré varios: ' || v_nombres || '. Escribe /recibo con un nombre más exacto.';
	end if;

	select *
	into v_recibo
	from public.recibos
	where id = v_ids[1];

	select coalesce(sum(q.monto_pagado), 0)
	into v_pagado
	from public.cuotas q
	where q.recibo_id = v_recibo.id
		and q.estado <> 'ANULADA';

	v_fechas := array_remove(array[
		case when v_recibo.fecha_limite_aporte is not null then 'Aportar hasta ' || app_private.whatsapp_fecha(v_recibo.fecha_limite_aporte) end,
		case
			when v_recibo.fecha_vencimiento is null then null
			when v_recibo.fecha_limite_aporte is null then 'Vence ' || app_private.whatsapp_fecha(v_recibo.fecha_vencimiento)
			else 'vence ' || app_private.whatsapp_fecha(v_recibo.fecha_vencimiento)
		end
	], null);

	if v_recibo.monto_total is null then
		return array_to_string(array[
			app_private.whatsapp_emoji_servicio(v_recibo.tipo_servicio) || ' *' || v_recibo.nombre_concepto || '* — esperando monto',
			case when cardinality(v_fechas) > 0 then array_to_string(v_fechas, ' · ') end,
			'Aún no llega el monto. Les aviso cuando se registre.'
		], E'\n');
	end if;

	v_estado := 'Estado: ' || app_private.whatsapp_estado_recaudacion(v_recibo.estado_recaudacion, v_pagado, v_recibo.monto_total)
		|| case
			when v_recibo.estado = 'PAGADO' then ' · pagado a la empresa'
			when v_recibo.estado = 'VENCIDO' then ' · ⚠️ vencido'
			when v_recibo.estado = 'REQUIERE_REVISION' then ' · en revisión'
			else ''
		end;

	select array_agg(
		'• ' || q.nombre_miembro || ' ' || app_private.whatsapp_monto(q.monto_asignado, p_moneda) || ' · '
		|| case
			when q.estado = 'PAGADA' then 'pagado'
			when q.estado = 'POR_VALIDAR' then 'en validación'
			when q.estado = 'PARCIAL' then 'falta ' || app_private.whatsapp_monto(q.saldo_pendiente, p_moneda)
			else 'pendiente'
		end
		order by q.created_at, q.nombre_miembro
	)
	into v_cuotas
	from public.cuotas q
	where q.recibo_id = v_recibo.id
		and q.estado <> 'ANULADA';

	return array_to_string(array[
		app_private.whatsapp_emoji_servicio(v_recibo.tipo_servicio) || ' *' || v_recibo.nombre_concepto || '* — '
			|| app_private.whatsapp_monto(v_recibo.monto_total, p_moneda),
		case when cardinality(v_fechas) > 0 then array_to_string(v_fechas, ' · ') end,
		v_estado,
		app_private.whatsapp_lista(v_cuotas)
	], E'\n');
end;
$$;

create or replace function app_private.whatsapp_cmd_pendientes(p_familia_id uuid, p_moneda char(3))
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
	v_periodo public.periodos%rowtype;
	v_lineas text[];
begin
	select *
	into v_periodo
	from public.periodos
	where id = app_private.whatsapp_periodo_actual(p_familia_id);

	if v_periodo.id is null then
		return 'Aún no se generaron los recibos de este mes.';
	end if;

	with pendientes as (
		select
			q.miembro_id,
			q.nombre_miembro,
			q.estado,
			q.saldo_pendiente,
			r.nombre_concepto,
			coalesce(r.fecha_limite_aporte, r.fecha_vencimiento) as fecha_objetivo
		from public.cuotas q
		inner join public.recibos r on r.id = q.recibo_id
		where r.periodo_id = v_periodo.id
			and r.estado <> 'ANULADO'
			and q.estado <> 'ANULADA'
			and q.saldo_pendiente > 0
	),
	por_miembro as (
		select
			miembro_id,
			min(nombre_miembro) as nombre,
			sum(saldo_pendiente) as total,
			string_agg(
				nombre_concepto || ' ' || app_private.whatsapp_monto(saldo_pendiente, p_moneda)
				|| case when estado = 'POR_VALIDAR' then ' en validación' else '' end,
				', '
				order by fecha_objetivo asc nulls last, nombre_concepto
			) as detalle
		from pendientes
		group by miembro_id
	)
	select array_agg(
		'• ' || nombre || ': ' || app_private.whatsapp_monto(total, p_moneda) || ' (' || detalle || ')'
		order by total desc, nombre
	)
	into v_lineas
	from por_miembro;

	if v_lineas is null then
		return 'Nadie tiene saldo pendiente este mes. 🎉';
	end if;

	return '📌 *Falta aportar — ' || app_private.whatsapp_mes(v_periodo.anio, v_periodo.mes) || '*' || E'\n' || app_private.whatsapp_lista(v_lineas);
end;
$$;

create or replace function app_private.whatsapp_cmd_pagar(
	p_familia_id uuid,
	p_usuario_id uuid,
	p_moneda char(3)
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
	select array_to_string(array[
		'Para pagar entra a {APP_URL}/pagar',
		'Ahí ves a quién pagar y subes tu comprobante.',
		case
			when p_usuario_id is not null then 'Tu saldo este mes: ' || app_private.whatsapp_monto(
				app_private.whatsapp_deuda_usuario(p_familia_id, p_usuario_id, app_private.whatsapp_periodo_actual(p_familia_id)),
				p_moneda
			)
		end
	], E'\n');
$$;

create or replace function app_private.whatsapp_cmd_porvalidar(
	p_familia_id uuid,
	p_miembro_id uuid,
	p_es_admin boolean,
	p_moneda char(3)
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
	v_zona text;
	v_hoy date;
	v_lineas text[];
begin
	select zona_horaria
	into v_zona
	from public.familias
	where id = p_familia_id;

	v_hoy := timezone(coalesce(v_zona, 'America/Lima'), now())::date;

	with pendientes as (
		select
			pf.pagador_nombre_snapshot as nombre,
			pf.monto_total as monto,
			coalesce(pf.enviado_at, pf.updated_at, pf.created_at) as fecha
		from public.pagos_familiares pf
		where pf.familia_id = p_familia_id
			and pf.estado = 'POR_VALIDAR'
			and (p_es_admin or pf.responsable_receptor_miembro_id = p_miembro_id)
		union all
		select
			coalesce(nullif(trim(per.nombre), ''), 'Integrante'),
			a.monto,
			a.created_at
		from public.aportes a
		inner join public.miembros_familia m on m.id = a.pagador_miembro_id
		left join public.perfiles per on per.id = m.usuario_id
		where a.familia_id = p_familia_id
			and a.estado = 'POR_VALIDAR'
			and a.pago_familiar_id is null
			and (p_es_admin or a.receptor_miembro_id = p_miembro_id)
	)
	select array_agg(
		'• ' || nombre || ' ' || app_private.whatsapp_monto(monto, p_moneda) || ' · '
		|| app_private.whatsapp_hace(v_hoy - timezone(coalesce(v_zona, 'America/Lima'), fecha)::date)
		order by fecha
	)
	into v_lineas
	from pendientes;

	if v_lineas is null then
		return 'No hay pagos por validar. ✅';
	end if;

	return '📥 *Pagos por validar*' || E'\n' || app_private.whatsapp_lista(v_lineas) || E'\n' || 'Valídalos en {APP_URL}/pagos';
end;
$$;

create or replace function app_private.whatsapp_cmd_avisos(
	p_familia_id uuid,
	p_usuario_id uuid,
	p_argumento text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_accion text := split_part(app_private.whatsapp_normalizar(p_argumento), ' ', 1);
	v_config public.whatsapp_configuracion%rowtype;
	v_dias smallint[];
	v_recordatorios text[] := '{}';
	v_dias_semana constant text[] := array['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'];
begin
	perform app_private.whatsapp_asegurar_configuracion(p_familia_id);

	if v_accion = 'pausar' then
		update public.whatsapp_configuracion
		set avisos_activos = false,
			updated_at = now(),
			updated_by = p_usuario_id
		where familia_id = p_familia_id;

		update public.avisos_whatsapp
		set estado = 'EXPIRADO',
			bloqueado_hasta = null
		where familia_id = p_familia_id
			and estado = 'PENDIENTE';

		return 'Avisos automáticos pausados. Reanúdalos con /avisos reanudar.';
	end if;

	if v_accion = 'reanudar' then
		update public.whatsapp_configuracion
		set avisos_activos = true,
			updated_at = now(),
			updated_by = p_usuario_id
		where familia_id = p_familia_id;

		return 'Avisos automáticos activados.';
	end if;

	if v_accion not in ('', 'estado') then
		return 'Usa /avisos estado, /avisos pausar o /avisos reanudar.';
	end if;

	select *
	into v_config
	from public.whatsapp_configuracion
	where familia_id = p_familia_id;

	select array_agg(dia order by dia desc)
	into v_dias
	from unnest(v_config.dias_aviso_previo) dia;

	if v_dias is not null then
		v_recordatorios := v_recordatorios || (
			app_private.whatsapp_unir(array(select d::text from unnest(v_dias) d))
			|| case when cardinality(v_dias) = 1 and v_dias[1] = 1 then ' día antes' else ' días antes' end
		);
	end if;

	if v_config.avisar_vence_hoy then
		v_recordatorios := v_recordatorios || 'el día límite'::text;
	end if;

	v_recordatorios := v_recordatorios || (
		case
			when v_config.frecuencia_vencidos_dias = 0 then 'vencidos una vez'
			when v_config.frecuencia_vencidos_dias = 1 then 'vencidos cada día'
			else 'vencidos cada ' || v_config.frecuencia_vencidos_dias::text || ' días'
		end
	);

	return array_to_string(array[
		'🔔 Avisos: ' || case when v_config.avisos_activos then 'activos' else 'pausados' end,
		'Recordatorios: ' || app_private.whatsapp_unir(v_recordatorios),
		'Horario: ' || to_char(v_config.hora_inicio_envio, 'HH24:MI') || ' a ' || to_char(v_config.hora_fin_envio, 'HH24:MI'),
		'Resumen: ' || case
			when v_config.resumen_semanal then v_dias_semana[v_config.dia_resumen + 1] || ' ' || to_char(v_config.hora_resumen, 'HH24:MI')
			else 'desactivado'
		end
	], E'\n');
end;
$$;

create or replace function app_private.whatsapp_procesar_comando_impl(
	p_grupo_id text,
	p_remitente_ids text[],
	p_comando text,
	p_argumento text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_comando text := lower(trim(coalesce(p_comando, '')));
	v_argumento text := left(trim(coalesce(p_argumento, '')), 60);
	v_ids text[] := app_private.whatsapp_remitentes(p_remitente_ids);
	v_ctx record;
	v_es_admin boolean;
	v_lenguaje_natural boolean;
begin
	if v_comando = 'vincular-grupo' then
		return app_private.whatsapp_respuesta(
			app_private.whatsapp_cmd_vincular(p_grupo_id, v_ids, v_argumento, 'GRUPO', null)
		);
	end if;

	select *
	into v_ctx
	from app_private.whatsapp_contexto(p_grupo_id, v_ids);

	if v_ctx.familia_id is null then
		return app_private.whatsapp_respuesta(
			'Este grupo aún no está vinculado a una familia. Un administrador debe escribir /vincular-grupo CÓDIGO.'
		) || jsonb_build_object('grupoVinculado', false);
	end if;

	if v_comando in ('desvincular', 'deuda', 'porvalidar', 'avisos') and v_ctx.miembro_id is null then
		return app_private.whatsapp_respuesta(
			'Aún no vinculas tu WhatsApp. En FamiliaHub ve a Perfil > WhatsApp, genera tu código y escribe aquí /vincular CÓDIGO.'
		);
	end if;

	v_es_admin := v_ctx.rol is not distinct from 'ADMINISTRADOR';

	if v_comando = 'avisos' and not v_es_admin then
		return app_private.whatsapp_respuesta('Este comando es solo para administradores.');
	end if;

	if v_comando = 'porvalidar'
		and not v_es_admin
		and not app_private.whatsapp_es_responsable(v_ctx.familia_id, v_ctx.miembro_id)
	then
		return app_private.whatsapp_respuesta('Este comando es solo para administradores.');
	end if;

	case v_comando
		when 'vincular' then
			return app_private.whatsapp_respuesta(
				app_private.whatsapp_cmd_vincular(p_grupo_id, v_ids, v_argumento, 'INTEGRANTE', v_ctx.familia_id)
			);
		when 'desvincular' then
			return app_private.whatsapp_respuesta(app_private.whatsapp_cmd_desvincular(v_ctx.miembro_id, v_ctx.nombre));
		when 'ayuda' then
			return app_private.whatsapp_respuesta(app_private.whatsapp_cmd_ayuda());
		when 'yo' then
			return app_private.whatsapp_respuesta(app_private.whatsapp_cmd_yo(v_ctx.nombre, v_ctx.rol, v_ctx.familia_nombre));
		when 'deuda' then
			return app_private.whatsapp_respuesta(
				app_private.whatsapp_cmd_deuda(v_ctx.familia_id, v_ctx.usuario_id, v_ctx.nombre, v_ctx.moneda)
			);
		when 'vence' then
			return app_private.whatsapp_respuesta(app_private.whatsapp_cmd_vence(v_ctx.familia_id, v_ctx.moneda));
		when 'recibos' then
			return app_private.whatsapp_respuesta(app_private.whatsapp_cmd_recibos(v_ctx.familia_id, v_ctx.moneda));
		when 'recibo' then
			return app_private.whatsapp_respuesta(app_private.whatsapp_cmd_recibo(v_ctx.familia_id, v_ctx.moneda, v_argumento));
		when 'pendientes' then
			return app_private.whatsapp_respuesta(app_private.whatsapp_cmd_pendientes(v_ctx.familia_id, v_ctx.moneda));
		when 'resumen' then
			return app_private.whatsapp_respuesta(
				coalesce(app_private.whatsapp_texto_resumen(v_ctx.familia_id), 'Aún no se generaron los recibos de este mes.')
			);
		when 'pagar' then
			return app_private.whatsapp_respuesta(app_private.whatsapp_cmd_pagar(v_ctx.familia_id, v_ctx.usuario_id, v_ctx.moneda));
		when 'porvalidar' then
			return app_private.whatsapp_respuesta(
				app_private.whatsapp_cmd_porvalidar(v_ctx.familia_id, v_ctx.miembro_id, v_es_admin, v_ctx.moneda)
			);
		when 'avisos' then
			return app_private.whatsapp_respuesta(app_private.whatsapp_cmd_avisos(v_ctx.familia_id, v_ctx.usuario_id, v_argumento));
		when 'contexto' then
			select lenguaje_natural
			into v_lenguaje_natural
			from public.whatsapp_configuracion
			where familia_id = v_ctx.familia_id;

			return jsonb_build_object(
				'familia', v_ctx.familia_nombre,
				'nombre', v_ctx.nombre,
				'vinculado', v_ctx.miembro_id is not null,
				'lenguajeNatural', coalesce(v_lenguaje_natural, false)
			);
		when 'mencion' then
			return app_private.whatsapp_respuesta('Escribe /ayuda para ver lo que puedo hacer.');
		else
			return app_private.whatsapp_respuesta('No conozco ese comando. Escribe /ayuda.');
	end case;
end;
$$;

revoke all on function app_private.whatsapp_emoji_servicio(public.tipo_servicio) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_unir(text[]) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_estado_recaudacion(public.estado_recaudacion, numeric, numeric) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_hace(integer) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_deuda_usuario(uuid, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_es_responsable(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_texto_resumen(uuid) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_cmd_deuda(uuid, uuid, text, char) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_cmd_vence(uuid, char) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_cmd_recibos(uuid, char) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_cmd_recibo(uuid, char, text) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_cmd_pendientes(uuid, char) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_cmd_pagar(uuid, uuid, char) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_cmd_porvalidar(uuid, uuid, boolean, char) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_cmd_avisos(uuid, uuid, text) from public, anon, authenticated, service_role;

revoke all on function app_private.whatsapp_procesar_comando_impl(text, text[], text, text) from public, anon, authenticated;
grant execute on function app_private.whatsapp_procesar_comando_impl(text, text[], text, text) to service_role;
