alter table public.conceptos_pago
	add column fecha_inicio_generacion date not null default (timezone('America/Lima', now()))::date,
	add column dias_anticipacion_aporte smallint not null default 2;

alter table public.conceptos_pago
	add constraint conceptos_pago_dias_anticipacion_check
	check (dias_anticipacion_aporte between 0 and 31);

create type public.estado_recibo as enum (
	'ESPERANDO_MONTO',
	'PENDIENTE',
	'PAGADO',
	'VENCIDO',
	'ANULADO',
	'REQUIERE_REVISION'
);

create type public.estado_recaudacion as enum (
	'PENDIENTE',
	'PARCIAL',
	'COMPLETA'
);

create type public.estado_cuota as enum (
	'PENDIENTE',
	'PARCIAL',
	'POR_VALIDAR',
	'PAGADA',
	'RECHAZADA',
	'ANULADA'
);

create type public.estado_aporte as enum (
	'POR_VALIDAR',
	'CONFIRMADO',
	'RECHAZADO',
	'ANULADO'
);

create type public.tipo_aporte as enum (
	'APORTE_FAMILIAR',
	'REEMBOLSO',
	'COBERTURA_ADELANTO'
);

create type public.destino_aporte as enum (
	'FONDO_FAMILIAR',
	'INTEGRANTE'
);

create type public.origen_pago_proveedor as enum (
	'FONDO_FAMILIAR',
	'ADELANTO_INTEGRANTE'
);

create type public.estado_pago_proveedor as enum (
	'CONFIRMADO',
	'ANULADO'
);

create type public.estado_ajuste_recibo as enum (
	'APLICADO',
	'ANULADO'
);

create type public.tipo_cierre_periodo as enum (
	'AUTOMATICO',
	'MANUAL'
);

alter table public.periodos
	add column cierre_tipo public.tipo_cierre_periodo,
	add column completado_por uuid references auth.users(id),
	add column motivo_cierre text;

create index idx_periodos_completado_por on public.periodos(completado_por);

create table public.recibos (
	id uuid primary key default gen_random_uuid(),
	familia_id uuid not null references public.familias(id) on delete cascade,
	periodo_id uuid not null references public.periodos(id) on delete cascade,
	concepto_id uuid not null references public.conceptos_pago(id),
	nombre_concepto text not null,
	categoria_nombre text not null,
	proveedor_nombre text not null,
	tipo_servicio public.tipo_servicio not null,
	frecuencia public.frecuencia_concepto not null,
	metodo_obtencion public.metodo_obtencion_monto not null,
	tipo_vencimiento public.tipo_vencimiento_concepto not null,
	tipo_distribucion public.tipo_distribucion_concepto not null,
	reparto_resto public.tipo_reparto_resto,
	dias_anticipacion_aporte smallint not null check (dias_anticipacion_aporte between 0 and 31),
	monto_base numeric(12,2),
	monto_ajustes numeric(12,2) not null default 0,
	monto_total numeric(12,2) generated always as (
		case
			when monto_base is null then null
			else monto_base + monto_ajustes
		end
	) stored,
	fecha_vencimiento date,
	fecha_limite_aporte date,
	estado public.estado_recibo not null default 'ESPERANDO_MONTO',
	estado_recaudacion public.estado_recaudacion not null default 'PENDIENTE',
	monto_confirmado_at timestamptz,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now(),
	unique (periodo_id, concepto_id),
	check (monto_base is null or monto_base > 0),
	check (monto_base is null or monto_base + monto_ajustes > 0),
	check (fecha_limite_aporte is null or fecha_vencimiento is null or fecha_limite_aporte <= fecha_vencimiento)
);

create index idx_recibos_familia_periodo on public.recibos(familia_id, periodo_id);
create index idx_recibos_periodo_estado on public.recibos(periodo_id, estado);
create index idx_recibos_concepto on public.recibos(concepto_id);
create index idx_recibos_vencimiento on public.recibos(fecha_vencimiento) where estado in ('PENDIENTE', 'VENCIDO');

create table public.recibo_cuentas_snapshot (
	id uuid primary key default gen_random_uuid(),
	recibo_id uuid not null unique references public.recibos(id) on delete cascade,
	identificador_nombre text not null,
	identificador_valor text not null,
	alias text,
	created_at timestamptz not null default now()
);

create index idx_recibo_cuentas_snapshot_recibo on public.recibo_cuentas_snapshot(recibo_id);

create table public.recibo_participantes_snapshot (
	id uuid primary key default gen_random_uuid(),
	recibo_id uuid not null references public.recibos(id) on delete cascade,
	miembro_id uuid not null references public.miembros_familia(id),
	usuario_id uuid not null references auth.users(id),
	nombre_miembro text not null,
	modalidad public.modalidad_participante_concepto not null,
	valor numeric(12,4),
	orden smallint not null check (orden > 0),
	created_at timestamptz not null default now(),
	unique (recibo_id, miembro_id)
);

