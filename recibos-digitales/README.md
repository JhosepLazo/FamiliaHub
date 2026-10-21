# Recibos digitales automáticos

Cuando SEDAPAL, Luz del Sur o Cálidda envían su recibo digital al Gmail de la familia, un script en ese Gmail
lee el **número de suministro**, el **monto** y la **fecha de vencimiento** y se los manda a FamiliaHub.
Si el suministro coincide con un servicio y todo cuadra, FamiliaHub confirma solo el recibo del mes, reparte
las cuotas y el grupo de WhatsApp recibe el aviso como siempre. Nadie escribe el monto.

El script solo envía esos tres datos y el identificador del correo, nunca el texto del correo.

## 1. Afíliate al recibo digital

Hazlo con el Gmail donde vas a instalar el script (puede ser el tuyo):

| Empresa | Dónde afiliarse |
|---|---|
| SEDAPAL | https://www.gob.pe/12767-afiliarse-al-recibo-digital-de-sedapal |
| Luz del Sur | https://www.luzdelsur.pe/es/ReciboDigital |
| Cálidda | https://www.calidda.com.pe/recibo-digital |

En FamiliaHub, cada servicio debe tener registrado su número de suministro (**Administrar → Servicios**).
Así se sabe a qué servicio pertenece cada correo.

## 2. Activa FamiliaHub

Doble clic en **`activar.cmd`** (en esta carpeta). En unos minutos:

1. aplica en la base la migración de recibos digitales (confirma con **Y**);
2. crea una clave que solo conocen tu Gmail y FamiliaHub, y la guarda en Supabase;
3. publica la función `recibos-digitales` y comprueba que responde;
4. completa el script de Gmail con la dirección y la clave y lo **copia al portapapeles**.

Se puede ejecutar otra vez sin problema: reutiliza la misma clave.

## 3. Instala el script en Gmail

1. Abre https://script.new con **el Gmail donde llegan los recibos**.
2. Borra lo que aparece, pega con **Ctrl+V** y guarda con **Ctrl+S** (nombre sugerido: *FamiliaHub Recibos*).
3. En la lista de funciones de arriba elige **`instalar`** y pulsa **Ejecutar**.
4. Google pedirá permisos: *Revisar permisos* → tu cuenta → *Configuración avanzada* →
   *Ir a FamiliaHub Recibos (no seguro)* → *Permitir*. El aviso sale porque el script es tuyo y no pasó por
   la revisión de Google; solo lo usa tu cuenta.
5. En el registro debe aparecer **"Conectado con FamiliaHub"**. Desde ahí revisa el correo cada hora.

No pegues `RecibosDigitales.gs` de esta carpeta: es la plantilla, sin la dirección ni la clave. Si se te borró
el portapapeles, el script ya completado está en `%LOCALAPPDATA%\FamiliaHub\RecibosDigitales-listo.gs`
(ábrelo con el Bloc de notas y copia todo). No lo subas a ningún lado: tiene la clave.

## Qué pasa con cada recibo

Lo ves en **Recibos → Recibos digitales** (solo administradores).

| Estado | Cuándo | Qué hacer |
|---|---|---|
| **Confirmado solo** | El suministro coincide con un servicio, el recibo del mes espera su monto y el monto es parecido a los anteriores. | Nada. |
| **En espera** | Llegó el correo pero FamiliaHub aún no creó el recibo del mes. Se reintenta solo cada hora. | Nada. |
| **Revisar** | El monto es más del triple o menos de la tercera parte del anterior, la fecha no es razonable o el suministro está en dos servicios. | Confirma el monto en la app, como antes. |
| **Ignorado** | El recibo ya tenía monto o no hubo recibo de ese mes. | Nada. |

Si el suministro del correo no coincide con ningún servicio, el correo no aparece en la lista: revisa que el
número esté bien escrito en el servicio.

En Gmail, los correos leídos quedan con la etiqueta **FamiliaHub/Recibo leído**. Los que no se pudieron leer
completos (falta el monto, el vencimiento o el suministro) quedan con **FamiliaHub/Revisar**; para esos,
confirma el monto en la app.

FamiliaHub nunca adivina un monto: si algo no cuadra, el recibo se queda esperando como siempre.

## Si un correo no se lee bien

Cada empresa escribe sus correos a su manera. En el editor del script, elige la función **`probar`** y pulsa
**Ejecutar**: muestra en el registro lo que leería del último correo de cada empresa, sin enviar nada. Si algo
sale vacío o mal, ese es el correo que hay que revisar para ajustar el script.
