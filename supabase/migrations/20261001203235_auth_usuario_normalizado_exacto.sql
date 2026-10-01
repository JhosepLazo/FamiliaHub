alter table public.perfiles
      add column if not exists usuario_normalizado text
      generated always as (lower(trim(usuario))) stored;

    create unique index if not exists ux_perfiles_usuario_normalizado_exacto
    on public.perfiles (usuario_normalizado)
    where usuario_normalizado is not null;

    drop index if exists public.ux_perfiles_usuario_normalizado;
  