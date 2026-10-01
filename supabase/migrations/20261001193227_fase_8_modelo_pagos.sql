alter table public.configuracion_pago_familiar
	drop constraint if exists configuracion_pago_familiar_familia_id_key;

alter table public.configuracion_pago_familiar
	alter column referencia drop not null;

alter table public.configuracion_pago_familiar
	add column if not exists responsable_miembro_id uuid references public.miembros_familia(id);

create unique index if not exists ux_config_pago_familiar_metodo
on public.configuracion_pago_familiar(familia_id, metodo);

create index if not exists idx_config_pago_familiar_responsable
on public.configuracion_pago_familiar(responsable_miembro_id)
where responsable_miembro_id is not null;

drop policy if exists configuracion_pago_insert_admin on public.configuracion_pago_familiar;
drop policy if exists configuracion_pago_update_admin on public.configuracion_pago_familiar;

revoke all on table public.configuracion_pago_familiar from anon, authenticated;
grant select on table public.configuracion_pago_familiar to authenticated;

create table public.configuracion_cobro_miembro (
	id uuid primary key default gen_random_uuid(),
	familia_id uuid not null references public.familias(id) on delete cascade,
	miembro_id uuid not null references public.miembros_familia(id) on delete cascade,
	metodo public.metodo_pago_familiar not null,
	titular text not null,
	referencia text,
	qr_storage_path text,
	instrucciones text,
	activo boolean not null default true,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now(),
	unique (miembro_id, metodo)
);

create index idx_config_cobro_miembro_familia on public.configuracion_cobro_miembro(familia_id);
create index idx_config_cobro_miembro_activo on public.configuracion_cobro_miembro(miembro_id, activo);

create type public.estado_pago_familiar as enum (
	'BORRADOR',
	'POR_VALIDAR',
	'CONFIRMADO',
	'RECHAZADO',
	'ANULADO'
);

create table public.pagos_familiares (
	id uuid primary key default gen_random_uuid(),
	familia_id uuid not null references public.familias(id) on delete cascade,
	pagador_miembro_id uuid not null references public.miembros_familia(id),
	pagador_usuario_id uuid not null references auth.users(id),
	pagador_nombre_snapshot text not null,
	destino public.destino_aporte not null,
	receptor_miembro_id uuid references public.miembros_familia(id),
	responsable_receptor_miembro_id uuid references public.miembros_familia(id),
	receptor_nombre_snapshot text not null,
	metodo public.metodo_pago_familiar not null,
	receptor_titular_snapshot text not null,
	receptor_referencia_snapshot text,
	receptor_qr_bucket text,
	receptor_qr_storage_path text,
	monto_total numeric(12,2) not null check (monto_total > 0),
	estado public.estado_pago_familiar not null default 'BORRADOR',
	fecha_pago date,
	referencia_operacion text,
	comprobante_bucket text,
	comprobante_storage_path text,
	creado_por uuid not null references auth.users(id),
	enviado_at timestamptz,
	validado_por uuid references auth.users(id),
	validado_at timestamptz,
	rechazo_motivo text,
	anulado_por uuid references auth.users(id),
	anulado_at timestamptz,
	anulacion_motivo text,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now(),
	check (
		(destino = 'FONDO_FAMILIAR' and receptor_miembro_id is null)
		or
		(destino = 'INTEGRANTE' and receptor_miembro_id is not null)
	)
);

create index idx_pagos_familiares_familia on public.pagos_familiares(familia_id, created_at desc);
create index idx_pagos_familiares_pagador on public.pagos_familiares(pagador_miembro_id, estado);
create index idx_pagos_familiares_receptor on public.pagos_familiares(receptor_miembro_id, estado) where receptor_miembro_id is not null;
create index idx_pagos_familiares_responsable on public.pagos_familiares(responsable_receptor_miembro_id, estado) where responsable_receptor_miembro_id is not null;
create index idx_pagos_familiares_usuario on public.pagos_familiares(pagador_usuario_id, estado);
create index idx_pagos_familiares_validado_por on public.pagos_familiares(validado_por) where validado_por is not null;
create index idx_pagos_familiares_anulado_por on public.pagos_familiares(anulado_por) where anulado_por is not null;

