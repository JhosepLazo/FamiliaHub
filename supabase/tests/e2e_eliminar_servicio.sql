/*================================================================================
Objetivo:
	Validar eliminar_concepto_servicio: sin dinero movido el servicio se borra; con pagos
	se archiva conservando su historial; con pagos por validar se bloquea.

Requisitos:
	Los mismos de e2e_flujo_familiar.sql (usuarios Jhosep y Liliana sin familia activa).
	Ejecutar como postgres. Todo termina con Rollback.
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

Do $$
Begin
	Insert Into e2e_contexto (Clave, Valor)
	Select 'JHOSEP_USUARIO_ID', id::text From auth.users Where Lower(email) = Lower(Current_Setting('familiahub.e2e_jhosep_email', true)) And email_confirmed_at Is Not Null;
	Insert Into e2e_contexto (Clave, Valor)
	Select 'LILIANA_USUARIO_ID', id::text From auth.users Where Lower(email) = Lower(Current_Setting('familiahub.e2e_liliana_email', true)) And email_confirmed_at Is Not Null;
	If (Select Count(*) From e2e_contexto) <> 2 Then
		Raise Exception 'Configura familiahub.e2e_jhosep_email y familiahub.e2e_liliana_email con cuentas confirmadas.';
	End If;
End;
$$;

-- Ayudantes: actuar como Jhosep (administrador) o Liliana (integrante).
Create Or Replace Function pg_temp.como(p_quien text) Returns void Language plpgsql As $$
Begin
	Perform set_config('request.jwt.claims', Json_Build_Object('sub', (Select Valor From e2e_contexto Where Clave = p_quien || '_USUARIO_ID'), 'role', 'authenticated')::text, true);
End;
$$;

Create Or Replace Function pg_temp.ctx(p_clave text) Returns uuid Language sql As $$
	Select Valor::uuid From e2e_contexto Where Clave = p_clave;
$$;

Grant Execute On Function pg_temp.como(text), pg_temp.ctx(text) To authenticated;

Set Local Role authenticated;
Select pg_temp.como('JHOSEP');

Do $$
Begin
	Insert Into e2e_contexto (Clave, Valor) Values ('FAMILIA_ID', public.crear_familia_inicial('FamiliaHub Eliminar Servicio')::text);
End;
$$;

Reset Role;

Insert Into public.miembros_familia (familia_id, usuario_id, rol, estado)
Values (pg_temp.ctx('FAMILIA_ID'), pg_temp.ctx('LILIANA_USUARIO_ID'), 'INTEGRANTE', 'ACTIVO');

Insert Into e2e_contexto (Clave, Valor)
Select Case When usuario_id = pg_temp.ctx('JHOSEP_USUARIO_ID') Then 'JHOSEP_MIEMBRO_ID' Else 'LILIANA_MIEMBRO_ID' End, id::text
From public.miembros_familia Where familia_id = pg_temp.ctx('FAMILIA_ID');

Set Local Role authenticated;
Select pg_temp.como('JHOSEP');

-- Servicios de prueba. "Historial anterior" empieza el mes pasado para tener pagos en otro periodo.
Do $$
Declare
	v_familia_id uuid := pg_temp.ctx('FAMILIA_ID');
	v_categoria_id uuid;
	v_proveedor_id uuid := (Select id From public.proveedores Where codigo = 'WIN');
	v_plantilla_id uuid := (Select id From public.plantillas_servicio Where codigo = 'INTERNET');
	v_participantes jsonb := Jsonb_Build_Array(
		Jsonb_Build_Object('miembro_id', pg_temp.ctx('JHOSEP_MIEMBRO_ID'), 'modalidad', 'IGUAL', 'valor', Null),
		Jsonb_Build_Object('miembro_id', pg_temp.ctx('LILIANA_MIEMBRO_ID'), 'modalidad', 'IGUAL', 'valor', Null)
	);
	v_hoy date := (timezone('America/Lima', now()))::date;
	v_servicio record;
	v_concepto_id uuid;
Begin
	Select id Into v_categoria_id From public.categorias Where familia_id = v_familia_id And nombre = 'Servicios' And activo;

	Perform public.guardar_metodo_cobro_familiar(v_familia_id, 'YAPE', 'Jhosep', '972583495', 'Prueba sin dinero real.', Null, pg_temp.ctx('JHOSEP_MIEMBRO_ID'));

	For v_servicio In
		Select * From (Values
			('SIN_MOVIMIENTO', 'Sin movimiento', 'MANUAL', Null::numeric, v_hoy),
			('CONFIRMADO', 'Confirmado sin pagos', 'FIJO', 20.00, v_hoy),
			('BORRADOR', 'Con borrador', 'FIJO', 6.00, v_hoy),
			('POR_VALIDAR', 'Con pago por validar', 'FIJO', 8.00, v_hoy),
			('VALIDADO', 'Con pago validado', 'FIJO', 10.00, v_hoy),
			('ANTERIOR', 'Historial anterior', 'FIJO', 12.00, (date_trunc('month', v_hoy) - interval '1 month')::date)
		) As s(clave, nombre, metodo, monto, inicio)
	Loop
		Select public.guardar_concepto_servicio_fase6(
			Null, v_familia_id, v_categoria_id, v_proveedor_id, v_plantilla_id, v_servicio.nombre, 'MENSUAL',
			v_servicio.metodo::public.metodo_obtencion_monto, v_servicio.monto,
			Case When v_servicio.metodo = 'FIJO' Then 'DIA_FIJO' Else 'PROVEEDOR' End::public.tipo_vencimiento_concepto,
			Case When v_servicio.metodo = 'FIJO' Then 28 End::smallint,
			'IGUAL', Null, true, '{}'::jsonb, v_participantes, v_servicio.inicio, 2::smallint
		) Into v_concepto_id;

		Insert Into e2e_contexto (Clave, Valor) Values ('CONCEPTO_' || v_servicio.clave, v_concepto_id::text);
	End Loop;
End;
$$;

Reset Role;

-- Recibo del mes pasado para "Historial anterior" (lo genera el mismo motor de periodos).
Select app_private.sincronizar_periodos_impl(pg_temp.ctx('FAMILIA_ID'), (date_trunc('month', timezone('America/Lima', now())) - interval '1 month')::date + 5);

Insert Into e2e_contexto (Clave, Valor)
Select 'RECIBO_' || c.Clave || Case When pe.anio * 12 + pe.mes < Extract(Year From timezone('America/Lima', now())) * 12 + Extract(Month From timezone('America/Lima', now())) Then '_ANTERIOR' Else '' End, r.id::text
From e2e_contexto c
Join public.recibos r On r.concepto_id = c.Valor::uuid
Join public.periodos pe On pe.id = r.periodo_id
Where c.Clave Like 'CONCEPTO_%';

Update e2e_contexto Set Clave = Replace(Clave, 'RECIBO_CONCEPTO_', 'RECIBO_') Where Clave Like 'RECIBO_CONCEPTO_%';

-- Pagos de Liliana: uno en borrador, uno por validar, uno validado este mes y uno validado el mes pasado.
Set Local Role authenticated;
Select pg_temp.como('LILIANA');

Do $$
Declare
	v_caso record;
	v_cuota public.cuotas%rowtype;
	v_pago_id uuid;
Begin
	For v_caso In Select * From (Values ('BORRADOR', false), ('POR_VALIDAR', true), ('VALIDADO', true), ('ANTERIOR_ANTERIOR', true)) As s(clave, enviar) Loop
		Select * Into v_cuota From public.cuotas
		Where recibo_id = pg_temp.ctx('RECIBO_' || v_caso.clave) And usuario_id = pg_temp.ctx('LILIANA_USUARIO_ID');

		v_pago_id := public.crear_pago_familiar(Jsonb_Build_Array(Jsonb_Build_Object('cuota_id', v_cuota.id, 'monto', v_cuota.saldo_pendiente)), 'YAPE');
		If v_caso.enviar Then
			Perform public.finalizar_pago_familiar(v_pago_id, (timezone('America/Lima', now()))::date, 'PRUEBA-' || v_caso.clave, Null);
		End If;
		Insert Into e2e_contexto (Clave, Valor) Values ('PAGO_' || v_caso.clave, v_pago_id::text);
	End Loop;
End;
$$;

Select pg_temp.como('JHOSEP');
Select public.validar_pago_familiar(pg_temp.ctx('PAGO_VALIDADO'), true, Null);
Select public.validar_pago_familiar(pg_temp.ctx('PAGO_ANTERIOR_ANTERIOR'), true, Null);

/*--------------------------------------------------------------------------------
Pruebas
--------------------------------------------------------------------------------*/

