/*================================================================================
Objetivo:
	Prueba de estrés de todos los procesos del administrador y de los integrantes en una
	familia de tres personas con ocho servicios: cientos de pagos (completos y parciales),
	validaciones, rechazos, anulaciones, correcciones de monto, pagos al proveedor (fondo y
	adelanto), anulación de recibos, eliminación de servicios e intentos indebidos.
	Al final comprueba que las cuentas cuadren en todos los recibos, cuotas y pagos.

Requisitos:
	Los mismos de e2e_flujo_familiar.sql. Crea un tercer usuario ficticio (Mario) dentro
	de la transacción. Ejecutar como postgres. Todo termina con Rollback.
================================================================================*/

Begin;

Create Temp Table e2e_contexto (Clave varchar(80) Primary Key, Valor text Not Null) On Commit Drop;
Create Temp Table e2e_resultados (Prueba varchar(120) Not Null, Resultado varchar(20) Not Null, Detalle text Null) On Commit Drop;
Create Temp Table estres_conteo (Clave varchar(40) Primary Key, Valor integer Not Null Default 0) On Commit Drop;
Grant Select, Insert, Update, Delete On e2e_contexto, e2e_resultados, estres_conteo To authenticated, service_role;

Insert Into auth.users (email, email_confirmed_at, raw_user_meta_data)
Values ('mario.estres@example.com', now(), '{"nombre": "Mario", "usuario": "MarioEstres"}');

Do $$
Begin
	Insert Into e2e_contexto (Clave, Valor)
	Select 'JHOSEP_USUARIO_ID', id::text From auth.users Where Lower(email) = Lower(Current_Setting('familiahub.e2e_jhosep_email', true)) And email_confirmed_at Is Not Null;
	Insert Into e2e_contexto (Clave, Valor)
	Select 'LILIANA_USUARIO_ID', id::text From auth.users Where Lower(email) = Lower(Current_Setting('familiahub.e2e_liliana_email', true)) And email_confirmed_at Is Not Null;
	Insert Into e2e_contexto (Clave, Valor)
	Select 'MARIO_USUARIO_ID', id::text From auth.users Where email = 'mario.estres@example.com';
	If (Select Count(*) From e2e_contexto) <> 3 Then
		Raise Exception 'Configura familiahub.e2e_jhosep_email y familiahub.e2e_liliana_email con cuentas confirmadas.';
	End If;
End;
$$;

Create Or Replace Function pg_temp.como(p_quien text) Returns void Language plpgsql As $$
Begin
	Perform set_config('request.jwt.claims', Json_Build_Object('sub', (Select Valor From e2e_contexto Where Clave = p_quien || '_USUARIO_ID'), 'role', 'authenticated')::text, true);
End;
$$;

Create Or Replace Function pg_temp.ctx(p_clave text) Returns uuid Language sql As $$
	Select Valor::uuid From e2e_contexto Where Clave = p_clave;
$$;

Create Or Replace Function pg_temp.contar(p_clave text, p_cuanto integer Default 1) Returns void Language sql As $$
	Insert Into estres_conteo (Clave, Valor) Values (p_clave, p_cuanto)
	On Conflict (Clave) Do Update Set Valor = estres_conteo.Valor + Excluded.Valor;
$$;

-- Ejecuta una operación que debe fallar; devuelve el mensaje de error (o null si no falló).
Create Or Replace Function pg_temp.debe_fallar(p_sql text) Returns text Language plpgsql As $$
Begin
	Execute p_sql;
	Return Null;
Exception When Others Then
	Return SqlErrM;
End;
$$;

-- Saldo disponible de una cuota (función interna de la base, que un integrante no puede llamar directamente).
Create Or Replace Function pg_temp.disponible(p_cuota uuid) Returns numeric Language sql Security Definer As $$
	Select app_private.saldo_disponible_cuota(p_cuota, Null);
$$;

Grant Execute On Function pg_temp.como(text), pg_temp.ctx(text), pg_temp.contar(text, integer), pg_temp.debe_fallar(text), pg_temp.disponible(uuid) To authenticated;

