# FamiliaHub — Documentación funcional del proyecto

> Estado: Documento base del producto  
> Proyecto: FamiliaHub  
> Tipo: Asistente privado de pagos, recibos y cuotas familiares  
> Alcance: Uso familiar, no empresarial  
> Moneda inicial: PEN (S/)  
> Zona horaria inicial: America/Lima  
> Plataforma objetivo: Web responsive/PWA, Android e iOS

---

## 1. Descripción general

FamiliaHub será un asistente privado para el hogar orientado a simplificar la gestión de recibos, gastos compartidos, cuotas y vencimientos familiares.

El proyecto nace para reemplazar procesos dispersos que normalmente terminan en mensajes de WhatsApp, capturas, cálculos manuales, recordatorios personales y preguntas repetidas como:

- ¿Cuánto llegó la luz?
- ¿Cuánto me toca pagar?
- ¿Quiénes participan en este recibo?
- ¿Quién ya pagó?
- ¿Cuánto falta recaudar?
- ¿Ya se pagó el recibo al proveedor?
- ¿Dónde quedó el comprobante?
- ¿Cuánto pagué el mes pasado?

FamiliaHub no pretende convertirse en un ERP, sistema contable ni plataforma financiera empresarial. Su propósito es ser un asistente sencillo, claro y automatizado para una familia.

La regla central del producto será:

> Si FamiliaHub puede obtener, calcular, distribuir, recordar o actualizar algo automáticamente, no debe pedirle al usuario que lo haga manualmente.

---

## 2. Visión

FamiliaHub debe permitir que un integrante abra la aplicación y entienda su situación del mes en segundos:

- cuánto debe en total;
- qué cuotas tiene pendientes;
- cuánto cuesta cada recibo completo;
- cuánto le corresponde personalmente;
- cuándo vence;
- si ya pagó;
- cuánto falta para completar la recaudación familiar.

El administrador familiar debe poder conocer además:

- qué recibos existen este mes;
- qué servicios ya fueron consultados;
- qué pagos están pendientes de validar;
- cuánto se ha recaudado;
- cuánto falta;
- qué recibos ya fueron pagados al proveedor;
- qué excepciones requieren intervención manual.

La aplicación debe trabajar en segundo plano todo lo posible y mostrar únicamente las acciones que realmente necesitan intervención humana.

---

## 3. Objetivo general

Crear un asistente familiar multiplataforma que centralice los recibos y gastos compartidos del hogar, obtenga o registre sus importes, distribuya automáticamente las cuotas entre los integrantes correspondientes, facilite el pago, controle su estado, recuerde vencimientos y conserve un historial confiable.

---

## 4. Objetivos específicos

1. Dar a cada integrante un acceso personal y privado.
2. Mantener una familia cerrada, accesible únicamente mediante invitación.
3. Registrar los servicios y gastos habituales del hogar una sola vez.
4. Definir qué integrantes participan en cada concepto.
5. Consultar automáticamente recibos de proveedores cuando exista una integración autorizada.
6. Permitir carga manual cuando un proveedor no pueda consultarse automáticamente.
7. Obtener monto, periodo y vencimiento del recibo.
8. Calcular automáticamente la cuota de cada participante.
9. Mostrar siempre el monto total del recibo y la deuda personal.
10. Permitir divisiones iguales y, cuando sea necesario, divisiones personalizadas.
11. Facilitar el pago hacia una cuenta familiar configurada.
12. Registrar o recibir la confirmación del pago.
13. Separar el estado de la cuota individual del estado del recibo frente al proveedor.
14. Mantener comprobantes y trazabilidad mínima de movimientos.
15. Generar recordatorios automáticos.
16. Proporcionar historial mensual.
17. Cerrar cada periodo sin perder información histórica.
18. Mantener una experiencia responsive y simple en móvil, tablet y escritorio.

---

## 5. Qué NO es FamiliaHub

FamiliaHub no será inicialmente:

- un sistema contable;
- un ERP;
- un banco;
- una billetera digital;
- una aplicación de préstamos;
- una plataforma de cobranzas comerciales;
- un sistema de facturación electrónica;
- un chat familiar;
- una red social;
- un inventario doméstico;
- un gestor de recetas o compras;
- una plataforma de geolocalización familiar.

