import { Check, ExternalLink, ReceiptText, ShieldCheck, X } from 'lucide-react'
import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '../../lib/supabase'
import type { Tables } from '../../types/database'
import { useAuth } from '../auth/AuthContext'
import { useFamilia } from '../familia/FamiliaContext'
import { dateLabel, money } from '../recibos/reciboUi'
import { estadoPagoClass, estadoPagoLabel, metodoPagoLabel, signedFileUrl } from './pagoUi'

type Pago = Tables<'pagos_familiares'>
type Asignacion = Tables<'pago_asignaciones'>
type Recibo = Tables<'recibos'>

type Tab = 'MIOS' | 'VALIDAR' | 'HISTORIAL'

export default function PagosPage() {
	const { user } = useAuth()
	const { familia, membresia } = useFamilia()
	const isAdmin = membresia?.rol === 'ADMINISTRADOR'
	const [payments, setPayments] = useState<Pago[]>([])
	const [assignments, setAssignments] = useState<Asignacion[]>([])
	const [receipts, setReceipts] = useState<Recibo[]>([])
	const [tab, setTab] = useState<Tab>('MIOS')
	const [loading, setLoading] = useState(true)
	const [working, setWorking] = useState(false)
	const [message, setMessage] = useState<string | null>(null)

	const load = useCallback(async () => {
		if (!familia || !user) return
		setLoading(true)
		const { data: paymentRows, error } = await supabase
			.from('pagos_familiares')
			.select('*')
			.eq('familia_id', familia.id)
			.order('created_at', { ascending: false })

		if (error) {
			setMessage(error.message)
			setLoading(false)
			return
		}

		const rows = paymentRows ?? []
		setPayments(rows)
		const ids = rows.map((row) => row.id)
		if (!ids.length) {
			setAssignments([])
			setReceipts([])
			setLoading(false)
			return
		}

		const { data: assignmentRows } = await supabase.from('pago_asignaciones').select('*').in('pago_id', ids)
		setAssignments(assignmentRows ?? [])
		const receiptIds = [...new Set((assignmentRows ?? []).map((row) => row.recibo_id))]
		const { data: receiptRows } = receiptIds.length ? await supabase.from('recibos').select('*').in('id', receiptIds) : { data: [] as Recibo[] }
		setReceipts(receiptRows ?? [])
		setLoading(false)
	}, [familia, user])

	useEffect(() => { void load() }, [load])

	const receiptMap = useMemo(() => new Map(receipts.map((row) => [row.id, row])), [receipts])
	const assignmentMap = useMemo(() => {
		const map = new Map<string, Asignacion[]>()
		for (const row of assignments) {
			const list = map.get(row.pago_id) ?? []
			list.push(row)
			map.set(row.pago_id, list)
		}
		return map
	}, [assignments])

	const visible = useMemo(() => {
		if (tab === 'MIOS') return payments.filter((payment) => payment.pagador_usuario_id === user?.id)
		if (tab === 'VALIDAR') return payments.filter((payment) =>
			payment.estado === 'POR_VALIDAR'
			&& (isAdmin || payment.responsable_receptor_miembro_id === membresia?.id),
		)
		return payments
	}, [payments, tab, user, isAdmin, membresia])

	const validate = async (payment: Pago, approved: boolean) => {
		const reason = approved ? undefined : window.prompt('Motivo del rechazo:')
		if (!approved && !reason) return
		setWorking(true)
		const { error } = await supabase.rpc('validar_pago_familiar', {
			p_pago_id: payment.id,
			p_aprobar: approved,
			p_motivo: reason,
		})
		setMessage(error ? error.message : approved ? 'Pago confirmado.' : 'Pago rechazado.')
		if (!error) await load()
		setWorking(false)
	}

	const annul = async (payment: Pago) => {
		const reason = window.prompt('Motivo de la anulación:')
		if (!reason) return
		setWorking(true)
		const { error } = await supabase.rpc('anular_pago_familiar', {
			p_pago_id: payment.id,
			p_motivo: reason,
		})
		setMessage(error ? error.message : 'Pago anulado.')
		if (!error) await load()
		setWorking(false)
	}

	const openProof = async (payment: Pago) => {
		try {
			const url = await signedFileUrl(payment.comprobante_bucket, payment.comprobante_storage_path)
			if (url) window.open(url, '_blank', 'noopener,noreferrer')
		} catch {
			setMessage('No pudimos abrir el comprobante.')
		}
	}

	return (
		<div>
			<div>
				<p className="text-sm font-semibold text-[#0f766e]">Pagos</p>
				<h1 className="mt-1 text-3xl font-semibold tracking-tight">Pagos y validaciones</h1>
				<p className="mt-2 max-w-2xl text-sm leading-6 text-slate-500">Un pago enviado no modifica una cuota hasta que el receptor responsable lo confirme.</p>
			</div>

			<div className="mt-7 flex rounded-2xl border border-slate-200 bg-white p-1">
				<TabButton active={tab === 'MIOS'} onClick={() => setTab('MIOS')}>Mis pagos</TabButton>
				<TabButton active={tab === 'VALIDAR'} onClick={() => setTab('VALIDAR')}>Por validar</TabButton>
				<TabButton active={tab === 'HISTORIAL'} onClick={() => setTab('HISTORIAL')}>Historial</TabButton>
			</div>

			{loading ? (
				<div className="mt-6 h-72 animate-pulse rounded-3xl bg-white" />
			) : visible.length === 0 ? (
				<div className="mt-6 rounded-3xl border border-dashed border-slate-300 bg-white p-8 text-center"><ReceiptText className="mx-auto text-slate-400" /><h2 className="mt-3 font-semibold">{tab === 'VALIDAR' ? 'No tienes pagos por validar' : 'Todavía no hay pagos aquí'}</h2></div>
			) : (
				<div className="mt-6 space-y-4">
					{visible.map((payment) => {
						const rows = assignmentMap.get(payment.id) ?? []
						const names = [...new Set(rows.map((row) => receiptMap.get(row.recibo_id)?.nombre_concepto).filter(Boolean))]
						const canValidate = payment.estado === 'POR_VALIDAR' && (isAdmin || payment.responsable_receptor_miembro_id === membresia?.id)
						const canAnnul = payment.estado !== 'ANULADO' && (
							(payment.estado === 'CONFIRMADO' && (isAdmin || payment.responsable_receptor_miembro_id === membresia?.id))
							|| (payment.estado !== 'CONFIRMADO' && (payment.pagador_usuario_id === user?.id || isAdmin || payment.responsable_receptor_miembro_id === membresia?.id))
						)
						return (
							<article key={payment.id} className="rounded-3xl border border-slate-200 bg-white p-5 sm:p-6">
								<div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
									<div><div className="flex flex-wrap items-center gap-2"><h2 className="font-semibold">{payment.receptor_nombre_snapshot}</h2><span className={`rounded-full px-2.5 py-1 text-[10px] font-semibold ${estadoPagoClass(payment.estado)}`}>{estadoPagoLabel[payment.estado]}</span></div><p className="mt-1 text-xs text-slate-400">{metodoPagoLabel[payment.metodo]} · {names.join(', ') || 'Cuotas familiares'}</p></div>
									<p className="text-xl font-semibold">{money(payment.monto_total)}</p>
								</div>

								<div className="mt-5 grid gap-3 sm:grid-cols-3">
									<Info label="Pagador" value={payment.pagador_nombre_snapshot} />
									<Info label="Fecha" value={dateLabel(payment.fecha_pago)} />
									<Info label="Asignaciones" value={String(rows.length)} />
								</div>

								{payment.rechazo_motivo && <p className="mt-4 rounded-xl bg-rose-50 p-3 text-xs text-rose-600">Rechazado: {payment.rechazo_motivo}</p>}
								{payment.anulacion_motivo && <p className="mt-4 rounded-xl bg-slate-50 p-3 text-xs text-slate-500">Anulado: {payment.anulacion_motivo}</p>}

								<div className="mt-5 flex flex-wrap gap-2">
									{payment.comprobante_storage_path && <button type="button" onClick={() => void openProof(payment)} className="fh-button-secondary flex items-center gap-2"><ExternalLink size={14} />Comprobante</button>}
									{canValidate && <button disabled={working} onClick={() => void validate(payment, true)} className="fh-button-primary flex items-center gap-2"><Check size={14} />Confirmar</button>}
									{canValidate && <button disabled={working} onClick={() => void validate(payment, false)} className="fh-button-secondary flex items-center gap-2"><X size={14} />Rechazar</button>}
									{canAnnul && <button disabled={working} onClick={() => void annul(payment)} className="text-xs font-semibold text-rose-500">Anular</button>}
								</div>
							</article>
						)
					})}
				</div>
			)}

			{message && <p className="fh-alert mt-5">{message}</p>}
		</div>
	)
}

function TabButton({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
	return <button type="button" onClick={onClick} className={`flex-1 rounded-xl px-4 py-2 text-xs font-semibold transition ${active ? 'bg-[#0f766e] text-white' : 'text-slate-500'}`}>{children}</button>
}

function Info({ label, value }: { label: string; value: string }) {
	return <div className="rounded-2xl bg-slate-50 p-3"><p className="text-[10px] font-semibold uppercase tracking-wide text-slate-400">{label}</p><p className="mt-1 truncate text-xs font-semibold text-slate-700">{value}</p></div>
}