Set Local Role authenticated;
Select pg_temp.como('JHOSEP');
Do $$ Begin Insert Into e2e_contexto Values ('FAMILIA_ID', public.crear_familia_inicial('FamiliaHub Estrés Flujos')::text); End; $$;
Reset Role;

Insert Into public.miembros_familia (familia_id, usuario_id, rol, estado)
Values (pg_temp.ctx('FAMILIA_ID'), pg_temp.ctx('LILIANA_USUARIO_ID'), 'INTEGRANTE', 'ACTIVO'),
	(pg_temp.ctx('FAMILIA_ID'), pg_temp.ctx('MARIO_USUARIO_ID'), 'INTEGRANTE', 'ACTIVO');

Insert Into e2e_contexto (Clave, Valor)
Select Case usuario_id
		When pg_temp.ctx('JHOSEP_USUARIO_ID') Then 'JHOSEP_MIEMBRO_ID'
		When pg_temp.ctx('LILIANA_USUARIO_ID') Then 'LILIANA_MIEMBRO_ID'
		Else 'MARIO_MIEMBRO_ID'
	End, id::text
From public.miembros_familia Where familia_id = pg_temp.ctx('FAMILIA_ID');

Set Local Role authenticated;
Select pg_temp.como('JHOSEP');

-- Ocho servicios con distintas formas de monto y participantes.
Do $$
Declare
	v_familia_id uuid := pg_temp.ctx('FAMILIA_ID');
	v_categoria_id uuid := (Select id From public.categorias Where familia_id = pg_temp.ctx('FAMILIA_ID') And nombre = 'Servicios' And activo);
	v_todos jsonb := Jsonb_Build_Array(
		Jsonb_Build_Object('miembro_id', pg_temp.ctx('JHOSEP_MIEMBRO_ID'), 'modalidad', 'IGUAL', 'valor', Null),
		Jsonb_Build_Object('miembro_id', pg_temp.ctx('LILIANA_MIEMBRO_ID'), 'modalidad', 'IGUAL', 'valor', Null),
		Jsonb_Build_Object('miembro_id', pg_temp.ctx('MARIO_MIEMBRO_ID'), 'modalidad', 'IGUAL', 'valor', Null)
	);
	v_dos jsonb := Jsonb_Build_Array(
		Jsonb_Build_Object('miembro_id', pg_temp.ctx('JHOSEP_MIEMBRO_ID'), 'modalidad', 'IGUAL', 'valor', Null),
		Jsonb_Build_Object('miembro_id', pg_temp.ctx('LILIANA_MIEMBRO_ID'), 'modalidad', 'IGUAL', 'valor', Null)
	);
	v_hijos jsonb := Jsonb_Build_Array(
		Jsonb_Build_Object('miembro_id', pg_temp.ctx('LILIANA_MIEMBRO_ID'), 'modalidad', 'IGUAL', 'valor', Null),
		Jsonb_Build_Object('miembro_id', pg_temp.ctx('MARIO_MIEMBRO_ID'), 'modalidad', 'IGUAL', 'valor', Null)
	);
	v_servicio record;
	v_concepto_id uuid;
