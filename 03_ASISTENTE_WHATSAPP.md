# FamiliaHub — Asistente familiar en WhatsApp

> Estado: Código completo (12.1 a 12.5). Pendiente despliegue 24/7 (12.6) y validación con el chip dedicado.  
> Proyecto: FamiliaHub  
> Fase: 12 — Notificaciones, canal adicional WhatsApp  
> Canal: Grupo de WhatsApp familiar existente  
> Rama: `fase-12-whatsapp`  
> Principio: El bot es una pasarela. Toda la lógica, los cálculos y los permisos viven en Supabase.

---

## 1. Objetivo

Convertir FamiliaHub en un asistente que participa en el grupo de WhatsApp familiar como un integrante más, para que la familia reciba avisos y resuelva sus dudas de pagos sin abrir la aplicación ni calcular nada.

El asistente debe:

1. avisar automáticamente cuando un recibo está por vencer o ya venció;
2. indicar en cada aviso el monto total, cuánto falta recaudar y quiénes tienen saldo pendiente;
3. responder consultas de cada integrante: cuánto debe, qué vence pronto y cómo va el mes;
4. identificar a cada integrante por su WhatsApp de forma segura;
5. funcionar sin intervención humana una vez configurado.

### Criterio de éxito

Las preguntas que hoy circulan en el grupo y que dieron origen al proyecto se responden solas:

- ¿Cuánto llegó la luz?
- ¿Cuánto me toca pagar?
- ¿Quién ya pagó?
- ¿Cuánto falta recaudar?
- ¿Cuándo vence?

Esto aplica la regla principal del producto:

> Si FamiliaHub puede obtener, calcular, distribuir, recordar o actualizar algo automáticamente, no debe pedirle al usuario que lo haga manualmente.

---

## 2. Situación del proyecto

### Lo que ya existía y se reutiliza

| Pieza | Ubicación | Uso en el asistente |
|---|---|---|
| Motor de periodos, recibos y cuotas | `app_private.*` (Fase 6) | Fuente única de montos, saldos y estados |
| Ciclo diario | `pg_cron` → `app_private.procesar_ciclo_diario()` a las 05:10 UTC | Actualiza estados antes de los avisos |
| Fecha objetivo de pago | `fecha_limite_aporte ?? fecha_vencimiento` | Misma regla que usa Inicio y Mis cuotas |
| Snapshot de participantes | `cuotas.nombre_miembro`, `cuotas.saldo_pendiente` | Detalle de quién debe cuánto |
| Edge Functions en Deno | `supabase/functions/*` | Patrón para la función del bot |
| RLS por familia | Todas las tablas | Aislamiento entre familias |

`fecha_limite_aporte` se calcula como `fecha_vencimiento - dias_anticipacion_aporte`. El asistente usa la misma fecha objetivo que la app para que nunca se contradigan.

### Lo que agrega esta fase

- Vínculo entre el grupo de WhatsApp y la familia.
- Vínculo entre cada integrante y su identidad de WhatsApp.
- Cola de avisos de salida con reintentos.
- Comandos de consulta resueltos en la base de datos.
- Edge Function `bot-whatsapp` como única puerta del bot.
- Proceso del bot conectado a WhatsApp.
- Pantallas para vincular el grupo (Configuración) y cada WhatsApp (Perfil).

---

## 3. Alcance

### El asistente hace (V1)

- Enviar avisos automáticos de recibos por vencer y vencidos al grupo vinculado.
- Responder comandos de consulta: deuda personal, próximos vencimientos y resumen del mes.
- Vincular el grupo y a cada integrante mediante códigos de un solo uso.
- Respetar una ventana horaria de envío.

### El asistente no hace (V1)

- Registrar pagos, validar aportes ni subir comprobantes. Eso sigue en la app, porque requiere comprobante, revisión y trazabilidad.
- Conversar sobre temas generales. No es un chat; solo atiende comandos o menciones.
- Leer, guardar ni analizar mensajes del grupo que no sean comandos.
- Operar en chats privados.
- Enviar QR ni datos de cuentas receptoras.

---

