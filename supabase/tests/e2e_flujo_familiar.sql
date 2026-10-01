/*================================================================================
Objetivo:
	Validar de extremo a extremo la autorización financiera de FamiliaHub con dos
	usuarios reales de Supabase Auth, sin conocer ni almacenar sus contraseñas.

Requisitos:
	1. Ambos usuarios deben existir y tener el correo confirmado.
	2. Sus perfiles deben tener usuario definido.
	3. Ejecutar como rol postgres/service de mantenimiento.
	4. Configurar los correos solo en la sesión; no se guardan en el repositorio.

Ejemplo previo:
	Select set_config('familiahub.e2e_jhosep_email', '<correo-admin>', false);
	Select set_config('familiahub.e2e_liliana_email', '<correo-integrante>', false);

Importante:
	- Todo el escenario financiero se ejecuta dentro de una transacción y termina
	  con Rollback.
	- No crea movimientos reales ni conserva recibos/pagos de prueba.
	- La invitación por correo se valida aparte mediante las Edge Functions porque
	  requiere una llamada HTTP autenticada.
================================================================================*/

Begin;

Create Temp Table e2e_contexto
(
	Clave varchar(40) Primary Key,
	Valor uuid Not Null
) On Commit Drop;

Create Temp Table e2e_resultados
(
	Prueba varchar(120) Not Null,
	Resultado varchar(20) Not Null,
	Detalle text Null
) On Commit Drop;

Grant Select, Insert, Update On e2e_contexto, e2e_resultados To authenticated;

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

	Select id, email_confirmed_at
	Into v_jhosep_id, v_confirmado_jhosep
	From auth.users
	Where Lower(email) = Lower(v_correo_jhosep);

	Select id, email_confirmed_at
	Into v_liliana_id, v_confirmado_liliana
	From auth.users
	Where Lower(email) = Lower(v_correo_liliana);

	If v_jhosep_id Is Null Or v_liliana_id Is Null Then
		Raise Exception 'Ambas cuentas deben existir en Supabase Auth antes del E2E.';
	End If;

	If v_confirmado_jhosep Is Null Or v_confirmado_liliana Is Null Then
		Raise Exception 'Ambos correos deben estar confirmados antes del E2E.';
	End If;

	Select usuario Into v_usuario_jhosep From public.perfiles Where id = v_jhosep_id;
	Select usuario Into v_usuario_liliana From public.perfiles Where id = v_liliana_id;

	If Lower(Coalesce(v_usuario_jhosep, '')) <> 'jhosep'
		Or Lower(Coalesce(v_usuario_liliana, '')) <> 'liliana' Then
		Raise Exception 'Los perfiles deben usar los usuarios Jhosep y Liliana.';
	End If;

	Insert Into e2e_contexto (Clave, Valor)
	Values
		('JHOSEP_USUARIO_ID', v_jhosep_id),
		('LILIANA_USUARIO_ID', v_liliana_id);

	Insert Into e2e_resultados (Prueba, Resultado, Detalle)
	Values ('Auth y perfiles', 'OK', 'Usuarios reales, correos confirmados y usernames correctos.');
End;
$$;

Set Local Role authenticated;

Select set_config(
	'request.jwt.claims',
	Json_Build_Object(
		'sub', (Select Valor::text From e2e_contexto Where Clave = 'JHOSEP_USUARIO_ID'),
		'role', 'authenticated'
	)::text,
	true
);

Do $$
Declare
	v_familia_id uuid;
	v_jhosep_id uuid := (Select Valor From e2e_contexto Where Clave = 'JHOSEP_USUARIO_ID');
Begin
	Select public.crear_familia_inicial('FamiliaHub E2E')
	Into v_familia_id;

	Insert Into e2e_contexto (Clave, Valor)
	Values ('FAMILIA_ID', v_familia_id);

	Insert Into e2e_contexto (Clave, Valor)
	Select 'JHOSEP_MIEMBRO_ID', id
	From public.miembros_familia
	Where familia_id = v_familia_id
		and usuario_id = v_jhosep_id
		and rol = 'ADMINISTRADOR'
		and estado = 'ACTIVO';

	If Not Exists (Select 1 From e2e_contexto Where Clave = 'JHOSEP_MIEMBRO_ID') Then
		Raise Exception 'crear_familia_inicial no creó correctamente al administrador.';
	End If;

	Insert Into e2e_resultados (Prueba, Resultado, Detalle)
	Values ('Crear familia inicial', 'OK', 'Jhosep quedó como ADMINISTRADOR.');
