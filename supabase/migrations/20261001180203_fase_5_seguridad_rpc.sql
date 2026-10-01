create index idx_conceptos_pago_plantilla on public.conceptos_pago(plantilla_id);

revoke all on function public.crear_proveedor_personalizado(uuid, text, public.tipo_servicio) from public, anon, authenticated;
revoke all on function public.cambiar_estado_proveedor_personalizado(uuid, boolean) from public, anon, authenticated;
revoke all on function public.cambiar_estado_concepto(uuid, boolean) from public, anon, authenticated;
revoke all on function public.guardar_concepto_servicio(
	uuid,
	uuid,
	uuid,
	uuid,
	uuid,
	text,
	public.frecuencia_concepto,
	public.metodo_obtencion_monto,
	numeric,
	public.tipo_vencimiento_concepto,
	smallint,
	public.tipo_distribucion_concepto,
	public.tipo_reparto_resto,
	boolean,
	jsonb,
	jsonb
) from public, anon, authenticated;

alter function public.crear_proveedor_personalizado(uuid, text, public.tipo_servicio) set schema app_private;
alter function app_private.crear_proveedor_personalizado(uuid, text, public.tipo_servicio) rename to crear_proveedor_personalizado_impl;

alter function public.cambiar_estado_proveedor_personalizado(uuid, boolean) set schema app_private;
alter function app_private.cambiar_estado_proveedor_personalizado(uuid, boolean) rename to cambiar_estado_proveedor_personalizado_impl;

alter function public.cambiar_estado_concepto(uuid, boolean) set schema app_private;
alter function app_private.cambiar_estado_concepto(uuid, boolean) rename to cambiar_estado_concepto_impl;

alter function public.guardar_concepto_servicio(
	uuid,
	uuid,
	uuid,
	uuid,
	uuid,
	text,
	public.frecuencia_concepto,
	public.metodo_obtencion_monto,
	numeric,
	public.tipo_vencimiento_concepto,
	smallint,
	public.tipo_distribucion_concepto,
	public.tipo_reparto_resto,
	boolean,
	jsonb,
	jsonb
) set schema app_private;

alter function app_private.guardar_concepto_servicio(
	uuid,
	uuid,
	uuid,
	uuid,
	uuid,
	text,
	public.frecuencia_concepto,
	public.metodo_obtencion_monto,
	numeric,
	public.tipo_vencimiento_concepto,
	smallint,
	public.tipo_distribucion_concepto,
	public.tipo_reparto_resto,
	boolean,
	jsonb,
	jsonb
) rename to guardar_concepto_servicio_impl;

revoke all on function app_private.crear_proveedor_personalizado_impl(uuid, text, public.tipo_servicio) from public, anon;
revoke all on function app_private.cambiar_estado_proveedor_personalizado_impl(uuid, boolean) from public, anon;
revoke all on function app_private.cambiar_estado_concepto_impl(uuid, boolean) from public, anon;
revoke all on function app_private.guardar_concepto_servicio_impl(
	uuid,
	uuid,
	uuid,
	uuid,
	uuid,
	text,
	public.frecuencia_concepto,
	public.metodo_obtencion_monto,
	numeric,
	public.tipo_vencimiento_concepto,
	smallint,
	public.tipo_distribucion_concepto,
	public.tipo_reparto_resto,
	boolean,
	jsonb,
	jsonb
) from public, anon;

grant usage on schema app_private to authenticated;
grant execute on function app_private.crear_proveedor_personalizado_impl(uuid, text, public.tipo_servicio) to authenticated;
grant execute on function app_private.cambiar_estado_proveedor_personalizado_impl(uuid, boolean) to authenticated;
grant execute on function app_private.cambiar_estado_concepto_impl(uuid, boolean) to authenticated;
grant execute on function app_private.guardar_concepto_servicio_impl(
	uuid,
	uuid,
	uuid,
	uuid,
	uuid,
	text,
	public.frecuencia_concepto,
	public.metodo_obtencion_monto,
	numeric,
	public.tipo_vencimiento_concepto,
	smallint,
	public.tipo_distribucion_concepto,
	public.tipo_reparto_resto,
	boolean,
	jsonb,
	jsonb
) to authenticated;

