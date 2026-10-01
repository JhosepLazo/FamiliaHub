create or replace function app_private.actualizar_vencimiento_recibo_impl(
	p_recibo_id uuid,
	p_fecha_vencimiento date
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_recibo public.recibos%rowtype;
	v_fecha date := (timezone('America/Lima', now()))::date;
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
		raise exception 'Solo un administrador puede actualizar el vencimiento.';
	end if;

	if v_recibo.estado in ('ANULADO', 'PAGADO') then
		raise exception 'El recibo no admite cambios de vencimiento en su estado actual.';
	end if;

	if v_recibo.tipo_vencimiento = 'DIA_FIJO' then
		raise exception 'El vencimiento de este recibo se calcula desde el día fijo del servicio.';
	end if;

	if p_fecha_vencimiento is null then
		raise exception 'Indica la fecha de vencimiento.';
	end if;

	update public.recibos
	set fecha_vencimiento = p_fecha_vencimiento,
		fecha_limite_aporte = p_fecha_vencimiento - dias_anticipacion_aporte,
		estado = case
			when monto_total is null then estado
			when p_fecha_vencimiento < v_fecha then 'VENCIDO'::public.estado_recibo
			else 'PENDIENTE'::public.estado_recibo
		end,
		updated_at = now()
	where id = p_recibo_id;

	perform app_private.registrar_evento_financiero(
		v_recibo.familia_id,
		'RECIBO',
		p_recibo_id,
		'VENCIMIENTO_ACTUALIZADO',
		jsonb_build_object(
			'fecha_anterior', v_recibo.fecha_vencimiento,
			'fecha_nueva', p_fecha_vencimiento
		),
		v_usuario_id
	);
end;
$$;

create or replace function app_private.anular_recibo_impl(
	p_recibo_id uuid,
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
begin
	select *
	into v_recibo
	from public.recibos
	where id = p_recibo_id
	for update;

	if v_recibo.id is null or v_recibo.estado = 'ANULADO' then
		raise exception 'Recibo no disponible.';
	end if;

	if not app_private.es_admin(v_recibo.familia_id, v_usuario_id) then
		raise exception 'Solo un administrador puede anular un recibo.';
	end if;

	if nullif(trim(p_motivo), '') is null then
		raise exception 'Indica el motivo de la anulación.';
	end if;

	if exists (
		select 1
		from public.pagos_proveedor
		where recibo_id = p_recibo_id
			and estado = 'CONFIRMADO'
	) then
		raise exception 'Anula primero el pago confirmado al proveedor.';
	end if;

	if exists (
		select 1
		from public.aportes
		where recibo_id = p_recibo_id
			and estado in ('POR_VALIDAR', 'CONFIRMADO')
	) then
		raise exception 'Anula o resuelve primero los aportes activos del recibo.';
	end if;

	if exists (
		select 1
		from public.cuotas
		where recibo_id = p_recibo_id
			and monto_pagado > 0
	) then
		raise exception 'El recibo aún contiene importes pagados y no puede anularse.';
	end if;

	update public.cuotas
	set estado = 'ANULADA',
		updated_at = now()
	where recibo_id = p_recibo_id
		and estado <> 'ANULADA';

	update public.recibos
	set estado = 'ANULADO',
		estado_recaudacion = 'PENDIENTE',
		updated_at = now()
	where id = p_recibo_id;

	perform app_private.registrar_evento_financiero(
		v_recibo.familia_id,
		'RECIBO',
		p_recibo_id,
		'RECIBO_ANULADO',
		jsonb_build_object('motivo', trim(p_motivo)),
		v_usuario_id
	);

	perform app_private.intentar_cerrar_periodo(v_recibo.periodo_id);
end;
$$;

revoke all on function app_private.actualizar_vencimiento_recibo_impl(uuid, date) from public, anon;
revoke all on function app_private.anular_recibo_impl(uuid, text) from public, anon;
grant execute on function app_private.actualizar_vencimiento_recibo_impl(uuid, date) to authenticated;
grant execute on function app_private.anular_recibo_impl(uuid, text) to authenticated;

create or replace function public.actualizar_vencimiento_recibo(
	p_recibo_id uuid,
	p_fecha_vencimiento date
)
returns void
language sql
security invoker
set search_path = ''
as $$
	select app_private.actualizar_vencimiento_recibo_impl(p_recibo_id, p_fecha_vencimiento);
$$;

create or replace function public.anular_recibo(
	p_recibo_id uuid,
	p_motivo text
)
returns void
language sql
security invoker
set search_path = ''
as $$
	select app_private.anular_recibo_impl(p_recibo_id, p_motivo);
$$;

revoke all on function public.actualizar_vencimiento_recibo(uuid, date) from public, anon;
revoke all on function public.anular_recibo(uuid, text) from public, anon;
grant execute on function public.actualizar_vencimiento_recibo(uuid, date) to authenticated;
grant execute on function public.anular_recibo(uuid, text) to authenticated;
