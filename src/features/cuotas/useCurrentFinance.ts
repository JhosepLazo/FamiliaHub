import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '../../lib/supabase'
import type { Tables } from '../../types/database'
import { useAuth } from '../auth/AuthContext'
import { useFamilia } from '../familia/FamiliaContext'
import { todayLima } from '../recibos/reciboUi'

export type Periodo = Tables<'periodos'>
export type Recibo = Tables<'recibos'>
export type Cuota = Tables<'cuotas'>
export type Aporte = Tables<'aportes'>

export type CuotaConRecibo = {
	cuota: Cuota
	recibo: Recibo
	fechaObjetivo: string | null
	diasRestantes: number | null
	vencida: boolean
}

export type AdminAttention = {
	recibosEsperandoMonto: number
	vencimientosFaltantes: number
	aportesPorValidar: number
	recibosVencidos: number
	recaudacionesAtrasadas: number
	total: number
}

export function useCurrentFinance() {
	const { user } = useAuth()
	const { familia, membresia } = useFamilia()
	const isAdmin = membresia?.rol === 'ADMINISTRADOR'

	const [periodo, setPeriodo] = useState<Periodo | null>(null)
	const [recibos, setRecibos] = useState<Recibo[]>([])
	const [cuotas, setCuotas] = useState<Cuota[]>([])
	const [aportesPorValidar, setAportesPorValidar] = useState<Aporte[]>([])
	const [loading, setLoading] = useState(true)
	const [error, setError] = useState<string | null>(null)

	const load = useCallback(async () => {
		if (!familia || !user) return

		setLoading(true)
		setError(null)

		const today = todayLima()
		const [year, month] = today.split('-').map(Number)

		const { data: periodRow, error: periodError } = await supabase
			.from('periodos')
			.select('*')
			.eq('familia_id', familia.id)
			.eq('anio', year)
			.eq('mes', month)
			.maybeSingle()

		if (periodError) {
			setError(periodError.message)
			setLoading(false)
			return
		}

		if (!periodRow) {
			setPeriodo(null)
			setRecibos([])
			setCuotas([])
			setAportesPorValidar([])
			setLoading(false)
			return
		}

		setPeriodo(periodRow)

		const { data: receiptRows, error: receiptsError } = await supabase
			.from('recibos')
			.select('*')
			.eq('periodo_id', periodRow.id)
			.order('fecha_limite_aporte', { ascending: true, nullsFirst: false })
			.order('created_at')

		if (receiptsError) {
			setError(receiptsError.message)
			setLoading(false)
			return
		}

		const receiptList = receiptRows ?? []
		setRecibos(receiptList)
		const receiptIds = receiptList.map((receipt) => receipt.id)

		if (receiptIds.length) {
			const { data: quotaRows, error: quotaError } = await supabase
				.from('cuotas')
				.select('*')
				.eq('familia_id', familia.id)
				.eq('usuario_id', user.id)
				.in('recibo_id', receiptIds)
				.order('created_at')

			if (quotaError) setError(quotaError.message)
			setCuotas(quotaRows ?? [])
		} else {
			setCuotas([])
		}

		if (isAdmin) {
			const { data: pendingRows, error: pendingError } = await supabase
				.from('aportes')
				.select('*')
				.eq('familia_id', familia.id)
				.eq('estado', 'POR_VALIDAR')
				.order('created_at')

			if (pendingError) setError(pendingError.message)
			setAportesPorValidar(pendingRows ?? [])
		} else {
			setAportesPorValidar([])
		}

		setLoading(false)
	}, [familia, user, isAdmin])

	useEffect(() => { void load() }, [load])

	const reciboMap = useMemo(() => new Map(recibos.map((receipt) => [receipt.id, receipt])), [recibos])

	const cuotasConRecibo = useMemo<CuotaConRecibo[]>(() => {
		const today = todayLima()
		return cuotas
			.map((quota) => {
				const receipt = reciboMap.get(quota.recibo_id)
				if (!receipt) return null
				const targetDate = receipt.fecha_limite_aporte ?? receipt.fecha_vencimiento
				const days = targetDate ? daysBetween(today, targetDate) : null
				return {
					cuota: quota,
					recibo: receipt,
					fechaObjetivo: targetDate,
					diasRestantes: days,
					vencida: days != null && days < 0 && (quota.saldo_pendiente ?? 0) > 0,
				}
			})
			.filter((row): row is CuotaConRecibo => Boolean(row))
			.sort(compareQuotaPriority)
	}, [cuotas, reciboMap])

	const resumen = useMemo(() => {
		const activas = cuotasConRecibo.filter(({ cuota }) => cuota.estado !== 'ANULADA')
		const pendientes = activas.filter(({ cuota }) => (cuota.saldo_pendiente ?? 0) > 0)
		const pagadas = activas.filter(({ cuota }) => cuota.estado === 'PAGADA')
		const porValidar = activas.filter(({ cuota }) => cuota.estado === 'POR_VALIDAR')
		return {
			debe: roundMoney(pendientes.reduce((sum, { cuota }) => sum + (cuota.saldo_pendiente ?? 0), 0)),
			pagado: roundMoney(activas.reduce((sum, { cuota }) => sum + cuota.monto_pagado, 0)),
			pendientes: pendientes.length,
			pagadas: pagadas.length,
			porValidar: porValidar.length,
			proxima: pendientes[0] ?? null,
		}
	}, [cuotasConRecibo])

	const adminAttention = useMemo<AdminAttention>(() => {
		if (!isAdmin) return emptyAttention()

		const today = todayLima()
		const activeReceipts = recibos.filter((receipt) => receipt.estado !== 'ANULADO')
		const receiptsWaitingAmount = activeReceipts.filter((receipt) => receipt.estado === 'ESPERANDO_MONTO').length
		const missingDueDates = activeReceipts.filter((receipt) =>
			receipt.monto_total != null
			&& receipt.tipo_vencimiento !== 'DIA_FIJO'
			&& !receipt.fecha_vencimiento
			&& receipt.estado !== 'PAGADO',
		).length
		const overdueReceipts = activeReceipts.filter((receipt) => receipt.estado === 'VENCIDO').length
		const lateCollections = activeReceipts.filter((receipt) =>
			receipt.estado_recaudacion !== 'COMPLETA'
			&& receipt.fecha_limite_aporte != null
			&& receipt.fecha_limite_aporte < today,
		).length
		const pendingContributions = aportesPorValidar.length

		return {
			recibosEsperandoMonto: receiptsWaitingAmount,
			vencimientosFaltantes: missingDueDates,
			aportesPorValidar: pendingContributions,
			recibosVencidos: overdueReceipts,
			recaudacionesAtrasadas: lateCollections,
			total: receiptsWaitingAmount + missingDueDates + pendingContributions + overdueReceipts + lateCollections,
		}
	}, [isAdmin, recibos, aportesPorValidar])

	return {
		periodo,
		recibos,
		cuotas,
		cuotasConRecibo,
		resumen,
		adminAttention,
		loading,
		error,
		reload: load,
	}
}

