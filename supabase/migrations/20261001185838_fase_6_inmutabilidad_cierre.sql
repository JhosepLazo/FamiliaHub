create or replace function app_private.periodo_recibo_abierto(p_recibo_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
	select exists (
		select 1
		from public.recibos r
		inner join public.periodos p on p.id = r.periodo_id
		where r.id = p_recibo_id
			and p.estado = 'ABIERTO'
	);
$$;

revoke all on function app_private.periodo_recibo_abierto(uuid) from public, anon, authenticated;

create or replace function app_private.bloquear_periodo_financiero_cerrado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_recibo_id uuid;
begin
	v_recibo_id := case
		when tg_table_name = 'recibos' then coalesce(new.id, old.id)
		else coalesce(new.recibo_id, old.recibo_id)
	end;

	if not app_private.periodo_recibo_abierto(v_recibo_id) then
		raise exception 'El periodo está cerrado y sus movimientos financieros son inmutables.';
	end if;

	return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function app_private.bloquear_periodo_financiero_cerrado() from public, anon, authenticated;

create trigger bloquear_recibos_periodo_cerrado
before insert or update or delete on public.recibos
for each row execute function app_private.bloquear_periodo_financiero_cerrado();

create trigger bloquear_cuotas_periodo_cerrado
before insert or update or delete on public.cuotas
for each row execute function app_private.bloquear_periodo_financiero_cerrado();

create trigger bloquear_aportes_periodo_cerrado
before insert or update or delete on public.aportes
for each row execute function app_private.bloquear_periodo_financiero_cerrado();

create trigger bloquear_pagos_proveedor_periodo_cerrado
before insert or update or delete on public.pagos_proveedor
for each row execute function app_private.bloquear_periodo_financiero_cerrado();

create trigger bloquear_ajustes_periodo_cerrado
before insert or update or delete on public.recibo_ajustes
for each row execute function app_private.bloquear_periodo_financiero_cerrado();

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
	v_periodo_id uuid;
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
	where id = p_recibo_id
	returning periodo_id into v_periodo_id;

	if v_periodo_id is not null then
		perform app_private.intentar_cerrar_periodo(v_periodo_id);
	end if;
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
			and mes = extract(month from p_fecha)::smallint
			and estado = 'ABIERTO';

		if v_periodo_id is null then
			continue;
		end if;

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

revoke execute on function app_private.sincronizar_periodos_impl(uuid, date) from authenticated;
revoke execute on function public.guardar_concepto_servicio(
	uuid,
	uuid,
	uuid,
	uuid,
	uuid,
	text,
	public.frecuencia_concepto,
	public.metodo_obtencion_monto,
	numeric,
	public.tipo_vencimiento_concepto,
	smallint,
	public.tipo_distribucion_concepto,
	public.tipo_reparto_resto,
	boolean,
	jsonb,
	jsonb
) from authenticated;
