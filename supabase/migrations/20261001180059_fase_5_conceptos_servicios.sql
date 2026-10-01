create type public.tipo_servicio as enum ('AGUA', 'LUZ', 'INTERNET', 'GAS', 'OTRO');
create type public.frecuencia_concepto as enum ('MENSUAL', 'ANUAL', 'UNICA');
create type public.metodo_obtencion_monto as enum ('MANUAL', 'FIJO', 'AUTOMATICO');
create type public.tipo_vencimiento_concepto as enum ('DIA_FIJO', 'VARIABLE', 'PROVEEDOR');
create type public.tipo_distribucion_concepto as enum ('IGUAL', 'PORCENTAJE', 'MONTO_FIJO', 'MIXTA');
create type public.tipo_reparto_resto as enum ('IGUAL', 'PORCENTAJE');
create type public.modalidad_participante_concepto as enum ('IGUAL', 'PORCENTAJE', 'MONTO_FIJO', 'RESTO_IGUAL', 'RESTO_PORCENTAJE');
create type public.estado_integracion_proveedor as enum ('NO_DISPONIBLE', 'PREPARADO', 'DISPONIBLE');

create table public.proveedores (
	id uuid primary key default gen_random_uuid(),
	familia_id uuid references public.familias(id) on delete cascade,
	codigo text,
	nombre text not null,
	tipo_servicio public.tipo_servicio not null,
	es_sistema boolean not null default false,
	estado_integracion public.estado_integracion_proveedor not null default 'NO_DISPONIBLE',
	activo boolean not null default true,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now(),
	check (
		(es_sistema = true and familia_id is null and codigo is not null)
		or
		(es_sistema = false and familia_id is not null and codigo is null)
	)
);

create unique index ux_proveedores_sistema_codigo
on public.proveedores(codigo)
where familia_id is null;

create unique index ux_proveedores_personalizado_nombre
on public.proveedores(familia_id, lower(nombre))
where familia_id is not null;

create index idx_proveedores_familia on public.proveedores(familia_id);

create table public.tipos_identificador_proveedor (
	id uuid primary key default gen_random_uuid(),
	proveedor_id uuid not null references public.proveedores(id) on delete cascade,
	codigo text not null,
	nombre text not null,
	ayuda text,
	orden smallint not null default 1 check (orden > 0),
	activo boolean not null default true,
	created_at timestamptz not null default now(),
	unique (proveedor_id, codigo)
);

create index idx_tipos_identificador_proveedor on public.tipos_identificador_proveedor(proveedor_id, orden);

create table public.plantillas_servicio (
	id uuid primary key default gen_random_uuid(),
	codigo text not null unique,
	nombre text not null,
	tipo_servicio public.tipo_servicio not null,
	icono text not null,
	descripcion text,
	frecuencia_recomendada public.frecuencia_concepto not null default 'MENSUAL',
	metodo_obtencion_recomendado public.metodo_obtencion_monto not null default 'AUTOMATICO',
	tipo_vencimiento_recomendado public.tipo_vencimiento_concepto not null default 'PROVEEDOR',
	orden smallint not null default 1 check (orden > 0),
	activo boolean not null default true,
	created_at timestamptz not null default now()
);

create table public.conceptos_pago (
	id uuid primary key default gen_random_uuid(),
	familia_id uuid not null references public.familias(id) on delete cascade,
	categoria_id uuid not null references public.categorias(id),
	proveedor_id uuid not null references public.proveedores(id),
	plantilla_id uuid references public.plantillas_servicio(id),
	nombre text not null,
	frecuencia public.frecuencia_concepto not null default 'MENSUAL',
	metodo_obtencion public.metodo_obtencion_monto not null,
	monto_fijo numeric(12,2),
	tipo_vencimiento public.tipo_vencimiento_concepto not null,
	dia_vencimiento smallint,
	tipo_distribucion public.tipo_distribucion_concepto not null default 'IGUAL',
	reparto_resto public.tipo_reparto_resto,
	fallback_manual boolean not null default true,
	activo boolean not null default true,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now(),
	check (
		(metodo_obtencion = 'FIJO' and monto_fijo is not null and monto_fijo > 0)
		or
		(metodo_obtencion <> 'FIJO' and monto_fijo is null)
	),
	check (
		(tipo_vencimiento = 'DIA_FIJO' and dia_vencimiento between 1 and 31)
		or
		(tipo_vencimiento <> 'DIA_FIJO' and dia_vencimiento is null)
	),
	check (
		(tipo_distribucion = 'MIXTA' and reparto_resto is not null)
		or
		(tipo_distribucion <> 'MIXTA' and reparto_resto is null)
	),
	check (metodo_obtencion <> 'AUTOMATICO' or fallback_manual = true)
);

