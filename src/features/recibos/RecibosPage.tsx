import { CalendarDays, CheckCircle2, ChevronRight, RefreshCw, ReceiptText } from 'lucide-react'
import { useCallback, useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import type { Tables } from '../../types/database'
import { useAuth } from '../auth/AuthContext'
import { useFamilia } from '../familia/FamiliaContext'
import { dateLabel, money, periodLabel, recaudacionLabel, receiptBadgeClass, reciboEstadoLabel } from './reciboUi'

type Periodo = Tables<'periodos'>
type Recibo = Tables<'recibos'>
type Cuota = Tables<'cuotas'>

export default function RecibosPage() {
	const { user } = useAuth()
	const { familia, membresia } = useFamilia()
	const isAdmin = membresia?.rol === 'ADMINISTRADOR'
	const [periodos, setPeriodos] = useState<Periodo[]>([])
	const [periodoId, setPeriodoId] = useState('')
	const [recibos, setRecibos] = useState<Recibo[]>([])
	const [cuotas, setCuotas] = useState<Cuota[]>([])
	const [loading, setLoading] = useState(true)
	const [message, setMessage] = useState<string | null>(null)
	const [syncing, setSyncing] = useState(false)

	const loadPeriods = useCallback(async (sync = false) => {
		if (!familia) return
		setLoading(true)
		setMessage(null)

		if (sync && isAdmin) {
			setSyncing(true)
			const { error } = await supabase.rpc('sincronizar_periodo_actual', { p_familia_id: familia.id })
			if (error) setMessage(error.message)
			setSyncing(false)
		}

		const { data, error } = await supabase
			.from('periodos')
			.select('*')
			.eq('familia_id', familia.id)
			.order('anio', { ascending: false })
			.order('mes', { ascending: false })

		if (error) {
			setMessage(error.message)
			setLoading(false)
			return
		}

		const rows = data ?? []
		setPeriodos(rows)
		setPeriodoId((current) => current && rows.some((row) => row.id === current) ? current : rows[0]?.id ?? '')
		setLoading(false)
	}, [familia, isAdmin])

	const loadReceipts = useCallback(async () => {
		if (!periodoId) {
			setRecibos([])
			setCuotas([])
			return
		}

		setLoading(true)
		const { data: receiptRows, error } = await supabase
			.from('recibos')
			.select('*')
			.eq('periodo_id', periodoId)
			.order('created_at')

		if (error) {
			setMessage(error.message)
			setLoading(false)
			return
		}

		const receiptList = receiptRows ?? []
		setRecibos(receiptList)
		const ids = receiptList.map((row) => row.id)

		if (!ids.length) {
			setCuotas([])
			setLoading(false)
			return
		}

		const { data: quotaRows } = await supabase.from('cuotas').select('*').in('recibo_id', ids).order('created_at')
		setCuotas(quotaRows ?? [])
		setLoading(false)
	}, [periodoId])

	useEffect(() => { void loadPeriods(true) }, [loadPeriods])
	useEffect(() => { void loadReceipts() }, [loadReceipts])

	const currentPeriod = useMemo(() => periodos.find((period) => period.id === periodoId) ?? null, [periodos, periodoId])
	const quotaByReceipt = useMemo(() => {
		const map = new Map<string, Cuota[]>()
		for (const quota of cuotas) {
			const rows = map.get(quota.recibo_id) ?? []
			rows.push(quota)
			map.set(quota.recibo_id, rows)
		}
		return map
	}, [cuotas])

	const closePeriod = async () => {
		if (!currentPeriod) return
		setMessage(null)
		const { error } = await supabase.rpc('cerrar_periodo', { p_periodo_id: currentPeriod.id })
		setMessage(error ? error.message : 'Periodo cerrado correctamente.')
		if (!error) await loadPeriods(false)
	}

	return (
		<div>
			<div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
				<div>
					<p className="text-sm font-semibold text-[#0f766e]">Hogar</p>
					<h1 className="mt-1 text-3xl font-semibold tracking-tight">Recibos</h1>
					<p className="mt-2 max-w-2xl text-sm leading-6 text-slate-500">Cada recibo conserva su total, vencimiento, distribución familiar y estado del proveedor de forma independiente.</p>
				</div>
				{isAdmin && (
					<button onClick={() => void loadPeriods(true)} disabled={syncing} className="fh-button-secondary flex items-center gap-2">
						<RefreshCw size={16} className={syncing ? 'animate-spin' : ''} />Sincronizar
					</button>
				)}
			</div>

			<div className="mt-7 flex flex-col gap-3 rounded-2xl border border-slate-200 bg-white p-4 sm:flex-row sm:items-center sm:justify-between">
				<div className="flex items-center gap-3">
					<div className="grid size-10 place-items-center rounded-xl bg-emerald-50 text-[#0f766e]"><CalendarDays size={18} /></div>
					<div><p className="text-xs font-medium text-slate-400">Periodo</p><p className="text-sm font-semibold">{currentPeriod ? periodLabel(currentPeriod.anio, currentPeriod.mes) : 'Sin periodo'}</p></div>
				</div>
				<div className="flex flex-col gap-2 sm:flex-row">
					<select className="fh-select min-w-48" value={periodoId} onChange={(e) => setPeriodoId(e.target.value)}>
						{periodos.map((period) => <option key={period.id} value={period.id}>{periodLabel(period.anio, period.mes)} · {period.estado === 'COMPLETADO' ? 'Cerrado' : 'Abierto'}</option>)}
					</select>
					{isAdmin && currentPeriod?.estado === 'ABIERTO' && <button onClick={() => void closePeriod()} className="fh-button-secondary flex items-center gap-2"><CheckCircle2 size={16} />Cerrar periodo</button>}
				</div>
			</div>

			{loading ? (
				<div className="mt-6 grid gap-4 lg:grid-cols-2"><div className="h-56 animate-pulse rounded-3xl bg-white" /><div className="h-56 animate-pulse rounded-3xl bg-white" /></div>
			) : recibos.length === 0 ? (
				<section className="mt-6 rounded-3xl border border-dashed border-slate-300 bg-white p-8 text-center">
					<div className="mx-auto grid size-12 place-items-center rounded-2xl bg-slate-50 text-slate-400"><ReceiptText /></div>
					<h2 className="mt-4 text-lg font-semibold">No hay recibos en este periodo</h2>
					<p className="mx-auto mt-2 max-w-lg text-sm leading-6 text-slate-500">{isAdmin ? 'Configura servicios activos o sincroniza el periodo. FamiliaHub solo crea una instancia por servicio y periodo.' : 'Cuando el administrador configure servicios para este periodo aparecerán aquí.'}</p>
				</section>
			) : (
				<div className="mt-6 grid gap-4 lg:grid-cols-2">
					{recibos.map((receipt) => {
						const receiptQuotas = quotaByReceipt.get(receipt.id) ?? []
						const assigned = receiptQuotas.reduce((sum, quota) => sum + quota.monto_asignado, 0)
						const paid = receiptQuotas.reduce((sum, quota) => sum + quota.monto_pagado, 0)
						const own = receiptQuotas.find((quota) => quota.usuario_id === user?.id)
						const progress = assigned > 0 ? Math.min(100, Math.round((paid / assigned) * 100)) : 0
						return (
							<Link key={receipt.id} to={`/recibos/${receipt.id}`} className="group rounded-3xl border border-slate-200 bg-white p-5 transition hover:border-slate-300 sm:p-6">
								<div className="flex items-start justify-between gap-4">
									<div className="min-w-0">
										<div className="flex flex-wrap items-center gap-2"><h2 className="truncate text-lg font-semibold">{receipt.nombre_concepto}</h2><span className={`rounded-full px-2.5 py-1 text-[10px] font-semibold ${receiptBadgeClass(receipt.estado)}`}>{reciboEstadoLabel[receipt.estado]}</span></div>
										<p className="mt-1 text-xs text-slate-400">{receipt.proveedor_nombre} · {receipt.categoria_nombre}</p>
									</div>
									<ChevronRight className="shrink-0 text-slate-300 transition group-hover:translate-x-1 group-hover:text-slate-500" size={18} />
								</div>

								<div className="mt-6 grid grid-cols-2 gap-3">
									<div className="rounded-2xl bg-slate-50 p-4"><p className="text-[10px] font-semibold uppercase tracking-wide text-slate-400">Total recibo</p><p className="mt-1 text-lg font-semibold">{money(receipt.monto_total)}</p></div>
									<div className="rounded-2xl bg-emerald-50/60 p-4"><p className="text-[10px] font-semibold uppercase tracking-wide text-emerald-700/60">Tu cuota</p><p className="mt-1 text-lg font-semibold text-[#0f766e]">{own ? money(own.monto_asignado) : 'No participas'}</p></div>
								</div>

								<div className="mt-5 grid grid-cols-2 gap-4 text-xs">
									<div><p className="text-slate-400">Vence proveedor</p><p className="mt-1 font-semibold text-slate-600">{dateLabel(receipt.fecha_vencimiento)}</p></div>
									<div><p className="text-slate-400">Aporte familiar</p><p className="mt-1 font-semibold text-slate-600">{dateLabel(receipt.fecha_limite_aporte)}</p></div>
								</div>

								{receipt.monto_total != null && (
									<div className="mt-5">
										<div className="flex items-center justify-between text-[11px]"><span className="font-medium text-slate-400">Recaudación · {recaudacionLabel[receipt.estado_recaudacion]}</span><span className="font-semibold text-slate-500">{money(paid)} / {money(assigned)}</span></div>
										<div className="mt-2 h-2 overflow-hidden rounded-full bg-slate-100"><div className="h-full rounded-full bg-[#0f766e]" style={{ width: `${progress}%` }} /></div>
									</div>
								)}
							</Link>
						)
					})}
				</div>
			)}

			{message && <p className="fh-alert mt-5">{message}</p>}
		</div>
	)
}
