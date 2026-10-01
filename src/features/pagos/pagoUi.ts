import type { Enums } from '../../types/database'
import { supabase } from '../../lib/supabase'

export type MetodoPago = Enums<'metodo_pago_familiar'>
export type EstadoPago = Enums<'estado_pago_familiar'>

export const metodoPagoLabel: Record<MetodoPago, string> = {
	YAPE: 'Yape',
	TRANSFERENCIA: 'Transferencia',
	EFECTIVO: 'Efectivo',
	OTRO: 'Otro',
}

export const estadoPagoLabel: Record<EstadoPago, string> = {
	BORRADOR: 'Borrador',
	POR_VALIDAR: 'Pago enviado',
	CONFIRMADO: 'Confirmado',
	RECHAZADO: 'Rechazado',
	ANULADO: 'Anulado',
}

export function estadoPagoClass(value: EstadoPago) {
	if (value === 'CONFIRMADO') return 'bg-emerald-50 text-emerald-700'
	if (value === 'POR_VALIDAR') return 'bg-amber-50 text-amber-700'
	if (value === 'RECHAZADO') return 'bg-rose-50 text-rose-600'
	if (value === 'ANULADO') return 'bg-slate-100 text-slate-400'
	return 'bg-sky-50 text-sky-700'
}

export async function signedFileUrl(bucket: string | null, path: string | null, expiresIn = 120) {
	if (!bucket || !path) return null
	const { data, error } = await supabase.storage.from(bucket).createSignedUrl(path, expiresIn)
	if (error) throw error
	return data.signedUrl
}

export function fileExtension(file: File) {
	const byName = file.name.split('.').pop()?.toLowerCase()
	if (byName) return byName
	if (file.type === 'application/pdf') return 'pdf'
	if (file.type === 'image/png') return 'png'
	if (file.type === 'image/webp') return 'webp'
	return 'jpg'
}
