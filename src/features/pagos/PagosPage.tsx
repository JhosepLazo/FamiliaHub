import { Check, ExternalLink, ReceiptText, ShieldCheck, X } from 'lucide-react'
import { useCallback, useEffect, useMemo, useState } from 'react'
import EmptyState from '../../components/ui/EmptyState'
import { useDialogo } from '../../components/ui/Dialogo'
import MensajeFlotante from '../../components/ui/MensajeFlotante'
import { useEnVivo } from '../../lib/enVivo'
import { supabase } from '../../lib/supabase'
import type { Tables } from '../../types/database'
import { useAuth } from '../auth/AuthContext'
import { useFamilia } from '../familia/FamiliaContext'
import { dateLabel, money } from '../recibos/reciboUi'
import { estadoPagoClass, estadoPagoLabel, metodoPagoLabel, signedFileUrl } from './pagoUi'

type Pago = Tables<'pagos_familiares'>
type Asignacion = Tables<'pago_asignaciones'>
type Recibo = Tables<'recibos'>

export type VistaPagos = 'MIOS' | 'VALIDAR' | 'HISTORIAL'

// Lista de pagos familiares; el módulo Pagos decide qué vista mostrar con sus pestañas.
export default function PagosPage({ vista: tab }: { vista: VistaPagos }) {
	const { user } = useAuth()
	const { familia, membresia } = useFamilia()
	const { pedirTexto } = useDialogo()
	const isAdmin = membresia?.rol === 'ADMINISTRADOR'
	const [payments, setPayments] = useState<Pago[]>([])
	const [assignments, setAssignments] = useState<Asignacion[]>([])
	const [receipts, setReceipts] = useState<Recibo[]>([])
	const [loading, setLoading] = useState(true)
	const [working, setWorking] = useState(false)
	const [message, setMessage] = useState<string | null>(null)

	const load = useCallback(async (silencioso = false) => {
		if (!familia || !user) return
		if (!silencioso) setLoading(true)
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
	useEnVivo(() => void load(true))

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
		const reason = approved ? undefined : await pedirTexto({
			titulo: `¿Rechazar el pago de ${payment.pagador_nombre_snapshot}?`,
			mensaje: 'Sus cuotas vuelven a quedar pendientes. Verá el motivo en sus pagos para saber qué corregir.',
			etiqueta: 'Motivo del rechazo',
			placeholder: 'Por ejemplo: no veo el Yape en mi cuenta.',
			accion: 'Rechazar pago',
			peligro: true,
		})
		if (!approved && !reason) return
		setWorking(true)
		const { error } = await supabase.rpc('validar_pago_familiar', {
			p_pago_id: payment.id,
			p_aprobar: approved,
			...(reason ? { p_motivo: reason } : {}),
		})
		setMessage(error ? error.message : approved ? 'Pago confirmado.' : 'Pago rechazado.')
		if (!error) await load()
		setWorking(false)
	}

	const annul = async (payment: Pago) => {
		const reason = await pedirTexto({
			titulo: '¿Anular este pago?',
			mensaje: `${payment.pagador_nombre_snapshot} → ${payment.receptor_nombre_snapshot}. Las cuotas vuelven a quedar pendientes y el pago se conserva en el historial.`,
			etiqueta: 'Motivo',
			placeholder: 'Por ejemplo: el Yape no llegó.',
			accion: 'Anular pago',
			peligro: true,
		})
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
		<div className="fh-entrada">
			{tab === 'VALIDAR' && <p className="mb-4 text-sm text-slate-500">Un pago enviado no cambia la cuota hasta que su receptor responsable lo confirma.</p>}

			{loading ? (
				<div className="h-72 animate-pulse rounded-3xl bg-white/60" />
			) : visible.length === 0 ? (
				<EmptyState
					icon={tab === 'VALIDAR' ? <ShieldCheck size={20} /> : <ReceiptText size={20} />}
					title={tab === 'VALIDAR' ? 'No tienes pagos por validar' : tab === 'MIOS' ? 'Todavía no registraste pagos' : 'Todavía no hay pagos en la familia'}
					description={tab === 'VALIDAR' ? 'Cuando alguien te envíe un pago, aparecerá aquí para que lo confirmes.' : 'Los pagos aparecen aquí apenas se registran desde "Por pagar".'}
				/>
			) : (
				<div className="space-y-4">
					{visible.map((payment) => {
						const rows = assignmentMap.get(payment.id) ?? []
						const names = [...new Set(rows.map((row) => receiptMap.get(row.recibo_id)?.nombre_concepto).filter(Boolean))]
						const canValidate = payment.estado === 'POR_VALIDAR' && (isAdmin || payment.responsable_receptor_miembro_id === membresia?.id)
						const canAnnul = payment.estado !== 'ANULADO' && (
							(payment.estado === 'CONFIRMADO' && (isAdmin || payment.responsable_receptor_miembro_id === membresia?.id))
							|| (payment.estado !== 'CONFIRMADO' && (payment.pagador_usuario_id === user?.id || isAdmin || payment.responsable_receptor_miembro_id === membresia?.id))
						)
						return (
							<article key={payment.id} className={`fh-card p-5 sm:p-6 ${canValidate ? 'ring-2 ring-amber-200/70' : ''}`}>
								<div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
									<div className="min-w-0">
										<div className="flex flex-wrap items-center gap-2"><h2 className="font-bold text-slate-900">Para {payment.receptor_nombre_snapshot}</h2><span className={`fh-pill ${estadoPagoClass(payment.estado)}`}>{estadoPagoLabel[payment.estado]}</span></div>
										<p className="mt-1 text-xs text-slate-400">{metodoPagoLabel[payment.metodo]} · {names.join(', ') || 'Cuotas familiares'}</p>
									</div>
									<p className="text-2xl font-extrabold tracking-tight tabular-nums text-slate-900">{money(payment.monto_total)}</p>
								</div>

								<div className="mt-5 grid gap-3 sm:grid-cols-3">
									<Info label="Pagador" value={payment.pagador_nombre_snapshot} />
									<Info label="Fecha" value={dateLabel(payment.fecha_pago)} />
									<Info label="Asignaciones" value={String(rows.length)} />
								</div>

								{payment.rechazo_motivo && <p className="mt-4 rounded-xl bg-rose-50 p-3 text-xs text-rose-600">Rechazado: {payment.rechazo_motivo}</p>}
								{payment.anulacion_motivo && <p className="mt-4 rounded-xl bg-slate-50 p-3 text-xs text-slate-500">Anulado: {payment.anulacion_motivo}</p>}

								<div className="mt-5 flex flex-wrap items-center gap-2">
									{canValidate && <button disabled={working} onClick={() => void validate(payment, true)} className="fh-button-primary">{working ? <span className="fh-spinner" /> : <Check size={15} />}Confirmar pago</button>}
									{canValidate && <button disabled={working} onClick={() => void validate(payment, false)} className="fh-button-danger"><X size={15} />Rechazar</button>}
									{payment.comprobante_storage_path && <button type="button" onClick={() => void openProof(payment)} className="fh-button-secondary"><ExternalLink size={14} />Ver comprobante</button>}
									{canAnnul && <button disabled={working} onClick={() => void annul(payment)} className="ml-auto rounded-lg px-2 py-1 text-xs font-bold text-rose-500 transition hover:bg-rose-50 active:scale-95">Anular</button>}
								</div>
							</article>
						)
					})}
				</div>
			)}

			<MensajeFlotante mensaje={message} alCerrar={() => setMessage(null)} />
		</div>
	)
}

function Info({ label, value }: { label: string; value: string }) {
	return <div className="rounded-2xl bg-slate-50/80 p-3"><p className="text-[10px] font-bold uppercase tracking-wide text-slate-400">{label}</p><p className="mt-1 truncate text-xs font-bold text-slate-700">{value}</p></div>
}
