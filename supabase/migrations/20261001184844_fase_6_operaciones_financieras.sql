create or replace function app_private.guardar_concepto_servicio_fase6_impl(
	p_concepto_id uuid,
	p_familia_id uuid,
	p_categoria_id uuid,
	p_proveedor_id uuid,
	p_plantilla_id uuid,
	p_nombre text,
	p_frecuencia public.frecuencia_concepto,
	p_metodo_obtencion public.metodo_obtencion_monto,
	p_monto_fijo numeric,
	p_tipo_vencimiento public.tipo_vencimiento_concepto,
	p_dia_vencimiento smallint,
	p_tipo_distribucion public.tipo_distribucion_concepto,
	p_reparto_resto public.tipo_reparto_resto,
	p_fallback_manual boolean,
	p_cuenta jsonb,
	p_participantes jsonb,
	p_fecha_inicio_generacion date,
	p_dias_anticipacion_aporte smallint
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_concepto_id uuid;
begin
	if p_fecha_inicio_generacion is null then
		raise exception 'La fecha de inicio es obligatoria.';
	end if;

	if p_dias_anticipacion_aporte is null or p_dias_anticipacion_aporte < 0 or p_dias_anticipacion_aporte > 31 then
		raise exception 'Los días de anticipación deben estar entre 0 y 31.';
	end if;

	v_concepto_id := app_private.guardar_concepto_servicio_impl(
		p_concepto_id,
		p_familia_id,
		p_categoria_id,
		p_proveedor_id,
		p_plantilla_id,
		p_nombre,
		p_frecuencia,
		p_metodo_obtencion,
		p_monto_fijo,
		p_tipo_vencimiento,
		p_dia_vencimiento,
		p_tipo_distribucion,
		p_reparto_resto,
		p_fallback_manual,
		p_cuenta,
		p_participantes
	);

	update public.conceptos_pago
	set fecha_inicio_generacion = p_fecha_inicio_generacion,
		dias_anticipacion_aporte = p_dias_anticipacion_aporte,
		updated_at = now()
	where id = v_concepto_id;

	perform app_private.sincronizar_periodos_impl(
		p_familia_id,
		(timezone('America/Lima', now()))::date
	);

	return v_concepto_id;
end;
$$;

create or replace function app_private.sincronizar_periodo_actual_usuario_impl(p_familia_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
begin
	if v_usuario_id is null or not app_private.es_admin(p_familia_id, v_usuario_id) then
		raise exception 'Solo un administrador puede sincronizar el periodo.';
	end if;

	return app_private.sincronizar_periodos_impl(
		p_familia_id,
		(timezone('America/Lima', now()))::date
	);
end;
$$;

create or replace function app_private.confirmar_monto_recibo_impl(
	p_recibo_id uuid,
	p_monto numeric,
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
	v_vencimiento date;
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
		raise exception 'Solo un administrador puede confirmar el monto.';
	end if;

	if v_recibo.estado <> 'ESPERANDO_MONTO' then
		raise exception 'El recibo ya tiene un monto confirmado o no admite esta operación.';
	end if;

	if p_monto is null or p_monto <= 0 or round(p_monto, 2) <> p_monto then
		raise exception 'El monto debe ser mayor a cero y tener máximo dos decimales.';
	end if;

	if v_recibo.tipo_vencimiento = 'DIA_FIJO' then
		v_vencimiento := v_recibo.fecha_vencimiento;
	else
		if p_fecha_vencimiento is null then
			raise exception 'Indica la fecha de vencimiento del recibo.';
		end if;
		v_vencimiento := p_fecha_vencimiento;
	end if;

	update public.recibos
	set monto_base = p_monto,
		fecha_vencimiento = v_vencimiento,
		fecha_limite_aporte = case
			when v_vencimiento is null then null
			else v_vencimiento - dias_anticipacion_aporte
		end,
		estado = case
			when v_vencimiento is not null and v_vencimiento < v_fecha then 'VENCIDO'::public.estado_recibo
			else 'PENDIENTE'::public.estado_recibo
		end,
		monto_confirmado_at = now(),
		updated_at = now()
	where id = p_recibo_id;

	perform app_private.crear_cuotas_recibo(p_recibo_id);

	perform app_private.registrar_evento_financiero(
		v_recibo.familia_id,
		'RECIBO',
		p_recibo_id,
		'MONTO_CONFIRMADO',
		jsonb_build_object('monto', p_monto, 'fecha_vencimiento', v_vencimiento),
		v_usuario_id
	);
end;
$$;

create or replace function app_private.corregir_monto_recibo_impl(
	p_recibo_id uuid,
	p_nuevo_monto numeric,
	p_motivo text,
	p_fecha_vencimiento date default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_recibo public.recibos%rowtype;
	v_delta numeric;
	v_fecha date := (timezone('America/Lima', now()))::date;
	v_cuota record;
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
		raise exception 'Solo un administrador puede corregir el monto.';
	end if;

	if v_recibo.monto_total is null or v_recibo.estado in ('ANULADO', 'PAGADO') then
		raise exception 'El recibo no admite corrección de monto en su estado actual.';
	end if;

	if exists (
		select 1
		from public.pagos_proveedor
		where recibo_id = p_recibo_id
			and estado = 'CONFIRMADO'
	) then
		raise exception 'Anula primero el pago al proveedor antes de corregir el monto.';
	end if;

	if p_nuevo_monto is null or p_nuevo_monto <= 0 or round(p_nuevo_monto, 2) <> p_nuevo_monto then
		raise exception 'El nuevo monto debe ser mayor a cero y tener máximo dos decimales.';
	end if;

	if round(p_nuevo_monto, 2) = round(v_recibo.monto_total, 2) then
		raise exception 'El nuevo monto debe ser diferente al monto actual.';
	end if;

	if nullif(trim(p_motivo), '') is null then
		raise exception 'Indica el motivo de la corrección.';
	end if;

	for v_cuota in
		select q.id, q.monto_pagado, d.monto as nuevo_asignado
		from public.cuotas q
		inner join app_private.calcular_cuotas(p_recibo_id, p_nuevo_monto) d
			on d.miembro_id = q.miembro_id
		where q.recibo_id = p_recibo_id
			and q.estado <> 'ANULADA'
	loop
		if v_cuota.monto_pagado > v_cuota.nuevo_asignado then
			raise exception 'La corrección dejaría una cuota por debajo de un importe ya pagado. Anula o ajusta primero los aportes involucrados.';
		end if;
	end loop;

	v_delta := round(p_nuevo_monto - v_recibo.monto_total, 2);

	insert into public.recibo_ajustes (
		familia_id,
		recibo_id,
		monto_anterior,
		monto_nuevo,
		delta,
		motivo,
		creado_por
	)
	values (
		v_recibo.familia_id,
		p_recibo_id,
		v_recibo.monto_total,
		p_nuevo_monto,
		v_delta,
		trim(p_motivo),
		v_usuario_id
	);

	update public.recibos
	set monto_ajustes = monto_ajustes + v_delta,
		fecha_vencimiento = coalesce(p_fecha_vencimiento, fecha_vencimiento),
		fecha_limite_aporte = case
			when coalesce(p_fecha_vencimiento, fecha_vencimiento) is null then null
			else coalesce(p_fecha_vencimiento, fecha_vencimiento) - dias_anticipacion_aporte
		end,
		estado = case
			when coalesce(p_fecha_vencimiento, fecha_vencimiento) is not null
				and coalesce(p_fecha_vencimiento, fecha_vencimiento) < v_fecha
				then 'VENCIDO'::public.estado_recibo
			else 'PENDIENTE'::public.estado_recibo
		end,
		updated_at = now()
	where id = p_recibo_id;

	update public.cuotas q
	set monto_asignado = d.monto,
		updated_at = now()
	from app_private.calcular_cuotas(p_recibo_id, p_nuevo_monto) d
	where q.recibo_id = p_recibo_id
		and q.miembro_id = d.miembro_id
		and q.estado <> 'ANULADA';

	for v_cuota in
		select id from public.cuotas where recibo_id = p_recibo_id
	loop
		perform app_private.actualizar_estado_cuota(v_cuota.id);
	end loop;

	perform app_private.actualizar_estado_recaudacion(p_recibo_id);

	perform app_private.registrar_evento_financiero(
		v_recibo.familia_id,
		'RECIBO',
		p_recibo_id,
		'MONTO_CORREGIDO',
		jsonb_build_object('monto_anterior', v_recibo.monto_total, 'monto_nuevo', p_nuevo_monto, 'delta', v_delta, 'motivo', trim(p_motivo)),
		v_usuario_id
	);
end;
$$;

create or replace function app_private.registrar_aporte_impl(
	p_cuota_id uuid,
	p_monto numeric,
	p_metodo public.metodo_pago_familiar,
	p_referencia text default null,
	p_nota text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_cuota public.cuotas%rowtype;
	v_auth_miembro_id uuid;
	v_es_admin boolean;
	v_pendiente numeric;
	v_disponible numeric;
	v_estado public.estado_aporte;
	v_tipo public.tipo_aporte;
	v_aporte_id uuid;
begin
	select q.*
	into v_cuota
	from public.cuotas q
	inner join public.recibos r on r.id = q.recibo_id
	where q.id = p_cuota_id
		and r.estado <> 'ANULADO'
	for update of q;

	if v_cuota.id is null then
		raise exception 'Cuota no disponible.';
	end if;

	select id
	into v_auth_miembro_id
	from public.miembros_familia
	where familia_id = v_cuota.familia_id
		and usuario_id = v_usuario_id
		and estado = 'ACTIVO';

	v_es_admin := app_private.es_admin(v_cuota.familia_id, v_usuario_id);

	if not v_es_admin and v_auth_miembro_id is distinct from v_cuota.miembro_id then
		raise exception 'Solo puedes registrar aportes para tu propia cuota.';
	end if;

	if p_monto is null or p_monto <= 0 or round(p_monto, 2) <> p_monto then
		raise exception 'El aporte debe ser mayor a cero y tener máximo dos decimales.';
	end if;

	select coalesce(sum(monto), 0)
	into v_pendiente
	from public.aportes
	where cuota_id = p_cuota_id
		and estado = 'POR_VALIDAR';

	v_disponible := v_cuota.monto_asignado - v_cuota.monto_pagado - v_pendiente;

	if p_monto > v_disponible then
		raise exception 'El aporte supera el saldo disponible de la cuota.';
	end if;

	v_estado := case when v_es_admin then 'CONFIRMADO'::public.estado_aporte else 'POR_VALIDAR'::public.estado_aporte end;
	v_tipo := case
		when v_cuota.destino = 'FONDO_FAMILIAR' then 'APORTE_FAMILIAR'::public.tipo_aporte
		else 'REEMBOLSO'::public.tipo_aporte
	end;

	insert into public.aportes (
		familia_id,
		recibo_id,
		cuota_id,
		pagador_miembro_id,
		receptor_miembro_id,
		destino,
		tipo,
		metodo,
		monto,
		estado,
		referencia,
		nota,
		creado_por,
		validado_por,
		validado_at
	)
	values (
		v_cuota.familia_id,
		v_cuota.recibo_id,
		v_cuota.id,
		v_cuota.miembro_id,
		v_cuota.receptor_miembro_id,
		v_cuota.destino,
		v_tipo,
		p_metodo,
		p_monto,
		v_estado,
		nullif(trim(coalesce(p_referencia, '')), ''),
		nullif(trim(coalesce(p_nota, '')), ''),
		v_usuario_id,
		case when v_estado = 'CONFIRMADO' then v_usuario_id else null end,
		case when v_estado = 'CONFIRMADO' then now() else null end
	)
	returning id into v_aporte_id;

	if v_estado = 'CONFIRMADO' then
		update public.cuotas
		set monto_pagado = monto_pagado + p_monto,
			updated_at = now()
		where id = p_cuota_id;
	end if;

	perform app_private.actualizar_estado_cuota(p_cuota_id);
	perform app_private.actualizar_estado_recaudacion(v_cuota.recibo_id);

	perform app_private.registrar_evento_financiero(
		v_cuota.familia_id,
		'APORTE',
		v_aporte_id,
		'APORTE_REGISTRADO',
		jsonb_build_object('cuota_id', p_cuota_id, 'monto', p_monto, 'estado', v_estado, 'tipo', v_tipo),
		v_usuario_id
	);

	return v_aporte_id;
end;
$$;

create or replace function app_private.validar_aporte_impl(
	p_aporte_id uuid,
	p_aprobar boolean,
	p_motivo text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_aporte public.aportes%rowtype;
	v_cuota public.cuotas%rowtype;
	v_auth_miembro_id uuid;
	v_autorizado boolean;
begin
	select *
	into v_aporte
	from public.aportes
	where id = p_aporte_id
	for update;

	if v_aporte.id is null or v_aporte.estado <> 'POR_VALIDAR' then
		raise exception 'El aporte no está pendiente de validación.';
	end if;

	select id
	into v_auth_miembro_id
	from public.miembros_familia
	where familia_id = v_aporte.familia_id
		and usuario_id = v_usuario_id
		and estado = 'ACTIVO';

	v_autorizado :=
		app_private.es_admin(v_aporte.familia_id, v_usuario_id)
		or (
			v_aporte.receptor_miembro_id is not null
			and v_auth_miembro_id = v_aporte.receptor_miembro_id
		);

	if not v_autorizado then
		raise exception 'No tienes permiso para validar este aporte.';
	end if;

	select *
	into v_cuota
	from public.cuotas
	where id = v_aporte.cuota_id
	for update;

	if p_aprobar then
		if v_aporte.monto > v_cuota.monto_asignado - v_cuota.monto_pagado then
			raise exception 'El aporte supera el saldo pendiente de la cuota.';
		end if;

		update public.aportes
		set estado = 'CONFIRMADO',
			validado_por = v_usuario_id,
			validado_at = now(),
			rechazo_motivo = null
		where id = p_aporte_id;

		update public.cuotas
		set monto_pagado = monto_pagado + v_aporte.monto,
			updated_at = now()
		where id = v_cuota.id;
	else
		if nullif(trim(coalesce(p_motivo, '')), '') is null then
			raise exception 'Indica el motivo del rechazo.';
		end if;

		update public.aportes
		set estado = 'RECHAZADO',
			validado_por = v_usuario_id,
			validado_at = now(),
			rechazo_motivo = trim(p_motivo)
		where id = p_aporte_id;
	end if;

	perform app_private.actualizar_estado_cuota(v_cuota.id);
	perform app_private.actualizar_estado_recaudacion(v_cuota.recibo_id);

	perform app_private.registrar_evento_financiero(
		v_aporte.familia_id,
		'APORTE',
		p_aporte_id,
		case when p_aprobar then 'APORTE_CONFIRMADO' else 'APORTE_RECHAZADO' end,
		jsonb_build_object('monto', v_aporte.monto, 'motivo', p_motivo),
		v_usuario_id
	);
end;
$$;

create or replace function app_private.anular_aporte_impl(
	p_aporte_id uuid,
	p_motivo text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_aporte public.aportes%rowtype;
	v_cuota public.cuotas%rowtype;
	v_puede boolean;
begin
	select *
	into v_aporte
	from public.aportes
	where id = p_aporte_id
	for update;

	if v_aporte.id is null or v_aporte.estado = 'ANULADO' then
		raise exception 'Aporte no disponible.';
	end if;

	if v_aporte.tipo = 'COBERTURA_ADELANTO' then
		raise exception 'La cobertura de un adelanto se revierte anulando el pago al proveedor.';
	end if;

	v_puede := app_private.es_admin(v_aporte.familia_id, v_usuario_id)
		or (v_aporte.estado = 'POR_VALIDAR' and v_aporte.creado_por = v_usuario_id);

	if not v_puede then
		raise exception 'No tienes permiso para anular este aporte.';
	end if;

	if nullif(trim(p_motivo), '') is null then
		raise exception 'Indica el motivo de la anulación.';
	end if;

	select *
	into v_cuota
	from public.cuotas
	where id = v_aporte.cuota_id
	for update;

	if v_aporte.estado = 'CONFIRMADO' then
		update public.cuotas
		set monto_pagado = monto_pagado - v_aporte.monto,
			updated_at = now()
		where id = v_cuota.id;
	end if;

	update public.aportes
	set estado = 'ANULADO',
		anulado_por = v_usuario_id,
		anulado_at = now(),
		anulacion_motivo = trim(p_motivo)
	where id = p_aporte_id;

	perform app_private.actualizar_estado_cuota(v_cuota.id);
	perform app_private.actualizar_estado_recaudacion(v_cuota.recibo_id);

	perform app_private.registrar_evento_financiero(
		v_aporte.familia_id,
		'APORTE',
		p_aporte_id,
		'APORTE_ANULADO',
		jsonb_build_object('motivo', trim(p_motivo)),
		v_usuario_id
	);
end;
$$;

create or replace function app_private.registrar_pago_proveedor_impl(
	p_recibo_id uuid,
	p_origen public.origen_pago_proveedor,
	p_pagador_miembro_id uuid,
	p_monto numeric,
	p_fecha_pago date,
	p_referencia text default null,
	p_nota text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_recibo public.recibos%rowtype;
	v_pago_id uuid;
	v_pagador_nombre text;
	v_cuota public.cuotas%rowtype;
begin
	select *
	into v_recibo
	from public.recibos
	where id = p_recibo_id
	for update;

	if v_recibo.id is null or v_recibo.monto_total is null or v_recibo.estado = 'ANULADO' then
		raise exception 'Recibo no disponible para pago.';
	end if;

	if not app_private.es_admin(v_recibo.familia_id, v_usuario_id) then
		raise exception 'Solo un administrador puede registrar el pago al proveedor.';
	end if;

	if exists (
		select 1 from public.pagos_proveedor
		where recibo_id = p_recibo_id
			and estado = 'CONFIRMADO'
	) then
		raise exception 'El proveedor ya tiene un pago confirmado para este recibo.';
	end if;

	if p_monto is null or round(p_monto, 2) <> round(v_recibo.monto_total, 2) then
		raise exception 'El pago al proveedor debe coincidir exactamente con el total del recibo.';
	end if;

	if p_fecha_pago is null then
		raise exception 'Indica la fecha del pago al proveedor.';
	end if;

	if p_origen = 'FONDO_FAMILIAR' then
		if v_recibo.estado_recaudacion <> 'COMPLETA' then
			raise exception 'Para pagar desde el fondo familiar, la recaudación debe estar completa.';
		end if;
		p_pagador_miembro_id := null;
	else
		if p_pagador_miembro_id is null then
			raise exception 'Selecciona al integrante que adelantó el pago.';
		end if;

		select coalesce(per.nombre, 'Integrante')
		into v_pagador_nombre
		from public.miembros_familia m
		left join public.perfiles per on per.id = m.usuario_id
		where m.id = p_pagador_miembro_id
			and m.familia_id = v_recibo.familia_id
			and m.estado = 'ACTIVO';

		if v_pagador_nombre is null then
			raise exception 'El integrante que adelanta el pago no está activo en la familia.';
		end if;

		if exists (
			select 1
			from public.aportes
			where recibo_id = p_recibo_id
				and estado in ('POR_VALIDAR', 'CONFIRMADO')
		) then
			raise exception 'No se puede convertir a adelanto porque el recibo ya tiene aportes activos. Anúlalos o resuélvelos primero.';
		end if;

		update public.cuotas
		set destino = 'INTEGRANTE',
			receptor_miembro_id = p_pagador_miembro_id,
			updated_at = now()
		where recibo_id = p_recibo_id
			and miembro_id <> p_pagador_miembro_id
			and estado <> 'ANULADA';

		select *
		into v_cuota
		from public.cuotas
		where recibo_id = p_recibo_id
			and miembro_id = p_pagador_miembro_id
			and estado <> 'ANULADA'
		for update;

		if v_cuota.id is not null then
			insert into public.aportes (
				familia_id,
				recibo_id,
				cuota_id,
				pagador_miembro_id,
				destino,
				tipo,
				metodo,
				monto,
				estado,
				nota,
				creado_por,
				validado_por,
				validado_at
			)
			values (
				v_recibo.familia_id,
				p_recibo_id,
				v_cuota.id,
				p_pagador_miembro_id,
				'FONDO_FAMILIAR',
				'COBERTURA_ADELANTO',
				null,
				v_cuota.monto_asignado,
				'CONFIRMADO',
				'Cuota cubierta por adelanto del pago total al proveedor.',
				v_usuario_id,
				v_usuario_id,
				now()
			);

			update public.cuotas
			set monto_pagado = monto_asignado,
				updated_at = now()
			where id = v_cuota.id;

			perform app_private.actualizar_estado_cuota(v_cuota.id);
		end if;
	end if;

	insert into public.pagos_proveedor (
		familia_id,
		recibo_id,
		origen,
		pagador_miembro_id,
		pagador_nombre_snapshot,
		monto,
		fecha_pago,
		referencia,
		nota,
		creado_por
	)
	values (
		v_recibo.familia_id,
		p_recibo_id,
		p_origen,
		p_pagador_miembro_id,
		v_pagador_nombre,
		p_monto,
		p_fecha_pago,
		nullif(trim(coalesce(p_referencia, '')), ''),
		nullif(trim(coalesce(p_nota, '')), ''),
		v_usuario_id
	)
	returning id into v_pago_id;

	update public.recibos
	set estado = 'PAGADO',
		updated_at = now()
	where id = p_recibo_id;

	perform app_private.actualizar_estado_recaudacion(p_recibo_id);
	perform app_private.intentar_cerrar_periodo(v_recibo.periodo_id);

	perform app_private.registrar_evento_financiero(
		v_recibo.familia_id,
		'PAGO_PROVEEDOR',
		v_pago_id,
		'PAGO_PROVEEDOR_REGISTRADO',
		jsonb_build_object('recibo_id', p_recibo_id, 'origen', p_origen, 'monto', p_monto, 'pagador_miembro_id', p_pagador_miembro_id),
		v_usuario_id
	);

	return v_pago_id;
end;
$$;

create or replace function app_private.anular_pago_proveedor_impl(
	p_pago_id uuid,
	p_motivo text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_pago public.pagos_proveedor%rowtype;
	v_recibo public.recibos%rowtype;
	v_cuota record;
	v_fecha date := (timezone('America/Lima', now()))::date;
begin
	select *
	into v_pago
	from public.pagos_proveedor
	where id = p_pago_id
	for update;

	if v_pago.id is null or v_pago.estado <> 'CONFIRMADO' then
		raise exception 'Pago al proveedor no disponible.';
	end if;

	if not app_private.es_admin(v_pago.familia_id, v_usuario_id) then
		raise exception 'Solo un administrador puede anular el pago al proveedor.';
	end if;

	if nullif(trim(p_motivo), '') is null then
		raise exception 'Indica el motivo de la anulación.';
	end if;

	select *
	into v_recibo
	from public.recibos
	where id = v_pago.recibo_id
	for update;

	if v_pago.origen = 'ADELANTO_INTEGRANTE' then
		if exists (
			select 1
			from public.aportes
			where recibo_id = v_pago.recibo_id
				and tipo <> 'COBERTURA_ADELANTO'
				and estado in ('POR_VALIDAR', 'CONFIRMADO')
		) then
			raise exception 'Existen reembolsos o aportes activos. Resuélvelos antes de anular el adelanto.';
		end if;

		for v_cuota in
			select a.id as aporte_id, a.cuota_id, a.monto
			from public.aportes a
			where a.recibo_id = v_pago.recibo_id
				and a.tipo = 'COBERTURA_ADELANTO'
				and a.estado = 'CONFIRMADO'
		loop
			update public.cuotas
			set monto_pagado = monto_pagado - v_cuota.monto,
				updated_at = now()
			where id = v_cuota.cuota_id;

			update public.aportes
			set estado = 'ANULADO',
				anulado_por = v_usuario_id,
				anulado_at = now(),
				anulacion_motivo = 'Cobertura revertida por anulación del adelanto.'
			where id = v_cuota.aporte_id;

			perform app_private.actualizar_estado_cuota(v_cuota.cuota_id);
		end loop;

		update public.cuotas
		set destino = 'FONDO_FAMILIAR',
			receptor_miembro_id = null,
			updated_at = now()
		where recibo_id = v_pago.recibo_id
			and estado <> 'ANULADA';
	end if;

	update public.pagos_proveedor
	set estado = 'ANULADO',
		anulado_por = v_usuario_id,
		anulado_at = now(),
		anulacion_motivo = trim(p_motivo)
	where id = p_pago_id;

	update public.recibos
	set estado = case
			when fecha_vencimiento is not null and fecha_vencimiento < v_fecha then 'VENCIDO'::public.estado_recibo
			else 'PENDIENTE'::public.estado_recibo
		end,
		updated_at = now()
	where id = v_pago.recibo_id;

	perform app_private.actualizar_estado_recaudacion(v_pago.recibo_id);

	perform app_private.registrar_evento_financiero(
		v_pago.familia_id,
		'PAGO_PROVEEDOR',
		p_pago_id,
		'PAGO_PROVEEDOR_ANULADO',
		jsonb_build_object('motivo', trim(p_motivo)),
		v_usuario_id
	);
end;
$$;

create or replace function app_private.cerrar_periodo_impl(
	p_periodo_id uuid,
	p_motivo text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_periodo public.periodos%rowtype;
begin
	select *
	into v_periodo
	from public.periodos
	where id = p_periodo_id
	for update;

	if v_periodo.id is null then
		raise exception 'Periodo no encontrado.';
	end if;

	if not app_private.es_admin(v_periodo.familia_id, v_usuario_id) then
		raise exception 'Solo un administrador puede cerrar el periodo.';
	end if;

	if v_periodo.estado = 'COMPLETADO' then
		return;
	end if;

	if not exists (
		select 1 from public.recibos
		where periodo_id = p_periodo_id
			and estado <> 'ANULADO'
	) then
		raise exception 'No puedes cerrar un periodo sin recibos.';
	end if;

	if exists (
		select 1
		from public.recibos
		where periodo_id = p_periodo_id
			and estado <> 'ANULADO'
			and (
				estado <> 'PAGADO'
				or estado_recaudacion <> 'COMPLETA'
			)
	) then
		raise exception 'El periodo todavía tiene recibos o cuotas pendientes.';
	end if;

	update public.periodos
	set estado = 'COMPLETADO',
		completado_at = now(),
		cierre_tipo = 'MANUAL',
		completado_por = v_usuario_id,
		motivo_cierre = nullif(trim(coalesce(p_motivo, '')), '')
	where id = p_periodo_id;

	perform app_private.registrar_evento_financiero(
		v_periodo.familia_id,
		'PERIODO',
		p_periodo_id,
		'PERIODO_CERRADO_MANUAL',
		jsonb_build_object('motivo', p_motivo),
		v_usuario_id
	);
end;
$$;

revoke all on function app_private.guardar_concepto_servicio_fase6_impl(uuid, uuid, uuid, uuid, uuid, text, public.frecuencia_concepto, public.metodo_obtencion_monto, numeric, public.tipo_vencimiento_concepto, smallint, public.tipo_distribucion_concepto, public.tipo_reparto_resto, boolean, jsonb, jsonb, date, smallint) from public, anon;
revoke all on function app_private.sincronizar_periodo_actual_usuario_impl(uuid) from public, anon;
revoke all on function app_private.confirmar_monto_recibo_impl(uuid, numeric, date) from public, anon;
revoke all on function app_private.corregir_monto_recibo_impl(uuid, numeric, text, date) from public, anon;
revoke all on function app_private.registrar_aporte_impl(uuid, numeric, public.metodo_pago_familiar, text, text) from public, anon;
revoke all on function app_private.validar_aporte_impl(uuid, boolean, text) from public, anon;
revoke all on function app_private.anular_aporte_impl(uuid, text) from public, anon;
revoke all on function app_private.registrar_pago_proveedor_impl(uuid, public.origen_pago_proveedor, uuid, numeric, date, text, text) from public, anon;
revoke all on function app_private.anular_pago_proveedor_impl(uuid, text) from public, anon;
revoke all on function app_private.cerrar_periodo_impl(uuid, text) from public, anon;

grant execute on function app_private.guardar_concepto_servicio_fase6_impl(uuid, uuid, uuid, uuid, uuid, text, public.frecuencia_concepto, public.metodo_obtencion_monto, numeric, public.tipo_vencimiento_concepto, smallint, public.tipo_distribucion_concepto, public.tipo_reparto_resto, boolean, jsonb, jsonb, date, smallint) to authenticated;
grant execute on function app_private.sincronizar_periodo_actual_usuario_impl(uuid) to authenticated;
grant execute on function app_private.confirmar_monto_recibo_impl(uuid, numeric, date) to authenticated;
grant execute on function app_private.corregir_monto_recibo_impl(uuid, numeric, text, date) to authenticated;
grant execute on function app_private.registrar_aporte_impl(uuid, numeric, public.metodo_pago_familiar, text, text) to authenticated;
grant execute on function app_private.validar_aporte_impl(uuid, boolean, text) to authenticated;
grant execute on function app_private.anular_aporte_impl(uuid, text) to authenticated;
grant execute on function app_private.registrar_pago_proveedor_impl(uuid, public.origen_pago_proveedor, uuid, numeric, date, text, text) to authenticated;
grant execute on function app_private.anular_pago_proveedor_impl(uuid, text) to authenticated;
grant execute on function app_private.cerrar_periodo_impl(uuid, text) to authenticated;

create or replace function public.guardar_concepto_servicio_fase6(
	p_concepto_id uuid,
	p_familia_id uuid,
	p_categoria_id uuid,
	p_proveedor_id uuid,
	p_plantilla_id uuid,
	p_nombre text,
	p_frecuencia public.frecuencia_concepto,
	p_metodo_obtencion public.metodo_obtencion_monto,
	p_monto_fijo numeric,
	p_tipo_vencimiento public.tipo_vencimiento_concepto,
	p_dia_vencimiento smallint,
	p_tipo_distribucion public.tipo_distribucion_concepto,
	p_reparto_resto public.tipo_reparto_resto,
	p_fallback_manual boolean,
	p_cuenta jsonb,
	p_participantes jsonb,
	p_fecha_inicio_generacion date,
	p_dias_anticipacion_aporte smallint
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
	select app_private.guardar_concepto_servicio_fase6_impl(
		p_concepto_id, p_familia_id, p_categoria_id, p_proveedor_id, p_plantilla_id,
		p_nombre, p_frecuencia, p_metodo_obtencion, p_monto_fijo, p_tipo_vencimiento,
		p_dia_vencimiento, p_tipo_distribucion, p_reparto_resto, p_fallback_manual,
		p_cuenta, p_participantes, p_fecha_inicio_generacion, p_dias_anticipacion_aporte
	);
$$;

create or replace function public.sincronizar_periodo_actual(p_familia_id uuid)
returns integer
language sql
security invoker
set search_path = ''
as $$ select app_private.sincronizar_periodo_actual_usuario_impl(p_familia_id); $$;

create or replace function public.confirmar_monto_recibo(p_recibo_id uuid, p_monto numeric, p_fecha_vencimiento date)
returns void
language sql
security invoker
set search_path = ''
as $$ select app_private.confirmar_monto_recibo_impl(p_recibo_id, p_monto, p_fecha_vencimiento); $$;

create or replace function public.corregir_monto_recibo(p_recibo_id uuid, p_nuevo_monto numeric, p_motivo text, p_fecha_vencimiento date default null)
returns void
language sql
security invoker
set search_path = ''
as $$ select app_private.corregir_monto_recibo_impl(p_recibo_id, p_nuevo_monto, p_motivo, p_fecha_vencimiento); $$;

create or replace function public.registrar_aporte(p_cuota_id uuid, p_monto numeric, p_metodo public.metodo_pago_familiar, p_referencia text default null, p_nota text default null)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select app_private.registrar_aporte_impl(p_cuota_id, p_monto, p_metodo, p_referencia, p_nota); $$;

create or replace function public.validar_aporte(p_aporte_id uuid, p_aprobar boolean, p_motivo text default null)
returns void
language sql
security invoker
set search_path = ''
as $$ select app_private.validar_aporte_impl(p_aporte_id, p_aprobar, p_motivo); $$;

create or replace function public.anular_aporte(p_aporte_id uuid, p_motivo text)
returns void
language sql
security invoker
set search_path = ''
as $$ select app_private.anular_aporte_impl(p_aporte_id, p_motivo); $$;

create or replace function public.registrar_pago_proveedor(p_recibo_id uuid, p_origen public.origen_pago_proveedor, p_pagador_miembro_id uuid, p_monto numeric, p_fecha_pago date, p_referencia text default null, p_nota text default null)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select app_private.registrar_pago_proveedor_impl(p_recibo_id, p_origen, p_pagador_miembro_id, p_monto, p_fecha_pago, p_referencia, p_nota); $$;

create or replace function public.anular_pago_proveedor(p_pago_id uuid, p_motivo text)
returns void
language sql
security invoker
set search_path = ''
as $$ select app_private.anular_pago_proveedor_impl(p_pago_id, p_motivo); $$;

create or replace function public.cerrar_periodo(p_periodo_id uuid, p_motivo text default null)
returns void
language sql
security invoker
set search_path = ''
as $$ select app_private.cerrar_periodo_impl(p_periodo_id, p_motivo); $$;

revoke all on function public.guardar_concepto_servicio_fase6(uuid, uuid, uuid, uuid, uuid, text, public.frecuencia_concepto, public.metodo_obtencion_monto, numeric, public.tipo_vencimiento_concepto, smallint, public.tipo_distribucion_concepto, public.tipo_reparto_resto, boolean, jsonb, jsonb, date, smallint) from public, anon;
revoke all on function public.sincronizar_periodo_actual(uuid) from public, anon;
revoke all on function public.confirmar_monto_recibo(uuid, numeric, date) from public, anon;
revoke all on function public.corregir_monto_recibo(uuid, numeric, text, date) from public, anon;
revoke all on function public.registrar_aporte(uuid, numeric, public.metodo_pago_familiar, text, text) from public, anon;
revoke all on function public.validar_aporte(uuid, boolean, text) from public, anon;
revoke all on function public.anular_aporte(uuid, text) from public, anon;
revoke all on function public.registrar_pago_proveedor(uuid, public.origen_pago_proveedor, uuid, numeric, date, text, text) from public, anon;
revoke all on function public.anular_pago_proveedor(uuid, text) from public, anon;
revoke all on function public.cerrar_periodo(uuid, text) from public, anon;

grant execute on function public.guardar_concepto_servicio_fase6(uuid, uuid, uuid, uuid, uuid, text, public.frecuencia_concepto, public.metodo_obtencion_monto, numeric, public.tipo_vencimiento_concepto, smallint, public.tipo_distribucion_concepto, public.tipo_reparto_resto, boolean, jsonb, jsonb, date, smallint) to authenticated;
grant execute on function public.sincronizar_periodo_actual(uuid) to authenticated;
grant execute on function public.confirmar_monto_recibo(uuid, numeric, date) to authenticated;
grant execute on function public.corregir_monto_recibo(uuid, numeric, text, date) to authenticated;
grant execute on function public.registrar_aporte(uuid, numeric, public.metodo_pago_familiar, text, text) to authenticated;
grant execute on function public.validar_aporte(uuid, boolean, text) to authenticated;
grant execute on function public.anular_aporte(uuid, text) to authenticated;
grant execute on function public.registrar_pago_proveedor(uuid, public.origen_pago_proveedor, uuid, numeric, date, text, text) to authenticated;
grant execute on function public.anular_pago_proveedor(uuid, text) to authenticated;
grant execute on function public.cerrar_periodo(uuid, text) to authenticated;
