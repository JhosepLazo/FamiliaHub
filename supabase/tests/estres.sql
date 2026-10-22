/*================================================================================
Objetivo:
	Pruebas de estrés de la base: muchas consultas seguidas del bot, correos de recibos
	digitales repetidos y tomas de avisos repetidas. Verifican que nada se duplique, que
	las respuestas sean siempre las mismas y que los tiempos se mantengan bajos.

Requisitos:
	Los mismos de e2e_recibos_digitales.sql (usuarios Jhosep y Liliana sin familia activa).
	Ejecutar como postgres.

Importante:
	- Todo se ejecuta dentro de una transacción y termina con Rollback.
	- El grupo, los números de WhatsApp y los suministros son ficticios.
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

Create Temp Table estres_avisos_tomados
(
	Aviso_Id uuid Not Null
) On Commit Drop;

Grant Select, Insert, Update, Delete On e2e_contexto, e2e_resultados, estres_avisos_tomados To authenticated, service_role;

/*--------------------------------------------------------------------------------
Preparación: familia con Luz y Agua (con suministro), grupo e integrante vinculados.
--------------------------------------------------------------------------------*/

Do $$
Declare
	v_jhosep_id uuid;
	v_liliana_id uuid;
Begin
	Select id Into v_jhosep_id From auth.users Where Lower(email) = Lower(Current_Setting('familiahub.e2e_jhosep_email', true)) And email_confirmed_at Is Not Null;
	Select id Into v_liliana_id From auth.users Where Lower(email) = Lower(Current_Setting('familiahub.e2e_liliana_email', true)) And email_confirmed_at Is Not Null;

	If v_jhosep_id Is Null Or v_liliana_id Is Null Then
		Raise Exception 'Configura familiahub.e2e_jhosep_email y familiahub.e2e_liliana_email con cuentas confirmadas.';
	End If;

	Insert Into e2e_contexto (Clave, Valor) Values ('JHOSEP_USUARIO_ID', v_jhosep_id::text), ('LILIANA_USUARIO_ID', v_liliana_id::text);
End;
$$;

Set Local Role authenticated;
Select set_config('request.jwt.claims', Json_Build_Object('sub', (Select Valor From e2e_contexto Where Clave = 'JHOSEP_USUARIO_ID'), 'role', 'authenticated')::text, true);

Do $$
Begin
	Insert Into e2e_contexto (Clave, Valor) Values ('FAMILIA_ID', public.crear_familia_inicial('FamiliaHub Estrés')::text);
End;
$$;

Reset Role;

