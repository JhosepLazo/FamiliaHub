# Pruebas E2E de usuarios y pagos

Este directorio contiene pruebas de integración de Supabase que utilizan usuarios **reales** de Auth, pero nunca requieren conocer sus contraseñas.

## Flujo cubierto

El archivo `e2e_flujo_familiar.sql` valida:

1. que ambos usuarios existan y tengan correo confirmado;
2. que los usernames sean `Jhosep` y `Liliana`;
3. creación de familia con Jhosep como administrador;
4. contexto de Liliana como integrante;
5. configuración de Yape;
6. creación de un servicio de prueba;
7. generación automática de recibo y cuotas;
8. envío de un pago de Liliana;
9. bloqueo de autovalidación;
10. bloqueo de acciones administrativas para Liliana;
11. validación del pago por Jhosep;
12. actualización de la cuota a `PAGADA`;
13. reversión del pago;
14. restauración de la cuota.

Todo el escenario termina con `Rollback`, por lo que no conserva movimientos financieros ficticios.

## Lo que se prueba aparte

La invitación por correo utiliza las Edge Functions `invitar-integrante` y `aceptar-invitacion`. Ese recorrido necesita una sesión/llamada HTTP real y se valida por separado durante el onboarding de los usuarios.

## Datos personales

Los correos no deben escribirse dentro del archivo SQL ni subirse al repositorio. Se suministran únicamente como variables de sesión:

```sql
Select set_config('familiahub.e2e_jhosep_email', '<correo-admin>', false);
Select set_config('familiahub.e2e_liliana_email', '<correo-integrante>', false);
```

Después se ejecuta `e2e_flujo_familiar.sql`.
