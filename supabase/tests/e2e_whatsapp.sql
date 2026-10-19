/*================================================================================
Objetivo:
	Validar de extremo a extremo el asistente de WhatsApp de FamiliaHub (Fase 12):
	vinculación, permisos, consultas, configuración y avisos automáticos, con los
	mismos usuarios reales de Supabase Auth que e2e_flujo_familiar.sql.

Requisitos:
	1. Ambos usuarios deben existir y tener el correo confirmado.
	2. Sus perfiles deben tener usuario definido (Jhosep y Liliana).
	3. Ninguno de los dos debe pertenecer a una familia activa.
	4. Ejecutar como rol postgres/service de mantenimiento.
	5. Configurar los correos solo en la sesión; no se guardan en el repositorio.

Ejemplo previo:
	Select set_config('familiahub.e2e_jhosep_email', '<correo-admin>', false);
	Select set_config('familiahub.e2e_liliana_email', '<correo-integrante>', false);

Importante:
	- Todo se ejecuta dentro de una transacción y termina con Rollback.
	- Los IDs de WhatsApp y grupos son ficticios; no se envía ningún mensaje.
	- Las funciones de jobs se llaman directamente, sin esperar a pg_cron.
================================================================================*/

Begin;

Create Temp Table e2e_contexto
(
	Clave varchar(60) Primary Key,
	Valor text Not Null
) On Commit Drop;

Create Temp Table e2e_resultados
(
	Prueba varchar(120) Not Null,
	Resultado varchar(20) Not Null,
	Detalle text Null
) On Commit Drop;

Grant Select, Insert, Update, Delete On e2e_contexto, e2e_resultados To authenticated, service_role;

Insert Into e2e_contexto (Clave, Valor)
Values
	('GRUPO_FAMILIA', '120363000000000001@g.us'),
	('GRUPO_AJENO', '120363000000000002@g.us'),
	('GRUPO_LIBRE', '120363000000000099@g.us'),
	('JHOSEP_PN', '51900000001@s.whatsapp.net'),
	('JHOSEP_LID', '100000000000001@lid'),
	('LILIANA_LID', '200000000000002@lid'),
	('LILIANA_PN', '51900000002@s.whatsapp.net');

/*--------------------------------------------------------------------------------
Preparación: usuarios, familia, integrante, método de cobro y servicio con cuotas.
--------------------------------------------------------------------------------*/

Do $$
Declare
	v_correo_jhosep text := NullIf(Current_Setting('familiahub.e2e_jhosep_email', true), '');
	v_correo_liliana text := NullIf(Current_Setting('familiahub.e2e_liliana_email', true), '');
	v_jhosep_id uuid;
	v_liliana_id uuid;
	v_usuario_jhosep text;
	v_usuario_liliana text;
	v_confirmado_jhosep timestamptz;
	v_confirmado_liliana timestamptz;
Begin
	If v_correo_jhosep Is Null Or v_correo_liliana Is Null Then
		Raise Exception 'Configura familiahub.e2e_jhosep_email y familiahub.e2e_liliana_email antes de ejecutar.';
	End If;

	Select id, email_confirmed_at Into v_jhosep_id, v_confirmado_jhosep From auth.users Where Lower(email) = Lower(v_correo_jhosep);
	Select id, email_confirmed_at Into v_liliana_id, v_confirmado_liliana From auth.users Where Lower(email) = Lower(v_correo_liliana);

	If v_jhosep_id Is Null Or v_liliana_id Is Null Then
		Raise Exception 'Ambas cuentas deben existir en Supabase Auth antes del E2E.';
	End If;

	If v_confirmado_jhosep Is Null Or v_confirmado_liliana Is Null Then
		Raise Exception 'Ambos correos deben estar confirmados antes del E2E.';
	End If;

	Select usuario Into v_usuario_jhosep From public.perfiles Where id = v_jhosep_id;
	Select usuario Into v_usuario_liliana From public.perfiles Where id = v_liliana_id;

	If Lower(Coalesce(v_usuario_jhosep, '')) <> 'jhosep' Or Lower(Coalesce(v_usuario_liliana, '')) <> 'liliana' Then
		Raise Exception 'Los perfiles deben usar los usuarios Jhosep y Liliana.';
	End If;

	Insert Into e2e_contexto (Clave, Valor)
	Values
		('JHOSEP_USUARIO_ID', v_jhosep_id::text),
		('LILIANA_USUARIO_ID', v_liliana_id::text);

	Insert Into e2e_resultados (Prueba, Resultado, Detalle)
	Values ('00a. Auth y perfiles', 'OK', 'Usuarios reales, correos confirmados y usernames correctos.');
End;
$$;

Set Local Role authenticated;

Select set_config('request.jwt.claims', Json_Build_Object('sub', (Select Valor From e2e_contexto Where Clave = 'JHOSEP_USUARIO_ID'), 'role', 'authenticated')::text, true);

Do $$
Declare
	v_familia_id uuid;
Begin
	Select public.crear_familia_inicial('FamiliaHub WhatsApp E2E') Into v_familia_id;

	Insert Into e2e_contexto (Clave, Valor) Values ('FAMILIA_ID', v_familia_id::text);
End;
$$;

Reset Role;

