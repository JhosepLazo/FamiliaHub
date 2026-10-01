# FamiliaHub — Plan de creación y flujo completo por fases

> Estado: Hoja de ruta técnica y funcional  
> Proyecto: FamiliaHub  
> Objetivo: Construir desde cero el asistente familiar completo, desde autenticación hasta cierre mensual  
> Estrategia: Mobile first, web/PWA primero y reutilización hacia Android/iOS  
> Principio: Cada fase debe quedar funcional, verificable y estable antes de depender de ella

---

## 1. Objetivo de este documento

Este documento define cómo se construirá FamiliaHub de inicio a fin.

Contiene dos recorridos complementarios:

1. El orden técnico de construcción del proyecto.
2. El flujo real que seguirá una familia dentro de la aplicación.

La intención es evitar desarrollar pantallas aisladas sin lógica completa, impedir dependencias circulares y asegurar que cada módulo tenga un propósito claro.

FamiliaHub debe terminar funcionando como un asistente, no como un CRUD que obligue a la familia a registrar todo manualmente.

---

# PARTE I — DECISIONES TÉCNICAS

## 2. Stack tecnológico

### 2.1 Lenguaje principal

TypeScript.

Se utilizará TypeScript porque permite compartir lenguaje y modelos entre frontend, integraciones y funciones backend.

Ventajas:

- tipado estático;
- mejor mantenibilidad;
- reutilización;
- ecosistema React;
- compatibilidad con Capacitor;
- integración directa con Supabase;
- menor diferencia entre Web y App móvil.

### 2.2 Frontend

- React
- Vite
- TypeScript
- Tailwind CSS
- React Router
- PWA
- Capacitor

### 2.3 Backend

Supabase:

- Auth
- PostgreSQL
- Row Level Security
- Storage
- Edge Functions
- Cron
- Webhooks/Database Functions cuando corresponda

### 2.4 Aplicación móvil

La aplicación se desarrollará inicialmente como Web responsive/PWA.

Después se empaquetará con Capacitor para:

- Android
- iOS

La intención es mantener la mayor cantidad posible de código compartido.

No se desarrollarán dos interfaces independientes.

### 2.5 Estilos

Tailwind CSS.

Objetivos:

- mobile first;
- diseño consistente;
- componentes reutilizables;
- rápida adaptación responsive;
- estados visuales claros;
- tema centralizado.

### 2.6 Iconografía

Una única librería de iconos consistente, preferentemente Lucide.

No mezclar múltiples estilos de iconografía.

---

## 3. Arquitectura general

~~~text
┌─────────────────────────────────────────┐
│              FamiliaHub                 │
│                                         │
│ React + TypeScript + Tailwind           │
│ Web / PWA / Capacitor                   │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│              Supabase                   │
│                                         │
│ Auth                                    │
│ PostgreSQL + RLS                        │
│ Storage                                 │
│ Edge Functions                          │
│ Cron                                    │
└──────────────────┬──────────────────────┘
                   │
          Integraciones servidor
                   │
         ┌─────────┼─────────┐
         ▼         ▼         ▼
      SEDAPAL    Pagos    Otros
      /otros     webhook   proveedores
~~~

### Regla

El frontend nunca debe contener secretos de proveedores.

Toda integración externa sensible deberá pasar por Edge Functions u otro servicio de servidor autorizado.

---

## 4. Capas lógicas

La estructura debe mantenerse simple.

### Presentación

Pantallas y componentes React.

### Aplicación

Casos de uso:

- crear recibo;
- generar cuotas;
- registrar pago;
- validar pago;
- pagar proveedor;
- cerrar periodo.

### Datos

Acceso a Supabase.

### Integraciones

Adaptadores de proveedores y pagos.

No crear capas adicionales si no tienen una responsabilidad real.

---

## 5. Estructura inicial prevista

No se crearán archivos hasta iniciar la implementación, pero la organización objetivo será aproximadamente:

~~~text
src/
├── app/
├── components/
├── features/
│   ├── auth/
│   ├── familia/
│   ├── inicio/
│   ├── servicios/
│   ├── recibos/
│   ├── cuotas/
│   ├── pagos/
│   ├── calendario/
│   ├── historial/
│   └── configuracion/
├── hooks/
├── lib/
├── routes/
├── services/
├── types/
└── styles/

supabase/
├── functions/
├── migrations/
└── seed/
~~~

La estructura definitiva se ajustará solo cuando exista código que la necesite.

---

# PARTE II — DISEÑO Y EXPERIENCIA

## 6. Principios UI/UX

### 6.1 Mobile first

El uso principal se espera desde celular.

Toda pantalla se diseña primero para un ancho móvil.

Después se expande a tablet y escritorio.

### 6.2 Una acción principal por contexto

Ejemplos:

- cuota pendiente → Pagar;
- pago enviado → Ver estado;
- recibo sin monto → Registrar monto;
- error de proveedor → Reintentar / Registrar manualmente.

### 6.3 Información prioritaria

En cada cuota:

1. Nombre del servicio.
2. Total del recibo.
3. Tu cuota.
4. Vencimiento.
5. Estado.
6. Acción.