Cualquier función futura deberá justificar que ayuda directamente a administrar pagos, recibos, cuotas o coordinación económica del hogar.

---

## 6. Principios funcionales

### 6.1 Automatización primero

Los procesos repetitivos deben ejecutarse automáticamente:

- detectar periodos;
- consultar proveedores;
- crear recibos;
- calcular cuotas;
- enviar recordatorios;
- actualizar estados;
- preparar resúmenes;
- detectar pendientes.

### 6.2 Intervención humana mínima

Un usuario debería intervenir principalmente para:

1. configurar su familia o un servicio una vez;
2. realizar un pago;
3. resolver una excepción o corregir un dato.

### 6.3 Claridad antes que complejidad

La interfaz utilizará lenguaje familiar:

- Mis cuotas
- Pagos del hogar
- Tu cuota
- Falta pagar
- Ya pagaste
- Falta recaudar
- Vence pronto

Se evitarán términos empresariales como cuentas por cobrar, cartera, conciliación contable o centro de costos.

### 6.4 Historial inmutable en lo importante

Los cambios futuros de participantes o reglas no deben alterar periodos cerrados ni recibos históricos.

### 6.5 Sin dependencia absoluta de terceros

Toda integración automática deberá tener una alternativa manual para que FamiliaHub continúe funcionando si el proveedor externo falla.

---

## 7. Usuarios y roles

### 7.1 Administrador familiar

Será uno o más integrantes autorizados para administrar la familia.

Puede:

- crear y configurar la familia;
- invitar integrantes;
- activar o desactivar integrantes;
- crear categorías y conceptos;
- configurar servicios;
- indicar participantes;
- configurar método de división;
- configurar la cuenta receptora;
- registrar recibos manuales;
- revisar sincronizaciones;
- validar pagos cuando no exista confirmación automática;
- registrar pago al proveedor;
- corregir importes con trazabilidad;
- anular movimientos erróneos dejando historial;
- consultar toda la información necesaria de la familia.

### 7.2 Integrante

Puede:

- iniciar sesión con su cuenta;
- visualizar sus cuotas;
- consultar el total del recibo en el que participa;
- consultar cuánto le corresponde;
- visualizar vencimientos;
- pagar o registrar un pago;
- adjuntar comprobante cuando sea requerido;
- consultar su historial;
- visualizar el estado general de los participantes del recibo cuando corresponda.

Por privacidad, un integrante no necesita acceder a credenciales de proveedores, secretos, configuraciones técnicas ni datos de autenticación de otros usuarios.

---

## 8. Acceso y pertenencia a la familia

FamiliaHub será una aplicación privada.

### Reglas

- No existirá un listado público de familias.
- El alta inicial crea una familia y su primer administrador.
- Los demás integrantes ingresan mediante invitación.
- Cada invitación debe tener token único, expiración y estado.
- Un usuario no puede acceder a información de otra familia.
- En V1 se priorizará una familia activa por usuario.
- La sesión se mantendrá de forma segura y podrá cerrarse desde cualquier dispositivo.
- Recuperación de contraseña disponible mediante el proveedor de autenticación.

### Creación y acceso de cuenta

La identidad real continúa protegida por Supabase Auth.

Al crear una cuenta se solicita:

- nombre;
- correo electrónico real;
- usuario único;
- contraseña;
- confirmación del correo.

El correo se utiliza para:

- validar la creación de la cuenta;
- recuperar acceso;
- comunicaciones de seguridad.

El ingreso diario utiliza:

- usuario;
- contraseña.

El frontend nunca resuelve ni expone el correo asociado a un username. La resolución `usuario → identidad Auth` ocurre exclusivamente en una Edge Function del servidor y cualquier error de usuario inexistente o contraseña incorrecta devuelve el mismo mensaje genérico.

Los usernames son únicos sin distinguir mayúsculas/minúsculas. Se permiten entre 3 y 30 caracteres usando letras, números, punto, guion y guion bajo.

En versiones posteriores podrá agregarse OTP, passkeys o biometría en móvil sin cambiar el modelo de usuario.

---

## 9. Conceptos del dominio

### 9.1 Familia

Grupo privado al que pertenecen los integrantes y donde se administra la información del hogar.

