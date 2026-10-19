-- Fase 12: pasa al modelo nuevo los grupos e integrantes que quedaron vinculados con el patch anterior
-- (los guardó 20261019115900). Si no hay nada que recuperar, no hace nada.
-- Solo se recuperan integrantes que siguen activos en su familia.

do $$
begin
	if to_regclass('app_private.whatsapp_vinculos_anteriores') is null then
		return;
	end if;

	insert into public.whatsapp_vinculos (familia_id, tipo, miembro_id, whatsapp_id, vinculado_at)
	select a.familia_id, 'GRUPO', null, a.whatsapp_id, a.vinculado_at
	from app_private.whatsapp_vinculos_anteriores a
	where a.tipo = 'GRUPO'
	on conflict do nothing;

	insert into public.whatsapp_vinculos (familia_id, tipo, miembro_id, whatsapp_id, vinculado_at)
	select a.familia_id, 'INTEGRANTE', a.miembro_id, a.whatsapp_id, a.vinculado_at
	from app_private.whatsapp_vinculos_anteriores a
	inner join public.miembros_familia m
		on m.id = a.miembro_id
		and m.familia_id = a.familia_id
		and m.estado = 'ACTIVO'
	where a.tipo = 'INTEGRANTE'
	on conflict do nothing;

	insert into public.whatsapp_configuracion (familia_id)
	select v.familia_id
	from public.whatsapp_vinculos v
	where v.tipo = 'GRUPO'
	on conflict (familia_id) do nothing;

	drop table app_private.whatsapp_vinculos_anteriores;
end
$$;
