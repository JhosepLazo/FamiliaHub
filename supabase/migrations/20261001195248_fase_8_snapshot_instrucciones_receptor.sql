alter table public.pagos_familiares
	add column receptor_instrucciones_snapshot text;

create or replace function app_private.crear_pago_familiar_impl(
	p_asignaciones jsonb,
	p_metodo public.metodo_pago_familiar
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_familia_id uuid;
	v_pagador_miembro_id uuid;
	v_pagador_nombre text;
	v_destino public.destino_aporte;
	v_receptor_miembro_id uuid;
	v_responsable_miembro_id uuid;
	v_receptor_nombre text;
	v_titular text;
	v_referencia text;
	v_instrucciones text;
	v_qr_path text;
	v_qr_bucket text;
	v_monto_total numeric;
	v_pago_id uuid;
	v_total integer;
	v_distintos integer;
	v_grupos integer;
	v_asig record;
begin
	if v_usuario_id is null then
		raise exception 'Sesión no válida.';
	end if;

	if p_asignaciones is null or jsonb_typeof(p_asignaciones) <> 'array' or jsonb_array_length(p_asignaciones) = 0 then
		raise exception 'Selecciona al menos una cuota.';
	end if;

	select count(*), count(distinct elemento ->> 'cuota_id')
	into v_total, v_distintos
	from jsonb_array_elements(p_asignaciones) elemento;

	if v_total <> v_distintos then
		raise exception 'Una cuota no puede aparecer más de una vez en el mismo pago.';
	end if;

	if exists (
		select 1
		from jsonb_array_elements(p_asignaciones) elemento
		where nullif(coalesce(elemento ->> 'monto', ''), '') is null
			or (elemento ->> 'monto')::numeric <= 0
			or round((elemento ->> 'monto')::numeric, 2) <> (elemento ->> 'monto')::numeric
	) then
		raise exception 'Cada importe debe ser mayor a cero y tener máximo dos decimales.';
	end if;

	with elegibles as (
		select q.*
		from jsonb_array_elements(p_asignaciones) elemento
		inner join public.cuotas q on q.id = (elemento ->> 'cuota_id')::uuid
		inner join public.recibos r on r.id = q.recibo_id
		inner join public.periodos pe on pe.id = r.periodo_id
		where q.usuario_id = v_usuario_id
			and q.estado <> 'ANULADA'
			and r.estado <> 'ANULADO'
			and pe.estado = 'ABIERTO'
	)
	select
		count(distinct familia_id),
		count(distinct (destino::text || ':' || coalesce(receptor_miembro_id::text, 'FONDO'))),
		(array_agg(familia_id order by id))[1],
		(array_agg(miembro_id order by id))[1],
		(array_agg(destino order by id))[1],
		(array_agg(receptor_miembro_id order by id nulls last))[1]
	into
		v_total,
		v_grupos,
		v_familia_id,
		v_pagador_miembro_id,
		v_destino,
		v_receptor_miembro_id
	from elegibles;

	if v_total <> 1 then
		raise exception 'Todas las cuotas deben pertenecer a una sola familia.';
	end if;

	if v_grupos <> 1 then
		raise exception 'Un pago no puede mezclar receptores diferentes.';
	end if;

	if (
		select count(*)
		from jsonb_array_elements(p_asignaciones)
	) <> (
		select count(*)
		from jsonb_array_elements(p_asignaciones) elemento
		inner join public.cuotas q on q.id = (elemento ->> 'cuota_id')::uuid
		inner join public.recibos r on r.id = q.recibo_id
		inner join public.periodos pe on pe.id = r.periodo_id
		where q.usuario_id = v_usuario_id
			and q.estado <> 'ANULADA'
			and r.estado <> 'ANULADO'
			and pe.estado = 'ABIERTO'
	) then
		raise exception 'Alguna cuota no está disponible para este pago.';
	end if;

	for v_asig in
		select
			q.id as cuota_id,
			(elemento ->> 'monto')::numeric as monto
		from jsonb_array_elements(p_asignaciones) elemento
		inner join public.cuotas q on q.id = (elemento ->> 'cuota_id')::uuid
		order by q.id
	loop
		perform 1 from public.cuotas where id = v_asig.cuota_id for update;

		if v_asig.monto > app_private.saldo_disponible_cuota(v_asig.cuota_id, null) then
			raise exception 'Una de las cuotas tiene un saldo menor al importe solicitado.';
		end if;
	end loop;

	select coalesce(per.nombre, 'Integrante')
	into v_pagador_nombre
	from public.miembros_familia m
	left join public.perfiles per on per.id = m.usuario_id
	where m.id = v_pagador_miembro_id;

	if v_destino = 'FONDO_FAMILIAR' then
		select
			c.responsable_miembro_id,
			'Fondo familiar · ' || f.nombre,
			c.titular,
			c.referencia,
			c.instrucciones,
			c.qr_storage_path
		into
			v_responsable_miembro_id,
			v_receptor_nombre,
			v_titular,
			v_referencia,
			v_instrucciones,
			v_qr_path
		from public.configuracion_pago_familiar c
		inner join public.familias f on f.id = c.familia_id
		where c.familia_id = v_familia_id
			and c.metodo = p_metodo
			and c.activo = true;

		v_qr_bucket := case when v_qr_path is null then null else 'familia-configuracion' end;
	else
		select
			c.miembro_id,
			coalesce(per.nombre, 'Integrante'),
			c.titular,
			c.referencia,
			c.instrucciones,
			c.qr_storage_path
		into
			v_responsable_miembro_id,
			v_receptor_nombre,
			v_titular,
			v_referencia,
			v_instrucciones,
			v_qr_path
		from public.configuracion_cobro_miembro c
		inner join public.miembros_familia m on m.id = c.miembro_id
		left join public.perfiles per on per.id = m.usuario_id
		where c.miembro_id = v_receptor_miembro_id
			and c.metodo = p_metodo
			and c.activo = true
			and m.estado = 'ACTIVO';

		v_qr_bucket := case when v_qr_path is null then null else 'familia-cobros' end;
	end if;

	if v_titular is null or v_responsable_miembro_id is null then
		raise exception 'El receptor no tiene configurado este método de cobro.';
	end if;

	select sum((elemento ->> 'monto')::numeric)
	into v_monto_total
	from jsonb_array_elements(p_asignaciones) elemento;

	insert into public.pagos_familiares (
		familia_id,
		pagador_miembro_id,
		pagador_usuario_id,
		pagador_nombre_snapshot,
		destino,
		receptor_miembro_id,
		responsable_receptor_miembro_id,
		receptor_nombre_snapshot,
		metodo,
		receptor_titular_snapshot,
		receptor_referencia_snapshot,
		receptor_instrucciones_snapshot,
		receptor_qr_bucket,
		receptor_qr_storage_path,
		monto_total,
		creado_por
	)
	values (
		v_familia_id,
		v_pagador_miembro_id,
		v_usuario_id,
		v_pagador_nombre,
		v_destino,
		v_receptor_miembro_id,
		v_responsable_miembro_id,
		v_receptor_nombre,
		p_metodo,
		v_titular,
		v_referencia,
		v_instrucciones,
		v_qr_bucket,
		v_qr_path,
		v_monto_total,
		v_usuario_id
	)
	returning id into v_pago_id;

	insert into public.pago_asignaciones (
		pago_id,
		cuota_id,
		recibo_id,
		monto
	)
	select
		v_pago_id,
		q.id,
		q.recibo_id,
		(elemento ->> 'monto')::numeric(12,2)
	from jsonb_array_elements(p_asignaciones) elemento
	inner join public.cuotas q on q.id = (elemento ->> 'cuota_id')::uuid;

	perform app_private.registrar_evento_financiero(
		v_familia_id,
		'PAGO_FAMILIAR',
		v_pago_id,
		'PAGO_BORRADOR_CREADO',
		jsonb_build_object('monto_total', v_monto_total, 'metodo', p_metodo, 'destino', v_destino),
		v_usuario_id
	);

	return v_pago_id;
end;
$$;
