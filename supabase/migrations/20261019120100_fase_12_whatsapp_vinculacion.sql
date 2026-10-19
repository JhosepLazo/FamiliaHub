grant usage on schema app_private to service_role;

create or replace function app_private.whatsapp_ahora_local(p_familia_id uuid)
returns timestamp
language sql
stable
security definer
set search_path = ''
as $$
	select timezone(
		coalesce(
			(select f.zona_horaria from public.familias f where f.id = p_familia_id),
			'America/Lima'
		),
		now()
	);
$$;

create or replace function app_private.whatsapp_monto(p_monto numeric, p_moneda char(3))
returns text
language sql
stable
set search_path = ''
as $$
	select
		case upper(trim(coalesce(p_moneda, 'PEN')))
			when 'PEN' then 'S/ '
			when 'USD' then 'US$ '
			else upper(trim(p_moneda)) || ' '
		end
		|| to_char(coalesce(p_monto, 0), 'FM999,999,990.00');
$$;

create or replace function app_private.whatsapp_fecha(p_fecha date)
returns text
language sql
stable
set search_path = ''
as $$
	select case
		when p_fecha is null then null
		else (array['dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb'])[extract(dow from p_fecha)::int + 1]
			|| ' '
			|| to_char(p_fecha, 'DD/MM')
	end;
$$;

create or replace function app_private.whatsapp_mes(p_anio smallint, p_mes smallint)
returns text
language sql
immutable
set search_path = ''
as $$
	select (array[
		'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
		'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
	])[p_mes] || ' ' || p_anio::text;
$$;

create or replace function app_private.whatsapp_normalizar(p_texto text)
returns text
language sql
immutable
set search_path = ''
as $$
	select trim(regexp_replace(
		lower(translate(
			coalesce(p_texto, ''),
			'ÁÉÍÓÚÜÀÈÌÒÙÂÊÎÔÛÑáéíóúüàèìòùâêîôûñ',
			'AEIOUUAEIOUAEIOUNaeiouuaeiouaeioun'
		)),
		'\s+',
		' ',
		'g'
	));
$$;

create or replace function app_private.whatsapp_recortar(p_texto text, p_max integer default 1500)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
	v_lineas text[];
	v_total integer;
	v_incluidas integer := 0;
	v_resultado text := '';
	v_sufijo text;
begin
	if p_texto is null or char_length(p_texto) <= p_max then
		return p_texto;
	end if;

	v_lineas := string_to_array(p_texto, E'\n');
	v_total := coalesce(array_length(v_lineas, 1), 0);

	while v_incluidas < v_total loop
		v_sufijo := E'\n… y ' || (v_total - v_incluidas - 1)::text || ' más';
		exit when char_length(v_resultado)
			+ case when v_incluidas = 0 then 0 else 1 end
			+ char_length(v_lineas[v_incluidas + 1])
			+ char_length(v_sufijo) > p_max;

		v_resultado := case
			when v_incluidas = 0 then v_lineas[1]
			else v_resultado || E'\n' || v_lineas[v_incluidas + 1]
		end;
		v_incluidas := v_incluidas + 1;
	end loop;

	if v_incluidas = 0 or v_incluidas >= v_total then
		return left(p_texto, p_max - 1) || '…';
	end if;

	return v_resultado || E'\n… y ' || (v_total - v_incluidas)::text || ' más';
end;
$$;

create or replace function app_private.whatsapp_lista(p_lineas text[], p_max integer default 10)
returns text
language sql
immutable
set search_path = ''
as $$
	select case
		when coalesce(cardinality(p_lineas), 0) = 0 then null
		when cardinality(p_lineas) <= p_max then array_to_string(p_lineas, E'\n')
		else array_to_string(p_lineas[1:p_max], E'\n')
			|| E'\n… y ' || (cardinality(p_lineas) - p_max)::text || ' más'
	end;
$$;