create table public.pago_asignaciones (
	id uuid primary key default gen_random_uuid(),
	pago_id uuid not null references public.pagos_familiares(id) on delete cascade,
	cuota_id uuid not null references public.cuotas(id),
	recibo_id uuid not null references public.recibos(id),
	monto numeric(12,2) not null check (monto > 0),
	created_at timestamptz not null default now(),
	unique (pago_id, cuota_id)
);

create index idx_pago_asignaciones_pago on public.pago_asignaciones(pago_id);
create index idx_pago_asignaciones_cuota on public.pago_asignaciones(cuota_id);
create index idx_pago_asignaciones_recibo on public.pago_asignaciones(recibo_id);

alter table public.aportes
	add column if not exists pago_familiar_id uuid references public.pagos_familiares(id),
	add column if not exists pago_asignacion_id uuid references public.pago_asignaciones(id);

create index idx_aportes_pago_familiar on public.aportes(pago_familiar_id) where pago_familiar_id is not null;
create unique index ux_aportes_pago_asignacion on public.aportes(pago_asignacion_id) where pago_asignacion_id is not null;

alter table public.pagos_proveedor
	add column if not exists comprobante_bucket text,
	add column if not exists comprobante_storage_path text;

alter table public.configuracion_cobro_miembro enable row level security;
alter table public.pagos_familiares enable row level security;
alter table public.pago_asignaciones enable row level security;

revoke all on table public.configuracion_cobro_miembro from anon, authenticated;
revoke all on table public.pagos_familiares from anon, authenticated;
revoke all on table public.pago_asignaciones from anon, authenticated;

grant select on table public.configuracion_cobro_miembro to authenticated;
grant select on table public.pagos_familiares to authenticated;
grant select on table public.pago_asignaciones to authenticated;

create or replace function app_private.puede_ver_pago_familiar(
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
			and (
				pf.pagador_usuario_id = p_usuario_id
				or app_private.es_admin(pf.familia_id, p_usuario_id)
				or exists (
					select 1
					from public.miembros_familia m
					where m.id = pf.responsable_receptor_miembro_id
						and m.usuario_id = p_usuario_id
				)
			)
	);
$$;

create or replace function app_private.puede_gestionar_cobro_miembro(
	p_familia_id uuid,
	p_miembro_id uuid,
	p_usuario_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
	select
		app_private.es_admin(p_familia_id, p_usuario_id)
		or exists (
			select 1
			from public.miembros_familia m
			where m.id = p_miembro_id
				and m.familia_id = p_familia_id
				and m.usuario_id = p_usuario_id
				and m.estado = 'ACTIVO'
		);
$$;

create or replace function app_private.puede_ver_cobro_miembro(
	p_familia_id uuid,
	p_miembro_id uuid,
	p_usuario_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
	select
		app_private.puede_gestionar_cobro_miembro(p_familia_id, p_miembro_id, p_usuario_id)
		or exists (
			select 1
			from public.cuotas q
			where q.familia_id = p_familia_id
				and q.usuario_id = p_usuario_id
				and q.receptor_miembro_id = p_miembro_id
				and q.estado <> 'ANULADA'
		);
$$;

revoke all on function app_private.puede_ver_pago_familiar(uuid, uuid) from public, anon, authenticated;
revoke all on function app_private.puede_gestionar_cobro_miembro(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function app_private.puede_ver_cobro_miembro(uuid, uuid, uuid) from public, anon, authenticated;

create policy config_cobro_miembro_select
on public.configuracion_cobro_miembro
for select
to authenticated
using (
	app_private.puede_ver_cobro_miembro(
		familia_id,
		miembro_id,
		(select auth.uid())
	)
);

create policy pagos_familiares_select
on public.pagos_familiares
for select
to authenticated
using (
	app_private.puede_ver_pago_familiar(id, (select auth.uid()))
);

create policy pago_asignaciones_select
on public.pago_asignaciones
for select
to authenticated
using (
	app_private.puede_ver_pago_familiar(pago_id, (select auth.uid()))
);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
	('familia-cobros', 'familia-cobros', false, 5242880, array['image/png','image/jpeg','image/webp']),
	('familia-comprobantes', 'familia-comprobantes', false, 8388608, array['image/png','image/jpeg','image/webp','application/pdf'])
on conflict (id) do update
set public = excluded.public,
	file_size_limit = excluded.file_size_limit,
	allowed_mime_types = excluded.allowed_mime_types;