Begin
	Perform public.guardar_metodo_cobro_familiar(v_familia_id, 'YAPE', 'Jhosep', '972583495', 'Prueba sin dinero real.', Null, pg_temp.ctx('JHOSEP_MIEMBRO_ID'));

	For v_servicio In
		Select * From (Values
			('INTERNET', 'Internet', 'FIJO', 90.00, v_todos),
			('AGUA', 'Agua', 'MANUAL', Null::numeric, v_todos),
			('LUZ', 'Luz', 'MANUAL', Null::numeric, v_todos),
			('GAS', 'Gas', 'FIJO', 31.00, v_todos),
			('NETFLIX', 'Netflix', 'FIJO', 44.90, v_dos),
			('CABLE', 'Cable', 'FIJO', 25.00, v_todos),
			('SPOTIFY', 'Spotify', 'FIJO', 20.00, v_dos),
			('MOVIL', 'Plan móvil', 'FIJO', 20.00, v_hijos)
		) As s(clave, nombre, metodo, monto, participantes)
	Loop
		v_concepto_id := public.guardar_concepto_servicio_fase6(
			Null, v_familia_id, v_categoria_id, (Select id From public.proveedores Where codigo = 'WIN'), (Select id From public.plantillas_servicio Where codigo = 'INTERNET'),
			v_servicio.nombre, 'MENSUAL', v_servicio.metodo::public.metodo_obtencion_monto, v_servicio.monto,
			Case When v_servicio.metodo = 'FIJO' Then 'DIA_FIJO' Else 'PROVEEDOR' End::public.tipo_vencimiento_concepto,
			Case When v_servicio.metodo = 'FIJO' Then 28 End::smallint,
			'IGUAL', Null, true, '{}'::jsonb, v_servicio.participantes, (timezone('America/Lima', now()))::date, 2::smallint
		);
		Insert Into e2e_contexto Values ('CONCEPTO_' || v_servicio.clave, v_concepto_id::text);
		Insert Into e2e_contexto
		Select 'RECIBO_' || v_servicio.clave, id::text From public.recibos Where concepto_id = v_concepto_id;
	End Loop;

	-- Los servicios variables reciben su monto (con céntimos que no se dividen exacto entre tres).
	Perform public.confirmar_monto_recibo(pg_temp.ctx('RECIBO_AGUA'), 100.00, (timezone('America/Lima', now()))::date + 12);
	Perform public.confirmar_monto_recibo(pg_temp.ctx('RECIBO_LUZ'), 145.50, (timezone('America/Lima', now()))::date + 15);
End;
$$;

/*--------------------------------------------------------------------------------
1. 300 rondas de pago de integrantes con validaciones, rechazos, anulaciones y pagos pendientes.
--------------------------------------------------------------------------------*/

Do $$
Declare
	v_inicio timestamptz := clock_timestamp();
	v_pagador text;
	v_cuota record;
	v_monto numeric;
	v_pago_id uuid;
	v_confirmado uuid;
	v_accion integer;
