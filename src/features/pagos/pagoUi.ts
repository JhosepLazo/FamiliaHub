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
	if (value === 'CONFIRMADO') return 'bg-emerald-50 text-emerald-700 ring-1 ring-inset ring-emerald-200/70'
	if (value === 'POR_VALIDAR') return 'bg-amber-50 text-amber-700 ring-1 ring-inset ring-amber-200/70'
	if (value === 'RECHAZADO') return 'bg-rose-50 text-rose-600 ring-1 ring-inset ring-rose-200/70'
	if (value === 'ANULADO') return 'bg-slate-100 text-slate-400 ring-1 ring-inset ring-slate-200'
	return 'bg-sky-50 text-sky-700 ring-1 ring-inset ring-sky-200/70'
}

export async function signedFileUrl(bucket: string | null, path: string | null, expiresIn = 120) {
	if (!bucket || !path) return null
	const { data, error } = await supabase.storage.from(bucket).createSignedUrl(path, expiresIn)
	if (error) throw error
	return data.signedUrl
}

export function fileExtension(file: File) {
	if (file.type === 'application/pdf') return 'pdf'
	if (file.type === 'image/png') return 'png'
	if (file.type === 'image/webp') return 'webp'
	if (file.type === 'image/jpeg') return 'jpg'
	const byName = file.name.includes('.') ? file.name.split('.').pop()?.toLowerCase() : undefined
	return byName || 'jpg'
}

// Los mismos límites que tienen los buckets en Supabase. Revisarlos antes de subir evita esperar la subida y
// recibir un error técnico en inglés (por ejemplo, con una foto HEIC del iPhone o una muy pesada).
export function problemaArchivo(file: File, maxMb: number, conPdf = false) {
	const tipos = ['image/png', 'image/jpeg', 'image/webp', ...(conPdf ? ['application/pdf'] : [])]
	if (!tipos.includes(file.type)) return conPdf ? 'Sube una imagen PNG, JPG o WEBP, o un PDF. Si es una foto del iPhone, envía una captura de pantalla.' : 'Sube una imagen PNG, JPG o WEBP. Si es una foto del iPhone, envía una captura de pantalla.'
	if (file.size > maxMb * 1024 * 1024) return `El archivo pesa más de ${maxMb} MB. Sube una captura de pantalla, que pesa menos.`
	return null
}