### 6.4 No saturar

Los detalles técnicos, identificadores y auditoría no deben ocupar la pantalla principal.

### 6.5 Estados comprensibles

No mostrar códigos internos.

Mostrar:

- Pendiente
- Pago enviado
- Pagado
- Vencido
- Falta recaudar
- Recibo pagado

---

## 7. Sistema visual

### Personalidad

- moderna;
- familiar;
- profesional;
- limpia;
- confiable;
- ligera.

### Colores semánticos

- Primario: verde/teal.
- Información: azul.
- Atención: ámbar.
- Error/vencido: rojo.
- Éxito: verde.
- Fondo: neutro claro.

### Componentes base

- Button
- Input
- Select
- Checkbox
- Radio
- Modal/Sheet
- Toast
- Card
- Badge
- Avatar
- Progress
- Tabs
- EmptyState
- Skeleton
- DatePicker
- FileUploader
- ConfirmDialog

No crear variantes innecesarias.

---

## 8. Responsive

### Móvil

- navegación inferior;
- encabezado compacto;
- una columna;
- botones grandes;
- sheets para acciones secundarias.

### Tablet

- una o dos columnas;
- navegación adaptable;
- paneles laterales solo donde aporten valor.

### Escritorio

- sidebar;
- contenido central;
- panel contextual opcional;
- ancho máximo para formularios.

### Regla

Una función disponible en escritorio también debe poder completarse desde móvil.

---

# PARTE III — FLUJO FUNCIONAL DE LA FAMILIA

## 9. Flujo maestro

~~~mermaid
flowchart TD
    A[Login] --> B[Inicio]
    B --> C{Familia configurada}
    C -- No --> D[Configuración inicial]
    D --> E[Integrantes]
    E --> F[Servicios]
    F --> G[Participantes y cuotas]
    G --> B
    C -- Sí --> H[Periodo actual]
    H --> I[Consultar/generar recibos]
    I --> J[Crear recibo]
    J --> K[Calcular cuotas]
    K --> L[Notificar integrantes]
    L --> M[Usuario revisa su cuota]
    M --> N[Usuario paga]
    N --> O{Confirmación automática}
    O -- Sí --> P[Pago confirmado]
    O -- No --> Q[Pago enviado]
    Q --> R[Validación]
    R --> P
    P --> S[Actualizar recaudación]
    S --> T{Recaudación completa}
    T -- No --> L
    T -- Sí --> U[Pago al proveedor]
    U --> V[Guardar comprobante]
    V --> W[Recibo completado]
    W --> X[Historial y cierre mensual]
~~~

---

## 10. Fase funcional A — Acceso personal

### Objetivo

Cada integrante debe entrar con una identidad propia.

### Login

Campos:

- correo;
- contraseña.

Acciones:

- Iniciar sesión.
- Olvidé mi contraseña.
- Aceptar invitación si accede desde un enlace.

### Comportamiento

Al iniciar sesión:

1. validar credenciales;
2. recuperar perfil;
3. identificar familia;
4. recuperar rol;
5. recuperar periodo actual;
6. cargar resumen personal;
7. redirigir a Inicio.

### Seguridad

- No guardar contraseña en tablas propias.
- Utilizar Supabase Auth.
- Sesión persistente segura.
- Logout completo.
- RLS desde el primer módulo de datos.

### Criterio de aceptación

Un integrante autenticado solo puede leer información autorizada de su familia.

---

## 11. Fase funcional B — Creación de familia

Solo ocurre una vez para el primer administrador.

### Datos mínimos

- nombre de la familia;
- zona horaria;
- moneda;
- nombre del administrador.

Valores iniciales:

- America/Lima;
- PEN.

### Resultado

Se crean:

- familia;
- membresía del administrador;
- configuración inicial;
- periodo actual.

---

## 12. Fase funcional C — Invitación de integrantes

### Administrador

Selecciona Agregar integrante.

Ingresa:

- nombre;
- correo;
- rol.

### Sistema

1. crea invitación;
2. genera token;
3. asigna expiración;
4. envía o permite compartir enlace.

### Invitado

1. abre enlace;
2. valida invitación;
3. crea/inicia cuenta;
4. acepta pertenencia;
5. completa perfil;
6. accede a FamiliaHub.

### Reglas

- token de un solo uso;
- fecha de expiración;
- invitación revocable;
- email invitado debe coincidir cuando corresponda;
- no duplicar membresía.

---

## 13. Fase funcional D — Configuración de servicios

El administrador configura una sola vez los conceptos habituales.

Ejemplo Agua:

- categoría: Servicios;
- nombre: Agua;
- proveedor: SEDAPAL;
- frecuencia: Mensual;
- tipo de monto: Variable;
- método de obtención: Automático;
- suministro/cuenta: valor autorizado;
- vencimiento: obtenido del proveedor;
- participantes: Jhosep, Mamá, Papá;
- división: Igualitaria.

Ejemplo Internet:

- nombre: Internet;
- monto: Fijo o Automático;
- participantes: Jhosep y Mamá.