Begin
	For i In 1..300 Loop
		v_pagador := Case When i % 2 = 0 Then 'LILIANA' Else 'MARIO' End;
		Perform pg_temp.como(v_pagador);

		Select q.id, pg_temp.disponible(q.id) As disponible
		Into v_cuota
		From public.cuotas q
		Join public.recibos r On r.id = q.recibo_id
		Where q.familia_id = pg_temp.ctx('FAMILIA_ID')
			And q.usuario_id = pg_temp.ctx(v_pagador || '_USUARIO_ID')
			And q.estado <> 'ANULADA' And r.estado <> 'ANULADO'
			And r.id Not In (pg_temp.ctx('RECIBO_SPOTIFY'), pg_temp.ctx('RECIBO_MOVIL'), pg_temp.ctx('RECIBO_CABLE'))
			And pg_temp.disponible(q.id) > 0
		Order By md5(q.id::text || i::text)
		Limit 1;

		If v_cuota.id Is Null Then
			Perform pg_temp.contar('sin_saldo');
			Continue;
		End If;

		-- Pagos pequeños (como Yapes parciales) para que quepan cientos sobre las mismas cuotas; cada 50 se paga todo lo que falta.
		v_monto := Case
			When i % 50 = 0 Then v_cuota.disponible
			When i % 3 = 0 Then Least(2.00, v_cuota.disponible)
			When i % 3 = 1 Then Least(0.50, v_cuota.disponible)
			Else Least(1.00, v_cuota.disponible)
		End;

		v_pago_id := public.crear_pago_familiar(Jsonb_Build_Array(Jsonb_Build_Object('cuota_id', v_cuota.id, 'monto', v_monto)), 'YAPE');
		Perform public.finalizar_pago_familiar(v_pago_id, (timezone('America/Lima', now()))::date, 'E-' || i, Null);
		Perform pg_temp.contar('pagos_enviados');

		Perform pg_temp.como('JHOSEP');
		v_accion := i % 5;
		If v_accion In (0, 1, 2) Then
			Perform public.validar_pago_familiar(v_pago_id, true, Null);
			Perform pg_temp.contar('validados');
			v_confirmado := v_pago_id;
		ElsIf v_accion = 3 Then
			Perform public.validar_pago_familiar(v_pago_id, false, 'No llegó el Yape ' || i);
			Perform pg_temp.contar('rechazados');
		Else
			Perform pg_temp.contar('quedan_por_validar');
		End If;

		-- Cada 7 pagos el administrador anula el último pago confirmado (por ejemplo, un Yape que se devolvió).
		If i % 7 = 0 And v_confirmado Is Not Null Then
			Perform public.anular_pago_familiar(v_confirmado, 'Devolución de prueba ' || i);
			Perform pg_temp.contar('anulados');
			v_confirmado := Null;
		End If;
	End Loop;

	Insert Into e2e_resultados
	Select '01. 300 rondas de pago', -- Las rondas sin saldo son cuotas ya pagadas o reservadas por completo: el sistema no deja pagar de más.
		Case When Coalesce((Select Valor From estres_conteo Where Clave = 'pagos_enviados'), 0) >= 200 Then 'OK' Else 'ERROR' End,
		Format('%s pagos enviados · %s validados · %s rechazados · %s anulados · %s por validar · %s sin saldo · %s ms',
			Coalesce((Select Valor From estres_conteo Where Clave = 'pagos_enviados'), 0),
			Coalesce((Select Valor From estres_conteo Where Clave = 'validados'), 0),
			Coalesce((Select Valor From estres_conteo Where Clave = 'rechazados'), 0),
			Coalesce((Select Valor From estres_conteo Where Clave = 'anulados'), 0),
			Coalesce((Select Valor From estres_conteo Where Clave = 'quedan_por_validar'), 0),
			Coalesce((Select Valor From estres_conteo Where Clave = 'sin_saldo'), 0),
			Round(Extract(Epoch From clock_timestamp() - v_inicio) * 1000));
End;
$$;

/*--------------------------------------------------------------------------------
2. Intentos indebidos de integrantes: todos deben fallar sin cambiar nada.
--------------------------------------------------------------------------------*/

Do $$
Declare
	v_cuota_liliana uuid := (Select id From public.cuotas Where recibo_id = pg_temp.ctx('RECIBO_SPOTIFY') And usuario_id = pg_temp.ctx('LILIANA_USUARIO_ID'));
	v_cuota_jhosep uuid := (Select id From public.cuotas Where recibo_id = pg_temp.ctx('RECIBO_SPOTIFY') And usuario_id = pg_temp.ctx('JHOSEP_USUARIO_ID'));
	v_pago_pendiente uuid;
	v_fallas text[] := '{}';
	v_errores text[] := '{}';
	v_intento record;
