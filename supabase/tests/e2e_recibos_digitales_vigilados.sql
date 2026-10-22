/*================================================================================
Objetivo:
	Validar los recibos digitales con suministro oculto ("****6543") y el aviso único
	cuando el recibo digital de un servicio no llega a tiempo.

Requisitos:
	Los mismos de e2e_recibos_digitales.sql. Ejecutar como postgres. Termina con Rollback.
================================================================================*/

Begin;

Create Temp Table e2e_contexto (Clave varchar(60) Primary Key, Valor text Not Null) On Commit Drop;
Create Temp Table e2e_resultados (Prueba varchar(120) Not Null, Resultado varchar(20) Not Null, Detalle text Null) On Commit Drop;
Grant Select, Insert, Update, Delete On e2e_contexto, e2e_resultados To authenticated, service_role;

Do $$
Begin
	Insert Into e2e_contexto (Clave, Valor)
	Select 'JHOSEP_USUARIO_ID', id::text From auth.users Where Lower(email) = Lower(Current_Setting('familiahub.e2e_jhosep_email', true)) And email_confirmed_at Is Not Null;
	If Not Found Then Raise Exception 'Configura familiahub.e2e_jhosep_email con una cuenta confirmada.'; End If;
End;
$$;

Create Or Replace Function pg_temp.ctx(p_clave text) Returns uuid Language sql As $$
	Select Valor::uuid From e2e_contexto Where Clave = p_clave;
$$;
Grant Execute On Function pg_temp.ctx(text) To authenticated, service_role;

Set Local Role authenticated;
Select set_config('request.jwt.claims', Json_Build_Object('sub', (Select Valor From e2e_contexto Where Clave = 'JHOSEP_USUARIO_ID'), 'role', 'authenticated')::text, true);

Do $$
Declare
	v_familia_id uuid := public.crear_familia_inicial('FamiliaHub Recibos Vigilados');
	v_miembro_id uuid;
	v_servicio record;
	v_concepto_id uuid;
Begin
	Insert Into e2e_contexto Values ('FAMILIA_ID', v_familia_id::text);
	Select id Into v_miembro_id From public.miembros_familia Where familia_id = v_familia_id;

	For v_servicio In
		Select * From (Values ('LUZ', 'LUZ_DEL_SUR', 'Luz', '1876543'), ('AGUA', 'SEDAPAL', 'Agua', '2345678'), ('LUZ2', 'LUZ_DEL_SUR', 'Luz del depa', '9996543'))
			As s(plantilla, proveedor, nombre, suministro)
	Loop
		v_concepto_id := public.guardar_concepto_servicio_fase6(
			Null, v_familia_id, (Select id From public.categorias Where familia_id = v_familia_id And nombre = 'Servicios'),
			(Select id From public.proveedores Where codigo = v_servicio.proveedor),
			(Select id From public.plantillas_servicio Where codigo = Case When v_servicio.plantilla = 'LUZ2' Then 'LUZ' Else v_servicio.plantilla End),
			v_servicio.nombre, 'MENSUAL', 'MANUAL', Null, 'PROVEEDOR', Null::smallint, 'IGUAL', Null, true,
			Jsonb_Build_Object(
				'tipo_identificador_id', (Select t.id From public.tipos_identificador_proveedor t Join public.proveedores p On p.id = t.proveedor_id Where p.codigo = v_servicio.proveedor Order By t.orden Limit 1),
				'identificador_valor', v_servicio.suministro
			),
			Jsonb_Build_Array(Jsonb_Build_Object('miembro_id', v_miembro_id, 'modalidad', 'IGUAL', 'valor', Null)),
			(timezone('America/Lima', now()))::date, 3::smallint
		);
		Insert Into e2e_contexto Values ('CONCEPTO_' || v_servicio.plantilla, v_concepto_id::text);
		Insert Into e2e_contexto Select 'RECIBO_' || v_servicio.plantilla, id::text From public.recibos Where concepto_id = v_concepto_id;
	End Loop;

	-- "Luz del depa" se pausa: así "*6543" solo coincide con un servicio activo en la prueba 01.
	Perform public.cambiar_estado_concepto(pg_temp.ctx('CONCEPTO_LUZ2'), false);
End;
$$;

Reset Role;

-- Grupo de WhatsApp vinculado y avisos activos todo el día.
Insert Into public.whatsapp_vinculos (familia_id, tipo, whatsapp_id, vinculado_at) Values (pg_temp.ctx('FAMILIA_ID'), 'GRUPO', '120363000000888001@g.us', now());
Insert Into public.whatsapp_configuracion (familia_id, hora_inicio_envio, hora_fin_envio) Values (pg_temp.ctx('FAMILIA_ID'), '00:00', '23:59')
On Conflict (familia_id) Do Update Set hora_inicio_envio = '00:00', hora_fin_envio = '23:59', avisos_activos = true;

Set Local Role service_role;

-- 01. Suministro oculto que coincide con un solo servicio activo: se confirma.
Do $$
Declare
	v_resultado jsonb := public.registrar_recibo_digital('vig-1', 'LUZ_DEL_SUR', Array['*6543'], 120.00, (timezone('America/Lima', now()))::date + 8);
Begin
	Insert Into e2e_resultados Values ('01. Suministro oculto se reconoce',
		Case When v_resultado ->> 'estado' = 'CONFIRMADO' And (v_resultado ->> 'reciboId')::uuid = pg_temp.ctx('RECIBO_LUZ') Then 'OK' Else 'ERROR' End, v_resultado::text);
End;
$$;