## 4. Restricción del canal y decisión técnica

### 4.1 API oficial de WhatsApp

Meta ofrece una Groups API en la Cloud API, pero con condiciones que la hacen inviable para una familia:

- requiere una Official Business Account (cuenta verificada con insignia);
- los grupos admiten como máximo 8 participantes;
- el grupo lo crea el negocio y solo se ingresa por enlace de invitación;
- no permite agregar el bot a un grupo que ya existe.

### 4.2 Opciones evaluadas

| Opción | Grupo actual | Costo | Riesgo | Decisión |
|---|---|---|---|---|
| A. Número dedicado + Baileys | Sí, entra como integrante | Chip + hosting | Baneo del número | **Elegida** |
| B. API oficial, mensajes 1:1 | No, avisos en privado | Verificación + costo por plantilla | Bajo | Plan de contingencia |
| C. Bot de Telegram | Solo si la familia migra | Gratis | Ninguno | Descartada por adopción |

### 4.3 Consecuencias aceptadas de la opción A

- Baileys es una librería no oficial. Usarla puede violar los términos de WhatsApp y el número del bot puede ser baneado.
- Por eso se usa un chip dedicado, nunca un número personal.
- El bot es una pasarela delgada: si se pierde el número, se reemplaza el conector sin tocar la lógica ni la base de datos.

---

## 5. Arquitectura

```text
┌──────────────────────────────┐
│   Grupo WhatsApp familiar    │
└──────────────┬───────────────┘
               │ mensajes / avisos
┌──────────────▼───────────────┐
│ bot-whatsapp                 │  Node + Baileys
│ - sesión en auth/            │  Proceso 24/7
│ - solo comandos y avisos     │  Chip dedicado
└──────────────┬───────────────┘
               │ HTTPS + secreto compartido
┌──────────────▼───────────────┐
│ Edge Function bot-whatsapp   │  Supabase
│ - valida secreto             │
│ - llama funciones de BD      │
└──────────────┬───────────────┘
               │ rpc (service_role)
┌──────────────▼───────────────┐
│ Postgres                     │
│ - whatsapp_vinculos          │
│ - avisos_whatsapp            │
│ - app_private.* (lógica)     │
│ - pg_cron (genera avisos)    │
└──────────────────────────────┘
```

### 5.1 Componentes

| Componente | Dónde corre | Responsabilidad | Estado |
|---|---|---|---|
| `bot-whatsapp/` | PC, Raspberry o VPS 24/7 | Conectar, recibir comandos, enviar avisos | Implementado |
| Edge Function `bot-whatsapp` | Supabase | Autenticar al bot, enrutar acciones a la BD | Implementado |
| `whatsapp_vinculos` | Postgres | Grupo ↔ familia, integrante ↔ WhatsApp | Implementado |
| `avisos_whatsapp` | Postgres | Cola de salida idempotente | Implementado |
| Funciones de vinculación | Postgres | Generar y consumir códigos | Implementado |
| Funciones de avisos y consultas | Postgres | Generar avisos, responder comandos | Implementado |
| `WhatsappVinculo` | React (Configuración y Perfil) | Generar código y mostrar el estado del vínculo | Implementado |

### 5.2 Reglas de arquitectura

1. El bot no calcula montos, no decide estados y no conoce reglas de negocio.
2. El bot nunca tiene la clave secreta de Supabase. Solo conoce la URL de la Edge Function y un secreto compartido.
3. Los textos de avisos y respuestas se arman en la base de datos, igual que los mensajes de error existentes.
4. Toda operación del bot pasa por una única Edge Function con acciones definidas.
5. Las tablas del canal no tienen acceso para `anon` ni `authenticated`.
6. La ventana horaria también vive en la base de datos: fuera de horario la cola no entrega avisos.

---

## 6. Modelo de datos

Migraciones:

- `supabase/migrations/20261009120000_whatsapp_vinculos_cola.sql` — tablas, códigos y vinculación.
- `supabase/migrations/20261009121000_whatsapp_avisos.sql` — reglas, cola de avisos y job de `pg_cron`.
- `supabase/migrations/20261009122000_whatsapp_comandos.sql` — comandos de consulta.