function compareQuotaPriority(a: CuotaConRecibo, b: CuotaConRecibo) {
	const aPending = (a.cuota.saldo_pendiente ?? 0) > 0
	const bPending = (b.cuota.saldo_pendiente ?? 0) > 0
	if (aPending !== bPending) return aPending ? -1 : 1
	if (a.vencida !== b.vencida) return a.vencida ? -1 : 1
	if (a.fechaObjetivo && b.fechaObjetivo) return a.fechaObjetivo.localeCompare(b.fechaObjetivo)
	if (a.fechaObjetivo) return -1
	if (b.fechaObjetivo) return 1
	return a.recibo.nombre_concepto.localeCompare(b.recibo.nombre_concepto)
}

function daysBetween(from: string, to: string) {
	const fromDate = new Date(`${from}T00:00:00Z`)
	const toDate = new Date(`${to}T00:00:00Z`)
	return Math.round((toDate.getTime() - fromDate.getTime()) / 86_400_000)
}

function roundMoney(value: number) {
	return Math.round((value + Number.EPSILON) * 100) / 100
}

function emptyAttention(): AdminAttention {
	return {
		recibosEsperandoMonto: 0,
		vencimientosFaltantes: 0,
		aportesPorValidar: 0,
		recibosVencidos: 0,
		recaudacionesAtrasadas: 0,
		total: 0,
	}
}
