import { Droplets, Flame, Shapes, Wifi, Zap, type LucideIcon } from 'lucide-react'
import type { Enums } from '../../types/database'

export type TipoServicio = Enums<'tipo_servicio'>
export type MetodoObtencion = Enums<'metodo_obtencion_monto'>
export type Frecuencia = Enums<'frecuencia_concepto'>
export type TipoVencimiento = Enums<'tipo_vencimiento_concepto'>
export type TipoDistribucion = Enums<'tipo_distribucion_concepto'>
export type RepartoResto = Enums<'tipo_reparto_resto'>
export type ModalidadParticipante = Enums<'modalidad_participante_concepto'>

export const tipoServicioLabel: Record<TipoServicio, string> = {
	AGUA: 'Agua',
	LUZ: 'Luz',
	INTERNET: 'Internet',
	GAS: 'Gas',
	OTRO: 'Otro',
}

export const metodoLabel: Record<MetodoObtencion, string> = {
	AUTOMATICO: 'Automático',
	FIJO: 'Fijo',
	MANUAL: 'Manual',
}

export const frecuenciaLabel: Record<Frecuencia, string> = {
	MENSUAL: 'Mensual',
	ANUAL: 'Anual',
	UNICA: 'Única',
}

export const vencimientoLabel: Record<TipoVencimiento, string> = {
	DIA_FIJO: 'Día fijo',
	VARIABLE: 'Variable',
	PROVEEDOR: 'Desde proveedor',
}

export const distribucionLabel: Record<TipoDistribucion, string> = {
	IGUAL: 'Igual',
	PORCENTAJE: 'Porcentaje',
	MONTO_FIJO: 'Monto fijo',
	MIXTA: 'Mixta',
}

const icons: Record<TipoServicio, LucideIcon> = {
	AGUA: Droplets,
	LUZ: Zap,
	INTERNET: Wifi,
	GAS: Flame,
	OTRO: Shapes,
}

export function ServicioIcon({ tipo, size = 20 }: { tipo: TipoServicio; size?: number }) {
	const Icon = icons[tipo]
	return <Icon size={size} />
}

export function integrationLabel(value: Enums<'estado_integracion_proveedor'>) {
	if (value === 'DISPONIBLE') return 'Integración disponible'
	if (value === 'PREPARADO') return 'Integración preparada'
	return 'Integración pendiente'
}

export function money(value: number | null) {
	if (value == null) return 'Variable'
	return new Intl.NumberFormat('es-PE', { style: 'currency', currency: 'PEN' }).format(value)
}
