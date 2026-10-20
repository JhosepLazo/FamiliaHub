
create or replace function app_private.saldo_disponible_cuota(
	p_cuota_id uuid,
	p_excluir_pago_id uuid default null
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
	select greatest(
		0::numeric,
		q.saldo_pendiente
		- coalesce((
			select sum(a.monto)
			from public.aportes a
			where a.cuota_id = q.id
				and a.estado = 'POR_VALIDAR'
		), 0)
		- coalesce((
			select sum(pa.monto)
			from public.pago_asignaciones pa
			inner join public.pagos_familiares pf on pf.id = pa.pago_id
			where pa.cuota_id = q.id
				and pf.estado = 'POR_VALIDAR'
				and (p_excluir_pago_id is null or pf.id <> p_excluir_pago_id)
		), 0)
	)
	from public.cuotas q
	where q.id = p_cuota_id;
$$;

revoke all on function app_private.saldo_disponible_cuota(uuid, uuid) from public, anon, authenticated;

create or replace function app_private.actualizar_estado_cuota(p_cuota_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_asignado numeric;
	v_pagado numeric;
	v_pendiente numeric;
	v_estado public.estado_cuota;
begin
	select monto_asignado, monto_pagado, estado
	into v_asignado, v_pagado, v_estado
	from public.cuotas
	where id = p_cuota_id
	for update;

	if v_estado = 'ANULADA' then
		return;
	end if;

	select
		coalesce((
			select sum(a.monto)
			from public.aportes a
			where a.cuota_id = p_cuota_id
				and a.estado = 'POR_VALIDAR'
		), 0)
		+
		coalesce((
			select sum(pa.monto)
			from public.pago_asignaciones pa
			inner join public.pagos_familiares pf on pf.id = pa.pago_id
			where pa.cuota_id = p_cuota_id
				and pf.estado = 'POR_VALIDAR'
		), 0)
	into v_pendiente;

	update public.cuotas
	set estado = case
			when v_pagado >= v_asignado then 'PAGADA'::public.estado_cuota
			when v_pendiente > 0 then 'POR_VALIDAR'::public.estado_cuota
			when v_pagado > 0 then 'PARCIAL'::public.estado_cuota
			else 'PENDIENTE'::public.estado_cuota
		end,
		updated_at = now()
	where id = p_cuota_id;
end;
$$;

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

	select
		count(distinct q.familia_id),
		count(distinct (q.destino::text || ':' || coalesce(q.receptor_miembro_id::text, 'FONDO'))),
		min(q.familia_id),
		min(q.miembro_id),
		min(q.destino::text)::public.destino_aporte,
		min(q.receptor_miembro_id)
	into
		v_total,
		v_grupos,
		v_familia_id,
		v_pagador_miembro_id,
		v_destino,
		v_receptor_miembro_id
	from jsonb_array_elements(p_asignaciones) elemento
	inner join public.cuotas q on q.id = (elemento ->> 'cuota_id')::uuid
	inner join public.recibos r on r.id = q.recibo_id
	inner join public.periodos pe on pe.id = r.periodo_id
	where q.usuario_id = v_usuario_id
		and q.estado <> 'ANULADA'
		and r.estado <> 'ANULADO'
		and pe.estado = 'ABIERTO';

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
			c.qr_storage_path
		into
			v_responsable_miembro_id,
			v_receptor_nombre,
			v_titular,
			v_referencia,
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
			c.qr_storage_path
		into
			v_responsable_miembro_id,
			v_receptor_nombre,
			v_titular,
			v_referencia,
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

create or replace function app_private.finalizar_pago_familiar_impl(
	p_pago_id uuid,
	p_fecha_pago date,
	p_referencia_operacion text default null,
	p_comprobante_storage_path text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_pago public.pagos_familiares%rowtype;
	v_asig record;
	v_fecha_actual date := (timezone('America/Lima', now()))::date;
begin
	select *
	into v_pago
	from public.pagos_familiares
	where id = p_pago_id
	for update;

	if v_pago.id is null or v_pago.pagador_usuario_id <> v_usuario_id then
		raise exception 'Pago no disponible.';
	end if;

	if v_pago.estado <> 'BORRADOR' then
		raise exception 'Este pago ya fue enviado o cerrado.';
	end if;

	if p_fecha_pago is null or p_fecha_pago > v_fecha_actual then
		raise exception 'La fecha del pago no puede ser futura.';
	end if;

	if v_pago.metodo in ('YAPE', 'TRANSFERENCIA')
		and nullif(trim(coalesce(p_referencia_operacion, '')), '') is null
		and nullif(trim(coalesce(p_comprobante_storage_path, '')), '') is null then
		raise exception 'Yape o transferencia requieren referencia de operación o comprobante.';
	end if;

	if p_comprobante_storage_path is not null then
		if p_comprobante_storage_path !~ (
			'^' || v_pago.familia_id::text || '/pagos/' || v_pago.id::text || '/'
		) then
			raise exception 'La ruta del comprobante no corresponde a este pago.';
		end if;

		if not exists (
			select 1
			from storage.objects o
			where o.bucket_id = 'familia-comprobantes'
				and o.name = p_comprobante_storage_path
		) then
			raise exception 'El comprobante indicado no existe.';
		end if;
	end if;

	for v_asig in
		select pa.*
		from public.pago_asignaciones pa
		where pa.pago_id = p_pago_id
		order by pa.cuota_id
	loop
		perform 1 from public.cuotas where id = v_asig.cuota_id for update;

		if v_asig.monto > app_private.saldo_disponible_cuota(v_asig.cuota_id, p_pago_id) then
			raise exception 'El saldo de una cuota cambió. Revisa el pago antes de enviarlo.';
		end if;
	end loop;

	update public.pagos_familiares
	set estado = 'POR_VALIDAR',
		fecha_pago = p_fecha_pago,
		referencia_operacion = nullif(trim(coalesce(p_referencia_operacion, '')), ''),
		comprobante_bucket = case when p_comprobante_storage_path is null then null else 'familia-comprobantes' end,
		comprobante_storage_path = nullif(trim(coalesce(p_comprobante_storage_path, '')), ''),
		enviado_at = now(),
		updated_at = now()
	where id = p_pago_id;

	for v_asig in
		select cuota_id
		from public.pago_asignaciones
		where pago_id = p_pago_id
	loop
		perform app_private.actualizar_estado_cuota(v_asig.cuota_id);
	end loop;

	perform app_private.registrar_evento_financiero(
		v_pago.familia_id,
		'PAGO_FAMILIAR',
		p_pago_id,
		'PAGO_ENVIADO',
		jsonb_build_object('monto_total', v_pago.monto_total, 'metodo', v_pago.metodo),
		v_usuario_id
	);
end;
$$;

create or replace function app_private.validar_pago_familiar_impl(
	p_pago_id uuid,
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
	v_pago public.pagos_familiares%rowtype;
	v_miembro_id uuid;
	v_autorizado boolean;
	v_asig record;
	v_cuota public.cuotas%rowtype;
	v_aporte_id uuid;
begin
	select *
	into v_pago
	from public.pagos_familiares
	where id = p_pago_id
	for update;

	if v_pago.id is null or v_pago.estado <> 'POR_VALIDAR' then
		raise exception 'El pago no está pendiente de validación.';
	end if;

	select id into v_miembro_id
	from public.miembros_familia
	where familia_id = v_pago.familia_id
		and usuario_id = v_usuario_id
		and estado = 'ACTIVO';

	v_autorizado :=
		app_private.es_admin(v_pago.familia_id, v_usuario_id)
		or v_miembro_id = v_pago.responsable_receptor_miembro_id;

	if not v_autorizado then
		raise exception 'No tienes permiso para validar este pago.';
	end if;

	if not p_aprobar then
		if nullif(trim(coalesce(p_motivo, '')), '') is null then
			raise exception 'Indica el motivo del rechazo.';
		end if;

		update public.pagos_familiares
		set estado = 'RECHAZADO',
			validado_por = v_usuario_id,
			validado_at = now(),
			rechazo_motivo = trim(p_motivo),
			updated_at = now()
		where id = p_pago_id;

		for v_asig in
			select cuota_id
			from public.pago_asignaciones
			where pago_id = p_pago_id
		loop
			perform app_private.actualizar_estado_cuota(v_asig.cuota_id);
		end loop;

		perform app_private.registrar_evento_financiero(
			v_pago.familia_id,
			'PAGO_FAMILIAR',
			p_pago_id,
			'PAGO_RECHAZADO',
			jsonb_build_object('motivo', trim(p_motivo)),
			v_usuario_id
		);
		return;
	end if;

	for v_asig in
		select pa.*
		from public.pago_asignaciones pa
		where pa.pago_id = p_pago_id
		order by pa.cuota_id
	loop
		select *
		into v_cuota
		from public.cuotas
		where id = v_asig.cuota_id
		for update;

		if v_cuota.id is null
			or v_cuota.estado = 'ANULADA'
			or v_asig.monto > v_cuota.saldo_pendiente then
			raise exception 'Una cuota cambió y el pago ya no puede aprobarse con esos importes.';
		end if;

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
			validado_at,
			pago_familiar_id,
			pago_asignacion_id
		)
		values (
			v_pago.familia_id,
			v_asig.recibo_id,
			v_asig.cuota_id,
			v_pago.pagador_miembro_id,
			v_pago.receptor_miembro_id,
			v_pago.destino,
			case
				when v_pago.destino = 'FONDO_FAMILIAR' then 'APORTE_FAMILIAR'::public.tipo_aporte
				else 'REEMBOLSO'::public.tipo_aporte
			end,
			v_pago.metodo,
			v_asig.monto,
			'CONFIRMADO',
			v_pago.referencia_operacion,
			'Pago validado desde Fase 8.',
			v_pago.creado_por,
			v_usuario_id,
			now(),
			v_pago.id,
			v_asig.id
		)
		returning id into v_aporte_id;

		update public.cuotas
		set monto_pagado = monto_pagado + v_asig.monto,
			updated_at = now()
		where id = v_asig.cuota_id;

		perform app_private.actualizar_estado_cuota(v_asig.cuota_id);
		perform app_private.actualizar_estado_recaudacion(v_asig.recibo_id);
	end loop;

	update public.pagos_familiares
	set estado = 'CONFIRMADO',
		validado_por = v_usuario_id,
		validado_at = now(),
		rechazo_motivo = null,
		updated_at = now()
	where id = p_pago_id;

	perform app_private.registrar_evento_financiero(
		v_pago.familia_id,
		'PAGO_FAMILIAR',
		p_pago_id,
		'PAGO_CONFIRMADO',
		jsonb_build_object('monto_total', v_pago.monto_total, 'metodo', v_pago.metodo),
		v_usuario_id
	);
end;
$$;

create or replace function app_private.anular_pago_familiar_impl(
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
	v_pago public.pagos_familiares%rowtype;
	v_miembro_id uuid;
	v_puede boolean;
	v_asig record;
	v_aporte public.aportes%rowtype;
begin
	select *
	into v_pago
	from public.pagos_familiares
	where id = p_pago_id
	for update;

	if v_pago.id is null or v_pago.estado = 'ANULADO' then
		raise exception 'Pago no disponible.';
	end if;

	if nullif(trim(coalesce(p_motivo, '')), '') is null then
		raise exception 'Indica el motivo de la anulación.';
	end if;

	select id into v_miembro_id
	from public.miembros_familia
	where familia_id = v_pago.familia_id
		and usuario_id = v_usuario_id
		and estado = 'ACTIVO';

	if v_pago.estado = 'CONFIRMADO' then
		v_puede :=
			app_private.es_admin(v_pago.familia_id, v_usuario_id)
			or v_miembro_id = v_pago.responsable_receptor_miembro_id;
	else
		v_puede :=
			v_pago.pagador_usuario_id = v_usuario_id
			or app_private.es_admin(v_pago.familia_id, v_usuario_id)
			or v_miembro_id = v_pago.responsable_receptor_miembro_id;
	end if;

	if not v_puede then
		raise exception 'No tienes permiso para anular este pago.';
	end if;

	if v_pago.estado = 'CONFIRMADO' then
		for v_asig in
			select pa.*
			from public.pago_asignaciones pa
			where pa.pago_id = p_pago_id
			order by pa.cuota_id
		loop
			select *
			into v_aporte
			from public.aportes
			where pago_asignacion_id = v_asig.id
				and estado = 'CONFIRMADO'
			for update;

			if v_aporte.id is null then
				raise exception 'No se encontró el aporte confirmado asociado al pago.';
			end if;

			perform 1 from public.cuotas where id = v_asig.cuota_id for update;

			update public.cuotas
			set monto_pagado = monto_pagado - v_aporte.monto,
				updated_at = now()
			where id = v_asig.cuota_id;

			update public.aportes
			set estado = 'ANULADO',
				anulado_por = v_usuario_id,
				anulado_at = now(),
				anulacion_motivo = trim(p_motivo)
			where id = v_aporte.id;

			perform app_private.actualizar_estado_cuota(v_asig.cuota_id);
			perform app_private.actualizar_estado_recaudacion(v_asig.recibo_id);
		end loop;
	end if;

	update public.pagos_familiares
	set estado = 'ANULADO',
		anulado_por = v_usuario_id,
		anulado_at = now(),
		anulacion_motivo = trim(p_motivo),
		updated_at = now()
	where id = p_pago_id;

	if v_pago.estado = 'POR_VALIDAR' then
		for v_asig in
			select cuota_id
			from public.pago_asignaciones
			where pago_id = p_pago_id
		loop
			perform app_private.actualizar_estado_cuota(v_asig.cuota_id);
		end loop;
	end if;

	perform app_private.registrar_evento_financiero(
		v_pago.familia_id,
		'PAGO_FAMILIAR',
		p_pago_id,
		'PAGO_ANULADO',
		jsonb_build_object('motivo', trim(p_motivo)),
		v_usuario_id
	);
end;
$$;

create or replace function app_private.adjuntar_comprobante_pago_proveedor_impl(
	p_pago_id uuid,
	p_comprobante_storage_path text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_pago public.pagos_proveedor%rowtype;
begin
	select *
	into v_pago
	from public.pagos_proveedor
	where id = p_pago_id
	for update;

	if v_pago.id is null or not app_private.es_admin(v_pago.familia_id, v_usuario_id) then
		raise exception 'No tienes permiso para adjuntar este comprobante.';
	end if;

	if p_comprobante_storage_path !~ (
		'^' || v_pago.familia_id::text || '/proveedor/' || v_pago.id::text || '/'
	) then
		raise exception 'La ruta del comprobante no corresponde a este pago.';
	end if;

	if not exists (
		select 1
		from storage.objects o
		where o.bucket_id = 'familia-comprobantes'
			and o.name = p_comprobante_storage_path
	) then
		raise exception 'El comprobante indicado no existe.';
	end if;

	update public.pagos_proveedor
	set comprobante_bucket = 'familia-comprobantes',
		comprobante_storage_path = p_comprobante_storage_path
	where id = p_pago_id;
end;
$$;

revoke all on function app_private.crear_pago_familiar_impl(jsonb, public.metodo_pago_familiar) from public, anon;
revoke all on function app_private.finalizar_pago_familiar_impl(uuid, date, text, text) from public, anon;
revoke all on function app_private.validar_pago_familiar_impl(uuid, boolean, text) from public, anon;
revoke all on function app_private.anular_pago_familiar_impl(uuid, text) from public, anon;
revoke all on function app_private.adjuntar_comprobante_pago_proveedor_impl(uuid, text) from public, anon;

grant execute on function app_private.crear_pago_familiar_impl(jsonb, public.metodo_pago_familiar) to authenticated;
grant execute on function app_private.finalizar_pago_familiar_impl(uuid, date, text, text) to authenticated;
grant execute on function app_private.validar_pago_familiar_impl(uuid, boolean, text) to authenticated;
grant execute on function app_private.anular_pago_familiar_impl(uuid, text) to authenticated;
grant execute on function app_private.adjuntar_comprobante_pago_proveedor_impl(uuid, text) to authenticated;

create or replace function public.crear_pago_familiar(
	p_asignaciones jsonb,
	p_metodo public.metodo_pago_familiar
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
	select app_private.crear_pago_familiar_impl(p_asignaciones, p_metodo);
$$;

create or replace function public.finalizar_pago_familiar(
	p_pago_id uuid,
	p_fecha_pago date,
	p_referencia_operacion text default null,
	p_comprobante_storage_path text default null
)
returns void
language sql
security invoker
set search_path = ''
as $$
	select app_private.finalizar_pago_familiar_impl(
		p_pago_id,
		p_fecha_pago,
		p_referencia_operacion,
		p_comprobante_storage_path
	);
$$;

create or replace function public.validar_pago_familiar(
	p_pago_id uuid,
	p_aprobar boolean,
	p_motivo text default null
)
returns void
language sql
security invoker
set search_path = ''
as $$
	select app_private.validar_pago_familiar_impl(p_pago_id, p_aprobar, p_motivo);
$$;

create or replace function public.anular_pago_familiar(
	p_pago_id uuid,
	p_motivo text
)
returns void
language sql
security invoker
set search_path = ''
as $$
	select app_private.anular_pago_familiar_impl(p_pago_id, p_motivo);
$$;

create or replace function public.adjuntar_comprobante_pago_proveedor(
	p_pago_id uuid,
	p_comprobante_storage_path text
)
returns void
language sql
security invoker
set search_path = ''
as $$
	select app_private.adjuntar_comprobante_pago_proveedor_impl(
		p_pago_id,
		p_comprobante_storage_path
	);
$$;

revoke all on function public.crear_pago_familiar(jsonb, public.metodo_pago_familiar) from public, anon;
revoke all on function public.finalizar_pago_familiar(uuid, date, text, text) from public, anon;
revoke all on function public.validar_pago_familiar(uuid, boolean, text) from public, anon;
revoke all on function public.anular_pago_familiar(uuid, text) from public, anon;
revoke all on function public.adjuntar_comprobante_pago_proveedor(uuid, text) from public, anon;

grant execute on function public.crear_pago_familiar(jsonb, public.metodo_pago_familiar) to authenticated;
grant execute on function public.finalizar_pago_familiar(uuid, date, text, text) to authenticated;
grant execute on function public.validar_pago_familiar(uuid, boolean, text) to authenticated;
grant execute on function public.anular_pago_familiar(uuid, text) to authenticated;
grant execute on function public.adjuntar_comprobante_pago_proveedor(uuid, text) to authenticated;
;
