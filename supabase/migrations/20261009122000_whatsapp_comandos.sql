create or replace function app_private.whatsapp_mes(p_mes integer)
returns text
language sql
immutable
set search_path = ''
as $$
	select (array[
		'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
		'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
	])[p_mes];
$$;

-- Punto de entrada de los mensajes del grupo. Devuelve el texto a responder o null para ignorar.
-- Los montos salen de las mismas tablas y reglas que Inicio y Mis cuotas (periodo del mes actual).
create or replace function app_private.responder_comando_whatsapp_impl(
	p_grupo_id text,
	p_remitente_id text,
	p_comando text,
	p_remitente_alt text default null,
	p_fecha date default (timezone('America/Lima', now()))::date
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_texto text := regexp_replace(trim(coalesce(p_comando, '')), '\s+', ' ', 'g');
	v_comando text;
	v_argumento text;
	v_familia_id uuid;
	v_miembro_id uuid;
	v_usuario_id uuid;
	v_nombre text;
	v_periodo_id uuid;
	v_mes text := app_private.whatsapp_mes(extract(month from p_fecha)::int);
	v_total numeric;
	v_lineas text;
	v_recibos integer;
	v_pagados integer;
	v_esperando integer;
	v_recaudado numeric;
	v_asignado numeric;
begin
	if left(v_texto, 1) <> '/' then
		return null;
	end if;

	v_comando := lower(split_part(v_texto, ' ', 1));
	v_argumento := nullif(split_part(v_texto, ' ', 2), '');

	if v_comando = '/ping' then
		return 'pong 🏠';
	end if;

	select g.familia_id
	into v_familia_id
	from public.whatsapp_vinculos g
	join public.familias f on f.id = g.familia_id and f.activo = true
	where g.tipo = 'GRUPO'
		and g.whatsapp_id = p_grupo_id;

	-- En un grupo no vinculado solo se atienden /ping y /vincular-grupo.
	if v_familia_id is null and v_comando <> '/vincular-grupo' then
		return null;
	end if;

	if v_comando in ('/vincular-grupo', '/vincular') then
		if v_argumento is null then
			return case v_comando
				when '/vincular-grupo' then 'Escribe /vincular-grupo seguido del código que generaste en FamiliaHub > Configuración > WhatsApp.'
				else 'Escribe /vincular seguido del código que generaste en FamiliaHub > Perfil > WhatsApp.'
			end;
		end if;

		begin
			return app_private.vincular_whatsapp_impl(v_argumento, p_grupo_id, coalesce(p_remitente_id, p_remitente_alt));
		exception
			when raise_exception then
				return sqlerrm;
			when unique_violation then
				return 'Este grupo o WhatsApp ya está vinculado. Revisa el estado en FamiliaHub.';
		end;
	end if;

	if v_comando in ('/ayuda', '/comandos', '/help') then
		return concat_ws(
			E'\n',
			'🏠 FamiliaHub',
			'/deuda · cuánto te falta pagar este mes',
			'/vence · próximos vencimientos',
			'/resumen · cómo va el mes',
			'/vincular CODIGO · vincula tu WhatsApp (código en Perfil)',
			'Los pagos se registran en la app.'
		);
	end if;

	if v_comando not in ('/deuda', '/vence', '/resumen') then
		return 'No conozco ese comando. Escribe /ayuda para ver la lista.';
	end if;

	select m.id, m.usuario_id, coalesce(nullif(trim(p.nombre), ''), p.usuario, 'Integrante')
	into v_miembro_id, v_usuario_id, v_nombre
	from public.whatsapp_vinculos v
	join public.miembros_familia m
		on m.id = v.miembro_id
		and m.familia_id = v.familia_id
		and m.estado = 'ACTIVO'
	left join public.perfiles p on p.id = m.usuario_id
	where v.familia_id = v_familia_id
		and v.tipo = 'INTEGRANTE'
		and v.whatsapp_id in (p_remitente_id, p_remitente_alt)
	order by (v.whatsapp_id = p_remitente_id) desc
	limit 1;

	if v_miembro_id is null then
		return 'Aún no vinculas tu WhatsApp. Genera tu código en FamiliaHub > Perfil > WhatsApp y escribe aquí /vincular CODIGO.';
	end if;

	select id
	into v_periodo_id
	from public.periodos
	where familia_id = v_familia_id
		and anio = extract(year from p_fecha)::smallint
		and mes = extract(month from p_fecha)::smallint;

	if v_comando = '/deuda' then
		select
			coalesce(sum(q.saldo), 0),
			string_agg(
				format(
					'• %s: %s (%s%s)',
					q.nombre,
					app_private.whatsapp_monto(q.saldo),
					case
						when q.objetivo is null then 'sin fecha límite'
						when q.objetivo < p_fecha then 'vencida ' || app_private.whatsapp_fecha(q.objetivo)
						when q.objetivo = p_fecha then 'vence hoy'
						else 'vence ' || app_private.whatsapp_fecha(q.objetivo)
					end,
					case when q.estado = 'POR_VALIDAR' then ' · pago por validar' else '' end
				),
				E'\n'
				order by q.objetivo nulls last, q.nombre, q.id
			)
		into v_total, v_lineas
		from (
			select
				c.id,
				r.nombre_concepto as nombre,
				c.saldo_pendiente as saldo,
				c.estado,
				coalesce(r.fecha_limite_aporte, r.fecha_vencimiento) as objetivo
			from public.cuotas c
			join public.recibos r on r.id = c.recibo_id
			where c.familia_id = v_familia_id
				and c.usuario_id = v_usuario_id
				and r.periodo_id = v_periodo_id
				and c.estado <> 'ANULADA'
				and c.saldo_pendiente > 0
		) q;

		if v_total = 0 then
			return format('%s, no tienes cuotas pendientes este mes. ✅', v_nombre);
		end if;

		return format('%s, tienes %s pendientes:', v_nombre, app_private.whatsapp_monto(v_total)) || E'\n' || v_lineas;
	end if;

	if v_comando = '/vence' then
		select string_agg(
			'• ' || q.nombre || ': ' ||
			case
				when q.monto_total is null then 'esperando monto'
				else concat_ws(
					' · ',
					case
						when q.objetivo is null then 'sin fecha'
						when q.objetivo < p_fecha then 'venció ' || app_private.whatsapp_fecha(q.objetivo)
						when q.objetivo = p_fecha then 'vence hoy'
						when q.objetivo = p_fecha + 1 then 'vence mañana'
						else format('vence %s (en %s días)', app_private.whatsapp_fecha(q.objetivo), q.objetivo - p_fecha)
					end,
					'falta ' || app_private.whatsapp_monto(q.falta),
					case when q.mio > 0 then 'tú ' || app_private.whatsapp_monto(q.mio) end
				)
			end,
			E'\n'
			order by q.objetivo nulls last, q.nombre, q.id
		)
		into v_lineas
		from (
			select
				r.id,
				r.nombre_concepto as nombre,
				r.monto_total,
				coalesce(r.fecha_limite_aporte, r.fecha_vencimiento) as objetivo,
				s.falta,
				s.mio
			from public.recibos r
			cross join lateral (
				select
					coalesce(sum(c.saldo_pendiente), 0) as falta,
					coalesce(sum(c.saldo_pendiente) filter (where c.usuario_id = v_usuario_id), 0) as mio
				from public.cuotas c
				where c.recibo_id = r.id
					and c.estado <> 'ANULADA'
			) s
			where r.periodo_id = v_periodo_id
				and r.estado <> 'ANULADO'
				and r.estado_recaudacion <> 'COMPLETA'
		) q;

		if v_lineas is null then
			return format('No hay vencimientos pendientes en %s. ✅', v_mes);
		end if;

		return format('Vencimientos de %s:', v_mes) || E'\n' || v_lineas;
	end if;

	select
		count(*) filter (where r.estado <> 'ANULADO'),
		count(*) filter (where r.estado = 'PAGADO'),
		count(*) filter (where r.estado = 'ESPERANDO_MONTO')
	into v_recibos, v_pagados, v_esperando
	from public.recibos r
	where r.periodo_id = v_periodo_id;

	if coalesce(v_recibos, 0) = 0 then
		return format('%s %s', initcap(v_mes), extract(year from p_fecha)) || E'\nAún no hay recibos este mes.';
	end if;

	select
		coalesce(sum(c.monto_pagado), 0),
		coalesce(sum(c.monto_asignado), 0),
		coalesce(sum(c.saldo_pendiente), 0)
	into v_recaudado, v_asignado, v_total
	from public.cuotas c
	join public.recibos r on r.id = c.recibo_id
	where r.periodo_id = v_periodo_id
		and r.estado <> 'ANULADO'
		and c.estado <> 'ANULADA';

	return concat_ws(
		E'\n',
		format('%s %s', initcap(v_mes), extract(year from p_fecha)),
		format('Recibos: %s · Pagados al proveedor: %s', v_recibos, v_pagados),
		format('Recaudado: %s de %s', app_private.whatsapp_monto(v_recaudado), app_private.whatsapp_monto(v_asignado)),
		'Falta: ' || app_private.whatsapp_monto(v_total),
		case when v_esperando > 0 then format('Esperando monto: %s', v_esperando) end
	);
end;
$$;

revoke all on function app_private.whatsapp_mes(integer) from public, anon, authenticated;
revoke all on function app_private.responder_comando_whatsapp_impl(text, text, text, text, date) from public, anon, authenticated;

grant execute on function app_private.responder_comando_whatsapp_impl(text, text, text, text, date) to service_role;

create or replace function public.responder_comando_whatsapp(
	p_grupo_id text,
	p_remitente_id text,
	p_comando text,
	p_remitente_alt text default null
)
returns text
language sql
security invoker
set search_path = ''
as $$ select app_private.responder_comando_whatsapp_impl(p_grupo_id, p_remitente_id, p_comando, p_remitente_alt); $$;

revoke all on function public.responder_comando_whatsapp(text, text, text, text) from public, anon, authenticated;

grant execute on function public.responder_comando_whatsapp(text, text, text, text) to service_role;
