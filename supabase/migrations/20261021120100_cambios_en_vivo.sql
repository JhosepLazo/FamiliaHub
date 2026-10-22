-- Cambios en vivo: la app se actualiza sola cuando cambia un recibo, una cuota o un pago de la familia
-- (por ejemplo, el integrante ve su cuota "Pagada" en cuanto el administrador valida el pago).
-- Supabase Realtime respeta las políticas RLS: cada usuario solo recibe los cambios de filas que ya puede ver.

do $$
declare
	v_tabla text;
begin
	if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
		return;
	end if;

	foreach v_tabla in array array['recibos', 'cuotas', 'pagos_familiares'] loop
		if not exists (
			select 1
			from pg_publication_tables
			where pubname = 'supabase_realtime'
				and schemaname = 'public'
				and tablename = v_tabla
		) then
			execute format('alter publication supabase_realtime add table public.%I', v_tabla);
		end if;
	end loop;
end;
$$;