### 9.2 Integrante

Persona asociada a una familia y a una cuenta autenticada.

### 9.3 Categoría

Clasificación visual de un gasto. Ejemplos:

- Servicios
- Vivienda
- Educación
- Suscripciones
- Hogar
- Otros

La categoría NO define quién paga.

### 9.4 Concepto de pago

Configuración permanente que describe qué se paga.

Ejemplos:

- Luz
- Agua
- Internet
- Mantenimiento
- Mensualidad
- Netflix

Define frecuencia, forma de obtención del monto, proveedor, vencimiento habitual y participantes.

### 9.5 Servicio/proveedor

Entidad que origina el recibo cuando corresponde.

Ejemplos:

- SEDAPAL
- empresa eléctrica
- proveedor de internet

### 9.6 Recibo u obligación

Instancia de un concepto para un periodo concreto.

Ejemplo:

Luz — Octubre 2026 — S/ 157.80 — vence 08/10/2026.

### 9.7 Participante

Integrante que forma parte de la distribución de un recibo.

### 9.8 Cuota

Importe específico que corresponde a un participante dentro de un recibo.

### 9.9 Aporte/pago de cuota

Movimiento mediante el cual un integrante paga total o parcialmente su cuota.

### 9.10 Recaudación

Suma de aportes confirmados asociados al recibo.

### 9.11 Pago al proveedor

Pago real del recibo a la empresa o persona que originó la obligación.

### 9.12 Comprobante

Archivo o referencia que respalda un recibo, aporte o pago al proveedor.

---

## 10. Módulos funcionales

### 10.1 Autenticación

Funciones:

- login;
- logout;
- recuperación de contraseña;
- aceptación de invitación;
- perfil personal;
- gestión de sesión.

### 10.2 Inicio / Asistente

Debe responder en segundos:

- cuánto debo;
- qué tengo pendiente;
- qué vence primero;
- qué ya pagué;
- si existe algún pago por confirmar.

Para administrador también mostrará:

- total familiar del periodo;
- recaudado;
- pendiente;
- recibos sin pagar;
- pagos por validar;
- errores de sincronización que requieren atención.

### 10.3 Mis cuotas

Listado personal dividido como mínimo en:

- Pendientes
- Pago enviado
- Pagadas
- Vencidas

Cada tarjeta debe mostrar:

- concepto;
- periodo;
- total del recibo;
- cuota personal;
- fecha de vencimiento;
- estado;
- acción principal.

### 10.4 Pagos del hogar

Vista consolidada de recibos del periodo.

Debe mostrar:

- concepto;
- proveedor;
- monto total;
- vencimiento;
- recaudado;
- número de cuotas pagadas;
- estado de recaudación;
- estado del recibo frente al proveedor.

### 10.5 Detalle de recibo

Información mínima:

- concepto;
- periodo;
- proveedor;
- monto total;
- vencimiento;
- origen del monto: automático, fijo o manual;
- estado del recibo;
- progreso de recaudación;
- participantes;
- cuota de cada participante;
- estado de cada cuota;
- recibo original si existe;
- comprobante del pago al proveedor si existe.

Un integrante participante debe ver claramente:

1. Total del recibo.
2. Tu cuota.
3. Fecha de vencimiento.
4. Estado de tu cuota.
5. Progreso general.

### 10.6 Servicios y conceptos

Configuración reutilizable.

Campos funcionales:

- nombre;
- categoría;
- proveedor;
- frecuencia;
- tipo de monto;
- fecha/día habitual de vencimiento;
- método de obtención;
- participantes;
- forma de división;
- estado activo/inactivo.

### 10.7 Integraciones de proveedores

FamiliaHub utilizará adaptadores independientes por proveedor.

Modos de obtención:

- AUTOMATICO: integración autorizada.
- FIJO: valor recurrente conocido.
- MANUAL: administrador registra monto y vencimiento.

Regla obligatoria:

> Ninguna integración externa puede bloquear la creación manual de un recibo.

Para consultas automáticas se guardará solamente la información estrictamente necesaria. Los secretos y credenciales nunca deben exponerse al frontend.

### 10.8 Cuotas

El motor debe:

- obtener participantes vigentes;
- crear una copia de participantes para el recibo;
- calcular importes;
- resolver redondeos;
- permitir división personalizada;
- impedir que la suma de cuotas difiera del monto distribuible;
- no recalcular automáticamente cuotas históricas pagadas.

### 10.9 Pagos de cuota

El sistema debe permitir:

- pago total;
- pago parcial;
- uno o varios aportes para una cuota;
- comprobante opcional/obligatorio según el método;
- estado pendiente de validación;
- confirmación automática cuando exista webhook oficial;
- validación manual como contingencia.

### 10.10 Cuenta receptora familiar

Configuración por familia:

- método;
- titular;
- referencia o número;
- QR;
- instrucciones.

V1 priorizará un flujo con Yape mediante QR o datos de pago y posterior confirmación.

Si en el futuro existe una integración oficial/contratada que entregue confirmación mediante API o webhook, FamiliaHub podrá reemplazar la validación manual sin modificar el modelo de cuotas.

### 10.11 Pago al proveedor

Debe tratarse como proceso distinto a la recaudación.

Un recibo puede estar:

- pagado al proveedor y todavía tener cuotas familiares pendientes;
- completamente recaudado pero todavía pendiente de pago al proveedor.

Estos estados nunca se mezclarán.

### 10.12 Calendario

Vista simple orientada únicamente a pagos:

- vencimientos;
- próximos recibos;
- periodos;
- pagos familiares programados.

### 10.13 Historial

Consulta por:

- mes;
- año;
- concepto;
- integrante;
- estado.

Debe conservar:

- monto total original;
- cuotas originales;
- aportes;
- ajustes;
- anulaciones;
- comprobantes;
- pago al proveedor.

### 10.14 Notificaciones

Eventos mínimos:

- nuevo recibo;
- nueva cuota;
- vencimiento próximo;
- cuota vencida;
- pago enviado;
- pago confirmado;
- pago rechazado;
- recaudación completada;
- recibo pagado;
- error de sincronización relevante para administrador.

Canales por etapas:

1. Centro de notificaciones interno.
2. Push web/PWA.
3. Push nativo mediante Capacitor.
4. Canales adicionales solo si aportan valor real.

---

## 11. Reglas de participación y división

### 11.1 Participantes por concepto

Cada concepto tiene sus propios participantes.

Ejemplo:

| Concepto | Jhosep | Mamá | Papá | Hermana |
|---|---:|---:|---:|---:|
| Luz | Sí | Sí | Sí | No |
| Agua | Sí | Sí | Sí | No |
| Internet | Sí | Sí | No | No |
| Streaming | Sí | No | No | Sí |

### 11.2 Snapshot por recibo

Cuando se crea un recibo, FamiliaHub copia los participantes y reglas vigentes a ese recibo.

Si posteriormente cambia un integrante, el recibo histórico no se modifica.

### 11.3 División igualitaria

Monto distribuible / número de participantes.

Ejemplo:

S/ 186.30 / 3 = S/ 62.10 por integrante.

### 11.4 Redondeo

El total de las cuotas debe coincidir exactamente con el monto a distribuir.

Ejemplo:

S/ 100.00 / 3:

- S/ 33.33
- S/ 33.33
- S/ 33.34

La diferencia residual será asignada por una regla determinística.

### 11.5 División personalizada

El administrador podrá definir porcentajes o importes cuando una división igualitaria no corresponda.

El sistema debe validar que la suma final coincida con el monto distribuible.

---

## 12. Estados

### 12.1 Estado de una cuota

Estados visibles:

- PENDIENTE
- PAGO_ENVIADO
- PARCIAL
- PAGADA
- VENCIDA
- RECHAZADA

### 12.2 Estado de recaudación

- SIN_APORTES
- PARCIAL
- COMPLETA

### 12.3 Estado del recibo

- ESPERANDO_MONTO
- PENDIENTE
- PAGADO
- VENCIDO
- ANULADO

### 12.4 Estado de sincronización

- PENDIENTE
- CONSULTANDO
- ACTUALIZADO
- SIN_CAMBIOS
- ERROR

Los estados técnicos se traducirán a lenguaje simple en la interfaz.

---

## 13. Flujo automático de un recibo

~~~text
Periodo activo
    ↓
FamiliaHub revisa conceptos activos
    ↓