### Criterio

Modificar la configuración solo afecta recibos futuros.

---

## 14. Fase funcional E — Participantes y reglas de cuota

### Configuración

Para cada concepto:

- integrantes participantes;
- tipo de división;
- porcentaje/importe personalizado si aplica.

### Regla crítica

La categoría no determina quién paga.

Participantes y categoría son conceptos independientes.

### Snapshot

Al crear un recibo:

1. leer configuración vigente;
2. copiar participantes al recibo;
3. copiar regla de distribución;
4. generar cuotas.

Cambios posteriores no alteran ese recibo.

---

## 15. Fase funcional F — Inicio del periodo

FamiliaHub manejará periodos mensuales.

Ejemplo:

Octubre 2026.

### Automatización

Al comenzar un periodo:

1. crear periodo si no existe;
2. identificar conceptos activos;
3. clasificar cada concepto:
   - fijo;
   - automático;
   - manual;
4. programar/ejecutar obtención.

No es necesario generar recibos vacíos de todos los servicios si no aportan valor; la implementación debe evitar datos innecesarios.

---

## 16. Fase funcional G — Obtención del recibo

### Método AUTOMATICO

1. job programado identifica servicio pendiente;
2. llama Edge Function;
3. Edge Function obtiene configuración segura;
4. ejecuta adaptador;
5. normaliza respuesta;
6. valida periodo/monto/vencimiento;
7. verifica duplicados;
8. crea/actualiza recibo;
9. registra sincronización.

### Método FIJO

FamiliaHub conoce el monto recurrente.

Crea el recibo automáticamente para el periodo.

### Método MANUAL

El administrador recibe una tarea simple:

> Falta registrar el monto de Mantenimiento.

Campos:

- monto;
- vencimiento;
- archivo opcional.

Después FamiliaHub continúa automáticamente.

---

## 17. Fase funcional H — Normalización de proveedor

Todos los adaptadores deben producir el mismo modelo lógico.

~~~text
provider
accountReference
period
amount
currency
dueDate
status
externalReference
documentUrl/documentData
queriedAt
~~~

No permitir que cada proveedor contamine el modelo de FamiliaHub con estructuras diferentes.

---

## 18. Fase funcional I — Generación del recibo

Cuando existe información suficiente:

1. crear recibo;
2. asociar familia;
3. asociar concepto;
4. asociar periodo;
5. guardar importe;
6. guardar vencimiento;
7. guardar referencia externa;
8. guardar origen;
9. guardar documento si existe;
10. generar snapshot de participantes;
11. ejecutar cálculo de cuotas.

### Idempotencia

El mismo recibo no se crea dos veces aunque el job se ejecute repetidamente.

---

## 19. Fase funcional J — Motor de cuotas

### Igualitaria

Monto / participantes.

### Personalizada por porcentaje

Monto × porcentaje.

### Personalizada por importe

Importes definidos.

### Validaciones

- mínimo un participante;
- importe positivo;
- suma de cuotas = monto distribuible;
- porcentajes = 100%;
- resolver céntimos;
- no duplicar integrante.

### Redondeo

Regla determinística.

Ejemplo S/100 / 3:

- S/33.33
- S/33.33
- S/33.34

Nunca dejar una diferencia contable.

---

## 20. Fase funcional K — Notificación de nueva cuota

Al generar cuotas:

Cada participante recibe:

- concepto;
- monto total;
- su cuota;
- vencimiento.

Ejemplo:

> Nuevo recibo de Luz. Total S/157.80. Tu cuota S/52.60. Vence el 08 de octubre.

No enviar múltiples notificaciones por una misma generación.

---

## 21. Fase funcional L — Inicio personal

Un integrante entra y debe ver:

### Resumen

- Tu pendiente.
- Pagaste este mes.
- Número de cuotas pendientes.
- Próximo vencimiento.

### Lista inmediata

Cada cuota:

- icono;
- servicio;
- total del recibo;
- tu cuota;
- vencimiento;
- estado;
- botón Pagar/Ver.

### Prioridad

Ordenar por:

1. vencidas;
2. vencimiento más próximo;
3. resto.

---

## 22. Fase funcional M — Mis cuotas

Filtros simples:

- Pendientes
- Pagadas
- Todas

Cada cuota permite abrir detalle.

No incorporar filtros avanzados en V1 si no son necesarios.

---

## 23. Fase funcional N — Detalle del recibo

Un participante visualiza:

### Cabecera

- Servicio.
- Periodo.
- Total.
- Tu cuota.
- Vencimiento.
- Estado.

### Distribución

Ejemplo:

- Jhosep — S/52.60 — Pendiente
- Mamá — S/52.60 — Pagado
- Papá — S/52.60 — Pagado

### Progreso

S/105.20 de S/157.80.

### Acciones

Si tiene saldo:

- Pagar.

Si envió pago:

- Ver pago enviado.

Si pagó:

- Ver comprobación.

### Privacidad

Todos pueden visualizar el estado necesario para coordinar el recibo.

Detalles de comprobantes individuales pueden restringirse al dueño y administradores.

