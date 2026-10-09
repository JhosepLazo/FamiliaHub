/*================================================================================
Objetivo:
	Validar la Fase 12 (asistente de WhatsApp): códigos de vinculación, vínculos
	de grupo e integrantes, cola de avisos, comandos de consulta y permisos.

Requisitos:
	1. Ejecutar como rol postgres (SQL Editor de Supabase o psql).
	2. No necesita usuarios reales: crea usuarios ficticios dentro de la
	   transacción.

Importante:
	- Todo el escenario termina con Rollback; no deja usuarios, familias,
	  recibos, vínculos ni avisos.
	- Las fechas son relativas al día actual en America/Lima.
	- Resultado esperado: todas las filas con Resultado = 'OK'.
================================================================================*/

Begin;

Create Temp Table wa_contexto
(
	Clave varchar(40) Primary Key,
	Valor text Not Null
) On Commit Drop;

Create Temp Table wa_resultados
(
	Orden serial,
	Prueba varchar(120) Not Null,
	Resultado varchar(10) Not Null,
	Detalle text Null
) On Commit Drop;

Grant Select, Insert, Update On wa_contexto, wa_resultados To authenticated, service_role, anon;
Grant Usage On Sequence wa_resultados_orden_seq To authenticated, service_role, anon;

Create Function pg_temp.ctx(p_clave text)
Returns text
Language sql
As $$ Select Valor From wa_contexto Where Clave = p_clave; $$;

Create Function pg_temp.guardar(p_clave text, p_valor text)
Returns void
Language sql
As $$
	Insert Into wa_contexto (Clave, Valor) Values (p_clave, p_valor)
	On Conflict (Clave) Do Update Set Valor = Excluded.Valor;
$$;

Create Function pg_temp.esperar(p_prueba text, p_ok boolean, p_detalle text)
Returns void
Language sql
As $$
	Insert Into wa_resultados (Prueba, Resultado, Detalle)
	Values (p_prueba, Case When Coalesce(p_ok, false) Then 'OK' Else 'FALLA' End, p_detalle);
$$;

-- Cambia la identidad efectiva dentro de la transacción.
Create Function pg_temp.como(p_clave_usuario text)
Returns void
Language plpgsql
As $$
Begin
	Perform set_config('role', 'none', true);
	If p_clave_usuario = 'postgres' Then
		Perform set_config('request.jwt.claims', '', true);
	ElsIf p_clave_usuario In ('service_role', 'anon') Then
		Perform set_config('request.jwt.claims', Json_Build_Object('role', p_clave_usuario)::text, true);
		Perform set_config('role', p_clave_usuario, true);
	Else
		Perform set_config(
			'request.jwt.claims',
			Json_Build_Object('sub', pg_temp.ctx(p_clave_usuario), 'role', 'authenticated')::text,
			true
		);
		Perform set_config('role', 'authenticated', true);
	End If;
End;
$$;

Create Function pg_temp.error_de(p_sql text)
Returns text
Language plpgsql
As $$
Begin
	Execute p_sql;
	Return Null;
Exception
	When Others Then
		Return Sqlerrm;
End;
$$;

Create Function pg_temp.responder(p_grupo text, p_remitente text, p_texto text, p_alt text Default Null)
Returns text
Language sql
As $$ Select public.responder_comando_whatsapp(p_grupo, p_remitente, p_texto, p_alt); $$;

-- Paga completamente una cuota sin pasar por el flujo de comprobantes (solo para la prueba).
Create Function pg_temp.pagar_cuota(p_recibo_id uuid, p_usuario_id uuid)
Returns void
Language plpgsql
As $$
Declare
	v_cuota_id uuid;
Begin
	Update public.cuotas
	Set monto_pagado = monto_asignado
	Where recibo_id = p_recibo_id
		And usuario_id = p_usuario_id
	Returning id Into v_cuota_id;

	Perform app_private.actualizar_estado_cuota(v_cuota_id);
	Perform app_private.actualizar_estado_recaudacion(p_recibo_id);