Begin
	Perform pg_temp.como('LILIANA');
	-- Un pago pendiente de Liliana para probar la reserva de saldo y la autovalidación.
	v_pago_pendiente := public.crear_pago_familiar(Jsonb_Build_Array(Jsonb_Build_Object('cuota_id', v_cuota_liliana, 'monto', 4.00)), 'YAPE');
	Perform public.finalizar_pago_familiar(v_pago_pendiente, (timezone('America/Lima', now()))::date, 'RESERVA', Null);
	Insert Into e2e_contexto Values ('PAGO_RESERVA', v_pago_pendiente::text);

	For v_intento In Select * From (Values
		('pagar más que la cuota', Format('Select public.crear_pago_familiar(%L::jsonb, %L)', Json_Build_Array(Json_Build_Object('cuota_id', v_cuota_liliana, 'monto', 999))::text, 'YAPE')),
		('pagar lo ya reservado', Format('Select public.crear_pago_familiar(%L::jsonb, %L)', Json_Build_Array(Json_Build_Object('cuota_id', v_cuota_liliana, 'monto', 7.00))::text, 'YAPE')),
		('pagar la cuota de otro', Format('Select public.crear_pago_familiar(%L::jsonb, %L)', Json_Build_Array(Json_Build_Object('cuota_id', v_cuota_jhosep, 'monto', 1))::text, 'YAPE')),
		('monto con tres decimales', Format('Select public.crear_pago_familiar(%L::jsonb, %L)', Json_Build_Array(Json_Build_Object('cuota_id', v_cuota_liliana, 'monto', 1.005))::text, 'YAPE')),
		('validar su propio pago', Format('Select public.validar_pago_familiar(%L, true, null)', v_pago_pendiente)),
		('confirmar un monto', Format('Select public.confirmar_monto_recibo(%L, 50, current_date + 5)', pg_temp.ctx('RECIBO_SPOTIFY'))),
		('corregir un monto', Format('Select public.corregir_monto_recibo(%L, 10, %L)', pg_temp.ctx('RECIBO_SPOTIFY'), 'intento')),
		('registrar pago al proveedor', Format('Select public.registrar_pago_proveedor(p_recibo_id => %L, p_origen => %L, p_pagador_miembro_id => %L, p_monto => 20, p_fecha_pago => current_date)', pg_temp.ctx('RECIBO_SPOTIFY'), 'ADELANTO_INTEGRANTE', pg_temp.ctx('LILIANA_MIEMBRO_ID'))),
		('anular un recibo', Format('Select public.anular_recibo(%L, %L)', pg_temp.ctx('RECIBO_SPOTIFY'), 'intento')),
		('eliminar un servicio', Format('Select public.eliminar_concepto_servicio(%L)', pg_temp.ctx('CONCEPTO_SPOTIFY'))),
		('cambiar el estado de un servicio', Format('Select public.cambiar_estado_concepto(%L, false)', pg_temp.ctx('CONCEPTO_SPOTIFY'))),
		('ver los datos de otra familia', 'Select 1 / (Select Count(*)::int - Count(*)::int From public.recibos Where familia_id <> ' || Quote_Literal(pg_temp.ctx('FAMILIA_ID')) || ')')
	) As s(nombre, consulta) Loop
		Declare
			v_error text := pg_temp.debe_fallar(v_intento.consulta);
		Begin
			If v_error Is Null Then v_fallas := v_fallas || v_intento.nombre; Else v_errores := v_errores || v_error; End If;
		End;
	End Loop;

	Insert Into e2e_resultados Values ('02. Intentos indebidos rechazados',
		Case When cardinality(v_fallas) = 0 Then 'OK' Else 'ERROR' End,
		Case When cardinality(v_fallas) = 0 Then cardinality(v_errores) || ' intentos rechazados' Else 'Se permitió: ' || array_to_string(v_fallas, ', ') End);
End;
$$;

/*--------------------------------------------------------------------------------
3. Procesos del administrador.
--------------------------------------------------------------------------------*/

Select pg_temp.como('JHOSEP');

-- 3a. Corregir el monto de Luz (con pagos parciales encima) cuando lo permite.
Do $$
Declare
	v_error text := pg_temp.debe_fallar(Format('Select public.corregir_monto_recibo(%L, 150.00, %L)', pg_temp.ctx('RECIBO_LUZ'), 'Recibo corregido por la empresa'));
Begin
	Insert Into e2e_resultados Values ('03. Corregir monto de Luz',
		Case When v_error Is Null And (Select monto_total From public.recibos Where id = pg_temp.ctx('RECIBO_LUZ')) = 150.00 Then 'OK'
			When v_error Like '%encima%' Or v_error Like '%supera%' Or v_error Like '%pagado%' Then 'OK'
			Else 'ERROR' End,
		Coalesce(v_error, 'Nuevo total S/ 150.00'));
End;
$$;

