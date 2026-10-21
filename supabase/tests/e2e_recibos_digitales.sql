/*================================================================================
Objetivo:
	Validar los recibos digitales: con el número de suministro, el monto y el vencimiento
	que llegan del correo del proveedor, FamiliaHub confirma solo el recibo del mes,
	sin adivinar nada cuando algo no cuadra.

Requisitos:
	Los mismos de e2e_flujo_familiar.sql y e2e_whatsapp.sql (usuarios reales, correos
	confirmados, usuarios Jhosep y Liliana, sin familia activa). Ejecutar como postgres.

Ejemplo previo:
	Select set_config('familiahub.e2e_jhosep_email', '<correo-admin>', false);
	Select set_config('familiahub.e2e_liliana_email', '<correo-integrante>', false);

Importante:
	- Todo se ejecuta dentro de una transacción y termina con Rollback.
	- Los números de suministro y los correos son ficticios.
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

/*--------------------------------------------------------------------------------
Preparación: usuarios, familia y dos servicios variables con su número de suministro.
--------------------------------------------------------------------------------*/

Do $$
Declare
	v_correo_jhosep text := NullIf(Current_Setting('familiahub.e2e_jhosep_email', true), '');
	v_correo_liliana text := NullIf(Current_Setting('familiahub.e2e_liliana_email', true), '');
	v_jhosep_id uuid;
	v_liliana_id uuid;
Begin
	If v_correo_jhosep Is Null Or v_correo_liliana Is Null Then
		Raise Exception 'Configura familiahub.e2e_jhosep_email y familiahub.e2e_liliana_email antes de ejecutar.';
	End If;

	Select id Into v_jhosep_id From auth.users Where Lower(email) = Lower(v_correo_jhosep) And email_confirmed_at Is Not Null;
	Select id Into v_liliana_id From auth.users Where Lower(email) = Lower(v_correo_liliana) And email_confirmed_at Is Not Null;

	If v_jhosep_id Is Null Or v_liliana_id Is Null Then
		Raise Exception 'Ambas cuentas deben existir en Supabase Auth con el correo confirmado.';
	End If;

	Insert Into e2e_contexto (Clave, Valor)
	Values ('JHOSEP_USUARIO_ID', v_jhosep_id::text), ('LILIANA_USUARIO_ID', v_liliana_id::text);
End;
$$;

Set Local Role authenticated;
Select set_config('request.jwt.claims', Json_Build_Object('sub', (Select Valor From e2e_contexto Where Clave = 'JHOSEP_USUARIO_ID'), 'role', 'authenticated')::text, true);

Do $$
Declare
	v_familia_id uuid;