End;
$$;

Create Function pg_temp.crear_servicio(p_nombre text, p_proveedor text, p_monto numeric, p_dias_objetivo integer)
Returns uuid
Language plpgsql
As $$
Declare
	v_familia_id uuid := pg_temp.ctx('FAMILIA_ID')::uuid;
	v_hoy date := (timezone('America/Lima', now()))::date;
	v_concepto_id uuid;
	v_recibo_id uuid;
Begin
	Perform pg_temp.como('ANA');

	Select public.guardar_concepto_servicio_fase6(
		Null,
		v_familia_id,
		(Select id From public.categorias Where familia_id = v_familia_id And nombre = 'Servicios'),
		(Select id From public.proveedores Where codigo = p_proveedor),
		Null,
		p_nombre,
		'MENSUAL',
		'MANUAL',
		Null,
		'VARIABLE',
		Null,
		'IGUAL',
		Null,
		false,
		'{}'::jsonb,
		Json_Build_Array(
			Json_Build_Object('miembro_id', pg_temp.ctx('ANA_MIEMBRO_ID'), 'modalidad', 'IGUAL', 'valor', Null),
			Json_Build_Object('miembro_id', pg_temp.ctx('LUIS_MIEMBRO_ID'), 'modalidad', 'IGUAL', 'valor', Null)
		)::jsonb,
		v_hoy,
		0::smallint
	)
	Into v_concepto_id;

	Select id Into v_recibo_id From public.recibos Where concepto_id = v_concepto_id;

	If p_monto Is Not Null Then
		Perform public.confirmar_monto_recibo(v_recibo_id, p_monto, v_hoy + p_dias_objetivo);
	End If;

	Perform pg_temp.como('postgres');
	Return v_recibo_id;
End;
$$;

Grant Execute On All Functions In Schema pg_temp To authenticated, service_role, anon;

Do $$
Declare
	v_hoy date := (timezone('America/Lima', now()))::date;
	v_mediodia timestamptz := (v_hoy::timestamp + time '12:00') At Time Zone 'America/Lima';
	v_madrugada timestamptz := (v_hoy::timestamp + time '03:00') At Time Zone 'America/Lima';
	v_familia_id uuid;
	v_otra_familia_id uuid;
	v_codigo text;
	v_codigo_2 text;
	v_expira timestamptz;
	v_texto text;
	v_error text;
	v_total integer;
	v_debe_app numeric;
	v_luz uuid;
	v_agua uuid;
	v_internet uuid;
	v_gas uuid;
	v_cable uuid;
	v_aviso record;
	v_avisos uuid[];
	G1 constant text := '120363000000000001@g.us';
	G2 constant text := '120363000000000002@g.us';
	G9 constant text := '120363000000000009@g.us';
	LUIS_LID constant text := '211111111111111@lid';
	LUIS_PN constant text := '51911111111@s.whatsapp.net';
	ANA_LID constant text := '222222222222222@lid';
