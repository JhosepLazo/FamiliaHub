drop index if exists public.idx_configuracion_pago_familia;

drop policy if exists invitaciones_update_admin on public.invitaciones;

create policy invitaciones_update_admin
on public.invitaciones
for update
to authenticated
using (app_private.es_admin(familia_id, (select auth.uid())))
with check (
	app_private.es_admin(familia_id, (select auth.uid()))
	and estado = 'REVOCADA'
);