---

## 24. Fase funcional O — Pago de cuota

### V1

Al pulsar Pagar:

1. mostrar importe exacto pendiente;
2. mostrar cuenta receptora;
3. mostrar QR;
4. permitir copiar referencia/número;
5. explicar que el usuario debe volver a FamiliaHub;
6. botón Ya pagué.

### Confirmación manual asistida

Formulario:

- importe;
- operación/referencia;
- comprobante;
- fecha.

El importe se precarga y no debe obligar al usuario a calcular.

### Resultado

Aporte queda PAGO_ENVIADO.

---

## 25. Fase funcional P — Confirmación automática de pago

Se implementará cuando exista un proveedor de pago autorizado con API/webhook.

### Flujo

1. crear intento/referencia;
2. enviar al proveedor;
3. recibir webhook;
4. validar firma;
5. validar importe;
6. validar referencia;
7. comprobar idempotencia;
8. registrar aporte;
9. aplicar a cuota;
10. marcar confirmado.

### Seguridad

Nunca confiar en parámetros enviados solamente desde el frontend.

---

## 26. Fase funcional Q — Validación manual

Mientras el medio de pago no tenga webhook:

Administrador/receptor ve:

- usuario;
- concepto;
- cuota;
- importe;
- fecha;
- referencia;
- comprobante.

Acciones:

- Confirmar.
- Rechazar.

### Confirmar

- aporte confirmado;
- saldo de cuota actualizado;
- cuota PAGADA si saldo = 0;
- recaudación recalculada;
- notificación al integrante.

### Rechazar

- motivo obligatorio;
- estado RECHAZADA;
- saldo no cambia;
- integrante recibe notificación.

---

## 27. Fase funcional R — Pago parcial

Si un usuario paga menos:

- registrar aporte;
- reducir saldo;
- cuota PARCIAL;
- mantener botón Pagar saldo.

Ejemplo:

Cuota S/100.

Aporte S/60.

Saldo S/40.

---

## 28. Fase funcional S — Sobrepago

Si importe > saldo:

No asignar automáticamente.

Mostrar:

> El importe supera tu saldo en S/X.

Requerir corrección o resolución administrativa.

No transferir excedentes entre recibos sin confirmación.

---

## 29. Fase funcional T — Recaudación

Cada vez que cambia un aporte confirmado:

1. sumar aportes confirmados;
2. comparar contra monto distribuible;
3. actualizar progreso;
4. actualizar estado:
   - sin aportes;
   - parcial;
   - completa.

Cuando sea completa:

- notificar administrador;
- actualizar visualmente el recibo.

---

## 30. Fase funcional U — Pago del recibo al proveedor

Proceso independiente de la recaudación.

### Posibles escenarios

#### Escenario 1

La familia recauda primero y luego paga al proveedor.

#### Escenario 2

Un integrante paga al proveedor primero y luego los demás le reembolsan sus cuotas.

Ambos deben ser válidos.

### Registro

- importe;
- fecha;
- pagado por;
- método;
- comprobante;
- referencia.

### Resultado

Estado del recibo = PAGADO.

No marcar cuotas personales como pagadas por este hecho.

---

## 31. Fase funcional V — Historial

Al terminar un recibo, debe seguir siendo consultable.

Información:

- total;
- vencimiento;
- participantes históricos;
- cuotas;
- aportes;
- anulaciones;
- pago al proveedor;
- comprobantes;
- eventos importantes.

---

## 32. Fase funcional W — Calendario

Debe reflejar:

- vencimientos;
- servicios próximos;
- recibos vencidos.

Un participante visualiza su cuota cuando corresponde.

No convertir este módulo en calendario familiar genérico.

---

## 33. Fase funcional X — Cierre mensual

Al terminar el mes:

FamiliaHub genera resumen:

- gasto total;
- recaudado;
- pendiente;
- cuotas generadas;
- pagadas;
- pendientes;
- recibos pagados;
- recibos pendientes.

### Cierre

No bloquear correcciones legítimas, pero registrar cambios posteriores.

Periodo COMPLETADO cuando cumple condiciones definidas.

---

# PARTE IV — FASES DE DESARROLLO

## 34. FASE 0 — Preparación del repositorio

### Objetivo

Crear una base mínima y reproducible.

### Tareas

- inicializar React + Vite + TypeScript;
- configurar npm;
- configurar Tailwind;
- ESLint;
- Prettier si se decide utilizar;
- variables de entorno;
- archivo .env.example;
- aliases;
- configuración PWA;
- configuración inicial Capacitor;
- README;
- estructura mínima;
- conexión de desarrollo con Supabase.

### No hacer

- crear módulos vacíos;
- crear carpetas sin uso;
- implementar todas las tablas anticipadamente.

### Salida

Proyecto ejecutable localmente.

---

## 35. FASE 1 — Diseño base

### Objetivo

Crear el sistema visual antes de construir módulos.

### Entregables

- tokens;
- tipografía;
- colores;
- spacing;
- botones;
- inputs;
- cards;
- badges;
- feedback;
- layout;
- navegación móvil;
- sidebar escritorio.

