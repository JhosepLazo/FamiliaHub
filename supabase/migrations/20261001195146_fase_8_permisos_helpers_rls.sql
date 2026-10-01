grant execute on function app_private.puede_ver_pago_familiar(uuid, uuid) to authenticated;
grant execute on function app_private.puede_gestionar_cobro_miembro(uuid, uuid, uuid) to authenticated;
grant execute on function app_private.puede_ver_cobro_miembro(uuid, uuid, uuid) to authenticated;
grant execute on function app_private.puede_subir_comprobante_pago(uuid, uuid) to authenticated;
grant execute on function app_private.puede_ver_pago_proveedor(uuid, uuid) to authenticated;
grant execute on function app_private.puede_gestionar_pago_proveedor(uuid, uuid) to authenticated;