create index idx_recibo_participantes_recibo on public.recibo_participantes_snapshot(recibo_id, orden);
create index idx_recibo_participantes_miembro on public.recibo_participantes_snapshot(miembro_id);
create index idx_recibo_participantes_usuario on public.recibo_participantes_snapshot(usuario_id);

create table public.cuotas (
	id uuid primary key default gen_random_uuid(),
	familia_id uuid not null references public.familias(id) on delete cascade,
	recibo_id uuid not null references public.recibos(id) on delete cascade,
	miembro_id uuid not null references public.miembros_familia(id),
	usuario_id uuid not null references auth.users(id),
	nombre_miembro text not null,
	monto_asignado numeric(12,2) not null check (monto_asignado > 0),
	monto_pagado numeric(12,2) not null default 0 check (monto_pagado >= 0),
	saldo_pendiente numeric(12,2) generated always as (monto_asignado - monto_pagado) stored,
	estado public.estado_cuota not null default 'PENDIENTE',
	destino public.destino_aporte not null default 'FONDO_FAMILIAR',
	receptor_miembro_id uuid references public.miembros_familia(id),
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now(),
	unique (recibo_id, miembro_id),
	check (monto_pagado <= monto_asignado),
	check (
		(destino = 'FONDO_FAMILIAR' and receptor_miembro_id is null)
		or
		(destino = 'INTEGRANTE' and receptor_miembro_id is not null)
	)
);

create index idx_cuotas_familia_usuario on public.cuotas(familia_id, usuario_id);
create index idx_cuotas_recibo_estado on public.cuotas(recibo_id, estado);
create index idx_cuotas_miembro on public.cuotas(miembro_id);
create index idx_cuotas_receptor on public.cuotas(receptor_miembro_id) where receptor_miembro_id is not null;

create table public.aportes (
	id uuid primary key default gen_random_uuid(),
	familia_id uuid not null references public.familias(id) on delete cascade,
	recibo_id uuid not null references public.recibos(id) on delete cascade,
	cuota_id uuid not null references public.cuotas(id) on delete cascade,
	pagador_miembro_id uuid not null references public.miembros_familia(id),
	receptor_miembro_id uuid references public.miembros_familia(id),
	destino public.destino_aporte not null,
	tipo public.tipo_aporte not null,
	metodo public.metodo_pago_familiar,
	monto numeric(12,2) not null check (monto > 0),
	estado public.estado_aporte not null default 'POR_VALIDAR',
	referencia text,
	nota text,
	creado_por uuid references auth.users(id),
	validado_por uuid references auth.users(id),
	validado_at timestamptz,
	rechazo_motivo text,
	anulado_por uuid references auth.users(id),
	anulado_at timestamptz,
	anulacion_motivo text,
	created_at timestamptz not null default now(),
	check (
		(destino = 'FONDO_FAMILIAR' and receptor_miembro_id is null)
		or
		(destino = 'INTEGRANTE' and receptor_miembro_id is not null)
	),
	check (
		(tipo = 'COBERTURA_ADELANTO' and metodo is null)
		or
		(tipo <> 'COBERTURA_ADELANTO' and metodo is not null)
	)
);

create index idx_aportes_cuota_estado on public.aportes(cuota_id, estado);
create index idx_aportes_recibo on public.aportes(recibo_id);
create index idx_aportes_pagador on public.aportes(pagador_miembro_id);
create index idx_aportes_receptor on public.aportes(receptor_miembro_id) where receptor_miembro_id is not null;
create index idx_aportes_creado_por on public.aportes(creado_por);
create index idx_aportes_validado_por on public.aportes(validado_por) where validado_por is not null;

create table public.pagos_proveedor (
	id uuid primary key default gen_random_uuid(),
	familia_id uuid not null references public.familias(id) on delete cascade,
	recibo_id uuid not null references public.recibos(id) on delete cascade,
	origen public.origen_pago_proveedor not null,
	pagador_miembro_id uuid references public.miembros_familia(id),
	pagador_nombre_snapshot text,
	monto numeric(12,2) not null check (monto > 0),
	fecha_pago date not null,
	estado public.estado_pago_proveedor not null default 'CONFIRMADO',
	referencia text,
	nota text,
	creado_por uuid references auth.users(id),
	anulado_por uuid references auth.users(id),
	anulado_at timestamptz,
	anulacion_motivo text,
	created_at timestamptz not null default now(),
	check (
		(origen = 'FONDO_FAMILIAR' and pagador_miembro_id is null)
		or
		(origen = 'ADELANTO_INTEGRANTE' and pagador_miembro_id is not null)
	)
);

create unique index ux_pagos_proveedor_activo
on public.pagos_proveedor(recibo_id)
where estado = 'CONFIRMADO';

create index idx_pagos_proveedor_familia on public.pagos_proveedor(familia_id);
create index idx_pagos_proveedor_pagador on public.pagos_proveedor(pagador_miembro_id) where pagador_miembro_id is not null;
create index idx_pagos_proveedor_creado_por on public.pagos_proveedor(creado_por);