### Pantallas prototipo

- Login.
- Inicio.
- Mis cuotas.
- Detalle de recibo.

### Criterio

Las cuatro deben funcionar responsive sin lógica final.

---

## 36. FASE 2 — Supabase y seguridad base

### Objetivo

No construir funcionalidad sobre una base insegura.

### Entregables

- proyecto Supabase;
- migraciones;
- Auth;
- familias;
- perfiles;
- miembros;
- invitaciones;
- políticas RLS;
- Storage privado inicial.

### Pruebas obligatorias

- usuario A no accede a familia B;
- usuario no autenticado no accede a datos;
- integrante no ejecuta acciones de administrador.

---

## 37. FASE 3 — Login e invitaciones

### Entregables

- Login.
- Logout.
- Recuperación.
- Crear familia inicial.
- Invitar integrante.
- Aceptar invitación.
- Perfil.
- Guard de rutas.
- Redirecciones según estado.

### Criterio

Dos usuarios distintos pueden ingresar a la misma familia con permisos correctos.

---

## 38. FASE 4 — Configuración familiar

### Entregables

- familia;
- integrantes;
- roles;
- activar/desactivar;
- cuenta receptora;
- categorías.

No agregar aún recibos.

---

## 39. FASE 5 — Conceptos y servicios

### Entregables

- CRUD mínimo de conceptos;
- proveedor;
- frecuencia;
- tipo de monto;
- método de obtención;
- participantes;
- división.

### Validaciones

- concepto activo;
- participantes válidos;
- no duplicar configuraciones incoherentes.

---

## 40. FASE 6 — Periodos y recibos manuales/fijos

Antes de integrar proveedores externos debe funcionar el dominio sin ellos.

### Entregables

- periodos;
- recibo manual;
- recibo de monto fijo;
- snapshot de participantes;
- motor de cuotas;
- redondeo;
- estados.

### Criterio

Crear Luz S/100 para 3 personas debe generar exactamente S/100 distribuido.

---

## 41. FASE 7 — Mis cuotas e Inicio

### Entregables

- resumen personal;
- listado de cuotas;
- filtros básicos;
- detalle;
- progreso;
- estados;
- vista Hogar.

### Criterio

Un integrante entiende qué debe sin necesitar explicación externa.

---

## 42. FASE 8 — Pagos familiares

### Entregables

- configuración QR;
- Pagar;
- registrar aporte;
- comprobante;
- pago parcial;
- estado PAGO_ENVIADO;
- panel de validación;
- confirmar/rechazar;
- actualización de cuota;
- recaudación.

### Pruebas

- pago total;
- parcial;
- rechazado;
- repetido;
- sobrepago;
- comprobante inválido.

---

## 43. FASE 9 — Pago al proveedor

### Entregables

- registrar pago;
- comprobante;
- estado del recibo;
- independencia con recaudación.

### Casos

- proveedor pagado antes de recaudar;
- proveedor pagado después;
- recaudación completa pero proveedor pendiente.

---

## 44. FASE 10 — Automatización de proveedores

Solo cuando el flujo manual esté estable.

### Entregables

- contrato ProviderAdapter;
- Edge Function;
- primer adaptador real;
- sincronización;
- log;
- idempotencia;
- reintentos;
- fallback manual.

### Orden sugerido

1. implementar un proveedor;
2. estabilizar contrato;
3. agregar siguientes.

No desarrollar múltiples integraciones simultáneamente.

---

## 45. FASE 11 — Cron y asistente automático

### Jobs

- revisar periodos;
- consultar recibos;
- reintentar fallos;
- detectar vencimientos;
- generar notificaciones;
- preparar resumen.

### Requisitos

- idempotencia;
- logs;
- límites;
- control de errores;
- no duplicar notificaciones.

---

## 46. FASE 12 — Notificaciones

### V1

Centro interno.

### V1.1

Push PWA.

### Móvil

Push nativo cuando la app Capacitor esté habilitada.

### Reglas

No saturar.

Priorizar:

- nuevo recibo;
- vence pronto;
- vencido;
- pago confirmado/rechazado.

---

## 47. FASE 13 — Calendario e historial

### Entregables

- calendario;
- filtros de historial;
- detalle histórico;
- comprobantes;
- resumen mensual;
- cierre de periodo.

---

## 48. FASE 14 — PWA

### Requisitos

- manifest;
- iconos;
- service worker;
- installability;
- pantalla offline controlada;
- actualización de versión;
- splash cuando corresponda.

### Offline

No intentar convertir V1 en offline-first completo.

La app puede mostrar información cacheada limitada, pero acciones financieras requieren conexión.

---

## 49. FASE 15 — Capacitor Android/iOS

### Objetivo

Reutilizar la app Web.

### Pasos

- inicializar Capacitor;
- Android;
- iOS;
- revisar safe areas;
- teclado;
- archivos/cámara;
- deep links;
- notificaciones;
- permisos;
- splash/icon;
- pruebas reales.

### Regla

No bifurcar lógica funcional por plataforma salvo necesidad nativa.

