create or replace function app_private.validar_cuota_aportes_pendientes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_pendiente numeric;
begin
	if new.monto_asignado is distinct from old.monto_asignado then
		select coalesce(sum(monto), 0)
		into v_pendiente
		from public.aportes
		where cuota_id = old.id
			and estado = 'POR_VALIDAR';

		if new.monto_asignado < new.monto_pagado + v_pendiente then
			raise exception 'La nueva cuota quedaría por debajo de importes pagados o pendientes de validación.';
		end if;
	end if;

	return new;
end;
$$;

revoke all on function app_private.validar_cuota_aportes_pendientes() from public, anon, authenticated;

create trigger validar_cuota_aportes_pendientes
before update of monto_asignado on public.cuotas
for each row execute function app_private.validar_cuota_aportes_pendientes();
