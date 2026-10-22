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

## Asistente de WhatsApp (Fase 12)

El archivo `e2e_whatsapp.sql` usa los mismos usuarios E2E y las mismas variables de sesión. Requiere que ninguno de los dos pertenezca a una familia activa, porque crea una familia de prueba dentro de la transacción.

Valida, sin enviar ningún mensaje real:

1. códigos de vinculación: solo administradores generan el de grupo, regenerar reemplaza el anterior, un solo uso y 10 minutos de vigencia;
2. permisos: `authenticated` no lee las tablas `whatsapp_*` ni ejecuta las funciones de `service_role`;
3. vinculación de grupo e integrantes, con rechazo de códigos equivocados, grupos ajenos, IDs repetidos (principal o alterno) e integrantes inactivos;
4. reconocimiento del integrante por su ID alterno (LID o número);
5. `/deuda`, `/pendientes`, `/resumen`, `/recibo`, `/recibos`, `/vence`, `/pagar` y `/porvalidar` con las mismas reglas de la app;
6. `/avisos` y `guardar_configuracion_whatsapp` solo para administradores, con validación de claves y rangos;
7. avisos `POR_VENCER`, `VENCE_HOY`, `VENCIDO`, `RECIBO_MONTO`, `RECAUDACION_COMPLETA`, `PENDIENTES_ADMIN`, `PAGO_ENVIADO` y `PAGO_CONFIRMADO`, sin duplicados aunque los jobs corran dos veces;
8. descarte de eventos de más de 12 horas, ventana horaria, expiración, reintentos y pausa de avisos;
9. salida del bot del grupo, heartbeat y pérdida del vínculo al pasar a `INACTIVO`.

Las funciones de los jobs (`whatsapp_procesar_eventos`, `whatsapp_generar_avisos_familia`) se llaman directamente; no hace falta esperar a `pg_cron`. Para que el resultado no dependa de la hora de ejecución, la prueba configura una ventana de envío de 00:00 a 23:59 dentro de la transacción.

```sql
Select set_config('familiahub.e2e_jhosep_email', '<correo-admin>', false);
Select set_config('familiahub.e2e_liliana_email', '<correo-integrante>', false);
```

Después se ejecuta `e2e_whatsapp.sql`. El resultado es una tabla con una fila por prueba (`OK` o `ERROR` y el detalle). Todo termina con `Rollback`.

## Recibos digitales

El archivo `e2e_recibos_digitales.sql` usa los mismos usuarios y variables de sesión, y crea dos servicios con número de suministro (Luz del Sur y SEDAPAL). Valida `registrar_recibo_digital` como lo llama la Edge Function `recibos-digitales`:

1. confirmación del recibo del mes con el monto y el vencimiento del correo, con cuotas y evento `MONTO_CONFIRMADO`;
2. correo repetido sin efecto y recibo ya confirmado ignorado;
3. suministro desconocido o de otro proveedor ignorado;
4. datos inválidos rechazados;
5. monto muy distinto al anterior y vencimiento absurdo marcados para revisar;
6. lectura en espera aplicada después por el job `aplicar_recibos_digitales_en_espera`;
7. permisos: solo `service_role` puede registrar.

Todo termina con `Rollback`.

## Estrés

El archivo `estres.sql` usa los mismos usuarios y variables de sesión, y crea su propia familia con Luz y Agua, un grupo y un integrante vinculados (datos ficticios). Comprueba, todo dentro de una transacción que termina con `Rollback`:

1. 1 000 consultas del bot (`/deuda`, `/pendientes`, `/recibos`, `/resumen`, `/vence`) que devuelven siempre la misma respuesta;
2. el mismo correo de recibo digital 500 veces: una sola lectura, sin cuotas ni confirmaciones de más;
3. 300 correos de suministros ajenos: todos ignorados y sin tocar ningún recibo;
4. 120 avisos y 200 tomas seguidas: cada aviso se entrega una sola vez.

Cada fila muestra también cuánto tardó.

## Eliminar servicios

`e2e_eliminar_servicio.sql` valida `eliminar_concepto_servicio`: un integrante no puede eliminar; sin dinero movido el servicio se borra con sus recibos (también con cuotas confirmadas o un pago preparado sin enviar); con un pago por validar se bloquea; con pagos se archiva conservando su historial y anulando solo los recibos abiertos sin movimientos; el nombre queda libre; eliminar dos veces falla y sincronizar el periodo no los revive.

## Estrés de todos los procesos

`estres_flujos.sql` crea una familia de tres personas (un tercer usuario ficticio dentro de la transacción) con ocho servicios y ejecuta 300 rondas de pagos de integrantes con validaciones, rechazos, anulaciones y pagos pendientes; 12 intentos indebidos (pagar de más, pagar lo reservado o la cuota de otro, validar su propio pago, acciones de administrador, ver otra familia); corrección de monto, adelanto y su anulación, pago desde el fondo con recaudación completa, anulación de recibo y eliminación de servicios. Al final comprueba que los repartos sumen el total, que los saldos y estados cuadren con los aportes, que lo reservado no supere el saldo y que no haya dos pagos a la empresa por recibo.

## Recibos digitales vigilados

`e2e_recibos_digitales_vigilados.sql` valida el suministro oculto (`*6543` se confirma si coincide con un solo servicio activo, se rechaza con menos de 4 cifras y queda para revisar si coincide con dos) y el aviso único de WhatsApp cuando el recibo digital de un servicio no llega a tiempo (se espera desde 5 días antes del vencimiento del mes anterior, o el día 25 sin historial; no se repite aunque la revisión corra varias veces y no se avisa de servicios cuyo recibo ya llegó).
