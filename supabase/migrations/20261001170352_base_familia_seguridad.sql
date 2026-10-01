create schema if not exists app_private;

create type public.rol_familia as enum ('ADMINISTRADOR', 'INTEGRANTE');
create type public.estado_miembro as enum ('ACTIVO', 'INACTIVO');
create type public.estado_invitacion as enum ('PENDIENTE', 'ACEPTADA', 'EXPIRADA', 'REVOCADA');
create type public.estado_periodo as enum ('ABIERTO', 'COMPLETADO');

create table public.perfiles (
	id uuid primary key references auth.users(id) on delete cascade,
	nombre text,
	avatar_url text,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);

create table public.familias (
	id uuid primary key default gen_random_uuid(),
	nombre text not null,
	moneda char(3) not null default 'PEN',
	zona_horaria text not null default 'America/Lima',
	creado_por uuid not null references auth.users(id),
	activo boolean not null default true,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);

create table public.miembros_familia (
	id uuid primary key default gen_random_uuid(),
	familia_id uuid not null references public.familias(id) on delete cascade,
	usuario_id uuid not null references auth.users(id) on delete cascade,
	rol public.rol_familia not null default 'INTEGRANTE',
	estado public.estado_miembro not null default 'ACTIVO',
	joined_at timestamptz not null default now(),
	unique (familia_id, usuario_id)
);

create table public.invitaciones (
	id uuid primary key default gen_random_uuid(),
	familia_id uuid not null references public.familias(id) on delete cascade,
	email text not null,
	rol public.rol_familia not null default 'INTEGRANTE',
	token_hash text not null unique,
	expira_at timestamptz not null,
	estado public.estado_invitacion not null default 'PENDIENTE',
	creado_por uuid not null references auth.users(id),
	created_at timestamptz not null default now(),
	aceptada_at timestamptz
);

create table public.categorias (
	id uuid primary key default gen_random_uuid(),
	familia_id uuid not null references public.familias(id) on delete cascade,
	nombre text not null,
	icono text,
	activo boolean not null default true,
	created_at timestamptz not null default now(),
	unique (familia_id, nombre)
);

create table public.periodos (
	id uuid primary key default gen_random_uuid(),
	familia_id uuid not null references public.familias(id) on delete cascade,
	anio smallint not null check (anio between 2000 and 2100),
	mes smallint not null check (mes between 1 and 12),
	estado public.estado_periodo not null default 'ABIERTO',
	created_at timestamptz not null default now(),
	completado_at timestamptz,
	unique (familia_id, anio, mes)
);

create index idx_miembros_familia_usuario on public.miembros_familia(usuario_id, familia_id);
create index idx_invitaciones_familia_estado on public.invitaciones(familia_id, estado);
create index idx_categorias_familia on public.categorias(familia_id);
create index idx_periodos_familia_fecha on public.periodos(familia_id, anio desc, mes desc);