---

## 50. FASE 16 — Pruebas

### Unitarias

- división;
- redondeo;
- estados;
- saldo;
- ajustes.

### Integración

- RLS;
- creación de recibo;
- cuotas;
- aportes;
- proveedor;
- webhooks.

### End to End

Flujo:

Login → cuota → pago → validación → pagado.

Administrador:

Login → recibo → cuotas → validar → proveedor → cierre.

### Responsive

- móvil pequeño;
- móvil grande;
- tablet;
- escritorio.

### Navegadores

- Chromium;
- Safari donde sea posible;
- Firefox para Web.

---

## 51. FASE 17 — Seguridad

Checklist:

- RLS completa;
- secretos fuera de cliente;
- validación servidor;
- URLs firmadas;
- archivos privados;
- tokens expirables;
- rate limit;
- webhook signature;
- idempotency keys;
- logs sin secretos;
- inputs sanitizados/validados;
- dependencias actualizadas;
- políticas de CORS correctas.

---

## 52. FASE 18 — Deploy

### Ambientes

- Local.
- Desarrollo/Preview.
- Producción.

### Frontend

Hosting compatible con Vite/PWA.

### Backend

Supabase.

### CI

GitHub Actions:

- instalar dependencias;
- lint;
- typecheck;
- test;
- build.

Deploy únicamente si verificaciones pasan.

---

## 53. FASE 19 — Observabilidad

Registrar:

- errores frontend;
- errores Edge Functions;
- fallos de provider;
- cron;
- webhooks;
- validaciones;
- acciones críticas.

El administrador familiar solo debe ver errores accionables.

Los detalles técnicos quedan para desarrollo.

---

## 54. FASE 20 — Piloto familiar

Antes de agregar nuevas funciones:

1. configurar familia real;
2. cargar servicios reales;
3. ejecutar un mes;
4. observar fricción;
5. medir tareas manuales;
6. corregir experiencia.

Preguntas:

- ¿Se entiende cuánto toca pagar?
- ¿Se encuentra Pagar fácilmente?
- ¿El administrador interviene demasiado?
- ¿Los estados son comprensibles?
- ¿WhatsApp sigue siendo necesario para saber quién pagó?

---

# PARTE V — MODELO DE DATOS PLANIFICADO

## 55. Tablas principales previstas

Los nombres son conceptuales hasta crear migraciones.

### familias

- id
- nombre
- moneda
- zona_horaria
- activo
- created_at

### perfiles

- id
- nombre
- avatar_url
- created_at

Relaciona con auth.users.

### miembros_familia

- id
- familia_id
- usuario_id
- rol
- estado
- joined_at

### invitaciones

- id
- familia_id
- email
- rol
- token_hash
- expira_at
- estado

### categorias

- id
- familia_id
- nombre
- icono
- activo

### conceptos_pago

- id
- familia_id
- categoria_id
- proveedor_id
- nombre
- frecuencia
- tipo_monto
- monto_fijo
- metodo_obtencion
- activo

### concepto_participantes

- id
- concepto_id
- miembro_id
- tipo_distribucion
- porcentaje
- monto_personalizado

### proveedores

- id
- codigo
- nombre
- tipo_integracion

### cuentas_servicio

- id
- familia_id
- concepto_id
- proveedor_id
- referencia
- configuracion_segura_ref
- activo

### periodos

- id
- familia_id
- anio
- mes
- estado

### recibos

- id
- familia_id
- concepto_id
- periodo_id
- monto
- moneda
- vencimiento
- origen
- referencia_externa
- estado
- pagado_at

### recibo_participantes

- id
- recibo_id
- miembro_id
- regla_snapshot
- monto_asignado

### cuotas

- id
- recibo_participante_id
- monto
- pagado
- saldo
- estado

### aportes

- id
- familia_id
- miembro_id
- monto
- metodo
- referencia
- estado
- fecha_pago

### aplicaciones_aporte

Permite aplicar un aporte a una o varias cuotas en el futuro.

- id
- aporte_id
- cuota_id
- monto

### pagos_proveedor

- id
- recibo_id
- pagado_por
- monto
- metodo
- referencia
- fecha

### comprobantes

- id
- familia_id
- tipo
- entidad_id
- storage_path
- mime_type
- uploaded_by
- created_at

### configuracion_pago_familiar

- id
- familia_id
- metodo
- titular
- referencia
- qr_storage_path
- activo

### notificaciones

- id
- usuario_id
- tipo
- titulo
- mensaje
- leida_at
- entidad_tipo
- entidad_id

### sincronizaciones_proveedor

- id
- cuenta_servicio_id
- inicio
- fin
- estado
- referencia
- error_code

### eventos_auditoria

Solo eventos relevantes.

- id
- familia_id
- usuario_id
- tipo
- entidad
- entidad_id
- metadata
- created_at

---

# PARTE VI — FUNCIONES BACKEND PREVISTAS

## 56. Edge Functions

Solo se crearán cuando exista la necesidad.

Posibles funciones:

### provider-sync

Consulta un proveedor autorizado.