create function public.crear_proveedor_personalizado(
	p_familia_id uuid,
	p_nombre text,
	p_tipo_servicio public.tipo_servicio
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
	select app_private.crear_proveedor_personalizado_impl(p_familia_id, p_nombre, p_tipo_servicio);
$$;

create function public.cambiar_estado_proveedor_personalizado(
	p_proveedor_id uuid,
	p_activo boolean
)
returns void
language sql
security invoker
set search_path = ''
as $$
	select app_private.cambiar_estado_proveedor_personalizado_impl(p_proveedor_id, p_activo);
$$;

create function public.cambiar_estado_concepto(
	p_concepto_id uuid,
	p_activo boolean
)
returns void
language sql
security invoker
set search_path = ''
as $$
	select app_private.cambiar_estado_concepto_impl(p_concepto_id, p_activo);
$$;

create function public.guardar_concepto_servicio(
	p_concepto_id uuid,
	p_familia_id uuid,
	p_categoria_id uuid,
	p_proveedor_id uuid,
	p_plantilla_id uuid,
	p_nombre text,
	p_frecuencia public.frecuencia_concepto,
	p_metodo_obtencion public.metodo_obtencion_monto,
	p_monto_fijo numeric,
	p_tipo_vencimiento public.tipo_vencimiento_concepto,
	p_dia_vencimiento smallint,
	p_tipo_distribucion public.tipo_distribucion_concepto,
	p_reparto_resto public.tipo_reparto_resto,
	p_fallback_manual boolean,
	p_cuenta jsonb,
	p_participantes jsonb
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
	select app_private.guardar_concepto_servicio_impl(
		p_concepto_id,
		p_familia_id,
		p_categoria_id,
		p_proveedor_id,
		p_plantilla_id,
		p_nombre,
		p_frecuencia,
		p_metodo_obtencion,
		p_monto_fijo,
		p_tipo_vencimiento,
		p_dia_vencimiento,
		p_tipo_distribucion,
		p_reparto_resto,
		p_fallback_manual,
		p_cuenta,
		p_participantes
	);
$$;

revoke all on function public.crear_proveedor_personalizado(uuid, text, public.tipo_servicio) from public, anon;
revoke all on function public.cambiar_estado_proveedor_personalizado(uuid, boolean) from public, anon;
revoke all on function public.cambiar_estado_concepto(uuid, boolean) from public, anon;
revoke all on function public.guardar_concepto_servicio(
	uuid,
	uuid,
	uuid,
	uuid,
	uuid,
	text,
	public.frecuencia_concepto,
	public.metodo_obtencion_monto,
	numeric,
	public.tipo_vencimiento_concepto,
	smallint,
	public.tipo_distribucion_concepto,
	public.tipo_reparto_resto,
	boolean,
	jsonb,
	jsonb
) from public, anon;

grant execute on function public.crear_proveedor_personalizado(uuid, text, public.tipo_servicio) to authenticated;
grant execute on function public.cambiar_estado_proveedor_personalizado(uuid, boolean) to authenticated;
grant execute on function public.cambiar_estado_concepto(uuid, boolean) to authenticated;
grant execute on function public.guardar_concepto_servicio(
	uuid,
	uuid,
	uuid,
	uuid,
	uuid,
	text,
	public.frecuencia_concepto,
	public.metodo_obtencion_monto,
	numeric,
	public.tipo_vencimiento_concepto,
	smallint,
	public.tipo_distribucion_concepto,
	public.tipo_reparto_resto,
	boolean,
	jsonb,
	jsonb
) to authenticated;
