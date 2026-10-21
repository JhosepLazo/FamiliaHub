import type { Enums } from '../../types/database'

export function money(value: number | null | undefined) {
	if (value == null) return 'Pendiente'
	return new Intl.NumberFormat('es-PE', { style: 'currency', currency: 'PEN' }).format(value)
}

export function dateLabel(value: string | null | undefined) {
	if (!value) return 'Por definir'
	return new Intl.DateTimeFormat('es-PE', {
		day: '2-digit',
		month: 'short',
		year: 'numeric',
		timeZone: 'UTC',
	}).format(new Date(`${value}T00:00:00Z`))
}

export function periodLabel(year: number, month: number) {
	return new Intl.DateTimeFormat('es-PE', {
		month: 'long',
		year: 'numeric',
		timeZone: 'UTC',
	}).format(new Date(Date.UTC(year, month - 1, 1)))
}

export const reciboEstadoLabel: Record<Enums<'estado_recibo'>, string> = {
	ESPERANDO_MONTO: 'Esperando monto',
	PENDIENTE: 'Pendiente',
	PAGADO: 'Pagado',
	VENCIDO: 'Vencido',
	ANULADO: 'Anulado',
	REQUIERE_REVISION: 'Requiere revisión',
}

export const recaudacionLabel: Record<Enums<'estado_recaudacion'>, string> = {
	PENDIENTE: 'Pendiente',
	PARCIAL: 'Parcial',
	COMPLETA: 'Completa',
}

export const cuotaEstadoLabel: Record<Enums<'estado_cuota'>, string> = {
	PENDIENTE: 'Pendiente',
	PARCIAL: 'Parcial',
	POR_VALIDAR: 'Por validar',
	PAGADA: 'Pagada',
	RECHAZADA: 'Rechazada',
	ANULADA: 'Anulada',
}

export function receiptBadgeClass(value: Enums<'estado_recibo'>) {
	if (value === 'PAGADO') return 'bg-emerald-50 text-emerald-700 ring-1 ring-inset ring-emerald-200/70'
	if (value === 'VENCIDO') return 'bg-rose-50 text-rose-600 ring-1 ring-inset ring-rose-200/70'
	if (value === 'ESPERANDO_MONTO' || value === 'REQUIERE_REVISION') return 'bg-amber-50 text-amber-700 ring-1 ring-inset ring-amber-200/70'
	if (value === 'ANULADO') return 'bg-slate-100 text-slate-400 ring-1 ring-inset ring-slate-200'
	return 'bg-sky-50 text-sky-700 ring-1 ring-inset ring-sky-200/70'
}

export function quotaBadgeClass(value: Enums<'estado_cuota'>) {
	if (value === 'PAGADA') return 'bg-emerald-50 text-emerald-700 ring-1 ring-inset ring-emerald-200/70'
	if (value === 'POR_VALIDAR') return 'bg-amber-50 text-amber-700 ring-1 ring-inset ring-amber-200/70'
	if (value === 'PARCIAL') return 'bg-sky-50 text-sky-700 ring-1 ring-inset ring-sky-200/70'
	if (value === 'RECHAZADA') return 'bg-rose-50 text-rose-600 ring-1 ring-inset ring-rose-200/70'
	return 'bg-slate-100 text-slate-500 ring-1 ring-inset ring-slate-200'
}

export function todayLima() {
	return new Intl.DateTimeFormat('en-CA', {
		timeZone: 'America/Lima',
		year: 'numeric',
		month: '2-digit',
		day: '2-digit',
	}).format(new Date())
}
