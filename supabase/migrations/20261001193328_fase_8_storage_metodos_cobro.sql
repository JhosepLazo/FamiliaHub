create or replace function app_private.puede_subir_comprobante_pago(
	p_pago_id uuid,
	p_usuario_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
	select exists (
		select 1
		from public.pagos_familiares pf
		where pf.id = p_pago_id
			and pf.pagador_usuario_id = p_usuario_id
			and pf.creado_por = p_usuario_id
			and pf.estado = 'BORRADOR'
	);
$$;

create or replace function app_private.puede_ver_pago_proveedor(
	p_pago_id uuid,
	p_usuario_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
	select exists (
		select 1
		from public.pagos_proveedor pp
		where pp.id = p_pago_id
			and app_private.es_miembro(pp.familia_id, p_usuario_id)
	);
$$;

create or replace function app_private.puede_gestionar_pago_proveedor(
	p_pago_id uuid,
	p_usuario_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
	select exists (
		select 1
		from public.pagos_proveedor pp
		where pp.id = p_pago_id
			and app_private.es_admin(pp.familia_id, p_usuario_id)
	);
$$;

revoke all on function app_private.puede_subir_comprobante_pago(uuid, uuid) from public, anon, authenticated;
revoke all on function app_private.puede_ver_pago_proveedor(uuid, uuid) from public, anon, authenticated;
revoke all on function app_private.puede_gestionar_pago_proveedor(uuid, uuid) from public, anon, authenticated;

drop policy if exists familia_cobros_select on storage.objects;
drop policy if exists familia_cobros_insert on storage.objects;
drop policy if exists familia_cobros_update on storage.objects;
drop policy if exists familia_cobros_delete on storage.objects;

create policy familia_cobros_select
on storage.objects
for select
to authenticated
using (
	bucket_id = 'familia-cobros'
	and (storage.foldername(name))[2] = 'miembros'
	and coalesce((storage.foldername(name))[1], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
	and coalesce((storage.foldername(name))[3], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
	and app_private.puede_ver_cobro_miembro(
		((storage.foldername(name))[1])::uuid,
		((storage.foldername(name))[3])::uuid,
		(select auth.uid())
	)
);

create policy familia_cobros_insert
on storage.objects
for insert
to authenticated
with check (
	bucket_id = 'familia-cobros'
	and (storage.foldername(name))[2] = 'miembros'
	and coalesce((storage.foldername(name))[1], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
	and coalesce((storage.foldername(name))[3], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
	and app_private.puede_gestionar_cobro_miembro(
		((storage.foldername(name))[1])::uuid,
		((storage.foldername(name))[3])::uuid,
		(select auth.uid())
	)
);

create policy familia_cobros_update
on storage.objects
for update
to authenticated
using (
	bucket_id = 'familia-cobros'
	and (storage.foldername(name))[2] = 'miembros'
	and coalesce((storage.foldername(name))[1], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
	and coalesce((storage.foldername(name))[3], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
	and app_private.puede_gestionar_cobro_miembro(
		((storage.foldername(name))[1])::uuid,
		((storage.foldername(name))[3])::uuid,
		(select auth.uid())
	)
)
with check (
	bucket_id = 'familia-cobros'
	and app_private.puede_gestionar_cobro_miembro(
		((storage.foldername(name))[1])::uuid,
		((storage.foldername(name))[3])::uuid,
		(select auth.uid())
	)
);

create policy familia_cobros_delete
on storage.objects
for delete
to authenticated
using (
	bucket_id = 'familia-cobros'
	and (storage.foldername(name))[2] = 'miembros'
	and coalesce((storage.foldername(name))[1], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
	and coalesce((storage.foldername(name))[3], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
	and app_private.puede_gestionar_cobro_miembro(
		((storage.foldername(name))[1])::uuid,
		((storage.foldername(name))[3])::uuid,
		(select auth.uid())
	)
);

drop policy if exists familia_comprobantes_select on storage.objects;
drop policy if exists familia_comprobantes_insert on storage.objects;
drop policy if exists familia_comprobantes_delete on storage.objects;

create policy familia_comprobantes_select
on storage.objects
for select
to authenticated
using (
	bucket_id = 'familia-comprobantes'
	and coalesce((storage.foldername(name))[1], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
	and coalesce((storage.foldername(name))[3], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
	and (
		(
			(storage.foldername(name))[2] = 'pagos'
			and app_private.puede_ver_pago_familiar(
				((storage.foldername(name))[3])::uuid,
				(select auth.uid())
			)
		)
		or
		(
			(storage.foldername(name))[2] = 'proveedor'
			and app_private.puede_ver_pago_proveedor(
				((storage.foldername(name))[3])::uuid,
				(select auth.uid())
			)
		)
	)
);

create policy familia_comprobantes_insert
on storage.objects
for insert
to authenticated
with check (
	bucket_id = 'familia-comprobantes'
	and coalesce((storage.foldername(name))[1], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
	and coalesce((storage.foldername(name))[3], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
	and (
		(
			(storage.foldername(name))[2] = 'pagos'
			and app_private.puede_subir_comprobante_pago(
				((storage.foldername(name))[3])::uuid,
				(select auth.uid())
			)
		)
		or
		(
			(storage.foldername(name))[2] = 'proveedor'
			and app_private.puede_gestionar_pago_proveedor(
				((storage.foldername(name))[3])::uuid,
				(select auth.uid())
			)
		)
	)
);

create policy familia_comprobantes_delete
on storage.objects
for delete
to authenticated
using (
	bucket_id = 'familia-comprobantes'
	and coalesce((storage.foldername(name))[3], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
	and (
		(
			(storage.foldername(name))[2] = 'pagos'
			and app_private.puede_subir_comprobante_pago(
				((storage.foldername(name))[3])::uuid,
				(select auth.uid())
			)
		)
		or
		(
			(storage.foldername(name))[2] = 'proveedor'
			and app_private.puede_gestionar_pago_proveedor(
				((storage.foldername(name))[3])::uuid,
				(select auth.uid())
			)
		)
	)
);

create or replace function app_private.guardar_metodo_cobro_familiar_impl(
	p_familia_id uuid,
	p_metodo public.metodo_pago_familiar,
	p_titular text,
	p_referencia text,
	p_instrucciones text,
	p_qr_storage_path text,
	p_responsable_miembro_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_id uuid;
begin
	if v_usuario_id is null or not app_private.es_admin(p_familia_id, v_usuario_id) then
		raise exception 'Solo un administrador puede configurar métodos de cobro familiares.';
	end if;

	if nullif(trim(p_titular), '') is null then
		raise exception 'El titular es obligatorio.';
	end if;

	if p_responsable_miembro_id is null or not exists (
		select 1
		from public.miembros_familia m
		where m.id = p_responsable_miembro_id
			and m.familia_id = p_familia_id
			and m.estado = 'ACTIVO'
	) then
		raise exception 'Selecciona un responsable activo de la familia.';
	end if;

	if p_metodo = 'TRANSFERENCIA' and nullif(trim(coalesce(p_referencia, '')), '') is null then
		raise exception 'La transferencia necesita una cuenta o referencia de destino.';
	end if;

	if p_metodo = 'YAPE'
		and nullif(trim(coalesce(p_referencia, '')), '') is null
		and nullif(trim(coalesce(p_qr_storage_path, '')), '') is null then
		raise exception 'Yape necesita un número o un QR.';
	end if;

	if p_qr_storage_path is not null
		and p_qr_storage_path !~ ('^' || p_familia_id::text || '/') then
		raise exception 'La ruta del QR no pertenece a esta familia.';
	end if;

	insert into public.configuracion_pago_familiar (
		familia_id,
		metodo,
		titular,
		referencia,
		instrucciones,
		qr_storage_path,
		responsable_miembro_id,
		activo,
		updated_at
	)
	values (
		p_familia_id,
		p_metodo,
		trim(p_titular),
		nullif(trim(coalesce(p_referencia, '')), ''),
		nullif(trim(coalesce(p_instrucciones, '')), ''),
		nullif(trim(coalesce(p_qr_storage_path, '')), ''),
		p_responsable_miembro_id,
		true,
		now()
	)
	on conflict (familia_id, metodo)
	do update set
		titular = excluded.titular,
		referencia = excluded.referencia,
		instrucciones = excluded.instrucciones,
		qr_storage_path = excluded.qr_storage_path,
		responsable_miembro_id = excluded.responsable_miembro_id,
		activo = true,
		updated_at = now()
	returning id into v_id;

	return v_id;
end;
$$;

create or replace function app_private.guardar_metodo_cobro_personal_impl(
	p_metodo public.metodo_pago_familiar,
	p_titular text,
	p_referencia text,
	p_instrucciones text,
	p_qr_storage_path text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_miembro public.miembros_familia%rowtype;
	v_id uuid;
begin
	select *
	into v_miembro
	from public.miembros_familia
	where usuario_id = v_usuario_id
		and estado = 'ACTIVO'
	order by joined_at
	limit 1;

	if v_miembro.id is null then
		raise exception 'No perteneces a una familia activa.';
	end if;

	if nullif(trim(p_titular), '') is null then
		raise exception 'El titular es obligatorio.';
	end if;

	if p_metodo = 'TRANSFERENCIA' and nullif(trim(coalesce(p_referencia, '')), '') is null then
		raise exception 'La transferencia necesita una cuenta o referencia de destino.';
	end if;

	if p_metodo = 'YAPE'
		and nullif(trim(coalesce(p_referencia, '')), '') is null
		and nullif(trim(coalesce(p_qr_storage_path, '')), '') is null then
		raise exception 'Yape necesita un número o un QR.';
	end if;

	if p_qr_storage_path is not null
		and p_qr_storage_path !~ (
			'^' || v_miembro.familia_id::text || '/miembros/' || v_miembro.id::text || '/'
		) then
		raise exception 'La ruta del QR no corresponde a tu cuenta de cobro.';
	end if;

	insert into public.configuracion_cobro_miembro (
		familia_id,
		miembro_id,
		metodo,
		titular,
		referencia,
		instrucciones,
		qr_storage_path,
		activo,
		updated_at
	)
	values (
		v_miembro.familia_id,
		v_miembro.id,
		p_metodo,
		trim(p_titular),
		nullif(trim(coalesce(p_referencia, '')), ''),
		nullif(trim(coalesce(p_instrucciones, '')), ''),
		nullif(trim(coalesce(p_qr_storage_path, '')), ''),
		true,
		now()
	)
	on conflict (miembro_id, metodo)
	do update set
		titular = excluded.titular,
		referencia = excluded.referencia,
		instrucciones = excluded.instrucciones,
		qr_storage_path = excluded.qr_storage_path,
		activo = true,
		updated_at = now()
	returning id into v_id;

	return v_id;
end;
$$;

create or replace function app_private.cambiar_estado_metodo_cobro_familiar_impl(
	p_configuracion_id uuid,
	p_activo boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_familia_id uuid;
begin
	select familia_id into v_familia_id
	from public.configuracion_pago_familiar
	where id = p_configuracion_id;

	if v_familia_id is null or not app_private.es_admin(v_familia_id, v_usuario_id) then
		raise exception 'No tienes permiso para modificar este método.';
	end if;

	update public.configuracion_pago_familiar
	set activo = p_activo,
		updated_at = now()
	where id = p_configuracion_id;
end;
$$;

create or replace function app_private.cambiar_estado_metodo_cobro_personal_impl(
	p_configuracion_id uuid,
	p_activo boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
begin
	if not exists (
		select 1
		from public.configuracion_cobro_miembro c
		inner join public.miembros_familia m on m.id = c.miembro_id
		where c.id = p_configuracion_id
			and m.usuario_id = v_usuario_id
	) then
		raise exception 'No tienes permiso para modificar este método.';
	end if;

	update public.configuracion_cobro_miembro
	set activo = p_activo,
		updated_at = now()
	where id = p_configuracion_id;
end;
$$;

revoke all on function app_private.guardar_metodo_cobro_familiar_impl(uuid, public.metodo_pago_familiar, text, text, text, text, uuid) from public, anon;
revoke all on function app_private.guardar_metodo_cobro_personal_impl(public.metodo_pago_familiar, text, text, text, text) from public, anon;
revoke all on function app_private.cambiar_estado_metodo_cobro_familiar_impl(uuid, boolean) from public, anon;
revoke all on function app_private.cambiar_estado_metodo_cobro_personal_impl(uuid, boolean) from public, anon;

grant execute on function app_private.guardar_metodo_cobro_familiar_impl(uuid, public.metodo_pago_familiar, text, text, text, text, uuid) to authenticated;
grant execute on function app_private.guardar_metodo_cobro_personal_impl(public.metodo_pago_familiar, text, text, text, text) to authenticated;
grant execute on function app_private.cambiar_estado_metodo_cobro_familiar_impl(uuid, boolean) to authenticated;
grant execute on function app_private.cambiar_estado_metodo_cobro_personal_impl(uuid, boolean) to authenticated;

create or replace function public.guardar_metodo_cobro_familiar(
	p_familia_id uuid,
	p_metodo public.metodo_pago_familiar,
	p_titular text,
	p_referencia text default null,
	p_instrucciones text default null,
	p_qr_storage_path text default null,
	p_responsable_miembro_id uuid default null
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
	select app_private.guardar_metodo_cobro_familiar_impl(
		p_familia_id,
		p_metodo,
		p_titular,
		p_referencia,
		p_instrucciones,
		p_qr_storage_path,
		p_responsable_miembro_id
	);
$$;

create or replace function public.guardar_metodo_cobro_personal(
	p_metodo public.metodo_pago_familiar,
	p_titular text,
	p_referencia text default null,
	p_instrucciones text default null,
	p_qr_storage_path text default null
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
	select app_private.guardar_metodo_cobro_personal_impl(
		p_metodo,
		p_titular,
		p_referencia,
		p_instrucciones,
		p_qr_storage_path
	);
$$;

create or replace function public.cambiar_estado_metodo_cobro_familiar(
	p_configuracion_id uuid,
	p_activo boolean
)
returns void
language sql
security invoker
set search_path = ''
as $$
	select app_private.cambiar_estado_metodo_cobro_familiar_impl(p_configuracion_id, p_activo);
$$;

create or replace function public.cambiar_estado_metodo_cobro_personal(
	p_configuracion_id uuid,
	p_activo boolean
)
returns void
language sql
security invoker
set search_path = ''
as $$
	select app_private.cambiar_estado_metodo_cobro_personal_impl(p_configuracion_id, p_activo);
$$;

revoke all on function public.guardar_metodo_cobro_familiar(uuid, public.metodo_pago_familiar, text, text, text, text, uuid) from public, anon;
revoke all on function public.guardar_metodo_cobro_personal(public.metodo_pago_familiar, text, text, text, text) from public, anon;
revoke all on function public.cambiar_estado_metodo_cobro_familiar(uuid, boolean) from public, anon;
revoke all on function public.cambiar_estado_metodo_cobro_personal(uuid, boolean) from public, anon;

grant execute on function public.guardar_metodo_cobro_familiar(uuid, public.metodo_pago_familiar, text, text, text, text, uuid) to authenticated;
grant execute on function public.guardar_metodo_cobro_personal(public.metodo_pago_familiar, text, text, text, text) to authenticated;
grant execute on function public.cambiar_estado_metodo_cobro_familiar(uuid, boolean) to authenticated;
grant execute on function public.cambiar_estado_metodo_cobro_personal(uuid, boolean) to authenticated;