### provider-webhook

Recibe eventos externos si el proveedor lo requiere.

### payment-webhook

Confirma pagos automáticos.

### invite-member

Gestiona envío seguro de invitación si es necesario.

### notify

Canaliza notificaciones push cuando se implemente.

La lógica simple de base de datos no debe convertirse innecesariamente en Edge Function.

---

## 57. Funciones de base de datos

Adecuadas para operaciones atómicas como:

- generar cuotas;
- aplicar aporte;
- confirmar aporte;
- recalcular saldo;
- cerrar recibo;
- obtener resumen.

El objetivo es evitar estados intermedios inconsistentes.

---

# PARTE VII — REGLAS DE INTEGRIDAD

## 58. Reglas obligatorias

1. Una cuota siempre pertenece a un participante de un recibo.
2. Un recibo siempre pertenece a una familia.
3. Un usuario no opera una familia ajena.
4. La suma de cuotas debe coincidir con el monto distribuido.
5. Un aporte confirmado no se elimina físicamente.
6. Una sincronización repetida no duplica recibos.
7. Un webhook repetido no duplica pagos.
8. Cambiar participantes de un concepto no altera recibos anteriores.
9. Pagar al proveedor no paga automáticamente las cuotas.
10. Recaudación completa no implica recibo pagado al proveedor.
11. Un pago enviado no significa pago confirmado.
12. Los comprobantes financieros son privados.
13. Las acciones sensibles requieren autorización servidor/base de datos.

---

# PARTE VIII — MANEJO DE CASOS ESPECIALES

## 59. Recibo no encontrado

- reintentar;
- informar al administrador solo cuando sea necesario;
- permitir registro manual.

## 60. Proveedor caído

FamiliaHub continúa operando.

No bloquear otros servicios.

## 61. Monto modificado por proveedor

Si no hay pagos:

- actualizar/recalcular.

Si hay pagos:

- generar ajuste controlado.

## 62. Integrante sale de la familia

- se desactiva membresía;
- conserva historial;
- no participa en nuevos recibos;
- obligaciones históricas no desaparecen automáticamente.

## 63. Integrante entra a mitad de mes

Por defecto participa desde futuros recibos.

El administrador puede incluirlo explícitamente en un recibo actual antes de pagos si corresponde.

## 64. Pago duplicado

Detectar por referencia externa/idempotencia cuando sea posible.

No aplicar dos veces.

## 65. Comprobante incorrecto

Rechazar con motivo.

El integrante vuelve a estado con saldo pendiente.

## 66. Pago en efectivo

Permitido como método manual.

Administrador confirma.

## 67. Recibo extraordinario

Crear concepto/evento no recurrente o recibo extraordinario.

Debe utilizar el mismo motor de participantes y cuotas.

---

# PARTE IX — NAVEGACIÓN FINAL

## 68. Integrante

### Móvil

Barra inferior:

- Inicio
- Mis cuotas
- Hogar
- Historial

Perfil desde cabecera.

Calendario accesible desde Inicio/Hogar o como quinta opción si las pruebas lo justifican.

### Escritorio

Sidebar:

- Inicio
- Mis cuotas
- Hogar
- Calendario
- Historial
- Perfil

---

## 69. Administrador

Agrega:

- Familia
- Servicios
- Configuración

Las funciones administrativas no deben contaminar la experiencia diaria de pago.

---

# PARTE X — PANTALLAS A CONSTRUIR

## 70. Autenticación

- Login.
- Recuperar contraseña.
- Invitación.
- Crear contraseña/perfil.

## 71. Onboarding administrador

- Crear familia.
- Añadir integrantes.
- Configurar cuenta receptora.
- Crear primer servicio.

## 72. Operación normal

- Inicio.
- Mis cuotas.
- Detalle cuota/recibo.
- Pagar.
- Confirmar pago enviado.
- Hogar.
- Detalle recibo.
- Calendario.
- Historial.
- Detalle histórico.

## 73. Administración

- Familia.
- Integrantes.
- Servicios.
- Crear/editar servicio.
- Participantes.
- Registrar recibo manual.
- Pagos por validar.
- Registrar pago proveedor.
- Configuración de pago.
- Sincronizaciones/errores accionables.

---

# PARTE XI — ORDEN ESTRICTO DE IMPLEMENTACIÓN

## 74. Secuencia recomendada

No cambiar este orden sin una razón técnica:

1. Repositorio/base.
2. Diseño.
3. Supabase/RLS.
4. Auth.
5. Familia.
6. Integrantes.
7. Categorías.
8. Conceptos.
9. Participantes.
10. Periodos.
11. Recibos manuales/fijos.
12. Motor de cuotas.
13. Inicio.
14. Mis cuotas.
15. Detalle.
16. Pagos manuales.
17. Validación.
18. Recaudación.
19. Pago proveedor.
20. Historial.
21. Calendario.
22. Notificaciones.
23. ProviderAdapter.
24. Primera integración automática.
25. Cron.
26. PWA.
27. Capacitor.
28. Pruebas finales.
29. Producción.
30. Piloto familiar.