### 6.1 `whatsapp_vinculos`

Una fila por grupo de cada familia y una fila por integrante.

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | uuid | Clave primaria |
| `familia_id` | uuid | Familia dueña del vínculo |
| `tipo` | `GRUPO` / `INTEGRANTE` | Qué se vincula |
| `miembro_id` | uuid | Integrante; nulo cuando `tipo = GRUPO` |
| `whatsapp_id` | text | JID del grupo o identificador del remitente |
| `codigo` | text | Código pendiente de 6 caracteres |
| `codigo_expira_at` | timestamptz | Vence a los 10 minutos |
| `vinculado_at` | timestamptz | Fecha del vínculo efectivo |

Reglas garantizadas por la base de datos:

- un grupo por familia y un vínculo por integrante;
- un grupo de WhatsApp solo puede pertenecer a una familia;
- un WhatsApp solo puede representar a un integrante dentro de la familia;
- los códigos son únicos mientras estén pendientes y usan 31 símbolos sin `I`, `L`, `O`, `0` ni `1`;
- el código y su expiración existen juntos o no existen;
- el identificador y la fecha de vínculo existen juntos o no existen;
- el formato del JID se valida (`@g.us` para grupos; `@lid` o `@s.whatsapp.net` para personas).

### 6.2 `avisos_whatsapp`

Cola de mensajes de salida.

| Columna | Tipo | Descripción |
|---|---|---|
| `familia_id` | uuid | Familia destino |
| `recibo_id` | uuid | Recibo que origina el aviso |
| `tipo` | `POR_VENCER` / `VENCIDO` | Motivo |
| `fecha_aviso` | date | Día al que corresponde el aviso |
| `mensaje` | text | Texto final listo para enviar |
| `estado` | `PENDIENTE` / `ENVIADO` / `ERROR` / `DESCARTADO` | Ciclo de vida |
| `intentos` | smallint | Reintentos realizados |
| `error` | text | Último error de envío |
| `tomado_at` | timestamptz | Reserva de 2 minutos mientras el bot envía |
| `enviado_at` | timestamptz | Momento del envío |

La restricción única `(recibo_id, tipo, fecha_aviso)` garantiza que ejecutar el job varias veces no duplique avisos.

```text
PENDIENTE ──envío correcto──▶ ENVIADO
    │
    ├──falla──▶ intentos + 1 ──(< 3)──▶ PENDIENTE
    │                    └──(= 3)──▶ ERROR
    │
    └──ya no aplica (pagado, otro día, grupo desvinculado)──▶ DESCARTADO
```

`DESCARTADO` evita enviar avisos viejos: si el bot estuvo apagado o el recibo se completó entre la generación y el envío, el aviso no sale.

### 6.3 Funciones

| Función | Quién la ejecuta | Qué hace |
|---|---|---|
| `public.generar_codigo_whatsapp(familia, tipo)` | Usuario autenticado | Genera código. `GRUPO` solo para administradores |
| `public.estado_whatsapp(familia)` | Usuario autenticado | Estado del grupo, del propio vínculo y conteo de integrantes vinculados |
| `public.desvincular_whatsapp(familia, tipo)` | Usuario autenticado | Quita el propio vínculo; `GRUPO` solo para administradores |
| `public.vincular_whatsapp(codigo, grupo, remitente)` | Solo `service_role` | Consume el código y registra el vínculo |
| `public.responder_comando_whatsapp(grupo, remitente, comando, remitente_alt)` | Solo `service_role` | Resuelve el comando y devuelve el texto de respuesta o `null` |
| `public.tomar_avisos_whatsapp()` | Solo `service_role` | Entrega avisos pendientes con el JID del grupo destino |
| `public.marcar_aviso_whatsapp(aviso, enviado, error)` | Solo `service_role` | Registra el resultado del envío |
| `app_private.generar_avisos_whatsapp_impl(fecha)` | Solo `pg_cron` | Inserta en la cola los avisos del día |

Las funciones públicas siguen el patrón del proyecto: envoltura `security invoker` en `public` que llama a una implementación `security definer` en `app_private`.

