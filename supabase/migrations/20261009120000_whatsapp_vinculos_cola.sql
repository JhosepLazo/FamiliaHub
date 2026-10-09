create type public.tipo_vinculo_whatsapp as enum ('GRUPO', 'INTEGRANTE');
create type public.tipo_aviso_whatsapp as enum ('POR_VENCER', 'VENCIDO');
create type public.estado_aviso_whatsapp as enum ('PENDIENTE', 'ENVIADO', 'ERROR', 'DESCARTADO');

create table public.whatsapp_vinculos (
	id uuid primary key default gen_random_uuid(),
	familia_id uuid not null references public.familias(id) on delete cascade,
	tipo public.tipo_vinculo_whatsapp not null,
	miembro_id uuid references public.miembros_familia(id) on delete cascade,
	whatsapp_id text,
	codigo text,
	codigo_expira_at timestamptz,
	vinculado_at timestamptz,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now(),
	check (
		(tipo = 'GRUPO' and miembro_id is null)
		or
		(tipo = 'INTEGRANTE' and miembro_id is not null)
	),
	check ((codigo is null) = (codigo_expira_at is null)),
	check ((whatsapp_id is null) = (vinculado_at is null)),
	check (codigo is null or codigo ~ '^[ABCDEFGHJKMNPQRSTUVWXYZ2-9]{6}$'),
	check (
		whatsapp_id is null
		or (tipo = 'GRUPO' and whatsapp_id ~ '^[0-9]+(-[0-9]+)?@g\.us$')
		or (tipo = 'INTEGRANTE' and whatsapp_id ~ '^[0-9]+@(s\.whatsapp\.net|lid|hosted|hosted\.lid)$')
	)
);

create index idx_whatsapp_vinculos_familia on public.whatsapp_vinculos(familia_id);
create unique index ux_whatsapp_vinculos_grupo_familia on public.whatsapp_vinculos(familia_id) where tipo = 'GRUPO';
create unique index ux_whatsapp_vinculos_miembro on public.whatsapp_vinculos(miembro_id) where tipo = 'INTEGRANTE';
create unique index ux_whatsapp_vinculos_grupo_jid on public.whatsapp_vinculos(whatsapp_id) where tipo = 'GRUPO' and whatsapp_id is not null;
create unique index ux_whatsapp_vinculos_integrante_jid on public.whatsapp_vinculos(familia_id, whatsapp_id) where tipo = 'INTEGRANTE' and whatsapp_id is not null;
create unique index ux_whatsapp_vinculos_codigo on public.whatsapp_vinculos(codigo) where codigo is not null;

create table public.avisos_whatsapp (
	id uuid primary key default gen_random_uuid(),
	familia_id uuid not null references public.familias(id) on delete cascade,
	recibo_id uuid not null references public.recibos(id) on delete cascade,
	tipo public.tipo_aviso_whatsapp not null,
	fecha_aviso date not null,
	mensaje text not null,
	estado public.estado_aviso_whatsapp not null default 'PENDIENTE',
	intentos smallint not null default 0 check (intentos between 0 and 3),
	error text,
	tomado_at timestamptz,
	enviado_at timestamptz,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now(),
	unique (recibo_id, tipo, fecha_aviso),
	check ((estado = 'ENVIADO') = (enviado_at is not null))
);

create index idx_avisos_whatsapp_familia on public.avisos_whatsapp(familia_id, fecha_aviso desc);
create index idx_avisos_whatsapp_pendientes on public.avisos_whatsapp(created_at) where estado = 'PENDIENTE';

alter table public.whatsapp_vinculos enable row level security;
alter table public.avisos_whatsapp enable row level security;

revoke all on table public.whatsapp_vinculos from anon, authenticated;
revoke all on table public.avisos_whatsapp from anon, authenticated;

create or replace function app_private.nuevo_codigo_whatsapp()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
	-- 31 símbolos: sin I, L, O, 0 ni 1 para evitar confusiones al copiar.
	v_alfabeto constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
	v_bytes bytea;
	v_byte integer;
	v_codigo text := '';
