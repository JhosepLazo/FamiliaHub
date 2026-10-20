# Bot de WhatsApp de FamiliaHub

Proceso Node.js que conecta un número de WhatsApp dedicado (chip propio) al grupo familiar. Es solo una pasarela: recibe comandos del grupo, los envía a la Edge Function `bot-whatsapp` de Supabase y publica las respuestas y los avisos que arma Postgres. No calcula montos ni decide nada.

```text
Grupo de WhatsApp ⇄ bot-whatsapp (este proceso) ⇄ Edge Function bot-whatsapp ⇄ Postgres
```

## Inicio rápido en Windows

Todo se hace con doble clic sobre los archivos `.cmd` de esta carpeta. El resto de este documento explica lo mismo paso a paso y para Linux o macOS.

**La forma más simple: doble clic en `lanzar-bot.cmd`.** Hace los pasos 1 a 4 en orden y salta lo que ya esté hecho:

- instala Node.js y Git si faltan;
- si el proyecto de Supabase está pausado, abre el panel para que lo restaures y espera;
- configura Supabase;
- sube el código a GitHub y lo publica en `main`, preguntándote antes;
- espera a que la app nueva esté en línea;
- enciende el bot y muestra el QR.

Al terminar solo quedan los pasos 5 y 6. El avance queda en `logs/lanzamiento.log`, sin secretos.

Si prefieres hacerlo paso a paso:

| Paso | Qué hacer |
|---|---|
| 1 | Instala Node.js y Git (una vez): `winget install OpenJS.NodeJS.LTS` y `winget install Git.Git`. |
| 2 | **`configurar-supabase.cmd`**: inicia sesión en Supabase, aplica las migraciones, guarda los secretos, publica la función, crea `.env` y comprueba que la función responde. Te pide la contraseña de la base de datos y la dirección web de FamiliaHub. |
| 3 | Sube el código: `git push -u origin fase-12-whatsapp`, abre el Pull Request en GitHub y únelo a `main`. GitHub Actions vuelve a publicar la app con las pantallas de WhatsApp. |
| 4 | **`iniciar-bot.cmd`**: escanea el QR con el celular del chip. El bot queda en segundo plano y se enciende solo cada vez que entras a Windows. |
| 5 | Agrega el número del chip al grupo familiar. En FamiliaHub, un administrador entra a Configuración > Asistente de WhatsApp > **Vincular grupo** y escribe en el grupo `/vincular-grupo CÓDIGO`. |
| 6 | Cada integrante entra a Perfil > WhatsApp > **Vincular mi WhatsApp** y escribe en el grupo `/vincular CÓDIGO`. |

- **`estado-bot.cmd`** muestra si el bot funciona y las últimas líneas de `logs/bot.log`; **`detener-bot.cmd`** lo apaga y quita el inicio automático.
- La PC debe quedar encendida y sin suspenderse: Configuración > Sistema > Energía > Suspender: **Nunca** (al menos con el cargador conectado).
- El inicio automático es una tarea programada de tu usuario (`FamiliaHub Bot WhatsApp`): no necesita permisos de administrador y reinicia el bot si se cae por un error inesperado.

## Requisitos

- Node.js 22.18 o superior (ejecuta TypeScript directamente, sin compilar).
- Un chip dedicado con WhatsApp instalado en un celular. **Nunca uses un número personal.**
- La base de datos con las migraciones de la Fase 12 aplicadas y la Edge Function desplegada (ver más abajo).
- Una máquina encendida 24/7: PC o Raspberry Pi para el piloto, un VPS básico para uso estable. En Railway o Fly.io solo con un volumen persistente para `auth/`.

## 1. Preparar Supabase (una sola vez)

Desde la raíz del repositorio:

```bash
openssl rand -hex 32            # copia el resultado: es el secreto compartido
supabase db push
supabase secrets set FAMILIAHUB_BOT_SECRET=<secreto> APP_URL=https://<tu-app>.vercel.app
supabase functions deploy bot-whatsapp
```

