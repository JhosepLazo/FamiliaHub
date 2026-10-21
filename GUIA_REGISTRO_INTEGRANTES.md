# Cómo registrar a un integrante en FamiliaHub

Cada integrante tiene su propio acceso (usuario y contraseña) y su propio perfil. Nadie comparte cuenta: el administrador invita y cada persona crea su acceso desde el enlace que recibe.

## 1. El administrador genera la invitación

1. Entra a FamiliaHub y abre **Familia**. En el celular: **Perfil > Familia e integrantes**.
2. En **Invitar integrante** completa:
   - **Nombre**: cómo aparecerá en la familia (por ejemplo, "Liliana").
   - **Correo**: el correo real de esa persona. La invitación solo funciona con ese correo.
   - **Rol**: **Integrante** (ve y paga sus cuotas) o **Administrador** (además configura servicios, valida pagos e invita).
3. Pulsa **Generar invitación**. Aparece un enlace: usa **Compartir** o **Copiar** y envíaselo por WhatsApp.

El enlace dura **7 días** y sirve **una sola vez**. Mientras nadie lo use, aparece en **Invitaciones pendientes**, donde puedes **Revocarlo**.

## 2. El integrante crea su acceso

1. Abre el enlace que le enviaron.
2. Si es nuevo, pulsa **Crear mi acceso**. Si ya tenía cuenta, pulsa **Ya tengo cuenta**.
3. Completa el registro:
   - **Correo**: **el mismo** al que llegó la invitación.
   - **Usuario**: con esto entrará siempre. De 3 a 30 caracteres, empieza con una letra y solo usa letras, números, punto, guion o guion bajo. Ejemplo: `Liliana`.
   - **Contraseña**: mínimo 8 caracteres.
4. Si la app pide confirmar el correo, abre el mensaje que llegó y luego vuelve a abrir el enlace de invitación.
5. Pulsa **Aceptar invitación**. Listo: entra a **Inicio** con su familia.

Desde ese momento ingresa en la página de FamiliaHub con su **usuario** y su **contraseña**.

## 3. Su perfil personal

En **Perfil** cada integrante ve y configura lo suyo:

- **Tu información**: puede cambiar su nombre. El usuario y el correo no se cambian ahí.
- **Cómo recibir reembolsos**: sus datos de cobro (por ejemplo, Yape o Plin). Solo se muestran cuando otro integrante realmente le debe dinero.
- **WhatsApp**: **Vincular mi WhatsApp** genera un código. Lo escribe en el grupo familiar como `/vincular CÓDIGO` y desde entonces puede usar `/deuda`, `/vence` y los demás comandos.

En **Mis cuotas** ve cuánto le toca de cada recibo, y en **Pagar** registra sus pagos.

## 4. Cambiar el rol o dar de baja

En **Familia**, junto a cada integrante, el administrador puede cambiar el **rol** (Integrante o Administrador) o el **estado** (Activo o Inactivo). Un integrante inactivo deja de ver la información de la familia y pierde su vínculo de WhatsApp. Si vuelve a activarse, solo tiene que vincular su WhatsApp de nuevo.

La familia siempre debe tener al menos un administrador activo.

## 5. Problemas frecuentes

| Mensaje o situación | Qué hacer |
|---|---|
| "La invitación pertenece a otro correo" | Creó su acceso con un correo distinto. Revoca la invitación y genera otra para el correo con el que se registró. |
| "La invitación venció" o "ya no está disponible" | Genera una invitación nueva. |
| "Ya existe una invitación pendiente para este correo" | Revoca la pendiente en **Invitaciones pendientes** y vuelve a generarla. |
| "Ya perteneces a otra familia activa" | Una persona solo puede estar en una familia activa a la vez. |
| No recuerda su contraseña | En la pantalla de ingreso, **Olvidé mi contraseña** le envía un correo para crear una nueva. |
| No recuerda su usuario | Si aún tiene la sesión abierta, lo ve en **Perfil > Usuario**. Si no, el administrador lo busca en Supabase: **Table Editor > perfiles**, columna `usuario`. |
