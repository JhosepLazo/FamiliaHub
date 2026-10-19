create or replace function app_private.whatsapp_encolar(
	p_familia_id uuid,
	p_tipo public.tipo_aviso_whatsapp,
	p_clave text,
	p_recibo_id uuid,
	p_texto text,
	p_menciones text[],
	p_expira_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
	if nullif(trim(coalesce(p_texto, '')), '') is null
		or nullif(trim(coalesce(p_clave, '')), '') is null
		or p_expira_at is null
		or p_expira_at <= now()
	then
		return;
	end if;

	if not exists (
		select 1
		from public.whatsapp_vinculos g
		inner join public.whatsapp_configuracion c on c.familia_id = g.familia_id
		where g.familia_id = p_familia_id
			and g.tipo = 'GRUPO'
			and g.whatsapp_id is not null
			and c.avisos_activos
	) then
		return;
	end if;

	-- created_at con clock_timestamp() conserva el orden de inserción dentro de una misma ejecución.
	insert into public.avisos_whatsapp (
		familia_id,
		tipo,
		clave,
		recibo_id,
		texto,
		menciones,
		expira_at,
		created_at
	)
	values (
		p_familia_id,
		p_tipo,
		p_clave,
		p_recibo_id,
		app_private.whatsapp_recortar(trim(p_texto)),
		coalesce(
			array(
				select distinct trim(m)
				from unnest(coalesce(p_menciones, '{}'::text[])) m
				where nullif(trim(m), '') is not null
			),
			'{}'::text[]
		),
		p_expira_at,
		clock_timestamp()
	)
	on conflict (clave) do nothing;
end;
$$;

create or replace function app_private.whatsapp_grupo_vinculado_at(p_familia_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
	select g.vinculado_at
	from public.whatsapp_vinculos g
	where g.familia_id = p_familia_id
		and g.tipo = 'GRUPO'
		and g.whatsapp_id is not null;
$$;

create or replace function app_private.whatsapp_menciones_admins(p_familia_id uuid)
returns table (
	texto text,
	menciones text[],
	cantidad integer
)
language sql
stable
security definer
set search_path = ''
as $$
	select
		string_agg(men.texto, ', ' order by m.joined_at, m.id),
		coalesce(array_agg(men.jid order by m.joined_at, m.id) filter (where men.jid is not null), '{}'::text[]),
		count(*)::integer
	from public.miembros_familia m
	left join public.perfiles per on per.id = m.usuario_id
	cross join lateral app_private.whatsapp_mencion(m.familia_id, m.id, coalesce(nullif(trim(per.nombre), ''), 'Integrante')) men
	where m.familia_id = p_familia_id
		and m.rol = 'ADMINISTRADOR'
		and m.estado = 'ACTIVO';
$$;

create or replace function app_private.whatsapp_pendientes_recibo(p_recibo_id uuid, p_moneda char(3))
returns table (
	texto text,
	menciones text[],
	falta numeric
)
language sql
stable
security definer
set search_path = ''
as $$
	select
		string_agg(
			case
				when q.estado = 'POR_VALIDAR' then q.nombre_miembro || ' ' || app_private.whatsapp_monto(q.saldo_pendiente, p_moneda) || ' (en validación)'
				else men.texto || ' ' || app_private.whatsapp_monto(q.saldo_pendiente, p_moneda)
			end,
			' · '
			order by q.saldo_pendiente desc, q.nombre_miembro
		),
		coalesce(array_agg(men.jid) filter (where men.jid is not null and q.estado <> 'POR_VALIDAR'), '{}'::text[]),
		coalesce(sum(q.saldo_pendiente), 0)
	from public.cuotas q
	cross join lateral app_private.whatsapp_mencion(q.familia_id, q.miembro_id, q.nombre_miembro) men
	where q.recibo_id = p_recibo_id
		and q.estado <> 'ANULADA'
		and q.saldo_pendiente > 0;
$$;

create or replace function app_private.whatsapp_texto_reparto(p_recibo_id uuid, p_moneda char(3))
returns text
language sql
stable
security definer
set search_path = ''
as $$
	select app_private.whatsapp_lista(
		array_agg(
			'• ' || q.nombre_miembro || ' ' || app_private.whatsapp_monto(q.monto_asignado, p_moneda)
			order by q.created_at, q.nombre_miembro
		)
	)
	from public.cuotas q
	where q.recibo_id = p_recibo_id
		and q.estado <> 'ANULADA';
$$;

create or replace function app_private.whatsapp_texto_monto(
	p_recibo public.recibos,
	p_moneda char(3),
	p_corregido boolean
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
	select array_to_string(array[
		case
			when p_corregido then '✏️ *Se corrigió ' || (p_recibo).nombre_concepto || ':* '
			else app_private.whatsapp_emoji_servicio((p_recibo).tipo_servicio) || ' *Llegó ' || (p_recibo).nombre_concepto || ':* '
		end || app_private.whatsapp_monto((p_recibo).monto_total, p_moneda),
		case
			when coalesce((p_recibo).fecha_limite_aporte, (p_recibo).fecha_vencimiento) is not null
				then 'Aportar hasta: ' || app_private.whatsapp_fecha(coalesce((p_recibo).fecha_limite_aporte, (p_recibo).fecha_vencimiento))
		end,
		'A cada uno le toca:',
		app_private.whatsapp_texto_reparto((p_recibo).id, p_moneda)
	], E'\n');
$$;

create or replace function app_private.whatsapp_texto_inicio_mes(p_periodo public.periodos, p_moneda char(3))
returns text
language sql
stable
security definer
set search_path = ''
as $$
	select case
		when x.lineas is null then null
		else '🗓️ *' || app_private.whatsapp_mes((p_periodo).anio, (p_periodo).mes) || '* — recibos del mes'
			|| E'\n' || app_private.whatsapp_lista(x.lineas)
			|| E'\n' || 'Les aviso cuando llegue cada monto y antes de cada fecha.'
	end
	from (
		select array_agg(
			'• ' || r.nombre_concepto || ': '
			|| case
				when r.monto_total is null then 'esperando monto'
				else app_private.whatsapp_monto(r.monto_total, p_moneda)
					|| case
						when coalesce(r.fecha_limite_aporte, r.fecha_vencimiento) is not null
							then ' · aportar hasta ' || app_private.whatsapp_fecha(coalesce(r.fecha_limite_aporte, r.fecha_vencimiento))
						else ''
					end
			end
			order by r.fecha_limite_aporte asc nulls last, r.created_at
		) as lineas
		from public.recibos r
		where r.periodo_id = (p_periodo).id
			and r.estado <> 'ANULADO'
	) x;
$$;

create or replace function app_private.whatsapp_aviso_pago_familiar(
	p_pago public.pagos_familiares,
	p_tipo public.tipo_aviso_whatsapp
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_config public.whatsapp_configuracion%rowtype;
	v_moneda char(3);
	v_momento timestamptz;
	v_vinculado_at timestamptz;
	v_recibos text;
	v_detalle text;
	v_asignaciones integer;
	v_recibo_id uuid;
	v_mencion_texto text;
	v_mencion_jids text[];
	v_mencion_cantidad integer;
	v_texto text;
begin
	select *
	into v_config
	from public.whatsapp_configuracion
	where familia_id = (p_pago).familia_id;

	if v_config.familia_id is null or not v_config.avisos_activos then
		return;
	end if;

	if p_tipo = 'PAGO_ENVIADO' and not v_config.avisar_pago_enviado then
		return;
	end if;

	if p_tipo = 'PAGO_CONFIRMADO' and not v_config.avisar_pago_confirmado then
		return;
	end if;

	v_momento := case
		when p_tipo = 'PAGO_ENVIADO' then coalesce((p_pago).enviado_at, (p_pago).updated_at)
		else coalesce((p_pago).validado_at, (p_pago).updated_at)
	end;

	v_vinculado_at := app_private.whatsapp_grupo_vinculado_at((p_pago).familia_id);

	if v_vinculado_at is null or v_momento < v_vinculado_at or v_momento < now() - interval '12 hours' then
		return;
	end if;

	select moneda
	into v_moneda
	from public.familias
	where id = (p_pago).familia_id;

	select
		string_agg(distinct r.nombre_concepto, ', '),
		string_agg(r.nombre_concepto || ' ' || app_private.whatsapp_monto(pa.monto, v_moneda), ', ' order by r.nombre_concepto),
		count(*)::integer,
		case when count(distinct pa.recibo_id) = 1 then min(pa.recibo_id::text)::uuid end
	into v_recibos, v_detalle, v_asignaciones, v_recibo_id
	from public.pago_asignaciones pa
	inner join public.recibos r on r.id = pa.recibo_id
	where pa.pago_id = (p_pago).id;

	if p_tipo = 'PAGO_ENVIADO' then
		if (p_pago).responsable_receptor_miembro_id is not null then
			select
				men.texto,
				case when men.jid is null then '{}'::text[] else array[men.jid] end,
				1
			into v_mencion_texto, v_mencion_jids, v_mencion_cantidad
			from public.miembros_familia m
			left join public.perfiles per on per.id = m.usuario_id
			cross join lateral app_private.whatsapp_mencion(m.familia_id, m.id, coalesce(nullif(trim(per.nombre), ''), 'Integrante')) men
			where m.id = (p_pago).responsable_receptor_miembro_id;
		end if;

		if v_mencion_texto is null then
			select texto, menciones, cantidad
			into v_mencion_texto, v_mencion_jids, v_mencion_cantidad
			from app_private.whatsapp_menciones_admins((p_pago).familia_id);
		end if;

		v_texto := '📥 ' || (p_pago).pagador_nombre_snapshot || ' registró un pago de '
			|| app_private.whatsapp_monto((p_pago).monto_total, v_moneda)
			|| case when v_recibos is not null then ' (' || v_recibos || ')' else '' end || '.'
			|| E'\n' || coalesce(v_mencion_texto, 'Administradores')
			|| case when coalesce(v_mencion_cantidad, 1) > 1 then ', revísenlo' else ', revísalo' end
			|| ' en FamiliaHub: {APP_URL}/pagos';

		perform app_private.whatsapp_encolar(
			(p_pago).familia_id,
			'PAGO_ENVIADO',
			'PAGO_ENVIADO:' || (p_pago).id,
			v_recibo_id,
			v_texto,
			coalesce(v_mencion_jids, '{}'::text[]),
			v_momento + interval '12 hours'
		);

		return;
	end if;

	v_texto := '✅ *' || (p_pago).pagador_nombre_snapshot || '* pagó '
		|| app_private.whatsapp_monto((p_pago).monto_total, v_moneda)
		|| case
			when v_asignaciones > 1 then ' · ' || v_detalle
			when v_recibos is not null then ' · ' || v_recibos
			else ''
		end;

	perform app_private.whatsapp_encolar(
		(p_pago).familia_id,
		'PAGO_CONFIRMADO',
		'PAGO_CONFIRMADO:' || (p_pago).id,
		v_recibo_id,
		v_texto,
		'{}'::text[],
		v_momento + interval '12 hours'
	);
end;
$$;

create or replace function app_private.whatsapp_aviso_evento(p_evento public.eventos_financieros)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_config public.whatsapp_configuracion%rowtype;
	v_vinculado_at timestamptz;
	v_moneda char(3);
	v_recibo public.recibos%rowtype;
	v_aporte public.aportes%rowtype;
	v_pago_proveedor public.pagos_proveedor%rowtype;
	v_pagador text;
	v_admins record;
	v_expira timestamptz := (p_evento).created_at + interval '12 hours';
	v_clave text := 'EVENTO:' || (p_evento).id;
	v_texto text;
begin
	if (p_evento).created_at < now() - interval '12 hours' then
		return;
	end if;

	select *
	into v_config
	from public.whatsapp_configuracion
	where familia_id = (p_evento).familia_id;

	if v_config.familia_id is null or not v_config.avisos_activos then
		return;
	end if;

	v_vinculado_at := app_private.whatsapp_grupo_vinculado_at((p_evento).familia_id);

	if v_vinculado_at is null or (p_evento).created_at < v_vinculado_at then
		return;
	end if;

	select moneda
	into v_moneda
	from public.familias
	where id = (p_evento).familia_id;

	if (p_evento).evento in ('MONTO_CONFIRMADO', 'MONTO_CORREGIDO') then
		if not v_config.avisar_monto then
			return;
		end if;

		select *
		into v_recibo
		from public.recibos
		where id = (p_evento).entidad_id;

		if v_recibo.id is null or v_recibo.estado = 'ANULADO' or v_recibo.monto_total is null then
			return;
		end if;

		perform app_private.whatsapp_encolar(
			(p_evento).familia_id,
			'RECIBO_MONTO',
			v_clave,
			v_recibo.id,
			app_private.whatsapp_texto_monto(v_recibo, v_moneda, (p_evento).evento = 'MONTO_CORREGIDO'),
			'{}'::text[],
			v_expira
		);

		return;
	end if;

	if (p_evento).evento = 'PAGO_PROVEEDOR_REGISTRADO' then
		if not v_config.avisar_pago_proveedor then
			return;
		end if;

		select *
		into v_pago_proveedor
		from public.pagos_proveedor
		where id = (p_evento).entidad_id;

		if v_pago_proveedor.id is null or v_pago_proveedor.estado <> 'CONFIRMADO' then
			return;
		end if;

		select *
		into v_recibo
		from public.recibos
		where id = v_pago_proveedor.recibo_id;

		perform app_private.whatsapp_encolar(
			(p_evento).familia_id,
			'PAGO_PROVEEDOR',
			v_clave,
			v_recibo.id,
			'🏁 *' || v_recibo.nombre_concepto || '* ya se pagó a la empresa ('
				|| app_private.whatsapp_monto(v_pago_proveedor.monto, v_moneda) || ').',
			'{}'::text[],
			v_expira
		);

		return;
	end if;

	if (p_evento).evento in ('VENCIMIENTO_ACTUALIZADO', 'DISTRIBUCION_AJUSTADA', 'RECIBO_ANULADO') then
		if not v_config.avisar_cambios_recibo then
			return;
		end if;

		select *
		into v_recibo
		from public.recibos
		where id = (p_evento).entidad_id;

		if v_recibo.id is null then
			return;
		end if;

		if (p_evento).evento = 'RECIBO_ANULADO' then
			-- Sin recibo_id: al tomar avisos se expiran los de recibos anulados, y este aviso debe salir igual.
			perform app_private.whatsapp_encolar(
				(p_evento).familia_id,
				'RECIBO_ACTUALIZADO',
				v_clave,
				null,
				'🚫 *' || v_recibo.nombre_concepto || '* fue anulado. Ya no hay que aportar.',
				'{}'::text[],
				v_expira
			);

			return;
		end if;

		if v_recibo.estado = 'ANULADO' then
			return;
		end if;

		if (p_evento).evento = 'VENCIMIENTO_ACTUALIZADO' then
			v_texto := '📅 *' || v_recibo.nombre_concepto || ':* nueva fecha de vencimiento '
				|| coalesce(app_private.whatsapp_fecha(v_recibo.fecha_vencimiento), 'por definir')
				|| case
					when v_recibo.fecha_limite_aporte is not null
						and v_recibo.fecha_limite_aporte is distinct from v_recibo.fecha_vencimiento
						then ' · aportar hasta ' || app_private.whatsapp_fecha(v_recibo.fecha_limite_aporte)
					else ''
				end;
		else
			v_texto := '🔁 *' || v_recibo.nombre_concepto || ':* se ajustó el reparto'
				|| coalesce(E'\n' || app_private.whatsapp_texto_reparto(v_recibo.id, v_moneda), '');
		end if;

		perform app_private.whatsapp_encolar(
			(p_evento).familia_id,
			'RECIBO_ACTUALIZADO',
			v_clave,
			v_recibo.id,
			v_texto,
			'{}'::text[],
			v_expira
		);

		return;
	end if;

	if (p_evento).evento in ('APORTE_REGISTRADO', 'APORTE_CONFIRMADO') then
		select *
		into v_aporte
		from public.aportes
		where id = (p_evento).entidad_id;

		-- Los aportes ligados a un pago familiar se anuncian desde pagos_familiares para no duplicar avisos.
		if v_aporte.id is null or v_aporte.tipo = 'COBERTURA_ADELANTO' or v_aporte.pago_familiar_id is not null then
			return;
		end if;

		select *
		into v_recibo
		from public.recibos
		where id = v_aporte.recibo_id;

		select coalesce(nullif(trim(per.nombre), ''), 'Integrante')
		into v_pagador
		from public.miembros_familia m
		left join public.perfiles per on per.id = m.usuario_id
		where m.id = v_aporte.pagador_miembro_id;

		if (p_evento).evento = 'APORTE_REGISTRADO' and v_aporte.estado = 'POR_VALIDAR' then
			if not v_config.avisar_pago_enviado then
				return;
			end if;

			select *
			into v_admins
			from app_private.whatsapp_menciones_admins((p_evento).familia_id);

			perform app_private.whatsapp_encolar(
				(p_evento).familia_id,
				'PAGO_ENVIADO',
				'PAGO_ENVIADO:' || v_aporte.id,
				v_recibo.id,
				'📥 ' || coalesce(v_pagador, 'Integrante') || ' registró un pago de '
					|| app_private.whatsapp_monto(v_aporte.monto, v_moneda) || ' (' || v_recibo.nombre_concepto || ').'
					|| E'\n' || coalesce(v_admins.texto, 'Administradores')
					|| case when coalesce(v_admins.cantidad, 1) > 1 then ', revísenlo' else ', revísalo' end
					|| ' en FamiliaHub: {APP_URL}/pagos',
				coalesce(v_admins.menciones, '{}'::text[]),
				v_expira
			);

			return;
		end if;

		if v_aporte.estado = 'CONFIRMADO'
			and (
				(p_evento).evento = 'APORTE_CONFIRMADO'
				or (p_evento).detalle ->> 'estado' = 'CONFIRMADO'
			)
		then
			if not v_config.avisar_pago_confirmado then
				return;
			end if;

			perform app_private.whatsapp_encolar(
				(p_evento).familia_id,
				'PAGO_CONFIRMADO',
				'PAGO_CONFIRMADO:' || v_aporte.id,
				v_recibo.id,
				'✅ *' || coalesce(v_pagador, 'Integrante') || '* pagó '
					|| app_private.whatsapp_monto(v_aporte.monto, v_moneda) || ' · ' || v_recibo.nombre_concepto,
				'{}'::text[],
				v_expira
			);
		end if;
	end if;
end;
$$;

create or replace function app_private.whatsapp_procesar_eventos()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_sistema public.whatsapp_sistema%rowtype;
	v_ahora timestamptz := now();
	v_corte timestamptz := now() - interval '12 hours';
	v_desde_pagos timestamptz;
	v_ultimo bigint;
	v_evento public.eventos_financieros%rowtype;
	v_pago public.pagos_familiares%rowtype;
	v_recibo record;
begin
	select *
	into v_sistema
	from public.whatsapp_sistema
	where id = 1
	for update skip locked;

	-- Otra ejecución tiene el cursor tomado: esta termina sin hacer nada.
	if v_sistema.id is null then
		return;
	end if;

	v_ultimo := v_sistema.ultimo_evento_id;
	v_desde_pagos := v_sistema.ultima_revision_pagos_at - interval '10 minutes';

	for v_evento in
		select *
		from public.eventos_financieros
		where id > v_sistema.ultimo_evento_id
		order by id
		limit 500
	loop
		v_ultimo := v_evento.id;

		continue when v_evento.created_at < v_corte;

		begin
			perform app_private.whatsapp_aviso_evento(v_evento);
		exception
			when others then
				raise warning 'WhatsApp: no se pudo procesar el evento %: %', v_evento.id, sqlerrm;
		end;
	end loop;

	-- Una transacción puede confirmar un evento con id menor al cursor después de avanzarlo.
	-- Se revisan los eventos recientes ya cubiertos; la clave única de avisos_whatsapp evita duplicados.
	for v_evento in
		select *
		from public.eventos_financieros
		where id <= v_sistema.ultimo_evento_id
			and created_at > v_ahora - interval '10 minutes'
		order by id
	loop
		begin
			perform app_private.whatsapp_aviso_evento(v_evento);
		exception
			when others then
				raise warning 'WhatsApp: no se pudo revisar el evento %: %', v_evento.id, sqlerrm;
		end;
	end loop;

	for v_pago in
		select *
		from public.pagos_familiares pf
		where pf.estado = 'POR_VALIDAR'
			and coalesce(pf.enviado_at, pf.updated_at) > v_desde_pagos
			and coalesce(pf.enviado_at, pf.updated_at) > v_corte
		order by coalesce(pf.enviado_at, pf.updated_at), pf.id
	loop
		begin
			perform app_private.whatsapp_aviso_pago_familiar(v_pago, 'PAGO_ENVIADO');
		exception
			when others then
				raise warning 'WhatsApp: no se pudo avisar el pago enviado %: %', v_pago.id, sqlerrm;
		end;
	end loop;

	for v_pago in
		select *
		from public.pagos_familiares pf
		where pf.estado = 'CONFIRMADO'
			and coalesce(pf.validado_at, pf.updated_at) > v_desde_pagos
			and coalesce(pf.validado_at, pf.updated_at) > v_corte
		order by coalesce(pf.validado_at, pf.updated_at), pf.id
	loop
		begin
			perform app_private.whatsapp_aviso_pago_familiar(v_pago, 'PAGO_CONFIRMADO');
		exception
			when others then
				raise warning 'WhatsApp: no se pudo avisar el pago confirmado %: %', v_pago.id, sqlerrm;
		end;
	end loop;

	for v_recibo in
		select r.id, r.familia_id, r.nombre_concepto, r.monto_total, f.moneda
		from public.recibos r
		inner join public.familias f on f.id = r.familia_id
		inner join public.whatsapp_vinculos g
			on g.familia_id = r.familia_id
			and g.tipo = 'GRUPO'
			and g.whatsapp_id is not null
		inner join public.whatsapp_configuracion c
			on c.familia_id = r.familia_id
			and c.avisos_activos
			and c.avisar_recaudacion_completa
		where r.estado_recaudacion = 'COMPLETA'
			and r.estado <> 'ANULADO'
			and r.monto_total is not null
			and r.updated_at > v_corte
			and r.updated_at >= g.vinculado_at
			and not exists (
				select 1
				from public.avisos_whatsapp a
				where a.clave = 'RECAUDACION_COMPLETA:' || r.id
			)
		order by r.updated_at, r.id
	loop
		begin
			perform app_private.whatsapp_encolar(
				v_recibo.familia_id,
				'RECAUDACION_COMPLETA',
				'RECAUDACION_COMPLETA:' || v_recibo.id,
				v_recibo.id,
				'🎉 *' || v_recibo.nombre_concepto || ':* ya se recaudó todo ('
					|| app_private.whatsapp_monto(v_recibo.monto_total, v_recibo.moneda) || '). ¡Gracias, familia!',
				'{}'::text[],
				v_ahora + interval '12 hours'
			);
		exception
			when others then
				raise warning 'WhatsApp: no se pudo avisar la recaudación completa %: %', v_recibo.id, sqlerrm;
		end;
	end loop;

	update public.whatsapp_sistema
	set ultimo_evento_id = greatest(ultimo_evento_id, v_ultimo),
		ultima_revision_pagos_at = v_ahora,
		updated_at = now()
	where id = 1;
end;
$$;

create or replace function app_private.whatsapp_generar_avisos_familia(p_familia_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_familia public.familias%rowtype;
	v_config public.whatsapp_configuracion%rowtype;
	v_vinculado_at timestamptz;
	v_local timestamp;
	v_hoy date;
	v_hora time;
	v_fin_dia timestamptz;
	v_periodo public.periodos%rowtype;
	v_recibo record;
	v_pendientes record;
	v_dias integer;
	v_texto text;
	v_lineas text[];
	v_menciones text[];
	v_total integer;
	v_pagos integer;
	v_responsables record;
	v_admins record;
	v_cierre record;
begin
	select *
	into v_familia
	from public.familias
	where id = p_familia_id;

	select *
	into v_config
	from public.whatsapp_configuracion
	where familia_id = p_familia_id;

	v_vinculado_at := app_private.whatsapp_grupo_vinculado_at(p_familia_id);

	if v_familia.id is null or v_config.familia_id is null or not v_config.avisos_activos or v_vinculado_at is null then
		return;
	end if;

	v_local := timezone(v_familia.zona_horaria, now());
	v_hoy := v_local::date;
	v_hora := v_local::time;

	if v_hora < v_config.hora_inicio_envio or v_hora >= v_config.hora_fin_envio then
		return;
	end if;

	v_fin_dia := (v_hoy + 1)::timestamp at time zone v_familia.zona_horaria;

	select *
	into v_periodo
	from public.periodos
	where id = app_private.whatsapp_periodo_actual(p_familia_id);

	if v_config.avisar_inicio_mes and v_periodo.id is not null and extract(day from v_hoy) between 1 and 3 then
		perform app_private.whatsapp_encolar(
			p_familia_id,
			'INICIO_MES',
			'INICIO_MES:' || v_periodo.id,
			null,
			app_private.whatsapp_texto_inicio_mes(v_periodo, v_familia.moneda),
			'{}'::text[],
			now() + interval '48 hours'
		);
	end if;

	for v_recibo in
		select
			r.*,
			coalesce(r.fecha_limite_aporte, r.fecha_vencimiento) as fecha_objetivo
		from public.recibos r
		inner join public.periodos p on p.id = r.periodo_id
		where r.familia_id = p_familia_id
			and (p.id = v_periodo.id or p.estado = 'ABIERTO')
			and r.estado in ('PENDIENTE', 'VENCIDO')
			and r.monto_total is not null
			and r.estado_recaudacion <> 'COMPLETA'
			and coalesce(r.fecha_limite_aporte, r.fecha_vencimiento) is not null
		order by fecha_objetivo, r.nombre_concepto
	loop
		v_dias := v_recibo.fecha_objetivo - v_hoy;

		select *
		into v_pendientes
		from app_private.whatsapp_pendientes_recibo(v_recibo.id, v_familia.moneda);

		if v_dias > 0 and v_dias = any(v_config.dias_aviso_previo) then
			perform app_private.whatsapp_encolar(
				p_familia_id,
				'POR_VENCER',
				'POR_VENCER:' || v_recibo.id || ':' || to_char(v_hoy, 'YYYY-MM-DD'),
				v_recibo.id,
				'⏰ *' || v_recibo.nombre_concepto || ':* '
					|| case when v_dias = 1 then 'falta 1 día' else 'faltan ' || v_dias::text || ' días' end
					|| ' para aportar (' || app_private.whatsapp_fecha(v_recibo.fecha_objetivo) || ')'
					|| E'\n' || 'Total ' || app_private.whatsapp_monto(v_recibo.monto_total, v_familia.moneda)
					|| ' · Falta ' || app_private.whatsapp_monto(v_pendientes.falta, v_familia.moneda)
					|| coalesce(E'\n' || 'Pendiente: ' || v_pendientes.texto, ''),
				v_pendientes.menciones,
				v_fin_dia
			);
		elsif v_dias = 0 and v_config.avisar_vence_hoy then
			perform app_private.whatsapp_encolar(
				p_familia_id,
				'VENCE_HOY',
				'VENCE_HOY:' || v_recibo.id,
				v_recibo.id,
				'⏰ *' || v_recibo.nombre_concepto || ':* hoy es el último día para aportar'
					|| E'\n' || 'Falta ' || app_private.whatsapp_monto(v_pendientes.falta, v_familia.moneda)
					|| coalesce(E'\n' || 'Pendiente: ' || v_pendientes.texto, ''),
				v_pendientes.menciones,
				v_fin_dia
			);
		elsif v_dias < 0
			and (
				-v_dias = 1
				or (v_config.frecuencia_vencidos_dias > 0 and (-v_dias - 1) % v_config.frecuencia_vencidos_dias = 0)
			)
		then
			perform app_private.whatsapp_encolar(
				p_familia_id,
				'VENCIDO',
				'VENCIDO:' || v_recibo.id || ':' || to_char(v_hoy, 'YYYY-MM-DD'),
				v_recibo.id,
				'⚠️ *' || v_recibo.nombre_concepto || ':* el plazo para aportar venció hace '
					|| case when -v_dias = 1 then '1 día' else (-v_dias)::text || ' días' end
					|| ' (' || app_private.whatsapp_fecha(v_recibo.fecha_objetivo) || ')'
					|| case
						when v_recibo.fecha_vencimiento is not null and v_recibo.fecha_vencimiento > v_recibo.fecha_objetivo then
							E'\n' || case
								when v_recibo.fecha_vencimiento >= v_hoy then 'El recibo vence el ' || app_private.whatsapp_fecha(v_recibo.fecha_vencimiento) || '.'
								else 'El recibo venció el ' || app_private.whatsapp_fecha(v_recibo.fecha_vencimiento) || '.'
							end
						else ''
					end
					|| E'\n' || 'Falta ' || app_private.whatsapp_monto(v_pendientes.falta, v_familia.moneda)
					|| coalesce(' · Pendiente: ' || v_pendientes.texto, ''),
				v_pendientes.menciones,
				v_fin_dia
			);
		end if;
	end loop;

	if v_config.avisar_pendientes_admin and v_hora >= v_config.hora_pendientes_admin then
		select
			(select count(*) from public.aportes a where a.familia_id = p_familia_id and a.estado = 'POR_VALIDAR')
			+ (select count(*) from public.pagos_familiares pf where pf.familia_id = p_familia_id and pf.estado = 'POR_VALIDAR')
		into v_pagos;

		select
			string_agg(men.texto, ', ' order by men.texto) as texto,
			coalesce(array_agg(men.jid) filter (where men.jid is not null), '{}'::text[]) as menciones
		into v_responsables
		from (
			select distinct pf.responsable_receptor_miembro_id as miembro_id
			from public.pagos_familiares pf
			where pf.familia_id = p_familia_id
				and pf.estado = 'POR_VALIDAR'
				and pf.responsable_receptor_miembro_id is not null
			union
			select m.id
			from public.miembros_familia m
			where m.familia_id = p_familia_id
				and m.rol = 'ADMINISTRADOR'
				and m.estado = 'ACTIVO'
				and (
					exists (select 1 from public.aportes a where a.familia_id = p_familia_id and a.estado = 'POR_VALIDAR')
					or exists (
						select 1
						from public.pagos_familiares pf
						where pf.familia_id = p_familia_id
							and pf.estado = 'POR_VALIDAR'
							and pf.responsable_receptor_miembro_id is null
					)
				)
		) responsables
		inner join public.miembros_familia m on m.id = responsables.miembro_id
		left join public.perfiles per on per.id = m.usuario_id
		cross join lateral app_private.whatsapp_mencion(m.familia_id, m.id, coalesce(nullif(trim(per.nombre), ''), 'Integrante')) men;

		select array_agg(x.linea order by x.orden, x.fecha, x.nombre)
		into v_lineas
		from (
			select 1 as orden, r.fecha_limite_aporte as fecha, r.nombre_concepto as nombre, '• ' || r.nombre_concepto || ': falta registrar el monto' as linea
			from public.recibos r
			where r.periodo_id = v_periodo.id and r.estado <> 'ANULADO' and r.estado = 'ESPERANDO_MONTO'
			union all
			select 2, r.fecha_limite_aporte, r.nombre_concepto, '• ' || r.nombre_concepto || ': falta la fecha de vencimiento'
			from public.recibos r
			where r.periodo_id = v_periodo.id
				and r.estado <> 'ANULADO'
				and r.monto_total is not null
				and r.tipo_vencimiento <> 'DIA_FIJO'
				and r.fecha_vencimiento is null
				and r.estado <> 'PAGADO'
			union all
			select 3, r.fecha_vencimiento, r.nombre_concepto, '• ' || r.nombre_concepto || ': vencido sin pagar a la empresa'
			from public.recibos r
			where r.periodo_id = v_periodo.id and r.estado = 'VENCIDO'
			union all
			select 4, r.fecha_limite_aporte, r.nombre_concepto, '• ' || r.nombre_concepto || ': recaudación atrasada'
			from public.recibos r
			where r.periodo_id = v_periodo.id
				and r.estado <> 'ANULADO'
				and r.estado_recaudacion <> 'COMPLETA'
				and r.fecha_limite_aporte < v_hoy
			union all
			select 5, r.fecha_limite_aporte, r.nombre_concepto, '• ' || r.nombre_concepto || ': requiere revisión'
			from public.recibos r
			where r.periodo_id = v_periodo.id and r.estado = 'REQUIERE_REVISION'
		) x;

		v_total := v_pagos + coalesce(cardinality(v_lineas), 0);

		if v_total > 0 then
			select *
			into v_admins
			from app_private.whatsapp_menciones_admins(p_familia_id);

			-- Si solo hay pagos por validar, basta con mencionar a sus responsables en esa línea.
			v_menciones := coalesce(v_responsables.menciones, '{}'::text[])
				|| case when v_lineas is not null then coalesce(v_admins.menciones, '{}'::text[]) else '{}'::text[] end;

			v_texto := array_to_string(array[
				'📋 *Pendientes de administración*',
				case
					when v_pagos > 0 then '• ' || v_pagos::text || case when v_pagos = 1 then ' pago por validar' else ' pagos por validar' end
						|| coalesce(' (' || v_responsables.texto || ')', '')
				end,
				app_private.whatsapp_lista(v_lineas, case when v_pagos > 0 then 9 else 10 end),
				case
					when v_lineas is null then 'Valídalos en FamiliaHub: {APP_URL}/pagos'
					else coalesce(v_admins.texto, 'Administradores')
						|| case when coalesce(v_admins.cantidad, 1) > 1 then ', revísenlo' else ', revísalo' end
						|| ' en FamiliaHub: {APP_URL}/inicio'
				end
			], E'\n');

			perform app_private.whatsapp_encolar(
				p_familia_id,
				'PENDIENTES_ADMIN',
				'PENDIENTES_ADMIN:' || p_familia_id || ':' || to_char(v_hoy, 'YYYY-MM-DD'),
				null,
				v_texto,
				v_menciones,
				v_fin_dia
			);
		end if;
	end if;

	if v_config.resumen_semanal
		and extract(dow from v_hoy) = v_config.dia_resumen
		and v_hora >= v_config.hora_resumen
	then
		perform app_private.whatsapp_encolar(
			p_familia_id,
			'RESUMEN_SEMANAL',
			'RESUMEN_SEMANAL:' || p_familia_id || ':' || to_char(v_hoy, 'IYYY') || '-' || to_char(v_hoy, 'IW'),
			null,
			app_private.whatsapp_texto_resumen(p_familia_id),
			'{}'::text[],
			v_fin_dia
		);
	end if;

	if v_config.avisar_cierre_mes then
		for v_cierre in
			select
				p.id,
				p.anio,
				p.mes,
				p.completado_at,
				count(r.id) filter (where r.estado = 'PAGADO') as pagados,
				coalesce(sum(r.monto_total) filter (where r.estado = 'PAGADO'), 0) as total
			from public.periodos p
			left join public.recibos r on r.periodo_id = p.id
			where p.familia_id = p_familia_id
				and p.estado = 'COMPLETADO'
				and p.completado_at > now() - interval '48 hours'
				and p.completado_at >= v_vinculado_at
			group by p.id, p.anio, p.mes, p.completado_at
		loop
			perform app_private.whatsapp_encolar(
				p_familia_id,
				'CIERRE_MES',
				'CIERRE_MES:' || v_cierre.id,
				null,
				'🏆 *' || app_private.whatsapp_mes(v_cierre.anio, v_cierre.mes) || ' cerrado.* Se '
					|| case when v_cierre.pagados = 1 then 'pagó 1 recibo' else 'pagaron ' || v_cierre.pagados::text || ' recibos' end
					|| ' por ' || app_private.whatsapp_monto(v_cierre.total, v_familia.moneda) || '. ¡Todo al día!',
				'{}'::text[],
				v_cierre.completado_at + interval '48 hours'
			);
		end loop;
	end if;
end;
$$;

create or replace function app_private.whatsapp_generar_avisos_programados()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_familia record;
begin
	for v_familia in
		select g.familia_id
		from public.whatsapp_vinculos g
		inner join public.familias f on f.id = g.familia_id
		where g.tipo = 'GRUPO'
			and g.whatsapp_id is not null
			and f.activo
		order by g.vinculado_at
	loop
		begin
			perform app_private.whatsapp_generar_avisos_familia(v_familia.familia_id);
		exception
			when others then
				raise warning 'WhatsApp: no se pudieron generar los avisos de la familia %: %', v_familia.familia_id, sqlerrm;
		end;
	end loop;

	update public.avisos_whatsapp
	set estado = 'EXPIRADO',
		bloqueado_hasta = null
	where estado = 'PENDIENTE'
		and expira_at <= now();

	delete from public.avisos_whatsapp
	where estado in ('ENVIADO', 'EXPIRADO', 'ERROR')
		and created_at < now() - interval '90 days';

	update public.whatsapp_vinculos
	set codigo = null,
		codigo_expira_at = null,
		updated_at = now()
	where codigo_expira_at <= now();
end;
$$;

create or replace function app_private.whatsapp_tomar_avisos_impl(p_limite smallint default 5)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_limite integer := greatest(1, least(coalesce(p_limite, 5), 20));
	v_resultado jsonb;
begin
	update public.avisos_whatsapp
	set estado = 'EXPIRADO',
		bloqueado_hasta = null
	where estado = 'PENDIENTE'
		and expira_at <= now();

	update public.avisos_whatsapp a
	set estado = 'EXPIRADO',
		bloqueado_hasta = null
	from public.recibos r
	where a.recibo_id = r.id
		and a.estado = 'PENDIENTE'
		and r.estado = 'ANULADO';

	update public.avisos_whatsapp a
	set estado = 'EXPIRADO',
		bloqueado_hasta = null
	from public.recibos r
	where a.recibo_id = r.id
		and a.estado = 'PENDIENTE'
		and a.tipo in ('POR_VENCER', 'VENCE_HOY', 'VENCIDO')
		and not (
			r.estado in ('PENDIENTE', 'VENCIDO')
			and r.monto_total is not null
			and r.estado_recaudacion <> 'COMPLETA'
			and coalesce(r.fecha_limite_aporte, r.fecha_vencimiento) is not null
		);

	update public.avisos_whatsapp a
	set estado = 'EXPIRADO',
		bloqueado_hasta = null
	where a.estado = 'PENDIENTE'
		and (
			not exists (
				select 1
				from public.whatsapp_vinculos g
				where g.familia_id = a.familia_id
					and g.tipo = 'GRUPO'
					and g.whatsapp_id is not null
			)
			or exists (
				select 1
				from public.whatsapp_configuracion c
				where c.familia_id = a.familia_id
					and not c.avisos_activos
			)
		);

	with candidatos as (
		select
			a.id,
			g.whatsapp_id as grupo_id
		from public.avisos_whatsapp a
		inner join public.whatsapp_vinculos g
			on g.familia_id = a.familia_id
			and g.tipo = 'GRUPO'
			and g.whatsapp_id is not null
		inner join public.whatsapp_configuracion c on c.familia_id = a.familia_id
		inner join public.familias f on f.id = a.familia_id
		where a.estado = 'PENDIENTE'
			and (a.bloqueado_hasta is null or a.bloqueado_hasta <= now())
			and timezone(f.zona_horaria, now())::time >= c.hora_inicio_envio
			and timezone(f.zona_horaria, now())::time < c.hora_fin_envio
		order by a.created_at, a.id
		limit v_limite
		for update of a skip locked
	),
	tomados as (
		update public.avisos_whatsapp a
		set bloqueado_hasta = now() + interval '5 minutes'
		from candidatos
		where a.id = candidatos.id
		returning a.id, candidatos.grupo_id, a.texto, a.menciones, a.created_at
	)
	select coalesce(
		jsonb_agg(
			jsonb_build_object(
				'id', tomados.id,
				'grupoId', tomados.grupo_id,
				'texto', tomados.texto,
				'menciones', to_jsonb(tomados.menciones)
			)
			order by tomados.created_at, tomados.id
		),
		'[]'::jsonb
	)
	into v_resultado
	from tomados;

	return v_resultado;
end;
$$;

create or replace function app_private.whatsapp_marcar_aviso_impl(
	p_aviso_id uuid,
	p_enviado boolean,
	p_error text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_aviso public.avisos_whatsapp%rowtype;
	v_intentos smallint;
begin
	select *
	into v_aviso
	from public.avisos_whatsapp
	where id = p_aviso_id
	for update;

	if v_aviso.id is null then
		raise exception 'Aviso no encontrado.';
	end if;

	if v_aviso.estado <> 'PENDIENTE' then
		return;
	end if;

	if coalesce(p_enviado, false) then
		update public.avisos_whatsapp
		set estado = 'ENVIADO',
			enviado_at = now(),
			bloqueado_hasta = null,
			error = null
		where id = p_aviso_id;

		return;
	end if;

	v_intentos := least(v_aviso.intentos + 1, 3);

	update public.avisos_whatsapp
	set intentos = v_intentos,
		error = left(coalesce(nullif(trim(p_error), ''), 'Error desconocido.'), 500),
		estado = case when v_intentos >= 3 then 'ERROR'::public.estado_aviso_whatsapp else 'PENDIENTE'::public.estado_aviso_whatsapp end,
		bloqueado_hasta = case when v_intentos >= 3 then null else now() + interval '2 minutes' end
	where id = p_aviso_id;
end;
$$;

create or replace function public.whatsapp_tomar_avisos(p_limite smallint default 5)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
	select app_private.whatsapp_tomar_avisos_impl(p_limite);
$$;

create or replace function public.whatsapp_marcar_aviso(
	p_aviso_id uuid,
	p_enviado boolean,
	p_error text
)
returns void
language sql
security invoker
set search_path = ''
as $$
	select app_private.whatsapp_marcar_aviso_impl(p_aviso_id, p_enviado, p_error);
$$;

revoke all on function app_private.whatsapp_encolar(uuid, public.tipo_aviso_whatsapp, text, uuid, text, text[], timestamptz) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_grupo_vinculado_at(uuid) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_menciones_admins(uuid) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_pendientes_recibo(uuid, char) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_texto_reparto(uuid, char) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_texto_monto(public.recibos, char, boolean) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_texto_inicio_mes(public.periodos, char) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_aviso_pago_familiar(public.pagos_familiares, public.tipo_aviso_whatsapp) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_aviso_evento(public.eventos_financieros) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_generar_avisos_familia(uuid) from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_procesar_eventos() from public, anon, authenticated, service_role;
revoke all on function app_private.whatsapp_generar_avisos_programados() from public, anon, authenticated, service_role;

revoke all on function app_private.whatsapp_tomar_avisos_impl(smallint) from public, anon, authenticated;
revoke all on function app_private.whatsapp_marcar_aviso_impl(uuid, boolean, text) from public, anon, authenticated;
grant execute on function app_private.whatsapp_tomar_avisos_impl(smallint) to service_role;
grant execute on function app_private.whatsapp_marcar_aviso_impl(uuid, boolean, text) to service_role;

revoke all on function public.whatsapp_tomar_avisos(smallint) from public, anon, authenticated;
revoke all on function public.whatsapp_marcar_aviso(uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.whatsapp_tomar_avisos(smallint) to service_role;
grant execute on function public.whatsapp_marcar_aviso(uuid, boolean, text) to service_role;

do $$
begin
	perform cron.unschedule('familiahub-whatsapp-eventos');
exception
	when others then
		null;
end
$$;

do $$
begin
	perform cron.unschedule('familiahub-whatsapp-programados');
exception
	when others then
		null;
end
$$;

select cron.schedule(
	'familiahub-whatsapp-eventos',
	'* * * * *',
	$$select app_private.whatsapp_procesar_eventos();$$
);

select cron.schedule(
	'familiahub-whatsapp-programados',
	'5 * * * *',
	$$select app_private.whatsapp_generar_avisos_programados();$$
);