- Si el proyecto está pausado (Supabase pausa los proyectos gratuitos tras 7 días sin uso y su dirección deja de existir), restáuralo en el panel con **Restore project** antes de seguir. Con el bot funcionando no vuelve a pausarse.
- Si `supabase db push` responde `Remote migration versions not found in local migrations directory` con versiones `20261009…`, tu base tiene aplicado el patch anterior del asistente. Recupera sus migraciones y vuelve a ejecutar `db push`:

  ```bash
  git checkout 8d40a1a -- supabase/migrations/20261009120000_whatsapp_vinculos_cola.sql supabase/migrations/20261009121000_whatsapp_avisos.sql supabase/migrations/20261009122000_whatsapp_comandos.sql
  ```

  `20261019115900_fase_12_whatsapp_retirar_patch_anterior.sql` lo retira (tablas, funciones y su job) y `20261019120400_fase_12_whatsapp_recuperar_vinculos.sql` conserva el grupo y los integrantes activos ya vinculados. En una base sin el patch, ambas no hacen nada. `configurar-supabase.cmd` hace esta revisión solo.
- `APP_URL` va sin `/` final.
- `SUPABASE_URL` y la clave de servicio ya existen en el runtime de las Edge Functions; no se configuran a mano y nunca se copian al bot.
- La función usa `verify_jwt = false` (está en `supabase/config.toml`): la protege el encabezado `x-bot-secret`.

Opcional, Fase 7 (preguntas en lenguaje natural):

```bash
supabase secrets set ANTHROPIC_API_KEY=<clave> ANTHROPIC_MODEL=claude-opus-5-5
```

Si `ANTHROPIC_MODEL` no se define, se usa `claude-opus-5-5`. Para gastar menos puedes poner otro modelo. Además, el administrador debe activar el interruptor en Configuración > Asistente de WhatsApp.

## 2. Instalar el bot

```bash
cd bot-whatsapp
cp .env.example .env
npm ci
```

Edita `.env`:

| Variable | Obligatoria | Default | Descripción |
|---|---|---|---|
| `FAMILIAHUB_FUNCTION_URL` | Sí | — | `https://<proyecto>.supabase.co/functions/v1/bot-whatsapp` (o `http://127.0.0.1:54321/functions/v1/bot-whatsapp` con Supabase local) |
| `FAMILIAHUB_BOT_SECRET` | Sí | — | El mismo secreto que guardaste con `supabase secrets set` |
| `AUTH_DIR` | No | `auth` | Carpeta donde se guarda la sesión de WhatsApp |
| `LOG_LEVEL` | No | `warn` | `fatal`, `error`, `warn`, `info`, `debug`, `trace` o `silent` |

Si falta una variable obligatoria, el bot termina al iniciar con un mensaje claro.

## 3. Primer inicio y QR

```bash
npm start
```

1. En la terminal aparece un código QR.
2. En el celular del chip: WhatsApp > Dispositivos vinculados > Vincular dispositivo, y escanea el QR.
3. Cuando aparezca `Conectado a WhatsApp`, agrega el número del chip al grupo familiar.
4. En FamiliaHub, un administrador entra a Configuración > Asistente de WhatsApp > **Vincular grupo** y escribe en el grupo el comando que muestra la app: `/vincular-grupo CÓDIGO`.
5. Cada integrante entra a Perfil > WhatsApp > **Vincular mi WhatsApp** y escribe en el grupo `/vincular CÓDIGO`.

Los códigos duran 10 minutos y sirven una sola vez.

Comprueba que responde escribiendo `/ping` en el grupo (responde `pong 🏠`) y luego `/ayuda`.

## 4. Ejecución continua con pm2

```bash
npm install -g pm2
pm2 start npm --name familiahub-bot --stop-exit-codes 1 -- start
pm2 save
pm2 startup        # sigue la instrucción que imprime para arrancar con el sistema
```

`--stop-exit-codes 1` evita reinicios en bucle cuando la sesión se cierra desde el teléfono o falta configuración: en esos casos el bot sale con código 1 a propósito.

Códigos de salida del bot:

| Código | Significado | pm2 y la tarea de Windows |
|---|---|---|
| `0` | Detenido a propósito (Ctrl+C, `pm2 stop`, SIGTERM) | No reinician |
| `1` | Necesita intervención: falta configuración o la sesión se cerró desde el teléfono | No reinician |
| `2` | Error inesperado | Reinician |