-- 01. Un integrante no puede eliminar.
Select pg_temp.como('LILIANA');
Do $$
Begin
	Perform public.eliminar_concepto_servicio(pg_temp.ctx('CONCEPTO_SIN_MOVIMIENTO'));
	Insert Into e2e_resultados Values ('01. Integrante no elimina', 'ERROR', 'Liliana pudo eliminar un servicio.');
Exception When Others Then
	Insert Into e2e_resultados Values ('01. Integrante no elimina', Case When SqlErrM = 'Solo un administrador puede eliminar servicios.' Then 'OK' Else 'ERROR' End, SqlErrM);
End;
$$;

Select pg_temp.como('JHOSEP');

-- 02. Sin movimiento: se borra todo.
Do $$
Declare
	v_resultado jsonb := public.eliminar_concepto_servicio(pg_temp.ctx('CONCEPTO_SIN_MOVIMIENTO'));
Begin
	Insert Into e2e_resultados Values ('02. Sin movimiento se borra',
		Case When v_resultado ->> 'modo' = 'ELIMINADO'
			And Not Exists (Select 1 From public.conceptos_pago Where id = pg_temp.ctx('CONCEPTO_SIN_MOVIMIENTO'))
			And Not Exists (Select 1 From public.recibos Where id = pg_temp.ctx('RECIBO_SIN_MOVIMIENTO'))
		Then 'OK' Else 'ERROR' End, v_resultado::text);
