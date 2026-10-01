create unique index ux_invitaciones_pendiente_email
on public.invitaciones(familia_id, lower(email))
where estado = 'PENDIENTE';