En Windows no hace falta pm2: `iniciar-bot.cmd` registra una tarea programada que hace lo mismo (ver [Inicio rápido en Windows](#inicio-rápido-en-windows)).

Comandos útiles:

```bash
pm2 logs familiahub-bot      # errores y avisos del proceso
pm2 restart familiahub-bot
pm2 stop familiahub-bot      # SIGTERM: el bot cierra la conexión y sale con código 0
```

## Qué hace el bot

- Solo atiende el grupo vinculado. Nunca escribe por privado.
- Procesa únicamente mensajes de texto que empiezan con `/`, que lo mencionan o que responden a un mensaje suyo. Ignora multimedia, reacciones, encuestas, mensajes editados o eliminados, y todo mensaje con más de 10 minutos de antigüedad (por ejemplo, lo que llegó mientras estuvo apagado).
- No guarda mensajes. En los logs solo registra el grupo abreviado, el comando, la duración y los errores.
- Límites: 5 comandos por minuto por persona; 1 respuesta por hora en grupos no vinculados; en lenguaje natural, 3 preguntas por minuto por persona y 20 por hora por grupo. Lo que supera el límite se ignora en silencio.
- Envía con ritmo humano: indicador "escribiendo" de 1 a 2,5 segundos y al menos 2 segundos entre dos mensajes.
- Cada 60 segundos pide los avisos pendientes (dentro del horario de la familia) y los publica; cada 5 minutos registra un heartbeat que la app muestra como "Activo".
- Si lo retiran del grupo, desvincula el grupo en FamiliaHub y se expiran sus avisos pendientes.
- Si se corta la conexión, reintenta con espera creciente (3 s, 6 s, 12 s… hasta 60 s).

Comandos disponibles en el grupo: `/ping`, `/ayuda`, `/vincular-grupo CÓDIGO`, `/vincular CÓDIGO`, `/desvincular`, `/yo`, `/deuda`, `/vence`, `/recibos`, `/recibo TEXTO`, `/pendientes`, `/resumen`, `/pagar`, `/porvalidar` y `/avisos estado|pausar|reanudar`. No distinguen mayúsculas ni tildes.

## Pruebas

```bash
npm test
```

Ejecuta `test/mensajes.test.ts` (extracción de texto y filtros) y `test/control.test.ts` (deduplicación, límites y espera exponencial) con `node --test`.

Las pruebas de base de datos están en `supabase/tests/e2e_whatsapp.sql` (ver `supabase/tests/README.md`).

## Probar la Edge Function con curl

Define primero:

```bash
FN=https://<proyecto>.supabase.co/functions/v1/bot-whatsapp
SECRETO=<secreto>
```

**mensaje** (lo que envía el bot por cada comando):

```bash
curl -s -X POST "$FN" -H "content-type: application/json" -H "x-bot-secret: $SECRETO" \
  -d '{"accion":"mensaje","grupoId":"120363000000000001@g.us","remitenteIds":["100000000000001@lid"],"texto":"/ayuda","mencionaBot":false,"respondeBot":false}'
# → {"respuesta":{"texto":"🏠 *FamiliaHub* — esto puedo hacer…","menciones":[]},"grupoVinculado":true}
```

**avisos_tomar** (reserva hasta `limite` avisos durante 5 minutos):

```bash
curl -s -X POST "$FN" -H "content-type: application/json" -H "x-bot-secret: $SECRETO" \
  -d '{"accion":"avisos_tomar","limite":5}'
# → {"avisos":[{"id":"…","grupoId":"…@g.us","texto":"…","menciones":["…"]}]}
```

**avisos_marcar**:

```bash
curl -s -X POST "$FN" -H "content-type: application/json" -H "x-bot-secret: $SECRETO" \
  -d '{"accion":"avisos_marcar","id":"<uuid-del-aviso>","enviado":true,"error":null}'
# → {"ok":true}
```

**grupo_salida**:

```bash
curl -s -X POST "$FN" -H "content-type: application/json" -H "x-bot-secret: $SECRETO" \
  -d '{"accion":"grupo_salida","grupoId":"120363000000000001@g.us"}'
# → {"ok":true}
```

**heartbeat**:

```bash
curl -s -X POST "$FN" -H "content-type: application/json" -H "x-bot-secret: $SECRETO" \
  -d '{"accion":"heartbeat","version":"1.0.0"}'
# → {"ok":true}
```

Casos de error:

```bash
# 401 sin secreto
curl -s -X POST "$FN" -H "content-type: application/json" -d '{"accion":"heartbeat"}'
# → {"error":"No autorizado."}

# 400 con acción desconocida
curl -s -X POST "$FN" -H "content-type: application/json" -H "x-bot-secret: $SECRETO" -d '{"accion":"borrar"}'
# → {"error":"Solicitud inválida."}

# Mensaje de negocio devuelto como respuesta (HTTP 200): código inválido
curl -s -X POST "$FN" -H "content-type: application/json" -H "x-bot-secret: $SECRETO" \
  -d '{"accion":"mensaje","grupoId":"120363000000000001@g.us","remitenteIds":["100000000000001@lid"],"texto":"/vincular AAAAAA","mencionaBot":false,"respondeBot":false}'
# → {"respuesta":{"texto":"Código inválido o vencido. Genera uno nuevo en FamiliaHub.","menciones":[]},"grupoVinculado":true}
```

Otros códigos: `405` si el método no es POST, `400` si el cuerpo no es JSON o pesa más de 10 KB, `500` ante un error interno (el detalle queda en los logs de la función: `supabase functions logs bot-whatsapp`).

## Desarrollo local

```bash
supabase start
supabase functions serve bot-whatsapp --env-file supabase/functions/.env   # con FAMILIAHUB_BOT_SECRET y APP_URL
```

Y en `bot-whatsapp/.env`: `FAMILIAHUB_FUNCTION_URL=http://127.0.0.1:54321/functions/v1/bot-whatsapp`. Ese archivo `.env` de funciones tampoco se sube al repositorio.

## Seguridad

- La carpeta `auth/` equivale a tener el WhatsApp del chip abierto. Está en `.gitignore`, el bot la crea con permisos `700` (solo su usuario; en Windows, `iniciar-bot.cmd` y `configurar-supabase.cmd` dejan `auth/` y `.env` legibles solo por tu usuario) y conviene respaldarla **cifrada** (por ejemplo `tar czf - auth | gpg -c > auth.tar.gz.gpg`).
- El bot solo conoce la URL de la función y el secreto compartido. La clave de servicio de Supabase nunca sale del runtime de Supabase.
- Los permisos (quién es administrador, quién puede validar) se revisan en Postgres, no en el bot.
- Si sospechas que el secreto se filtró: genera uno nuevo, actualízalo con `supabase secrets set` y en `.env`, y reinicia el bot.

## Riesgo de bloqueo del número

1. Usa siempre un chip dedicado.
2. El bot solo responde a comandos y menciones, solo en el grupo vinculado, con pausas humanas y dentro del horario configurado.
3. **Abre WhatsApp en el celular del chip al menos una vez por semana.** WhatsApp cierra los dispositivos vinculados si el teléfono principal pasa unos 14 días sin uso.

## Monitoreo

- Configuración > Asistente de WhatsApp muestra "Bot: Activo" si hubo heartbeat en los últimos 10 minutos; si no, desde cuándo no hay conexión.
- Avisos que fallaron 3 veces quedan en estado `ERROR` con el motivo en la columna `error`:

  ```sql
  select created_at, tipo, error from public.avisos_whatsapp where estado = 'ERROR' order by created_at desc limit 20;
  ```

- `pm2 logs familiahub-bot` para los errores del proceso; en Windows, `estado-bot.cmd` o el archivo `logs/bot.log` (el anterior queda en `logs/bot.anterior.log` al pasar de 5 MB).

## Recuperación

| Situación | Qué hacer |
|---|---|
| El bot muestra "Sesión cerrada desde el teléfono…" y se detiene | Borra la carpeta `auth/`, ejecuta `npm start` (o `pm2 restart familiahub-bot`; en Windows, `iniciar-bot.cmd`) y escanea el QR de nuevo |
| Se perdió o bloquearon el número | Consigue un chip nuevo, borra `auth/`, escanea el QR con el nuevo número y agrégalo al **mismo** grupo. No hace falta volver a vincular nada |
| La familia crea un grupo nuevo | El administrador desvincula el grupo anterior en la app, agrega el bot al nuevo y lo vincula. Los integrantes conservan su vínculo |
| El bot estuvo apagado varias horas | Al volver no responde mensajes de más de 10 minutos ni publica avisos vencidos o eventos de más de 12 horas |
| La app dice "Sin conexión" pero el proceso corre | Revisa `pm2 logs`: suele ser falta de internet o un secreto distinto entre `.env` y Supabase (la función responde 401) |
| Hay que mover el bot a otra máquina | Copia `bot-whatsapp/` con `.env` y `auth/`, ejecuta `npm ci` y arráncalo; si no copias `auth/`, escanea el QR otra vez |

Riesgo aceptado: si el bot se cae justo después de enviar un aviso y antes de confirmarlo, ese aviso puede repetirse una vez cuando venza su reserva de 5 minutos.
