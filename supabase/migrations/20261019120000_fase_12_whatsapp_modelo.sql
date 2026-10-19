create type public.tipo_vinculo_whatsapp as enum ('GRUPO', 'INTEGRANTE');

create type public.tipo_aviso_whatsapp as enum (
	'INICIO_MES', 'RECIBO_MONTO', 'POR_VENCER', 'VENCE_HOY', 'VENCIDO',
	'PAGO_ENVIADO', 'PAGO_CONFIRMADO', 'RECAUDACION_COMPLETA', 'PAGO_PROVEEDOR',
	'RECIBO_ACTUALIZADO', 'PENDIENTES_ADMIN', 'RESUMEN_SEMANAL', 'CIERRE_MES'
);

create type public.estado_aviso_whatsapp as enum ('PENDIENTE', 'ENVIADO', 'ERROR', 'EXPIRADO');

create table public.whatsapp_vinculos (
	id uuid primary key default gen_random_uuid(),
	familia_id uuid not null references public.familias(id) on delete cascade,
	tipo public.tipo_vinculo_whatsapp not null,
	miembro_id uuid references public.miembros_familia(id) on delete cascade,
	whatsapp_id text,
	whatsapp_id_alt text,
	codigo text,
	codigo_expira_at timestamptz,
	vinculado_at timestamptz,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now(),
	unique nulls not distinct (familia_id, tipo, miembro_id),
	check ((tipo = 'GRUPO' and miembro_id is null) or (tipo = 'INTEGRANTE' and miembro_id is not null)),
	check ((codigo is null) = (codigo_expira_at is null)),
	check ((whatsapp_id is null) = (vinculado_at is null)),
	check (tipo = 'INTEGRANTE' or whatsapp_id_alt is null),
	check (codigo is null or codigo ~ '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{6}$')
);

create unique index ux_whatsapp_vinculos_grupo
on public.whatsapp_vinculos(whatsapp_id)
where tipo = 'GRUPO';

create unique index ux_whatsapp_vinculos_integrante
on public.whatsapp_vinculos(familia_id, whatsapp_id)
where tipo = 'INTEGRANTE';

create unique index ux_whatsapp_vinculos_integrante_alt
on public.whatsapp_vinculos(familia_id, whatsapp_id_alt)
where tipo = 'INTEGRANTE' and whatsapp_id_alt is not null;

create unique index ux_whatsapp_vinculos_codigo
on public.whatsapp_vinculos(codigo)
where codigo is not null;

create index idx_whatsapp_vinculos_miembro
on public.whatsapp_vinculos(miembro_id)
where miembro_id is not null;

create table public.whatsapp_configuracion (
	familia_id uuid primary key references public.familias(id) on delete cascade,
	avisos_activos boolean not null default true,
	dias_aviso_previo smallint[] not null default '{3,1}',
	avisar_vence_hoy boolean not null default true,
	frecuencia_vencidos_dias smallint not null default 3,
	hora_inicio_envio time not null default '08:00',
	hora_fin_envio time not null default '21:00',
	avisar_inicio_mes boolean not null default true,
	avisar_monto boolean not null default true,
	avisar_pago_enviado boolean not null default true,
	avisar_pago_confirmado boolean not null default true,
	avisar_recaudacion_completa boolean not null default true,
	avisar_pago_proveedor boolean not null default true,
	avisar_cambios_recibo boolean not null default true,
	avisar_pendientes_admin boolean not null default true,
	hora_pendientes_admin time not null default '09:00',
	resumen_semanal boolean not null default true,
	dia_resumen smallint not null default 0,
	hora_resumen time not null default '19:00',
	avisar_cierre_mes boolean not null default true,
	mencionar_integrantes boolean not null default true,
	lenguaje_natural boolean not null default false,
	updated_at timestamptz not null default now(),
	updated_by uuid references auth.users(id) on delete set null,
	check (cardinality(dias_aviso_previo) <= 5),
	check (array_position(dias_aviso_previo, null) is null),
	check (1 <= all(dias_aviso_previo) and 15 >= all(dias_aviso_previo)),
	check (frecuencia_vencidos_dias between 0 and 15),
	check (hora_inicio_envio < hora_fin_envio),
	check (hora_pendientes_admin >= hora_inicio_envio and hora_pendientes_admin < hora_fin_envio),
	check (dia_resumen between 0 and 6),
	check (hora_resumen >= hora_inicio_envio and hora_resumen < hora_fin_envio)
);

create index idx_whatsapp_configuracion_updated_by
on public.whatsapp_configuracion(updated_by)
where updated_by is not null;

create table public.avisos_whatsapp (
	id uuid primary key default gen_random_uuid(),
	familia_id uuid not null references public.familias(id) on delete cascade,
	tipo public.tipo_aviso_whatsapp not null,
	clave text not null unique,
	recibo_id uuid references public.recibos(id) on delete cascade,
	texto text not null check (char_length(texto) between 1 and 1500),
	menciones text[] not null default '{}',
	estado public.estado_aviso_whatsapp not null default 'PENDIENTE',
	intentos smallint not null default 0 check (intentos between 0 and 3),
	error text,
	expira_at timestamptz not null,
	bloqueado_hasta timestamptz,
	enviado_at timestamptz,
	created_at timestamptz not null default now()
);

create index idx_avisos_whatsapp_pendientes
on public.avisos_whatsapp(created_at)
where estado = 'PENDIENTE';

create index idx_avisos_whatsapp_familia
on public.avisos_whatsapp(familia_id);

create index idx_avisos_whatsapp_recibo
on public.avisos_whatsapp(recibo_id)
where recibo_id is not null;

create table public.whatsapp_sistema (
	id smallint primary key default 1 check (id = 1),
	ultimo_evento_id bigint not null,
	ultima_revision_pagos_at timestamptz not null default now(),
	ultimo_heartbeat_at timestamptz,
	version_bot text,
	updated_at timestamptz
);

insert into public.whatsapp_sistema (id, ultimo_evento_id, ultima_revision_pagos_at)
select 1, coalesce(max(id), 0), now()
from public.eventos_financieros;

alter table public.whatsapp_vinculos enable row level security;
alter table public.whatsapp_configuracion enable row level security;
alter table public.avisos_whatsapp enable row level security;
alter table public.whatsapp_sistema enable row level security;

revoke all on table public.whatsapp_vinculos from anon, authenticated;
revoke all on table public.whatsapp_configuracion from anon, authenticated;
revoke all on table public.avisos_whatsapp from anon, authenticated;
revoke all on table public.whatsapp_sistema from anon, authenticated;