---

## 7. Flujos

### 7.1 Vincular el grupo familiar

```text
Administrador abre Configuración > Grupo de WhatsApp
    ↓
Pulsa "Vincular grupo" → recibe código (ej. W37D3C)
    ↓
Agrega el número del bot al grupo familiar
    ↓
Escribe en el grupo: /vincular-grupo W37D3C
    ↓
Bot envía (código, JID del grupo, remitente) a la Edge Function
    ↓
vincular_whatsapp valida y guarda el JID
    ↓
Bot responde: "Listo. Este grupo quedó vinculado a la familia Lazo."
    ↓
La pantalla de Configuración detecta el vínculo sola
```

### 7.2 Vincular a un integrante

```text
Integrante abre Perfil > Tu WhatsApp
    ↓
Pulsa "Vincular mi WhatsApp" → recibe código
    ↓
Escribe en el grupo familiar: /vincular FPZ5Z5
    ↓
Se valida que el código se use en el grupo de su familia
    ↓
Se guarda el identificador con el que llegó el mensaje
    ↓
Bot responde: "Listo, Luis. Tu WhatsApp quedó vinculado."
```

Se usa el identificador recibido y no el número de teléfono porque WhatsApp está migrando a identificadores internos (LID) en grupos, y el número del remitente no siempre llega. El bot prefiere el LID y, cuando también llega el número, lo envía como identificador alterno; la consulta reconoce al integrante por cualquiera de los dos.

### 7.3 Avisos automáticos

```text
05:10 UTC procesar_ciclo_diario() actualiza estados
    ↓
Cada hora (minuto 5) generar_avisos_whatsapp_impl(hoy) inserta avisos en la cola
    ↓
Bot consulta la cola cada 5 minutos
    ↓
tomar_avisos_whatsapp: ¿dentro de 08:00–21:00 Lima?
    ├── No → no entrega nada
    └── Sí → descarta avisos que ya no aplican, recalcula montos y los entrega
               ↓
          Bot envía al grupo (3 s entre mensajes) → marca ENVIADO o registra error
```

La generación es horaria para que un recibo confirmado durante el día también reciba su aviso a tiempo; la cola es idempotente, así que no hay duplicados.

Un recibo genera aviso solo si cumple todo lo siguiente:

- la familia está activa y tiene grupo vinculado;
- el periodo del recibo está abierto;
- el recibo tiene monto confirmado (`monto_total` no nulo);
- el estado del recibo es `PENDIENTE` o `VENCIDO`;
- la recaudación no está `COMPLETA` y hay al menos una cuota con saldo.

Momentos de aviso, sobre la fecha objetivo (`fecha_limite_aporte ?? fecha_vencimiento`):

| Tipo | Cuándo |
|---|---|
| `POR_VENCER` | Faltan 3 días y falta 1 día |
| `VENCIDO` | Al día siguiente y luego cada 3 días mientras siga pendiente |

### 7.4 Consultas por comando

```text
Integrante escribe /deuda en el grupo
    ↓
Bot verifica el límite de comandos por minuto
    ↓
Edge Function → responder_comando_whatsapp
    ↓
¿Grupo vinculado? ── No → se ignora
    ↓
¿Remitente vinculado?
    ├── No → "Aún no vinculas tu WhatsApp. Genera tu código en FamiliaHub > Perfil > WhatsApp…"
    └── Sí → texto con su deuda calculada por el motor existente
    ↓
Bot responde citando el mensaje original
```

### 7.5 Lenguaje natural (opcional, posterior)

Cuando los comandos estén estables, el asistente puede entender preguntas libres como "@FamiliaHub ¿cuánto me falta de la luz?".

- Se usa la API de Claude con tool use.
- Las herramientas disponibles son las mismas funciones de consulta de la base de datos.
- El modelo interpreta la pregunta y redacta la respuesta, pero nunca calcula montos; siempre los obtiene de las funciones.
- Si la pregunta no corresponde a pagos del hogar, responde con la lista de comandos.

Hoy, una mención al bot sin comando responde con `/ayuda`.