Razón:

Primero debe ser correcto manualmente. Después se automatiza.

Si se automatiza antes de tener un dominio estable, los errores del proveedor esconderán errores del propio sistema.

---

# PARTE XII — CRITERIOS DE TERMINACIÓN

## 75. Definition of Done por funcionalidad

Una función está terminada cuando:

- cumple flujo esperado;
- tiene validaciones;
- respeta permisos;
- funciona en móvil;
- funciona en escritorio;
- maneja carga;
- maneja vacío;
- maneja error;
- tiene tipos correctos;
- no duplica datos;
- pasa pruebas relevantes;
- no expone secretos.

---

## 76. Definition of Done del MVP

FamiliaHub V1 puede considerarse terminado cuando una familia real puede completar el siguiente escenario:

1. Administrador crea familia.
2. Invita dos integrantes.
3. Los tres ingresan con su cuenta.
4. Administrador configura Luz.
5. Asigna tres participantes.
6. Se obtiene o registra recibo de S/150.
7. FamiliaHub crea tres cuotas de S/50.
8. Cada integrante ve S/150 total y S/50 personal.
9. Un integrante registra pago.
10. Administrador lo confirma.
11. Estado del integrante cambia a Pagado.
12. Los tres completan sus cuotas.
13. Recaudación muestra S/150/S/150.
14. Se registra pago del recibo al proveedor.
15. Se adjunta comprobante.
16. Recibo aparece Pagado.
17. Historial conserva toda la operación.
18. Resumen mensual refleja correctamente el movimiento.
19. Ningún usuario ajeno puede acceder.
20. Todo el proceso puede completarse desde un teléfono.

---

# PARTE XIII — AUTOMATIZACIÓN OBJETIVO

## 77. Experiencia final deseada

Después de configurar un servicio una vez:

~~~text
FamiliaHub
    ↓
Detecta nuevo periodo
    ↓
Consulta proveedor
    ↓
Obtiene recibo
    ↓
Genera cuotas
    ↓
Avisa a integrantes
    ↓
Integrante abre FamiliaHub
    ↓
Ve:
Total S/150
Tu cuota S/50
Vence 10 Oct
    ↓
Paga
    ↓
FamiliaHub confirma
    ↓
Actualiza recaudación
    ↓
Recibo se paga/registran datos
    ↓
Historial
~~~

La familia no debe hacer cálculos manuales.

---

## 78. Qué debe hacer el asistente sin preguntar

Siempre que exista información suficiente:

- saber el periodo;
- identificar servicios activos;
- consultar proveedores;
- evitar duplicados;
- calcular cuotas;
- asignar participantes;
- recordar vencimientos;
- actualizar saldos;
- actualizar estados;
- generar resumen.

---

## 79. Qué sí debe preguntar

Solo información que FamiliaHub no pueda determinar de forma segura:

- monto de un recibo manual;
- confirmación de una corrección;
- comprobante cuando no haya confirmación automática;
- motivo de rechazo/anulación;
- configuración inicial.

---

# PARTE XIV — EVOLUCIÓN DESPUÉS DEL MVP

## 80. Etapa siguiente

Solo después de validar V1:

- pagar varias cuotas en una sola operación;
- integración automática de pagos;
- push móvil;
- biometría;
- más proveedores;
- comparación mensual;
- alertas de variación;
- resumen inteligente.

## 81. Funciones que requieren validación real

No implementar solo porque parezcan atractivas:

- chat;
- IA conversacional;
- presupuestos avanzados;
- préstamos;
- lista de compras;
- inventario;
- documentos generales;
- tareas domésticas.

FamiliaHub debe conservar un alcance claro.

---

# PARTE XV — REFERENCIAS TÉCNICAS DE LA DECISIÓN

La arquitectura fue elegida para mantener una base web moderna, responsive y fácilmente reutilizable como aplicación móvil.

Referencias oficiales:

- React: https://react.dev/
- Vite: https://vite.dev/
- Tailwind CSS: https://tailwindcss.com/
- Capacitor: https://capacitorjs.com/docs
- Supabase: https://supabase.com/docs

Supabase se utilizará especialmente por:

- autenticación;
- PostgreSQL;
- Row Level Security;
- almacenamiento privado;
- Edge Functions;
- ejecución programada de automatizaciones.

Capacitor permitirá reutilizar una aplicación web moderna en Web, Android e iOS, agregando acceso a APIs nativas únicamente cuando sea necesario.

---

# 82. Resultado esperado

Cuando todas las fases estén completas, FamiliaHub deberá comportarse como un asistente familiar autónomo:

- la familia configura;
- FamiliaHub observa;
- FamiliaHub obtiene;
- FamiliaHub calcula;
- FamiliaHub avisa;
- el integrante paga;
- FamiliaHub verifica;
- FamiliaHub actualiza;
- FamiliaHub conserva el historial.

La automatización existe para reducir el trabajo de la familia, no para introducir complejidad visible.

Este documento será la guía de implementación. Cualquier cambio futuro deberá preservar el flujo principal y justificar por qué mejora la experiencia familiar.