create or replace function app_private.es_miembro(p_familia_id uuid, p_usuario_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
	select exists (
		select 1
		from public.miembros_familia
		where familia_id = p_familia_id
			and usuario_id = p_usuario_id
			and estado = 'ACTIVO'
	);
$$;

create or replace function app_private.es_admin(p_familia_id uuid, p_usuario_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
	select exists (
		select 1
		from public.miembros_familia
		where familia_id = p_familia_id
			and usuario_id = p_usuario_id
			and rol = 'ADMINISTRADOR'
			and estado = 'ACTIVO'
	);
$$;

revoke all on function app_private.es_miembro(uuid, uuid) from public;
revoke all on function app_private.es_admin(uuid, uuid) from public;
grant execute on function app_private.es_miembro(uuid, uuid) to authenticated;
grant execute on function app_private.es_admin(uuid, uuid) to authenticated;

create or replace function app_private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
	insert into public.perfiles (id, nombre)
	values (new.id, nullif(trim(coalesce(new.raw_user_meta_data ->> 'nombre', '')), ''))
	on conflict (id) do nothing;

	return new;
end;
$$;

revoke all on function app_private.handle_new_user() from public;

create trigger on_auth_user_created
	after insert on auth.users
	for each row execute function app_private.handle_new_user();

alter table public.perfiles enable row level security;
alter table public.familias enable row level security;
alter table public.miembros_familia enable row level security;
alter table public.invitaciones enable row level security;
alter table public.categorias enable row level security;
alter table public.periodos enable row level security;

create policy perfiles_select_familia
on public.perfiles
for select
to authenticated
using (
	id = (select auth.uid())
	or exists (
		select 1
		from public.miembros_familia mf_actual
		join public.miembros_familia mf_objetivo on mf_actual.familia_id = mf_objetivo.familia_id
		where mf_actual.usuario_id = (select auth.uid())
			and mf_actual.estado = 'ACTIVO'
			and mf_objetivo.usuario_id = perfiles.id
			and mf_objetivo.estado = 'ACTIVO'
	)
);

create policy perfiles_update_propio
on public.perfiles
for update
to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

create policy familias_select_miembro
on public.familias
for select
to authenticated
using (
	creado_por = (select auth.uid())
	or app_private.es_miembro(id, (select auth.uid()))
);

create policy familias_insert_propietario
on public.familias
for insert
to authenticated
with check (creado_por = (select auth.uid()));

create policy familias_update_admin
on public.familias
for update
to authenticated
using (app_private.es_admin(id, (select auth.uid())))
with check (app_private.es_admin(id, (select auth.uid())));

create policy miembros_select_familia
on public.miembros_familia
for select
to authenticated
using (
	usuario_id = (select auth.uid())
	or app_private.es_miembro(familia_id, (select auth.uid()))
);

create policy miembros_insert_admin_o_creador
on public.miembros_familia
for insert
to authenticated
with check (
	app_private.es_admin(familia_id, (select auth.uid()))
	or (
		usuario_id = (select auth.uid())
		and rol = 'ADMINISTRADOR'
		and exists (
			select 1
			from public.familias f
			where f.id = miembros_familia.familia_id
				and f.creado_por = (select auth.uid())
		)
	)
);

create policy miembros_update_admin
on public.miembros_familia
for update
to authenticated
using (app_private.es_admin(familia_id, (select auth.uid())))
with check (app_private.es_admin(familia_id, (select auth.uid())));

create policy invitaciones_select_admin
on public.invitaciones
for select
to authenticated
using (app_private.es_admin(familia_id, (select auth.uid())));

create policy invitaciones_insert_admin
on public.invitaciones
for insert
to authenticated
with check (
	app_private.es_admin(familia_id, (select auth.uid()))
	and creado_por = (select auth.uid())
);

create policy invitaciones_update_admin
on public.invitaciones
for update
to authenticated
using (app_private.es_admin(familia_id, (select auth.uid())))
with check (app_private.es_admin(familia_id, (select auth.uid())));

create policy categorias_select_miembro
on public.categorias
for select
to authenticated
using (app_private.es_miembro(familia_id, (select auth.uid())));

create policy categorias_insert_admin
on public.categorias
for insert
to authenticated
with check (app_private.es_admin(familia_id, (select auth.uid())));

create policy categorias_update_admin
on public.categorias
for update
to authenticated
using (app_private.es_admin(familia_id, (select auth.uid())))
with check (app_private.es_admin(familia_id, (select auth.uid())));

create policy periodos_select_miembro
on public.periodos
for select
to authenticated
using (app_private.es_miembro(familia_id, (select auth.uid())));

create policy periodos_insert_admin
on public.periodos
for insert
to authenticated
with check (app_private.es_admin(familia_id, (select auth.uid())));

create policy periodos_update_admin
on public.periodos
for update
to authenticated
using (app_private.es_admin(familia_id, (select auth.uid())))
with check (app_private.es_admin(familia_id, (select auth.uid())));

grant usage on schema public to authenticated;
grant select, update on public.perfiles to authenticated;
grant select, insert, update on public.familias to authenticated;
grant select, insert, update on public.miembros_familia to authenticated;
grant select, insert, update on public.invitaciones to authenticated;
grant select, insert, update on public.categorias to authenticated;
grant select, insert, update on public.periodos to authenticated;
