import {
	ArrowLeft,
	Banknote,
	CircleAlert,
	CircleCheck,
	CreditCard,
	ExternalLink,
	HandCoins,
	ImageUp,
	RotateCcw,
	ShieldCheck,
} from 'lucide-react'
import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import type { Database, Enums, Json, Tables } from '../../types/database'
import { fileExtension, signedFileUrl } from '../pagos/pagoUi'
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

	const [providerOrigin, setProviderOrigin] = useState<OrigenPagoProveedor>('FONDO_FAMILIAR')
	const [providerPayer, setProviderPayer] = useState('')
	const [providerDate, setProviderDate] = useState(todayLima())
	const [providerReference, setProviderReference] = useState('')
	const [providerProof, setProviderProof] = useState<File | null>(null)
	const [providerProofUrl, setProviderProofUrl] = useState<string | null>(null)
	const [hasActiveFamilyPayments, setHasActiveFamilyPayments] = useState(false)
	const [pendingDueDate, setPendingDueDate] = useState('')
	const [distributionOpen, setDistributionOpen] = useState(false)
	const [distributionReason, setDistributionReason] = useState('')
	const [distributionDraft, setDistributionDraft] = useState<Record<string, { selected: boolean; amount: string }>>({})

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

		const { data: phase8Assignments } = await supabase.from('pago_asignaciones').select('pago_id').eq('recibo_id', id)
		const phase8PaymentIds = [...new Set((phase8Assignments ?? []).map((row) => row.pago_id))]
		if (phase8PaymentIds.length) {
			const { data: phase8Payments } = await supabase.from('pagos_familiares').select('id,estado').in('id', phase8PaymentIds).in('estado', ['BORRADOR','POR_VALIDAR','CONFIRMADO'])
			setHasActiveFamilyPayments((phase8Payments ?? []).length > 0)
		} else {
			setHasActiveFamilyPayments(false)
		}

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

	useEffect(() => {
		setProviderProofUrl(null)
		if (!activeProviderPayment?.comprobante_bucket || !activeProviderPayment.comprobante_storage_path) return
		void signedFileUrl(activeProviderPayment.comprobante_bucket, activeProviderPayment.comprobante_storage_path, 300)
			.then(setProviderProofUrl)
			.catch(() => setProviderProofUrl(null))
	}, [activeProviderPayment?.id, activeProviderPayment?.comprobante_storage_path])

	const assigned = useMemo(() => quotas.reduce((sum, quota) => sum + quota.monto_asignado, 0), [quotas])
	const paid = useMemo(() => quotas.reduce((sum, quota) => sum + quota.monto_pagado, 0), [quotas])
	const progress = assigned > 0 ? Math.min(100, Math.round((paid / assigned) * 100)) : 0
	const hasActiveContributions = contributions.some((item) => item.estado === 'POR_VALIDAR' || item.estado === 'CONFIRMADO')

	const run = async (operation: () => PromiseLike<{ error: { message: string } | null }>, success: string) => {
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
				p_fecha_vencimiento: receipt.tipo_vencimiento === 'DIA_FIJO'
					? receipt.fecha_vencimiento ?? todayLima()
					: dueDate,
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
				...(dueDate ? { p_fecha_vencimiento: dueDate } : {}),
			}).then(({ error }) => ({ error })),
			'Corrección registrada sin reescribir el historial.',
		)
		setCorrectionReason('')
	}

	const registerProviderPayment = async (event: FormEvent) => {
		event.preventDefault()
		if (!receipt?.monto_total) return
		await run(
			() => supabase.rpc('registrar_pago_proveedor', ({
				p_recibo_id: receipt.id,
				p_origen: providerOrigin,
				p_pagador_miembro_id: providerOrigin === 'ADELANTO_INTEGRANTE' ? providerPayer : null,
				p_monto: receipt.monto_total,
				p_fecha_pago: providerDate,
				...(providerReference ? { p_referencia: providerReference } : {}),
			}) as unknown as Database['public']['Functions']['registrar_pago_proveedor']['Args']).then(({ error }) => ({ error })),
			'Pago al proveedor registrado.',
		)
	}

	const openDistributionOverride = () => {
		setDistributionDraft(Object.fromEntries(members.map((member) => {
			const quota = quotas.find((item) => item.miembro_id === member.id)
			return [member.id, { selected: Boolean(quota), amount: quota ? String(quota.monto_asignado) : '' }]
		})))
		setDistributionReason(receipt?.distribucion_ajuste_motivo ?? '')
		setDistributionOpen(true)
	}

	const equalizeDistribution = () => {
		if (!receipt?.monto_total) return
		const selected = members.filter((member) => distributionDraft[member.id]?.selected)
		const shares = splitMoney(receipt.monto_total, selected.length)
		setDistributionDraft((current) => {
			const next = structuredClone(current)
			selected.forEach((member, index) => {
				next[member.id] = { selected: true, amount: shares[index] ?? '' }
			})
			return next
		})
	}

	const saveDistributionOverride = async (event: FormEvent) => {
		event.preventDefault()
		if (!receipt?.monto_total) return
		const rows = members
			.filter((member) => distributionDraft[member.id]?.selected)
			.map((member) => ({
				miembro_id: member.id,
				monto: Number(distributionDraft[member.id]?.amount || 0),
			}))

		if (!rows.length) return setMessage('Selecciona al menos un integrante para este recibo.')
		const total = rows.reduce((sum, row) => sum + row.monto, 0)
		if (rows.some((row) => row.monto <= 0) || Math.abs(total - receipt.monto_total) > 0.005) {
			return setMessage(`La distribución debe sumar exactamente ${money(receipt.monto_total)} y todas las cuotas deben ser mayores a cero.`)
		}
		if (!distributionReason.trim()) return setMessage('Indica el motivo del ajuste de este periodo.')

		await run(
			() => supabase.rpc('ajustar_cuotas_recibo', {
				p_recibo_id: receipt.id,
				p_cuotas: rows as Json,
				p_motivo: distributionReason.trim(),
			}).then(({ error }) => ({ error })),
			'Distribución del periodo actualizada sin modificar la plantilla del servicio.',
		)
		setDistributionOpen(false)
	}

	const updateDueDate = async (event: FormEvent) => {
		event.preventDefault()
		if (!receipt || !pendingDueDate) return
		await run(
			() => supabase.rpc('actualizar_vencimiento_recibo', {
				p_recibo_id: receipt.id,
				p_fecha_vencimiento: pendingDueDate,
			}).then(({ error }) => ({ error })),
			'Vencimiento y fecha límite familiar actualizados.',
		)
		setPendingDueDate('')
	}

	const annulReceipt = async () => {
		if (!receipt) return
		const reason = window.prompt('Motivo de la anulación del recibo:')
		if (!reason) return
		await run(
			() => supabase.rpc('anular_recibo', {
				p_recibo_id: receipt.id,
				p_motivo: reason,
			}).then(({ error }) => ({ error })),
			'Recibo anulado sin eliminar su historial.',
		)
	}

	const attachProviderProof = async () => {
		if (!familia || !activeProviderPayment || !providerProof) return
		setWorking(true)
		setMessage(null)
		const path = `${familia.id}/proveedor/${activeProviderPayment.id}/comprobante-${crypto.randomUUID()}.${fileExtension(providerProof)}`
		const { error: uploadError } = await supabase.storage.from('familia-comprobantes').upload(path, providerProof)
		if (uploadError) {
			setMessage(uploadError.message)
			setWorking(false)
			return
		}

		const { error } = await supabase.rpc('adjuntar_comprobante_pago_proveedor', {
			p_pago_id: activeProviderPayment.id,
			p_comprobante_storage_path: path,
		})
		if (error) {
			await supabase.storage.from('familia-comprobantes').remove([path])
			setMessage(error.message)
		} else {
			setProviderProof(null)
			setMessage('Comprobante del proveedor guardado.')
			await load()
		}
		setWorking(false)
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

			{receipt.monto_total != null && !receipt.fecha_vencimiento && receipt.tipo_vencimiento !== 'DIA_FIJO' && isAdmin && receipt.estado !== 'ANULADO' && receipt.estado !== 'PAGADO' && (
				<section className="mt-6 rounded-3xl border border-amber-100 bg-amber-50 p-5 sm:p-6">
					<div className="flex items-center gap-3 text-amber-800">
						<CircleAlert size={20} />
						<div><h2 className="font-semibold">Falta el vencimiento del proveedor</h2><p className="mt-1 text-xs">El monto ya es conocido. Registra únicamente la fecha para calcular la fecha límite familiar.</p></div>
					</div>
					<form onSubmit={updateDueDate} className="mt-5 flex flex-col gap-3 sm:flex-row">
						<input className="fh-input max-w-xs" type="date" required value={pendingDueDate} onChange={(e) => setPendingDueDate(e.target.value)} />
						<button disabled={working} className="fh-button-primary">Guardar vencimiento</button>
					</form>
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
									<div className="flex items-center gap-5 text-right"><div><p className="text-[10px] uppercase text-slate-400">Cuota</p><p className="text-sm font-semibold">{money(quota.monto_asignado)}</p></div><div><p className="text-[10px] uppercase text-slate-400">Falta</p><p className="text-sm font-semibold text-[#0f766e]">{money(quota.saldo_pendiente)}</p></div>{quota.usuario_id === user?.id && quota.estado === 'POR_VALIDAR' && <Link to="/pagos" className="fh-button-secondary">Pago enviado</Link>}
{quota.usuario_id === user?.id && quota.estado !== 'POR_VALIDAR' && quota.estado !== 'PAGADA' && quota.estado !== 'ANULADA' && (quota.saldo_pendiente ?? 0) > 0 && <Link to={`/pagar?cuotas=${quota.id}`} className="fh-button-primary">Pagar</Link>}</div>
								</div>
							</div>
						))}
					</div>
				</section>
			)}

			{isAdmin && receipt.monto_total != null && receipt.estado !== 'PAGADO' && receipt.estado !== 'ANULADO' && (
				<section className="mt-5 rounded-3xl border border-slate-200 bg-white p-5 sm:p-6">
					<div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
						<div>
							<div className="flex flex-wrap items-center gap-2">
								<h2 className="font-semibold">Excepción de este periodo</h2>
								{receipt.distribucion_ajustada && <span className="rounded-full bg-amber-50 px-2 py-1 text-[10px] font-semibold text-amber-700">Distribución ajustada</span>}
							</div>
							<p className="mt-1 text-xs leading-5 text-slate-400">Permite excluir o reasignar integrantes solo en este recibo. La plantilla del servicio no cambia.</p>
							{receipt.distribucion_ajuste_motivo && <p className="mt-2 text-xs text-slate-500">Motivo actual: {receipt.distribucion_ajuste_motivo}</p>}
						</div>
						<button type="button" disabled={hasActiveContributions || hasActiveFamilyPayments || Boolean(activeProviderPayment)} onClick={openDistributionOverride} className="fh-button-secondary shrink-0 disabled:opacity-40">Ajustar distribución</button>
					</div>

					{(hasActiveContributions || hasActiveFamilyPayments || activeProviderPayment) && <p className="mt-3 text-xs text-amber-700">La distribución queda bloqueada desde el primer pago preparado, aporte activo o pago al proveedor.</p>}

					{distributionOpen && (
						<form onSubmit={saveDistributionOverride} className="mt-5 rounded-2xl bg-slate-50 p-4">
							<div className="space-y-3">
								{members.map((member) => {
									const draft = distributionDraft[member.id] ?? { selected: false, amount: '' }
									return (
										<div key={member.id} className="grid gap-3 rounded-xl bg-white p-3 sm:grid-cols-[1fr_180px] sm:items-center">
											<label className="flex items-center gap-3 text-sm font-medium"><input type="checkbox" checked={draft.selected} onChange={(e) => setDistributionDraft((current) => ({ ...current, [member.id]: { ...draft, selected: e.target.checked, amount: e.target.checked ? draft.amount : '' } }))} className="size-4 accent-[#0f766e]" />{member.nombre}</label>
											{draft.selected && <input className="fh-input" type="number" min="0.01" step="0.01" required value={draft.amount} onChange={(e) => setDistributionDraft((current) => ({ ...current, [member.id]: { ...draft, amount: e.target.value } }))} placeholder="Monto" />}
										</div>
									)
								})}
							</div>
							<div className="mt-4 grid gap-3 sm:grid-cols-[1fr_auto_auto]">
								<input className="fh-input" required value={distributionReason} onChange={(e) => setDistributionReason(e.target.value)} placeholder="Motivo de la excepción de este periodo" />
								<button type="button" onClick={equalizeDistribution} className="fh-button-secondary">Repartir igual</button>
								<button disabled={working} className="fh-button-primary">Guardar ajuste</button>
							</div>
						</form>
					)}
				</section>
			)}

			{contributions.length > 0 && (
				<section className="mt-6 rounded-3xl border border-slate-200 bg-white p-5 sm:p-6">
					<div className="flex items-center gap-3"><CreditCard size={19} className="text-[#0f766e]" /><div><h2 className="font-semibold">Aportes y reembolsos</h2><p className="text-xs text-slate-400">Libro financiero del recibo. Los pagos nuevos se validan desde la sección Pagos.</p></div></div>
					<div className="mt-5 space-y-3">
						{contributions.map((contribution) => {
							const quota = quotaMap.get(contribution.cuota_id)
							return (
								<div key={contribution.id} className="flex flex-col gap-2 rounded-2xl border border-slate-100 p-4 sm:flex-row sm:items-center sm:justify-between">
									<div><p className="text-sm font-semibold">{quota?.nombre_miembro ?? 'Integrante'} · {money(contribution.monto)}</p><p className="mt-1 text-xs text-slate-400">{contribution.tipo === 'REEMBOLSO' ? 'Reembolso' : contribution.tipo === 'COBERTURA_ADELANTO' ? 'Cubierto por adelanto' : 'Aporte familiar'} · {contribution.estado.replaceAll('_', ' ')}</p></div>
									{contribution.pago_familiar_id && <Link to="/pagos" className="text-xs font-semibold text-[#0f766e]">Ver pago</Link>}
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
							<div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div className="flex items-start gap-3"><CircleCheck className="mt-0.5 text-emerald-600" size={19} /><div><p className="text-sm font-semibold text-emerald-800">Proveedor pagado · {money(activeProviderPayment.monto)}</p><p className="mt-1 text-xs text-emerald-700/70">{activeProviderPayment.origen === 'ADELANTO_INTEGRANTE' ? `Adelantó ${activeProviderPayment.pagador_nombre_snapshot ?? 'un integrante'}` : 'Pagado desde fondo familiar'} · {dateLabel(activeProviderPayment.fecha_pago)}</p></div></div><div className="flex flex-wrap gap-2">{providerProofUrl && <button type="button" onClick={() => window.open(providerProofUrl, '_blank', 'noopener,noreferrer')} className="fh-button-secondary flex items-center gap-2"><ExternalLink size={14} />Comprobante</button>}{isAdmin && <button onClick={() => void annulProviderPayment(activeProviderPayment)} className="fh-button-secondary flex items-center gap-2"><RotateCcw size={14} />Anular pago</button>}</div></div>
							{isAdmin && !activeProviderPayment.comprobante_storage_path && <div className="mt-4 flex flex-col gap-3 rounded-xl bg-white/70 p-3 sm:flex-row sm:items-center"><label className="flex flex-1 cursor-pointer items-center gap-3"><div className="grid size-10 place-items-center rounded-xl bg-slate-50 text-slate-400"><ImageUp size={17} /></div><div><p className="text-xs font-semibold">{providerProof ? providerProof.name : 'Adjuntar comprobante del proveedor'}</p><p className="mt-1 text-[10px] text-slate-400">Imagen o PDF · separado del comprobante del integrante</p></div><input className="hidden" type="file" accept="image/png,image/jpeg,image/webp,application/pdf" onChange={(e) => setProviderProof(e.target.files?.[0] ?? null)} /></label><button type="button" disabled={!providerProof || working} onClick={() => void attachProviderProof()} className="fh-button-primary">Guardar comprobante</button></div>}
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

			{isAdmin && receipt.estado !== 'ANULADO' && (
				<section className="mt-6 rounded-3xl border border-rose-100 bg-rose-50/50 p-5">
					<div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
						<div><p className="text-sm font-semibold text-rose-700">Anular recibo</p><p className="mt-1 text-xs leading-5 text-rose-600/70">No elimina datos. FamiliaHub exige resolver primero cualquier aporte o pago al proveedor activo.</p></div>
						<button type="button" disabled={working} onClick={() => void annulReceipt()} className="fh-button-secondary shrink-0 text-rose-600">Anular recibo</button>
					</div>
				</section>
			)}

			{message && <p className="fh-alert mt-5">{message}</p>}
		</div>
	)
}

function Metric({ label, value, accent = false }: { label: string; value: string; accent?: boolean }) {
	return <div className={`rounded-2xl border p-5 ${accent ? 'border-emerald-100 bg-emerald-50/60' : 'border-slate-200 bg-white'}`}><p className={`text-[10px] font-semibold uppercase tracking-wide ${accent ? 'text-emerald-700/60' : 'text-slate-400'}`}>{label}</p><p className={`mt-2 text-lg font-semibold ${accent ? 'text-[#0f766e]' : 'text-slate-800'}`}>{value}</p></div>
}

function splitMoney(total: number, count: number) {
	if (!count) return []
	const cents = Math.round(total * 100)
	const base = Math.floor(cents / count)
	const values = Array.from({ length: count }, () => base)
	values[count - 1] = cents - base * (count - 1)
	return values.map((value) => (value / 100).toFixed(2))
}
