create or replace function app_private.guardar_metodo_cobro_personal_impl(
	p_familia_id uuid,
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
	where familia_id = p_familia_id
		and usuario_id = v_usuario_id
		and estado = 'ACTIVO';

	if v_miembro.id is null then
		raise exception 'No perteneces a esta familia o tu membresía no está activa.';
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
			'^' || p_familia_id::text || '/miembros/' || v_miembro.id::text || '/'
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
		p_familia_id,
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

revoke all on function app_private.guardar_metodo_cobro_personal_impl(uuid, public.metodo_pago_familiar, text, text, text, text) from public, anon;
grant execute on function app_private.guardar_metodo_cobro_personal_impl(uuid, public.metodo_pago_familiar, text, text, text, text) to authenticated;

drop function if exists public.guardar_metodo_cobro_personal(public.metodo_pago_familiar, text, text, text, text);

create or replace function public.guardar_metodo_cobro_personal(
	p_familia_id uuid,
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
		p_familia_id,
		p_metodo,
		p_titular,
		p_referencia,
		p_instrucciones,
		p_qr_storage_path
	);
$$;

revoke all on function public.guardar_metodo_cobro_personal(uuid, public.metodo_pago_familiar, text, text, text, text) from public, anon;
grant execute on function public.guardar_metodo_cobro_personal(uuid, public.metodo_pago_familiar, text, text, text, text) to authenticated;