¿Monto fijo, automático o manual?
    ↓
Obtiene o solicita monto
    ↓
Crea recibo
    ↓
Copia participantes vigentes
    ↓
Calcula cuotas
    ↓
Notifica a cada participante
    ↓
Cada integrante ve:
- total del recibo
- su cuota
- vencimiento
- estado
    ↓
Realiza aporte
    ↓
Confirmación automática o validación
    ↓
Actualiza cuota y recaudación
    ↓
Se registra pago al proveedor
    ↓
Recibo pagado
    ↓
Periodo/historial
~~~

---

## 14. Obtención automática de recibos

La arquitectura debe permitir proveedores independientes.

Cada adaptador deberá transformar la respuesta externa a un formato común:

- proveedor;
- identificador de suministro/cuenta;
- periodo;
- monto;
- moneda;
- vencimiento;
- estado;
- referencia externa;
- recibo/documento cuando esté disponible;
- fecha de consulta.

### Reglas de seguridad

- Usar únicamente integraciones autorizadas y compatibles con los términos del proveedor.
- No realizar scraping de áreas privadas protegidas como base crítica del producto.
- No guardar contraseñas de proveedores en texto plano.
- Secretos únicamente en entorno servidor.
- La interfaz nunca recibe claves privadas de integración.
- Si una integración falla, registrar error y ofrecer carga manual.

### Idempotencia

Una misma respuesta externa no puede crear dos recibos iguales.

Se debe controlar como mínimo:

familia + concepto + proveedor + periodo + referencia externa.

---

## 15. Flujo de pago familiar

### V1 segura

1. Usuario abre su cuota.
2. Ve total del recibo y su cuota.
3. Pulsa Pagar.
4. FamiliaHub muestra QR/datos de la cuenta receptora.
5. Usuario realiza el pago mediante la aplicación correspondiente.
6. Regresa a FamiliaHub.
7. Registra operación/comprobante cuando sea necesario.
8. Estado pasa a PAGO_ENVIADO.
9. Administrador/receptor confirma.
10. FamiliaHub recalcula automáticamente el saldo.

### Integración automática futura

Cuando exista un medio oficial/contratado con webhook:

1. FamiliaHub crea referencia de pago.
2. Usuario paga.
3. Proveedor de pagos confirma al backend.
4. Backend valida firma y referencia.
5. Aporte queda PAGADO.
6. Cuota y recaudación se actualizan sin intervención manual.

Nunca se marcará un pago como confirmado solo porque el usuario presionó Ya pagué.

---

## 16. Pagos parciales y sobrepagos

### Pago parcial

Una cuota puede recibir varios aportes hasta completar su importe.

Ejemplo:

Cuota S/ 100.00

- Aporte 1: S/ 60.00
- Saldo: S/ 40.00
- Aporte 2: S/ 40.00
- Estado final: PAGADA

### Sobrepago

Si un aporte supera el saldo, el sistema debe detener la asignación automática y pedir resolución.

Nunca debe mover el excedente a otra cuota sin una decisión explícita.

---

## 17. Modificación de un recibo

### Sin aportes confirmados

Se permite actualizar monto y recalcular cuotas.

### Con aportes confirmados

El sistema debe:

- mostrar monto anterior;
- mostrar nuevo monto;
- calcular diferencia;
- conservar pagos ya realizados;
- recalcular únicamente saldos necesarios mediante un ajuste trazable;
- solicitar confirmación administrativa.

No se deben sobrescribir silenciosamente importes históricos.

---

## 18. Anulaciones

Los movimientos financieros importantes no se eliminan físicamente desde la interfaz.

Se utiliza anulación lógica con:

- motivo;
- usuario;
- fecha;
- referencia al movimiento original.

Esto permite reconstruir qué ocurrió sin implementar una contabilidad empresarial.

---

## 19. Cierre mensual

Al finalizar un periodo, FamiliaHub debe generar un resumen con:

- total de recibos;
- total familiar pagado;
- total recaudado;
- total pendiente;
- número de cuotas;
- cuotas pagadas;
- cuotas pendientes;
- recibos pagados;
- recibos pendientes;
- incidencias.

Un periodo puede marcarse COMPLETADO cuando no existen obligaciones pendientes según las reglas definidas.