---

## 8. Catálogo de comandos

| Comando | Quién | Respuesta | Estado |
|---|---|---|---|
| `/ping` | Cualquiera | `pong 🏠` (prueba de conexión; no consulta Supabase) | Implementado |
| `/vincular-grupo CODIGO` | Administrador | Vincula el grupo a la familia | Implementado |
| `/vincular CODIGO` | Integrante | Vincula su WhatsApp | Implementado |
| `/ayuda` | Cualquiera en grupo vinculado | Lista de comandos (también `/comandos`) | Implementado |
| `/deuda` | Integrante vinculado | Total pendiente y detalle por recibo | Implementado |
| `/vence` | Integrante vinculado | Vencimientos del mes, faltante y su parte | Implementado |
| `/resumen` | Integrante vinculado | Recibos del mes, recaudado y faltante | Implementado |

Reglas:

- los comandos no distinguen mayúsculas ni minúsculas;
- en un grupo no vinculado solo se atienden `/ping` y `/vincular-grupo`;
- se ignora cualquier mensaje que no empiece con `/` ni mencione al bot;
- un comando desconocido en el grupo vinculado responde con una sugerencia de `/ayuda`;
- máximo 5 comandos por minuto por remitente.

---

## 9. Ejemplos de mensajes

Textos reales generados por la base de datos (montos ilustrativos).

**Aviso por vencer**

```text
⏰ Luz vence en 3 días (lun 12/10)
Total: S/ 184.50
Falta recaudar: S/ 92.25
Pendientes: Ana S/ 46.12 · Luis S/ 46.13
Paga desde FamiliaHub > Mis cuotas.
```

**Aviso vencido**

```text
⚠️ Agua venció ayer (jue 08/10)
Total: S/ 70.00
Falta recaudar: S/ 35.00
Pendiente: Luis S/ 35.00 (por validar)
Paga desde FamiliaHub > Mis cuotas.
```

`(por validar)` aparece cuando el integrante ya envió su pago y falta la validación.

**Respuesta a /deuda**

```text
Luis, tienes S/ 81.13 pendientes:
• Agua: S/ 35.00 (vencida 08/10)
• Luz: S/ 46.13 (vence 12/10)
```

**Respuesta a /vence**

```text
Vencimientos de octubre:
• Agua: venció 08/10 · falta S/ 35.00 · tú S/ 35.00
• Luz: vence 12/10 (en 3 días) · falta S/ 92.25 · tú S/ 46.13
• Internet: esperando monto
```

**Respuesta a /resumen**

```text
Octubre 2026
Recibos: 4 · Pagados al proveedor: 1
Recaudado: S/ 210.00 de S/ 402.50
Falta: S/ 192.50
Esperando monto: 1
```

---

## 10. Privacidad

En un grupo todos ven todos los mensajes. Reglas:

1. Los avisos muestran el total del recibo y quiénes tienen saldo pendiente. Esto es coherente con el documento funcional, que permite ver el estado general de los participantes de un recibo.
2. No se publican QR, cuentas receptoras, comprobantes ni datos de autenticación.
3. El bot no guarda mensajes. Solo procesa comandos y descarta el resto. En los logs solo registra el nombre del comando, nunca el código de vinculación.
4. Un integrante solo puede consultar información de su propia familia.
5. Cada integrante puede desvincular su WhatsApp desde Perfil.

`/deuda` responde en el grupo citando al integrante (decisión de la sección 17).

---

## 11. Seguridad

| Riesgo | Control |
|---|---|
| Robo de la sesión del bot | `bot-whatsapp/auth/` en `.gitignore`. Quien tenga esa carpeta controla el número |
| Exposición de la clave de Supabase | El bot no la tiene; usa un secreto compartido con la Edge Function |
| Suplantación de integrante | Vínculo solo con código de un solo uso, 10 minutos, generado por el propio usuario autenticado |
| Secuestro del grupo | Solo un administrador genera el código de grupo; un grupo no puede pertenecer a dos familias |
| Fuerza bruta de códigos | 6 caracteres de 31 símbolos generados con `gen_random_uuid` (aleatoriedad criptográfica), expiración corta y límite de comandos por minuto |
| Lectura directa de tablas | RLS activo y sin permisos para `anon` ni `authenticated` |
| Ejecución indebida de vinculación, comandos o cola | Funciones solo ejecutables por `service_role` |
| Comparación del secreto | La Edge Function compara resúmenes SHA-256 en tiempo constante y exige un secreto de al menos 32 caracteres |