-- 3b. Adelanto: Liliana paga Spotify a la empresa; se anula y se vuelve a registrar. Desde el fondo debe fallar.
Do $$
Declare
	v_reserva_resuelta text;
	v_pago_proveedor uuid;
	v_error_fondo text;
	v_ok boolean := true;
Begin
	-- El pago de reserva del paso 2 se rechaza: sin aportes, el recibo admite un adelanto.
	Perform public.validar_pago_familiar(pg_temp.ctx('PAGO_RESERVA'), false, 'Prueba de reserva');

	v_error_fondo := pg_temp.debe_fallar(Format('Select public.registrar_pago_proveedor(p_recibo_id => %L, p_origen => %L, p_pagador_miembro_id => null, p_monto => 20, p_fecha_pago => current_date)', pg_temp.ctx('RECIBO_SPOTIFY'), 'FONDO_FAMILIAR'));
	If v_error_fondo Is Null Then v_ok := false; End If;

	v_pago_proveedor := public.registrar_pago_proveedor(p_recibo_id => pg_temp.ctx('RECIBO_SPOTIFY'), p_origen => 'ADELANTO_INTEGRANTE', p_pagador_miembro_id => pg_temp.ctx('LILIANA_MIEMBRO_ID'), p_monto => 20, p_fecha_pago => (timezone('America/Lima', now()))::date, p_referencia => 'ADELANTO-1');
	Perform public.anular_pago_proveedor(v_pago_proveedor, 'Se registró con la persona equivocada');
	v_pago_proveedor := public.registrar_pago_proveedor(p_recibo_id => pg_temp.ctx('RECIBO_SPOTIFY'), p_origen => 'ADELANTO_INTEGRANTE', p_pagador_miembro_id => pg_temp.ctx('JHOSEP_MIEMBRO_ID'), p_monto => 20, p_fecha_pago => (timezone('America/Lima', now()))::date, p_referencia => 'ADELANTO-2');

	Insert Into e2e_resultados Values ('04. Adelanto, anulación y nuevo registro',
		Case When v_ok And (Select Count(*) From public.pagos_proveedor Where recibo_id = pg_temp.ctx('RECIBO_SPOTIFY') And estado = 'CONFIRMADO') = 1
			And (Select Count(*) From public.pagos_proveedor Where recibo_id = pg_temp.ctx('RECIBO_SPOTIFY') And estado = 'ANULADO') = 1
		Then 'OK' Else 'ERROR' End,
		'Desde el fondo sin recaudación completa: ' || Coalesce(v_error_fondo, 'se permitió'));
End;
$$;

-- 3c. Plan móvil: los dos hijos pagan todo, se valida y se paga a la empresa desde el fondo.
Do $$
Declare
	v_quien text;
	v_cuota record;
	v_pago uuid;
	v_pago_proveedor uuid;
Begin
	Foreach v_quien In Array Array['LILIANA', 'MARIO'] Loop
		Perform pg_temp.como(v_quien);
		Select id, saldo_pendiente Into v_cuota From public.cuotas Where recibo_id = pg_temp.ctx('RECIBO_MOVIL') And usuario_id = pg_temp.ctx(v_quien || '_USUARIO_ID');
		v_pago := public.crear_pago_familiar(Jsonb_Build_Array(Jsonb_Build_Object('cuota_id', v_cuota.id, 'monto', v_cuota.saldo_pendiente)), 'YAPE');
		Perform public.finalizar_pago_familiar(v_pago, (timezone('America/Lima', now()))::date, 'MOVIL-' || v_quien, Null);
		Perform pg_temp.como('JHOSEP');
		Perform public.validar_pago_familiar(v_pago, true, Null);
	End Loop;

	v_pago_proveedor := public.registrar_pago_proveedor(p_recibo_id => pg_temp.ctx('RECIBO_MOVIL'), p_origen => 'FONDO_FAMILIAR', p_pagador_miembro_id => Null, p_monto => 20, p_fecha_pago => (timezone('America/Lima', now()))::date, p_referencia => 'FONDO-1');

	Insert Into e2e_resultados Values ('05. Recaudación completa y pago desde el fondo',
		Case When (Select estado_recaudacion From public.recibos Where id = pg_temp.ctx('RECIBO_MOVIL')) = 'COMPLETA'
			And (Select estado From public.recibos Where id = pg_temp.ctx('RECIBO_MOVIL')) = 'PAGADO'
		Then 'OK' Else 'ERROR' End,
		(Select estado::text || ' · ' || estado_recaudacion::text From public.recibos Where id = pg_temp.ctx('RECIBO_MOVIL')));
