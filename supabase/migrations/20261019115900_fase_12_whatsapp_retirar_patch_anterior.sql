-- Fase 12: retira el asistente de WhatsApp del patch anterior (migraciones 20261009120000,
-- 20261009121000 y 20261009122000) si llegó a aplicarse. En una base donde nunca se aplicó no hace nada.
-- Los grupos e integrantes ya vinculados se guardan aparte y 20261019120400 los pasa al modelo nuevo;
-- los códigos pendientes y la cola de avisos anterior se descartan.

do $$
begin
	perform cron.unschedule('familiahub-avisos-whatsapp');
exception
	when others then
		null;
end
$$;

do $$
begin
	if to_regclass('public.whatsapp_vinculos') is not null then
		create table app_private.whatsapp_vinculos_anteriores as
		select familia_id, tipo::text as tipo, miembro_id, whatsapp_id, vinculado_at
		from public.whatsapp_vinculos
		where whatsapp_id is not null;
	end if;
end
$$;

drop function if exists public.responder_comando_whatsapp(text, text, text, text);
drop function if exists app_private.responder_comando_whatsapp_impl(text, text, text, text, date);
drop function if exists app_private.whatsapp_mes(integer);

drop function if exists public.tomar_avisos_whatsapp();
drop function if exists public.marcar_aviso_whatsapp(uuid, boolean, text);
drop function if exists app_private.tomar_avisos_whatsapp_impl(timestamptz);
drop function if exists app_private.marcar_aviso_whatsapp_impl(uuid, boolean, text);
drop function if exists app_private.generar_avisos_whatsapp_impl(date);
drop function if exists app_private.mensaje_aviso_whatsapp(uuid, public.tipo_aviso_whatsapp, date);
drop function if exists app_private.tipo_aviso_whatsapp_del_dia(uuid, date);
drop function if exists app_private.whatsapp_pendientes_recibo(uuid);
drop function if exists app_private.whatsapp_fecha_dia(date);
drop function if exists app_private.whatsapp_fecha(date);
drop function if exists app_private.whatsapp_monto(numeric);

drop function if exists public.generar_codigo_whatsapp(uuid, public.tipo_vinculo_whatsapp);
drop function if exists public.vincular_whatsapp(text, text, text);
drop function if exists public.estado_whatsapp(uuid);
drop function if exists public.desvincular_whatsapp(uuid, public.tipo_vinculo_whatsapp);
drop function if exists app_private.generar_codigo_whatsapp_impl(uuid, public.tipo_vinculo_whatsapp);
drop function if exists app_private.vincular_whatsapp_impl(text, text, text);
drop function if exists app_private.estado_whatsapp_impl(uuid);
drop function if exists app_private.desvincular_whatsapp_impl(uuid, public.tipo_vinculo_whatsapp);
drop function if exists app_private.nuevo_codigo_whatsapp();

drop table if exists public.avisos_whatsapp;
drop table if exists public.whatsapp_vinculos;

drop type if exists public.estado_aviso_whatsapp;
drop type if exists public.tipo_aviso_whatsapp;
drop type if exists public.tipo_vinculo_whatsapp;