Configuración de la Edge Function, igual que `login-usuario`:

```toml
[functions.bot-whatsapp]
verify_jwt = false
```

La función valida el secreto en el header `x-familiahub-bot-secret` y rechaza cualquier petición sin él.

---

## 12. Riesgo de baneo y mitigación

1. Usar un chip dedicado, nunca un número personal.
2. Responder solo a comandos o menciones.
3. No enviar mensajes fuera del grupo vinculado (los avisos solo van al JID guardado en `whatsapp_vinculos`).
4. No enviar mensajes masivos ni a contactos desconocidos; el bot no opera en chats privados.
5. Mantener pocos avisos por día, solo en horario razonable y con 3 segundos entre mensajes.
6. Esperar 3 segundos entre reconexiones para no saturar los servidores de WhatsApp.
7. No marcarse "en línea" al conectar ni descargar historial.
8. Mantener activo el celular del chip: WhatsApp cierra los dispositivos vinculados si el teléfono principal pasa unos 14 días sin uso.

---

## 13. Infraestructura y despliegue

### 13.1 Dónde corre el bot

Baileys mantiene un WebSocket permanente. No puede correr en Edge Functions ni en Vercel.

| Opción | Ventaja | Desventaja |
|---|---|---|
| PC o Raspberry Pi en casa | Gratis | Depende de la luz y del internet del hogar |
| VPS básico | Estable 24/7, costo bajo | Pago mensual y administración del servidor |
| Railway / Fly.io | Despliegue simple | Requiere volumen persistente para `auth/` |

### 13.2 Requisitos

- Node.js 22.18 o superior (ejecuta TypeScript sin compilar).
- Disco persistente para `auth/`.
- Gestor de procesos (`pm2` o `systemd`) para reiniciar ante caídas.
- Archivo `bot-whatsapp/.env` (ver `.env.example`):
  - `FAMILIAHUB_FUNCTION_URL`
  - `FAMILIAHUB_BOT_SECRET`

Sin estas variables el bot arranca en modo mínimo y solo responde `/ping`.

### 13.3 Supabase (una vez)

```bash
supabase db push                                   # aplica las 3 migraciones
supabase secrets set FAMILIAHUB_BOT_SECRET=$(openssl rand -hex 32)
supabase functions deploy bot-whatsapp             # usa verify_jwt = false de config.toml
```

Guardar el mismo secreto en `bot-whatsapp/.env`.

### 13.4 Puesta en marcha del bot

```bash
cd bot-whatsapp
npm install --omit=dev
cp .env.example .env    # completar URL y secreto
npm start
```

1. Escanear el QR con el celular del chip: WhatsApp > Dispositivos vinculados > Vincular dispositivo.
2. Tras el primer escaneo, WhatsApp reinicia la sesión; el bot reconecta solo.
3. Agregar el número al grupo familiar y escribir `/ping`.
4. Vincular el grupo desde Configuración y cada integrante desde Perfil.

Si el bot termina con "Sesión cerrada desde el teléfono", se borra `auth/` y se vuelve a escanear el QR.

### 13.5 Ejecución 24/7

```bash
npm install -g pm2
cd bot-whatsapp
pm2 start ecosystem.config.cjs
pm2 save
pm2 startup             # sigue la instrucción que imprime para arrancar con el sistema
pm2 logs familiahub-bot
```

Respaldo cifrado de la sesión (sin él, perder el disco obliga a reescanear el QR):

```bash
tar -czf - auth | gpg --symmetric --cipher-algo AES256 -o auth-$(date +%F).tar.gz.gpg
```

---

## 14. Plan de implementación por fases