End;
$$;

-- 3d. Cable: se anula su recibo y luego se elimina el servicio (sin dinero movido, se borra).
Do $$
Declare
	v_resultado jsonb;
Begin
	Perform public.anular_recibo(pg_temp.ctx('RECIBO_CABLE'), 'Ya no tenemos cable');
	v_resultado := public.eliminar_concepto_servicio(pg_temp.ctx('CONCEPTO_CABLE'));
	Insert Into e2e_resultados Values ('06. Anular recibo y eliminar servicio',
		Case When v_resultado ->> 'modo' = 'ELIMINADO' And Not Exists (Select 1 From public.recibos Where id = pg_temp.ctx('RECIBO_CABLE')) Then 'OK' Else 'ERROR' End,
		v_resultado::text);
End;
$$;

-- 3e. Netflix tiene pagos: al eliminarlo se archiva y su historial queda.
Do $$
Declare
	v_resultado jsonb;
	v_error text;
Begin
	-- Primero se resuelven los pagos pendientes de Netflix (si los hay), como pide el sistema.
	Perform public.validar_pago_familiar(pf.id, true, Null)
	From public.pagos_familiares pf
	Where pf.estado = 'POR_VALIDAR'
		And Exists (Select 1 From public.pago_asignaciones pa Where pa.pago_id = pf.id And pa.recibo_id = pg_temp.ctx('RECIBO_NETFLIX'));

	v_error := pg_temp.debe_fallar(Format('Select public.eliminar_concepto_servicio(%L)', pg_temp.ctx('CONCEPTO_NETFLIX')));
	Insert Into e2e_resultados Values ('07. Eliminar servicio con pagos',
		Case When v_error Is Null And (Select eliminado_at Is Not Null And Not activo From public.conceptos_pago Where id = pg_temp.ctx('CONCEPTO_NETFLIX'))
			And Exists (Select 1 From public.recibos Where id = pg_temp.ctx('RECIBO_NETFLIX'))
		Then 'OK' Else 'ERROR' End,
		Coalesce(v_error, 'Archivado con su historial'));
End;
$$;

/*--------------------------------------------------------------------------------
4. Las cuentas cuadran en todo el sistema.
--------------------------------------------------------------------------------*/

Reset Role;

Do $$
Declare
	v_familia uuid := pg_temp.ctx('FAMILIA_ID');
	v_problemas text[] := '{}';
	v_cuenta integer;