End;
$$;

-- 03. Confirmado con cuotas pero sin pagos: se borra con sus cuotas.
Do $$
Declare
	v_resultado jsonb := public.eliminar_concepto_servicio(pg_temp.ctx('CONCEPTO_CONFIRMADO'));
Begin
	Insert Into e2e_resultados Values ('03. Confirmado sin pagos se borra',
		Case When v_resultado ->> 'modo' = 'ELIMINADO'
			And Not Exists (Select 1 From public.cuotas Where recibo_id = pg_temp.ctx('RECIBO_CONFIRMADO'))
		Then 'OK' Else 'ERROR' End, v_resultado::text);
End;
$$;

-- 04. Con un pago preparado y nunca enviado: el borrador se descarta y el servicio se borra.
Do $$
Declare
	v_resultado jsonb := public.eliminar_concepto_servicio(pg_temp.ctx('CONCEPTO_BORRADOR'));
Begin
	Insert Into e2e_resultados Values ('04. Borrador se descarta',
		Case When v_resultado ->> 'modo' = 'ELIMINADO'
			And Not Exists (Select 1 From public.pagos_familiares Where id = pg_temp.ctx('PAGO_BORRADOR'))
		Then 'OK' Else 'ERROR' End, v_resultado::text);
End;
$$;

-- 05. Con un pago por validar: se bloquea y no cambia nada.
Do $$
Begin
	Perform public.eliminar_concepto_servicio(pg_temp.ctx('CONCEPTO_POR_VALIDAR'));
	Insert Into e2e_resultados Values ('05. Pago por validar bloquea', 'ERROR', 'Se eliminó con un pago por validar.');
Exception When Others Then
	Insert Into e2e_resultados Values ('05. Pago por validar bloquea',
		Case When SqlErrM Like 'Este servicio tiene pagos por validar.%'
			And Exists (Select 1 From public.conceptos_pago Where id = pg_temp.ctx('CONCEPTO_POR_VALIDAR') And activo And eliminado_at Is Null)
		Then 'OK' Else 'ERROR' End, SqlErrM);
End;
$$;

-- 06. Con un pago validado: se archiva y el recibo pagado se conserva.
Do $$
Declare
	v_resultado jsonb := public.eliminar_concepto_servicio(pg_temp.ctx('CONCEPTO_VALIDADO'));
	v_concepto public.conceptos_pago%rowtype;
