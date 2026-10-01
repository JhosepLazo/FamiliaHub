create extension if not exists pg_cron with schema pg_catalog;

do $$
begin
	perform cron.unschedule('familiahub-ciclo-diario');
exception
	when others then
		null;
end
$$;

select cron.schedule(
	'familiahub-ciclo-diario',
	'10 5 * * *',
	$$select app_private.procesar_ciclo_diario();$$
);

select app_private.procesar_ciclo_diario();
