alter table public.perfiles
	add column if not exists usuario text;

create unique index if not exists ux_perfiles_usuario_normalizado
on public.perfiles ((lower(trim(usuario))))
where usuario is not null;

alter table public.perfiles
	drop constraint if exists perfiles_usuario_formato_check;

alter table public.perfiles
	add constraint perfiles_usuario_formato_check
	check (
		usuario is null
		or usuario ~ '^[A-Za-z][A-Za-z0-9._-]{2,29}$'
	);

create or replace function app_private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_nombre text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'nombre', '')), '');
	v_usuario text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'usuario', '')), '');
begin
	if v_usuario is not null and v_usuario !~ '^[A-Za-z][A-Za-z0-9._-]{2,29}$' then
		raise exception 'El usuario debe tener entre 3 y 30 caracteres y usar solo letras, números, punto, guion o guion bajo.';
	end if;

	insert into public.perfiles (id, nombre, usuario)
	values (new.id, v_nombre, v_usuario)
	on conflict (id)
	do update set
		nombre = coalesce(public.perfiles.nombre, excluded.nombre),
		usuario = coalesce(public.perfiles.usuario, excluded.usuario),
		updated_at = now();

	return new;
end;
$$;