create table public.recibo_ajustes (
	id uuid primary key default gen_random_uuid(),
	familia_id uuid not null references public.familias(id) on delete cascade,
	recibo_id uuid not null references public.recibos(id) on delete cascade,
	monto_anterior numeric(12,2) not null,
	monto_nuevo numeric(12,2) not null,
	delta numeric(12,2) not null,
	motivo text not null,
	estado public.estado_ajuste_recibo not null default 'APLICADO',
	creado_por uuid references auth.users(id),
	anulado_por uuid references auth.users(id),
	anulado_at timestamptz,
	anulacion_motivo text,
	created_at timestamptz not null default now(),
	check (monto_anterior > 0),
	check (monto_nuevo > 0),
	check (delta <> 0)
);

create index idx_recibo_ajustes_recibo on public.recibo_ajustes(recibo_id);
create index idx_recibo_ajustes_familia on public.recibo_ajustes(familia_id);
create index idx_recibo_ajustes_creado_por on public.recibo_ajustes(creado_por);

create table public.eventos_financieros (
	id bigint generated always as identity primary key,
	familia_id uuid not null references public.familias(id) on delete cascade,
	entidad text not null,
	entidad_id uuid,
	evento text not null,
	detalle jsonb not null default '{}'::jsonb,
	usuario_id uuid references auth.users(id),
	created_at timestamptz not null default now()
);

create index idx_eventos_financieros_familia_fecha on public.eventos_financieros(familia_id, created_at desc);
create index idx_eventos_financieros_entidad on public.eventos_financieros(entidad, entidad_id);

alter table public.recibos enable row level security;
alter table public.recibo_cuentas_snapshot enable row level security;
alter table public.recibo_participantes_snapshot enable row level security;
alter table public.cuotas enable row level security;
alter table public.aportes enable row level security;
alter table public.pagos_proveedor enable row level security;
alter table public.recibo_ajustes enable row level security;
alter table public.eventos_financieros enable row level security;

create policy recibos_select_miembro
on public.recibos for select to authenticated
using (app_private.es_miembro(familia_id, (select auth.uid())));

create policy recibo_cuentas_select_admin
on public.recibo_cuentas_snapshot for select to authenticated
using (
	exists (
		select 1
		from public.recibos r
		where r.id = recibo_cuentas_snapshot.recibo_id
			and app_private.es_admin(r.familia_id, (select auth.uid()))
	)
);

create policy recibo_participantes_select_miembro
on public.recibo_participantes_snapshot for select to authenticated
using (
	exists (
		select 1
		from public.recibos r
		where r.id = recibo_participantes_snapshot.recibo_id
			and app_private.es_miembro(r.familia_id, (select auth.uid()))
	)
);

create policy cuotas_select_miembro
on public.cuotas for select to authenticated
using (app_private.es_miembro(familia_id, (select auth.uid())));

create policy aportes_select_involucrado
on public.aportes for select to authenticated
using (
	app_private.es_admin(familia_id, (select auth.uid()))
	or exists (
		select 1
		from public.miembros_familia m
		where m.id = aportes.pagador_miembro_id
			and m.usuario_id = (select auth.uid())
			and m.estado = 'ACTIVO'
	)
	or exists (
		select 1
		from public.miembros_familia m
		where m.id = aportes.receptor_miembro_id
			and m.usuario_id = (select auth.uid())
			and m.estado = 'ACTIVO'
	)
);

create policy pagos_proveedor_select_miembro
on public.pagos_proveedor for select to authenticated
using (app_private.es_miembro(familia_id, (select auth.uid())));

create policy recibo_ajustes_select_miembro
on public.recibo_ajustes for select to authenticated
using (app_private.es_miembro(familia_id, (select auth.uid())));

create policy eventos_financieros_select_admin
on public.eventos_financieros for select to authenticated
using (app_private.es_admin(familia_id, (select auth.uid())));

revoke all on table public.recibos from anon, authenticated;
revoke all on table public.recibo_cuentas_snapshot from anon, authenticated;
revoke all on table public.recibo_participantes_snapshot from anon, authenticated;
revoke all on table public.cuotas from anon, authenticated;
revoke all on table public.aportes from anon, authenticated;
revoke all on table public.pagos_proveedor from anon, authenticated;
revoke all on table public.recibo_ajustes from anon, authenticated;
revoke all on table public.eventos_financieros from anon, authenticated;

grant select on table public.recibos to authenticated;
grant select on table public.recibo_cuentas_snapshot to authenticated;
grant select on table public.recibo_participantes_snapshot to authenticated;
grant select on table public.cuotas to authenticated;
grant select on table public.aportes to authenticated;
grant select on table public.pagos_proveedor to authenticated;
grant select on table public.recibo_ajustes to authenticated;
grant select on table public.eventos_financieros to authenticated;
