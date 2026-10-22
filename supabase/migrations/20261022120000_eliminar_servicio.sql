-- Eliminar un servicio desde Administrar → Servicios.
-- Si nunca se movió dinero, el servicio y sus recibos se borran por completo. Si ya tiene pagos, se archiva:
-- deja de generar recibos, sale de la lista, se anulan sus recibos abiertos sin movimientos y los recibos con
-- pagos se conservan tal cual (siguen visibles y lo pendiente se puede pagar). El nombre queda libre para crear
-- un servicio nuevo con el mismo nombre.

alter table public.conceptos_pago add column eliminado_at timestamptz;

create or replace function app_private.eliminar_concepto_servicio_impl(p_concepto_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_concepto public.conceptos_pago%rowtype;
	v_recibos uuid[];
	v_periodos uuid[];
	v_recibo_id uuid;
	v_periodo_id uuid;
	v_anulados integer := 0;
	v_con_historial boolean;
begin
	select *
	into v_concepto
	from public.conceptos_pago
	where id = p_concepto_id
	for update;

	if v_concepto.id is null or v_concepto.eliminado_at is not null then
		raise exception 'Servicio no disponible.';
	end if;

	if not app_private.es_admin(v_concepto.familia_id, v_usuario_id) then
		raise exception 'Solo un administrador puede eliminar servicios.';
	end if;

	select coalesce(array_agg(r.id), '{}'), coalesce(array_agg(distinct r.periodo_id), '{}')
	into v_recibos, v_periodos
	from public.recibos r
	where r.concepto_id = p_concepto_id;

	perform 1 from public.recibos where id = any(v_recibos) for update;

	if exists (
		select 1
		from public.pago_asignaciones pa
		inner join public.pagos_familiares pf on pf.id = pa.pago_id
		where pa.recibo_id = any(v_recibos)
			and pf.estado = 'POR_VALIDAR'
	) or exists (
		select 1
		from public.aportes
		where recibo_id = any(v_recibos)
			and estado = 'POR_VALIDAR'
	) then
		raise exception 'Este servicio tiene pagos por validar. Valídalos o recházalos en Pagos y vuelve a intentarlo.';
	end if;

	-- Los pagos preparados y nunca enviados no movieron dinero: se descartan.
	delete from public.pagos_familiares pf
	where pf.estado = 'BORRADOR'
		and exists (
			select 1
			from public.pago_asignaciones pa
			where pa.pago_id = pf.id
				and pa.recibo_id = any(v_recibos)
		);

	-- Un periodo cerrado es inmutable: si el servicio tiene recibos ahí, se archiva en lugar de borrarse.
	v_con_historial := exists (select 1 from public.pago_asignaciones where recibo_id = any(v_recibos))
		or exists (select 1 from public.aportes where recibo_id = any(v_recibos))
		or exists (select 1 from public.pagos_proveedor where recibo_id = any(v_recibos))
		or exists (select 1 from public.recibo_ajustes where recibo_id = any(v_recibos))
		or exists (select 1 from public.cuotas where recibo_id = any(v_recibos) and monto_pagado > 0)
		or exists (select 1 from public.periodos where id = any(v_periodos) and estado <> 'ABIERTO');

	if not v_con_historial then
		-- Las cuotas se borran antes que su recibo: la protección de periodos cerrados las revisa
		-- mirando su recibo, que en un borrado en cascada ya no existiría.
		delete from public.cuotas where recibo_id = any(v_recibos);
		delete from public.recibos where id = any(v_recibos);
		delete from public.conceptos_pago where id = p_concepto_id;

		perform app_private.registrar_evento_financiero(
			v_concepto.familia_id,
			'CONCEPTO',
			p_concepto_id,
			'CONCEPTO_ELIMINADO',
			jsonb_build_object('nombre', v_concepto.nombre, 'recibos', cardinality(v_recibos)),
			v_usuario_id
		);

		-- Sin ese recibo, el periodo puede quedar completo.
		foreach v_periodo_id in array v_periodos loop
			perform app_private.intentar_cerrar_periodo(v_periodo_id);
		end loop;

		return jsonb_build_object('modo', 'ELIMINADO', 'recibosAnulados', 0);
	end if;

	-- Con historial: se anulan solo los recibos abiertos que no tienen ningún movimiento.
	for v_recibo_id in
		select r.id
		from public.recibos r
		inner join public.periodos pe on pe.id = r.periodo_id
		where r.concepto_id = p_concepto_id
			and r.estado <> 'ANULADO'
			and pe.estado = 'ABIERTO'
			and not exists (select 1 from public.pago_asignaciones pa where pa.recibo_id = r.id)
			and not exists (select 1 from public.aportes a where a.recibo_id = r.id and a.estado in ('POR_VALIDAR', 'CONFIRMADO'))
			and not exists (select 1 from public.pagos_proveedor pp where pp.recibo_id = r.id and pp.estado = 'CONFIRMADO')
			and not exists (select 1 from public.cuotas q where q.recibo_id = r.id and q.monto_pagado > 0)
	loop
		perform app_private.anular_recibo_impl(v_recibo_id, 'Servicio eliminado');
		v_anulados := v_anulados + 1;
	end loop;

	update public.cuentas_servicio
	set activo = false,
		updated_at = now()
	where concepto_id = p_concepto_id;

	update public.conceptos_pago
	set activo = false,
		eliminado_at = now(),
		nombre = left(nombre, 60) || ' (eliminado ' || to_char(timezone('America/Lima', now()), 'DD/MM/YYYY') || ' · ' || left(id::text, 4) || ')',
		updated_at = now()
	where id = p_concepto_id;

	perform app_private.registrar_evento_financiero(
		v_concepto.familia_id,
		'CONCEPTO',
		p_concepto_id,
		'CONCEPTO_ARCHIVADO',
		jsonb_build_object('nombre', v_concepto.nombre, 'recibosAnulados', v_anulados),
		v_usuario_id
	);

	return jsonb_build_object('modo', 'ARCHIVADO', 'recibosAnulados', v_anulados);
end;
$$;

create or replace function public.eliminar_concepto_servicio(p_concepto_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
	select app_private.eliminar_concepto_servicio_impl(p_concepto_id);
$$;

revoke all on function app_private.eliminar_concepto_servicio_impl(uuid) from public, anon;
grant execute on function app_private.eliminar_concepto_servicio_impl(uuid) to authenticated;
revoke all on function public.eliminar_concepto_servicio(uuid) from public, anon;
grant execute on function public.eliminar_concepto_servicio(uuid) to authenticated;
