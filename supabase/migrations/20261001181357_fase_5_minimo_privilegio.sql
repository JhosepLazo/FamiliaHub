revoke all on table public.proveedores from anon, authenticated;
revoke all on table public.tipos_identificador_proveedor from anon, authenticated;
revoke all on table public.plantillas_servicio from anon, authenticated;
revoke all on table public.conceptos_pago from anon, authenticated;
revoke all on table public.cuentas_servicio from anon, authenticated;
revoke all on table public.concepto_participantes from anon, authenticated;

grant select on table public.proveedores to authenticated;
grant select on table public.tipos_identificador_proveedor to authenticated;
grant select on table public.plantillas_servicio to authenticated;
grant select on table public.conceptos_pago to authenticated;
grant select on table public.cuentas_servicio to authenticated;
grant select on table public.concepto_participantes to authenticated;
