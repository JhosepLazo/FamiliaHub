create or replace function app_private.validar_pago_proveedor_vencimiento()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
	if new.estado = 'CONFIRMADO' and not exists (
		select 1
		from public.recibos
		where id = new.recibo_id
			and fecha_vencimiento is not null
	) then
		raise exception 'Registra primero la fecha de vencimiento del proveedor.';
	end if;

	return new;
end;
$$;

revoke all on function app_private.validar_pago_proveedor_vencimiento() from public, anon, authenticated;

create trigger validar_pago_proveedor_vencimiento
before insert or update of estado, recibo_id on public.pagos_proveedor
for each row execute function app_private.validar_pago_proveedor_vencimiento();