Los periodos cerrados permanecen consultables.

---

## 20. Experiencia de usuario

### Navegación de integrante

- Inicio
- Mis cuotas
- Hogar
- Calendario
- Historial
- Perfil

### Navegación adicional para administrador

- Familia
- Servicios
- Configuración

### Pantalla Inicio

Debe priorizar:

1. Tu pendiente.
2. Próximo vencimiento.
3. Cuotas pendientes.
4. Cuotas pagadas.
5. Alertas importantes.

### Diseño

FamiliaHub debe sentirse:

- familiar;
- moderno;
- limpio;
- cálido;
- confiable;
- simple;
- no corporativo.

No se utilizarán tablas densas en móvil cuando una tarjeta sea más clara.

### Responsive

Mobile first.

- Móvil: navegación inferior y acciones grandes.
- Tablet: layout de dos columnas cuando aporte claridad.
- Escritorio: navegación lateral y contenido central.
- Formularios con ancho controlado.
- Tarjetas reorganizables sin perder información.
- Acciones críticas accesibles con una mano en móvil.

---

## 21. Lenguaje visual

Base propuesta:

- fondo claro y neutro;
- verde/teal como color primario de confianza;
- azul para información;
- ámbar para próximos vencimientos;
- rojo únicamente para vencimientos/errores;
- bordes suaves;
- sombras discretas;
- radios amplios;
- iconografía simple;
- jerarquía tipográfica fuerte;
- estados acompañados por texto, no solo por color.

La accesibilidad debe contemplar contraste, foco visible, tamaño táctil y etiquetas comprensibles.

---

## 22. Arquitectura tecnológica propuesta

### Frontend

- TypeScript
- React
- Vite
- Tailwind CSS
- React Router
- PWA
- Capacitor para empaquetar la misma aplicación hacia Android/iOS

### Backend administrado

- Supabase Auth
- PostgreSQL
- Row Level Security
- Supabase Storage
- Edge Functions
- Cron/Jobs para automatizaciones
- Realtime únicamente donde agregue valor

### Razón

Este stack permite:

- una base principal en TypeScript;
- desarrollo web rápido;
- diseño Tailwind;
- experiencia responsive;
- instalación como PWA;
- reutilizar la aplicación web dentro de Capacitor para Android/iOS;
- autenticación, base de datos, archivos y automatizaciones sin crear infraestructura innecesaria.

La lógica crítica de seguridad y las integraciones externas no deben vivir exclusivamente en el navegador.

---

## 23. Modelo conceptual de datos

Entidades principales:

- familias
- perfiles
- miembros_familia
- invitaciones
- categorias
- conceptos_pago
- concepto_participantes
- proveedores
- cuentas_servicio
- recibos
- recibo_participantes
- cuotas
- aportes
- aplicaciones_aporte
- pagos_proveedor
- comprobantes
- metodos_pago
- configuracion_pago_familiar
- notificaciones
- sincronizaciones_proveedor
- periodos
- eventos_auditoria

Los nombres definitivos se validarán al diseñar la base de datos física.

---

## 24. Privacidad y seguridad

FamiliaHub administrará información financiera familiar, por lo que la seguridad no será opcional.

### Requisitos

- HTTPS en producción.
- Autenticación segura.
- Row Level Security por familia.
- Validación de permisos en servidor.
- Archivos privados por defecto.
- URLs firmadas para comprobantes cuando corresponda.
- Secretos únicamente en backend.
- Variables de entorno fuera del repositorio.
- Tokens de invitación con expiración.
- Validación de inputs.
- Rate limiting en operaciones sensibles.
- Registro de acciones financieras relevantes.
- Backups de base de datos según el servicio contratado.
- No almacenar datos personales que no sean necesarios.
- Nunca guardar credenciales bancarias completas ni claves de Yape.

### Regla de aislamiento

Un usuario solo puede consultar información de familias a las que pertenece.

RLS deberá reforzar esta regla en base de datos, no depender únicamente de ocultar pantallas.

---

## 25. Comprobantes y archivos

Se podrán almacenar:

- recibo original;
- comprobante de aporte;
- comprobante de pago al proveedor.

Reglas:

- almacenamiento privado;
- nombre interno no predecible;
- relación directa con la entidad correspondiente;
- MIME permitido;
- límite de tamaño;
- fecha de carga;
- usuario que cargó el archivo;
- eliminación/anulación controlada.

---

## 26. Automatizaciones

FamiliaHub deberá contar con procesos programados para:

- iniciar periodos;
- revisar conceptos recurrentes;
- consultar proveedores;
- detectar recibos nuevos;
- reintentar errores controlados;
- generar cuotas;
- enviar recordatorios;
- detectar vencidos;
- generar resumen mensual.

Los jobs deben ser idempotentes: ejecutarlos dos veces no debe duplicar recibos, cuotas, pagos ni notificaciones.

---

## 27. Manejo de errores

Cada proceso automático debe indicar:

- qué intentó hacer;
- cuándo;
- resultado;
- mensaje técnico interno;
- mensaje amigable para usuario;
- si se reintentará;
- si requiere intervención.

Ejemplo visible:

> No pudimos actualizar SEDAPAL. Reintentaremos automáticamente. También puedes registrar el recibo manualmente.

No mostrar stack traces ni secretos al usuario.

---

## 28. Requisitos no funcionales

### Rendimiento

- Inicio debe cargar únicamente información necesaria del periodo actual.
- Listados históricos deben paginarse.
- Imágenes/comprobantes no deben bloquear la vista principal.
- Consultas frecuentes deben contar con índices apropiados.

### Disponibilidad

Un fallo de un proveedor externo no debe impedir usar las demás funciones.

### Mantenibilidad

- componentes reutilizables;
- dominio claramente separado de integración externa;
- adaptador independiente por proveedor;
- validaciones centralizadas;
- tipos compartidos;
- migraciones versionadas.

### Observabilidad

- errores de frontend;
- errores de Edge Functions;
- fallos de cron;
- sincronizaciones;
- webhooks;
- operaciones críticas.

---

## 29. MVP funcional

La primera versión utilizable deberá incluir:

- Login personal.
- Invitaciones familiares.
- Roles Administrador/Integrante.
- Inicio personalizado.
- Categorías.
- Conceptos/servicios.
- Participantes por concepto.
- Recibos recurrentes.
- Monto fijo/manual/automático mediante adaptadores disponibles.
- División igualitaria.
- División personalizada.
- Mis cuotas.
- Total del recibo + cuota personal.
- Estado de participantes.
- Pago mediante cuenta familiar/QR.
- Registro de comprobante.
- Validación de pago.
- Pagos parciales.
- Recaudación.
- Pago al proveedor.
- Calendario.
- Notificaciones internas.
- Historial.
- Cierre/resumen mensual.
- PWA responsive.
- Preparación para Android/iOS mediante Capacitor.

---

## 30. Funciones posteriores, no bloqueantes para V1

- Confirmación automática mediante gateway/webhook.
- Push nativo.
- Biometría.
- Pago múltiple de varias cuotas con una sola operación.
- Comparación contra meses anteriores.
- Detección de consumos atípicos.
- Resúmenes inteligentes.
- Más proveedores.
- Exportación de historial.
- Widget móvil.
- Integraciones adicionales autorizadas.

Estas funciones no deben retrasar el flujo principal del MVP.

---

## 31. Criterios de éxito del producto

FamiliaHub será exitoso cuando un integrante pueda:

1. iniciar sesión;
2. ver inmediatamente cuánto debe;
3. abrir un recibo;
4. visualizar monto total y su cuota;
5. entender cuándo vence;
6. pagar;
7. conocer si su pago fue confirmado;
8. revisar su historial;

sin necesitar preguntar en WhatsApp ni realizar cálculos externos.

Para el administrador será exitoso cuando pueda:

1. configurar cada servicio una sola vez;
2. permitir que FamiliaHub genere el trabajo repetitivo;
3. identificar rápidamente excepciones;
4. conocer quién falta pagar;
5. conocer si el proveedor ya fue pagado;
6. cerrar el mes con información confiable.

---

## 32. Definición funcional final

FamiliaHub es un asistente familiar de recibos y cuotas.

Su flujo esencial es:

Concepto → obtención del recibo → participantes → cuotas → aportes → recaudación → pago al proveedor → historial.

La complejidad debe existir internamente para que la experiencia externa siga siendo simple.