create unique index ux_conceptos_pago_familia_nombre
on public.conceptos_pago(familia_id, lower(nombre));

create index idx_conceptos_pago_familia_activo on public.conceptos_pago(familia_id, activo);
create index idx_conceptos_pago_categoria on public.conceptos_pago(categoria_id);
create index idx_conceptos_pago_proveedor on public.conceptos_pago(proveedor_id);

create table public.cuentas_servicio (
	id uuid primary key default gen_random_uuid(),
	concepto_id uuid not null unique references public.conceptos_pago(id) on delete cascade,
	tipo_identificador_id uuid references public.tipos_identificador_proveedor(id),
	identificador_nombre text,
	identificador_valor text not null,
	alias text,
	activo boolean not null default true,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now(),
	check (nullif(trim(identificador_valor), '') is not null),
	check (
		tipo_identificador_id is not null
		or nullif(trim(identificador_nombre), '') is not null
	)
);

create index idx_cuentas_servicio_identificador on public.cuentas_servicio(tipo_identificador_id);

create table public.concepto_participantes (
	id uuid primary key default gen_random_uuid(),
	concepto_id uuid not null references public.conceptos_pago(id) on delete cascade,
	miembro_id uuid not null references public.miembros_familia(id),
	modalidad public.modalidad_participante_concepto not null,
	valor numeric(12,4),
	orden smallint not null default 1 check (orden > 0),
	created_at timestamptz not null default now(),
	unique (concepto_id, miembro_id),
	check (
		(modalidad in ('IGUAL', 'RESTO_IGUAL') and valor is null)
		or
		(modalidad in ('PORCENTAJE', 'RESTO_PORCENTAJE') and valor is not null and valor > 0 and valor <= 100)
		or
		(modalidad = 'MONTO_FIJO' and valor is not null and valor > 0 and round(valor, 2) = valor)
	)
);

create index idx_concepto_participantes_concepto on public.concepto_participantes(concepto_id, orden);
create index idx_concepto_participantes_miembro on public.concepto_participantes(miembro_id);

alter table public.proveedores enable row level security;
alter table public.tipos_identificador_proveedor enable row level security;
alter table public.plantillas_servicio enable row level security;
alter table public.conceptos_pago enable row level security;
alter table public.cuentas_servicio enable row level security;
alter table public.concepto_participantes enable row level security;

create policy proveedores_select
on public.proveedores
for select
to authenticated
using (
	(familia_id is null and activo = true)
	or
	(familia_id is not null and app_private.es_miembro(familia_id, (select auth.uid())))
);

create policy tipos_identificador_select
on public.tipos_identificador_proveedor
for select
to authenticated
using (
	exists (
		select 1
		from public.proveedores
		where proveedores.id = tipos_identificador_proveedor.proveedor_id
			and (
				(proveedores.familia_id is null and proveedores.activo = true)
				or
				(proveedores.familia_id is not null and app_private.es_miembro(proveedores.familia_id, (select auth.uid())))
			)
	)
);

create policy plantillas_servicio_select
on public.plantillas_servicio
for select
to authenticated
using (activo = true);

create policy conceptos_pago_select
on public.conceptos_pago
for select
to authenticated
using (app_private.es_miembro(familia_id, (select auth.uid())));

create policy cuentas_servicio_select
on public.cuentas_servicio
for select
to authenticated
using (
	exists (
		select 1
		from public.conceptos_pago
		where conceptos_pago.id = cuentas_servicio.concepto_id
			and app_private.es_miembro(conceptos_pago.familia_id, (select auth.uid()))
	)
);

