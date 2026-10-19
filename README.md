# FamiliaHub

Asistente privado para organizar recibos, cuotas y pagos familiares.

## Stack

- React 19 + TypeScript
- Vite
- Tailwind CSS
- Supabase
- PWA / Capacitor en fases posteriores

## Estado actual

### Fases completadas

- Fase 0: base del repositorio.
- Fase 2: Supabase y seguridad base.
- Fase 3: acceso personal e invitaciones.
- Fase 4: configuración familiar.
- Fase 5: conceptos y servicios del hogar.
- Fase 6: periodos, recibos y motor financiero de cuotas.
- Fase 7: Inicio inteligente y Mis cuotas.
- Fase 8: pagos, Yape, comprobantes y Pagar todo.

### Funcionalidad disponible

- Login por usuario + contraseña y sesión persistente.
- Registro con correo verificado, usuario único y contraseña.
- Recuperación y cambio de contraseña.
- Creación inicial de familia.
- Perfil personal.
- Roles Administrador / Integrante.
- Activación y desactivación de integrantes.
- Protección para conservar al menos un administrador activo.
- Invitaciones privadas con token de un solo uso y expiración de 7 días.
- Enlaces de invitación compartibles por WhatsApp u otros canales.
- Categorías familiares.
- Cuenta receptora familiar.
- QR privado almacenado en Supabase Storage.
- RLS por familia.
- Edge Functions protegidas para crear y aceptar invitaciones.
- Catálogo de proveedores y proveedores personalizados.
- Plantillas inteligentes para Agua, Luz, Internet y Gas.
- Cuenta de servicio mediante identificador real del proveedor.
- Frecuencia, método de monto y vencimiento por concepto.
- Participantes explícitos por servicio.
- División igual, porcentual, monto fijo y mixta.
- Activación/desactivación lógica sin borrar historial.
- Periodos automáticos por mes y cron diario idempotente.
- Recibos con snapshot histórico de servicio, proveedor, cuenta y participantes.
- Cuotas determinísticas con redondeo en centavos.
- Aportes parciales y validación.
- Adelanto de un integrante con reembolsos automáticos.
- Pago al proveedor separado de la recaudación familiar.
- Correcciones mediante ajustes auditables.
- Cierre automático o manual cuando todo está resuelto.
- Inicio personal con deuda, pagado, pendientes y próximo vencimiento.
- Priorización automática de cuotas vencidas y próximas.
- Mis cuotas con filtros Pendientes / Pagadas / Todas.
- Bloque administrativo “Necesita tu atención” basado en excepciones reales.
- Navegación móvil diferenciada por rol sin perder acceso a Familia/Configuración.
- Métodos de cobro familiares: Yape, transferencia, efectivo y otro.
- Métodos de cobro personales para recibir reembolsos.
- QR privados en Supabase Storage.
- Pago individual o agrupado de varias cuotas.
- Pagar todo agrupado automáticamente por receptor.
- Pagos parciales sin sobrepasar el saldo disponible.
- Referencia o comprobante obligatorio para Yape/transferencia.
- Comprobantes privados para aportes familiares y reembolsos.
- Validación por administrador o receptor responsable.
- Aplicación atómica de pagos multi-cuota.
- Historial de pagos, rechazos y anulaciones.
- Comprobante independiente del pago al proveedor.

## Desarrollo local

1. Instala dependencias:

```bash
npm install
```

2. Crea `.env.local` a partir de `.env.example`.

3. Ejecuta:

```bash
npm run dev
```

## Variables del proyecto

El navegador utiliza únicamente:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`

Las claves secretas de Supabase nunca pertenecen al frontend ni al repositorio. Las operaciones privilegiadas se ejecutan en Edge Functions o funciones privadas de base de datos con validación explícita, según el flujo.

## Flujo actual

```text
Acceso personal
    ↓
Registro: correo + usuario + contraseña
    ↓
Confirmación de correo
    ↓
Login diario: usuario + contraseña
    ↓
Recuperación: correo
    ↓
¿Pertenece a una familia?
    ├── No → Crear familia o aceptar invitación
    └── Sí → Inicio
               ↓
            Familia
               ↓
        Integrantes y roles
               ↓
          Configuración
               ↓
 Categorías + cuenta receptora
```

La Fase 8 completa el pago manual asistido: FamiliaHub prepara el importe, separa receptores, muestra Yape/cuenta/QR, recibe referencia o comprobante privado y mantiene el pago en validación hasta que el receptor real o un administrador lo confirme. “Pagar todo” utiliza una cabecera de pago con asignaciones multi-cuota y nunca mezcla destinatarios distintos en una sola operación externa.

## Documentación

- [Documentación funcional](./01_DOCUMENTACION_FUNCIONAL.md)
- [Plan de creación y flujo por fases](./02_PLAN_CREACION_Y_FLUJO_POR_FASES.md)

## Regla principal

> Si FamiliaHub puede obtener, calcular, distribuir, recordar o actualizar algo automáticamente, no debe pedirle al usuario que lo haga manualmente.
