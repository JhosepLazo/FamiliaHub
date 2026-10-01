import { ArrowLeft, CheckCircle2, Copy, ImageUp, ReceiptText, ShieldCheck } from 'lucide-react'
import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import type { Enums, Json, Tables } from '../../types/database'
import { useAuth } from '../auth/AuthContext'
import { useFamilia } from '../familia/FamiliaContext'
import { money, todayLima } from '../recibos/reciboUi'
import { fileExtension, metodoPagoLabel, signedFileUrl, type MetodoPago } from './pagoUi'

type Cuota = Tables<'cuotas'>
type Recibo = Tables<'recibos'>
type FamilyConfig = Tables<'configuracion_pago_familiar'>
type PersonalConfig = Tables<'configuracion_cobro_miembro'>
type Pago = Tables<'pagos_familiares'>

type Group = {
	key: string
	destino: Enums<'destino_aporte'>
	receptorMiembroId: string | null
	receptorNombre: string
	rows: { cuota: Cuota; recibo: Recibo }[]
	configs: Array<FamilyConfig | PersonalConfig>
}

export default function PagarPage() {
	const { user } = useAuth()
	const { familia } = useFamilia()
	const [params] = useSearchParams()
	const quotaIds = useMemo(() => [...new Set((params.get('cuotas') ?? '').split(',').filter(Boolean))], [params])
	const [groups, setGroups] = useState<Group[]>([])
	const [amounts, setAmounts] = useState<Record<string, string>>({})
	const [methods, setMethods] = useState<Record<string, MetodoPago>>({})
	const [activeGroup, setActiveGroup] = useState<string | null>(null)
	const [draft, setDraft] = useState<Pago | null>(null)
	const [qrUrl, setQrUrl] = useState<string | null>(null)
	const [reference, setReference] = useState('')
	const [proof, setProof] = useState<File | null>(null)
	const [paymentDate, setPaymentDate] = useState(todayLima())
	const [sentGroups, setSentGroups] = useState<string[]>([])
	const [loading, setLoading] = useState(true)
	const [working, setWorking] = useState(false)
	const [message, setMessage] = useState<string | null>(null)

	const load = useCallback(async () => {
		if (!familia || !user || !quotaIds.length) {
			setLoading(false)
			return
		}

		setLoading(true)
		setMessage(null)

		const { data: quotaRows, error } = await supabase
			.from('cuotas')
			.select('*')
			.in('id', quotaIds)
			.eq('familia_id', familia.id)
			.eq('usuario_id', user.id)

		if (error || !quotaRows?.length) {
			setMessage(error?.message ?? 'No encontramos cuotas disponibles para pagar.')
			setLoading(false)
			return
		}

		const receiptIds = [...new Set(quotaRows.map((row) => row.recibo_id))]
		const receiverIds = [...new Set(quotaRows.map((row) => row.receptor_miembro_id).filter((value): value is string => Boolean(value)))]

		const [{ data: receiptRows }, { data: familyConfigs }, personalResult] = await Promise.all([
			supabase.from('recibos').select('*').in('id', receiptIds),
			supabase.from('configuracion_pago_familiar').select('*').eq('familia_id', familia.id).eq('activo', true),
			receiverIds.length
				? supabase.from('configuracion_cobro_miembro').select('*').in('miembro_id', receiverIds).eq('activo', true)
				: Promise.resolve({ data: [] as PersonalConfig[] }),
		])

		const receipts = new Map((receiptRows ?? []).map((row) => [row.id, row]))
		const personalConfigs = personalResult.data ?? []
		const memberIds = receiverIds
		let memberNames = new Map<string, string>()
		if (memberIds.length) {
			const { data: members } = await supabase.from('miembros_familia').select('id,usuario_id').in('id', memberIds)
			const userIds = (members ?? []).map((row) => row.usuario_id)
			const { data: profiles } = userIds.length ? await supabase.from('perfiles').select('id,nombre').in('id', userIds) : { data: [] }
			const profilesMap = new Map((profiles ?? []).map((row) => [row.id, row.nombre ?? 'Integrante']))
			memberNames = new Map((members ?? []).map((row) => [row.id, profilesMap.get(row.usuario_id) ?? 'Integrante']))
		}

		const map = new Map<string, Group>()
		const initialAmounts: Record<string, string> = {}
		const initialMethods: Record<string, MetodoPago> = {}

		for (const quota of quotaRows) {
			if (quota.estado === 'ANULADA' || quota.estado === 'PAGADA' || quota.estado === 'POR_VALIDAR' || (quota.saldo_pendiente ?? 0) <= 0) continue
			const receipt = receipts.get(quota.recibo_id)
			if (!receipt) continue
			const key = `${quota.destino}:${quota.receptor_miembro_id ?? 'FONDO'}`
			const existing = map.get(key)
			if (existing) {
				existing.rows.push({ cuota: quota, recibo: receipt })
			} else {
				const configs = quota.destino === 'FONDO_FAMILIAR'
					? (familyConfigs ?? [])
					: personalConfigs.filter((config) => config.miembro_id === quota.receptor_miembro_id)
				map.set(key, {
					key,
					destino: quota.destino,
					receptorMiembroId: quota.receptor_miembro_id,
					receptorNombre: quota.destino === 'FONDO_FAMILIAR' ? `Fondo familiar · ${familia.nombre}` : memberNames.get(quota.receptor_miembro_id ?? '') ?? 'Integrante',
					rows: [{ cuota: quota, recibo: receipt }],
					configs,
				})
			}
			initialAmounts[quota.id] = String(quota.saldo_pendiente ?? 0)
		}

		const nextGroups = [...map.values()]
		for (const group of nextGroups) {
			if (group.configs.length) initialMethods[group.key] = group.configs[0].metodo
		}

		setGroups(nextGroups)
		setAmounts(initialAmounts)
		setMethods(initialMethods)
		setLoading(false)
	}, [familia, user, quotaIds])

	useEffect(() => { void load() }, [load])

	const prepare = async (group: Group) => {
		const method = methods[group.key]
		if (!method) {
			setMessage('El receptor todavía no tiene un método de cobro disponible.')
			return
		}

		const assignments = group.rows.map(({ cuota }) => ({
			cuota_id: cuota.id,
			monto: Number(amounts[cuota.id] || 0),
		}))

		if (assignments.some((row) => row.monto <= 0)) {
			setMessage('Todos los importes deben ser mayores a cero.')
			return
		}

		setWorking(true)
		setMessage(null)
		const { data: paymentId, error } = await supabase.rpc('crear_pago_familiar', {
			p_asignaciones: assignments as Json,
			p_metodo: method,
		})

		if (error || !paymentId) {
			setMessage(error?.message ?? 'No pudimos preparar el pago.')
			setWorking(false)
			return
		}

		const { data: payment } = await supabase.from('pagos_familiares').select('*').eq('id', paymentId).single()
		if (!payment) {
			setMessage('El pago se creó, pero no pudimos cargar sus datos.')
			setWorking(false)
			return
		}

		setActiveGroup(group.key)
		setDraft(payment)
		setReference('')
		setProof(null)
		setPaymentDate(todayLima())
		setQrUrl(null)

		if (payment.receptor_qr_bucket && payment.receptor_qr_storage_path) {
			try {
				setQrUrl(await signedFileUrl(payment.receptor_qr_bucket, payment.receptor_qr_storage_path, 300))
			} catch {
				setQrUrl(null)
			}
		}

		setWorking(false)
	}

	const cancelDraft = async () => {
		if (!draft) return
		setWorking(true)
		const { error } = await supabase.rpc('anular_pago_familiar', {
			p_pago_id: draft.id,
			p_motivo: 'Preparación cancelada por el pagador.',
		})
		if (error) {
			setMessage(error.message)
		} else {
			setDraft(null)
			setActiveGroup(null)
			setQrUrl(null)
			setProof(null)
			setReference('')
		}
		setWorking(false)
	}

	const finalize = async (event: FormEvent) => {
		event.preventDefault()
		if (!draft || !familia || !activeGroup) return
		setWorking(true)
		setMessage(null)

		let proofPath: string | undefined
		if (proof) {
			proofPath = `${familia.id}/pagos/${draft.id}/comprobante-${crypto.randomUUID()}.${fileExtension(proof)}`
			const { error: uploadError } = await supabase.storage.from('familia-comprobantes').upload(proofPath, proof)
			if (uploadError) {
				setMessage(uploadError.message)
				setWorking(false)
				return
			}
		}

		const { error } = await supabase.rpc('finalizar_pago_familiar', {
			p_pago_id: draft.id,
			p_fecha_pago: paymentDate,
			p_referencia_operacion: reference.trim() || undefined,
			p_comprobante_storage_path: proofPath,
		})

		if (error) {
			setMessage(error.message)
			setWorking(false)
			return
		}

		setSentGroups((current) => [...current, activeGroup])
		setDraft(null)
		setActiveGroup(null)
		setQrUrl(null)
		setProof(null)
		setReference('')
		setMessage('Pago enviado para validación. Tu cuota no se marcará como pagada hasta que el receptor lo confirme.')
		setWorking(false)
	}

	if (loading) return <div className="h-96 animate-pulse rounded-3xl bg-white" />

	return (
		<div className="mx-auto max-w-5xl">
			<div className="flex items-start gap-4">
				<Link to="/mis-cuotas" className="mt-1 grid size-10 shrink-0 place-items-center rounded-xl border border-slate-200 bg-white text-slate-500"><ArrowLeft size={17} /></Link>
				<div><p className="text-sm font-semibold text-[#0f766e]">Pago</p><h1 className="mt-1 text-3xl font-semibold tracking-tight">Pagar cuotas</h1><p className="mt-2 text-sm leading-6 text-slate-500">FamiliaHub separa automáticamente destinatarios distintos para que un solo pago externo nunca mezcle receptores.</p></div>
			</div>

			{groups.length > 1 && <div className="mt-6 rounded-2xl border border-sky-100 bg-sky-50 p-4 text-sm text-sky-700">Estas cuotas pertenecen a {groups.length} receptores. Deberás completar un pago por cada grupo.</div>}

			<div className="mt-6 space-y-5">
				{groups.length === 0 && <div className="rounded-3xl border border-dashed border-slate-300 bg-white p-8 text-center"><CheckCircle2 className="mx-auto text-emerald-600" /><h2 className="mt-3 font-semibold">No hay cuotas disponibles para pagar</h2></div>}
				{groups.map((group) => {
					const sent = sentGroups.includes(group.key)
					const total = group.rows.reduce((sum, { cuota }) => sum + Number(amounts[cuota.id] || 0), 0)
					return (
						<section key={group.key} className={`rounded-3xl border bg-white p-5 sm:p-6 ${sent ? 'border-emerald-100 opacity-70' : 'border-slate-200'}`}>
							<div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
								<div><div className="flex items-center gap-2"><ShieldCheck size={18} className="text-[#0f766e]" /><h2 className="font-semibold">{group.receptorNombre}</h2></div><p className="mt-1 text-xs text-slate-400">{group.destino === 'FONDO_FAMILIAR' ? 'Aporte al fondo familiar' : 'Reembolso a integrante'}</p></div>
								{sent && <span className="rounded-full bg-emerald-50 px-3 py-1.5 text-xs font-semibold text-emerald-700">Pago enviado</span>}
							</div>

							<div className="mt-5 space-y-3">
								{group.rows.map(({ cuota, recibo }) => (
									<div key={cuota.id} className="grid gap-3 rounded-2xl bg-slate-50 p-4 sm:grid-cols-[1fr_170px] sm:items-center">
										<div><p className="text-sm font-semibold">{recibo.nombre_concepto}</p><p className="mt-1 text-xs text-slate-400">Saldo disponible: {money(cuota.saldo_pendiente)}</p></div>
										<input className="fh-input" type="number" min="0.01" max={cuota.saldo_pendiente ?? 0} step="0.01" disabled={sent || activeGroup === group.key} value={amounts[cuota.id] ?? ''} onChange={(e) => setAmounts((current) => ({ ...current, [cuota.id]: e.target.value }))} />
									</div>
								))}
							</div>

							<div className="mt-5 grid gap-4 sm:grid-cols-[1fr_auto] sm:items-end">
								<label><span className="fh-label">Método</span><select className="fh-input" disabled={sent || activeGroup === group.key} value={methods[group.key] ?? ''} onChange={(e) => setMethods((current) => ({ ...current, [group.key]: e.target.value as MetodoPago }))}><option value="">Selecciona</option>{group.configs.map((config) => <option key={config.id} value={config.metodo}>{metodoPagoLabel[config.metodo]}</option>)}</select></label>
								<button type="button" disabled={sent || working || activeGroup !== null || group.configs.length === 0} onClick={() => void prepare(group)} className="fh-button-primary">Preparar {money(total)}</button>
							</div>

							{group.configs.length === 0 && <p className="mt-3 text-xs text-amber-700">Este receptor todavía no configuró una forma de cobro. El pago no puede prepararse hasta resolverlo.</p>}

							{draft && activeGroup === group.key && (
								<div className="mt-6 rounded-2xl border border-emerald-100 bg-emerald-50/50 p-5">
									<h3 className="font-semibold">Realiza el pago fuera de FamiliaHub</h3>
									<p className="mt-1 text-xs text-slate-500">Importe exacto: <strong>{money(draft.monto_total)}</strong> · {metodoPagoLabel[draft.metodo]}</p>

									<div className="mt-5 grid gap-4 sm:grid-cols-2">
										<div className="rounded-2xl bg-white p-4"><p className="text-[10px] font-semibold uppercase text-slate-400">Titular</p><p className="mt-1 text-sm font-semibold">{draft.receptor_titular_snapshot}</p>{draft.receptor_referencia_snapshot && <div className="mt-3 flex items-center gap-2"><code className="text-xs text-slate-600">{draft.receptor_referencia_snapshot}</code><button type="button" onClick={() => void navigator.clipboard.writeText(draft.receptor_referencia_snapshot ?? '')} className="text-slate-400"><Copy size={14} /></button></div>}</div>
										{qrUrl ? <img src={qrUrl} alt="QR de cobro" className="mx-auto size-40 rounded-2xl bg-white object-contain p-2" /> : <div className="grid min-h-40 place-items-center rounded-2xl bg-white text-xs text-slate-400">Sin QR para este método</div>}
									</div>

									<form onSubmit={finalize} className="mt-5 grid gap-4 sm:grid-cols-2">
										<label><span className="fh-label">Fecha del pago</span><input className="fh-input" type="date" max={todayLima()} required value={paymentDate} onChange={(e) => setPaymentDate(e.target.value)} /></label>
										<label><span className="fh-label">Referencia / operación</span><input className="fh-input" value={reference} onChange={(e) => setReference(e.target.value)} placeholder="Código de Yape, operación, etc." /></label>
										<label className="sm:col-span-2 flex cursor-pointer items-center gap-4 rounded-2xl border border-dashed border-slate-300 bg-white p-4"><div className="grid size-14 place-items-center rounded-xl bg-slate-50 text-slate-400"><ImageUp /></div><div><p className="text-sm font-semibold">{proof ? proof.name : 'Adjuntar comprobante'}</p><p className="mt-1 text-xs text-slate-400">Imagen o PDF · máximo 8 MB. Para Yape/transferencia se exige referencia o comprobante.</p></div><input className="hidden" type="file" accept="image/png,image/jpeg,image/webp,application/pdf" onChange={(e) => setProof(e.target.files?.[0] ?? null)} /></label>
										<div className="sm:col-span-2 flex flex-wrap gap-3"><button className="fh-button-primary" disabled={working}>Ya pagué · Enviar a validar</button><button type="button" disabled={working} className="fh-button-secondary" onClick={() => void cancelDraft()}>Cancelar preparación</button></div>
									</form>
								</div>
							)}
						</section>
					)
				})}
			</div>

			{sentGroups.length > 0 && <div className="mt-6 rounded-2xl bg-emerald-50 p-4 text-sm text-emerald-800"><ReceiptText size={17} className="mb-2" />Los pagos enviados quedan reservados mientras esperan validación. <Link to="/pagos" className="font-semibold underline">Ver mis pagos</Link></div>}
			{message && <p className="fh-alert mt-5">{message}</p>}
		</div>
	)
}
