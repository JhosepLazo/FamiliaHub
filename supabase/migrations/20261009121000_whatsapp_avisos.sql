create or replace function app_private.whatsapp_monto(p_monto numeric)
returns text
language sql
immutable
set search_path = ''
as $$
	select 'S/ ' || to_char(coalesce(p_monto, 0), 'FM999,999,990.00');
$$;

create or replace function app_private.whatsapp_fecha(p_fecha date)
returns text
language sql
immutable
set search_path = ''
as $$
	select to_char(p_fecha, 'DD/MM');
$$;

create or replace function app_private.whatsapp_fecha_dia(p_fecha date)
returns text
language sql
immutable
set search_path = ''
as $$
	select (array['dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb'])[extract(dow from p_fecha)::int + 1]
		|| ' ' || to_char(p_fecha, 'DD/MM');
$$;

-- Saldos pendientes por integrante de un recibo, en orden alfabético.
create or replace function app_private.whatsapp_pendientes_recibo(p_recibo_id uuid)
returns text
language sql
stable
set search_path = ''
as $$
	select
		case when count(*) = 1 then 'Pendiente: ' else 'Pendientes: ' end
		|| string_agg(
			c.nombre_miembro || ' ' || app_private.whatsapp_monto(c.saldo_pendiente)
				|| case when c.estado = 'POR_VALIDAR' then ' (por validar)' else '' end,
			' · '
			order by c.nombre_miembro, c.id
		)
	from public.cuotas c
	where c.recibo_id = p_recibo_id
		and c.estado <> 'ANULADA'
		and c.saldo_pendiente > 0
	having count(*) > 0;
$$;

-- Devuelve el tipo de aviso que corresponde a un recibo en una fecha, o null.
-- Usa la misma fecha objetivo que Inicio y Mis cuotas.
create or replace function app_private.tipo_aviso_whatsapp_del_dia(p_recibo_id uuid, p_fecha date)
returns public.tipo_aviso_whatsapp
language sql
stable
set search_path = ''
as $$
	select
		case
			when objetivo - p_fecha in (3, 1) then 'POR_VENCER'::public.tipo_aviso_whatsapp
			when p_fecha - objetivo >= 1 and (p_fecha - objetivo - 1) % 3 = 0 then 'VENCIDO'::public.tipo_aviso_whatsapp
		end
	from (
		select coalesce(r.fecha_limite_aporte, r.fecha_vencimiento) as objetivo
		from public.recibos r
		join public.periodos p on p.id = r.periodo_id and p.estado = 'ABIERTO'
		join public.familias f on f.id = r.familia_id and f.activo = true
		join public.whatsapp_vinculos g
			on g.familia_id = r.familia_id
			and g.tipo = 'GRUPO'
			and g.whatsapp_id is not null
		where r.id = p_recibo_id
			and r.monto_total is not null
			and r.estado in ('PENDIENTE', 'VENCIDO')
			and r.estado_recaudacion <> 'COMPLETA'
			and exists (
				select 1
				from public.cuotas c
				where c.recibo_id = r.id
					and c.estado <> 'ANULADA'
					and c.saldo_pendiente > 0
			)
	) recibo
	where objetivo is not null;
$$;

create or replace function app_private.mensaje_aviso_whatsapp(
	p_recibo_id uuid,
	p_tipo public.tipo_aviso_whatsapp,
	p_fecha date
)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
	v_nombre text;
	v_total numeric;
	v_objetivo date;
	v_falta numeric;
	v_dias integer;
	v_titulo text;
begin
	select r.nombre_concepto, r.monto_total, coalesce(r.fecha_limite_aporte, r.fecha_vencimiento)
	into v_nombre, v_total, v_objetivo
	from public.recibos r
	where r.id = p_recibo_id;

	select coalesce(sum(c.saldo_pendiente), 0)
	into v_falta
	from public.cuotas c
	where c.recibo_id = p_recibo_id
		and c.estado <> 'ANULADA';

	v_dias := v_objetivo - p_fecha;

	if p_tipo = 'POR_VENCER' then
		v_titulo := format(
			'⏰ %s vence %s (%s)',
			v_nombre,
			case v_dias when 0 then 'hoy' when 1 then 'mañana' else format('en %s días', v_dias) end,
			app_private.whatsapp_fecha_dia(v_objetivo)
		);
	else
		v_titulo := format(
			'⚠️ %s venció %s (%s)',
			v_nombre,
			case -v_dias when 1 then 'ayer' else format('hace %s días', -v_dias) end,
			app_private.whatsapp_fecha_dia(v_objetivo)
		);
	end if;

	return concat_ws(
		E'\n',
		v_titulo,
		'Total: ' || app_private.whatsapp_monto(v_total),
		'Falta recaudar: ' || app_private.whatsapp_monto(v_falta),
		app_private.whatsapp_pendientes_recibo(p_recibo_id),
		'Paga desde FamiliaHub > Mis cuotas.'
	);
end;
$$;