create policy concepto_participantes_select
on public.concepto_participantes
for select
to authenticated
using (
	exists (
		select 1
		from public.conceptos_pago
		where conceptos_pago.id = concepto_participantes.concepto_id
			and app_private.es_miembro(conceptos_pago.familia_id, (select auth.uid()))
	)
);

grant select on public.proveedores to authenticated;
grant select on public.tipos_identificador_proveedor to authenticated;
grant select on public.plantillas_servicio to authenticated;
grant select on public.conceptos_pago to authenticated;
grant select on public.cuentas_servicio to authenticated;
grant select on public.concepto_participantes to authenticated;

create or replace function public.crear_proveedor_personalizado(
	p_familia_id uuid,
	p_nombre text,
	p_tipo_servicio public.tipo_servicio
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_proveedor_id uuid;
begin
	if v_usuario_id is null then
		raise exception 'Debes iniciar sesión.';
	end if;

	if not app_private.es_admin(p_familia_id, v_usuario_id) then
		raise exception 'Solo un administrador puede crear proveedores.';
	end if;

	if nullif(trim(p_nombre), '') is null then
		raise exception 'El nombre del proveedor es obligatorio.';
	end if;

	insert into public.proveedores (
		familia_id,
		nombre,
		tipo_servicio,
		es_sistema,
		estado_integracion
	)
	values (
		p_familia_id,
		trim(p_nombre),
		p_tipo_servicio,
		false,
		'NO_DISPONIBLE'
	)
	returning id into v_proveedor_id;

	return v_proveedor_id;
exception
	when unique_violation then
		raise exception 'Ya existe un proveedor personalizado con ese nombre.';
end;
$$;

revoke all on function public.crear_proveedor_personalizado(uuid, text, public.tipo_servicio) from public;
grant execute on function public.crear_proveedor_personalizado(uuid, text, public.tipo_servicio) to authenticated;

create or replace function public.cambiar_estado_proveedor_personalizado(
	p_proveedor_id uuid,
	p_activo boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_familia_id uuid;
	v_es_sistema boolean;
begin
	select familia_id, es_sistema
	into v_familia_id, v_es_sistema
	from public.proveedores
	where id = p_proveedor_id;

	if v_familia_id is null or v_es_sistema is true then
		raise exception 'Solo puedes modificar proveedores personalizados.';
	end if;

	if not app_private.es_admin(v_familia_id, v_usuario_id) then
		raise exception 'Solo un administrador puede modificar proveedores.';
	end if;

	if p_activo = false and exists (
		select 1
		from public.conceptos_pago
		where proveedor_id = p_proveedor_id
			and activo = true
	) then
		raise exception 'Desactiva primero los servicios activos asociados a este proveedor.';
	end if;

	update public.proveedores
	set activo = p_activo,
		updated_at = now()
	where id = p_proveedor_id;
end;
$$;

revoke all on function public.cambiar_estado_proveedor_personalizado(uuid, boolean) from public;
grant execute on function public.cambiar_estado_proveedor_personalizado(uuid, boolean) to authenticated;

create or replace function public.cambiar_estado_concepto(
	p_concepto_id uuid,
	p_activo boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_familia_id uuid;
	v_proveedor_activo boolean;
begin
	select c.familia_id, p.activo
	into v_familia_id, v_proveedor_activo
	from public.conceptos_pago c
	inner join public.proveedores p on p.id = c.proveedor_id
	where c.id = p_concepto_id;

	if v_familia_id is null then
		raise exception 'Servicio no encontrado.';
	end if;

	if not app_private.es_admin(v_familia_id, v_usuario_id) then
		raise exception 'Solo un administrador puede modificar servicios.';
	end if;

	if p_activo = true and v_proveedor_activo = false then
		raise exception 'Activa primero el proveedor asociado.';
	end if;

	update public.conceptos_pago
	set activo = p_activo,
		updated_at = now()
	where id = p_concepto_id;
end;
$$;

revoke all on function public.cambiar_estado_concepto(uuid, boolean) from public;
grant execute on function public.cambiar_estado_concepto(uuid, boolean) to authenticated;

create or replace function public.guardar_concepto_servicio(
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
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_usuario_id uuid := auth.uid();
	v_concepto_id uuid;
	v_proveedor_tipo public.tipo_servicio;
	v_total integer;
	v_distintos integer;
	v_suma numeric;
	v_fijos numeric;
	v_cuenta_valor text;
	v_cuenta_nombre text;
	v_tipo_identificador_id uuid;
begin
	if v_usuario_id is null then
		raise exception 'Debes iniciar sesión.';
	end if;

	if not app_private.es_admin(p_familia_id, v_usuario_id) then
		raise exception 'Solo un administrador puede configurar servicios.';
	end if;

	if nullif(trim(p_nombre), '') is null then
		raise exception 'El nombre del servicio es obligatorio.';
	end if;

	if not exists (
		select 1
		from public.categorias
		where id = p_categoria_id
			and familia_id = p_familia_id
			and activo = true
	) then
		raise exception 'La categoría seleccionada no pertenece a la familia o está inactiva.';
	end if;

	select tipo_servicio
	into v_proveedor_tipo
	from public.proveedores
	where id = p_proveedor_id
		and activo = true
		and (
			familia_id is null
			or familia_id = p_familia_id
		);

	if v_proveedor_tipo is null then
		raise exception 'El proveedor seleccionado no está disponible para esta familia.';
	end if;

	if p_plantilla_id is not null and not exists (
		select 1
		from public.plantillas_servicio
		where id = p_plantilla_id
			and activo = true
			and tipo_servicio = v_proveedor_tipo
	) then
		raise exception 'La plantilla no corresponde al tipo de proveedor seleccionado.';
	end if;

	if p_metodo_obtencion = 'FIJO' then
		if p_monto_fijo is null or p_monto_fijo <= 0 or round(p_monto_fijo, 2) <> p_monto_fijo then
			raise exception 'El monto fijo debe ser mayor a cero y tener máximo dos decimales.';
		end if;
	elsif p_monto_fijo is not null then
		raise exception 'Solo los servicios de monto fijo pueden guardar un monto fijo.';
	end if;

	if p_tipo_vencimiento = 'DIA_FIJO' then
		if p_dia_vencimiento is null or p_dia_vencimiento < 1 or p_dia_vencimiento > 31 then
			raise exception 'El día de vencimiento debe estar entre 1 y 31.';
		end if;
	elsif p_dia_vencimiento is not null then
		raise exception 'Solo el vencimiento de día fijo puede guardar un día.';
	end if;

	if p_metodo_obtencion = 'AUTOMATICO' and coalesce(p_fallback_manual, false) = false then
		raise exception 'Todo servicio automático debe conservar respaldo manual.';
	end if;

	if p_tipo_distribucion = 'MIXTA' and p_reparto_resto is null then
		raise exception 'La distribución mixta debe indicar cómo repartir el saldo restante.';
	elsif p_tipo_distribucion <> 'MIXTA' and p_reparto_resto is not null then
		raise exception 'Solo la distribución mixta puede definir reparto del saldo restante.';
	end if;

	if p_participantes is null or jsonb_typeof(p_participantes) <> 'array' or jsonb_array_length(p_participantes) = 0 then
		raise exception 'Debes seleccionar al menos un integrante.';
	end if;

	select count(*), count(distinct elemento ->> 'miembro_id')
	into v_total, v_distintos
	from jsonb_array_elements(p_participantes) as elemento;

	if v_total <> v_distintos then
		raise exception 'Un integrante no puede aparecer más de una vez.';
	end if;

	if exists (
		select 1
		from jsonb_array_elements(p_participantes) as elemento
		left join public.miembros_familia m
			on m.id = (elemento ->> 'miembro_id')::uuid
		where m.id is null
			or m.familia_id <> p_familia_id
			or m.estado <> 'ACTIVO'
	) then
		raise exception 'Todos los participantes deben ser integrantes activos de la familia.';
	end if;

	if p_tipo_distribucion = 'IGUAL' then
		if exists (
			select 1
			from jsonb_array_elements(p_participantes) as elemento
			where elemento ->> 'modalidad' <> 'IGUAL'
		) then
			raise exception 'La división igualitaria requiere modalidad IGUAL para todos.';
		end if;

	elsif p_tipo_distribucion = 'PORCENTAJE' then
		if exists (
			select 1
			from jsonb_array_elements(p_participantes) as elemento
			where elemento ->> 'modalidad' <> 'PORCENTAJE'
				or coalesce((elemento ->> 'valor')::numeric, 0) <= 0
				or (elemento ->> 'valor')::numeric > 100
		) then
			raise exception 'Cada porcentaje debe ser mayor a cero y menor o igual a 100.';
		end if;

		select coalesce(sum((elemento ->> 'valor')::numeric), 0)
		into v_suma
		from jsonb_array_elements(p_participantes) as elemento;

		if round(v_suma, 4) <> 100 then
			raise exception 'Los porcentajes deben sumar exactamente 100%%.';
		end if;

	elsif p_tipo_distribucion = 'MONTO_FIJO' then
		if p_metodo_obtencion <> 'FIJO' then
			raise exception 'La distribución por montos fijos requiere que el servicio tenga un monto fijo conocido.';
		end if;

		if exists (
			select 1
			from jsonb_array_elements(p_participantes) as elemento
			where elemento ->> 'modalidad' <> 'MONTO_FIJO'
				or coalesce((elemento ->> 'valor')::numeric, 0) <= 0
				or round((elemento ->> 'valor')::numeric, 2) <> (elemento ->> 'valor')::numeric
		) then
			raise exception 'Cada monto asignado debe ser mayor a cero y tener máximo dos decimales.';
		end if;

		select coalesce(sum((elemento ->> 'valor')::numeric), 0)
		into v_suma
		from jsonb_array_elements(p_participantes) as elemento;

		if round(v_suma, 2) <> round(p_monto_fijo, 2) then
			raise exception 'La suma de montos asignados debe coincidir con el monto fijo del servicio.';
		end if;

	else
		if not exists (
			select 1
			from jsonb_array_elements(p_participantes) as elemento
			where elemento ->> 'modalidad' = 'MONTO_FIJO'
		) then
			raise exception 'La distribución mixta necesita al menos un monto fijo.';
		end if;

		if p_reparto_resto = 'IGUAL' then
			if not exists (
				select 1
				from jsonb_array_elements(p_participantes) as elemento
				where elemento ->> 'modalidad' = 'RESTO_IGUAL'
			) then
				raise exception 'La distribución mixta necesita al menos un integrante para el saldo restante.';
			end if;

			if exists (
				select 1
				from jsonb_array_elements(p_participantes) as elemento
				where elemento ->> 'modalidad' not in ('MONTO_FIJO', 'RESTO_IGUAL')
					or (
						elemento ->> 'modalidad' = 'MONTO_FIJO'
						and (
							coalesce((elemento ->> 'valor')::numeric, 0) <= 0
							or round((elemento ->> 'valor')::numeric, 2) <> (elemento ->> 'valor')::numeric
						)
					)
			) then
				raise exception 'La distribución mixta contiene una configuración inválida.';
			end if;
		else
			if not exists (
				select 1
				from jsonb_array_elements(p_participantes) as elemento
				where elemento ->> 'modalidad' = 'RESTO_PORCENTAJE'
			) then
				raise exception 'La distribución mixta necesita participantes para el saldo restante.';
			end if;

			if exists (
				select 1
				from jsonb_array_elements(p_participantes) as elemento
				where elemento ->> 'modalidad' not in ('MONTO_FIJO', 'RESTO_PORCENTAJE')
					or (
						elemento ->> 'modalidad' = 'MONTO_FIJO'
						and (
							coalesce((elemento ->> 'valor')::numeric, 0) <= 0
							or round((elemento ->> 'valor')::numeric, 2) <> (elemento ->> 'valor')::numeric
						)
					)
					or (
						elemento ->> 'modalidad' = 'RESTO_PORCENTAJE'
						and (
							coalesce((elemento ->> 'valor')::numeric, 0) <= 0
							or (elemento ->> 'valor')::numeric > 100
						)
					)
			) then
				raise exception 'La distribución mixta contiene una configuración inválida.';
			end if;

			select coalesce(sum((elemento ->> 'valor')::numeric), 0)
			into v_suma
			from jsonb_array_elements(p_participantes) as elemento
			where elemento ->> 'modalidad' = 'RESTO_PORCENTAJE';

			if round(v_suma, 4) <> 100 then
				raise exception 'Los porcentajes del saldo restante deben sumar exactamente 100%%.';
			end if;
		end if;

		select coalesce(sum((elemento ->> 'valor')::numeric), 0)
		into v_fijos
		from jsonb_array_elements(p_participantes) as elemento
		where elemento ->> 'modalidad' = 'MONTO_FIJO';

		if p_metodo_obtencion = 'FIJO' and round(v_fijos, 2) >= round(p_monto_fijo, 2) then
			raise exception 'En una distribución mixta debe quedar un saldo positivo para repartir.';
		end if;
	end if;

	v_cuenta_valor := nullif(trim(coalesce(p_cuenta ->> 'identificador_valor', '')), '');
	v_cuenta_nombre := nullif(trim(coalesce(p_cuenta ->> 'identificador_nombre', '')), '');

	if nullif(coalesce(p_cuenta ->> 'tipo_identificador_id', ''), '') is not null then
		v_tipo_identificador_id := (p_cuenta ->> 'tipo_identificador_id')::uuid;

		if not exists (
			select 1
			from public.tipos_identificador_proveedor
			where id = v_tipo_identificador_id
				and proveedor_id = p_proveedor_id
				and activo = true
		) then
			raise exception 'El tipo de identificador no corresponde al proveedor seleccionado.';
		end if;
	end if;

	if p_metodo_obtencion = 'AUTOMATICO' and v_cuenta_valor is null then
		raise exception 'Los servicios automáticos necesitan una cuenta o identificador del proveedor.';
	end if;

	if v_cuenta_valor is not null and v_tipo_identificador_id is null and v_cuenta_nombre is null then
		raise exception 'Indica qué representa el identificador de la cuenta.';
	end if;

	if p_concepto_id is null then
		insert into public.conceptos_pago (
			familia_id,
			categoria_id,
			proveedor_id,
			plantilla_id,
			nombre,
			frecuencia,
			metodo_obtencion,
			monto_fijo,
			tipo_vencimiento,
			dia_vencimiento,
			tipo_distribucion,
			reparto_resto,
			fallback_manual
		)
		values (
			p_familia_id,
			p_categoria_id,
			p_proveedor_id,
			p_plantilla_id,
			trim(p_nombre),
			p_frecuencia,
			p_metodo_obtencion,
			p_monto_fijo,
			p_tipo_vencimiento,
			p_dia_vencimiento,
			p_tipo_distribucion,
			p_reparto_resto,
			p_fallback_manual
		)
		returning id into v_concepto_id;
	else
		if not exists (
			select 1
			from public.conceptos_pago
			where id = p_concepto_id
				and familia_id = p_familia_id
		) then
			raise exception 'Servicio no encontrado.';
		end if;

		v_concepto_id := p_concepto_id;

		update public.conceptos_pago
		set categoria_id = p_categoria_id,
			proveedor_id = p_proveedor_id,
			plantilla_id = p_plantilla_id,
			nombre = trim(p_nombre),
			frecuencia = p_frecuencia,
			metodo_obtencion = p_metodo_obtencion,
			monto_fijo = p_monto_fijo,
			tipo_vencimiento = p_tipo_vencimiento,
			dia_vencimiento = p_dia_vencimiento,
			tipo_distribucion = p_tipo_distribucion,
			reparto_resto = p_reparto_resto,
			fallback_manual = p_fallback_manual,
			updated_at = now()
		where id = v_concepto_id;

		delete from public.cuentas_servicio
		where concepto_id = v_concepto_id;

		delete from public.concepto_participantes
		where concepto_id = v_concepto_id;
	end if;

	if v_cuenta_valor is not null then
		insert into public.cuentas_servicio (
			concepto_id,
			tipo_identificador_id,
			identificador_nombre,
			identificador_valor,
			alias
		)
		values (
			v_concepto_id,
			v_tipo_identificador_id,
			case when v_tipo_identificador_id is null then v_cuenta_nombre else null end,
			v_cuenta_valor,
			nullif(trim(coalesce(p_cuenta ->> 'alias', '')), '')
		);
	end if;

	insert into public.concepto_participantes (
		concepto_id,
		miembro_id,
		modalidad,
		valor,
		orden
	)
	select
		v_concepto_id,
		(elemento ->> 'miembro_id')::uuid,
		(elemento ->> 'modalidad')::public.modalidad_participante_concepto,
		case
			when nullif(coalesce(elemento ->> 'valor', ''), '') is null then null
			else (elemento ->> 'valor')::numeric
		end,
		ordinalidad::smallint
	from jsonb_array_elements(p_participantes) with ordinality as datos(elemento, ordinalidad);

	return v_concepto_id;
exception
	when unique_violation then
		raise exception 'Ya existe un servicio con ese nombre dentro de la familia.';
end;
$$;

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
) from public;

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

insert into public.proveedores (codigo, nombre, tipo_servicio, es_sistema, estado_integracion)
values
	('SEDAPAL', 'SEDAPAL', 'AGUA', true, 'NO_DISPONIBLE'),
	('LUZ_DEL_SUR', 'Luz del Sur', 'LUZ', true, 'NO_DISPONIBLE'),
	('PLUZ', 'Pluz', 'LUZ', true, 'NO_DISPONIBLE'),
	('CALIDDA', 'Cálidda', 'GAS', true, 'NO_DISPONIBLE'),
	('WIN', 'WIN', 'INTERNET', true, 'NO_DISPONIBLE'),
	('CLARO', 'Claro', 'INTERNET', true, 'NO_DISPONIBLE'),
	('MOVISTAR', 'Movistar', 'INTERNET', true, 'NO_DISPONIBLE');

insert into public.tipos_identificador_proveedor (proveedor_id, codigo, nombre, ayuda, orden)
select id, 'NUMERO_SUMINISTRO', 'Número de suministro', 'Código que identifica el suministro de agua.', 1
from public.proveedores where codigo = 'SEDAPAL';

insert into public.tipos_identificador_proveedor (proveedor_id, codigo, nombre, ayuda, orden)
select id, 'NUMERO_SUMINISTRO', 'Número de suministro', 'Código del suministro eléctrico.', 1
from public.proveedores where codigo = 'LUZ_DEL_SUR';

insert into public.tipos_identificador_proveedor (proveedor_id, codigo, nombre, ayuda, orden)
select id, 'NUMERO_CLIENTE', 'Número de cliente', 'Pluz también denomina este dato número de suministro.', 1
from public.proveedores where codigo = 'PLUZ';

insert into public.tipos_identificador_proveedor (proveedor_id, codigo, nombre, ayuda, orden)
select id, 'NUMERO_CLIENTE', 'Número de cliente', 'Código que identifica al cliente para consultas y pagos.', 1
from public.proveedores where codigo = 'CALIDDA';

insert into public.tipos_identificador_proveedor (proveedor_id, codigo, nombre, ayuda, orden)
select id, 'CODIGO_PAGO', 'Código de pago', 'Código mostrado en el recibo WIN para realizar pagos.', 1
from public.proveedores where codigo = 'WIN';

insert into public.plantillas_servicio (
	codigo,
	nombre,
	tipo_servicio,
	icono,
	descripcion,
	frecuencia_recomendada,
	metodo_obtencion_recomendado,
	tipo_vencimiento_recomendado,
	orden
)
values
	('AGUA', 'Agua', 'AGUA', 'droplets', 'Recibo de agua del hogar.', 'MENSUAL', 'AUTOMATICO', 'PROVEEDOR', 1),
	('LUZ', 'Luz', 'LUZ', 'zap', 'Recibo de energía eléctrica del hogar.', 'MENSUAL', 'AUTOMATICO', 'PROVEEDOR', 2),
	('INTERNET', 'Internet', 'INTERNET', 'wifi', 'Servicio de internet del hogar.', 'MENSUAL', 'AUTOMATICO', 'PROVEEDOR', 3),
	('GAS', 'Gas', 'GAS', 'flame', 'Servicio de gas natural del hogar.', 'MENSUAL', 'AUTOMATICO', 'PROVEEDOR', 4);