Begin
	Select public.crear_familia_inicial('FamiliaHub Recibos Digitales E2E') Into v_familia_id;
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
Values ((Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID'), (Select Valor::uuid From e2e_contexto Where Clave = 'LILIANA_USUARIO_ID'), 'INTEGRANTE', 'ACTIVO');

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
	v_participantes jsonb := Jsonb_Build_Array(
		Jsonb_Build_Object('miembro_id', (Select Valor::uuid From e2e_contexto Where Clave = 'JHOSEP_MIEMBRO_ID'), 'modalidad', 'IGUAL', 'valor', Null),
		Jsonb_Build_Object('miembro_id', (Select Valor::uuid From e2e_contexto Where Clave = 'LILIANA_MIEMBRO_ID'), 'modalidad', 'IGUAL', 'valor', Null)
	);
	v_categoria_id uuid;
	v_servicio record;
	v_concepto_id uuid;
	v_recibo_id uuid;
Begin
	Select id Into v_categoria_id From public.categorias Where familia_id = v_familia_id and nombre = 'Servicios' and activo = true;

	For v_servicio In
		Select * From (Values ('LUZ', 'LUZ_DEL_SUR', 'Luz', '1876543'), ('AGUA', 'SEDAPAL', 'Agua', '2345678')) As s(plantilla, proveedor, nombre, suministro)
	Loop
		Select public.guardar_concepto_servicio_fase6(
			Null,
			v_familia_id,
			v_categoria_id,
			(Select id From public.proveedores Where codigo = v_servicio.proveedor),
			(Select id From public.plantillas_servicio Where codigo = v_servicio.plantilla),
			v_servicio.nombre || ' Recibo Digital E2E',
			'MENSUAL',
			'MANUAL',
			Null,
			'PROVEEDOR',
			Null::smallint,
			'IGUAL',
			Null,
			true,
			Jsonb_Build_Object(
				'tipo_identificador_id', (Select t.id From public.tipos_identificador_proveedor t Join public.proveedores p On p.id = t.proveedor_id Where p.codigo = v_servicio.proveedor Order By t.orden Limit 1),
				'identificador_valor', v_servicio.suministro
			),
			v_participantes,
			(timezone('America/Lima', now()))::date,
			3::smallint
		)
		Into v_concepto_id;

		Select id Into v_recibo_id From public.recibos Where concepto_id = v_concepto_id Order By created_at Desc Limit 1;

		Insert Into e2e_contexto (Clave, Valor)
		Values ('CONCEPTO_' || v_servicio.plantilla, v_concepto_id::text), ('RECIBO_' || v_servicio.plantilla, Coalesce(v_recibo_id::text, ''));
	End Loop;
End;
$$;

Reset Role;

Insert Into e2e_resultados (Prueba, Resultado, Detalle)
Select '00. Servicios con suministro', Case When Count(*) = 2 Then 'OK' Else 'ERROR' End, Count(*)::text || ' recibos esperando monto'
From public.recibos
Where id::text In (Select Valor From e2e_contexto Where Clave In ('RECIBO_LUZ', 'RECIBO_AGUA'))
	and estado = 'ESPERANDO_MONTO';

/*--------------------------------------------------------------------------------
Recibo anterior de Agua ya confirmado (S/ 50.00), para el control del monto.
--------------------------------------------------------------------------------*/

Do $$
Declare
	v_familia_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID');
	v_mes_anterior date := (date_trunc('month', timezone('America/Lima', now())) - interval '1 month')::date;
	v_periodo_id uuid;
Begin
	Insert Into public.periodos (familia_id, anio, mes, estado)
	Values (v_familia_id, Extract(Year From v_mes_anterior)::smallint, Extract(Month From v_mes_anterior)::smallint, 'ABIERTO')
	On Conflict (familia_id, anio, mes) Do Nothing;

	Select id Into v_periodo_id From public.periodos
	Where familia_id = v_familia_id and anio = Extract(Year From v_mes_anterior) and mes = Extract(Month From v_mes_anterior);

	Insert Into public.recibos (
		familia_id, periodo_id, concepto_id, nombre_concepto, categoria_nombre, proveedor_nombre, tipo_servicio,
		frecuencia, metodo_obtencion, tipo_vencimiento, tipo_distribucion, dias_anticipacion_aporte,
		monto_base, fecha_vencimiento, estado, monto_confirmado_at
	)
	Select v_familia_id, v_periodo_id, c.id, c.nombre, 'Servicios', 'SEDAPAL', 'AGUA',
		'MENSUAL', 'MANUAL', 'PROVEEDOR', 'IGUAL', 3,
		50.00, v_mes_anterior + 20, 'PENDIENTE', now() - interval '30 days'
	From public.conceptos_pago c
	Where c.id = (Select Valor::uuid From e2e_contexto Where Clave = 'CONCEPTO_AGUA')
	On Conflict (periodo_id, concepto_id) Do Nothing;
End;
$$;

Set Local Role service_role;

/*--------------------------------------------------------------------------------
1. Suministro con guiones y espacios: confirma el recibo, crea cuotas y registra el origen.
--------------------------------------------------------------------------------*/

Do $$
Declare
	v_hoy date := (timezone('America/Lima', now()))::date;
	v_resultado jsonb;
	v_recibo public.recibos%rowtype;
	v_cuotas integer;
	v_total numeric;
	v_evento boolean;
Begin
	v_resultado := public.registrar_recibo_digital('e2e-luz-1', 'LUZ_DEL_SUR', Array['Cliente 12345678901', ' 187-6543 '], 142.60, v_hoy + 8);
	Select * Into v_recibo From public.recibos Where id = (Select Valor::uuid From e2e_contexto Where Clave = 'RECIBO_LUZ');
	Select Count(*), Sum(monto_asignado) Into v_cuotas, v_total From public.cuotas Where recibo_id = v_recibo.id;
	Select Exists (
		Select 1 From public.eventos_financieros
		Where entidad_id = v_recibo.id and evento = 'MONTO_CONFIRMADO' and detalle ->> 'origen' = 'RECIBO_DIGITAL' and usuario_id Is Null
	) Into v_evento;

	Insert Into e2e_resultados (Prueba, Resultado, Detalle)
	Values (
		'01. Confirma con el recibo digital',
		Case When v_resultado ->> 'estado' = 'CONFIRMADO' and v_recibo.estado = 'PENDIENTE' and v_recibo.monto_total = 142.60
			and v_recibo.fecha_vencimiento = v_hoy + 8 and v_cuotas = 2 and v_total = 142.60 and v_evento Then 'OK' Else 'ERROR' End,
		Format('estado %s, recibo %s S/ %s, %s cuotas S/ %s, evento %s', v_resultado ->> 'estado', v_recibo.estado, v_recibo.monto_total, v_cuotas, v_total, v_evento)
	);
End;
$$;

/*--------------------------------------------------------------------------------
2. El mismo correo otra vez no se aplica de nuevo.
--------------------------------------------------------------------------------*/

Do $$
Declare
	v_resultado jsonb;
	v_cuotas integer;
Begin
	v_resultado := public.registrar_recibo_digital('e2e-luz-1', 'LUZ_DEL_SUR', Array['1876543'], 999.00, (timezone('America/Lima', now()))::date + 8);
	Select Count(*) Into v_cuotas From public.cuotas Where recibo_id = (Select Valor::uuid From e2e_contexto Where Clave = 'RECIBO_LUZ');

	Insert Into e2e_resultados (Prueba, Resultado, Detalle)
	Values ('02. Correo repetido', Case When (v_resultado ->> 'repetido')::boolean and v_resultado ->> 'estado' = 'CONFIRMADO' and v_cuotas = 2 Then 'OK' Else 'ERROR' End, v_resultado::text);
End;
$$;

/*--------------------------------------------------------------------------------
3 a 5. Recibo ya confirmado, suministro desconocido y proveedor equivocado se ignoran.
--------------------------------------------------------------------------------*/

Do $$
Declare
	v_hoy date := (timezone('America/Lima', now()))::date;
	v_ya_confirmado jsonb := public.registrar_recibo_digital('e2e-luz-2', 'LUZ_DEL_SUR', Array['1876543'], 150.00, v_hoy + 8);
	v_desconocido jsonb := public.registrar_recibo_digital('e2e-luz-3', 'LUZ_DEL_SUR', Array['9999999'], 80.00, v_hoy + 8);
	v_otro_proveedor jsonb := public.registrar_recibo_digital('e2e-sedapal-1', 'SEDAPAL', Array['1876543'], 40.00, v_hoy + 8);
Begin
	Insert Into e2e_resultados (Prueba, Resultado, Detalle)
	Values
		('03. Recibo ya confirmado', Case When v_ya_confirmado ->> 'estado' = 'IGNORADO' Then 'OK' Else 'ERROR' End, v_ya_confirmado ->> 'detalle'),
		('04. Suministro desconocido', Case When v_desconocido ->> 'estado' = 'IGNORADO' Then 'OK' Else 'ERROR' End, v_desconocido ->> 'detalle'),
		('05. Proveedor equivocado', Case When v_otro_proveedor ->> 'estado' = 'IGNORADO' Then 'OK' Else 'ERROR' End, v_otro_proveedor ->> 'detalle');
End;
$$;

/*--------------------------------------------------------------------------------
6. Datos inválidos se rechazan.
--------------------------------------------------------------------------------*/

Do $$
Declare
	v_hoy date := (timezone('America/Lima', now()))::date;
	v_errores text[] := '{}';
Begin
	Begin Perform public.registrar_recibo_digital('e2e-x1', 'LUZ_DEL_SUR', Array['1876543'], 0, v_hoy); Exception When Others Then v_errores := v_errores || 'monto 0'::text; End;
	Begin Perform public.registrar_recibo_digital('e2e-x2', 'LUZ_DEL_SUR', Array['1876543'], 10.555, v_hoy); Exception When Others Then v_errores := v_errores || 'tres decimales'::text; End;
	Begin Perform public.registrar_recibo_digital('e2e-x3', 'ENEL', Array['1876543'], 10, v_hoy); Exception When Others Then v_errores := v_errores || 'proveedor'::text; End;
	Begin Perform public.registrar_recibo_digital('e2e-x4', 'LUZ_DEL_SUR', Array['12'], 10, v_hoy); Exception When Others Then v_errores := v_errores || 'suministro'::text; End;
	Begin Perform public.registrar_recibo_digital('e2e-x5', 'LUZ_DEL_SUR', Array['1876543'], 10, Null); Exception When Others Then v_errores := v_errores || 'vencimiento'::text; End;
	Begin Perform public.registrar_recibo_digital('', 'LUZ_DEL_SUR', Array['1876543'], 10, v_hoy); Exception When Others Then v_errores := v_errores || 'mensaje'::text; End;

	Insert Into e2e_resultados (Prueba, Resultado, Detalle)
	Values ('06. Datos inválidos', Case When Cardinality(v_errores) = 6 Then 'OK' Else 'ERROR' End, Array_To_String(v_errores, ', '));
End;
$$;

/*--------------------------------------------------------------------------------
7 y 8. Monto muy distinto al anterior y fecha absurda quedan para revisar; luego confirma.
--------------------------------------------------------------------------------*/

Do $$
Declare
	v_hoy date := (timezone('America/Lima', now()))::date;
	v_alto jsonb := public.registrar_recibo_digital('e2e-agua-1', 'SEDAPAL', Array['2345678'], 500.00, v_hoy + 8);
	v_fecha jsonb := public.registrar_recibo_digital('e2e-agua-2', 'SEDAPAL', Array['2345678'], 55.00, v_hoy + 200);
	v_normal jsonb;
	v_estado public.estado_recibo;
Begin
	Select estado Into v_estado From public.recibos Where id = (Select Valor::uuid From e2e_contexto Where Clave = 'RECIBO_AGUA');

	Insert Into e2e_resultados (Prueba, Resultado, Detalle)
	Values
		('07. Monto 10 veces el anterior', Case When v_alto ->> 'estado' = 'REVISAR' and v_estado = 'ESPERANDO_MONTO' Then 'OK' Else 'ERROR' End, v_alto ->> 'detalle'),
		('08. Fecha de vencimiento absurda', Case When v_fecha ->> 'estado' = 'REVISAR' Then 'OK' Else 'ERROR' End, v_fecha ->> 'detalle');

	v_normal := public.registrar_recibo_digital('e2e-agua-3', 'SEDAPAL', Array['2345678'], 55.00, v_hoy + 8);
	Insert Into e2e_resultados (Prueba, Resultado, Detalle)
	Values ('09. Monto normal se confirma', Case When v_normal ->> 'estado' = 'CONFIRMADO' Then 'OK' Else 'ERROR' End, v_normal ->> 'detalle');
End;
$$;

/*--------------------------------------------------------------------------------
10. Correo que llega antes que el recibo del mes: queda en espera y el job lo aplica.
--------------------------------------------------------------------------------*/

Do $$
Declare
	v_vence date := (date_trunc('month', timezone('America/Lima', now())) + interval '2 months')::date + 2;
	v_espera jsonb;
Begin
	v_espera := public.registrar_recibo_digital('e2e-luz-futuro', 'LUZ_DEL_SUR', Array['1876543'], 150.00, v_vence);
	Insert Into e2e_contexto (Clave, Valor) Values ('ESPERA_ESTADO', v_espera ->> 'estado'), ('ESPERA_VENCE', v_vence::text);
End;
$$;

Reset Role;

Do $$
Declare
	v_familia_id uuid := (Select Valor::uuid From e2e_contexto Where Clave = 'FAMILIA_ID');
	v_vence date := (Select Valor::date From e2e_contexto Where Clave = 'ESPERA_VENCE');
	v_estado_inicial text := (Select Valor From e2e_contexto Where Clave = 'ESPERA_ESTADO');
	v_periodo_id uuid;
	v_final public.recibos_digitales%rowtype;
Begin
	Insert Into public.periodos (familia_id, anio, mes, estado)
	Values (v_familia_id, Extract(Year From v_vence)::smallint, Extract(Month From v_vence)::smallint, 'ABIERTO')
	Returning id Into v_periodo_id;

	Insert Into public.recibos (
		familia_id, periodo_id, concepto_id, nombre_concepto, categoria_nombre, proveedor_nombre, tipo_servicio,
		frecuencia, metodo_obtencion, tipo_vencimiento, tipo_distribucion, dias_anticipacion_aporte
	)
	Select v_familia_id, v_periodo_id, c.id, c.nombre, 'Servicios', 'Luz del Sur', 'LUZ', 'MENSUAL', 'MANUAL', 'PROVEEDOR', 'IGUAL', 3
	From public.conceptos_pago c
	Where c.id = (Select Valor::uuid From e2e_contexto Where Clave = 'CONCEPTO_LUZ');

	Perform app_private.aplicar_recibos_digitales_en_espera();
	Select * Into v_final From public.recibos_digitales Where mensaje_id = 'e2e-luz-futuro';

	Insert Into e2e_resultados (Prueba, Resultado, Detalle)
	Values (
		'10. En espera y aplicado por el job',
		Case When v_estado_inicial = 'EN_ESPERA' and v_final.estado = 'CONFIRMADO' and v_final.intentos = 2 Then 'OK' Else 'ERROR' End,
		Format('primero %s, después %s tras %s intentos', v_estado_inicial, v_final.estado, v_final.intentos)
	);
End;
$$;

/*--------------------------------------------------------------------------------
11. Permisos: solo el servicio registra recibos digitales.
--------------------------------------------------------------------------------*/

Insert Into e2e_resultados (Prueba, Resultado, Detalle)
Select '11. Permisos',
	Case When Not Has_Function_Privilege('authenticated', 'public.registrar_recibo_digital(text, text, text[], numeric, date)', 'EXECUTE')
		and Not Has_Function_Privilege('anon', 'public.registrar_recibo_digital(text, text, text[], numeric, date)', 'EXECUTE')
		and Has_Function_Privilege('service_role', 'public.registrar_recibo_digital(text, text, text[], numeric, date)', 'EXECUTE')
		and Not Has_Table_Privilege('anon', 'public.recibos_digitales', 'SELECT')
	Then 'OK' Else 'ERROR' End,
	'authenticated y anon no pueden registrar; service_role sí.';

Select Prueba, Resultado, Detalle From e2e_resultados Order By Prueba;

Rollback;