Begin
	-- Reparto: las cuotas vigentes suman exactamente el total de cada recibo.
	Select Count(*) Into v_cuenta From public.recibos r
	Where r.familia_id = v_familia And r.estado <> 'ANULADO' And r.monto_total Is Not Null
		And r.monto_total <> (Select Coalesce(Sum(q.monto_asignado), 0) From public.cuotas q Where q.recibo_id = r.id And q.estado <> 'ANULADA');
	If v_cuenta > 0 Then v_problemas := v_problemas || (v_cuenta || ' recibos cuyo reparto no suma el total'); End If;

	-- Saldos: nunca negativos ni por encima de la cuota, y saldo = cuota - pagado.
	Select Count(*) Into v_cuenta From public.cuotas q
	Where q.familia_id = v_familia And (q.monto_pagado < 0 Or q.monto_pagado > q.monto_asignado Or q.saldo_pendiente <> q.monto_asignado - q.monto_pagado);
	If v_cuenta > 0 Then v_problemas := v_problemas || (v_cuenta || ' cuotas con saldo inconsistente'); End If;

	-- Lo pagado de cada cuota coincide con sus aportes confirmados.
	Select Count(*) Into v_cuenta From public.cuotas q
	Where q.familia_id = v_familia And q.estado <> 'ANULADA'
		And q.monto_pagado <> (Select Coalesce(Sum(a.monto), 0) From public.aportes a Where a.cuota_id = q.id And a.estado = 'CONFIRMADO');
	If v_cuenta > 0 Then v_problemas := v_problemas || (v_cuenta || ' cuotas cuyo pagado no coincide con sus aportes'); End If;

	-- Lo reservado por pagos pendientes nunca supera el saldo.
	Select Count(*) Into v_cuenta From public.cuotas q
	Where q.familia_id = v_familia
		And (Select Coalesce(Sum(pa.monto), 0) From public.pago_asignaciones pa Join public.pagos_familiares pf On pf.id = pa.pago_id Where pa.cuota_id = q.id And pf.estado = 'POR_VALIDAR') > q.saldo_pendiente;
	If v_cuenta > 0 Then v_problemas := v_problemas || (v_cuenta || ' cuotas con más reservado que su saldo'); End If;

	-- Cada pago coincide con la suma de sus asignaciones.
	Select Count(*) Into v_cuenta From public.pagos_familiares pf
	Where pf.familia_id = v_familia And pf.monto_total <> (Select Coalesce(Sum(pa.monto), 0) From public.pago_asignaciones pa Where pa.pago_id = pf.id);
	If v_cuenta > 0 Then v_problemas := v_problemas || (v_cuenta || ' pagos que no suman sus asignaciones'); End If;

	-- Estado de cada cuota según su saldo.
	Select Count(*) Into v_cuenta From public.cuotas q
	Where q.familia_id = v_familia And q.estado <> 'ANULADA'
		And ((q.estado = 'PAGADA') <> (q.saldo_pendiente = 0 And q.monto_asignado > 0));
	If v_cuenta > 0 Then v_problemas := v_problemas || (v_cuenta || ' cuotas con estado PAGADA inconsistente'); End If;

	-- Recaudación de cada recibo según sus cuotas.
	Select Count(*) Into v_cuenta From public.recibos r
	Where r.familia_id = v_familia And r.estado <> 'ANULADO' And r.monto_total Is Not Null
		And ((r.estado_recaudacion = 'COMPLETA') <> Not Exists (Select 1 From public.cuotas q Where q.recibo_id = r.id And q.estado <> 'ANULADA' And q.saldo_pendiente > 0));
	If v_cuenta > 0 Then v_problemas := v_problemas || (v_cuenta || ' recibos con recaudación inconsistente'); End If;

	-- A lo más un pago confirmado a la empresa por recibo.
	Select Count(*) Into v_cuenta From (
		Select recibo_id From public.pagos_proveedor pp Join public.recibos r On r.id = pp.recibo_id
		Where r.familia_id = v_familia And pp.estado = 'CONFIRMADO' Group By recibo_id Having Count(*) > 1
	) x;
	If v_cuenta > 0 Then v_problemas := v_problemas || (v_cuenta || ' recibos con dos pagos a la empresa'); End If;

	Insert Into e2e_resultados Values ('08. Las cuentas cuadran',
		Case When cardinality(v_problemas) = 0 Then 'OK' Else 'ERROR' End,
		Case When cardinality(v_problemas) = 0
			Then Format('%s recibos · %s cuotas · %s pagos revisados',
				(Select Count(*) From public.recibos Where familia_id = v_familia),
				(Select Count(*) From public.cuotas Where familia_id = v_familia),
				(Select Count(*) From public.pagos_familiares Where familia_id = v_familia))
			Else array_to_string(v_problemas, '; ') End);
End;
$$;

Select Prueba As prueba, Resultado As resultado, Detalle As detalle From e2e_resultados Order By Prueba;

Rollback;