Insert Into public.miembros_familia (familia_id, usuario_id, rol, estado)
Values ((Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID'), (Select Valor::uuid From e2e_contexto Where Clave = 'LILIANA_USUARIO_ID'), 'INTEGRANTE', 'ACTIVO');

Insert Into e2e_contexto (Clave, Valor)
Select Case When m.usuario_id = (Select Valor::uuid From e2e_contexto Where Clave = 'JHOSEP_USUARIO_ID') Then 'JHOSEP_MIEMBRO_ID' Else 'LILIANA_MIEMBRO_ID' End, m.id::text
From public.miembros_familia m
Where m.familia_id = (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID');

Set Local Role authenticated;
Select set_config('request.jwt.claims', Json_Build_Object('sub', (Select Valor From e2e_contexto Where Clave = 'JHOSEP_USUARIO_ID'), 'role', 'authenticated')::text, true);

Do $$
Declare
	v_familia_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID');
	v_participantes jsonb := Jsonb_Build_Array(
		Jsonb_Build_Object('miembro_id', (Select Valor::uuid From e2e_contexto Where Clave = 'JHOSEP_MIEMBRO_ID'), 'modalidad', 'IGUAL', 'valor', Null),
		Jsonb_Build_Object('miembro_id', (Select Valor::uuid From e2e_contexto Where Clave = 'LILIANA_MIEMBRO_ID'), 'modalidad', 'IGUAL', 'valor', Null)
	);
	v_categoria_id uuid;
	v_servicio record;
	v_concepto_id uuid;
Begin
	Select id Into v_categoria_id From public.categorias Where familia_id = v_familia_id and nombre = 'Servicios' and activo = true;

	For v_servicio In
		Select * From (Values ('LUZ', 'LUZ_DEL_SUR', 'Luz', '1876543'), ('AGUA', 'SEDAPAL', 'Agua', '2345678')) As s(plantilla, proveedor, nombre, suministro)
	Loop
		Select public.guardar_concepto_servicio_fase6(
			Null, v_familia_id, v_categoria_id,
			(Select id From public.proveedores Where codigo = v_servicio.proveedor),
			(Select id From public.plantillas_servicio Where codigo = v_servicio.plantilla),
			v_servicio.nombre || ' Estrés', 'MENSUAL', 'MANUAL', Null, 'PROVEEDOR', Null::smallint, 'IGUAL', Null, true,
			Jsonb_Build_Object(
				'tipo_identificador_id', (Select t.id From public.tipos_identificador_proveedor t Join public.proveedores p On p.id = t.proveedor_id Where p.codigo = v_servicio.proveedor Order By t.orden Limit 1),
				'identificador_valor', v_servicio.suministro
			),
			v_participantes, (timezone('America/Lima', now()))::date, 3::smallint
		)
		Into v_concepto_id;

		Insert Into e2e_contexto (Clave, Valor)
		Values ('RECIBO_' || v_servicio.plantilla, (Select id::text From public.recibos Where concepto_id = v_concepto_id Order By created_at Desc Limit 1));
	End Loop;
End;
$$;

Reset Role;

Insert Into public.whatsapp_vinculos (familia_id, tipo, whatsapp_id, vinculado_at)
Values ((Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID'), 'GRUPO', '120363000000777001@g.us', now());

Insert Into public.whatsapp_vinculos (familia_id, tipo, miembro_id, whatsapp_id, vinculado_at)
Values ((Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID'), 'INTEGRANTE', (Select Valor::uuid From e2e_contexto Where Clave = 'LILIANA_MIEMBRO_ID'), '51900000777@s.whatsapp.net', now());

-- Ventana de envío de todo el día para que la prueba no dependa de la hora.
Insert Into public.whatsapp_configuracion (familia_id, hora_inicio_envio, hora_fin_envio)
Values ((Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID'), '00:00', '23:59')
On Conflict (familia_id) Do Update Set hora_inicio_envio = '00:00', hora_fin_envio = '23:59', avisos_activos = true;

Set Local Role service_role;

-- El recibo de Agua llega por correo: así hay monto y cuotas que consultar.
Select public.registrar_recibo_digital('estres-agua', 'SEDAPAL', Array['2345678'], 60.00, (timezone('America/Lima', now()))::date + 8);

/*--------------------------------------------------------------------------------
1. 1 000 consultas del bot (200 rondas de 5 comandos): siempre la misma respuesta.
--------------------------------------------------------------------------------*/

Do $$
Declare
	v_comandos text[] := Array['deuda', 'pendientes', 'recibos', 'resumen', 'vence'];
	v_primeras jsonb := '{}'::jsonb;
	v_texto text;
	v_inicio timestamptz := clock_timestamp();
	v_distintas integer := 0;
	v_ms numeric;
Begin
	For v_ronda In 1..200 Loop
		Foreach v_texto In Array v_comandos Loop
			Declare
				v_respuesta jsonb := public.whatsapp_procesar_comando('120363000000777001@g.us', Array['51900000777@s.whatsapp.net'], v_texto, '');
			Begin
				If v_respuesta ->> 'texto' Is Null Then
					Raise Exception 'El comando % no devolvió texto en la ronda %', v_texto, v_ronda;
				End If;
				If v_ronda = 1 Then
					v_primeras := v_primeras || Jsonb_Build_Object(v_texto, v_respuesta ->> 'texto');
				ElsIf v_primeras ->> v_texto Is Distinct From v_respuesta ->> 'texto' Then
					v_distintas := v_distintas + 1;
				End If;
			End;
		End Loop;
	End Loop;

	v_ms := Extract(Epoch From clock_timestamp() - v_inicio) * 1000;
	Insert Into e2e_resultados Values (
		'01. 1 000 consultas del bot',
		Case When v_distintas = 0 And v_primeras ->> 'deuda' Like 'Liliana, debes S/ 30.00%' Then 'OK' Else 'ERROR' End,
		Format('%s respuestas distintas · %s ms en total · %s ms por consulta', v_distintas, Round(v_ms), Round(v_ms / 1000, 2))
	);
End;
$$;

/*--------------------------------------------------------------------------------
2. El mismo correo de recibo digital llega 500 veces: una sola lectura, sin cuotas extra.
--------------------------------------------------------------------------------*/

Do $$
Declare
	v_hoy date := (timezone('America/Lima', now()))::date;
	v_resultado jsonb;
	v_no_repetidos integer := 0;
	v_inicio timestamptz := clock_timestamp();
	v_lecturas integer;
	v_cuotas integer;
	v_eventos integer;
Begin
	For i In 1..500 Loop
		v_resultado := public.registrar_recibo_digital('estres-luz', 'LUZ_DEL_SUR', Array['1876543'], 142.60, v_hoy + 8);
		If i > 1 And (v_resultado ->> 'repetido')::boolean Is Not True Then v_no_repetidos := v_no_repetidos + 1; End If;
	End Loop;

	Select Count(*) Into v_lecturas From public.recibos_digitales Where mensaje_id = 'estres-luz';
	Select Count(*) Into v_cuotas From public.cuotas Where recibo_id = (Select Valor::uuid From e2e_contexto Where Clave = 'RECIBO_LUZ');
	Select Count(*) Into v_eventos From public.eventos_financieros
	Where entidad_id = (Select Valor::uuid From e2e_contexto Where Clave = 'RECIBO_LUZ') And evento = 'MONTO_CONFIRMADO';

	Insert Into e2e_resultados Values (
		'02. Mismo correo 500 veces',
		Case When v_lecturas = 1 And v_cuotas = 2 And v_eventos = 1 And v_no_repetidos = 0 Then 'OK' Else 'ERROR' End,
		Format('%s lectura · %s cuotas · %s confirmación · %s ms', v_lecturas, v_cuotas, v_eventos, Round(Extract(Epoch From clock_timestamp() - v_inicio) * 1000))
	);
End;
$$;

/*--------------------------------------------------------------------------------
3. 300 correos de suministros que no son de la familia: se ignoran sin tocar recibos.
--------------------------------------------------------------------------------*/

Do $$
Declare
	v_hoy date := (timezone('America/Lima', now()))::date;
	v_antes text := (Select string_agg(id::text || estado::text || Coalesce(monto_base::text, '-'), ',' Order By id) From public.recibos Where familia_id = (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID'));
	v_despues text;
	v_ignorados integer;
	v_inicio timestamptz := clock_timestamp();
Begin
	For i In 1..300 Loop
		Perform public.registrar_recibo_digital('estres-ajeno-' || i, 'SEDAPAL', Array['99' || Lpad(i::text, 6, '0')], 10 + i, v_hoy + 5);
	End Loop;

	Select Count(*) Into v_ignorados From public.recibos_digitales Where mensaje_id Like 'estres-ajeno-%' And estado = 'IGNORADO';
	v_despues := (Select string_agg(id::text || estado::text || Coalesce(monto_base::text, '-'), ',' Order By id) From public.recibos Where familia_id = (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID'));

	Insert Into e2e_resultados Values (
		'03. 300 correos ajenos',
		Case When v_ignorados = 300 And v_antes = v_despues Then 'OK' Else 'ERROR' End,
		Format('%s ignorados · recibos sin cambios: %s · %s ms', v_ignorados, v_antes = v_despues, Round(Extract(Epoch From clock_timestamp() - v_inicio) * 1000))
	);
End;
$$;

/*--------------------------------------------------------------------------------
4. 120 avisos y 200 tomas seguidas de a 5: ningún aviso se entrega dos veces.
--------------------------------------------------------------------------------*/

Reset Role;

Insert Into public.avisos_whatsapp (familia_id, tipo, clave, texto, expira_at)
Select (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID'), 'INICIO_MES', 'estres-aviso-' || i, 'Aviso de prueba ' || i, now() + interval '1 hour'
From generate_series(1, 120) As i;

Set Local Role service_role;

Do $$
Declare
	v_avisos jsonb;
	v_inicio timestamptz := clock_timestamp();
	v_tomados integer;
	v_distintos integer;
	v_sobrantes integer;
Begin
	For i In 1..200 Loop
		v_avisos := public.whatsapp_tomar_avisos(5::smallint);
		Insert Into estres_avisos_tomados (Aviso_Id)
		Select (aviso ->> 'id')::uuid From jsonb_array_elements(Coalesce(v_avisos, '[]'::jsonb)) As aviso;
	End Loop;

	Select Count(*), Count(Distinct Aviso_Id) Into v_tomados, v_distintos From estres_avisos_tomados;

	-- Se confirman todos como enviados: no debe quedar nada por tomar.
	Perform public.whatsapp_marcar_aviso(Aviso_Id, true, Null) From estres_avisos_tomados;
	Select Count(*) Into v_sobrantes From public.avisos_whatsapp
	Where familia_id = (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID') And clave Like 'estres-aviso-%' And estado <> 'ENVIADO';

	Insert Into e2e_resultados Values (
		'04. 200 tomas de avisos',
		Case When v_tomados = 120 And v_distintos = 120 And v_sobrantes = 0 Then 'OK' Else 'ERROR' End,
		Format('%s tomados · %s distintos · %s sin enviar · %s ms', v_tomados, v_distintos, v_sobrantes, Round(Extract(Epoch From clock_timestamp() - v_inicio) * 1000))
	);
End;
$$;

Reset Role;

Select Prueba As prueba, Resultado As resultado, Detalle As detalle
From e2e_resultados
Order By Prueba;

Rollback;
