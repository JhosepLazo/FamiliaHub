drop policy if exists cuentas_servicio_select on public.cuentas_servicio;

create policy cuentas_servicio_select_admin
on public.cuentas_servicio
for select
to authenticated
using (
	exists (
		select 1
		from public.conceptos_pago
		where conceptos_pago.id = cuentas_servicio.concepto_id
			and app_private.es_admin(conceptos_pago.familia_id, (select auth.uid()))
	)
);