### 12.1 Bot mínimo — Implementado

- `bot-whatsapp/index.ts`, `package.json`, `package-lock.json`;
- conexión por QR con sesión persistente;
- reconexión con espera de 3 segundos;
- respuesta a `/ping` solo en grupos.

Criterio de aceptación: el bot responde `/ping` en el grupo familiar y se mantiene conectado durante varios días.

Pendiente: validar la conexión real con el chip dedicado.

### 12.2 Modelo de vínculos y cola — Implementado

- tablas `whatsapp_vinculos` y `avisos_whatsapp`;
- funciones `generar_codigo_whatsapp`, `vincular_whatsapp`, `estado_whatsapp` y `desvincular_whatsapp`;
- permisos y RLS.

### 12.3 Vinculación de punta a punta — Implementado

- Edge Function `bot-whatsapp` con acción `mensaje`;
- comandos `/vincular-grupo` y `/vincular`;
- componente `WhatsappVinculo` en Configuración (grupo) y en Perfil (integrante), con código, cuenta regresiva, copia del comando y detección automática del vínculo.

Criterio de aceptación: un administrador vincula el grupo y un integrante vincula su WhatsApp sin tocar la base de datos.

### 12.4 Avisos automáticos — Implementado

- `generar_avisos_whatsapp_impl` y job horario `familiahub-avisos-whatsapp` en `pg_cron`;
- acciones `avisos_pendientes` y `marcar_aviso` en la Edge Function;
- ventana horaria en la base de datos, lectura de la cola cada 5 minutos y reintentos en el bot.

Criterio de aceptación: un recibo que vence en 3 días genera un solo aviso aunque el job se ejecute varias veces, y se envía dentro del horario.

### 12.5 Comandos de consulta — Implementado

- `responder_comando_whatsapp_impl`;
- comandos `/ayuda`, `/deuda`, `/vence`, `/resumen`;
- límite de 5 comandos por minuto en el bot.

Criterio de aceptación: los montos del bot coinciden exactamente con Inicio y Mis cuotas.

### 12.6 Despliegue 24/7 — Preparado

Listo en el repositorio:

- `ecosystem.config.cjs` para pm2 con reinicio automático;
- instrucciones de respaldo cifrado de `auth/` (sección 13.5).

Pendiente: elegir servidor, aplicar migraciones, desplegar la Edge Function y escanear el QR con el chip.

Criterio de aceptación: el bot sobrevive a reinicios del servidor y a cortes de red.

### 12.7 Lenguaje natural — Opcional

- integración con la API de Claude usando tool use;
- herramientas limitadas a las funciones de consulta.

Criterio de aceptación: preguntas libres sobre pagos devuelven los mismos montos que los comandos.

---

## 15. Pruebas

| Suite | Cómo se ejecuta | Cobertura |
|---|---|---|
| `supabase/tests/whatsapp_asistente.sql` | SQL Editor o psql como `postgres`; termina con `Rollback` | 55 verificaciones: permisos, códigos, vínculos, avisos, cola y comandos |
| `bot-whatsapp/mensajes.test.ts` | `cd bot-whatsapp && npm test` | Extracción de comandos, menciones, LID/número y límite por minuto |
| Tipos del bot | `cd bot-whatsapp && npm run typecheck` | TypeScript estricto con sintaxis ejecutable por Node |

Casos cubiertos por la suite SQL:

| Caso | Resultado esperado |
|---|---|
| Integrante pide código de grupo | Rechazado |
| Código reusado o vencido | "Código inválido o vencido." |
| Grupo ya vinculado a otra familia | Rechazado |
| Integrante usa su código en otro grupo | Rechazado |
| Dos integrantes con el mismo WhatsApp | Rechazado |
| Integrante inactivo intenta vincularse | Rechazado |
| `authenticated` / `anon` leen tablas o ejecutan funciones del bot | Permiso denegado |
| Job de avisos ejecutado dos veces | Sin avisos duplicados |
| Recibo sin monto confirmado | No genera aviso |
| Recaudación completa | No genera aviso |
| Aviso fuera de horario | No se entrega hasta abrir la ventana |
| Pago entre generación y envío | El aviso sale con montos actualizados |
| Recibo completado antes del envío | Aviso `DESCARTADO` |
| Falla de envío 3 veces | Aviso en estado `ERROR` |
| `/deuda` de remitente no vinculado | Instrucciones para vincular |
| Montos de `/deuda` | Iguales a Mis cuotas |
| Integrante identificado por su identificador alterno | Reconocido |
| Grupo no vinculado | Solo responde `/ping` y `/vincular-grupo` |
| Grupo o integrante desvinculado | Deja de responder / pide vincular |