End;
$$;

Reset Role;

Insert Into public.miembros_familia
(
	familia_id,
	usuario_id,
	rol,
	estado
)
Values
(
	(Select Valor From e2e_contexto Where Clave = 'FAMILIA_ID'),
	(Select Valor From e2e_contexto Where Clave = 'LILIANA_USUARIO_ID'),
	'INTEGRANTE',
	'ACTIVO'
);

Insert Into e2e_contexto (Clave, Valor)
Select
	'LILIANA_MIEMBRO_ID',
	id
From public.miembros_familia
Where familia_id = (Select Valor From e2e_contexto Where Clave = 'FAMILIA_ID')
	and usuario_id = (Select Valor From e2e_contexto Where Clave = 'LILIANA_USUARIO_ID')
	and rol = 'INTEGRANTE'
	and estado = 'ACTIVO';

Insert Into e2e_resultados (Prueba, Resultado, Detalle)
Values ('Membresía Liliana', 'OK', 'Membresía de prueba creada dentro de la transacción.');

Set Local Role authenticated;

Select set_config(
	'request.jwt.claims',
	Json_Build_Object(
		'sub', (Select Valor::text From e2e_contexto Where Clave = 'JHOSEP_USUARIO_ID'),
		'role', 'authenticated'
	)::text,
	true
);

Do $$
Declare
	v_familia_id uuid := (Select Valor From e2e_contexto Where Clave = 'FAMILIA_ID');
	v_jhosep_miembro_id uuid := (Select Valor From e2e_contexto Where Clave = 'JHOSEP_MIEMBRO_ID');
	v_liliana_miembro_id uuid := (Select Valor From e2e_contexto Where Clave = 'LILIANA_MIEMBRO_ID');
	v_categoria_id uuid;
	v_proveedor_id uuid;
	v_plantilla_id uuid;
	v_concepto_id uuid;
	v_recibo_id uuid;
	v_cuota_liliana_id uuid;
Begin
	Select id
	Into v_categoria_id
	From public.categorias
	Where familia_id = v_familia_id
		and nombre = 'Servicios'
		and activo = true;

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
		'Prueba E2E FamiliaHub',
		'MENSUAL',
		'FIJO',
		2.00,
		'DIA_FIJO',
		28,
		'IGUAL',
		Null,
		false,
		'{}'::jsonb,
		Json_Build_Array(
			Json_Build_Object('miembro_id', v_jhosep_miembro_id, 'modalidad', 'IGUAL', 'valor', Null),
			Json_Build_Object('miembro_id', v_liliana_miembro_id, 'modalidad', 'IGUAL', 'valor', Null)
		),
		(timezone('America/Lima', now()))::date,
		2
	)
	Into v_concepto_id;

	Select id
	Into v_recibo_id
	From public.recibos
	Where familia_id = v_familia_id
		and concepto_id = v_concepto_id
	Order By created_at Desc
	Limit 1;

	Select id
	Into v_cuota_liliana_id
	From public.cuotas
	Where recibo_id = v_recibo_id
		and usuario_id = (Select Valor From e2e_contexto Where Clave = 'LILIANA_USUARIO_ID');

	If v_recibo_id Is Null Or v_cuota_liliana_id Is Null Then
		Raise Exception 'No se generaron correctamente el recibo o la cuota de Liliana.';
	End If;

	Insert Into e2e_contexto (Clave, Valor)
	Values
		('CONCEPTO_ID', v_concepto_id),
		('RECIBO_ID', v_recibo_id),
		('CUOTA_LILIANA_ID', v_cuota_liliana_id);

	Insert Into e2e_resultados (Prueba, Resultado, Detalle)
	Values ('Servicio y cuotas', 'OK', 'Recibo S/2.00 dividido entre Jhosep y Liliana.');
End;
$$;

Select set_config(
	'request.jwt.claims',
	Json_Build_Object(
		'sub', (Select Valor::text From e2e_contexto Where Clave = 'LILIANA_USUARIO_ID'),
		'role', 'authenticated'
	)::text,
	true
);

Do $$
Declare
	v_pago_id uuid;
	v_saldo numeric;