Begin
	-- Usuarios ficticios ----------------------------------------------------------
	Perform pg_temp.guardar('ANA', gen_random_uuid()::text);
	Perform pg_temp.guardar('LUIS', gen_random_uuid()::text);
	Perform pg_temp.guardar('ROSA', gen_random_uuid()::text);
	Perform pg_temp.guardar('OTRO', gen_random_uuid()::text);

	Insert Into auth.users (id, email, raw_user_meta_data)
	Values
		(pg_temp.ctx('ANA')::uuid, 'ana.wa-test@familiahub.invalid', '{"nombre": "Ana"}'),
		(pg_temp.ctx('LUIS')::uuid, 'luis.wa-test@familiahub.invalid', '{"nombre": "Luis"}'),
		(pg_temp.ctx('ROSA')::uuid, 'rosa.wa-test@familiahub.invalid', '{"nombre": "Rosa"}'),
		(pg_temp.ctx('OTRO')::uuid, 'otro.wa-test@familiahub.invalid', '{"nombre": "Otro"}');

	Perform pg_temp.como('ANA');
	v_familia_id := public.crear_familia_inicial('Lazo');
	Perform pg_temp.como('OTRO');
	v_otra_familia_id := public.crear_familia_inicial('Otra');
	Perform pg_temp.como('postgres');

	Perform pg_temp.guardar('FAMILIA_ID', v_familia_id::text);

	Insert Into public.miembros_familia (familia_id, usuario_id, rol, estado)
	Values
		(v_familia_id, pg_temp.ctx('LUIS')::uuid, 'INTEGRANTE', 'ACTIVO'),
		(v_familia_id, pg_temp.ctx('ROSA')::uuid, 'INTEGRANTE', 'ACTIVO');

	Perform pg_temp.guardar('ANA_MIEMBRO_ID', (Select id::text From public.miembros_familia Where usuario_id = pg_temp.ctx('ANA')::uuid));
	Perform pg_temp.guardar('LUIS_MIEMBRO_ID', (Select id::text From public.miembros_familia Where usuario_id = pg_temp.ctx('LUIS')::uuid));

	-- Recibos del mes -------------------------------------------------------------
	v_luz := pg_temp.crear_servicio('Luz', 'LUZ_DEL_SUR', 184.50, 3);
	v_agua := pg_temp.crear_servicio('Agua', 'SEDAPAL', 70.00, -1);
	v_internet := pg_temp.crear_servicio('Internet', 'WIN', Null, Null);
	v_gas := pg_temp.crear_servicio('Gas', 'CALIDDA', 50.00, 1);

	Perform pg_temp.pagar_cuota(v_agua, pg_temp.ctx('ANA')::uuid);
	Perform pg_temp.pagar_cuota(v_gas, pg_temp.ctx('ANA')::uuid);
	Perform pg_temp.pagar_cuota(v_gas, pg_temp.ctx('LUIS')::uuid);

	Perform pg_temp.esperar(
		'Escenario financiero',
		(Select count(*) From public.recibos Where familia_id = v_familia_id) = 4
			And (Select estado_recaudacion From public.recibos Where id = v_gas) = 'COMPLETA'
			And (Select estado From public.recibos Where id = v_internet) = 'ESPERANDO_MONTO',
		'Luz (vence en 3 días), Agua (vencida ayer), Internet (sin monto), Gas (recaudación completa).'
	);

	-- Códigos de vinculación ------------------------------------------------------
	Perform pg_temp.como('LUIS');
	v_error := pg_temp.error_de(Format('Select public.generar_codigo_whatsapp(%L, %L)', v_familia_id, 'GRUPO'));
	Perform pg_temp.esperar('Integrante pide código de grupo', v_error Like 'Solo un administrador%', v_error);

	Select codigo, expira_at Into v_codigo, v_expira From public.generar_codigo_whatsapp(v_familia_id, 'INTEGRANTE');
	Perform pg_temp.guardar('CODIGO_LUIS', v_codigo);
	Perform pg_temp.esperar(
		'Integrante genera su código',
		v_codigo ~ '^[ABCDEFGHJKMNPQRSTUVWXYZ2-9]{6}$' And v_expira Between now() + interval '9 minutes' And now() + interval '11 minutes',
		v_codigo
	);

	Perform pg_temp.como('ANA');
	Select codigo Into v_codigo From public.generar_codigo_whatsapp(v_familia_id, 'GRUPO');
	Perform pg_temp.guardar('CODIGO_GRUPO', v_codigo);
	Perform pg_temp.esperar('Administrador genera código de grupo', v_codigo Is Not Null, v_codigo);

	Perform pg_temp.como('OTRO');
	v_error := pg_temp.error_de(Format('Select public.generar_codigo_whatsapp(%L, %L)', v_familia_id, 'INTEGRANTE'));
	Perform pg_temp.esperar('Usuario ajeno pide código de otra familia', v_error = 'No perteneces a esta familia.', v_error);

	-- Permisos ---------------------------------------------------------------------
	Perform pg_temp.como('ANA');
	v_error := pg_temp.error_de('Select count(*) From public.whatsapp_vinculos');
	Perform pg_temp.esperar('authenticated no lee whatsapp_vinculos', v_error Like 'permission denied%', v_error);
	v_error := pg_temp.error_de('Select count(*) From public.avisos_whatsapp');
	Perform pg_temp.esperar('authenticated no lee avisos_whatsapp', v_error Like 'permission denied%', v_error);
	v_error := pg_temp.error_de(Format('Select public.vincular_whatsapp(%L, %L, %L)', v_codigo, G1, ANA_LID));
	Perform pg_temp.esperar('authenticated no ejecuta vincular_whatsapp', v_error Like 'permission denied%', v_error);
	v_error := pg_temp.error_de(Format('Select public.responder_comando_whatsapp(%L, %L, %L)', G1, ANA_LID, '/deuda'));
	Perform pg_temp.esperar('authenticated no ejecuta responder_comando_whatsapp', v_error Like 'permission denied%', v_error);
	v_error := pg_temp.error_de('Select * From public.tomar_avisos_whatsapp()');
	Perform pg_temp.esperar('authenticated no toma avisos', v_error Like 'permission denied%', v_error);

	Perform pg_temp.como('anon');
	v_error := pg_temp.error_de(Format('Select public.generar_codigo_whatsapp(%L, %L)', v_familia_id, 'INTEGRANTE'));
	Perform pg_temp.esperar('anon no genera códigos', v_error Like 'permission denied%', v_error);

	-- Vinculación del grupo ------------------------------------------------------
	Perform pg_temp.como('service_role');

	v_texto := pg_temp.responder(G1, LUIS_LID, '/vincular ' || pg_temp.ctx('CODIGO_LUIS'));
	Perform pg_temp.esperar('Grupo no vinculado ignora /vincular', v_texto Is Null, v_texto);

	v_error := pg_temp.error_de(Format('Select public.vincular_whatsapp(%L, %L, %L)', pg_temp.ctx('CODIGO_LUIS'), G1, LUIS_LID));
	Perform pg_temp.esperar('Código de integrante en grupo no vinculado', v_error = 'Usa tu código en el grupo de WhatsApp de tu familia.', v_error);

	v_texto := pg_temp.responder(G9, ANA_LID, '/ayuda');
	Perform pg_temp.esperar('Grupo no vinculado ignora /ayuda', v_texto Is Null, v_texto);

	v_texto := pg_temp.responder(G9, ANA_LID, '/ping');
	Perform pg_temp.esperar('Grupo no vinculado responde /ping', v_texto = 'pong 🏠', v_texto);

	v_texto := pg_temp.responder(G1, ANA_LID, '/vincular-grupo');
	Perform pg_temp.esperar('/vincular-grupo sin código explica el uso', v_texto Like 'Escribe /vincular-grupo%', v_texto);

	v_texto := pg_temp.responder(G1, ANA_LID, '  /VINCULAR-GRUPO   ' || Lower(pg_temp.ctx('CODIGO_GRUPO')));
	Perform pg_temp.esperar('Administrador vincula el grupo', v_texto Like 'Listo. Este grupo quedó vinculado a la familia Lazo.%', v_texto);

	v_texto := pg_temp.responder(G1, ANA_LID, '/vincular-grupo ' || pg_temp.ctx('CODIGO_GRUPO'));
	Perform pg_temp.esperar('Código reusado', v_texto = 'Código inválido o vencido.', v_texto);

	Perform pg_temp.como('OTRO');
	Select codigo Into v_codigo From public.generar_codigo_whatsapp(v_otra_familia_id, 'GRUPO');
	Perform pg_temp.como('service_role');
	v_texto := pg_temp.responder(G1, ANA_LID, '/vincular-grupo ' || v_codigo);
	Perform pg_temp.esperar('Grupo ya vinculado a otra familia', v_texto = 'Este grupo ya está vinculado a otra familia.', v_texto);
	v_texto := pg_temp.responder(G2, ANA_LID, '/vincular-grupo ' || v_codigo);
	Perform pg_temp.esperar('Otra familia vincula su propio grupo', v_texto Like 'Listo. Este grupo quedó vinculado a la familia Otra.%', v_texto);

	-- Vinculación de integrantes -------------------------------------------------
	v_texto := pg_temp.responder(G2, LUIS_LID, '/vincular ' || pg_temp.ctx('CODIGO_LUIS'));
	Perform pg_temp.esperar('Integrante usa su código en otro grupo', v_texto = 'Usa tu código en el grupo de WhatsApp de tu familia.', v_texto);

	Perform pg_temp.como('postgres');
	Update public.whatsapp_vinculos Set codigo_expira_at = now() - interval '1 minute' Where codigo = pg_temp.ctx('CODIGO_LUIS');
	Perform pg_temp.como('service_role');
	v_texto := pg_temp.responder(G1, LUIS_LID, '/vincular ' || pg_temp.ctx('CODIGO_LUIS'));
	Perform pg_temp.esperar('Código vencido', v_texto = 'Código inválido o vencido.', v_texto);

	v_texto := pg_temp.responder(G1, LUIS_LID, '/deuda');
	Perform pg_temp.esperar('/deuda de remitente no vinculado', v_texto Like 'Aún no vinculas tu WhatsApp.%', v_texto);

	Perform pg_temp.como('LUIS');
	Select codigo Into v_codigo From public.generar_codigo_whatsapp(v_familia_id, 'INTEGRANTE');
	Perform pg_temp.como('service_role');
	v_texto := pg_temp.responder(G1, LUIS_LID, '/vincular ' || v_codigo, LUIS_PN);
	Perform pg_temp.esperar('Integrante vincula su WhatsApp', v_texto = 'Listo, Luis. Tu WhatsApp quedó vinculado.', v_texto);

	Perform pg_temp.como('ANA');
	Select codigo Into v_codigo From public.generar_codigo_whatsapp(v_familia_id, 'INTEGRANTE');
	Perform pg_temp.como('service_role');
	v_texto := pg_temp.responder(G1, LUIS_LID, '/vincular ' || v_codigo);
	Perform pg_temp.esperar('Dos integrantes con el mismo WhatsApp', v_texto = 'Este WhatsApp ya está vinculado a otro integrante de la familia.', v_texto);
	v_texto := pg_temp.responder(G1, ANA_LID, '/vincular ' || v_codigo);
	Perform pg_temp.esperar('Administradora vincula su WhatsApp', v_texto = 'Listo, Ana. Tu WhatsApp quedó vinculado.', v_texto);

	Perform pg_temp.como('ROSA');
	Select codigo Into v_codigo From public.generar_codigo_whatsapp(v_familia_id, 'INTEGRANTE');
	Perform pg_temp.como('postgres');
	Update public.miembros_familia Set estado = 'INACTIVO' Where usuario_id = pg_temp.ctx('ROSA')::uuid;
	Perform pg_temp.como('service_role');
	v_texto := pg_temp.responder(G1, '233333333333333@lid', '/vincular ' || v_codigo);
	Perform pg_temp.esperar('Integrante inactivo intenta vincularse', v_texto = 'Tu acceso a esta familia no está activo.', v_texto);

	Perform pg_temp.como('ANA');
	Perform pg_temp.esperar(
		'Estado del vínculo para la app',
		(Select grupo_vinculado And integrante_vinculado And integrantes_vinculados = 2 And integrantes_activos = 2 From public.estado_whatsapp(v_familia_id)),
		(Select row_to_json(e)::text From public.estado_whatsapp(v_familia_id) e)
	);

	-- Avisos automáticos ---------------------------------------------------------
	Perform pg_temp.como('postgres');
	v_total := app_private.generar_avisos_whatsapp_impl(v_hoy);
	Perform pg_temp.esperar('Genera avisos del día', v_total = 2, v_total || ' avisos');
	v_total := app_private.generar_avisos_whatsapp_impl(v_hoy);
	Perform pg_temp.esperar(
		'Job de avisos ejecutado dos veces',
		v_total = 0 And (Select count(*) From public.avisos_whatsapp Where fecha_aviso = v_hoy) = 2,
		'Segunda ejecución: ' || v_total
	);
	Perform pg_temp.esperar(
		'Recibo sin monto confirmado no genera aviso',
		Not Exists (Select 1 From public.avisos_whatsapp Where recibo_id = v_internet),
		Null
	);
	Perform pg_temp.esperar(
		'Recaudación completa no genera aviso',
		Not Exists (Select 1 From public.avisos_whatsapp Where recibo_id = v_gas),
		Null
	);

	Select mensaje Into v_texto From public.avisos_whatsapp Where recibo_id = v_luz;
	Perform pg_temp.esperar(
		'Texto del aviso por vencer',
		v_texto Like '⏰ Luz vence en 3 días (% ' || To_Char(v_hoy + 3, 'DD/MM') || ')%'
			And v_texto Like '%Total: S/ 184.50%'
			And v_texto Like '%Falta recaudar: S/ 184.50%'
			And v_texto Like '%Pendientes: Ana S/ 92.25 · Luis S/ 92.25%',
		v_texto
	);

	Select mensaje Into v_texto From public.avisos_whatsapp Where recibo_id = v_agua;
	Perform pg_temp.esperar(
		'Texto del aviso vencido',
		v_texto Like '⚠️ Agua venció ayer%'
			And v_texto Like '%Falta recaudar: S/ 35.00%'
			And v_texto Like '%Pendiente: Luis S/ 35.00%',
		v_texto
	);

	-- Un aviso de otro día se descarta al tomar la cola.
	Perform app_private.generar_avisos_whatsapp_impl(v_hoy + 2);

	Perform pg_temp.como('service_role');
	Perform pg_temp.esperar(
		'Fuera de horario no entrega avisos',
		Not Exists (Select 1 From app_private.tomar_avisos_whatsapp_impl(v_madrugada)),
		Null
	);

	-- Ana paga su parte de la luz antes del envío: el aviso debe salir con montos actuales.
	Perform pg_temp.como('postgres');
	Perform pg_temp.pagar_cuota(v_luz, pg_temp.ctx('ANA')::uuid);
	Perform pg_temp.como('service_role');

	Select array_agg(t.id), count(*) Filter (Where t.grupo_id = G1)
	Into v_avisos, v_total
	From app_private.tomar_avisos_whatsapp_impl(v_mediodia) t;
	Perform pg_temp.esperar('Dentro de horario entrega avisos con el grupo', Coalesce(array_length(v_avisos, 1), 0) = 2 And v_total = 2, v_total || ' avisos para G1');

	Perform pg_temp.como('postgres');
	Select mensaje Into v_texto From public.avisos_whatsapp Where recibo_id = v_luz And fecha_aviso = v_hoy;
	Perform pg_temp.esperar(
		'El aviso recalcula montos al enviarse',
		v_texto Like '%Falta recaudar: S/ 92.25%' And v_texto Like '%Pendiente: Luis S/ 92.25%' And v_texto Not Like '%Ana%',
		v_texto
	);
	Perform pg_temp.esperar(
		'Aviso de otro día queda descartado',
		(Select estado From public.avisos_whatsapp Where fecha_aviso = v_hoy + 2) = 'DESCARTADO',
		Null
	);

	Perform pg_temp.como('service_role');
	Perform pg_temp.esperar(
		'Avisos tomados no se entregan dos veces',
		Not Exists (Select 1 From app_private.tomar_avisos_whatsapp_impl(v_mediodia)),
		Null
	);

	Select id Into v_aviso From public.avisos_whatsapp Where recibo_id = v_luz And fecha_aviso = v_hoy;
	Perform public.marcar_aviso_whatsapp(v_aviso.id, true);
	Perform pg_temp.como('postgres');
	Perform pg_temp.esperar(
		'Envío correcto marca ENVIADO',
		(Select estado = 'ENVIADO' And enviado_at Is Not Null From public.avisos_whatsapp Where id = v_aviso.id),
		Null
	);

	Perform pg_temp.como('service_role');
	Select id Into v_aviso From public.avisos_whatsapp Where recibo_id = v_agua And fecha_aviso = v_hoy;
	Perform public.marcar_aviso_whatsapp(v_aviso.id, false, 'timeout');
	Perform public.marcar_aviso_whatsapp(v_aviso.id, false, 'timeout');
	Perform pg_temp.como('postgres');
	Perform pg_temp.esperar(
		'Falla de envío permite reintento',
		(Select estado = 'PENDIENTE' And intentos = 2 From public.avisos_whatsapp Where id = v_aviso.id),
		Null
	);
	Perform pg_temp.como('service_role');
	Perform public.marcar_aviso_whatsapp(v_aviso.id, false, 'timeout');
	Perform pg_temp.como('postgres');
	Perform pg_temp.esperar(
		'Falla de envío 3 veces',
		(Select estado = 'ERROR' And intentos = 3 And error = 'timeout' From public.avisos_whatsapp Where id = v_aviso.id),
		Null
	);

	-- Un recibo que se completa antes del envío se descarta.
	v_cable := pg_temp.crear_servicio('Cable', 'CLARO', 40.00, 1);
	v_total := app_private.generar_avisos_whatsapp_impl(v_hoy);
	Perform pg_temp.pagar_cuota(v_cable, pg_temp.ctx('ANA')::uuid);
	Perform pg_temp.pagar_cuota(v_cable, pg_temp.ctx('LUIS')::uuid);
	Perform pg_temp.como('service_role');
	Perform pg_temp.esperar(
		'Recibo completado antes del envío no se envía',
		v_total = 1 And Not Exists (Select 1 From app_private.tomar_avisos_whatsapp_impl(v_mediodia)),
		Null
	);
	Perform pg_temp.como('postgres');
	Perform pg_temp.esperar(
		'Aviso de recibo completado queda descartado',
		(Select estado From public.avisos_whatsapp Where recibo_id = v_cable) = 'DESCARTADO',
		Null
	);

	-- Comandos de consulta -------------------------------------------------------
	Perform pg_temp.como('service_role');

	v_texto := pg_temp.responder(G1, LUIS_LID, '/ayuda');
	Perform pg_temp.esperar('/ayuda lista los comandos', v_texto Like '%/deuda%' And v_texto Like '%/vence%' And v_texto Like '%/resumen%', v_texto);

	v_texto := pg_temp.responder(G1, LUIS_LID, '/DEUDA');
	Perform pg_temp.como('postgres');
	Select Coalesce(Sum(c.saldo_pendiente), 0)
	Into v_debe_app
	From public.cuotas c
	Join public.recibos r On r.id = c.recibo_id
	Join public.periodos p On p.id = r.periodo_id
	Where c.usuario_id = pg_temp.ctx('LUIS')::uuid
		And p.anio = Extract(Year From v_hoy)
		And p.mes = Extract(Month From v_hoy)
		And c.estado <> 'ANULADA'
		And c.saldo_pendiente > 0;
	Perform pg_temp.esperar(
		'Montos de /deuda iguales a Mis cuotas',
		v_texto Like 'Luis, tienes ' || app_private.whatsapp_monto(v_debe_app) || ' pendientes:%'
			And v_texto Like '%• Agua: S/ 35.00 (vencida ' || To_Char(v_hoy - 1, 'DD/MM') || ')%'
			And v_texto Like '%• Luz: S/ 92.25 (vence ' || To_Char(v_hoy + 3, 'DD/MM') || ')%'
			And Position('Agua' In v_texto) < Position('Luz' In v_texto),
		v_texto
	);

	Perform pg_temp.como('service_role');
	v_texto := pg_temp.responder(G1, LUIS_PN, '/deuda', LUIS_LID);
	Perform pg_temp.esperar('Identifica al integrante por su identificador alterno', v_texto Like 'Luis, tienes%', v_texto);

	v_texto := pg_temp.responder(G1, ANA_LID, '/deuda');
	Perform pg_temp.esperar('/deuda sin pendientes', v_texto = 'Ana, no tienes cuotas pendientes este mes. ✅', v_texto);

	v_texto := pg_temp.responder(G1, LUIS_LID, '/vence');
	Perform pg_temp.esperar(
		'/vence muestra vencimientos del mes',
		v_texto Like 'Vencimientos de %'
			And v_texto Like '%• Agua: venció ' || To_Char(v_hoy - 1, 'DD/MM') || ' · falta S/ 35.00 · tú S/ 35.00%'
			And v_texto Like '%• Luz: vence ' || To_Char(v_hoy + 3, 'DD/MM') || ' (en 3 días) · falta S/ 92.25 · tú S/ 92.25%'
			And v_texto Like '%• Internet: esperando monto%'
			And v_texto Not Like '%Gas%',
		v_texto
	);

	v_texto := pg_temp.responder(G1, LUIS_LID, '/resumen');
	Perform pg_temp.esperar(
		'/resumen del mes',
		v_texto Like '%Recibos: 5 · Pagados al proveedor: 0%'
			And v_texto Like '%Recaudado: S/ 217.25 de S/ 344.50%'
			And v_texto Like '%Falta: S/ 127.25%'
			And v_texto Like '%Esperando monto: 1%',
		v_texto
	);

	v_texto := pg_temp.responder(G1, LUIS_LID, '/foo');
	Perform pg_temp.esperar('Comando desconocido', v_texto Like 'No conozco ese comando.%', v_texto);

	v_texto := pg_temp.responder(G1, LUIS_LID, 'hola a todos');
	Perform pg_temp.esperar('Mensaje sin comando se ignora', v_texto Is Null, v_texto);

	-- Desvinculación -------------------------------------------------------------
	Perform pg_temp.como('LUIS');
	v_error := pg_temp.error_de(Format('Select public.desvincular_whatsapp(%L, %L)', v_familia_id, 'GRUPO'));
	Perform pg_temp.esperar('Integrante no desvincula el grupo', v_error Like 'Solo un administrador%', v_error);
	Perform public.desvincular_whatsapp(v_familia_id, 'INTEGRANTE');
	Perform pg_temp.como('service_role');
	v_texto := pg_temp.responder(G1, LUIS_LID, '/deuda');
	Perform pg_temp.esperar('Integrante desvinculado', v_texto Like 'Aún no vinculas tu WhatsApp.%', v_texto);

	Perform pg_temp.como('ANA');
	Perform public.desvincular_whatsapp(v_familia_id, 'GRUPO');
	Perform pg_temp.como('service_role');
	v_texto := pg_temp.responder(G1, ANA_LID, '/ayuda');
	Perform pg_temp.esperar('Grupo desvinculado deja de responder', v_texto Is Null, v_texto);

	Perform pg_temp.como('postgres');
End;
$$;

Select Orden, Prueba, Resultado, Detalle
From wa_resultados
Order By Orden;

Select
	Count(*) Filter (Where Resultado = 'OK') As Ok,
	Count(*) Filter (Where Resultado <> 'OK') As Fallas
From wa_resultados;

Rollback;