Insert Into e2e_contexto (Clave, Valor)
Select 'JHOSEP_MIEMBRO_ID', id::text
From public.miembros_familia
Where familia_id = (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID')
	and usuario_id = (Select Valor::uuid From e2e_contexto Where Clave = 'JHOSEP_USUARIO_ID');

Insert Into public.miembros_familia (familia_id, usuario_id, rol, estado)
Values
(
	(Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID'),
	(Select Valor::uuid From e2e_contexto Where Clave = 'LILIANA_USUARIO_ID'),
	'INTEGRANTE',
	'ACTIVO'
);

Insert Into e2e_contexto (Clave, Valor)
Select 'LILIANA_MIEMBRO_ID', id::text
From public.miembros_familia
Where familia_id = (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID')
	and usuario_id = (Select Valor::uuid From e2e_contexto Where Clave = 'LILIANA_USUARIO_ID');

Set Local Role authenticated;

Select set_config('request.jwt.claims', Json_Build_Object('sub', (Select Valor From e2e_contexto Where Clave = 'JHOSEP_USUARIO_ID'), 'role', 'authenticated')::text, true);

Do $$
Declare
	v_familia_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID');
	v_jhosep_miembro_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'JHOSEP_MIEMBRO_ID');
	v_liliana_miembro_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'LILIANA_MIEMBRO_ID');
	v_categoria_id uuid;
	v_proveedor_id uuid;
	v_plantilla_id uuid;
	v_concepto_id uuid;
	v_recibo_id uuid;
Begin
	Select id Into v_categoria_id From public.categorias Where familia_id = v_familia_id and nombre = 'Servicios' and activo = true;
	Select id Into v_proveedor_id From public.proveedores Where codigo = 'WIN' and activo = true;
	Select id Into v_plantilla_id From public.plantillas_servicio Where codigo = 'INTERNET' and activo = true;

	Perform public.guardar_metodo_cobro_familiar(
		v_familia_id,
		'YAPE',
		'Jhosep',
		'972583495',
		'Prueba E2E sin movimiento real de dinero.',
		Null,
		v_jhosep_miembro_id
	);

	Select public.guardar_concepto_servicio_fase6(
		Null,
		v_familia_id,
		v_categoria_id,
		v_proveedor_id,
		v_plantilla_id,
		'Prueba WhatsApp E2E',
		'MENSUAL',
		'FIJO',
		2.00,
		'DIA_FIJO',
		28::smallint,
		'IGUAL',
		Null,
		false,
		'{}'::jsonb,
		Jsonb_Build_Array(
			Jsonb_Build_Object('miembro_id', v_jhosep_miembro_id, 'modalidad', 'IGUAL', 'valor', Null),
			Jsonb_Build_Object('miembro_id', v_liliana_miembro_id, 'modalidad', 'IGUAL', 'valor', Null)
		),
		(timezone('America/Lima', now()))::date,
		2::smallint
	)
	Into v_concepto_id;

	Select id Into v_recibo_id From public.recibos Where familia_id = v_familia_id and concepto_id = v_concepto_id Order By created_at Desc Limit 1;

	If v_recibo_id Is Null Then
		Raise Exception 'No se generó el recibo de prueba.';
	End If;

	Insert Into e2e_contexto (Clave, Valor) Values ('RECIBO_ID', v_recibo_id::text);
End;
$$;

Reset Role;

Insert Into e2e_contexto (Clave, Valor)
Select 'CUOTA_LILIANA_ID', id::text
From public.cuotas
Where recibo_id = (Select Valor::uuid From e2e_contexto Where Clave = 'RECIBO_ID')
	and usuario_id = (Select Valor::uuid From e2e_contexto Where Clave = 'LILIANA_USUARIO_ID');

Insert Into e2e_resultados (Prueba, Resultado, Detalle)
Select '00b. Familia y recibo', 'OK', 'Recibo S/2.00 dividido entre Jhosep y Liliana.'
Where Exists (Select 1 From e2e_contexto Where Clave = 'CUOTA_LILIANA_ID');

/*--------------------------------------------------------------------------------
30. Formatos de monto y fecha (6.9).
--------------------------------------------------------------------------------*/

Do $$
Begin
	If app_private.whatsapp_monto(1184.5, 'PEN') <> 'S/ 1,184.50'
		Or app_private.whatsapp_monto(20, 'USD') <> 'US$ 20.00'
		Or app_private.whatsapp_monto(15, 'EUR') <> 'EUR 15.00'
		Or app_private.whatsapp_monto(0.5, 'PEN') <> 'S/ 0.50'
		Or app_private.whatsapp_fecha('2026-10-12') <> 'lun 12/10'
		Or app_private.whatsapp_fecha('2026-10-14') <> 'mié 14/10'
		Or app_private.whatsapp_fecha('2026-10-17') <> 'sáb 17/10'
		Or app_private.whatsapp_mes(2026::smallint, 10::smallint) <> 'Octubre 2026'
	Then
		Raise Exception 'Formato inesperado: %, %, %', app_private.whatsapp_monto(1184.5, 'PEN'), app_private.whatsapp_fecha('2026-10-12'), app_private.whatsapp_mes(2026::smallint, 10::smallint);
	End If;

	If char_length(app_private.whatsapp_recortar(repeat(E'• línea de prueba\n', 200))) > 1500
		Or app_private.whatsapp_recortar(repeat(E'• línea de prueba\n', 200)) Not Like '%… y % más'
	Then
		Raise Exception 'El recorte de textos largos no respeta 1,500 caracteres.';
	End If;

	Insert Into e2e_resultados Values ('30. Formatos de monto y fecha', 'OK', 'S/ 1,184.50 · US$ 20.00 · EUR 15.00 · lun 12/10 · Octubre 2026');
Exception
	When Others Then
		Insert Into e2e_resultados Values ('30. Formatos de monto y fecha', 'ERROR', SqlErrM);
End;
$$;

/*--------------------------------------------------------------------------------
1. Integrante no puede generar código de grupo.
--------------------------------------------------------------------------------*/

Set Local Role authenticated;

Select set_config('request.jwt.claims', Json_Build_Object('sub', (Select Valor From e2e_contexto Where Clave = 'LILIANA_USUARIO_ID'), 'role', 'authenticated')::text, true);

Do $$
Declare
	v_error text;
Begin
	Begin
		Perform public.generar_codigo_whatsapp((Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID'), 'GRUPO');
	Exception
		When Others Then
			v_error := SqlErrM;
	End;

	If v_error Is Distinct From 'Solo un administrador puede vincular el grupo de WhatsApp.' Then
		Raise Exception 'Se esperaba rechazo y se obtuvo: %', Coalesce(v_error, 'sin error');
	End If;

	Insert Into e2e_resultados Values ('01. Integrante sin código de grupo', 'OK', v_error);
Exception
	When Others Then
		Insert Into e2e_resultados Values ('01. Integrante sin código de grupo', 'ERROR', SqlErrM);
End;
$$;

/*--------------------------------------------------------------------------------
2. Administrador genera código de grupo; regenerar mantiene una sola fila.
3. authenticated no lee tablas whatsapp_* ni ejecuta funciones de service_role.
--------------------------------------------------------------------------------*/

Select set_config('request.jwt.claims', Json_Build_Object('sub', (Select Valor From e2e_contexto Where Clave = 'JHOSEP_USUARIO_ID'), 'role', 'authenticated')::text, true);

Do $$
Declare
	v_familia_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID');
	v_primero jsonb;
	v_segundo jsonb;
Begin
	v_primero := public.generar_codigo_whatsapp(v_familia_id, 'GRUPO');
	v_segundo := public.generar_codigo_whatsapp(v_familia_id, 'GRUPO');

	If v_segundo ->> 'codigo' !~ '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{6}$' Or v_segundo ->> 'expiraAt' Is Null Then
		Raise Exception 'Código con formato inesperado: %', v_segundo;
	End If;

	If v_primero ->> 'codigo' = v_segundo ->> 'codigo' Then
		Raise Exception 'Regenerar debería producir un código nuevo.';
	End If;

	Insert Into e2e_contexto (Clave, Valor) Values ('CODIGO_GRUPO_ANTERIOR', v_primero ->> 'codigo'), ('CODIGO_GRUPO', v_segundo ->> 'codigo');
Exception
	When Others Then
		Insert Into e2e_resultados Values ('02. Código de grupo del administrador', 'ERROR', SqlErrM);
End;
$$;

Do $$
Declare
	v_errores text[] := '{}';
Begin
	Begin
		Perform count(*) From public.whatsapp_vinculos;
		v_errores := v_errores || 'whatsapp_vinculos legible'::text;
	Exception
		When insufficient_privilege Then Null;
	End;

	Begin
		Perform count(*) From public.whatsapp_configuracion;
		v_errores := v_errores || 'whatsapp_configuracion legible'::text;
	Exception
		When insufficient_privilege Then Null;
	End;

	Begin
		Perform count(*) From public.avisos_whatsapp;
		v_errores := v_errores || 'avisos_whatsapp legible'::text;
	Exception
		When insufficient_privilege Then Null;
	End;

	Begin
		Perform count(*) From public.whatsapp_sistema;
		v_errores := v_errores || 'whatsapp_sistema legible'::text;
	Exception
		When insufficient_privilege Then Null;
	End;

	Begin
		Perform public.whatsapp_procesar_comando('x@g.us', Array['y@lid'], 'ayuda', '');
		v_errores := v_errores || 'whatsapp_procesar_comando ejecutable'::text;
	Exception
		When insufficient_privilege Then Null;
	End;

	Begin
		Perform public.whatsapp_tomar_avisos(5::smallint);
		v_errores := v_errores || 'whatsapp_tomar_avisos ejecutable'::text;
	Exception
		When insufficient_privilege Then Null;
	End;

	Begin
		Perform public.whatsapp_heartbeat('e2e');
		v_errores := v_errores || 'whatsapp_heartbeat ejecutable'::text;
	Exception
		When insufficient_privilege Then Null;
	End;

	Begin
		Perform app_private.whatsapp_procesar_eventos();
		v_errores := v_errores || 'whatsapp_procesar_eventos ejecutable'::text;
	Exception
		When insufficient_privilege Then Null;
	End;

	If cardinality(v_errores) > 0 Then
		Raise Exception 'Permisos abiertos: %', array_to_string(v_errores, ', ');
	End If;

	Insert Into e2e_resultados Values ('03. authenticated sin acceso directo', 'OK', 'Tablas y funciones de servicio protegidas.');
Exception
	When Others Then
		Insert Into e2e_resultados Values ('03. authenticated sin acceso directo', 'ERROR', SqlErrM);
End;
$$;

Reset Role;

Do $$
Declare
	v_filas integer;
Begin
	Select count(*) Into v_filas
	From public.whatsapp_vinculos
	Where familia_id = (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID')
		and tipo = 'GRUPO';

	If v_filas <> 1 Or Not Exists (
		Select 1 From public.whatsapp_vinculos Where codigo = (Select Valor From e2e_contexto Where Clave = 'CODIGO_GRUPO')
	) Then
		Raise Exception 'Se esperaba una sola fila con el último código y hay %.', v_filas;
	End If;

	Insert Into e2e_resultados Values ('02. Código de grupo del administrador', 'OK', 'Una sola fila; el código se reemplazó al regenerar.');
Exception
	When Others Then
		Insert Into e2e_resultados Values ('02. Código de grupo del administrador', 'ERROR', SqlErrM);
End;
$$;

/*--------------------------------------------------------------------------------
16. Comando en grupo no vinculado.
4. Vincular grupo con código válido.
5. Código reusado es rechazado.
--------------------------------------------------------------------------------*/

Set Local Role service_role;

Do $$
Declare
	v_respuesta jsonb;
Begin
	v_respuesta := public.whatsapp_procesar_comando(
		(Select Valor From e2e_contexto Where Clave = 'GRUPO_LIBRE'),
		Array[(Select Valor From e2e_contexto Where Clave = 'JHOSEP_PN')],
		'deuda',
		''
	);

	If v_respuesta ->> 'texto' Is Distinct From 'Este grupo aún no está vinculado a una familia. Un administrador debe escribir /vincular-grupo CÓDIGO.'
		Or (v_respuesta ->> 'grupoVinculado')::boolean Is Distinct From false
	Then
		Raise Exception 'Respuesta inesperada: %', v_respuesta;
	End If;

	Insert Into e2e_resultados Values ('16. Grupo no vinculado', 'OK', v_respuesta ->> 'texto');
Exception
	When Others Then
		Insert Into e2e_resultados Values ('16. Grupo no vinculado', 'ERROR', SqlErrM);
End;
$$;

Do $$
Declare
	v_texto text;
Begin
	v_texto := public.whatsapp_procesar_comando(
		(Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'),
		Array[(Select Valor From e2e_contexto Where Clave = 'JHOSEP_PN'), (Select Valor From e2e_contexto Where Clave = 'JHOSEP_LID')],
		'vincular-grupo',
		Lower((Select Valor From e2e_contexto Where Clave = 'CODIGO_GRUPO'))
	) ->> 'texto';

	If v_texto Is Distinct From 'Listo. Este grupo quedó vinculado a la familia FamiliaHub WhatsApp E2E. Escriban /ayuda para ver lo que puedo hacer.' Then
		Raise Exception 'Respuesta inesperada: %', v_texto;
	End If;

	Insert Into e2e_resultados Values ('04. Vincular grupo', 'OK', v_texto);
Exception
	When Others Then
		Insert Into e2e_resultados Values ('04. Vincular grupo', 'ERROR', SqlErrM);
End;
$$;

Do $$
Declare
	v_error_reuso text;
	v_error_anterior text;
Begin
	Begin
		Perform public.whatsapp_procesar_comando(
			(Select Valor From e2e_contexto Where Clave = 'GRUPO_LIBRE'),
			Array[(Select Valor From e2e_contexto Where Clave = 'JHOSEP_PN')],
			'vincular-grupo',
			(Select Valor From e2e_contexto Where Clave = 'CODIGO_GRUPO')
		);
	Exception
		When Others Then
			v_error_reuso := SqlErrM;
	End;

	Begin
		Perform public.whatsapp_procesar_comando(
			(Select Valor From e2e_contexto Where Clave = 'GRUPO_LIBRE'),
			Array[(Select Valor From e2e_contexto Where Clave = 'JHOSEP_PN')],
			'vincular-grupo',
			(Select Valor From e2e_contexto Where Clave = 'CODIGO_GRUPO_ANTERIOR')
		);
	Exception
		When Others Then
			v_error_anterior := SqlErrM;
	End;

	If v_error_reuso Is Distinct From 'Código inválido o vencido. Genera uno nuevo en FamiliaHub.'
		Or v_error_anterior Is Distinct From 'Código inválido o vencido. Genera uno nuevo en FamiliaHub.'
	Then
		Raise Exception 'Reuso: %, reemplazado: %', Coalesce(v_error_reuso, 'aceptado'), Coalesce(v_error_anterior, 'aceptado');
	End If;

	Insert Into e2e_resultados Values ('05a. Código reusado o reemplazado', 'OK', v_error_reuso);
Exception
	When Others Then
		Insert Into e2e_resultados Values ('05a. Código reusado o reemplazado', 'ERROR', SqlErrM);
End;
$$;

/*--------------------------------------------------------------------------------
5. Código vencido es rechazado.
--------------------------------------------------------------------------------*/

Set Local Role authenticated;

Select set_config('request.jwt.claims', Json_Build_Object('sub', (Select Valor From e2e_contexto Where Clave = 'LILIANA_USUARIO_ID'), 'role', 'authenticated')::text, true);

Do $$
Begin
	Insert Into e2e_contexto (Clave, Valor)
	Values ('CODIGO_LILIANA', public.generar_codigo_whatsapp((Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID'), 'INTEGRANTE') ->> 'codigo');
End;
$$;

Reset Role;

Update public.whatsapp_vinculos
Set codigo_expira_at = now() - interval '1 minute'
Where codigo = (Select Valor From e2e_contexto Where Clave = 'CODIGO_LILIANA');

Set Local Role service_role;

Do $$
Declare
	v_error text;
Begin
	Begin
		Perform public.whatsapp_procesar_comando(
			(Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'),
			Array[(Select Valor From e2e_contexto Where Clave = 'LILIANA_LID')],
			'vincular',
			(Select Valor From e2e_contexto Where Clave = 'CODIGO_LILIANA')
		);
	Exception
		When Others Then
			v_error := SqlErrM;
	End;

	If v_error Is Distinct From 'Código inválido o vencido. Genera uno nuevo en FamiliaHub.' Then
		Raise Exception 'Se esperaba código vencido y se obtuvo: %', Coalesce(v_error, 'aceptado');
	End If;

	Insert Into e2e_resultados Values ('05b. Código vencido', 'OK', v_error);
Exception
	When Others Then
		Insert Into e2e_resultados Values ('05b. Código vencido', 'ERROR', SqlErrM);
End;
$$;

/*--------------------------------------------------------------------------------
Otra familia con grupo propio y un código de grupo pendiente (casos 6, 7 y 8).
--------------------------------------------------------------------------------*/

Reset Role;

Insert Into public.familias (nombre, creado_por)
Values ('Familia Ajena E2E', (Select Valor::uuid From e2e_contexto Where Clave = 'LILIANA_USUARIO_ID'));

Insert Into e2e_contexto (Clave, Valor)
Select 'FAMILIA_AJENA_ID', id::text From public.familias Where nombre = 'Familia Ajena E2E' Order By created_at Desc Limit 1;

Insert Into public.whatsapp_vinculos (familia_id, tipo, whatsapp_id, vinculado_at, codigo, codigo_expira_at)
Values
(
	(Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_AJENA_ID'),
	'GRUPO',
	(Select Valor From e2e_contexto Where Clave = 'GRUPO_AJENO'),
	now(),
	'ZZZZZ2',
	now() + interval '10 minutes'
);

Set Local Role authenticated;

Select set_config('request.jwt.claims', Json_Build_Object('sub', (Select Valor From e2e_contexto Where Clave = 'LILIANA_USUARIO_ID'), 'role', 'authenticated')::text, true);

Do $$
Begin
	Update e2e_contexto
	Set Valor = public.generar_codigo_whatsapp((Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID'), 'INTEGRANTE') ->> 'codigo'
	Where Clave = 'CODIGO_LILIANA';
End;
$$;

Set Local Role service_role;

Do $$
Declare
	v_error_integrante text;
	v_error_grupo text;
Begin
	Begin
		Perform public.whatsapp_procesar_comando(
			(Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'),
			Array[(Select Valor From e2e_contexto Where Clave = 'LILIANA_LID')],
			'vincular-grupo',
			(Select Valor From e2e_contexto Where Clave = 'CODIGO_LILIANA')
		);
	Exception
		When Others Then
			v_error_integrante := SqlErrM;
	End;

	Begin
		Perform public.whatsapp_procesar_comando(
			(Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'),
			Array[(Select Valor From e2e_contexto Where Clave = 'LILIANA_LID')],
			'vincular',
			'ZZZZZ2'
		);
	Exception
		When Others Then
			v_error_grupo := SqlErrM;
	End;

	If v_error_integrante Is Distinct From 'Ese código es para /vincular.'
		Or v_error_grupo Is Distinct From 'Ese código es para /vincular-grupo.'
	Then
		Raise Exception 'Integrante: %, grupo: %', Coalesce(v_error_integrante, 'aceptado'), Coalesce(v_error_grupo, 'aceptado');
	End If;

	Insert Into e2e_resultados Values ('06. Código usado con comando equivocado', 'OK', v_error_integrante || ' / ' || v_error_grupo);
Exception
	When Others Then
		Insert Into e2e_resultados Values ('06. Código usado con comando equivocado', 'ERROR', SqlErrM);
End;
$$;

Do $$
Declare
	v_error text;
Begin
	Begin
		Perform public.whatsapp_procesar_comando(
			(Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'),
			Array[(Select Valor From e2e_contexto Where Clave = 'LILIANA_LID')],
			'vincular-grupo',
			'zzzzz2'
		);
	Exception
		When Others Then
			v_error := SqlErrM;
	End;

	If v_error Is Distinct From 'Este grupo ya está vinculado a otra familia.' Then
		Raise Exception 'Se esperaba rechazo y se obtuvo: %', Coalesce(v_error, 'aceptado');
	End If;

	Insert Into e2e_resultados Values ('07. Otra familia no toma el grupo', 'OK', v_error);
Exception
	When Others Then
		Insert Into e2e_resultados Values ('07. Otra familia no toma el grupo', 'ERROR', SqlErrM);
End;
$$;

Do $$
Declare
	v_error text;
Begin
	Begin
		Perform public.whatsapp_procesar_comando(
			(Select Valor From e2e_contexto Where Clave = 'GRUPO_AJENO'),
			Array[(Select Valor From e2e_contexto Where Clave = 'LILIANA_LID')],
			'vincular',
			(Select Valor From e2e_contexto Where Clave = 'CODIGO_LILIANA')
		);
	Exception
		When Others Then
			v_error := SqlErrM;
	End;

	If v_error Is Distinct From 'Usa el código en el grupo vinculado a tu familia.' Then
		Raise Exception 'Se esperaba rechazo y se obtuvo: %', Coalesce(v_error, 'aceptado');
	End If;

	Insert Into e2e_resultados Values ('08. Código de integrante en grupo ajeno', 'OK', v_error);
Exception
	When Others Then
		Insert Into e2e_resultados Values ('08. Código de integrante en grupo ajeno', 'ERROR', SqlErrM);
End;
$$;

/*--------------------------------------------------------------------------------
Vincular a Jhosep (número + LID).
9. Dos integrantes no pueden usar el mismo ID principal ni alterno.
--------------------------------------------------------------------------------*/

Set Local Role authenticated;

Select set_config('request.jwt.claims', Json_Build_Object('sub', (Select Valor From e2e_contexto Where Clave = 'JHOSEP_USUARIO_ID'), 'role', 'authenticated')::text, true);

Do $$
Begin
	Insert Into e2e_contexto (Clave, Valor)
	Values ('CODIGO_JHOSEP', public.generar_codigo_whatsapp((Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID'), 'INTEGRANTE') ->> 'codigo');
End;
$$;

Set Local Role service_role;

Do $$
Declare
	v_texto text;
	v_error_principal text;
	v_error_alterno text;
Begin
	v_texto := public.whatsapp_procesar_comando(
		(Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'),
		Array[(Select Valor From e2e_contexto Where Clave = 'JHOSEP_PN'), (Select Valor From e2e_contexto Where Clave = 'JHOSEP_LID')],
		'vincular',
		(Select Valor From e2e_contexto Where Clave = 'CODIGO_JHOSEP')
	) ->> 'texto';

	If v_texto Is Distinct From 'Listo, Jhosep. Tu WhatsApp quedó vinculado.' Then
		Raise Exception 'Vínculo de Jhosep inesperado: %', v_texto;
	End If;

	Begin
		Perform public.whatsapp_procesar_comando(
			(Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'),
			Array[(Select Valor From e2e_contexto Where Clave = 'JHOSEP_PN')],
			'vincular',
			(Select Valor From e2e_contexto Where Clave = 'CODIGO_LILIANA')
		);
	Exception
		When Others Then
			v_error_principal := SqlErrM;
	End;

	Begin
		Perform public.whatsapp_procesar_comando(
			(Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'),
			Array[(Select Valor From e2e_contexto Where Clave = 'LILIANA_LID'), (Select Valor From e2e_contexto Where Clave = 'JHOSEP_LID')],
			'vincular',
			(Select Valor From e2e_contexto Where Clave = 'CODIGO_LILIANA')
		);
	Exception
		When Others Then
			v_error_alterno := SqlErrM;
	End;

	If v_error_principal Is Distinct From 'Este WhatsApp ya está vinculado a otro integrante.'
		Or v_error_alterno Is Distinct From 'Este WhatsApp ya está vinculado a otro integrante.'
	Then
		Raise Exception 'Principal: %, alterno: %', Coalesce(v_error_principal, 'aceptado'), Coalesce(v_error_alterno, 'aceptado');
	End If;

	Insert Into e2e_resultados Values ('09. IDs de WhatsApp únicos por familia', 'OK', v_error_principal);
Exception
	When Others Then
		Insert Into e2e_resultados Values ('09. IDs de WhatsApp únicos por familia', 'ERROR', SqlErrM);
End;
$$;

/*--------------------------------------------------------------------------------
10. Integrante inactivo no puede vincularse.
--------------------------------------------------------------------------------*/

Reset Role;

Update public.miembros_familia
Set estado = 'INACTIVO'
Where id = (Select Valor::uuid From e2e_contexto Where Clave = 'LILIANA_MIEMBRO_ID');

Set Local Role service_role;

Do $$
Declare
	v_error text;
Begin
	Begin
		Perform public.whatsapp_procesar_comando(
			(Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'),
			Array[(Select Valor From e2e_contexto Where Clave = 'LILIANA_LID')],
			'vincular',
			(Select Valor From e2e_contexto Where Clave = 'CODIGO_LILIANA')
		);
	Exception
		When Others Then
			v_error := SqlErrM;
	End;

	If v_error Is Distinct From 'Tu acceso a la familia no está activo.' Then
		Raise Exception 'Se esperaba rechazo y se obtuvo: %', Coalesce(v_error, 'aceptado');
	End If;

	Insert Into e2e_resultados Values ('10. Integrante inactivo', 'OK', v_error);
Exception
	When Others Then
		Insert Into e2e_resultados Values ('10. Integrante inactivo', 'ERROR', SqlErrM);
End;
$$;

Reset Role;

Update public.miembros_familia
Set estado = 'ACTIVO'
Where id = (Select Valor::uuid From e2e_contexto Where Clave = 'LILIANA_MIEMBRO_ID');

/*--------------------------------------------------------------------------------
Vincular a Liliana (LID + número).
11. El contexto reconoce al integrante por su ID alterno.
--------------------------------------------------------------------------------*/

Set Local Role service_role;

Do $$
Declare
	v_vinculo text;
	v_yo text;
Begin
	v_vinculo := public.whatsapp_procesar_comando(
		(Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'),
		Array[(Select Valor From e2e_contexto Where Clave = 'LILIANA_LID'), (Select Valor From e2e_contexto Where Clave = 'LILIANA_PN')],
		'vincular',
		(Select Valor From e2e_contexto Where Clave = 'CODIGO_LILIANA')
	) ->> 'texto';

	If v_vinculo Is Distinct From 'Listo, Liliana. Tu WhatsApp quedó vinculado.' Then
		Raise Exception 'Vínculo de Liliana inesperado: %', v_vinculo;
	End If;

	v_yo := public.whatsapp_procesar_comando(
		(Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'),
		Array[(Select Valor From e2e_contexto Where Clave = 'LILIANA_PN')],
		'yo',
		''
	) ->> 'texto';

	If v_yo Is Distinct From 'Estás vinculado como Liliana (Integrante) en la familia FamiliaHub WhatsApp E2E.' Then
		Raise Exception '/yo inesperado: %', v_yo;
	End If;

	Insert Into e2e_resultados Values ('11. Contexto por ID alterno', 'OK', v_yo);
Exception
	When Others Then
		Insert Into e2e_resultados Values ('11. Contexto por ID alterno', 'ERROR', SqlErrM);
End;
$$;

/*--------------------------------------------------------------------------------
12. /deuda coincide con la regla 6.3.
13. /pendientes y /resumen coinciden con 6.4 y 6.5.
--------------------------------------------------------------------------------*/

Reset Role;

Do $$
Declare
	v_familia_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID');
	v_periodo_id uuid;
	v_debe numeric;
	v_total numeric;
	v_recaudado numeric;
	v_falta numeric;
Begin
	Select id Into v_periodo_id
	From public.periodos
	Where familia_id = v_familia_id
		and anio = extract(year from timezone('America/Lima', now()))::smallint
		and mes = extract(month from timezone('America/Lima', now()))::smallint;

	Select coalesce(sum(q.saldo_pendiente), 0) Into v_debe
	From public.cuotas q
	Inner Join public.recibos r On r.id = q.recibo_id
	Where q.familia_id = v_familia_id
		and q.usuario_id = (Select Valor::uuid From e2e_contexto Where Clave = 'LILIANA_USUARIO_ID')
		and r.periodo_id = v_periodo_id
		and q.estado <> 'ANULADA'
		and q.saldo_pendiente > 0;

	Select coalesce(sum(monto_total), 0) Into v_total
	From public.recibos
	Where periodo_id = v_periodo_id and estado <> 'ANULADO' and monto_total Is Not Null;

	Select coalesce(sum(q.monto_pagado), 0), coalesce(sum(q.saldo_pendiente), 0) Into v_recaudado, v_falta
	From public.cuotas q
	Inner Join public.recibos r On r.id = q.recibo_id
	Where r.periodo_id = v_periodo_id and r.estado <> 'ANULADO' and q.estado <> 'ANULADA';

	Insert Into e2e_contexto (Clave, Valor)
	Values
		('ESPERADO_DEUDA', app_private.whatsapp_monto(v_debe, 'PEN')),
		('ESPERADO_RESUMEN', 'Recaudado ' || app_private.whatsapp_monto(v_recaudado, 'PEN') || ' de ' || app_private.whatsapp_monto(v_total, 'PEN') || ' (' || round(v_recaudado / v_total * 100)::int || '%)'),
		('ESPERADO_FALTA', app_private.whatsapp_monto(v_falta, 'PEN'));
End;
$$;

Set Local Role service_role;

Do $$
Declare
	v_texto text;
Begin
	v_texto := public.whatsapp_procesar_comando(
		(Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'),
		Array[(Select Valor From e2e_contexto Where Clave = 'LILIANA_LID')],
		'deuda',
		''
	) ->> 'texto';

	If v_texto Not Like 'Liliana, debes ' || (Select Valor From e2e_contexto Where Clave = 'ESPERADO_DEUDA') || ' este mes:%'
		Or v_texto Not Like '%Prueba WhatsApp E2E: S/ 1.00%'
		Or v_texto Not Like '%Paga desde {APP_URL}/pagar'
	Then
		Raise Exception '/deuda inesperado: %', v_texto;
	End If;

	Insert Into e2e_resultados Values ('12. /deuda igual a la app', 'OK', Replace(v_texto, E'\n', ' | '));
Exception
	When Others Then
		Insert Into e2e_resultados Values ('12. /deuda igual a la app', 'ERROR', SqlErrM);
End;
$$;

Do $$
Declare
	v_pendientes text;
	v_resumen text;
Begin
	v_pendientes := public.whatsapp_procesar_comando(
		(Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'),
		Array[(Select Valor From e2e_contexto Where Clave = 'LILIANA_LID')],
		'pendientes',
		''
	) ->> 'texto';

	v_resumen := public.whatsapp_procesar_comando(
		(Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'),
		Array['999999999@s.whatsapp.net'],
		'resumen',
		''
	) ->> 'texto';

	If v_pendientes Not Like '📌 *Falta aportar — %'
		Or v_pendientes Not Like '%• Jhosep: S/ 1.00 (Prueba WhatsApp E2E S/ 1.00)%'
		Or v_pendientes Not Like '%• Liliana: S/ 1.00 (Prueba WhatsApp E2E S/ 1.00)%'
	Then
		Raise Exception '/pendientes inesperado: %', v_pendientes;
	End If;

	If v_resumen Not Like '📊 *Resumen — %'
		Or v_resumen Not Like '%' || (Select Valor From e2e_contexto Where Clave = 'ESPERADO_RESUMEN') || ' · falta ' || (Select Valor From e2e_contexto Where Clave = 'ESPERADO_FALTA') || '%'
		Or v_resumen Not Like '%Pagados a la empresa: 0 de 1%'
	Then
		Raise Exception '/resumen inesperado: %', v_resumen;
	End If;

	Insert Into e2e_resultados Values ('13. /pendientes y /resumen', 'OK', Replace(v_resumen, E'\n', ' | '));
Exception
	When Others Then
		Insert Into e2e_resultados Values ('13. /pendientes y /resumen', 'ERROR', SqlErrM);
End;
$$;

/*--------------------------------------------------------------------------------
14. /porvalidar rechaza a un integrante sin rol ni responsabilidad.
15. /avisos pausar rechaza a un integrante y funciona con administrador.
--------------------------------------------------------------------------------*/

Do $$
Declare
	v_liliana text;
	v_jhosep text;
Begin
	v_liliana := public.whatsapp_procesar_comando(
		(Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'),
		Array[(Select Valor From e2e_contexto Where Clave = 'LILIANA_LID')],
		'porvalidar',
		''
	) ->> 'texto';

	v_jhosep := public.whatsapp_procesar_comando(
		(Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'),
		Array[(Select Valor From e2e_contexto Where Clave = 'JHOSEP_LID')],
		'porvalidar',
		''
	) ->> 'texto';

	If v_liliana Is Distinct From 'Este comando es solo para administradores.' Or v_jhosep Is Distinct From 'No hay pagos por validar. ✅' Then
		Raise Exception 'Liliana: %, Jhosep: %', v_liliana, v_jhosep;
	End If;

	Insert Into e2e_resultados Values ('14. /porvalidar con permisos', 'OK', v_liliana || ' / ' || v_jhosep);
Exception
	When Others Then
		Insert Into e2e_resultados Values ('14. /porvalidar con permisos', 'ERROR', SqlErrM);
End;
$$;

Do $$
Declare
	v_liliana text;
	v_pausar text;
	v_estado text;
	v_reanudar text;
	v_activos boolean;
Begin
	v_liliana := public.whatsapp_procesar_comando(
		(Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'),
		Array[(Select Valor From e2e_contexto Where Clave = 'LILIANA_PN')],
		'avisos',
		'pausar'
	) ->> 'texto';

	v_pausar := public.whatsapp_procesar_comando(
		(Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'),
		Array[(Select Valor From e2e_contexto Where Clave = 'JHOSEP_PN')],
		'avisos',
		'pausar'
	) ->> 'texto';

	v_estado := public.whatsapp_procesar_comando(
		(Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'),
		Array[(Select Valor From e2e_contexto Where Clave = 'JHOSEP_PN')],
		'avisos',
		'estado'
	) ->> 'texto';

	v_reanudar := public.whatsapp_procesar_comando(
		(Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'),
		Array[(Select Valor From e2e_contexto Where Clave = 'JHOSEP_PN')],
		'avisos',
		'reanudar'
	) ->> 'texto';

	If v_liliana Is Distinct From 'Este comando es solo para administradores.'
		Or v_pausar Is Distinct From 'Avisos automáticos pausados. Reanúdalos con /avisos reanudar.'
		Or v_estado Is Distinct From E'🔔 Avisos: pausados\nRecordatorios: 3 y 1 días antes, el día límite y vencidos cada 3 días\nHorario: 08:00 a 21:00\nResumen: domingo 19:00'
		Or v_reanudar Is Distinct From 'Avisos automáticos activados.'
	Then
		Raise Exception 'Liliana: % | pausar: % | estado: % | reanudar: %', v_liliana, v_pausar, v_estado, v_reanudar;
	End If;

	Insert Into e2e_resultados Values ('15. /avisos solo administradores', 'OK', Replace(v_estado, E'\n', ' | '));
Exception
	When Others Then
		Insert Into e2e_resultados Values ('15. /avisos solo administradores', 'ERROR', SqlErrM);
End;
$$;

Reset Role;

Do $$
Begin
	If Not (Select avisos_activos From public.whatsapp_configuracion Where familia_id = (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID')) Then
		Update e2e_resultados Set Resultado = 'ERROR', Detalle = 'Los avisos no quedaron reanudados.' Where Prueba Like '15.%';
	End If;
End;
$$;

/*--------------------------------------------------------------------------------
17. guardar_configuracion_whatsapp rechaza claves desconocidas y rangos inválidos.
--------------------------------------------------------------------------------*/

Set Local Role authenticated;

Select set_config('request.jwt.claims', Json_Build_Object('sub', (Select Valor From e2e_contexto Where Clave = 'LILIANA_USUARIO_ID'), 'role', 'authenticated')::text, true);

Do $$
Declare
	v_error text;
Begin
	Begin
		Perform public.guardar_configuracion_whatsapp((Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID'), '{"avisos_activos": false}'::jsonb);
	Exception
		When Others Then
			v_error := SqlErrM;
	End;

	Insert Into e2e_contexto (Clave, Valor) Values ('ERROR_CONFIG_INTEGRANTE', Coalesce(v_error, 'aceptado'));
End;
$$;

Select set_config('request.jwt.claims', Json_Build_Object('sub', (Select Valor From e2e_contexto Where Clave = 'JHOSEP_USUARIO_ID'), 'role', 'authenticated')::text, true);

Do $$
Declare
	v_familia_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID');
	v_casos jsonb[] := Array[
		'{"clave_rara": true}',
		'{"dias_aviso_previo": [0]}',
		'{"dias_aviso_previo": [1, 2, 3, 4, 5, 6]}',
		'{"frecuencia_vencidos_dias": 16}',
		'{"dia_resumen": 7}',
		'{"avisos_activos": "si"}',
		'{"hora_inicio_envio": "25:00"}',
		'{"hora_inicio_envio": "22:00"}',
		'{"hora_resumen": "23:00"}',
		'{"updated_by": null}'
	]::jsonb[];
	v_caso jsonb;
	v_aceptados text[] := '{}';
	v_error text;
Begin
	Foreach v_caso In Array v_casos
	Loop
		v_error := Null;

		Begin
			Perform public.guardar_configuracion_whatsapp(v_familia_id, v_caso);
		Exception
			When Others Then
				v_error := SqlErrM;
		End;

		If v_error Is Null Then
			v_aceptados := v_aceptados || v_caso::text;
		End If;
	End Loop;

	If cardinality(v_aceptados) > 0 Then
		Raise Exception 'Configuraciones inválidas aceptadas: %', array_to_string(v_aceptados, ', ');
	End If;

	If (Select Valor From e2e_contexto Where Clave = 'ERROR_CONFIG_INTEGRANTE') <> 'Solo un administrador puede configurar los avisos de WhatsApp.' Then
		Raise Exception 'Integrante: %', (Select Valor From e2e_contexto Where Clave = 'ERROR_CONFIG_INTEGRANTE');
	End If;

	-- Ventana casi completa para que las pruebas de avisos no dependan de la hora de ejecución.
	Perform public.guardar_configuracion_whatsapp(
		v_familia_id,
		'{"hora_inicio_envio": "00:00", "hora_fin_envio": "23:59", "hora_pendientes_admin": "00:00", "dias_aviso_previo": [1, 3, 3]}'::jsonb
	);

	If (public.obtener_estado_whatsapp(v_familia_id) -> 'configuracion' -> 'diasAvisoPrevio') <> '[3, 1]'::jsonb Then
		Raise Exception 'dias_aviso_previo no se normalizó: %', public.obtener_estado_whatsapp(v_familia_id) -> 'configuracion';
	End If;

	Insert Into e2e_resultados Values ('17. Validación de configuración', 'OK', '10 configuraciones inválidas rechazadas; integrante sin permiso.');
Exception
	When Others Then
		Insert Into e2e_resultados Values ('17. Validación de configuración', 'ERROR', SqlErrM);
End;
$$;

/*--------------------------------------------------------------------------------
Extra. obtener_estado_whatsapp separa datos de administración.
--------------------------------------------------------------------------------*/

Do $$
Declare
	v_estado jsonb := public.obtener_estado_whatsapp((Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID'));
Begin
	If Not (v_estado ->> 'esAdmin')::boolean
		Or Not (v_estado -> 'grupo' ->> 'vinculado')::boolean
		Or Not (v_estado -> 'yo' ->> 'vinculado')::boolean
		Or jsonb_array_length(v_estado -> 'integrantes') <> 2
		Or v_estado -> 'configuracion' Is Null
		Or jsonb_typeof(v_estado -> 'configuracion') <> 'object'
	Then
		Raise Exception 'Estado de administrador inesperado: %', v_estado;
	End If;

	Insert Into e2e_contexto (Clave, Valor) Values ('ESTADO_ADMIN', 'OK');
Exception
	When Others Then
		Insert Into e2e_contexto (Clave, Valor) Values ('ESTADO_ADMIN', SqlErrM);
End;
$$;

Select set_config('request.jwt.claims', Json_Build_Object('sub', (Select Valor From e2e_contexto Where Clave = 'LILIANA_USUARIO_ID'), 'role', 'authenticated')::text, true);

Do $$
Declare
	v_estado jsonb := public.obtener_estado_whatsapp((Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID'));
Begin
	If (v_estado ->> 'esAdmin')::boolean
		Or jsonb_array_length(v_estado -> 'integrantes') <> 0
		Or jsonb_typeof(v_estado -> 'configuracion') <> 'null'
		Or (v_estado -> 'grupo' ->> 'codigo') Is Not Null
		Or Not (v_estado -> 'yo' ->> 'vinculado')::boolean
	Then
		Raise Exception 'Estado de integrante inesperado: %', v_estado;
	End If;

	If (Select Valor From e2e_contexto Where Clave = 'ESTADO_ADMIN') <> 'OK' Then
		Raise Exception '%', (Select Valor From e2e_contexto Where Clave = 'ESTADO_ADMIN');
	End If;

	Insert Into e2e_resultados Values ('31. Estado de WhatsApp por rol', 'OK', 'Administrador ve integrantes y configuración; integrante no.');
Exception
	When Others Then
		Insert Into e2e_resultados Values ('31. Estado de WhatsApp por rol', 'ERROR', SqlErrM);
End;
$$;

/*--------------------------------------------------------------------------------
18. POR_VENCER a 3 y 1 días, una sola vez aunque el job corra dos veces.
--------------------------------------------------------------------------------*/

Reset Role;

Do $$
Declare
	v_familia_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID');
	v_recibo_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'RECIBO_ID');
	v_hoy date := timezone('America/Lima', now())::date;
	v_cantidad integer;
	v_texto text;
	v_menciones text[];
Begin
	Update public.recibos Set fecha_vencimiento = v_hoy + 5, fecha_limite_aporte = v_hoy + 3 Where id = v_recibo_id;

	Perform app_private.whatsapp_generar_avisos_familia(v_familia_id);
	Perform app_private.whatsapp_generar_avisos_familia(v_familia_id);

	Select count(*), min(texto), min(menciones::text)::text[] Into v_cantidad, v_texto, v_menciones
	From public.avisos_whatsapp
	Where clave = 'POR_VENCER:' || v_recibo_id || ':' || to_char(v_hoy, 'YYYY-MM-DD');

	If v_cantidad <> 1
		Or v_texto Not Like '⏰ *Prueba WhatsApp E2E:* faltan 3 días para aportar (%)%'
		Or v_texto Not Like '%Total S/ 2.00 · Falta S/ 2.00%'
		Or v_texto Not Like '%@200000000000002 S/ 1.00%'
		Or Not ((Select Valor From e2e_contexto Where Clave = 'LILIANA_LID') = Any(v_menciones))
		Or Not ((Select Valor From e2e_contexto Where Clave = 'JHOSEP_PN') = Any(v_menciones))
	Then
		Raise Exception 'POR_VENCER a 3 días: cantidad %, texto %, menciones %', v_cantidad, v_texto, v_menciones;
	End If;

	Delete From public.avisos_whatsapp Where familia_id = v_familia_id And tipo = 'POR_VENCER';
	Update public.recibos Set fecha_limite_aporte = v_hoy + 2 Where id = v_recibo_id;
	Perform app_private.whatsapp_generar_avisos_familia(v_familia_id);

	If Exists (Select 1 From public.avisos_whatsapp Where familia_id = v_familia_id And tipo = 'POR_VENCER') Then
		Raise Exception 'Se generó POR_VENCER a 2 días, que no está configurado.';
	End If;

	Update public.recibos Set fecha_limite_aporte = v_hoy + 1 Where id = v_recibo_id;
	Perform app_private.whatsapp_generar_avisos_familia(v_familia_id);
	Perform app_private.whatsapp_generar_avisos_familia(v_familia_id);

	Select count(*), min(texto) Into v_cantidad, v_texto
	From public.avisos_whatsapp
	Where familia_id = v_familia_id And tipo = 'POR_VENCER';

	If v_cantidad <> 1 Or v_texto Not Like '%falta 1 día para aportar%' Then
		Raise Exception 'POR_VENCER a 1 día: cantidad %, texto %', v_cantidad, v_texto;
	End If;

	Insert Into e2e_resultados Values ('18. POR_VENCER a 3 y 1 días', 'OK', Replace(v_texto, E'\n', ' | '));
Exception
	When Others Then
		Insert Into e2e_resultados Values ('18. POR_VENCER a 3 y 1 días', 'ERROR', SqlErrM);
End;
$$;

/*--------------------------------------------------------------------------------
19. VENCE_HOY y VENCIDO siguen la frecuencia configurada.
--------------------------------------------------------------------------------*/

Do $$
Declare
	v_familia_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID');
	v_recibo_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'RECIBO_ID');
	v_hoy date := timezone('America/Lima', now())::date;
	v_texto text;
	v_fallas text[] := '{}';
Begin
	Delete From public.avisos_whatsapp Where familia_id = v_familia_id;
	Update public.recibos Set fecha_limite_aporte = v_hoy Where id = v_recibo_id;
	Perform app_private.whatsapp_generar_avisos_familia(v_familia_id);

	Select texto Into v_texto From public.avisos_whatsapp Where clave = 'VENCE_HOY:' || v_recibo_id;

	If v_texto Is Null Or v_texto Not Like '⏰ *Prueba WhatsApp E2E:* hoy es el último día para aportar%' Then
		v_fallas := v_fallas || ('VENCE_HOY: ' || Coalesce(v_texto, 'no generado'));
	End If;

	Delete From public.avisos_whatsapp Where familia_id = v_familia_id;
	Update public.recibos Set fecha_limite_aporte = v_hoy - 1 Where id = v_recibo_id;
	Perform app_private.whatsapp_generar_avisos_familia(v_familia_id);

	Select texto Into v_texto From public.avisos_whatsapp Where familia_id = v_familia_id And tipo = 'VENCIDO';

	If v_texto Is Null Or v_texto Not Like '%venció hace 1 día%' Or v_texto Not Like '%El recibo vence el %' Then
		v_fallas := v_fallas || ('VENCIDO día 1: ' || Coalesce(v_texto, 'no generado'));
	End If;

	Delete From public.avisos_whatsapp Where familia_id = v_familia_id;
	Update public.recibos Set fecha_limite_aporte = v_hoy - 2 Where id = v_recibo_id;
	Perform app_private.whatsapp_generar_avisos_familia(v_familia_id);

	If Exists (Select 1 From public.avisos_whatsapp Where familia_id = v_familia_id And tipo = 'VENCIDO') Then
		v_fallas := v_fallas || 'VENCIDO día 2 no debía generarse'::text;
	End If;

	Update public.recibos Set fecha_limite_aporte = v_hoy - 4 Where id = v_recibo_id;
	Perform app_private.whatsapp_generar_avisos_familia(v_familia_id);

	If Not Exists (Select 1 From public.avisos_whatsapp Where familia_id = v_familia_id And tipo = 'VENCIDO' And texto Like '%venció hace 4 días%') Then
		v_fallas := v_fallas || 'VENCIDO día 4 debía generarse con frecuencia 3'::text;
	End If;

	Delete From public.avisos_whatsapp Where familia_id = v_familia_id;
	Update public.whatsapp_configuracion Set frecuencia_vencidos_dias = 0 Where familia_id = v_familia_id;
	Perform app_private.whatsapp_generar_avisos_familia(v_familia_id);

	If Exists (Select 1 From public.avisos_whatsapp Where familia_id = v_familia_id And tipo = 'VENCIDO') Then
		v_fallas := v_fallas || 'Con frecuencia 0 solo se avisa el primer día'::text;
	End If;

	Update public.whatsapp_configuracion Set frecuencia_vencidos_dias = 3 Where familia_id = v_familia_id;
	Delete From public.avisos_whatsapp Where familia_id = v_familia_id;
	Update public.recibos Set fecha_limite_aporte = v_hoy + 3 Where id = v_recibo_id;

	If cardinality(v_fallas) > 0 Then
		Raise Exception '%', array_to_string(v_fallas, ' / ');
	End If;

	Insert Into e2e_resultados Values ('19. VENCE_HOY y VENCIDO con frecuencia', 'OK', 'Día límite, día 1, día 4 y frecuencia 0 correctos.');
Exception
	When Others Then
		Insert Into e2e_resultados Values ('19. VENCE_HOY y VENCIDO con frecuencia', 'ERROR', SqlErrM);
End;
$$;

/*--------------------------------------------------------------------------------
20. Recibo sin monto, con recaudación completa o anulado no genera recordatorios.
--------------------------------------------------------------------------------*/

Do $$
Declare
	v_familia_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID');
	v_recibo_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'RECIBO_ID');
	v_fallas text[] := '{}';
Begin
	Update public.recibos Set estado_recaudacion = 'COMPLETA' Where id = v_recibo_id;
	Perform app_private.whatsapp_generar_avisos_familia(v_familia_id);
	If Exists (Select 1 From public.avisos_whatsapp Where recibo_id = v_recibo_id And tipo In ('POR_VENCER', 'VENCE_HOY', 'VENCIDO')) Then
		v_fallas := v_fallas || 'recaudación completa'::text;
	End If;
	Update public.recibos Set estado_recaudacion = 'PENDIENTE' Where id = v_recibo_id;

	Update public.recibos Set estado = 'ANULADO' Where id = v_recibo_id;
	Perform app_private.whatsapp_generar_avisos_familia(v_familia_id);
	If Exists (Select 1 From public.avisos_whatsapp Where recibo_id = v_recibo_id And tipo In ('POR_VENCER', 'VENCE_HOY', 'VENCIDO')) Then
		v_fallas := v_fallas || 'recibo anulado'::text;
	End If;
	Update public.recibos Set estado = 'PENDIENTE' Where id = v_recibo_id;

	Update public.recibos Set monto_base = Null Where id = v_recibo_id;
	Perform app_private.whatsapp_generar_avisos_familia(v_familia_id);
	If Exists (Select 1 From public.avisos_whatsapp Where recibo_id = v_recibo_id And tipo In ('POR_VENCER', 'VENCE_HOY', 'VENCIDO')) Then
		v_fallas := v_fallas || 'recibo sin monto'::text;
	End If;
	Update public.recibos Set monto_base = 2.00 Where id = v_recibo_id;

	Perform app_private.whatsapp_generar_avisos_familia(v_familia_id);
	If Not Exists (Select 1 From public.avisos_whatsapp Where recibo_id = v_recibo_id And tipo = 'POR_VENCER') Then
		v_fallas := v_fallas || 'el recibo restaurado sí debía avisar'::text;
	End If;

	If cardinality(v_fallas) > 0 Then
		Raise Exception 'Generó recordatorios indebidos: %', array_to_string(v_fallas, ', ');
	End If;

	Insert Into e2e_resultados Values ('20. Sin recordatorios para recibos no elegibles', 'OK', 'Sin monto, completo y anulado excluidos.');
Exception
	When Others Then
		Insert Into e2e_resultados Values ('20. Sin recordatorios para recibos no elegibles', 'ERROR', SqlErrM);
End;
$$;

/*--------------------------------------------------------------------------------
21. MONTO_CONFIRMADO genera RECIBO_MONTO.
22. Eventos de más de 12 horas no generan avisos.
23. RECAUDACION_COMPLETA se genera una sola vez.
--------------------------------------------------------------------------------*/

Do $$
Declare
	v_familia_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID');
	v_recibo_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'RECIBO_ID');
	v_evento_id bigint;
	v_texto text;
Begin
	Perform app_private.registrar_evento_financiero(v_familia_id, 'RECIBO', v_recibo_id, 'MONTO_CONFIRMADO', '{}'::jsonb, Null);
	Select max(id) Into v_evento_id From public.eventos_financieros Where familia_id = v_familia_id And evento = 'MONTO_CONFIRMADO';

	Perform app_private.whatsapp_procesar_eventos();
	Perform app_private.whatsapp_procesar_eventos();

	Select texto Into v_texto From public.avisos_whatsapp Where clave = 'EVENTO:' || v_evento_id And tipo = 'RECIBO_MONTO';

	If v_texto Is Null
		Or v_texto Not Like '%*Llegó Prueba WhatsApp E2E:* S/ 2.00%'
		Or v_texto Not Like '%A cada uno le toca:%• Jhosep S/ 1.00%• Liliana S/ 1.00%'
	Then
		Raise Exception 'RECIBO_MONTO inesperado: %', Coalesce(v_texto, 'no generado');
	End If;

	Insert Into e2e_resultados Values ('21. MONTO_CONFIRMADO genera RECIBO_MONTO', 'OK', Replace(v_texto, E'\n', ' | '));
Exception
	When Others Then
		Insert Into e2e_resultados Values ('21. MONTO_CONFIRMADO genera RECIBO_MONTO', 'ERROR', SqlErrM);
End;
$$;

Do $$
Declare
	v_familia_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID');
	v_recibo_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'RECIBO_ID');
	v_evento_id bigint;
Begin
	Perform app_private.registrar_evento_financiero(v_familia_id, 'RECIBO', v_recibo_id, 'MONTO_CORREGIDO', '{}'::jsonb, Null);
	Select max(id) Into v_evento_id From public.eventos_financieros Where familia_id = v_familia_id And evento = 'MONTO_CORREGIDO';
	Update public.eventos_financieros Set created_at = now() - interval '13 hours' Where id = v_evento_id;

	Perform app_private.whatsapp_procesar_eventos();

	If Exists (Select 1 From public.avisos_whatsapp Where clave = 'EVENTO:' || v_evento_id) Then
		Raise Exception 'Se avisó un evento de hace 13 horas.';
	End If;

	If (Select ultimo_evento_id From public.whatsapp_sistema Where id = 1) < v_evento_id Then
		Raise Exception 'El cursor no avanzó sobre el evento antiguo.';
	End If;

	Insert Into e2e_resultados Values ('22. Eventos viejos no se avisan', 'OK', 'Evento de 13 horas descartado y cursor avanzado.');
Exception
	When Others Then
		Insert Into e2e_resultados Values ('22. Eventos viejos no se avisan', 'ERROR', SqlErrM);
End;
$$;

Do $$
Declare
	v_recibo_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'RECIBO_ID');
	v_cantidad integer;
Begin
	Update public.recibos Set estado_recaudacion = 'COMPLETA', updated_at = now() Where id = v_recibo_id;

	Perform app_private.whatsapp_procesar_eventos();
	Perform app_private.whatsapp_procesar_eventos();

	Select count(*) Into v_cantidad From public.avisos_whatsapp Where clave = 'RECAUDACION_COMPLETA:' || v_recibo_id;

	Update public.recibos Set estado_recaudacion = 'PENDIENTE' Where id = v_recibo_id;

	If v_cantidad <> 1 Then
		Raise Exception 'Se esperaba un aviso de recaudación completa y hay %.', v_cantidad;
	End If;

	Insert Into e2e_resultados Values ('23. RECAUDACION_COMPLETA una vez', 'OK', 'Un solo aviso tras dos ejecuciones.');
Exception
	When Others Then
		Insert Into e2e_resultados Values ('23. RECAUDACION_COMPLETA una vez', 'ERROR', SqlErrM);
End;
$$;

/*--------------------------------------------------------------------------------
24. PENDIENTES_ADMIN solo con total mayor que 0.
--------------------------------------------------------------------------------*/

Do $$
Declare
	v_familia_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID');
Begin
	Delete From public.avisos_whatsapp Where familia_id = v_familia_id And tipo = 'PENDIENTES_ADMIN';
	Perform app_private.whatsapp_generar_avisos_familia(v_familia_id);

	Insert Into e2e_contexto (Clave, Valor)
	Values ('PENDIENTES_ADMIN_SIN_TAREAS', (Select count(*)::text From public.avisos_whatsapp Where familia_id = v_familia_id And tipo = 'PENDIENTES_ADMIN'));
End;
$$;

Set Local Role authenticated;

Select set_config('request.jwt.claims', Json_Build_Object('sub', (Select Valor From e2e_contexto Where Clave = 'LILIANA_USUARIO_ID'), 'role', 'authenticated')::text, true);

Do $$
Begin
	Insert Into e2e_contexto (Clave, Valor)
	Values ('APORTE_LILIANA_ID', public.registrar_aporte((Select Valor::uuid From e2e_contexto Where Clave = 'CUOTA_LILIANA_ID'), 1.00, 'YAPE', 'E2E-WHATSAPP', Null)::text);
End;
$$;

Reset Role;

Do $$
Declare
	v_familia_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID');
	v_texto text;
	v_menciones text[];
Begin
	If (Select Valor From e2e_contexto Where Clave = 'PENDIENTES_ADMIN_SIN_TAREAS') <> '0' Then
		Raise Exception 'Se generó PENDIENTES_ADMIN sin tareas pendientes.';
	End If;

	Perform app_private.whatsapp_generar_avisos_familia(v_familia_id);

	Select texto, menciones Into v_texto, v_menciones
	From public.avisos_whatsapp
	Where familia_id = v_familia_id And tipo = 'PENDIENTES_ADMIN';

	If v_texto Is Null
		Or v_texto Not Like '📋 *Pendientes de administración*%• 1 pago por validar (@51900000001)%'
		Or Not ((Select Valor From e2e_contexto Where Clave = 'JHOSEP_PN') = Any(v_menciones))
	Then
		Raise Exception 'PENDIENTES_ADMIN inesperado: % / %', Coalesce(v_texto, 'no generado'), v_menciones;
	End If;

	Insert Into e2e_resultados Values ('24. PENDIENTES_ADMIN solo con tareas', 'OK', Replace(v_texto, E'\n', ' | '));
Exception
	When Others Then
		Insert Into e2e_resultados Values ('24. PENDIENTES_ADMIN solo con tareas', 'ERROR', SqlErrM);
End;
$$;

/*--------------------------------------------------------------------------------
Extra. Pagos enviados y confirmados (aporte y pago familiar), y consultas con validación.
--------------------------------------------------------------------------------*/

Do $$
Declare
	v_familia_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID');
	v_aporte_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'APORTE_LILIANA_ID');
	v_pago_id uuid;
	v_enviado_aporte text;
	v_enviado_pago text;
	v_confirmado_pago text;
	v_menciones text[];
Begin
	Perform app_private.whatsapp_procesar_eventos();

	Select texto Into v_enviado_aporte From public.avisos_whatsapp Where clave = 'PAGO_ENVIADO:' || v_aporte_id;

	Insert Into public.pagos_familiares (
		familia_id, pagador_miembro_id, pagador_usuario_id, pagador_nombre_snapshot, destino,
		responsable_receptor_miembro_id, receptor_nombre_snapshot, metodo, receptor_titular_snapshot,
		monto_total, estado, enviado_at, creado_por
	)
	Values (
		v_familia_id,
		(Select Valor::uuid From e2e_contexto Where Clave = 'JHOSEP_MIEMBRO_ID'),
		(Select Valor::uuid From e2e_contexto Where Clave = 'JHOSEP_USUARIO_ID'),
		'Jhosep',
		'FONDO_FAMILIAR',
		(Select Valor::uuid From e2e_contexto Where Clave = 'JHOSEP_MIEMBRO_ID'),
		'Fondo familiar · E2E',
		'YAPE',
		'Jhosep',
		1.00,
		'POR_VALIDAR',
		now(),
		(Select Valor::uuid From e2e_contexto Where Clave = 'JHOSEP_USUARIO_ID')
	)
	Returning id Into v_pago_id;

	Insert Into public.pago_asignaciones (pago_id, cuota_id, recibo_id, monto)
	Select v_pago_id, q.id, q.recibo_id, 1.00
	From public.cuotas q
	Where q.recibo_id = (Select Valor::uuid From e2e_contexto Where Clave = 'RECIBO_ID')
		And q.usuario_id = (Select Valor::uuid From e2e_contexto Where Clave = 'JHOSEP_USUARIO_ID');

	Perform app_private.whatsapp_procesar_eventos();

	Select texto, menciones Into v_enviado_pago, v_menciones From public.avisos_whatsapp Where clave = 'PAGO_ENVIADO:' || v_pago_id;

	Update public.pagos_familiares Set estado = 'CONFIRMADO', validado_at = now() Where id = v_pago_id;
	Perform app_private.whatsapp_procesar_eventos();

	Select texto Into v_confirmado_pago From public.avisos_whatsapp Where clave = 'PAGO_CONFIRMADO:' || v_pago_id;

	Update public.pagos_familiares Set estado = 'POR_VALIDAR', validado_at = Null Where id = v_pago_id;
	Insert Into e2e_contexto (Clave, Valor) Values ('PAGO_FAMILIAR_ID', v_pago_id::text);

	If v_enviado_aporte Is Null
		Or v_enviado_aporte Not Like '📥 Liliana registró un pago de S/ 1.00 (Prueba WhatsApp E2E).%@51900000001, revísalo en FamiliaHub: {APP_URL}/pagos'
	Then
		Raise Exception 'PAGO_ENVIADO de aporte: %', Coalesce(v_enviado_aporte, 'no generado');
	End If;

	If v_enviado_pago Is Null
		Or v_enviado_pago Not Like '📥 Jhosep registró un pago de S/ 1.00 (Prueba WhatsApp E2E).%'
		Or Not ((Select Valor From e2e_contexto Where Clave = 'JHOSEP_PN') = Any(v_menciones))
	Then
		Raise Exception 'PAGO_ENVIADO de pago familiar: % / %', Coalesce(v_enviado_pago, 'no generado'), v_menciones;
	End If;

	If v_confirmado_pago Is Distinct From '✅ *Jhosep* pagó S/ 1.00 · Prueba WhatsApp E2E' Then
		Raise Exception 'PAGO_CONFIRMADO: %', Coalesce(v_confirmado_pago, 'no generado');
	End If;

	Insert Into e2e_resultados Values ('32. PAGO_ENVIADO y PAGO_CONFIRMADO', 'OK', Replace(v_enviado_aporte, E'\n', ' | ') || ' // ' || v_confirmado_pago);
Exception
	When Others Then
		Insert Into e2e_resultados Values ('32. PAGO_ENVIADO y PAGO_CONFIRMADO', 'ERROR', SqlErrM);
End;
$$;

Set Local Role service_role;

Do $$
Declare
	v_porvalidar text;
	v_deuda text;
	v_recibo text;
	v_no_encontrado text;
	v_vence text;
	v_recibos text;
	v_pagar text;
	v_desconocido text;
	v_ayuda text;
Begin
	v_porvalidar := public.whatsapp_procesar_comando((Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'), Array[(Select Valor From e2e_contexto Where Clave = 'JHOSEP_PN')], 'porvalidar', '') ->> 'texto';
	v_deuda := public.whatsapp_procesar_comando((Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'), Array[(Select Valor From e2e_contexto Where Clave = 'LILIANA_LID')], 'deuda', '') ->> 'texto';
	v_recibo := public.whatsapp_procesar_comando((Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'), Array[(Select Valor From e2e_contexto Where Clave = 'LILIANA_LID')], 'recibo', 'PRUEBA whatsapp') ->> 'texto';
	v_no_encontrado := public.whatsapp_procesar_comando((Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'), Array['1@lid'], 'recibo', 'cable') ->> 'texto';
	v_vence := public.whatsapp_procesar_comando((Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'), Array['1@lid'], 'vence', '') ->> 'texto';
	v_recibos := public.whatsapp_procesar_comando((Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'), Array['1@lid'], 'recibos', '') ->> 'texto';
	v_pagar := public.whatsapp_procesar_comando((Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'), Array['1@lid'], 'pagar', '') ->> 'texto';
	v_desconocido := public.whatsapp_procesar_comando((Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'), Array['1@lid'], 'desconocido', '') ->> 'texto';
	v_ayuda := public.whatsapp_procesar_comando((Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'), Array['1@lid'], 'ayuda', '') ->> 'texto';

	If v_porvalidar Not Like '📥 *Pagos por validar*%• Liliana S/ 1.00 · hoy%• Jhosep S/ 1.00 · hoy%Valídalos en {APP_URL}/pagos'
		And v_porvalidar Not Like '📥 *Pagos por validar*%• Jhosep S/ 1.00 · hoy%• Liliana S/ 1.00 · hoy%Valídalos en {APP_URL}/pagos'
	Then
		Raise Exception '/porvalidar: %', v_porvalidar;
	End If;

	If v_deuda Not Like 'Liliana, debes S/ 1.00 este mes:%En validación: Prueba WhatsApp E2E S/ 1.00%' Then
		Raise Exception '/deuda con validación: %', v_deuda;
	End If;

	If v_recibo Not Like '%*Prueba WhatsApp E2E* — S/ 2.00%Estado: por recaudar%• Liliana S/ 1.00 · en validación%' Then
		Raise Exception '/recibo: %', v_recibo;
	End If;

	If v_no_encontrado Is Distinct From 'No encontré "cable" este mes. Recibos: Prueba WhatsApp E2E.' Then
		Raise Exception '/recibo sin coincidencia: %', v_no_encontrado;
	End If;

	If v_vence Not Like '⏰ Próximos 7 días:%• Prueba WhatsApp E2E: falta S/ 2.00 (%)' Then
		Raise Exception '/vence: %', v_vence;
	End If;

	If v_recibos Not Like '🗓️ *%*%• Prueba WhatsApp E2E: S/ 2.00 · por recaudar · %' Then
		Raise Exception '/recibos: %', v_recibos;
	End If;

	If v_pagar Is Distinct From E'Para pagar entra a {APP_URL}/pagar\nAhí ves a quién pagar y subes tu comprobante.' Then
		Raise Exception '/pagar sin vínculo: %', v_pagar;
	End If;

	If v_desconocido Is Distinct From 'No conozco ese comando. Escribe /ayuda.' Or v_ayuda Not Like '🏠 *FamiliaHub* — esto puedo hacer%' Then
		Raise Exception 'desconocido: %, ayuda: %', v_desconocido, v_ayuda;
	End If;

	Insert Into e2e_resultados Values ('33. Consultas con pagos en validación', 'OK', Replace(v_recibo, E'\n', ' | '));
Exception
	When Others Then
		Insert Into e2e_resultados Values ('33. Consultas con pagos en validación', 'ERROR', SqlErrM);
End;
$$;

/*--------------------------------------------------------------------------------
25. tomar_avisos no devuelve avisos fuera de la ventana horaria.
26. tomar_avisos expira avisos vencidos y avisos de recibos que ya no cumplen.
--------------------------------------------------------------------------------*/

Reset Role;

Do $$
Declare
	v_familia_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID');
	v_hora time := timezone('America/Lima', now())::time;
Begin
	If v_hora < '12:00' Then
		Update public.whatsapp_configuracion
		Set hora_inicio_envio = '13:00', hora_fin_envio = '14:00', hora_pendientes_admin = '13:00', hora_resumen = '13:00'
		Where familia_id = v_familia_id;
	Else
		Update public.whatsapp_configuracion
		Set hora_inicio_envio = '01:00', hora_fin_envio = '02:00', hora_pendientes_admin = '01:00', hora_resumen = '01:00'
		Where familia_id = v_familia_id;
	End If;
End;
$$;

Set Local Role service_role;

Do $$
Declare
	v_avisos jsonb;
Begin
	v_avisos := public.whatsapp_tomar_avisos(5::smallint);

	Insert Into e2e_contexto (Clave, Valor) Values ('TOMADOS_FUERA_VENTANA', jsonb_array_length(v_avisos)::text);
End;
$$;

Reset Role;

Update public.whatsapp_configuracion
Set hora_inicio_envio = '00:00', hora_fin_envio = '23:59', hora_pendientes_admin = '00:00', hora_resumen = '19:00'
Where familia_id = (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID');

Do $$
Declare
	v_familia_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID');
	v_recibo_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'RECIBO_ID');
Begin
	Insert Into public.avisos_whatsapp (familia_id, tipo, clave, texto, expira_at)
	Values (v_familia_id, 'RESUMEN_SEMANAL', 'E2E:VENCIDO', 'Aviso vencido de prueba', now() - interval '1 minute');

	Delete From public.avisos_whatsapp Where familia_id = v_familia_id And tipo = 'POR_VENCER';
	Update public.recibos Set fecha_limite_aporte = timezone('America/Lima', now())::date + 3 Where id = v_recibo_id;
	Perform app_private.whatsapp_generar_avisos_familia(v_familia_id);
	Update public.recibos Set estado_recaudacion = 'COMPLETA' Where id = v_recibo_id;
End;
$$;

Set Local Role service_role;

Do $$
Declare
	v_avisos jsonb;
Begin
	v_avisos := public.whatsapp_tomar_avisos(20::smallint);

	Insert Into e2e_contexto (Clave, Valor) Values ('TOMADOS_DENTRO_VENTANA', v_avisos::text);
End;
$$;

Reset Role;

Do $$
Declare
	v_familia_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID');
	v_tomados jsonb := (Select Valor::jsonb From e2e_contexto Where Clave = 'TOMADOS_DENTRO_VENTANA');
Begin
	Update public.recibos Set estado_recaudacion = 'PENDIENTE' Where id = (Select Valor::uuid From e2e_contexto Where Clave = 'RECIBO_ID');

	If (Select Valor From e2e_contexto Where Clave = 'TOMADOS_FUERA_VENTANA') <> '0' Then
		Insert Into e2e_resultados Values ('25. Ventana horaria al tomar avisos', 'ERROR', 'Se tomaron avisos fuera de la ventana.');
	ElsIf jsonb_array_length(v_tomados) = 0
		Or v_tomados -> 0 ->> 'grupoId' <> (Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA')
		Or Exists (Select 1 From public.avisos_whatsapp Where familia_id = v_familia_id And estado = 'PENDIENTE' And id::text = Any(Array(Select jsonb_array_elements(v_tomados) ->> 'id')) And bloqueado_hasta Is Null)
	Then
		Insert Into e2e_resultados Values ('25. Ventana horaria al tomar avisos', 'ERROR', 'Dentro de la ventana no se tomaron ni reservaron avisos: ' || v_tomados::text);
	Else
		Insert Into e2e_resultados Values ('25. Ventana horaria al tomar avisos', 'OK', 'Fuera: 0 · dentro: ' || jsonb_array_length(v_tomados) || ' reservados 5 minutos.');
	End If;

	If (Select estado From public.avisos_whatsapp Where clave = 'E2E:VENCIDO') <> 'EXPIRADO'
		Or Exists (Select 1 From public.avisos_whatsapp Where familia_id = v_familia_id And tipo = 'POR_VENCER' And estado <> 'EXPIRADO')
		Or v_tomados::text Like '%Aviso vencido de prueba%'
		Or v_tomados::text Like '%faltan 3 días%'
	Then
		Insert Into e2e_resultados Values ('26. Expiración al tomar avisos', 'ERROR', 'Se entregó o no se expiró un aviso vencido o un recordatorio que ya no aplica.');
	Else
		Insert Into e2e_resultados Values ('26. Expiración al tomar avisos', 'OK', 'Aviso vencido y recordatorio de recibo completo expirados.');
	End If;
End;
$$;

/*--------------------------------------------------------------------------------
27. marcar_aviso aplica reintentos y pasa a ERROR al tercer fallo.
--------------------------------------------------------------------------------*/

Set Local Role service_role;

Do $$
Declare
	v_tomados jsonb := (Select Valor::jsonb From e2e_contexto Where Clave = 'TOMADOS_DENTRO_VENTANA');
	v_fallido uuid := (v_tomados -> 0 ->> 'id')::uuid;
	v_enviado uuid := (v_tomados -> 1 ->> 'id')::uuid;
Begin
	Perform public.whatsapp_marcar_aviso(v_fallido, false, 'Fallo de prueba 1');
	Insert Into e2e_contexto (Clave, Valor) Values ('AVISO_FALLIDO', v_fallido::text);
	Insert Into e2e_contexto (Clave, Valor)
	Select 'AVISO_PRIMER_FALLO', estado::text || ':' || intentos::text || ':' || (bloqueado_hasta Between now() + interval '119 seconds' And now() + interval '121 seconds')::text
	From public.avisos_whatsapp
	Where id = v_fallido;
	Perform public.whatsapp_marcar_aviso(v_fallido, false, 'Fallo de prueba 2');
	Perform public.whatsapp_marcar_aviso(v_fallido, false, 'Fallo de prueba 3');
	Perform public.whatsapp_marcar_aviso(v_fallido, false, 'Fallo de prueba 4');

	If v_enviado Is Not Null Then
		Perform public.whatsapp_marcar_aviso(v_enviado, true, Null);
		Perform public.whatsapp_marcar_aviso(v_enviado, false, 'No debe revertir un envío');
		Insert Into e2e_contexto (Clave, Valor) Values ('AVISO_ENVIADO', v_enviado::text);
	End If;
End;
$$;

Reset Role;

Do $$
Declare
	v_fallido public.avisos_whatsapp%rowtype;
	v_enviado public.avisos_whatsapp%rowtype;
Begin
	Select * Into v_fallido From public.avisos_whatsapp Where id = (Select Valor::uuid From e2e_contexto Where Clave = 'AVISO_FALLIDO');
	Select * Into v_enviado From public.avisos_whatsapp Where id = (Select Valor::uuid From e2e_contexto Where Clave = 'AVISO_ENVIADO');

	If (Select Valor From e2e_contexto Where Clave = 'AVISO_PRIMER_FALLO') <> 'PENDIENTE:1:true' Then
		Raise Exception 'Tras el primer fallo: %', (Select Valor From e2e_contexto Where Clave = 'AVISO_PRIMER_FALLO');
	End If;

	If v_fallido.estado <> 'ERROR' Or v_fallido.intentos <> 3 Or v_fallido.error <> 'Fallo de prueba 3' Then
		Raise Exception 'Aviso fallido: estado %, intentos %, error %', v_fallido.estado, v_fallido.intentos, v_fallido.error;
	End If;

	If v_enviado.id Is Not Null And (v_enviado.estado <> 'ENVIADO' Or v_enviado.enviado_at Is Null) Then
		Raise Exception 'Aviso enviado: estado %', v_enviado.estado;
	End If;

	Insert Into e2e_resultados Values ('27. Reintentos de marcar_aviso', 'OK', 'Dos reintentos, ERROR al tercero; un envío confirmado no se revierte.');
Exception
	When Others Then
		Insert Into e2e_resultados Values ('27. Reintentos de marcar_aviso', 'ERROR', SqlErrM);
End;
$$;

/*--------------------------------------------------------------------------------
28. Avisos pausados no se generan.
--------------------------------------------------------------------------------*/

Do $$
Declare
	v_familia_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID');
	v_antes integer;
	v_despues integer;
Begin
	Update public.whatsapp_configuracion Set avisos_activos = false Where familia_id = v_familia_id;
	Delete From public.avisos_whatsapp Where familia_id = v_familia_id And tipo In ('POR_VENCER', 'PENDIENTES_ADMIN');

	Select count(*) Into v_antes From public.avisos_whatsapp Where familia_id = v_familia_id;

	Perform app_private.whatsapp_generar_avisos_familia(v_familia_id);
	Perform app_private.registrar_evento_financiero(v_familia_id, 'RECIBO', (Select Valor::uuid From e2e_contexto Where Clave = 'RECIBO_ID'), 'MONTO_CONFIRMADO', '{}'::jsonb, Null);
	Perform app_private.whatsapp_procesar_eventos();
	Perform app_private.whatsapp_encolar(v_familia_id, 'RESUMEN_SEMANAL', 'E2E:PAUSADO', Null, 'No debe guardarse', '{}', now() + interval '1 hour');

	Select count(*) Into v_despues From public.avisos_whatsapp Where familia_id = v_familia_id;

	Update public.whatsapp_configuracion Set avisos_activos = true Where familia_id = v_familia_id;

	If v_despues <> v_antes Then
		Raise Exception 'Con avisos pausados se generaron % avisos.', v_despues - v_antes;
	End If;

	Insert Into e2e_resultados Values ('28. Avisos pausados', 'OK', 'Jobs y encolado no generan avisos mientras están pausados.');
Exception
	When Others Then
		Insert Into e2e_resultados Values ('28. Avisos pausados', 'ERROR', SqlErrM);
End;
$$;

/*--------------------------------------------------------------------------------
29. grupo_salida desvincula y expira pendientes.
Extra. Al pasar a INACTIVO se elimina el vínculo del integrante.
--------------------------------------------------------------------------------*/

Do $$
Begin
	Perform app_private.whatsapp_generar_avisos_familia((Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID'));
End;
$$;

Set Local Role service_role;

Select public.whatsapp_grupo_salida((Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'));
Select public.whatsapp_heartbeat('e2e-1.0.0');

Do $$
Declare
	v_respuesta jsonb;
Begin
	v_respuesta := public.whatsapp_procesar_comando(
		(Select Valor From e2e_contexto Where Clave = 'GRUPO_FAMILIA'),
		Array[(Select Valor From e2e_contexto Where Clave = 'JHOSEP_PN')],
		'ayuda',
		''
	);

	Insert Into e2e_contexto (Clave, Valor) Values ('RESPUESTA_TRAS_SALIDA', Coalesce(v_respuesta ->> 'grupoVinculado', 'true'));
End;
$$;

Reset Role;

Do $$
Declare
	v_familia_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID');
Begin
	If Exists (Select 1 From public.whatsapp_vinculos Where familia_id = v_familia_id And tipo = 'GRUPO')
		Or Exists (Select 1 From public.avisos_whatsapp Where familia_id = v_familia_id And estado = 'PENDIENTE')
		Or Not Exists (Select 1 From public.avisos_whatsapp Where familia_id = v_familia_id And estado = 'EXPIRADO')
		Or (Select Valor From e2e_contexto Where Clave = 'RESPUESTA_TRAS_SALIDA') <> 'false'
	Then
		Raise Exception 'El grupo sigue vinculado o quedaron avisos pendientes.';
	End If;

	If (Select version_bot From public.whatsapp_sistema Where id = 1) <> 'e2e-1.0.0'
		Or (Select ultimo_heartbeat_at From public.whatsapp_sistema Where id = 1) Is Null
	Then
		Raise Exception 'El heartbeat no se registró.';
	End If;

	Insert Into e2e_resultados Values ('29. grupo_salida', 'OK', 'Grupo desvinculado, avisos expirados y heartbeat registrado.');
Exception
	When Others Then
		Insert Into e2e_resultados Values ('29. grupo_salida', 'ERROR', SqlErrM);
End;
$$;

Do $$
Declare
	v_miembro_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'LILIANA_MIEMBRO_ID');
Begin
	Update public.miembros_familia Set estado = 'INACTIVO' Where id = v_miembro_id;

	If Exists (Select 1 From public.whatsapp_vinculos Where miembro_id = v_miembro_id And whatsapp_id Is Not Null) Then
		Raise Exception 'El vínculo de un integrante inactivo sigue vigente.';
	End If;

	Update public.miembros_familia Set estado = 'ACTIVO' Where id = v_miembro_id;

	Insert Into e2e_resultados Values ('34. Integrante inactivo pierde el vínculo', 'OK', 'Al volver deberá vincularse de nuevo.');
Exception
	When Others Then
		Insert Into e2e_resultados Values ('34. Integrante inactivo pierde el vínculo', 'ERROR', SqlErrM);
End;
$$;

Select
	Prueba,
	Resultado,
	Detalle
From e2e_resultados
Order By Prueba;

Rollback;
