import {
	ArrowLeft,
	Banknote,
	Check,
	CircleAlert,
	CircleCheck,
	CreditCard,
	HandCoins,
	ReceiptText,
	RotateCcw,
	ShieldCheck,
	X,
} from 'lucide-react'
import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import type { Enums, Tables } from '../../types/database'
import { useAuth } from '../auth/AuthContext'
import { useFamilia } from '../familia/FamiliaContext'
import {
	cuotaEstadoLabel,
	dateLabel,
	money,
	quotaBadgeClass,
	recaudacionLabel,
	receiptBadgeClass,
	reciboEstadoLabel,
	todayLima,
} from './reciboUi'

type Recibo = Tables<'recibos'>
type Cuota = Tables<'cuotas'>
type Aporte = Tables<'aportes'>
type PagoProveedor = Tables<'pagos_proveedor'>
type Ajuste = Tables<'recibo_ajustes'>
type MetodoPago = Enums<'metodo_pago_familiar'>
type OrigenPagoProveedor = Enums<'origen_pago_proveedor'>

type MemberView = {
	id: string
	nombre: string
}

export default function ReciboDetallePage() {
	const { id = '' } = useParams()
	const { user } = useAuth()
	const { familia, membresia } = useFamilia()
	const isAdmin = membresia?.rol === 'ADMINISTRADOR'

	const [receipt, setReceipt] = useState<Recibo | null>(null)
	const [quotas, setQuotas] = useState<Cuota[]>([])
	const [contributions, setContributions] = useState<Aporte[]>([])
	const [providerPayments, setProviderPayments] = useState<PagoProveedor[]>([])
	const [adjustments, setAdjustments] = useState<Ajuste[]>([])
	const [members, setMembers] = useState<MemberView[]>([])
	const [loading, setLoading] = useState(true)
	const [working, setWorking] = useState(false)
	const [message, setMessage] = useState<string | null>(null)

	const [amount, setAmount] = useState('')
	const [dueDate, setDueDate] = useState('')
	const [correctionAmount, setCorrectionAmount] = useState('')
	const [correctionReason, setCorrectionReason] = useState('')

	const [quotaId, setQuotaId] = useState('')
	const [contributionAmount, setContributionAmount] = useState('')
	const [contributionMethod, setContributionMethod] = useState<MetodoPago>('YAPE')
	const [contributionReference, setContributionReference] = useState('')

	const [providerOrigin, setProviderOrigin] = useState<OrigenPagoProveedor>('FONDO_FAMILIAR')
	const [providerPayer, setProviderPayer] = useState('')
	const [providerDate, setProviderDate] = useState(todayLima())
	const [providerReference, setProviderReference] = useState('')

	const load = useCallback(async () => {
		if (!familia || !id) return
		setLoading(true)

		const { data: receiptRow, error } = await supabase
			.from('recibos')
			.select('*')
			.eq('id', id)
			.eq('familia_id', familia.id)
			.maybeSingle()

		if (error || !receiptRow) {
			setMessage('No pudimos encontrar este recibo.')
			setLoading(false)
			return
		}

		const [
			{ data: quotaRows },
			{ data: contributionRows },
			{ data: paymentRows },
			{ data: adjustmentRows },
			{ data: memberRows },
		] = await Promise.all([
			supabase.from('cuotas').select('*').eq('recibo_id', id).order('created_at'),
			supabase.from('aportes').select('*').eq('recibo_id', id).order('created_at', { ascending: false }),
			supabase.from('pagos_proveedor').select('*').eq('recibo_id', id).order('created_at', { ascending: false }),
			supabase.from('recibo_ajustes').select('*').eq('recibo_id', id).order('created_at', { ascending: false }),
			supabase.from('miembros_familia').select('id,usuario_id').eq('familia_id', familia.id).eq('estado', 'ACTIVO').order('joined_at'),
		])

		const userIds = (memberRows ?? []).map((row) => row.usuario_id)
		let profiles: { id: string; nombre: string | null }[] = []
		if (userIds.length) profiles = (await supabase.from('perfiles').select('id,nombre').in('id', userIds)).data ?? []
		const names = new Map(profiles.map((profile) => [profile.id, profile.nombre ?? 'Integrante']))

		setReceipt(receiptRow)
		setQuotas(quotaRows ?? [])
		setContributions(contributionRows ?? [])
		setProviderPayments(paymentRows ?? [])
		setAdjustments(adjustmentRows ?? [])
		setMembers((memberRows ?? []).map((row) => ({ id: row.id, nombre: names.get(row.usuario_id) ?? 'Integrante' })))
		setAmount(receiptRow.monto_total == null ? '' : String(receiptRow.monto_total))
		setDueDate(receiptRow.fecha_vencimiento ?? '')
		setCorrectionAmount(receiptRow.monto_total == null ? '' : String(receiptRow.monto_total))
		setLoading(false)
	}, [familia, id])

	useEffect(() => { void load() }, [load])

	const quotaMap = useMemo(() => new Map(quotas.map((quota) => [quota.id, quota])), [quotas])
	const memberMap = useMemo(() => new Map(members.map((member) => [member.id, member.nombre])), [members])
	const ownQuota = useMemo(() => quotas.find((quota) => quota.usuario_id === user?.id) ?? null, [quotas, user])
	const activeProviderPayment = useMemo(() => providerPayments.find((payment) => payment.estado === 'CONFIRMADO') ?? null, [providerPayments])
	const assigned = useMemo(() => quotas.reduce((sum, quota) => sum + quota.monto_asignado, 0), [quotas])
	const paid = useMemo(() => quotas.reduce((sum, quota) => sum + quota.monto_pagado, 0), [quotas])
	const progress = assigned > 0 ? Math.min(100, Math.round((paid / assigned) * 100)) : 0

	const run = async (operation: () => Promise<{ error: { message: string } | null }>, success: string) => {
		setWorking(true)
		setMessage(null)
		const { error } = await operation()
		setMessage(error ? error.message : success)
		if (!error) await load()
		setWorking(false)
	}

	const confirmAmount = async (event: FormEvent) => {
		event.preventDefault()
		if (!receipt) return
		await run(
			() => supabase.rpc('confirmar_monto_recibo', {
				p_recibo_id: receipt.id,
				p_monto: Number(amount),
				p_fecha_vencimiento: receipt.tipo_vencimiento === 'DIA_FIJO' ? null : dueDate || null,
			}).then(({ error }) => ({ error })),
			'Monto confirmado y cuotas generadas.',
		)
	}

	const correctAmount = async (event: FormEvent) => {
		event.preventDefault()
		if (!receipt) return
		await run(
			() => supabase.rpc('corregir_monto_recibo', {
				p_recibo_id: receipt.id,
				p_nuevo_monto: Number(correctionAmount),
				p_motivo: correctionReason,
				p_fecha_vencimiento: dueDate || null,
			}).then(({ error }) => ({ error })),
			'Corrección registrada sin reescribir el historial.',
		)
		setCorrectionReason('')
	}

	const registerContribution = async (event: FormEvent) => {
		event.preventDefault()
		if (!quotaId) return
		await run(
			() => supabase.rpc('registrar_aporte', {
				p_cuota_id: quotaId,
				p_monto: Number(contributionAmount),
				p_metodo: contributionMethod,
				p_referencia: contributionReference || null,
				p_nota: null,
			}).then(({ error }) => ({ error })),
			isAdmin ? 'Aporte registrado y confirmado.' : 'Aporte enviado para validación.',
		)
		setContributionAmount('')
		setContributionReference('')
		setQuotaId('')
	}

	const validateContribution = async (contribution: Aporte, approved: boolean) => {
		const reason = approved ? null : window.prompt('Motivo del rechazo:')
		if (!approved && !reason) return
		await run(
			() => supabase.rpc('validar_aporte', {
				p_aporte_id: contribution.id,
				p_aprobar: approved,
				p_motivo: reason,
			}).then(({ error }) => ({ error })),
			approved ? 'Aporte confirmado.' : 'Aporte rechazado.',
		)
	}

	const annulContribution = async (contribution: Aporte) => {
		const reason = window.prompt('Motivo de la anulación:')
		if (!reason) return
		await run(
			() => supabase.rpc('anular_aporte', { p_aporte_id: contribution.id, p_motivo: reason }).then(({ error }) => ({ error })),
			'Aporte anulado.',
		)
	}

	const registerProviderPayment = async (event: FormEvent) => {
		event.preventDefault()
		if (!receipt?.monto_total) return
		await run(
			() => supabase.rpc('registrar_pago_proveedor', {
				p_recibo_id: receipt.id,
				p_origen: providerOrigin,
				p_pagador_miembro_id: providerOrigin === 'ADELANTO_INTEGRANTE' ? providerPayer || null : null,
				p_monto: receipt.monto_total,
				p_fecha_pago: providerDate,
				p_referencia: providerReference || null,
				p_nota: null,
			}).then(({ error }) => ({ error })),
			'Pago al proveedor registrado.',
		)
	}

	const annulProviderPayment = async (payment: PagoProveedor) => {
		const reason = window.prompt('Motivo de la anulación del pago al proveedor:')
		if (!reason) return
		await run(
			() => supabase.rpc('anular_pago_proveedor', { p_pago_id: payment.id, p_motivo: reason }).then(({ error }) => ({ error })),
			'Pago al proveedor anulado.',
		)
	}

	if (loading) return <div className="h-96 animate-pulse rounded-3xl bg-white" />
	if (!receipt) return <div className="fh-alert">Recibo no disponible.</div>

	return (
		<div>
			<div className="flex items-start gap-4">
				<Link to="/recibos" className="mt-1 grid size-10 shrink-0 place-items-center rounded-xl border border-slate-200 bg-white text-slate-500"><ArrowLeft size={17} /></Link>
				<div className="min-w-0 flex-1">
					<div className="flex flex-wrap items-center gap-2">
						<h1 className="text-3xl font-semibold tracking-tight">{receipt.nombre_concepto}</h1>
						<span className={`rounded-full px-2.5 py-1 text-[10px] font-semibold ${receiptBadgeClass(receipt.estado)}`}>{reciboEstadoLabel[receipt.estado]}</span>
					</div>
					<p className="mt-2 text-sm text-slate-500">{receipt.proveedor_nombre} · {receipt.categoria_nombre}</p>
				</div>
			</div>

			<div className="mt-7 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
				<Metric label="Total recibo" value={money(receipt.monto_total)} />
				<Metric label="Tu cuota" value={ownQuota ? money(ownQuota.monto_asignado) : 'No participas'} accent />
				<Metric label="Vence proveedor" value={dateLabel(receipt.fecha_vencimiento)} />
				<Metric label="Aporte familiar" value={dateLabel(receipt.fecha_limite_aporte)} />
			</div>

			{receipt.monto_total != null && (
				<section className="mt-5 rounded-3xl border border-slate-200 bg-white p-5">
					<div className="flex items-center justify-between gap-4">
						<div><p className="text-sm font-semibold">Recaudación familiar</p><p className="mt-1 text-xs text-slate-400">{recaudacionLabel[receipt.estado_recaudacion]} · {money(paid)} de {money(assigned)}</p></div>
						<p className="text-sm font-semibold text-[#0f766e]">{progress}%</p>
					</div>
					<div className="mt-3 h-2 overflow-hidden rounded-full bg-slate-100"><div className="h-full rounded-full bg-[#0f766e]" style={{ width: `${progress}%` }} /></div>
				</section>
			)}

			{receipt.estado === 'ESPERANDO_MONTO' && isAdmin && (
				<section className="mt-6 rounded-3xl border border-amber-100 bg-amber-50 p-5 sm:p-6">
					<div className="flex items-center gap-3 text-amber-800"><CircleAlert size={20} /><div><h2 className="font-semibold">Falta confirmar el recibo</h2><p className="mt-1 text-xs">Al confirmar el monto, FamiliaHub congelará esta instancia y generará sus cuotas.</p></div></div>
					<form onSubmit={confirmAmount} className="mt-5 grid gap-4 sm:grid-cols-3">
						<label><span className="fh-label">Monto total</span><input className="fh-input" type="number" min="0.01" step="0.01" required value={amount} onChange={(e) => setAmount(e.target.value)} /></label>
						{receipt.tipo_vencimiento !== 'DIA_FIJO' && <label><span className="fh-label">Vencimiento proveedor</span><input className="fh-input" type="date" required value={dueDate} onChange={(e) => setDueDate(e.target.value)} /></label>}
						<div className="flex items-end"><button disabled={working} className="fh-button-primary w-full">Confirmar recibo</button></div>
					</form>
				</section>
			)}

			{quotas.length > 0 && (
				<section className="mt-6 rounded-3xl border border-slate-200 bg-white p-5 sm:p-6">
					<div className="flex items-center gap-3"><HandCoins size={19} className="text-[#0f766e]" /><div><h2 className="font-semibold">Distribución familiar</h2><p className="text-xs text-slate-400">Cada cuota conserva su propio saldo y estado.</p></div></div>
					<div className="mt-5 space-y-3">
						{quotas.map((quota) => (
							<div key={quota.id} className="rounded-2xl border border-slate-100 p-4">
								<div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
									<div><div className="flex flex-wrap items-center gap-2"><p className="text-sm font-semibold">{quota.nombre_miembro}{quota.usuario_id === user?.id ? ' · Tú' : ''}</p><span className={`rounded-full px-2 py-1 text-[10px] font-semibold ${quotaBadgeClass(quota.estado)}`}>{cuotaEstadoLabel[quota.estado]}</span></div><p className="mt-1 text-xs text-slate-400">{quota.destino === 'INTEGRANTE' ? `Reembolso a ${memberMap.get(quota.receptor_miembro_id ?? '') ?? 'integrante'}` : 'Aporte al fondo familiar'}</p></div>
									<div className="flex items-center gap-5 text-right"><div><p className="text-[10px] uppercase text-slate-400">Cuota</p><p className="text-sm font-semibold">{money(quota.monto_asignado)}</p></div><div><p className="text-[10px] uppercase text-slate-400">Falta</p><p className="text-sm font-semibold text-[#0f766e]">{money(quota.saldo_pendiente)}</p></div>{quota.saldo_pendiente > 0 && (isAdmin || quota.usuario_id === user?.id) && <button onClick={() => { setQuotaId(quota.id); setContributionAmount(String(quota.saldo_pendiente)) }} className="fh-button-secondary">Aportar</button>}</div>
								</div>
							</div>
						))}
					</div>
				</section>
			)}

			{quotaId && (
				<section className="mt-5 rounded-3xl border border-emerald-100 bg-emerald-50/50 p-5">
					<div className="flex items-center justify-between"><div><h2 className="font-semibold">Registrar aporte</h2><p className="mt-1 text-xs text-slate-500">Puedes pagar parcialmente; FamiliaHub conservará el saldo restante.</p></div><button onClick={() => setQuotaId('')} className="text-slate-400"><X size={18} /></button></div>
					<form onSubmit={registerContribution} className="mt-5 grid gap-4 sm:grid-cols-4">
						<label><span className="fh-label">Monto</span><input className="fh-input" type="number" min="0.01" step="0.01" required value={contributionAmount} onChange={(e) => setContributionAmount(e.target.value)} /></label>
						<label><span className="fh-label">Método</span><select className="fh-input" value={contributionMethod} onChange={(e) => setContributionMethod(e.target.value as MetodoPago)}><option value="YAPE">Yape</option><option value="TRANSFERENCIA">Transferencia</option><option value="EFECTIVO">Efectivo</option><option value="OTRO">Otro</option></select></label>
						<label><span className="fh-label">Referencia</span><input className="fh-input" value={contributionReference} onChange={(e) => setContributionReference(e.target.value)} placeholder="Opcional" /></label>
						<div className="flex items-end"><button disabled={working} className="fh-button-primary w-full">Registrar</button></div>
					</form>
				</section>
			)}

			{contributions.length > 0 && (
				<section className="mt-6 rounded-3xl border border-slate-200 bg-white p-5 sm:p-6">
					<div className="flex items-center gap-3"><CreditCard size={19} className="text-[#0f766e]" /><div><h2 className="font-semibold">Aportes y reembolsos</h2><p className="text-xs text-slate-400">Los integrantes solo ven movimientos en los que participan; el administrador ve todos.</p></div></div>
					<div className="mt-5 space-y-3">
						{contributions.map((contribution) => {
							const quota = quotaMap.get(contribution.cuota_id)
							const canValidate = isAdmin || contribution.receptor_miembro_id === membresia?.id
							return (
								<div key={contribution.id} className="flex flex-col gap-3 rounded-2xl border border-slate-100 p-4 sm:flex-row sm:items-center sm:justify-between">
									<div><p className="text-sm font-semibold">{quota?.nombre_miembro ?? 'Integrante'} · {money(contribution.monto)}</p><p className="mt-1 text-xs text-slate-400">{contribution.tipo === 'REEMBOLSO' ? 'Reembolso' : contribution.tipo === 'COBERTURA_ADELANTO' ? 'Cubierto por adelanto' : 'Aporte familiar'} · {contribution.estado.replaceAll('_', ' ')}</p></div>
									<div className="flex flex-wrap gap-2">
										{contribution.estado === 'POR_VALIDAR' && canValidate && <><button onClick={() => void validateContribution(contribution, true)} className="fh-button-secondary flex items-center gap-2"><Check size={14} />Aprobar</button><button onClick={() => void validateContribution(contribution, false)} className="fh-button-secondary flex items-center gap-2"><X size={14} />Rechazar</button></>}
										{contribution.tipo !== 'COBERTURA_ADELANTO' && contribution.estado !== 'ANULADO' && (isAdmin || (contribution.estado === 'POR_VALIDAR' && contribution.creado_por === user?.id)) && <button onClick={() => void annulContribution(contribution)} className="text-xs font-semibold text-rose-500">Anular</button>}
									</div>
								</div>
							)
						})}
					</div>
				</section>
			)}

			{receipt.monto_total != null && (
				<section className="mt-6 rounded-3xl border border-slate-200 bg-white p-5 sm:p-6">
					<div className="flex items-center gap-3"><Banknote size={19} className="text-[#0f766e]" /><div><h2 className="font-semibold">Pago al proveedor</h2><p className="text-xs text-slate-400">Este estado es independiente de la recaudación familiar.</p></div></div>

					{activeProviderPayment ? (
						<div className="mt-5 rounded-2xl border border-emerald-100 bg-emerald-50 p-4">
							<div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div className="flex items-start gap-3"><CircleCheck className="mt-0.5 text-emerald-600" size={19} /><div><p className="text-sm font-semibold text-emerald-800">Proveedor pagado · {money(activeProviderPayment.monto)}</p><p className="mt-1 text-xs text-emerald-700/70">{activeProviderPayment.origen === 'ADELANTO_INTEGRANTE' ? `Adelantó ${activeProviderPayment.pagador_nombre_snapshot ?? 'un integrante'}` : 'Pagado desde fondo familiar'} · {dateLabel(activeProviderPayment.fecha_pago)}</p></div></div>{isAdmin && <button onClick={() => void annulProviderPayment(activeProviderPayment)} className="fh-button-secondary flex items-center gap-2"><RotateCcw size={14} />Anular pago</button>}</div>
						</div>
					) : isAdmin ? (
						<form onSubmit={registerProviderPayment} className="mt-5 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
							<label><span className="fh-label">Origen</span><select className="fh-input" value={providerOrigin} onChange={(e) => setProviderOrigin(e.target.value as OrigenPagoProveedor)}><option value="FONDO_FAMILIAR">Fondo familiar</option><option value="ADELANTO_INTEGRANTE">Adelanto de integrante</option></select></label>
							{providerOrigin === 'ADELANTO_INTEGRANTE' && <label><span className="fh-label">Quién adelanta</span><select className="fh-input" required value={providerPayer} onChange={(e) => setProviderPayer(e.target.value)}><option value="">Selecciona</option>{members.map((member) => <option key={member.id} value={member.id}>{member.nombre}</option>)}</select></label>}
							<label><span className="fh-label">Fecha</span><input className="fh-input" type="date" required value={providerDate} onChange={(e) => setProviderDate(e.target.value)} /></label>
							<label><span className="fh-label">Referencia</span><input className="fh-input" value={providerReference} onChange={(e) => setProviderReference(e.target.value)} placeholder="Opcional" /></label>
							<div className="sm:col-span-2 lg:col-span-4"><button disabled={working} className="fh-button-primary">Registrar pago de {money(receipt.monto_total)}</button></div>
						</form>
					) : (
						<div className="mt-5 rounded-2xl bg-amber-50 p-4 text-sm text-amber-700">El pago al proveedor aún está pendiente.</div>
					)}
				</section>
			)}

			{isAdmin && receipt.monto_total != null && !activeProviderPayment && receipt.estado !== 'ANULADO' && (
				<section className="mt-6 rounded-3xl border border-slate-200 bg-white p-5 sm:p-6">
					<div className="flex items-center gap-3"><ShieldCheck size={19} className="text-slate-500" /><div><h2 className="font-semibold">Corrección controlada</h2><p className="text-xs text-slate-400">No reescribe el monto original: crea un ajuste auditable y recalcula solo si ningún pago queda por encima de su nueva cuota.</p></div></div>
					<form onSubmit={correctAmount} className="mt-5 grid gap-4 sm:grid-cols-3">
						<label><span className="fh-label">Nuevo total</span><input className="fh-input" type="number" min="0.01" step="0.01" required value={correctionAmount} onChange={(e) => setCorrectionAmount(e.target.value)} /></label>
						<label><span className="fh-label">Motivo</span><input className="fh-input" required value={correctionReason} onChange={(e) => setCorrectionReason(e.target.value)} /></label>
						<div className="flex items-end"><button disabled={working} className="fh-button-secondary w-full">Aplicar ajuste</button></div>
					</form>
					{adjustments.length > 0 && <div className="mt-4 space-y-2">{adjustments.map((adjustment) => <div key={adjustment.id} className="rounded-xl bg-slate-50 px-4 py-3 text-xs text-slate-500">{money(adjustment.monto_anterior)} → {money(adjustment.monto_nuevo)} · {adjustment.motivo}</div>)}</div>}
				</section>
			)}

			{message && <p className="fh-alert mt-5">{message}</p>}
		</div>
	)
}

function Metric({ label, value, accent = false }: { label: string; value: string; accent?: boolean }) {
	return <div className={`rounded-2xl border p-5 ${accent ? 'border-emerald-100 bg-emerald-50/60' : 'border-slate-200 bg-white'}`}><p className={`text-[10px] font-semibold uppercase tracking-wide ${accent ? 'text-emerald-700/60' : 'text-slate-400'}`}>{label}</p><p className={`mt-2 text-lg font-semibold ${accent ? 'text-[#0f766e]' : 'text-slate-800'}`}>{value}</p></div>
}