create or replace function app_private.whatsapp_periodo_actual(p_familia_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
	select p.id
	from public.periodos p
	cross join lateral (select app_private.whatsapp_ahora_local(p_familia_id)::date as hoy) local
	where p.familia_id = p_familia_id
		and p.anio = extract(year from local.hoy)::smallint
		and p.mes = extract(month from local.hoy)::smallint;
$$;

create or replace function app_private.whatsapp_contexto(p_grupo_id text, p_remitente_ids text[])
returns table (
	familia_id uuid,
	familia_nombre text,
	moneda char(3),
	miembro_id uuid,
	usuario_id uuid,
	rol public.rol_familia,
	nombre text
)
language sql
stable
security definer
set search_path = ''
as $$
	select
		f.id,
		f.nombre,
		f.moneda,
		m.id,
		m.usuario_id,
		m.rol,
		case when m.id is null then null else coalesce(nullif(trim(per.nombre), ''), 'Integrante') end
	from public.whatsapp_vinculos g
	inner join public.familias f on f.id = g.familia_id
	left join lateral (
		select vi.miembro_id
		from public.whatsapp_vinculos vi
		where vi.familia_id = g.familia_id
			and vi.tipo = 'INTEGRANTE'
			and vi.whatsapp_id is not null
			and (
				vi.whatsapp_id = any(coalesce(p_remitente_ids, '{}'::text[]))
				or vi.whatsapp_id_alt = any(coalesce(p_remitente_ids, '{}'::text[]))
			)
		order by vi.vinculado_at
		limit 1
	) v on true
	left join public.miembros_familia m
		on m.id = v.miembro_id
		and m.familia_id = g.familia_id
		and m.estado = 'ACTIVO'
	left join public.perfiles per on per.id = m.usuario_id
	where p_grupo_id is not null
		and g.tipo = 'GRUPO'
		and g.whatsapp_id = p_grupo_id;
$$;

create or replace function app_private.whatsapp_mencion(p_familia_id uuid, p_miembro_id uuid, p_nombre text)
returns table (
	texto text,
	jid text
)
language sql
stable
security definer
set search_path = ''
as $$
	select
		case
			when v.whatsapp_id is null then coalesce(nullif(trim(p_nombre), ''), 'Integrante')
			else '@' || split_part(split_part(v.whatsapp_id, '@', 1), ':', 1)
		end,
		case
			when v.whatsapp_id is null then null
			else split_part(split_part(v.whatsapp_id, '@', 1), ':', 1) || '@' || split_part(v.whatsapp_id, '@', 2)
		end
	from (select 1) base
	left join lateral (
		select vi.whatsapp_id
		from public.whatsapp_vinculos vi
		inner join public.miembros_familia m
			on m.id = vi.miembro_id
			and m.estado = 'ACTIVO'
		inner join public.whatsapp_configuracion c
			on c.familia_id = vi.familia_id
			and c.mencionar_integrantes
		where vi.familia_id = p_familia_id
			and vi.miembro_id = p_miembro_id
			and vi.tipo = 'INTEGRANTE'
			and vi.whatsapp_id is not null
		limit 1
	) v on true;
$$;

create or replace function app_private.whatsapp_generar_codigo()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
	v_alfabeto constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
	v_codigo text := '';
	v_bytes bytea;
	v_byte integer;
	v_i integer;
begin
	-- Bytes 0 a 5 de un UUID v4 son aleatorios. Se descartan valores >= 248 para evitar sesgo de módulo.
	while char_length(v_codigo) < 6 loop
		v_bytes := uuid_send(gen_random_uuid());

		for v_i in 0..5 loop
			v_byte := get_byte(v_bytes, v_i);

			if v_byte < 248 and char_length(v_codigo) < 6 then
				v_codigo := v_codigo || substr(v_alfabeto, (v_byte % 31) + 1, 1);
			end if;
		end loop;
	end loop;

	return v_codigo;
end;
$$;

create or replace function app_private.whatsapp_asegurar_configuracion(p_familia_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
	insert into public.whatsapp_configuracion (familia_id)
	values (p_familia_id)
	on conflict (familia_id) do nothing;
$$;

create or replace function app_private.whatsapp_configuracion_json(p_configuracion public.whatsapp_configuracion)
returns jsonb
language sql
stable
set search_path = ''
as $$
	select jsonb_build_object(
		'avisosActivos', (p_configuracion).avisos_activos,
		'diasAvisoPrevio', to_jsonb(coalesce((p_configuracion).dias_aviso_previo, '{}'::smallint[])),
		'avisarVenceHoy', (p_configuracion).avisar_vence_hoy,
		'frecuenciaVencidosDias', (p_configuracion).frecuencia_vencidos_dias,
		'horaInicioEnvio', to_char((p_configuracion).hora_inicio_envio, 'HH24:MI'),
		'horaFinEnvio', to_char((p_configuracion).hora_fin_envio, 'HH24:MI'),
		'avisarInicioMes', (p_configuracion).avisar_inicio_mes,
		'avisarMonto', (p_configuracion).avisar_monto,
		'avisarPagoEnviado', (p_configuracion).avisar_pago_enviado,
		'avisarPagoConfirmado', (p_configuracion).avisar_pago_confirmado,
		'avisarRecaudacionCompleta', (p_configuracion).avisar_recaudacion_completa,
		'avisarPagoProveedor', (p_configuracion).avisar_pago_proveedor,
		'avisarCambiosRecibo', (p_configuracion).avisar_cambios_recibo,
		'avisarPendientesAdmin', (p_configuracion).avisar_pendientes_admin,
		'horaPendientesAdmin', to_char((p_configuracion).hora_pendientes_admin, 'HH24:MI'),
		'resumenSemanal', (p_configuracion).resumen_semanal,
		'diaResumen', (p_configuracion).dia_resumen,
		'horaResumen', to_char((p_configuracion).hora_resumen, 'HH24:MI'),
		'avisarCierreMes', (p_configuracion).avisar_cierre_mes,
		'mencionarIntegrantes', (p_configuracion).mencionar_integrantes,
		'lenguajeNatural', (p_configuracion).lenguaje_natural
	);
$$;

create or replace function app_private.whatsapp_config_booleano(p_json jsonb, p_clave text, p_actual boolean)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
begin
	if not (p_json ? p_clave) then
		return p_actual;
	end if;

	if jsonb_typeof(p_json -> p_clave) <> 'boolean' then
		raise exception 'El valor de % debe ser verdadero o falso.', p_clave;
	end if;

	return (p_json ->> p_clave)::boolean;
end;
$$;

create or replace function app_private.whatsapp_config_entero(
	p_json jsonb,
	p_clave text,
	p_actual smallint,
	p_minimo integer,
	p_maximo integer
)
returns smallint
language plpgsql
immutable
set search_path = ''
as $$
declare
	v_valor numeric;
begin
	if not (p_json ? p_clave) then
		return p_actual;
	end if;

	if jsonb_typeof(p_json -> p_clave) <> 'number' then
		raise exception 'El valor de % debe ser un número entero.', p_clave;
	end if;

	v_valor := (p_json ->> p_clave)::numeric;

	if v_valor <> trunc(v_valor) or v_valor < p_minimo or v_valor > p_maximo then
		raise exception 'El valor de % debe ser un entero entre % y %.', p_clave, p_minimo, p_maximo;
	end if;

	return v_valor::smallint;
end;
$$;

create or replace function app_private.whatsapp_config_hora(p_json jsonb, p_clave text, p_actual time)
returns time
language plpgsql
immutable
set search_path = ''
as $$
declare
	v_valor text;
begin
	if not (p_json ? p_clave) then
		return p_actual;
	end if;

	if jsonb_typeof(p_json -> p_clave) <> 'string' then
		raise exception 'El valor de % debe ser una hora con formato HH:MM.', p_clave;
	end if;

	v_valor := trim(p_json ->> p_clave);

	if v_valor !~ '^([01][0-9]|2[0-3]):[0-5][0-9](:00)?$' then
		raise exception 'El valor de % debe ser una hora con formato HH:MM.', p_clave;
	end if;

	return v_valor::time;
end;
$$;

create or replace function app_private.whatsapp_config_dias(p_json jsonb, p_clave text, p_actual smallint[])
returns smallint[]
language plpgsql
immutable
set search_path = ''
as $$
declare
	v_lista jsonb;
	v_elemento jsonb;
	v_valor numeric;
	v_dias smallint[] := '{}';
begin
	if not (p_json ? p_clave) then
		return p_actual;
	end if;

	v_lista := p_json -> p_clave;

	if jsonb_typeof(v_lista) <> 'array' then
		raise exception 'El valor de % debe ser una lista de días.', p_clave;
	end if;

	if jsonb_array_length(v_lista) > 5 then
		raise exception 'Puedes configurar como máximo 5 días de aviso previo.';
	end if;

	for v_elemento in select value from jsonb_array_elements(v_lista)
	loop
		if jsonb_typeof(v_elemento) <> 'number' then
			raise exception 'Cada día de aviso previo debe ser un número entero entre 1 y 15.';
		end if;

		v_valor := (v_elemento #>> '{}')::numeric;

		if v_valor <> trunc(v_valor) or v_valor < 1 or v_valor > 15 then
			raise exception 'Cada día de aviso previo debe ser un número entero entre 1 y 15.';
		end if;

		if not (v_valor::smallint = any(v_dias)) then
			v_dias := v_dias || v_valor::smallint;
		end if;
	end loop;

	return coalesce(
		(select array_agg(dia order by dia desc) from unnest(v_dias) dia),
		'{}'::smallint[]
	);
end;
$$;

create or replace function app_private.whatsapp_limpiar_vinculo_miembro()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
	-- Quien sale de la familia pierde su vínculo y, si vuelve, debe vincularse de nuevo.
	-- Un código pendiente se conserva: /vincular lo rechaza mientras el integrante esté inactivo.
	if new.estado = 'INACTIVO' and old.estado is distinct from new.estado then
		delete from public.whatsapp_vinculos
		where miembro_id = new.id
			and tipo = 'INTEGRANTE'
			and whatsapp_id is not null;
	end if;

	return new;
end;
$$;

create trigger whatsapp_limpiar_vinculo_miembro
after update of estado on public.miembros_familia
for each row execute function app_private.whatsapp_limpiar_vinculo_miembro();

create or replace function app_private.generar_codigo_whatsapp_impl(
	p_familia_id uuid,
	p_tipo public.tipo_vinculo_whatsapp
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_miembro_id uuid;
	v_miembro_vinculo uuid;
	v_vinculo public.whatsapp_vinculos%rowtype;
	v_codigo text;
	v_expira timestamptz := now() + interval '10 minutes';
	v_intento integer := 0;
begin
	if v_usuario_id is null then
		raise exception 'Debes iniciar sesión.';
	end if;

	if p_tipo is null then
		raise exception 'Indica el tipo de vínculo.';
	end if;

	select id
	into v_miembro_id
	from public.miembros_familia
	where familia_id = p_familia_id
		and usuario_id = v_usuario_id
		and estado = 'ACTIVO';

	if v_miembro_id is null then
		raise exception 'No perteneces a esta familia.';
	end if;

	if p_tipo = 'GRUPO' and not app_private.es_admin(p_familia_id, v_usuario_id) then
		raise exception 'Solo un administrador puede vincular el grupo de WhatsApp.';
	end if;

	v_miembro_vinculo := case when p_tipo = 'INTEGRANTE' then v_miembro_id else null end;

	select *
	into v_vinculo
	from public.whatsapp_vinculos
	where familia_id = p_familia_id
		and tipo = p_tipo
		and miembro_id is not distinct from v_miembro_vinculo
	for update;

	if v_vinculo.whatsapp_id is not null then
		if p_tipo = 'GRUPO' then
			raise exception 'El grupo ya está vinculado. Desvincúlalo antes de vincular otro.';
		end if;

		raise exception 'Tu WhatsApp ya está vinculado. Desvincúlalo antes de generar otro código.';
	end if;

	update public.whatsapp_vinculos
	set codigo = null,
		codigo_expira_at = null,
		updated_at = now()
	where codigo_expira_at <= now();

	loop
		v_intento := v_intento + 1;
		v_codigo := app_private.whatsapp_generar_codigo();

		begin
			insert into public.whatsapp_vinculos (
				familia_id,
				tipo,
				miembro_id,
				codigo,
				codigo_expira_at
			)
			values (
				p_familia_id,
				p_tipo,
				v_miembro_vinculo,
				v_codigo,
				v_expira
			)
			on conflict (familia_id, tipo, miembro_id) do update
			set codigo = excluded.codigo,
				codigo_expira_at = excluded.codigo_expira_at,
				updated_at = now();

			exit;
		exception
			when unique_violation then
				if v_intento >= 5 then
					raise exception 'No pudimos generar un código. Intenta nuevamente.';
				end if;
		end;
	end loop;

	return jsonb_build_object('codigo', v_codigo, 'expiraAt', v_expira);
end;
$$;

create or replace function app_private.desvincular_whatsapp_impl(
	p_familia_id uuid,
	p_tipo public.tipo_vinculo_whatsapp
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_miembro_id uuid;
begin
	if v_usuario_id is null then
		raise exception 'Debes iniciar sesión.';
	end if;

	if p_tipo is null then
		raise exception 'Indica el tipo de vínculo.';
	end if;

	select id
	into v_miembro_id
	from public.miembros_familia
	where familia_id = p_familia_id
		and usuario_id = v_usuario_id
		and estado = 'ACTIVO';

	if v_miembro_id is null then
		raise exception 'No perteneces a esta familia.';
	end if;

	if p_tipo = 'GRUPO' then
		if not app_private.es_admin(p_familia_id, v_usuario_id) then
			raise exception 'Solo un administrador puede desvincular el grupo de WhatsApp.';
		end if;

		delete from public.whatsapp_vinculos
		where familia_id = p_familia_id
			and tipo = 'GRUPO';

		update public.avisos_whatsapp
		set estado = 'EXPIRADO',
			bloqueado_hasta = null
		where familia_id = p_familia_id
			and estado = 'PENDIENTE';

		return;
	end if;

	delete from public.whatsapp_vinculos
	where familia_id = p_familia_id
		and tipo = 'INTEGRANTE'
		and miembro_id = v_miembro_id;
end;
$$;

create or replace function app_private.obtener_estado_whatsapp_impl(p_familia_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_miembro_id uuid;
	v_es_admin boolean;
	v_grupo public.whatsapp_vinculos%rowtype;
	v_yo public.whatsapp_vinculos%rowtype;
	v_heartbeat timestamptz;
	v_configuracion public.whatsapp_configuracion%rowtype;
	v_integrantes jsonb := '[]'::jsonb;
	v_configuracion_json jsonb;
begin
	if v_usuario_id is null then
		raise exception 'Debes iniciar sesión.';
	end if;

	select id
	into v_miembro_id
	from public.miembros_familia
	where familia_id = p_familia_id
		and usuario_id = v_usuario_id
		and estado = 'ACTIVO';

	if v_miembro_id is null then
		raise exception 'No perteneces a esta familia.';
	end if;

	v_es_admin := app_private.es_admin(p_familia_id, v_usuario_id);

	select *
	into v_grupo
	from public.whatsapp_vinculos
	where familia_id = p_familia_id
		and tipo = 'GRUPO';

	select *
	into v_yo
	from public.whatsapp_vinculos
	where familia_id = p_familia_id
		and tipo = 'INTEGRANTE'
		and miembro_id = v_miembro_id;

	select ultimo_heartbeat_at
	into v_heartbeat
	from public.whatsapp_sistema
	where id = 1;

	if v_es_admin then
		perform app_private.whatsapp_asegurar_configuracion(p_familia_id);

		select *
		into v_configuracion
		from public.whatsapp_configuracion
		where familia_id = p_familia_id;

		v_configuracion_json := app_private.whatsapp_configuracion_json(v_configuracion);

		select coalesce(
			jsonb_agg(
				jsonb_build_object(
					'miembroId', m.id,
					'nombre', coalesce(nullif(trim(per.nombre), ''), 'Integrante'),
					'rol', m.rol,
					'vinculado', vi.whatsapp_id is not null
				)
				order by m.joined_at, m.id
			),
			'[]'::jsonb
		)
		into v_integrantes
		from public.miembros_familia m
		left join public.perfiles per on per.id = m.usuario_id
		left join public.whatsapp_vinculos vi
			on vi.miembro_id = m.id
			and vi.familia_id = m.familia_id
			and vi.tipo = 'INTEGRANTE'
		where m.familia_id = p_familia_id
			and m.estado = 'ACTIVO';
	end if;

	return jsonb_build_object(
		'esAdmin', v_es_admin,
		'bot', jsonb_build_object('ultimoHeartbeatAt', v_heartbeat),
		'grupo', jsonb_build_object(
			'vinculado', v_grupo.whatsapp_id is not null,
			'vinculadoAt', v_grupo.vinculado_at,
			'codigo', case when v_es_admin and v_grupo.codigo_expira_at > now() then v_grupo.codigo end,
			'codigoExpiraAt', case when v_es_admin and v_grupo.codigo_expira_at > now() then v_grupo.codigo_expira_at end
		),
		'yo', jsonb_build_object(
			'vinculado', v_yo.whatsapp_id is not null,
			'vinculadoAt', v_yo.vinculado_at,
			'codigo', case when v_yo.codigo_expira_at > now() then v_yo.codigo end,
			'codigoExpiraAt', case when v_yo.codigo_expira_at > now() then v_yo.codigo_expira_at end
		),
		'integrantes', v_integrantes,
		'configuracion', v_configuracion_json
	);
end;
$$;

create or replace function app_private.guardar_configuracion_whatsapp_impl(
	p_familia_id uuid,
	p_configuracion jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_clave text;
	v_config public.whatsapp_configuracion%rowtype;
	v_permitidas constant text[] := array[
		'avisos_activos',
		'dias_aviso_previo',
		'avisar_vence_hoy',
		'frecuencia_vencidos_dias',
		'hora_inicio_envio',
		'hora_fin_envio',
		'avisar_inicio_mes',
		'avisar_monto',
		'avisar_pago_enviado',
		'avisar_pago_confirmado',
		'avisar_recaudacion_completa',
		'avisar_pago_proveedor',
		'avisar_cambios_recibo',
		'avisar_pendientes_admin',
		'hora_pendientes_admin',
		'resumen_semanal',
		'dia_resumen',
		'hora_resumen',
		'avisar_cierre_mes',
		'mencionar_integrantes',
		'lenguaje_natural'
	];
begin
	if v_usuario_id is null then
		raise exception 'Debes iniciar sesión.';
	end if;

	if not app_private.es_admin(p_familia_id, v_usuario_id) then
		raise exception 'Solo un administrador puede configurar los avisos de WhatsApp.';
	end if;

	if p_configuracion is null or jsonb_typeof(p_configuracion) <> 'object' then
		raise exception 'La configuración debe ser un objeto.';
	end if;

	for v_clave in select jsonb_object_keys(p_configuracion)
	loop
		if not (v_clave = any(v_permitidas)) then
			raise exception 'Clave de configuración desconocida: %.', v_clave;
		end if;
	end loop;

	perform app_private.whatsapp_asegurar_configuracion(p_familia_id);

	select *
	into v_config
	from public.whatsapp_configuracion
	where familia_id = p_familia_id
	for update;

	v_config.avisos_activos := app_private.whatsapp_config_booleano(p_configuracion, 'avisos_activos', v_config.avisos_activos);
	v_config.dias_aviso_previo := app_private.whatsapp_config_dias(p_configuracion, 'dias_aviso_previo', v_config.dias_aviso_previo);
	v_config.avisar_vence_hoy := app_private.whatsapp_config_booleano(p_configuracion, 'avisar_vence_hoy', v_config.avisar_vence_hoy);
	v_config.frecuencia_vencidos_dias := app_private.whatsapp_config_entero(p_configuracion, 'frecuencia_vencidos_dias', v_config.frecuencia_vencidos_dias, 0, 15);
	v_config.hora_inicio_envio := app_private.whatsapp_config_hora(p_configuracion, 'hora_inicio_envio', v_config.hora_inicio_envio);
	v_config.hora_fin_envio := app_private.whatsapp_config_hora(p_configuracion, 'hora_fin_envio', v_config.hora_fin_envio);
	v_config.avisar_inicio_mes := app_private.whatsapp_config_booleano(p_configuracion, 'avisar_inicio_mes', v_config.avisar_inicio_mes);
	v_config.avisar_monto := app_private.whatsapp_config_booleano(p_configuracion, 'avisar_monto', v_config.avisar_monto);
	v_config.avisar_pago_enviado := app_private.whatsapp_config_booleano(p_configuracion, 'avisar_pago_enviado', v_config.avisar_pago_enviado);
	v_config.avisar_pago_confirmado := app_private.whatsapp_config_booleano(p_configuracion, 'avisar_pago_confirmado', v_config.avisar_pago_confirmado);
	v_config.avisar_recaudacion_completa := app_private.whatsapp_config_booleano(p_configuracion, 'avisar_recaudacion_completa', v_config.avisar_recaudacion_completa);
	v_config.avisar_pago_proveedor := app_private.whatsapp_config_booleano(p_configuracion, 'avisar_pago_proveedor', v_config.avisar_pago_proveedor);
	v_config.avisar_cambios_recibo := app_private.whatsapp_config_booleano(p_configuracion, 'avisar_cambios_recibo', v_config.avisar_cambios_recibo);
	v_config.avisar_pendientes_admin := app_private.whatsapp_config_booleano(p_configuracion, 'avisar_pendientes_admin', v_config.avisar_pendientes_admin);
	v_config.hora_pendientes_admin := app_private.whatsapp_config_hora(p_configuracion, 'hora_pendientes_admin', v_config.hora_pendientes_admin);
	v_config.resumen_semanal := app_private.whatsapp_config_booleano(p_configuracion, 'resumen_semanal', v_config.resumen_semanal);
	v_config.dia_resumen := app_private.whatsapp_config_entero(p_configuracion, 'dia_resumen', v_config.dia_resumen, 0, 6);
	v_config.hora_resumen := app_private.whatsapp_config_hora(p_configuracion, 'hora_resumen', v_config.hora_resumen);
	v_config.avisar_cierre_mes := app_private.whatsapp_config_booleano(p_configuracion, 'avisar_cierre_mes', v_config.avisar_cierre_mes);
	v_config.mencionar_integrantes := app_private.whatsapp_config_booleano(p_configuracion, 'mencionar_integrantes', v_config.mencionar_integrantes);
	v_config.lenguaje_natural := app_private.whatsapp_config_booleano(p_configuracion, 'lenguaje_natural', v_config.lenguaje_natural);

	if v_config.hora_inicio_envio >= v_config.hora_fin_envio then
		raise exception 'La hora de inicio de envío debe ser menor que la hora de fin.';
	end if;

	if v_config.hora_pendientes_admin < v_config.hora_inicio_envio or v_config.hora_pendientes_admin >= v_config.hora_fin_envio then
		raise exception 'La hora de pendientes de administración debe estar dentro del horario de envío.';
	end if;

	if v_config.hora_resumen < v_config.hora_inicio_envio or v_config.hora_resumen >= v_config.hora_fin_envio then
		raise exception 'La hora del resumen semanal debe estar dentro del horario de envío.';
	end if;

	update public.whatsapp_configuracion
	set avisos_activos = v_config.avisos_activos,
		dias_aviso_previo = v_config.dias_aviso_previo,
		avisar_vence_hoy = v_config.avisar_vence_hoy,
		frecuencia_vencidos_dias = v_config.frecuencia_vencidos_dias,
		hora_inicio_envio = v_config.hora_inicio_envio,
		hora_fin_envio = v_config.hora_fin_envio,
		avisar_inicio_mes = v_config.avisar_inicio_mes,
		avisar_monto = v_config.avisar_monto,
		avisar_pago_enviado = v_config.avisar_pago_enviado,
		avisar_pago_confirmado = v_config.avisar_pago_confirmado,
		avisar_recaudacion_completa = v_config.avisar_recaudacion_completa,
		avisar_pago_proveedor = v_config.avisar_pago_proveedor,
		avisar_cambios_recibo = v_config.avisar_cambios_recibo,
		avisar_pendientes_admin = v_config.avisar_pendientes_admin,
		hora_pendientes_admin = v_config.hora_pendientes_admin,
		resumen_semanal = v_config.resumen_semanal,
		dia_resumen = v_config.dia_resumen,
		hora_resumen = v_config.hora_resumen,
		avisar_cierre_mes = v_config.avisar_cierre_mes,
		mencionar_integrantes = v_config.mencionar_integrantes,
		lenguaje_natural = v_config.lenguaje_natural,
		updated_at = now(),
		updated_by = v_usuario_id
	where familia_id = p_familia_id;

	if not v_config.avisos_activos then
		update public.avisos_whatsapp
		set estado = 'EXPIRADO',
			bloqueado_hasta = null
		where familia_id = p_familia_id
			and estado = 'PENDIENTE';
	end if;
end;
$$;

create or replace function app_private.whatsapp_heartbeat_impl(p_version text)
returns void
language sql
security definer
set search_path = ''
as $$
	update public.whatsapp_sistema
	set ultimo_heartbeat_at = now(),
		version_bot = left(nullif(trim(coalesce(p_version, '')), ''), 40),
		updated_at = now()
	where id = 1;
$$;

create or replace function app_private.whatsapp_grupo_salida_impl(p_grupo_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_familia_id uuid;
begin
	if nullif(trim(coalesce(p_grupo_id, '')), '') is null then
		return;
	end if;

	delete from public.whatsapp_vinculos
	where tipo = 'GRUPO'
		and whatsapp_id = p_grupo_id
	returning familia_id into v_familia_id;

	if v_familia_id is not null then
		update public.avisos_whatsapp
		set estado = 'EXPIRADO',
			bloqueado_hasta = null
		where familia_id = v_familia_id
			and estado = 'PENDIENTE';
	end if;
end;
$$;

create or replace function app_private.whatsapp_cmd_vincular(
	p_grupo_id text,
	p_remitente_ids text[],
	p_argumento text,
	p_tipo public.tipo_vinculo_whatsapp,
	p_familia_grupo_id uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_codigo text := upper(trim(coalesce(p_argumento, '')));
	v_principal text := nullif(trim(coalesce(p_remitente_ids[1], '')), '');
	v_alterno text;
	v_vinculo public.whatsapp_vinculos%rowtype;
	v_familia_nombre text;
	v_miembro public.miembros_familia%rowtype;
	v_nombre text;
begin
	v_alterno := nullif(nullif(trim(coalesce(p_remitente_ids[2], '')), ''), v_principal);

	if nullif(trim(coalesce(p_grupo_id, '')), '') is null or v_principal is null then
		raise exception 'Escribe el código dentro del grupo familiar.';
	end if;

	select *
	into v_vinculo
	from public.whatsapp_vinculos
	where codigo = v_codigo
		and codigo_expira_at > now()
	for update;

	if v_vinculo.id is null then
		raise exception 'Código inválido o vencido. Genera uno nuevo en FamiliaHub.';
	end if;

	if v_vinculo.tipo <> p_tipo then
		if v_vinculo.tipo = 'GRUPO' then
			raise exception 'Ese código es para /vincular-grupo.';
		end if;

		raise exception 'Ese código es para /vincular.';
	end if;

	select nombre
	into v_familia_nombre
	from public.familias
	where id = v_vinculo.familia_id;

	if p_tipo = 'GRUPO' then
		if exists (
			select 1
			from public.whatsapp_vinculos
			where tipo = 'GRUPO'
				and whatsapp_id = p_grupo_id
				and familia_id <> v_vinculo.familia_id
		) then
			raise exception 'Este grupo ya está vinculado a otra familia.';
		end if;

		update public.whatsapp_vinculos
		set whatsapp_id = p_grupo_id,
			vinculado_at = now(),
			codigo = null,
			codigo_expira_at = null,
			updated_at = now()
		where id = v_vinculo.id;

		perform app_private.whatsapp_asegurar_configuracion(v_vinculo.familia_id);

		return 'Listo. Este grupo quedó vinculado a la familia ' || v_familia_nombre || '. Escriban /ayuda para ver lo que puedo hacer.';
	end if;

	if p_familia_grupo_id is distinct from v_vinculo.familia_id then
		raise exception 'Usa el código en el grupo vinculado a tu familia.';
	end if;

	if exists (
		select 1
		from public.whatsapp_vinculos
		where familia_id = v_vinculo.familia_id
			and tipo = 'INTEGRANTE'
			and miembro_id <> v_vinculo.miembro_id
			and (
				whatsapp_id = any(p_remitente_ids)
				or whatsapp_id_alt = any(p_remitente_ids)
			)
	) then
		raise exception 'Este WhatsApp ya está vinculado a otro integrante.';
	end if;

	select *
	into v_miembro
	from public.miembros_familia
	where id = v_vinculo.miembro_id;

	if v_miembro.estado is distinct from 'ACTIVO' then
		raise exception 'Tu acceso a la familia no está activo.';
	end if;

	select coalesce(nullif(trim(nombre), ''), 'Integrante')
	into v_nombre
	from public.perfiles
	where id = v_miembro.usuario_id;

	update public.whatsapp_vinculos
	set whatsapp_id = v_principal,
		whatsapp_id_alt = v_alterno,
		vinculado_at = now(),
		codigo = null,
		codigo_expira_at = null,
		updated_at = now()
	where id = v_vinculo.id;

	return 'Listo, ' || coalesce(v_nombre, 'Integrante') || '. Tu WhatsApp quedó vinculado.';
end;
$$;

create or replace function app_private.whatsapp_cmd_desvincular(p_miembro_id uuid, p_nombre text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
	delete from public.whatsapp_vinculos
	where miembro_id = p_miembro_id
		and tipo = 'INTEGRANTE';

	return 'Listo, ' || coalesce(p_nombre, 'Integrante') || '. Tu WhatsApp ya no está vinculado.';
end;
$$;

create or replace function app_private.whatsapp_cmd_ayuda()
returns text
language sql
immutable
set search_path = ''
as $$
	select array_to_string(array[
		'🏠 *FamiliaHub* — esto puedo hacer',
		'/deuda — cuánto debes este mes',
		'/vence — vencidos y próximos 7 días',
		'/recibos — recibos del mes',
		'/recibo luz — detalle de un recibo',
		'/pendientes — quién falta aportar',
		'/resumen — cómo va el mes',
		'/pagar — cómo pagar',
		'/yo — tu vínculo',
		'/vincular CÓDIGO — vincular tu WhatsApp',
		'/desvincular — quitar tu vínculo',
		'Administradores: /porvalidar, /avisos estado, /avisos pausar, /avisos reanudar'
	], E'\n');
$$;

create or replace function app_private.whatsapp_cmd_yo(
	p_nombre text,
	p_rol public.rol_familia,
	p_familia_nombre text
)
returns text
language sql
immutable
set search_path = ''
as $$
	select case
		when p_nombre is null then 'Aún no vinculas tu WhatsApp. En FamiliaHub ve a Perfil > WhatsApp, genera tu código y escribe aquí /vincular CÓDIGO.'
		else 'Estás vinculado como ' || p_nombre
			|| ' (' || case when p_rol = 'ADMINISTRADOR' then 'Administrador' else 'Integrante' end || ')'
			|| ' en la familia ' || p_familia_nombre || '.'
	end;
$$;

create or replace function app_private.whatsapp_remitentes(p_remitente_ids text[])
returns text[]
language sql
immutable
set search_path = ''
as $$
	select coalesce(array_agg(ids.id order by ids.orden), '{}'::text[])
	from (
		select distinct on (trim(r.id)) trim(r.id) as id, r.orden
		from unnest(coalesce(p_remitente_ids, '{}'::text[])) with ordinality as r(id, orden)
		where nullif(trim(r.id), '') is not null
		order by trim(r.id), r.orden
		limit 5
	) ids;
$$;

create or replace function app_private.whatsapp_respuesta(p_texto text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
	select case
		when p_texto is null then null
		else jsonb_build_object(
			'texto', app_private.whatsapp_recortar(p_texto),
			'menciones', '[]'::jsonb
		)
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

	if v_comando = 'desvincular' and v_ctx.miembro_id is null then
		return app_private.whatsapp_respuesta(
			'Aún no vinculas tu WhatsApp. En FamiliaHub ve a Perfil > WhatsApp, genera tu código y escribe aquí /vincular CÓDIGO.'
		);
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

create or replace function public.generar_codigo_whatsapp(
	p_familia_id uuid,
	p_tipo public.tipo_vinculo_whatsapp
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
	select app_private.generar_codigo_whatsapp_impl(p_familia_id, p_tipo);
$$;

create or replace function public.desvincular_whatsapp(
	p_familia_id uuid,
	p_tipo public.tipo_vinculo_whatsapp
)
returns void
language sql
security invoker
set search_path = ''
as $$
	select app_private.desvincular_whatsapp_impl(p_familia_id, p_tipo);
$$;

create or replace function public.obtener_estado_whatsapp(p_familia_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
	select app_private.obtener_estado_whatsapp_impl(p_familia_id);
$$;

create or replace function public.guardar_configuracion_whatsapp(
	p_familia_id uuid,
	p_configuracion jsonb
)
returns void
language sql
security invoker
set search_path = ''
as $$
	select app_private.guardar_configuracion_whatsapp_impl(p_familia_id, p_configuracion);
$$;

create or replace function public.whatsapp_procesar_comando(
	p_grupo_id text,
	p_remitente_ids text[],
	p_comando text,
	p_argumento text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
	select app_private.whatsapp_procesar_comando_impl(p_grupo_id, p_remitente_ids, p_comando, p_argumento);
$$;

create or replace function public.whatsapp_grupo_salida(p_grupo_id text)
returns void
language sql
security invoker
set search_path = ''
as $$
	select app_private.whatsapp_grupo_salida_impl(p_grupo_id);
$$;

create or replace function public.whatsapp_heartbeat(p_version text)
returns void
language sql
security invoker
set search_path = ''
as $$
	select app_private.whatsapp_heartbeat_impl(p_version);
$$;

revoke all on function app_private.whatsapp_ahora_local(uuid) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_monto(numeric, char) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_fecha(date) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_mes(smallint, smallint) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_normalizar(text) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_recortar(text, integer) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_lista(text[], integer) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_periodo_actual(uuid) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_contexto(text, text[]) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_mencion(uuid, uuid, text) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_generar_codigo() from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_asegurar_configuracion(uuid) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_configuracion_json(public.whatsapp_configuracion) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_config_booleano(jsonb, text, boolean) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_config_entero(jsonb, text, smallint, integer, integer) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_config_hora(jsonb, text, time) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_config_dias(jsonb, text, smallint[]) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_limpiar_vinculo_miembro() from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_cmd_vincular(text, text[], text, public.tipo_vinculo_whatsapp, uuid) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_cmd_desvincular(uuid, text) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_cmd_ayuda() from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_cmd_yo(text, public.rol_familia, text) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_remitentes(text[]) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_respuesta(text) from public, anon, authenticated, service_role;

revoke all on function app_private.generar_codigo_whatsapp_impl(uuid, public.tipo_vinculo_whatsapp) from public, anon;
revoke all on function app_private.desvincular_whatsapp_impl(uuid, public.tipo_vinculo_whatsapp) from public, anon;
revoke all on function app_private.obtener_estado_whatsapp_impl(uuid) from public, anon;
revoke all on function app_private.guardar_configuracion_whatsapp_impl(uuid, jsonb) from public, anon;
grant execute on function app_private.generar_codigo_whatsapp_impl(uuid, public.tipo_vinculo_whatsapp) to authenticated;
grant execute on function app_private.desvincular_whatsapp_impl(uuid, public.tipo_vinculo_whatsapp) to authenticated;
grant execute on function app_private.obtener_estado_whatsapp_impl(uuid) to authenticated;
grant execute on function app_private.guardar_configuracion_whatsapp_impl(uuid, jsonb) to authenticated;

revoke all on function public.generar_codigo_whatsapp(uuid, public.tipo_vinculo_whatsapp) from public, anon;
revoke all on function public.desvincular_whatsapp(uuid, public.tipo_vinculo_whatsapp) from public, anon;
revoke all on function public.obtener_estado_whatsapp(uuid) from public, anon;
revoke all on function public.guardar_configuracion_whatsapp(uuid, jsonb) from public, anon;
grant execute on function public.generar_codigo_whatsapp(uuid, public.tipo_vinculo_whatsapp) to authenticated;
grant execute on function public.desvincular_whatsapp(uuid, public.tipo_vinculo_whatsapp) to authenticated;
grant execute on function public.obtener_estado_whatsapp(uuid) to authenticated;
grant execute on function public.guardar_configuracion_whatsapp(uuid, jsonb) to authenticated;

revoke all on function app_private.whatsapp_procesar_comando_impl(text, text[], text, text) from public, anon, authenticated;
revoke all on function app_private.whatsapp_grupo_salida_impl(text) from public, anon, authenticated;
revoke all on function app_private.whatsapp_heartbeat_impl(text) from public, anon, authenticated;
grant execute on function app_private.whatsapp_procesar_comando_impl(text, text[], text, text) to service_role;
grant execute on function app_private.whatsapp_grupo_salida_impl(text) to service_role;
grant execute on function app_private.whatsapp_heartbeat_impl(text) to service_role;

revoke all on function public.whatsapp_procesar_comando(text, text[], text, text) from public, anon, authenticated;
revoke all on function public.whatsapp_grupo_salida(text) from public, anon, authenticated;
revoke all on function public.whatsapp_heartbeat(text) from public, anon, authenticated;
grant execute on function public.whatsapp_procesar_comando(text, text[], text, text) to service_role;
grant execute on function public.whatsapp_grupo_salida(text) to service_role;
grant execute on function public.whatsapp_heartbeat(text) to service_role;
