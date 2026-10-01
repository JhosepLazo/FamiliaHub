create or replace function app_private.bloquear_periodo_financiero_cerrado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_abierto boolean;
	v_periodo_id uuid;
	v_recibo_id uuid;
begin
	if tg_table_name = 'recibos' then
		v_periodo_id := case when tg_op = 'DELETE' then old.periodo_id else new.periodo_id end;

		select estado = 'ABIERTO'
		into v_abierto
		from public.periodos
		where id = v_periodo_id;
	else
		v_recibo_id := case when tg_op = 'DELETE' then old.recibo_id else new.recibo_id end;
		v_abierto := app_private.periodo_recibo_abierto(v_recibo_id);
	end if;

	if coalesce(v_abierto, false) = false then
		raise exception 'El periodo está cerrado y sus movimientos financieros son inmutables.';
	end if;

	return case when tg_op = 'DELETE' then old else new end;
end;
$$;
