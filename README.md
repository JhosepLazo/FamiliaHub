# FamiliaHub

Asistente privado para organizar recibos, cuotas y pagos familiares.

## Stack

- React 19 + TypeScript
- Vite
- Tailwind CSS
- Supabase
- PWA / Capacitor en fases posteriores

## Estado actual

La implementación comenzó con:

- proyecto Supabase `FamiliaHub`;
- autenticación preparada con Supabase Auth;
- esquema base de familias e integrantes;
- Row Level Security desde el inicio;
- perfiles;
- invitaciones;
- categorías;
- periodos;
- Login responsive;
- tipos TypeScript generados desde la base real.

## Desarrollo local

1. Instala dependencias:

```bash
npm install
```

2. Crea `.env.local` a partir de `.env.example`.

3. Configura:

```env
VITE_SUPABASE_URL=https://TU_PROYECTO.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_xxxxxxxxx
```

4. Ejecuta:

```bash
npm run dev
```

## Variables del proyecto

Las claves secretas de Supabase no pertenecen al frontend ni al repositorio.

El navegador utiliza únicamente:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`

Las operaciones sensibles e integraciones externas se implementarán en backend/Edge Functions.

## Documentación

- [Documentación funcional](./01_DOCUMENTACION_FUNCIONAL.md)
- [Plan de creación y flujo por fases](./02_PLAN_CREACION_Y_FLUJO_POR_FASES.md)

## Regla principal

> Si FamiliaHub puede obtener, calcular, distribuir, recordar o actualizar algo automáticamente, no debe pedirle al usuario que lo haga manualmente.