Begin
	Select saldo_pendiente
	Into v_saldo
	From public.cuotas
	Where id = (Select Valor From e2e_contexto Where Clave = 'CUOTA_LILIANA_ID');

	Select public.crear_pago_familiar(
		Json_Build_Array(
			Json_Build_Object(
				'cuota_id', (Select Valor From e2e_contexto Where Clave = 'CUOTA_LILIANA_ID'),
				'monto', v_saldo
			)
		),
		'YAPE'
	)
	Into v_pago_id;

	Perform public.finalizar_pago_familiar(
		v_pago_id,
		(timezone('America/Lima', now()))::date,
		'PRUEBA-E2E-SIN-MOVIMIENTO-REAL',
		Null
	);

	Insert Into e2e_contexto (Clave, Valor)
	Values ('PAGO_ID', v_pago_id);

	Insert Into e2e_resultados (Prueba, Resultado, Detalle)
	Values ('Pago Liliana', 'OK', 'Pago Yape enviado y pendiente de validación.');
End;
$$;

Do $$
Begin
	Begin
		Perform public.validar_pago_familiar(
			(Select Valor From e2e_contexto Where Clave = 'PAGO_ID'),
			true,
			Null
		);

		Insert Into e2e_resultados (Prueba, Resultado, Detalle)
		Values ('Autovalidación Liliana', 'ERROR', 'Liliana pudo validar su propio pago.');
	Exception
		When Others Then
			Insert Into e2e_resultados (Prueba, Resultado, Detalle)
			Values ('Autovalidación Liliana', 'OK', SqlErrM);
	End;

	Begin
		Perform public.cambiar_estado_concepto(
			(Select Valor From e2e_contexto Where Clave = 'CONCEPTO_ID'),
			false
		);

		Insert Into e2e_resultados (Prueba, Resultado, Detalle)
		Values ('Permiso admin de Liliana', 'ERROR', 'Liliana pudo administrar un servicio.');
	Exception
		When Others Then
			Insert Into e2e_resultados (Prueba, Resultado, Detalle)
			Values ('Permiso admin de Liliana', 'OK', SqlErrM);
	End;
End;
$$;

Select set_config(
	'request.jwt.claims',
	Json_Build_Object(
		'sub', (Select Valor::text From e2e_contexto Where Clave = 'JHOSEP_USUARIO_ID'),
		'role', 'authenticated'
	)::text,
	true
);

Do $$
Declare
	v_pagado numeric;
	v_saldo numeric;
	v_estado text;
Begin
	Perform public.validar_pago_familiar(
		(Select Valor From e2e_contexto Where Clave = 'PAGO_ID'),
		true,
		Null
	);

	Select monto_pagado, saldo_pendiente, estado::text
	Into v_pagado, v_saldo, v_estado
	From public.cuotas
	Where id = (Select Valor From e2e_contexto Where Clave = 'CUOTA_LILIANA_ID');

	If v_pagado <> 1.00 Or v_saldo <> 0 Or v_estado <> 'PAGADA' Then
		Raise Exception 'La cuota no quedó pagada correctamente. Pagado %, saldo %, estado %.', v_pagado, v_saldo, v_estado;
	End If;

	Insert Into e2e_resultados (Prueba, Resultado, Detalle)
	Values ('Validación Jhosep', 'OK', 'Jhosep validó y la cuota de Liliana quedó PAGADA.');
End;
$$;

Do $$
Declare
	v_pagado numeric;
	v_saldo numeric;
	v_estado text;
Begin
	Perform public.anular_pago_familiar(
		(Select Valor From e2e_contexto Where Clave = 'PAGO_ID'),
		'Cierre automático de prueba E2E.'
	);

	Select monto_pagado, saldo_pendiente, estado::text
	Into v_pagado, v_saldo, v_estado
	From public.cuotas
	Where id = (Select Valor From e2e_contexto Where Clave = 'CUOTA_LILIANA_ID');

	If v_pagado <> 0 Or v_saldo <> 1.00 Or v_estado <> 'PENDIENTE' Then
		Raise Exception 'La reversión no restauró la cuota. Pagado %, saldo %, estado %.', v_pagado, v_saldo, v_estado;
	End If;

	Insert Into e2e_resultados (Prueba, Resultado, Detalle)
	Values ('Reversión de pago', 'OK', 'El pago se anuló y la cuota volvió a PENDIENTE.');
End;
$$;

Reset Role;

Select
	Prueba,
	Resultado,
	Detalle
From e2e_resultados
Order By Prueba;

Rollback;
