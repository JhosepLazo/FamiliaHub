alter table public.recibos
	add column distribucion_ajustada boolean not null default false,
	add column distribucion_ajuste_motivo text;

create or replace function app_private.ajustar_cuotas_recibo_impl(
	p_recibo_id uuid,
	p_cuotas jsonb,
	p_motivo text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_recibo public.recibos%rowtype;
	v_total integer;
	v_distintos integer;
	v_suma numeric;
	v_anterior jsonb;
begin
	select *
	into v_recibo
	from public.recibos
	where id = p_recibo_id
	for update;

	if v_recibo.id is null then
		raise exception 'Recibo no encontrado.';
	end if;

	if not app_private.es_admin(v_recibo.familia_id, v_usuario_id) then
		raise exception 'Solo un administrador puede ajustar la distribución del periodo.';
	end if;

	if v_recibo.monto_total is null or v_recibo.estado in ('PAGADO', 'ANULADO') then
		raise exception 'El recibo no admite un ajuste de distribución en su estado actual.';
	end if;

	if nullif(trim(p_motivo), '') is null then
		raise exception 'Indica el motivo del ajuste de distribución.';
	end if;

	if p_cuotas is null or jsonb_typeof(p_cuotas) <> 'array' or jsonb_array_length(p_cuotas) = 0 then
		raise exception 'Debes asignar el total a al menos un integrante.';
	end if;

	if exists (
		select 1
		from public.aportes
		where recibo_id = p_recibo_id
			and estado in ('POR_VALIDAR', 'CONFIRMADO')
	) then
		raise exception 'No puedes cambiar la distribución porque el recibo ya tiene aportes activos.';
	end if;

	if exists (
		select 1
		from public.pagos_proveedor
		where recibo_id = p_recibo_id
			and estado = 'CONFIRMADO'
	) then
		raise exception 'No puedes cambiar la distribución después de pagar al proveedor.';
	end if;

	select count(*), count(distinct elemento ->> 'miembro_id')
	into v_total, v_distintos
	from jsonb_array_elements(p_cuotas) as elemento;

	if v_total <> v_distintos then
		raise exception 'Un integrante no puede aparecer más de una vez.';
	end if;

	if exists (
		select 1
		from jsonb_array_elements(p_cuotas) as elemento
		left join public.miembros_familia m
			on m.id = (elemento ->> 'miembro_id')::uuid
		where m.id is null
			or m.familia_id <> v_recibo.familia_id
	) then
		raise exception 'Todos los integrantes deben pertenecer a la familia.';
	end if;

	if exists (
		select 1
		from jsonb_array_elements(p_cuotas) as elemento
		where nullif(coalesce(elemento ->> 'monto', ''), '') is null
			or (elemento ->> 'monto')::numeric <= 0
			or round((elemento ->> 'monto')::numeric, 2) <> (elemento ->> 'monto')::numeric
	) then
		raise exception 'Cada cuota debe ser mayor a cero y tener máximo dos decimales.';
	end if;

	select coalesce(sum((elemento ->> 'monto')::numeric), 0)
	into v_suma
	from jsonb_array_elements(p_cuotas) as elemento;

	if round(v_suma, 2) <> round(v_recibo.monto_total, 2) then
		raise exception 'La suma de las cuotas debe coincidir exactamente con el total del recibo.';
	end if;

	select coalesce(
		jsonb_agg(
			jsonb_build_object(
				'miembro_id', miembro_id,
				'nombre', nombre_miembro,
				'monto', monto_asignado
			)
			order by created_at, id
		),
		'[]'::jsonb
	)
	into v_anterior
	from public.cuotas
	where recibo_id = p_recibo_id
		and estado <> 'ANULADA';

	delete from public.cuotas
	where recibo_id = p_recibo_id;

	insert into public.cuotas (
		familia_id,
		recibo_id,
		miembro_id,
		usuario_id,
		nombre_miembro,
		monto_asignado,
		monto_pagado,
		estado,
		destino,
		receptor_miembro_id
	)
	select
		v_recibo.familia_id,
		p_recibo_id,
		m.id,
		m.usuario_id,
		coalesce(per.nombre, 'Integrante'),
		(elemento ->> 'monto')::numeric(12,2),
		0,
		'PENDIENTE',
		'FONDO_FAMILIAR',
		null
	from jsonb_array_elements(p_cuotas) as elemento
	inner join public.miembros_familia m
		on m.id = (elemento ->> 'miembro_id')::uuid
	left join public.perfiles per
		on per.id = m.usuario_id
	where m.familia_id = v_recibo.familia_id;

	update public.recibos
	set distribucion_ajustada = true,
		distribucion_ajuste_motivo = trim(p_motivo),
		estado_recaudacion = 'PENDIENTE',
		updated_at = now()
	where id = p_recibo_id;

	perform app_private.registrar_evento_financiero(
		v_recibo.familia_id,
		'RECIBO',
		p_recibo_id,
		'DISTRIBUCION_AJUSTADA',
		jsonb_build_object(
			'motivo', trim(p_motivo),
			'anterior', v_anterior,
			'nueva', p_cuotas
		),
		v_usuario_id
	);
end;
$$;

revoke all on function app_private.ajustar_cuotas_recibo_impl(uuid, jsonb, text) from public, anon;
grant execute on function app_private.ajustar_cuotas_recibo_impl(uuid, jsonb, text) to authenticated;

create or replace function public.ajustar_cuotas_recibo(
	p_recibo_id uuid,
	p_cuotas jsonb,
	p_motivo text
)
returns void
language sql
security invoker
set search_path = ''
as $$
	select app_private.ajustar_cuotas_recibo_impl(p_recibo_id, p_cuotas, p_motivo);
$$;

revoke all on function public.ajustar_cuotas_recibo(uuid, jsonb, text) from public, anon;
grant execute on function public.ajustar_cuotas_recibo(uuid, jsonb, text) to authenticated;
