import { CirclePlus, Pencil, Power, Settings2, UsersRound } from 'lucide-react'
import { useCallback, useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import type { Tables } from '../../types/database'
import { useFamilia } from '../familia/FamiliaContext'
import {
	distribucionLabel,
	frecuenciaLabel,
	integrationLabel,
	metodoLabel,
	money,
	ServicioIcon,
	tipoServicioLabel,
} from './servicioUi'

type Concepto = Tables<'conceptos_pago'>
type Proveedor = Tables<'proveedores'>
type Cuenta = Tables<'cuentas_servicio'>

export default function ServiciosPage() {
	const { familia } = useFamilia()
	const [conceptos, setConceptos] = useState<Concepto[]>([])
	const [proveedores, setProveedores] = useState<Proveedor[]>([])
	const [cuentas, setCuentas] = useState<Cuenta[]>([])
	const [participantes, setParticipantes] = useState<Record<string, number>>({})
	const [showInactive, setShowInactive] = useState(false)
	const [message, setMessage] = useState<string | null>(null)
	const [loading, setLoading] = useState(true)

	const load = useCallback(async () => {
		if (!familia) return
		setLoading(true)

		const [{ data: concepts }, { data: providers }] = await Promise.all([
			supabase.from('conceptos_pago').select('*').eq('familia_id', familia.id).order('created_at'),
			supabase.from('proveedores').select('*').order('nombre'),
		])

		const rows = concepts ?? []
		setConceptos(rows)
		setProveedores(providers ?? [])

		const ids = rows.map((item) => item.id)
		if (!ids.length) {
			setCuentas([])
			setParticipantes({})
			setLoading(false)
			return
		}

		const [{ data: accountRows }, { data: participantRows }] = await Promise.all([
			supabase.from('cuentas_servicio').select('*').in('concepto_id', ids),
			supabase.from('concepto_participantes').select('concepto_id').in('concepto_id', ids),
		])

		setCuentas(accountRows ?? [])

		const counts: Record<string, number> = {}
		for (const row of participantRows ?? []) counts[row.concepto_id] = (counts[row.concepto_id] ?? 0) + 1
		setParticipantes(counts)
		setLoading(false)
	}, [familia])

	useEffect(() => { void load() }, [load])

	const providerMap = useMemo(() => new Map(proveedores.map((provider) => [provider.id, provider])), [proveedores])
	const accountMap = useMemo(() => new Map(cuentas.map((account) => [account.concepto_id, account])), [cuentas])
	const customProviders = useMemo(
		() => proveedores.filter((provider) => provider.familia_id === familia?.id),
		[proveedores, familia],
	)
	const visibleConcepts = useMemo(
		() => conceptos.filter((concepto) => showInactive || concepto.activo),
		[conceptos, showInactive],
	)

	const toggleConcept = async (concepto: Concepto) => {
		setMessage(null)
		const { error } = await supabase.rpc('cambiar_estado_concepto', {
			p_concepto_id: concepto.id,
			p_activo: !concepto.activo,
		})
		setMessage(error ? error.message : concepto.activo ? 'Servicio desactivado.' : 'Servicio activado.')
		if (!error) await load()
	}

	const toggleProvider = async (provider: Proveedor) => {
		setMessage(null)
		const { error } = await supabase.rpc('cambiar_estado_proveedor_personalizado', {
			p_proveedor_id: provider.id,
			p_activo: !provider.activo,
		})
		setMessage(error ? error.message : provider.activo ? 'Proveedor desactivado.' : 'Proveedor activado.')
		if (!error) await load()
	}

	return (
		<div>
			<div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
				<div>
					<p className="text-sm font-semibold text-[#0f766e]">Configuración</p>
					<h1 className="mt-1 text-3xl font-semibold tracking-tight">Servicios del hogar</h1>
					<p className="mt-2 max-w-2xl text-sm leading-6 text-slate-500">
						Define una vez cómo funciona cada pago. Los recibos reales se generarán en la siguiente fase a partir de esta configuración.
					</p>
				</div>
				<Link to="/servicios/nuevo" className="fh-button-primary flex items-center gap-2">
					<CirclePlus size={17} />Nuevo servicio
				</Link>
			</div>

			<div className="mt-7 flex items-center justify-between gap-4">
				<p className="text-sm text-slate-500">
					{conceptos.filter((item) => item.activo).length} servicio{conceptos.filter((item) => item.activo).length === 1 ? '' : 's'} activo{conceptos.filter((item) => item.activo).length === 1 ? '' : 's'}
				</p>
				<label className="flex items-center gap-2 text-xs font-medium text-slate-500">
					<input type="checkbox" checked={showInactive} onChange={(e) => setShowInactive(e.target.checked)} />
					Mostrar inactivos
				</label>
			</div>

			{loading ? (
				<div className="mt-6 grid gap-4 lg:grid-cols-2">
					<div className="h-44 animate-pulse rounded-3xl bg-white" />
					<div className="h-44 animate-pulse rounded-3xl bg-white" />
				</div>
			) : visibleConcepts.length === 0 ? (
				<section className="mt-6 rounded-3xl border border-dashed border-slate-300 bg-white p-8 text-center">
					<div className="mx-auto grid size-12 place-items-center rounded-2xl bg-emerald-50 text-[#0f766e]"><Settings2 /></div>
					<h2 className="mt-4 text-lg font-semibold">Aún no configuraste servicios</h2>
					<p className="mx-auto mt-2 max-w-lg text-sm leading-6 text-slate-500">Empieza por Agua, Luz, Internet o Gas. FamiliaHub te sugerirá la configuración inicial y tú solo eliges participantes y forma de división.</p>
					<Link to="/servicios/nuevo" className="fh-button-primary mt-5 inline-flex">Configurar primer servicio</Link>
				</section>
			) : (
				<div className="mt-6 grid gap-4 lg:grid-cols-2">
					{visibleConcepts.map((concepto) => {
						const provider = providerMap.get(concepto.proveedor_id)
						const account = accountMap.get(concepto.id)
						return (
							<article key={concepto.id} className={`rounded-3xl border bg-white p-5 sm:p-6 ${concepto.activo ? 'border-slate-200' : 'border-slate-200 opacity-65'}`}>
								<div className="flex items-start justify-between gap-4">
									<div className="flex min-w-0 items-center gap-4">
										<div className="grid size-12 shrink-0 place-items-center rounded-2xl bg-emerald-50 text-[#0f766e]">
											<ServicioIcon tipo={provider?.tipo_servicio ?? 'OTRO'} />
										</div>
										<div className="min-w-0">
											<div className="flex flex-wrap items-center gap-2">
												<h2 className="truncate font-semibold">{concepto.nombre}</h2>
												<span className={`rounded-full px-2 py-1 text-[10px] font-semibold ${concepto.activo ? 'bg-emerald-50 text-[#0f766e]' : 'bg-slate-100 text-slate-400'}`}>{concepto.activo ? 'Activo' : 'Inactivo'}</span>
											</div>
											<p className="mt-1 text-xs text-slate-400">{provider?.nombre ?? 'Proveedor'} · {tipoServicioLabel[provider?.tipo_servicio ?? 'OTRO']}</p>
										</div>
									</div>
									<div className="flex shrink-0 gap-2">
										<Link to={`/servicios/${concepto.id}/editar`} className="grid size-9 place-items-center rounded-xl border border-slate-200 text-slate-500 hover:bg-slate-50" title="Editar"><Pencil size={16} /></Link>
										<button onClick={() => void toggleConcept(concepto)} className="grid size-9 place-items-center rounded-xl border border-slate-200 text-slate-500 hover:bg-slate-50" title={concepto.activo ? 'Desactivar' : 'Activar'}><Power size={16} /></button>
									</div>
								</div>

								<div className="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-4">
									<Info label="Monto" value={concepto.metodo_obtencion === 'FIJO' ? money(concepto.monto_fijo) : metodoLabel[concepto.metodo_obtencion]} />
									<Info label="Frecuencia" value={frecuenciaLabel[concepto.frecuencia]} />
									<Info label="División" value={distribucionLabel[concepto.tipo_distribucion]} />
									<Info label="Participantes" value={String(participantes[concepto.id] ?? 0)} />
								</div>

								<div className="mt-5 flex flex-wrap gap-2 text-xs">
									{account && <span className="rounded-full bg-slate-100 px-3 py-1.5 text-slate-500">{account.alias || account.identificador_nombre || 'Cuenta'} · {mask(account.identificador_valor)}</span>}
									{concepto.metodo_obtencion === 'AUTOMATICO' && provider && (
										<span className={`rounded-full px-3 py-1.5 ${provider.estado_integracion === 'DISPONIBLE' ? 'bg-emerald-50 text-[#0f766e]' : 'bg-amber-50 text-amber-700'}`}>{integrationLabel(provider.estado_integracion)}</span>
									)}
								</div>
							</article>
						)
					})}
				</div>
			)}

			<section className="mt-9 rounded-3xl border border-slate-200 bg-white p-6">
				<div className="flex items-center gap-3">
					<div className="grid size-10 place-items-center rounded-xl bg-slate-50 text-slate-500"><UsersRound size={18} /></div>
					<div>
						<h2 className="font-semibold">Proveedores personalizados</h2>
						<p className="text-xs text-slate-400">Solo aparecen aquí los proveedores creados por tu familia.</p>
					</div>
				</div>

				<div className="mt-5 grid gap-3 sm:grid-cols-2">
					{customProviders.length === 0 && <p className="text-sm text-slate-400">Todavía no creaste proveedores personalizados.</p>}
					{customProviders.map((provider) => (
						<div key={provider.id} className="flex items-center justify-between rounded-2xl border border-slate-100 p-4">
							<div className="min-w-0"><p className="truncate text-sm font-semibold">{provider.nombre}</p><p className="mt-1 text-xs text-slate-400">{tipoServicioLabel[provider.tipo_servicio]} · {provider.activo ? 'Activo' : 'Inactivo'}</p></div>
							<button onClick={() => void toggleProvider(provider)} className="grid size-9 place-items-center rounded-xl border border-slate-200 text-slate-500" title={provider.activo ? 'Desactivar proveedor' : 'Activar proveedor'}><Power size={15} /></button>
						</div>
					))}
				</div>
			</section>

			{message && <p className="fh-alert mt-5">{message}</p>}
		</div>
	)
}

function Info({ label, value }: { label: string; value: string }) {
	return <div className="rounded-2xl bg-slate-50 p-3"><p className="text-[10px] font-semibold uppercase tracking-wide text-slate-400">{label}</p><p className="mt-1 truncate text-xs font-semibold text-slate-700">{value}</p></div>
}

function mask(value: string) {
	if (value.length <= 4) return value
	return `••••${value.slice(-4)}`
}