-- Inserta en la cola los avisos del día. Es idempotente: puede ejecutarse varias veces.
create or replace function app_private.generar_avisos_whatsapp_impl(
	p_fecha date default (timezone('America/Lima', now()))::date
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_total integer;
begin
	insert into public.avisos_whatsapp (familia_id, recibo_id, tipo, fecha_aviso, mensaje)
	select
		r.familia_id,
		r.id,
		t.tipo,
		p_fecha,
		app_private.mensaje_aviso_whatsapp(r.id, t.tipo, p_fecha)
	from public.recibos r
	cross join lateral (
		select app_private.tipo_aviso_whatsapp_del_dia(r.id, p_fecha) as tipo
	) t
	where r.estado in ('PENDIENTE', 'VENCIDO')
		and t.tipo is not null
	order by r.familia_id, coalesce(r.fecha_limite_aporte, r.fecha_vencimiento), r.nombre_concepto
	on conflict (recibo_id, tipo, fecha_aviso) do nothing;

	get diagnostics v_total = row_count;
	return v_total;
end;
$$;

-- Entrega al bot los avisos listos para enviar con el grupo destino.
-- Fuera de la ventana horaria (08:00–21:00 Lima) no entrega nada.
-- Antes de entregar, descarta avisos que ya no aplican y recalcula los montos.
create or replace function app_private.tomar_avisos_whatsapp_impl(p_ahora timestamptz default now())
returns table (
	id uuid,
	grupo_id text,
	mensaje text
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
	v_local timestamp := timezone('America/Lima', p_ahora);
	v_hoy date := v_local::date;
begin
	if v_local::time < time '08:00' or v_local::time >= time '21:00' then
		return;
	end if;

	update public.avisos_whatsapp a
	set estado = 'DESCARTADO',
		tomado_at = null,
		updated_at = now()
	where a.estado = 'PENDIENTE'
		and (
			a.fecha_aviso <> v_hoy
			or app_private.tipo_aviso_whatsapp_del_dia(a.recibo_id, v_hoy) is distinct from a.tipo
		);

	return query
	with tomados as (
		update public.avisos_whatsapp a
		set tomado_at = now(),
			mensaje = app_private.mensaje_aviso_whatsapp(a.recibo_id, a.tipo, v_hoy),
			updated_at = now()
		where a.id in (
			select p.id
			from public.avisos_whatsapp p
			where p.estado = 'PENDIENTE'
				and (p.tomado_at is null or p.tomado_at < now() - interval '2 minutes')
			order by p.created_at, p.id
			limit 10
			for update skip locked
		)
		returning a.id, a.familia_id, a.mensaje, a.created_at
	)
	select t.id, g.whatsapp_id, t.mensaje
	from tomados t
	join public.whatsapp_vinculos g
		on g.familia_id = t.familia_id
		and g.tipo = 'GRUPO'
		and g.whatsapp_id is not null
	order by t.created_at, t.id;
end;
$$;

-- Registra el resultado del envío. Tras 3 fallos el aviso queda en ERROR.
create or replace function app_private.marcar_aviso_whatsapp_impl(
	p_aviso_id uuid,
	p_enviado boolean,
	p_error text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
	update public.avisos_whatsapp
	set estado = case
			when p_enviado then 'ENVIADO'::public.estado_aviso_whatsapp
			when intentos + 1 >= 3 then 'ERROR'::public.estado_aviso_whatsapp
			else 'PENDIENTE'::public.estado_aviso_whatsapp
		end,
		intentos = case when p_enviado then intentos else intentos + 1 end,
		error = case
			when p_enviado then null
			else left(coalesce(nullif(trim(p_error), ''), 'Error desconocido.'), 500)
		end,
		enviado_at = case when p_enviado then now() end,
		tomado_at = null,
		updated_at = now()
	where id = p_aviso_id
		and estado = 'PENDIENTE';

	return found;
end;
$$;

revoke all on function app_private.whatsapp_monto(numeric) from public, anon, authenticated;
revoke all on function app_private.whatsapp_fecha(date) from public, anon, authenticated;
revoke all on function app_private.whatsapp_fecha_dia(date) from public, anon, authenticated;
revoke all on function app_private.whatsapp_pendientes_recibo(uuid) from public, anon, authenticated;
revoke all on function app_private.tipo_aviso_whatsapp_del_dia(uuid, date) from public, anon, authenticated;
revoke all on function app_private.mensaje_aviso_whatsapp(uuid, public.tipo_aviso_whatsapp, date) from public, anon, authenticated;
revoke all on function app_private.generar_avisos_whatsapp_impl(date) from public, anon, authenticated, service_role;
revoke all on function app_private.tomar_avisos_whatsapp_impl(timestamptz) from public, anon, authenticated;
revoke all on function app_private.marcar_aviso_whatsapp_impl(uuid, boolean, text) from public, anon, authenticated;

grant execute on function app_private.tomar_avisos_whatsapp_impl(timestamptz) to service_role;
grant execute on function app_private.marcar_aviso_whatsapp_impl(uuid, boolean, text) to service_role;

create or replace function public.tomar_avisos_whatsapp()
returns table (id uuid, grupo_id text, mensaje text)
language sql
security invoker
set search_path = ''
as $$ select * from app_private.tomar_avisos_whatsapp_impl(); $$;

create or replace function public.marcar_aviso_whatsapp(p_aviso_id uuid, p_enviado boolean, p_error text default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select app_private.marcar_aviso_whatsapp_impl(p_aviso_id, p_enviado, p_error); $$;

revoke all on function public.tomar_avisos_whatsapp() from public, anon, authenticated;
revoke all on function public.marcar_aviso_whatsapp(uuid, boolean, text) from public, anon, authenticated;

grant execute on function public.tomar_avisos_whatsapp() to service_role;
grant execute on function public.marcar_aviso_whatsapp(uuid, boolean, text) to service_role;

-- Cada hora: los avisos de recibos confirmados durante el día también salen a tiempo.
-- La cola es idempotente y el bot solo recibe avisos dentro de la ventana horaria.
do $$
begin
	perform cron.unschedule('familiahub-avisos-whatsapp');
exception
	when others then
		null;
end
$$;

select cron.schedule(
	'familiahub-avisos-whatsapp',
	'5 * * * *',
	$$select app_private.generar_avisos_whatsapp_impl();$$
);