-- 02. Oculto con menos de 4 cifras: no alcanza para identificar el servicio.
Do $$
Begin
	Perform public.registrar_recibo_digital('vig-2', 'LUZ_DEL_SUR', Array['*543'], 120.00, (timezone('America/Lima', now()))::date + 8);
	Insert Into e2e_resultados Values ('02. Oculto demasiado corto', 'ERROR', 'Se aceptó');
Exception When Others Then
	Insert Into e2e_resultados Values ('02. Oculto demasiado corto', Case When SqlErrM = 'Falta el número de suministro.' Then 'OK' Else 'ERROR' End, SqlErrM);
End;
$$;

-- 03. Oculto que coincide con dos servicios activos: queda para revisar.
Reset Role;
Update public.conceptos_pago Set activo = true Where id = pg_temp.ctx('CONCEPTO_LUZ2');
Set Local Role service_role;

Do $$
Declare
	v_resultado jsonb := public.registrar_recibo_digital('vig-3', 'LUZ_DEL_SUR', Array['*6543'], 99.00, (timezone('America/Lima', now()))::date + 8);
Begin
	Insert Into e2e_resultados Values ('03. Oculto ambiguo se revisa',
		Case When v_resultado ->> 'estado' = 'REVISAR' And v_resultado ->> 'detalle' Like '%más de un servicio%' Then 'OK' Else 'ERROR' End, v_resultado::text);
End;
$$;

-- 04. Agua no tiene recibo digital: se avisa una sola vez cuando ya debería haber llegado.
--     El recibo del mes pasado venció el día 20, así que este mes se espera desde el 15.
Reset Role;

Do $$
Declare
	v_familia_id uuid := pg_temp.ctx('FAMILIA_ID');
	v_mes_anterior date := (date_trunc('month', timezone('America/Lima', now())) - interval '1 month')::date;
	v_periodo_id uuid;
Begin
	Insert Into public.periodos (familia_id, anio, mes, estado)
	Values (v_familia_id, Extract(Year From v_mes_anterior)::smallint, Extract(Month From v_mes_anterior)::smallint, 'ABIERTO')
	On Conflict (familia_id, anio, mes) Do Nothing;
	Select id Into v_periodo_id From public.periodos Where familia_id = v_familia_id And anio = Extract(Year From v_mes_anterior) And mes = Extract(Month From v_mes_anterior);

	Insert Into public.recibos (
		familia_id, periodo_id, concepto_id, nombre_concepto, categoria_nombre, proveedor_nombre, tipo_servicio,
		frecuencia, metodo_obtencion, tipo_vencimiento, tipo_distribucion, dias_anticipacion_aporte,
		monto_base, fecha_vencimiento, estado, monto_confirmado_at
	)
	Values (v_familia_id, v_periodo_id, pg_temp.ctx('CONCEPTO_AGUA'), 'Agua', 'Servicios', 'SEDAPAL', 'AGUA',
		'MENSUAL', 'MANUAL', 'PROVEEDOR', 'IGUAL', 3, 50.00, v_mes_anterior + 19, 'PENDIENTE', now() - interval '30 days');
End;
$$;

Do $$
Declare
	v_hoy date := (timezone('America/Lima', now()))::date;
	v_recibo public.recibos%rowtype;
	v_desde date;
	v_avisos integer;
	v_texto text;
Begin
	Select * Into v_recibo From public.recibos Where id = pg_temp.ctx('RECIBO_AGUA');
	v_desde := app_private.recibo_digital_esperado_desde(v_recibo);

	Perform app_private.recibos_digitales_vigilar();
	Perform app_private.recibos_digitales_vigilar();
	Perform app_private.recibos_digitales_vigilar();

	Select Count(*), Max(texto) Into v_avisos, v_texto From public.avisos_whatsapp Where clave = 'RECIBO_DIGITAL_FALTA:' || v_recibo.id;

	Insert Into e2e_resultados Values ('04. Aviso único si no llega',
		Case
			When v_hoy >= v_desde And v_avisos = 1 And v_texto Like '📭 *Agua:* el recibo digital de SEDAPAL aún no llega (suministro 2345678).%' Then 'OK'
			When v_hoy < v_desde And v_avisos = 0 Then 'OK'
			Else 'ERROR'
		End,
		Format('Se espera desde el %s · %s aviso(s)', to_char(v_desde, 'DD/MM'), v_avisos));
End;
$$;

-- 05. Luz ya llegó (lectura confirmada) y Luz del depa tiene una lectura para revisar: no se avisa de ninguno.
Do $$
Declare
	v_avisos integer := (Select Count(*) From public.avisos_whatsapp Where clave In ('RECIBO_DIGITAL_FALTA:' || pg_temp.ctx('RECIBO_LUZ'), 'RECIBO_DIGITAL_FALTA:' || pg_temp.ctx('RECIBO_LUZ2')));
Begin
	Insert Into e2e_resultados Values ('05. Sin aviso si ya llegó', Case When v_avisos = 0 Then 'OK' Else 'ERROR' End, v_avisos || ' aviso(s)');
End;
$$;

-- 06. Sin historial (Luz del depa no tiene recibos anteriores), la fecha esperada es el día 25 del mes.
Do $$
Declare
	v_recibo public.recibos%rowtype;
Begin
	Select * Into v_recibo From public.recibos Where id = pg_temp.ctx('RECIBO_LUZ2');
	Insert Into e2e_resultados Values ('06. Fecha esperada sin historial',
		Case When Extract(Day From app_private.recibo_digital_esperado_desde(v_recibo)) = 25 Then 'OK' Else 'ERROR' End,
		to_char(app_private.recibo_digital_esperado_desde(v_recibo), 'DD/MM/YYYY'));
End;
$$;

Select Prueba As prueba, Resultado As resultado, Detalle As detalle From e2e_resultados Order By Prueba;

Rollback;