El límite de más de 5 comandos por minuto se prueba en `mensajes.test.ts`.

---

## 16. Operación y contingencia

### Monitoreo

```sql
-- Estado de la cola en la última semana
Select fecha_aviso, estado, count(*)
From public.avisos_whatsapp
Where fecha_aviso >= current_date - 7
Group By 1, 2
Order By 1 Desc, 2;

-- Avisos con error
Select fecha_aviso, intentos, error, mensaje
From public.avisos_whatsapp
Where estado = 'ERROR'
Order By updated_at Desc;
```

- Avisos en estado `ERROR`: revisar el campo `error` y la conexión del bot.
- Logs del bot: `pm2 logs familiahub-bot` (Baileys en nivel `warn`).
- Muchos `DESCARTADO` del mismo día indican que el bot estuvo apagado en horario de envío.

### Si se pierde o banean el número

1. Conseguir un nuevo chip y escanear el QR con el bot.
2. Agregar el nuevo número al mismo grupo.
3. No hace falta volver a vincular: el JID del grupo y los identificadores de los integrantes no cambian porque pertenecen al grupo y a las personas, no al bot.

### Si la opción A deja de ser viable

- Opción B: API oficial con avisos 1:1 por plantilla.
- Opción C: bot de Telegram.

En ambos casos solo se reemplaza el conector. La cola, los textos y las funciones de consulta se reutilizan.

---

## 17. Decisiones

Se adoptaron las recomendaciones del diseño:

| Decisión | Elegido |
|---|---|
| Dónde responde `/deuda` | Grupo, citando al integrante |
| Días de aviso previo | 3 y 1 |
| Recordatorio de vencidos | Cada 3 días |
| Ventana horaria | 08:00–21:00 Lima |
| Avisar al administrador recibos sin monto | Fase posterior |
| Dónde corre el bot | Casa para piloto, VPS para uso estable |

---

## 18. Estructura de archivos

```text
FamiliaHub/
├── bot-whatsapp/
│   ├── index.ts               conexión, comandos y entrega de avisos
│   ├── mensajes.ts            interpretación pura de mensajes
│   ├── mensajes.test.ts
│   ├── familiahub.ts          cliente de la Edge Function
│   ├── ecosystem.config.cjs   pm2
│   ├── .env.example
│   ├── tsconfig.json
│   ├── package.json
│   ├── package-lock.json
│   └── auth/                  (ignorada por git)
├── src/features/whatsapp/
│   └── WhatsappVinculo.tsx
├── supabase/
│   ├── functions/
│   │   └── bot-whatsapp/
│   ├── migrations/
│   │   ├── 20261009120000_whatsapp_vinculos_cola.sql
│   │   ├── 20261009121000_whatsapp_avisos.sql
│   │   └── 20261009122000_whatsapp_comandos.sql
│   └── tests/
│       └── whatsapp_asistente.sql
└── 03_ASISTENTE_WHATSAPP.md
```

---

## 19. Referencias

- [Documentación funcional](./01_DOCUMENTACION_FUNCIONAL.md), sección 10.14 Notificaciones.
- [Plan de creación por fases](./02_PLAN_CREACION_Y_FLUJO_POR_FASES.md), Fase 11 Cron y Fase 12 Notificaciones.
- Baileys: https://github.com/WhiskeySockets/Baileys
- Estado de la Groups API oficial en 2026: https://kapso.ai/blog/whatsapp-groups-api-state-2026
- Límites de la Groups API: https://www.unipile.com/whatsapp-group-api/
