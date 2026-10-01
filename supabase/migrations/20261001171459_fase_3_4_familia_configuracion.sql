alter table public.invitaciones add column nombre text;

create unique index ux_miembros_familia_usuario_activo
on public.miembros_familia(usuario_id)
where estado = 'ACTIVO';

create type public.metodo_pago_familiar as enum ('YAPE', 'TRANSFERENCIA', 'EFECTIVO', 'OTRO');

create table public.configuracion_pago_familiar (
	id uuid primary key default gen_random_uuid(),
	familia_id uuid not null unique references public.familias(id) on delete cascade,
	metodo public.metodo_pago_familiar not null default 'YAPE',
	titular text not null,
	referencia text not null,
	qr_storage_path text,
	instrucciones text,
	activo boolean not null default true,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);

create index idx_configuracion_pago_familia on public.configuracion_pago_familiar(familia_id);

alter table public.configuracion_pago_familiar enable row level security;

create policy configuracion_pago_select_miembro
on public.configuracion_pago_familiar
for select
to authenticated
using (app_private.es_miembro(familia_id, (select auth.uid())));

create policy configuracion_pago_insert_admin
on public.configuracion_pago_familiar
for insert
to authenticated
with check (app_private.es_admin(familia_id, (select auth.uid())));

create policy configuracion_pago_update_admin
on public.configuracion_pago_familiar
for update
to authenticated
using (app_private.es_admin(familia_id, (select auth.uid())))
with check (app_private.es_admin(familia_id, (select auth.uid())));

grant select, insert on public.configuracion_pago_familiar to authenticated;
grant update (metodo, titular, referencia, qr_storage_path, instrucciones, activo, updated_at)
on public.configuracion_pago_familiar to authenticated;

revoke update on public.familias from authenticated;
grant update (nombre, moneda, zona_horaria, activo, updated_at) on public.familias to authenticated;

revoke update on public.miembros_familia from authenticated;
grant update (rol, estado) on public.miembros_familia to authenticated;

revoke insert, update on public.invitaciones from authenticated;
grant update (estado) on public.invitaciones to authenticated;

revoke update on public.categorias from authenticated;
grant update (nombre, icono, activo) on public.categorias to authenticated;

create or replace function app_private.validar_ultimo_administrador()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
	if old.rol = 'ADMINISTRADOR'
		and old.estado = 'ACTIVO'
		and (new.rol <> 'ADMINISTRADOR' or new.estado <> 'ACTIVO')
		and not exists (
			select 1
			from public.miembros_familia
			where familia_id = old.familia_id
				and id <> old.id
				and rol = 'ADMINISTRADOR'
				and estado = 'ACTIVO'
		)
	then
		raise exception 'La familia debe conservar al menos un administrador activo.';
	end if;

	return new;
end;
$$;

create trigger validar_ultimo_administrador
before update of rol, estado on public.miembros_familia
for each row execute function app_private.validar_ultimo_administrador();

create or replace function public.crear_familia_inicial(p_nombre text)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_familia_id uuid;
	v_fecha timestamp := timezone('America/Lima', now());
begin
	if v_usuario_id is null then
		raise exception 'Debes iniciar sesión.';
	end if;

	if nullif(trim(p_nombre), '') is null then
		raise exception 'El nombre de la familia es obligatorio.';
	end if;

	if exists (
		select 1
		from public.miembros_familia
		where usuario_id = v_usuario_id
			and estado = 'ACTIVO'
	) then
		raise exception 'Ya perteneces a una familia activa.';
	end if;

	insert into public.familias (nombre, creado_por)
	values (trim(p_nombre), v_usuario_id)
	returning id into v_familia_id;

	insert into public.miembros_familia (familia_id, usuario_id, rol)
	values (v_familia_id, v_usuario_id, 'ADMINISTRADOR');

	insert into public.periodos (familia_id, anio, mes)
	values (
		v_familia_id,
		extract(year from v_fecha)::smallint,
		extract(month from v_fecha)::smallint
	);

	insert into public.categorias (familia_id, nombre, icono)
	values
		(v_familia_id, 'Servicios', 'house-plug'),
		(v_familia_id, 'Vivienda', 'house'),
		(v_familia_id, 'Educación', 'graduation-cap'),
		(v_familia_id, 'Suscripciones', 'repeat-2'),
		(v_familia_id, 'Hogar', 'shopping-basket'),
		(v_familia_id, 'Otros', 'shapes');

	return v_familia_id;
end;
$$;

revoke all on function public.crear_familia_inicial(text) from public;
grant execute on function public.crear_familia_inicial(text) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
	'familia-configuracion',
	'familia-configuracion',
	false,
	5242880,
	array['image/png', 'image/jpeg', 'image/webp']
)
on conflict (id) do nothing;

create policy familia_config_storage_select
on storage.objects
for select
to authenticated
using (
	bucket_id = 'familia-configuracion'
	and case
		when coalesce((storage.foldername(name))[1], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
		then app_private.es_miembro(((storage.foldername(name))[1])::uuid, (select auth.uid()))
		else false
	end
);

create policy familia_config_storage_insert
on storage.objects
for insert
to authenticated
with check (
	bucket_id = 'familia-configuracion'
	and case
		when coalesce((storage.foldername(name))[1], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
		then app_private.es_admin(((storage.foldername(name))[1])::uuid, (select auth.uid()))
		else false
	end
);

create policy familia_config_storage_update
on storage.objects
for update
to authenticated
using (
	bucket_id = 'familia-configuracion'
	and case
		when coalesce((storage.foldername(name))[1], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
		then app_private.es_admin(((storage.foldername(name))[1])::uuid, (select auth.uid()))
		else false
	end
)
with check (
	bucket_id = 'familia-configuracion'
	and case
		when coalesce((storage.foldername(name))[1], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
		then app_private.es_admin(((storage.foldername(name))[1])::uuid, (select auth.uid()))
		else false
	end
);

create policy familia_config_storage_delete
on storage.objects
for delete
to authenticated
using (
	bucket_id = 'familia-configuracion'
	and case
		when coalesce((storage.foldername(name))[1], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
		then app_private.es_admin(((storage.foldername(name))[1])::uuid, (select auth.uid()))
		else false
	end
);