Begin
	Select * Into v_concepto From public.conceptos_pago Where id = pg_temp.ctx('CONCEPTO_VALIDADO');
	Insert Into e2e_resultados Values ('06. Con pagos se archiva',
		Case When v_resultado ->> 'modo' = 'ARCHIVADO'
			And (v_resultado ->> 'recibosAnulados')::int = 0
			And Not v_concepto.activo And v_concepto.eliminado_at Is Not Null
			And v_concepto.nombre Like 'Con pago validado (eliminado %'
			And Exists (Select 1 From public.recibos Where id = pg_temp.ctx('RECIBO_VALIDADO') And estado <> 'ANULADO')
			And Exists (Select 1 From public.cuotas Where recibo_id = pg_temp.ctx('RECIBO_VALIDADO') And monto_pagado > 0)
		Then 'OK' Else 'ERROR' End, v_resultado::text || ' · ' || v_concepto.nombre);
End;
$$;

-- 07. El nombre queda libre para un servicio nuevo.
Do $$
Declare
	v_nuevo uuid;
Begin
	v_nuevo := public.guardar_concepto_servicio_fase6(
		Null, pg_temp.ctx('FAMILIA_ID'), (Select id From public.categorias Where familia_id = pg_temp.ctx('FAMILIA_ID') And nombre = 'Servicios'),
		(Select id From public.proveedores Where codigo = 'WIN'), (Select id From public.plantillas_servicio Where codigo = 'INTERNET'),
		'Con pago validado', 'MENSUAL', 'MANUAL', Null, 'PROVEEDOR', Null::smallint, 'IGUAL', Null, true, '{}'::jsonb,
		Jsonb_Build_Array(Jsonb_Build_Object('miembro_id', pg_temp.ctx('JHOSEP_MIEMBRO_ID'), 'modalidad', 'IGUAL', 'valor', Null)),
		(timezone('America/Lima', now()))::date, 2::smallint
	);
	Insert Into e2e_resultados Values ('07. Mismo nombre otra vez', Case When v_nuevo Is Not Null Then 'OK' Else 'ERROR' End, 'Servicio nuevo creado');
Exception When Others Then
	Insert Into e2e_resultados Values ('07. Mismo nombre otra vez', 'ERROR', SqlErrM);
End;
$$;

-- 08. Pagos el mes pasado: se archiva, se anula el recibo de este mes sin movimientos y el anterior queda.
Do $$
Declare
	v_resultado jsonb := public.eliminar_concepto_servicio(pg_temp.ctx('CONCEPTO_ANTERIOR'));
Begin
	Insert Into e2e_resultados Values ('08. Historial anterior',
		Case When v_resultado ->> 'modo' = 'ARCHIVADO'
			And (v_resultado ->> 'recibosAnulados')::int = 1
			And Exists (Select 1 From public.recibos Where id = pg_temp.ctx('RECIBO_ANTERIOR') And estado = 'ANULADO')
			And Exists (Select 1 From public.recibos Where id = pg_temp.ctx('RECIBO_ANTERIOR_ANTERIOR') And estado <> 'ANULADO')
			And Not Exists (Select 1 From public.cuotas Where recibo_id = pg_temp.ctx('RECIBO_ANTERIOR') And estado <> 'ANULADA')
		Then 'OK' Else 'ERROR' End, v_resultado::text);
End;
$$;

-- 09. Eliminar dos veces.
Do $$
Begin
	Perform public.eliminar_concepto_servicio(pg_temp.ctx('CONCEPTO_VALIDADO'));
	Insert Into e2e_resultados Values ('09. Eliminar dos veces', 'ERROR', 'Se eliminó dos veces.');
Exception When Others Then
	Insert Into e2e_resultados Values ('09. Eliminar dos veces', Case When SqlErrM = 'Servicio no disponible.' Then 'OK' Else 'ERROR' End, SqlErrM);
End;
$$;

-- 10. Sincronizar el periodo no recrea recibos de servicios eliminados o archivados.
Do $$
Declare
	v_antes integer := (Select Count(*) From public.recibos Where familia_id = pg_temp.ctx('FAMILIA_ID'));
	v_despues integer;
Begin
	Perform public.sincronizar_periodo_actual(pg_temp.ctx('FAMILIA_ID'));
	v_despues := (Select Count(*) From public.recibos Where familia_id = pg_temp.ctx('FAMILIA_ID'));
	Insert Into e2e_resultados Values ('10. Sincronizar no los revive', Case When v_antes = v_despues Then 'OK' Else 'ERROR' End, v_antes || ' → ' || v_despues || ' recibos');
End;
$$;

Reset Role;

Select Prueba As prueba, Resultado As resultado, Detalle As detalle From e2e_resultados Order By Prueba;

Rollback;
