create index idx_aportes_anulado_por on public.aportes(anulado_por) where anulado_por is not null;
create index idx_aportes_familia on public.aportes(familia_id);
create index idx_cuotas_usuario on public.cuotas(usuario_id);
create index idx_eventos_financieros_usuario on public.eventos_financieros(usuario_id) where usuario_id is not null;
create index idx_pagos_proveedor_anulado_por on public.pagos_proveedor(anulado_por) where anulado_por is not null;
create index idx_recibo_ajustes_anulado_por on public.recibo_ajustes(anulado_por) where anulado_por is not null;