begin
	while length(v_codigo) < 6 loop
		-- gen_random_uuid usa el generador criptográfico de Postgres.
		v_bytes := uuid_send(gen_random_uuid());

		for v_posicion in 0..15 loop
			-- Los bytes 6 y 8 contienen bits fijos de versión y variante.
			continue when v_posicion in (6, 8);
			v_byte := get_byte(v_bytes, v_posicion);
			-- Rechazo para evitar sesgo: 248 es el mayor múltiplo de 31 bajo 256.
			continue when v_byte >= 248;
			v_codigo := v_codigo || substr(v_alfabeto, v_byte % 31 + 1, 1);
			exit when length(v_codigo) = 6;
		end loop;
	end loop;

	return v_codigo;
end;
$$;

create or replace function app_private.generar_codigo_whatsapp_impl(
	p_familia_id uuid,
	p_tipo public.tipo_vinculo_whatsapp
)
returns table (
	codigo text,
	expira_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
	v_usuario_id uuid := auth.uid();
	v_miembro_id uuid;
	v_codigo text;
	v_expira timestamptz := now() + interval '10 minutes';
	v_intento integer := 0;
begin
	if p_tipo is null then
		raise exception 'Indica qué deseas vincular.';
	end if;

	select m.id
	into v_miembro_id
	from public.miembros_familia m
	where m.familia_id = p_familia_id
		and m.usuario_id = v_usuario_id
		and m.estado = 'ACTIVO';

	if v_usuario_id is null or v_miembro_id is null then
		raise exception 'No perteneces a esta familia.';
	end if;

	if p_tipo = 'GRUPO' and not app_private.es_admin(p_familia_id, v_usuario_id) then
		raise exception 'Solo un administrador puede vincular el grupo de WhatsApp.';
	end if;

	update public.whatsapp_vinculos
	set codigo = null,
		codigo_expira_at = null,
		updated_at = now()
	where codigo_expira_at <= now();

	loop
		v_intento := v_intento + 1;
		v_codigo := app_private.nuevo_codigo_whatsapp();

		begin
			update public.whatsapp_vinculos v
			set codigo = v_codigo,
				codigo_expira_at = v_expira,
				updated_at = now()
			where v.familia_id = p_familia_id
				and v.tipo = p_tipo
				and (p_tipo = 'GRUPO' or v.miembro_id = v_miembro_id);

			if not found then
				insert into public.whatsapp_vinculos (familia_id, tipo, miembro_id, codigo, codigo_expira_at)
				values (
					p_familia_id,
					p_tipo,
					case when p_tipo = 'INTEGRANTE' then v_miembro_id end,
					v_codigo,
					v_expira
				);
			end if;

			exit;
		exception
			when unique_violation then
				if v_intento >= 5 then
					raise exception 'No pudimos generar el código. Intenta nuevamente.';
				end if;
		end;
	end loop;

	return query select v_codigo, v_expira;
end;
$$;

create or replace function app_private.vincular_whatsapp_impl(
	p_codigo text,
	p_grupo_id text,
	p_remitente_id text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_vinculo public.whatsapp_vinculos%rowtype;
	v_familia_nombre text;
	v_familia_grupo_id uuid;
	v_nombre text;
begin
	if coalesce(p_grupo_id, '') !~ '^[0-9]+(-[0-9]+)?@g\.us$' then
		raise exception 'Este comando solo funciona dentro del grupo familiar.';
	end if;

	select *
	into v_vinculo
	from public.whatsapp_vinculos
	where codigo = upper(trim(coalesce(p_codigo, '')))
		and codigo_expira_at > now()
	for update;

	if v_vinculo.id is null then
		raise exception 'Código inválido o vencido.';
	end if;

	select nombre
	into v_familia_nombre
	from public.familias
	where id = v_vinculo.familia_id
		and activo = true;

	if v_familia_nombre is null then
		raise exception 'Código inválido o vencido.';
	end if;

	select familia_id
	into v_familia_grupo_id
	from public.whatsapp_vinculos
	where tipo = 'GRUPO'
		and whatsapp_id = p_grupo_id;

	if v_vinculo.tipo = 'GRUPO' then
		if v_familia_grupo_id is not null and v_familia_grupo_id <> v_vinculo.familia_id then
			raise exception 'Este grupo ya está vinculado a otra familia.';
		end if;

		update public.whatsapp_vinculos
		set whatsapp_id = p_grupo_id,
			vinculado_at = now(),
			codigo = null,
			codigo_expira_at = null,
			updated_at = now()
		where id = v_vinculo.id;

		return format(
			'Listo. Este grupo quedó vinculado a la familia %s. Cada integrante puede vincular su WhatsApp desde FamiliaHub > Perfil. Escribe /ayuda para ver los comandos.',
			v_familia_nombre
		);
	end if;

	if coalesce(p_remitente_id, '') !~ '^[0-9]+@(s\.whatsapp\.net|lid|hosted|hosted\.lid)$' then
		raise exception 'No pudimos identificar tu WhatsApp. Intenta nuevamente.';
	end if;

	if v_familia_grupo_id is distinct from v_vinculo.familia_id then
		raise exception 'Usa tu código en el grupo de WhatsApp de tu familia.';
	end if;

	select coalesce(nullif(trim(p.nombre), ''), p.usuario, 'Integrante')
	into v_nombre
	from public.miembros_familia m
	left join public.perfiles p on p.id = m.usuario_id
	where m.id = v_vinculo.miembro_id
		and m.familia_id = v_vinculo.familia_id
		and m.estado = 'ACTIVO';

	if v_nombre is null then
		raise exception 'Tu acceso a esta familia no está activo.';
	end if;

	if exists (
		select 1
		from public.whatsapp_vinculos
		where tipo = 'INTEGRANTE'
			and familia_id = v_vinculo.familia_id
			and whatsapp_id = p_remitente_id
			and id <> v_vinculo.id
	) then
		raise exception 'Este WhatsApp ya está vinculado a otro integrante de la familia.';
	end if;

	update public.whatsapp_vinculos
	set whatsapp_id = p_remitente_id,
		vinculado_at = now(),
		codigo = null,
		codigo_expira_at = null,
		updated_at = now()
	where id = v_vinculo.id;

	return format('Listo, %s. Tu WhatsApp quedó vinculado.', v_nombre);
end;
$$;

create or replace function app_private.estado_whatsapp_impl(p_familia_id uuid)
returns table (
	grupo_vinculado boolean,
	grupo_vinculado_at timestamptz,
	integrante_vinculado boolean,
	integrante_vinculado_at timestamptz,
	integrantes_vinculados integer,
	integrantes_activos integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
begin
	if v_usuario_id is null or not app_private.es_miembro(p_familia_id, v_usuario_id) then
		raise exception 'No perteneces a esta familia.';
	end if;

	return query
	select
		g.vinculado_at is not null,
		g.vinculado_at,
		i.vinculado_at is not null,
		i.vinculado_at,
		(
			select count(*)::integer
			from public.whatsapp_vinculos v
			join public.miembros_familia m on m.id = v.miembro_id and m.estado = 'ACTIVO'
			where v.familia_id = p_familia_id
				and v.tipo = 'INTEGRANTE'
				and v.whatsapp_id is not null
		),
		(
			select count(*)::integer
			from public.miembros_familia m
			where m.familia_id = p_familia_id
				and m.estado = 'ACTIVO'
		)
	from (select 1) base
	left join public.whatsapp_vinculos g
		on g.familia_id = p_familia_id
		and g.tipo = 'GRUPO'
	left join public.whatsapp_vinculos i
		on i.familia_id = p_familia_id
		and i.tipo = 'INTEGRANTE'
		and i.miembro_id = (
			select m.id
			from public.miembros_familia m
			where m.familia_id = p_familia_id
				and m.usuario_id = v_usuario_id
		);
end;
$$;

create or replace function app_private.desvincular_whatsapp_impl(
	p_familia_id uuid,
	p_tipo public.tipo_vinculo_whatsapp
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
begin
	if v_usuario_id is null or not app_private.es_miembro(p_familia_id, v_usuario_id) then
		raise exception 'No perteneces a esta familia.';
	end if;

	if p_tipo = 'GRUPO' then
		if not app_private.es_admin(p_familia_id, v_usuario_id) then
			raise exception 'Solo un administrador puede desvincular el grupo de WhatsApp.';
		end if;

		delete from public.whatsapp_vinculos
		where familia_id = p_familia_id
			and tipo = 'GRUPO';
		return;
	end if;

	delete from public.whatsapp_vinculos v
	using public.miembros_familia m
	where v.miembro_id = m.id
		and v.tipo = 'INTEGRANTE'
		and m.familia_id = p_familia_id
		and m.usuario_id = v_usuario_id;
end;
$$;

revoke all on function app_private.nuevo_codigo_whatsapp() from public, anon, authenticated;
revoke all on function app_private.generar_codigo_whatsapp_impl(uuid, public.tipo_vinculo_whatsapp) from public, anon;
revoke all on function app_private.vincular_whatsapp_impl(text, text, text) from public, anon, authenticated;
revoke all on function app_private.estado_whatsapp_impl(uuid) from public, anon;
revoke all on function app_private.desvincular_whatsapp_impl(uuid, public.tipo_vinculo_whatsapp) from public, anon;

grant usage on schema app_private to service_role;
grant execute on function app_private.generar_codigo_whatsapp_impl(uuid, public.tipo_vinculo_whatsapp) to authenticated;
grant execute on function app_private.vincular_whatsapp_impl(text, text, text) to service_role;
grant execute on function app_private.estado_whatsapp_impl(uuid) to authenticated;
grant execute on function app_private.desvincular_whatsapp_impl(uuid, public.tipo_vinculo_whatsapp) to authenticated;

create or replace function public.generar_codigo_whatsapp(p_familia_id uuid, p_tipo public.tipo_vinculo_whatsapp)
returns table (codigo text, expira_at timestamptz)
language sql
security invoker
set search_path = ''
as $$ select * from app_private.generar_codigo_whatsapp_impl(p_familia_id, p_tipo); $$;

create or replace function public.vincular_whatsapp(p_codigo text, p_grupo_id text, p_remitente_id text)
returns text
language sql
security invoker
set search_path = ''
as $$ select app_private.vincular_whatsapp_impl(p_codigo, p_grupo_id, p_remitente_id); $$;

create or replace function public.estado_whatsapp(p_familia_id uuid)
returns table (
	grupo_vinculado boolean,
	grupo_vinculado_at timestamptz,
	integrante_vinculado boolean,
	integrante_vinculado_at timestamptz,
	integrantes_vinculados integer,
	integrantes_activos integer
)
language sql
stable
security invoker
set search_path = ''
as $$ select * from app_private.estado_whatsapp_impl(p_familia_id); $$;

create or replace function public.desvincular_whatsapp(p_familia_id uuid, p_tipo public.tipo_vinculo_whatsapp)
returns void
language sql
security invoker
set search_path = ''
as $$ select app_private.desvincular_whatsapp_impl(p_familia_id, p_tipo); $$;

revoke all on function public.generar_codigo_whatsapp(uuid, public.tipo_vinculo_whatsapp) from public, anon;
revoke all on function public.vincular_whatsapp(text, text, text) from public, anon, authenticated;
revoke all on function public.estado_whatsapp(uuid) from public, anon;
revoke all on function public.desvincular_whatsapp(uuid, public.tipo_vinculo_whatsapp) from public, anon;

grant execute on function public.generar_codigo_whatsapp(uuid, public.tipo_vinculo_whatsapp) to authenticated;
grant execute on function public.vincular_whatsapp(text, text, text) to service_role;
grant execute on function public.estado_whatsapp(uuid) to authenticated;
grant execute on function public.desvincular_whatsapp(uuid, public.tipo_vinculo_whatsapp) to authenticated;
