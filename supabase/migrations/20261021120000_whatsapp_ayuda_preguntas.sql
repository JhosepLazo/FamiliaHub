-- /ayuda más amigable: cada comando con su ícono y ejemplos de preguntas con palabras, que el bot ahora
-- entiende sin IA (supabase/functions/bot-whatsapp/intenciones.ts).

create or replace function app_private.whatsapp_cmd_ayuda()
returns text
language sql
immutable
set search_path = ''
as $$
	select array_to_string(array[
		'🏠 *FamiliaHub* — esto puedo hacer',
		'',
		'💰 /deuda — cuánto debes',
		'📅 /vence — vencidos y próximos 7 días',
		'🧾 /recibos — recibos del mes',
		'🔎 /recibo luz — detalle de un recibo',
		'👥 /pendientes — quién falta aportar',
		'📊 /resumen — cómo va el mes',
		'💳 /pagar — cómo pagar',
		'🙋 /yo — tu vínculo',
		'🔗 /vincular CÓDIGO — vincular tu WhatsApp',
		'✂️ /desvincular — quitar tu vínculo',
		'',
		'💬 También puedes mencionarme y preguntar con tus palabras: "¿cuánto debo?", "¿quién falta pagar?", "¿cuánto llegó la luz?"',
		'',
		'Administradores: /porvalidar · /avisos estado · /avisos pausar · /avisos reanudar'
	], E'\n');
$$;

revoke all on function app_private.whatsapp_cmd_ayuda() from public, anon, authenticated, service_role;
