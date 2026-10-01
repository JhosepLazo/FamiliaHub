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

### Funcionalidad disponible

- Login y sesión persistente.
- Registro de acceso personal.
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

Las claves secretas de Supabase nunca pertenecen al frontend ni al repositorio. Las operaciones privilegiadas se ejecutan en Edge Functions.

## Flujo actual

```text
Acceso personal
    ↓
Login / Registro / Recuperación
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

La siguiente fase incorpora conceptos y servicios del hogar; todavía no se crean recibos ni cuotas.

## Documentación

- [Documentación funcional](./01_DOCUMENTACION_FUNCIONAL.md)
- [Plan de creación y flujo por fases](./02_PLAN_CREACION_Y_FLUJO_POR_FASES.md)

## Regla principal

> Si FamiliaHub puede obtener, calcular, distribuir, recordar o actualizar algo automáticamente, no debe pedirle al usuario que lo haga manualmente.
