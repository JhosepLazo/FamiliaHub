import {
	ArrowLeft,
	ArrowRight,
	Building2,
	Check,
	CircleAlert,
	CirclePlus,
	Info,
	Sparkles,
	UsersRound,
} from 'lucide-react'
import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import type { Database, Enums, Json, Tables } from '../../types/database'
import { useFamilia } from '../familia/FamiliaContext'
import {
	distribucionLabel,
	frecuenciaLabel,
	integrationLabel,
	metodoLabel,
	ServicioIcon,
	tipoServicioLabel,
	vencimientoLabel,
	type Frecuencia,
	type MetodoObtencion,
	type ModalidadParticipante,
	type RepartoResto,
	type TipoDistribucion,
	type TipoServicio,
	type TipoVencimiento,
} from './servicioUi'

type Plantilla = Tables<'plantillas_servicio'>
type Proveedor = Tables<'proveedores'>
type Categoria = Tables<'categorias'>
type Identificador = Tables<'tipos_identificador_proveedor'>

type MemberView = {
	id: string
	usuarioId: string
	nombre: string
}

type ParticipantDraft = {
	selected: boolean
	modalidad: ModalidadParticipante
	valor: string
}

type FormState = {
	plantillaId: string | null
	tipoServicio: TipoServicio
	nombre: string
	categoriaId: string
	proveedorId: string
	frecuencia: Frecuencia
	metodo: MetodoObtencion
	montoFijo: string
	tipoVencimiento: TipoVencimiento
	diaVencimiento: string
	tipoDistribucion: TipoDistribucion
	repartoResto: RepartoResto | null
	cuentaTipoId: string
	cuentaNombre: string
	cuentaValor: string
	cuentaAlias: string
	participantes: Record<string, ParticipantDraft>
}

const initialState: FormState = {
	plantillaId: null,
	tipoServicio: 'OTRO',
	nombre: '',
	categoriaId: '',
	proveedorId: '',
	frecuencia: 'MENSUAL',
	metodo: 'MANUAL',
	montoFijo: '',
	tipoVencimiento: 'VARIABLE',
	diaVencimiento: '',
	tipoDistribucion: 'IGUAL',
	repartoResto: null,
	cuentaTipoId: '',
	cuentaNombre: '',
	cuentaValor: '',
	cuentaAlias: '',
	participantes: {},
}

export default function ServicioFormPage() {
	const { id } = useParams()
	const navigate = useNavigate()
	const { familia } = useFamilia()
	const editing = Boolean(id)

	const [step, setStep] = useState(1)
	const [state, setState] = useState<FormState>(initialState)
	const [templates, setTemplates] = useState<Plantilla[]>([])
	const [providers, setProviders] = useState<Proveedor[]>([])
	const [categories, setCategories] = useState<Categoria[]>([])
	const [identifiers, setIdentifiers] = useState<Identificador[]>([])
	const [members, setMembers] = useState<MemberView[]>([])
	const [loading, setLoading] = useState(true)
	const [saving, setSaving] = useState(false)
	const [message, setMessage] = useState<string | null>(null)
	const [showCustomProvider, setShowCustomProvider] = useState(false)
	const [customProviderName, setCustomProviderName] = useState('')
	const [creatingProvider, setCreatingProvider] = useState(false)

	const load = useCallback(async () => {
		if (!familia) return
		setLoading(true)

		const [
			{ data: templateRows },
			{ data: providerRows },
			{ data: categoryRows },
			{ data: identifierRows },
			{ data: memberRows },
		] = await Promise.all([
			supabase.from('plantillas_servicio').select('*').order('orden'),
			supabase.from('proveedores').select('*').order('nombre'),
			supabase.from('categorias').select('*').eq('familia_id', familia.id).eq('activo', true).order('created_at'),
			supabase.from('tipos_identificador_proveedor').select('*').eq('activo', true).order('orden'),
			supabase.from('miembros_familia').select('*').eq('familia_id', familia.id).eq('estado', 'ACTIVO').order('joined_at'),
		])

		const memberIds = (memberRows ?? []).map((member) => member.usuario_id)
		let profiles: { id: string; nombre: string | null }[] = []
		if (memberIds.length) profiles = (await supabase.from('perfiles').select('id,nombre').in('id', memberIds)).data ?? []

		const profileMap = new Map(profiles.map((profile) => [profile.id, profile.nombre ?? 'Integrante']))
		const memberOptions: MemberView[] = (memberRows ?? []).map((member) => ({
			id: member.id,
			usuarioId: member.usuario_id,
			nombre: profileMap.get(member.usuario_id) ?? 'Integrante',
		}))

		setTemplates(templateRows ?? [])
		setProviders(providerRows ?? [])
		setCategories(categoryRows ?? [])
		setIdentifiers(identifierRows ?? [])
		setMembers(memberOptions)

		if (!editing) {
			const serviceCategory = (categoryRows ?? []).find((category) => category.nombre.toLowerCase() === 'servicios')
			setState((current) => ({
				...current,
				categoriaId: current.categoriaId || serviceCategory?.id || categoryRows?.[0]?.id || '',
				participantes: Object.fromEntries(memberOptions.map((member) => [member.id, {
					selected: false,
					modalidad: 'IGUAL' as ModalidadParticipante,
					valor: '',
				}])),
			}))
			setLoading(false)
			return
		}

		const { data: concept, error } = await supabase
			.from('conceptos_pago')
			.select('*')
			.eq('id', id!)
			.eq('familia_id', familia.id)
			.single()

		if (error || !concept) {
			setMessage('No pudimos encontrar este servicio.')
			setLoading(false)
			return
		}

		const [{ data: account }, { data: participantRows }] = await Promise.all([
			supabase.from('cuentas_servicio').select('*').eq('concepto_id', concept.id).maybeSingle(),
			supabase.from('concepto_participantes').select('*').eq('concepto_id', concept.id).order('orden'),
		])

		const provider = (providerRows ?? []).find((row) => row.id === concept.proveedor_id)
		const participantMap = new Map((participantRows ?? []).map((row) => [row.miembro_id, row]))

		setState({
			plantillaId: concept.plantilla_id,
			tipoServicio: provider?.tipo_servicio ?? 'OTRO',
			nombre: concept.nombre,
			categoriaId: concept.categoria_id,
			proveedorId: concept.proveedor_id,
			frecuencia: concept.frecuencia,
			metodo: concept.metodo_obtencion,
			montoFijo: concept.monto_fijo == null ? '' : String(concept.monto_fijo),
			tipoVencimiento: concept.tipo_vencimiento,
			diaVencimiento: concept.dia_vencimiento == null ? '' : String(concept.dia_vencimiento),
			tipoDistribucion: concept.tipo_distribucion,
			repartoResto: concept.reparto_resto,
			cuentaTipoId: account?.tipo_identificador_id ?? '',
			cuentaNombre: account?.identificador_nombre ?? '',
			cuentaValor: account?.identificador_valor ?? '',
			cuentaAlias: account?.alias ?? '',
			participantes: Object.fromEntries(memberOptions.map((member) => {
				const saved = participantMap.get(member.id)
				return [member.id, {
					selected: Boolean(saved),
					modalidad: saved?.modalidad ?? 'IGUAL',
					valor: saved?.valor == null ? '' : String(saved.valor),
				}]
			})),
		})

		setLoading(false)
	}, [familia, editing, id])

	useEffect(() => { void load() }, [load])

	const activeProviders = useMemo(
		() => providers.filter((provider) => provider.activo && provider.tipo_servicio === state.tipoServicio),
		[providers, state.tipoServicio],
	)

	const provider = useMemo(() => providers.find((item) => item.id === state.proveedorId), [providers, state.proveedorId])
	const providerIdentifiers = useMemo(
		() => identifiers.filter((identifier) => identifier.proveedor_id === state.proveedorId),
		[identifiers, state.proveedorId],
	)
	const selectedMembers = useMemo(
		() => members.filter((member) => state.participantes[member.id]?.selected),
		[members, state.participantes],
	)

	const chooseTemplate = (template: Plantilla | null) => {
		if (!template) {
			setState((current) => ({
				...current,
				plantillaId: null,
				tipoServicio: 'OTRO',
				nombre: '',
				proveedorId: '',
				frecuencia: 'MENSUAL',
				metodo: 'MANUAL',
				montoFijo: '',
				tipoVencimiento: 'VARIABLE',
				diaVencimiento: '',
				cuentaTipoId: '',
				cuentaNombre: '',
				cuentaValor: '',
				cuentaAlias: '',
			}))
			return
		}

		const matching = providers.filter((item) => item.activo && item.tipo_servicio === template.tipo_servicio)
		setState((current) => ({
			...current,
			plantillaId: template.id,
			tipoServicio: template.tipo_servicio,
			nombre: template.nombre,
			proveedorId: matching.length === 1 ? matching[0].id : '',
			frecuencia: template.frecuencia_recomendada,
			metodo: template.metodo_obtencion_recomendado,
			montoFijo: '',
			tipoVencimiento: template.tipo_vencimiento_recomendado,
			diaVencimiento: '',
			cuentaTipoId: '',
			cuentaNombre: '',
			cuentaValor: '',
			cuentaAlias: '',
		}))
	}

	const changeProvider = (providerId: string) => {
		const firstIdentifier = identifiers.find((item) => item.proveedor_id === providerId)
		setState((current) => ({
			...current,
			proveedorId,
			cuentaTipoId: firstIdentifier?.id ?? '',
			cuentaNombre: '',
			cuentaValor: '',
			cuentaAlias: '',
		}))
	}

	const changeMethod = (method: MetodoObtencion) => {
		setState((current) => {
			const next: FormState = {
				...current,
				metodo: method,
				montoFijo: method === 'FIJO' ? current.montoFijo : '',
			}
			if (method !== 'FIJO' && current.tipoDistribucion === 'MONTO_FIJO') {
				next.tipoDistribucion = 'IGUAL'
				next.repartoResto = null
				next.participantes = remapParticipants(current.participantes, 'IGUAL', null, current.montoFijo)
			}
			return next
		})
	}

	const changeDistribution = (distribution: TipoDistribucion) => {
		if (distribution === 'MONTO_FIJO' && state.metodo !== 'FIJO') {
			setMessage('La división por monto fijo solo está disponible cuando el servicio tiene un monto fijo conocido.')
			return
		}

		setMessage(null)
		const restMode: RepartoResto | null = distribution === 'MIXTA' ? 'IGUAL' : null
		setState((current) => ({
			...current,
			tipoDistribucion: distribution,
			repartoResto: restMode,
			participantes: remapParticipants(current.participantes, distribution, restMode, current.montoFijo),
		}))
	}

	const changeRemainderMode = (value: RepartoResto) => {
		setState((current) => ({
			...current,
			repartoResto: value,
			participantes: remapMixedRemainder(current.participantes, value),
		}))
	}

	const toggleParticipant = (memberId: string) => {
		setState((current) => {
			const next = structuredClone(current.participantes)
			const participant = next[memberId] ?? { selected: false, modalidad: 'IGUAL' as ModalidadParticipante, valor: '' }
			participant.selected = !participant.selected
			next[memberId] = participant

			if (participant.selected) {
				if (current.tipoDistribucion === 'IGUAL') participant.modalidad = 'IGUAL'
				if (current.tipoDistribucion === 'PORCENTAJE') participant.modalidad = 'PORCENTAJE'
				if (current.tipoDistribucion === 'MONTO_FIJO') participant.modalidad = 'MONTO_FIJO'
				if (current.tipoDistribucion === 'MIXTA') {
					const alreadyFixed = Object.values(next).some((item) => item.selected && item.modalidad === 'MONTO_FIJO')
					participant.modalidad = alreadyFixed ? (current.repartoResto === 'PORCENTAJE' ? 'RESTO_PORCENTAJE' : 'RESTO_IGUAL') : 'MONTO_FIJO'
				}
			} else {
				participant.valor = ''
			}

			return {
				...current,
				participantes: normalizeParticipantValues(next, current.tipoDistribucion, current.repartoResto, current.montoFijo),
			}
		})
	}

	const updateParticipantValue = (memberId: string, value: string) => {
		setState((current) => ({
			...current,
			participantes: {
				...current.participantes,
				[memberId]: { ...current.participantes[memberId], valor: value },
			},
		}))
	}

	const changeMixedRole = (memberId: string, fixed: boolean) => {
		setState((current) => {
			const next = structuredClone(current.participantes)
			next[memberId] = {
				...next[memberId],
				modalidad: fixed ? 'MONTO_FIJO' : current.repartoResto === 'PORCENTAJE' ? 'RESTO_PORCENTAJE' : 'RESTO_IGUAL',
				valor: '',
			}
			return {
				...current,
				participantes: normalizeParticipantValues(next, 'MIXTA', current.repartoResto, current.montoFijo),
			}
		})
	}

	const createCustomProvider = async (event: FormEvent) => {
		event.preventDefault()
		if (!familia || !customProviderName.trim()) return
		setCreatingProvider(true)
		setMessage(null)

		const { data, error } = await supabase.rpc('crear_proveedor_personalizado', {
			p_familia_id: familia.id,
			p_nombre: customProviderName.trim(),
			p_tipo_servicio: state.tipoServicio,
		})

		if (error) {
			setMessage(error.message)
		} else {
			const { data: providerRows } = await supabase.from('proveedores').select('*').order('nombre')
			setProviders(providerRows ?? [])
			setState((current) => ({
				...current,
				proveedorId: data,
				cuentaTipoId: '',
				cuentaNombre: '',
				cuentaValor: '',
			}))
			setCustomProviderName('')
			setShowCustomProvider(false)
		}

		setCreatingProvider(false)
	}

	const nextStep = () => {
		const error = validateStep(step, state, providerIdentifiers, selectedMembers)
		if (error) return setMessage(error)
		setMessage(null)
		setStep((current) => Math.min(4, current + 1))
	}

	const previousStep = () => {
		setMessage(null)
		setStep((current) => Math.max(1, current - 1))
	}

	const save = async () => {
		if (!familia) return
		const error = validateAll(state, providerIdentifiers, selectedMembers)
		if (error) return setMessage(error)

		setSaving(true)
		setMessage(null)

		const participants = members
			.filter((member) => state.participantes[member.id]?.selected)
			.map((member) => {
				const draft = state.participantes[member.id]
				return {
					miembro_id: member.id,
					modalidad: draft.modalidad,
					valor: draft.valor.trim() ? Number(draft.valor) : null,
				}
			})

		const account = state.cuentaValor.trim()
			? {
				tipo_identificador_id: state.cuentaTipoId || null,
				identificador_nombre: state.cuentaTipoId ? null : state.cuentaNombre.trim() || null,
				identificador_valor: state.cuentaValor.trim(),
				alias: state.cuentaAlias.trim() || null,
			}
			: null

		const args = {
			p_concepto_id: id ?? null,
			p_familia_id: familia.id,
			p_categoria_id: state.categoriaId,
			p_proveedor_id: state.proveedorId,
			p_plantilla_id: state.plantillaId,
			p_nombre: state.nombre.trim(),
			p_frecuencia: state.frecuencia,
			p_metodo_obtencion: state.metodo,
			p_monto_fijo: state.metodo === 'FIJO' ? Number(state.montoFijo) : null,
			p_tipo_vencimiento: state.tipoVencimiento,
			p_dia_vencimiento: state.tipoVencimiento === 'DIA_FIJO' ? Number(state.diaVencimiento) : null,
			p_tipo_distribucion: state.tipoDistribucion,
			p_reparto_resto: state.tipoDistribucion === 'MIXTA' ? state.repartoResto : null,
			p_fallback_manual: true,
			p_cuenta: account as Json,
			p_participantes: participants as Json,
		} as unknown as Database['public']['Functions']['guardar_concepto_servicio']['Args']

		const { error: saveError } = await supabase.rpc('guardar_concepto_servicio', args)

		if (saveError) {
			setMessage(saveError.message)
			setSaving(false)
			return
		}

		navigate('/servicios', { replace: true })
	}

	if (loading) {
		return <div className="space-y-4"><div className="h-10 w-64 animate-pulse rounded-xl bg-white" /><div className="h-96 animate-pulse rounded-3xl bg-white" /></div>
	}

	return (
		<div className="mx-auto max-w-5xl">
			<div className="flex items-start gap-4">
				<Link to="/servicios" className="mt-1 grid size-10 shrink-0 place-items-center rounded-xl border border-slate-200 bg-white text-slate-500"><ArrowLeft size={17} /></Link>
				<div>
					<p className="text-sm font-semibold text-[#0f766e]">Servicios</p>
					<h1 className="mt-1 text-3xl font-semibold tracking-tight">{editing ? 'Editar servicio' : 'Nuevo servicio'}</h1>
					<p className="mt-2 text-sm leading-6 text-slate-500">FamiliaHub utilizará esta plantilla para crear recibos y cuotas sin volver a preguntarte lo mismo cada mes.</p>
				</div>
			</div>

			<StepBar current={step} />

			<section className="mt-6 rounded-3xl border border-slate-200 bg-white p-5 sm:p-7">
				{step === 1 && (
					<div>
						<SectionTitle title="1. ¿Qué servicio quieres organizar?" subtitle="Usa una plantilla para que FamiliaHub complete lo repetitivo por ti." />
						<div className="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
							{templates.map((template) => (
								<button key={template.id} type="button" onClick={() => chooseTemplate(template)} className={`rounded-2xl border p-4 text-left transition ${state.plantillaId === template.id ? 'border-[#0f766e] bg-emerald-50 ring-2 ring-emerald-100' : 'border-slate-200 hover:border-slate-300'}`}>
									<div className="text-[#0f766e]"><ServicioIcon tipo={template.tipo_servicio} /></div>
									<p className="mt-4 text-sm font-semibold">{template.nombre}</p>
									<p className="mt-1 text-xs text-slate-400">{template.descripcion}</p>
								</button>
							))}
							<button type="button" onClick={() => chooseTemplate(null)} className={`rounded-2xl border p-4 text-left transition ${state.plantillaId === null && state.tipoServicio === 'OTRO' ? 'border-[#0f766e] bg-emerald-50 ring-2 ring-emerald-100' : 'border-slate-200 hover:border-slate-300'}`}>
								<div className="text-[#0f766e]"><CirclePlus size={20} /></div>
								<p className="mt-4 text-sm font-semibold">Otro</p>
								<p className="mt-1 text-xs text-slate-400">Configura un servicio personalizado.</p>
							</button>
						</div>

						<div className="mt-7 grid gap-5 md:grid-cols-2">
							<label className="block"><span className="fh-label">Nombre del servicio</span><input className="fh-input" value={state.nombre} onChange={(e) => setState({ ...state, nombre: e.target.value })} placeholder="Ej. Agua" /></label>
							<label className="block"><span className="fh-label">Categoría</span><select className="fh-input" value={state.categoriaId} onChange={(e) => setState({ ...state, categoriaId: e.target.value })}><option value="">Selecciona una categoría</option>{categories.map((category) => <option key={category.id} value={category.id}>{category.nombre}</option>)}</select></label>
							{state.plantillaId === null && (
								<label className="block md:col-span-2"><span className="fh-label">Tipo de servicio</span><select className="fh-input" value={state.tipoServicio} onChange={(e) => setState({ ...state, tipoServicio: e.target.value as TipoServicio, proveedorId: '', cuentaTipoId: '', cuentaValor: '', cuentaNombre: '' })}>{(['AGUA','LUZ','INTERNET','GAS','OTRO'] as TipoServicio[]).map((type) => <option key={type} value={type}>{tipoServicioLabel[type]}</option>)}</select></label>
							)}
						</div>
					</div>
				)}

				{step === 2 && (
					<div>
						<SectionTitle title="2. Proveedor, monto y vencimiento" subtitle="Aquí defines de dónde saldrá el monto y qué dato identifica tu cuenta." />

						<div className="mt-6 grid gap-5 md:grid-cols-2">
							<label className="block">
								<span className="fh-label">Proveedor</span>
								<select className="fh-input" value={state.proveedorId} onChange={(e) => changeProvider(e.target.value)}>
									<option value="">Selecciona un proveedor</option>
									{activeProviders.map((item) => <option key={item.id} value={item.id}>{item.nombre}{item.es_sistema ? '' : ' · Personalizado'}</option>)}
								</select>
							</label>

							<div className="flex items-end">
								<button type="button" className="fh-button-secondary flex w-full items-center gap-2" onClick={() => setShowCustomProvider((value) => !value)}><Building2 size={16} />{showCustomProvider ? 'Cancelar' : 'Agregar proveedor personalizado'}</button>
							</div>
						</div>

						{showCustomProvider && (
							<form className="mt-4 flex flex-col gap-3 rounded-2xl border border-dashed border-slate-300 bg-slate-50 p-4 sm:flex-row" onSubmit={createCustomProvider}>
								<input className="fh-input flex-1" value={customProviderName} onChange={(e) => setCustomProviderName(e.target.value)} placeholder={`Proveedor de ${tipoServicioLabel[state.tipoServicio]}`} required />
								<button className="fh-button-primary shrink-0" disabled={creatingProvider}>{creatingProvider ? 'Creando...' : 'Crear proveedor'}</button>
							</form>
						)}

						{provider && state.metodo === 'AUTOMATICO' && (
							<div className={`mt-5 flex gap-3 rounded-2xl border p-4 text-sm ${provider.estado_integracion === 'DISPONIBLE' ? 'border-emerald-100 bg-emerald-50 text-emerald-800' : 'border-amber-100 bg-amber-50 text-amber-800'}`}>
								<CircleAlert size={18} className="mt-0.5 shrink-0" />
								<div><p className="font-semibold">{integrationLabel(provider.estado_integracion)}</p><p className="mt-1 text-xs leading-5">{provider.estado_integracion === 'DISPONIBLE' ? 'FamiliaHub podrá utilizar la integración configurada para este proveedor.' : 'La cuenta quedará preparada para automatización. Hasta que exista un adaptador autorizado, FamiliaHub utilizará el respaldo manual sin bloquear el servicio.'}</p></div>
							</div>
						)}

						<div className="mt-7 grid gap-5 md:grid-cols-3">
							<label className="block"><span className="fh-label">Frecuencia</span><select className="fh-input" value={state.frecuencia} onChange={(e) => setState({ ...state, frecuencia: e.target.value as Frecuencia })}><option value="MENSUAL">Mensual</option><option value="ANUAL">Anual</option><option value="UNICA">Única</option></select></label>
							<label className="block"><span className="fh-label">Cómo obtener el monto</span><select className="fh-input" value={state.metodo} onChange={(e) => changeMethod(e.target.value as MetodoObtencion)}><option value="AUTOMATICO">Automático</option><option value="FIJO">Fijo</option><option value="MANUAL">Manual</option></select></label>
							{state.metodo === 'FIJO' && <label className="block"><span className="fh-label">Monto fijo (S/)</span><input className="fh-input" type="number" min="0.01" step="0.01" value={state.montoFijo} onChange={(e) => setState({ ...state, montoFijo: e.target.value, participantes: normalizeParticipantValues(state.participantes, state.tipoDistribucion, state.repartoResto, e.target.value) })} placeholder="0.00" /></label>}
						</div>

						<div className="mt-5 grid gap-5 md:grid-cols-2">
							<label className="block"><span className="fh-label">Vencimiento</span><select className="fh-input" value={state.tipoVencimiento} onChange={(e) => setState({ ...state, tipoVencimiento: e.target.value as TipoVencimiento, diaVencimiento: '' })}><option value="PROVEEDOR">Desde proveedor</option><option value="DIA_FIJO">Día fijo</option><option value="VARIABLE">Variable</option></select></label>
							{state.tipoVencimiento === 'DIA_FIJO' && <label className="block"><span className="fh-label">Día del mes</span><input className="fh-input" type="number" min="1" max="31" value={state.diaVencimiento} onChange={(e) => setState({ ...state, diaVencimiento: e.target.value })} placeholder="15" /></label>}
						</div>

						<div className="mt-7 border-t border-slate-100 pt-6">
							<h3 className="text-sm font-semibold">Cuenta de servicio</h3>
							<p className="mt-1 text-xs text-slate-400">{state.metodo === 'AUTOMATICO' ? 'Obligatoria para automatización.' : 'Opcional en servicios manuales o de monto fijo.'}</p>

							<div className="mt-4 grid gap-5 md:grid-cols-2">
								{providerIdentifiers.length > 0 ? (
									<label className="block"><span className="fh-label">Tipo de identificador</span><select className="fh-input" value={state.cuentaTipoId} onChange={(e) => setState({ ...state, cuentaTipoId: e.target.value, cuentaNombre: '' })}><option value="">Selecciona</option>{providerIdentifiers.map((identifier) => <option key={identifier.id} value={identifier.id}>{identifier.nombre}</option>)}</select></label>
								) : (
									<label className="block"><span className="fh-label">Nombre del identificador</span><input className="fh-input" value={state.cuentaNombre} onChange={(e) => setState({ ...state, cuentaNombre: e.target.value })} placeholder="Ej. Código de cliente" /></label>
								)}
								<label className="block"><span className="fh-label">Identificador</span><input className="fh-input" value={state.cuentaValor} onChange={(e) => setState({ ...state, cuentaValor: e.target.value })} placeholder="Número de suministro, cliente o contrato" /></label>
								<label className="block md:col-span-2"><span className="fh-label">Alias de la cuenta</span><input className="fh-input" value={state.cuentaAlias} onChange={(e) => setState({ ...state, cuentaAlias: e.target.value })} placeholder="Ej. Agua de casa · opcional" /></label>
							</div>

							{providerIdentifiers.find((item) => item.id === state.cuentaTipoId)?.ayuda && <p className="mt-3 flex items-center gap-2 text-xs text-slate-400"><Info size={14} />{providerIdentifiers.find((item) => item.id === state.cuentaTipoId)?.ayuda}</p>}
						</div>
					</div>
				)}

				{step === 3 && (
					<div>
						<SectionTitle title="3. Integrantes y división" subtitle="Selecciona solo a quienes realmente les corresponde este servicio." />

						<div className="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
							{(['IGUAL','PORCENTAJE','MONTO_FIJO','MIXTA'] as TipoDistribucion[]).map((distribution) => (
								<button key={distribution} type="button" disabled={distribution === 'MONTO_FIJO' && state.metodo !== 'FIJO'} onClick={() => changeDistribution(distribution)} className={`rounded-2xl border p-4 text-left transition disabled:cursor-not-allowed disabled:opacity-40 ${state.tipoDistribucion === distribution ? 'border-[#0f766e] bg-emerald-50 ring-2 ring-emerald-100' : 'border-slate-200'}`}>
									<p className="text-sm font-semibold">{distribucionLabel[distribution]}</p>
									<p className="mt-1 text-xs leading-5 text-slate-400">{distributionDescription(distribution)}</p>
								</button>
							))}
						</div>

						{state.tipoDistribucion === 'MIXTA' && (
							<div className="mt-5 rounded-2xl bg-slate-50 p-4">
								<p className="text-xs font-semibold text-slate-500">¿Cómo se divide el saldo después de los montos fijos?</p>
								<div className="mt-3 flex gap-2">
									<button type="button" onClick={() => changeRemainderMode('IGUAL')} className={`rounded-xl px-4 py-2 text-xs font-semibold ${state.repartoResto === 'IGUAL' ? 'bg-[#0f766e] text-white' : 'bg-white text-slate-500'}`}>Igual</button>
									<button type="button" onClick={() => changeRemainderMode('PORCENTAJE')} className={`rounded-xl px-4 py-2 text-xs font-semibold ${state.repartoResto === 'PORCENTAJE' ? 'bg-[#0f766e] text-white' : 'bg-white text-slate-500'}`}>Porcentaje</button>
								</div>
							</div>
						)}

						<div className="mt-6 space-y-3">
							{members.map((member) => {
								const draft = state.participantes[member.id] ?? { selected: false, modalidad: 'IGUAL' as ModalidadParticipante, valor: '' }
								return (
									<div key={member.id} className={`rounded-2xl border p-4 transition ${draft.selected ? 'border-emerald-200 bg-emerald-50/40' : 'border-slate-200'}`}>
										<div className="flex items-center gap-3">
											<input type="checkbox" checked={draft.selected} onChange={() => toggleParticipant(member.id)} className="size-4 accent-[#0f766e]" />
											<div className="min-w-0 flex-1"><p className="truncate text-sm font-semibold">{member.nombre}</p><p className="text-xs text-slate-400">{draft.selected ? 'Participa en este servicio' : 'No participa'}</p></div>
										</div>

										{draft.selected && (
											<div className="mt-4 pl-7">
												{state.tipoDistribucion === 'IGUAL' && <p className="text-xs text-slate-500">FamiliaHub dividirá el total en partes iguales.</p>}
												{state.tipoDistribucion === 'PORCENTAJE' && <ValueInput label="Porcentaje" suffix="%" value={draft.valor} onChange={(value) => updateParticipantValue(member.id, value)} step="0.0001" />}
												{state.tipoDistribucion === 'MONTO_FIJO' && <ValueInput label="Monto" prefix="S/" value={draft.valor} onChange={(value) => updateParticipantValue(member.id, value)} step="0.01" />}
												{state.tipoDistribucion === 'MIXTA' && (
													<div className="grid gap-3 sm:grid-cols-[180px_1fr]">
														<select className="fh-input" value={draft.modalidad === 'MONTO_FIJO' ? 'FIJO' : 'RESTO'} onChange={(e) => changeMixedRole(member.id, e.target.value === 'FIJO')}><option value="FIJO">Monto fijo</option><option value="RESTO">Saldo restante</option></select>
														{draft.modalidad === 'MONTO_FIJO' && <ValueInput label="Monto fijo" prefix="S/" value={draft.valor} onChange={(value) => updateParticipantValue(member.id, value)} step="0.01" compact />}
														{draft.modalidad === 'RESTO_PORCENTAJE' && <ValueInput label="% del saldo" suffix="%" value={draft.valor} onChange={(value) => updateParticipantValue(member.id, value)} step="0.0001" compact />}
														{draft.modalidad === 'RESTO_IGUAL' && <p className="self-center text-xs text-slate-500">Recibirá una parte igual del saldo restante.</p>}
													</div>
												)}
											</div>
										)}
									</div>
								)
							})}
						</div>

						<DistributionSummary state={state} selected={selectedMembers.length} />
					</div>
				)}

				{step === 4 && (
					<div>
						<SectionTitle title="4. Revisa la configuración" subtitle="Esto es lo que FamiliaHub reutilizará cuando empiece un nuevo periodo." />
						<div className="mt-6 grid gap-4 md:grid-cols-2">
							<Review label="Servicio" value={state.nombre} />
							<Review label="Proveedor" value={provider?.nombre ?? 'Sin proveedor'} />
							<Review label="Frecuencia" value={frecuenciaLabel[state.frecuencia]} />
							<Review label="Monto" value={state.metodo === 'FIJO' ? `S/ ${Number(state.montoFijo || 0).toFixed(2)}` : metodoLabel[state.metodo]} />
							<Review label="Vencimiento" value={state.tipoVencimiento === 'DIA_FIJO' ? `Día ${state.diaVencimiento}` : vencimientoLabel[state.tipoVencimiento]} />
							<Review label="División" value={distribucionLabel[state.tipoDistribucion]} />
							<Review label="Participantes" value={selectedMembers.map((member) => member.nombre).join(', ')} wide />
							<Review label="Cuenta" value={state.cuentaValor ? `${state.cuentaAlias || state.cuentaNombre || providerIdentifiers.find((item) => item.id === state.cuentaTipoId)?.nombre || 'Cuenta'} · ${state.cuentaValor}` : 'No configurada'} wide />
						</div>

						{state.metodo === 'AUTOMATICO' && provider?.estado_integracion !== 'DISPONIBLE' && (
							<div className="mt-5 flex gap-3 rounded-2xl border border-amber-100 bg-amber-50 p-4 text-amber-800">
								<CircleAlert size={18} className="mt-0.5 shrink-0" />
								<div><p className="text-sm font-semibold">Automatización preparada, no activa todavía</p><p className="mt-1 text-xs leading-5">El servicio conservará la cuenta y el modo automático, pero utilizará registro manual hasta que implementemos una integración autorizada para {provider?.nombre}.</p></div>
							</div>
						)}
					</div>
				)}
			</section>

			{message && <p className="fh-alert mt-4">{message}</p>}

			<div className="mt-5 flex items-center justify-between gap-3">
				<button type="button" onClick={previousStep} disabled={step === 1 || saving} className="fh-button-secondary flex items-center gap-2 disabled:opacity-40"><ArrowLeft size={16} />Anterior</button>
				{step < 4 ? (
					<button type="button" onClick={nextStep} className="fh-button-primary flex items-center gap-2">Continuar<ArrowRight size={16} /></button>
				) : (
					<button type="button" onClick={() => void save()} disabled={saving} className="fh-button-primary flex items-center gap-2"><Check size={16} />{saving ? 'Guardando...' : editing ? 'Guardar cambios' : 'Crear servicio'}</button>
				)}
			</div>
		</div>
	)
}

function StepBar({ current }: { current: number }) {
	const labels = ['Servicio', 'Proveedor', 'División', 'Revisión']
	return (
		<div className="mt-8 grid grid-cols-4 gap-2">
			{labels.map((label, index) => {
				const number = index + 1
				const active = number <= current
				return <div key={label}><div className={`h-1.5 rounded-full ${active ? 'bg-[#0f766e]' : 'bg-slate-200'}`} /><p className={`mt-2 hidden text-[10px] font-semibold sm:block ${number === current ? 'text-[#0f766e]' : 'text-slate-400'}`}>{number}. {label}</p></div>
			})}
		</div>
	)
}

function SectionTitle({ title, subtitle }: { title: string; subtitle: string }) {
	return <div><h2 className="text-xl font-semibold">{title}</h2><p className="mt-2 text-sm leading-6 text-slate-500">{subtitle}</p></div>
}

function ValueInput({ label, value, onChange, prefix, suffix, step, compact = false }: { label: string; value: string; onChange: (value: string) => void; prefix?: string; suffix?: string; step: string; compact?: boolean }) {
	return <label className={compact ? 'block' : 'block max-w-xs'}><span className="mb-1 block text-xs font-medium text-slate-500">{label}</span><div className="relative">{prefix && <span className="absolute left-3 top-1/2 -translate-y-1/2 text-xs text-slate-400">{prefix}</span>}<input className={`fh-input ${prefix ? 'pl-9' : ''} ${suffix ? 'pr-9' : ''}`} type="number" min="0" step={step} value={value} onChange={(e) => onChange(e.target.value)} />{suffix && <span className="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-slate-400">{suffix}</span>}</div></label>
}

function Review({ label, value, wide = false }: { label: string; value: string; wide?: boolean }) {
	return <div className={`rounded-2xl bg-slate-50 p-4 ${wide ? 'md:col-span-2' : ''}`}><p className="text-[10px] font-semibold uppercase tracking-wide text-slate-400">{label}</p><p className="mt-1 text-sm font-semibold text-slate-700">{value || '—'}</p></div>
}

function DistributionSummary({ state, selected }: { state: FormState; selected: number }) {
	const rows = Object.values(state.participantes).filter((item) => item.selected)
	const total = rows.reduce((sum, item) => sum + (Number(item.valor) || 0), 0)
	let text = `${selected} participante${selected === 1 ? '' : 's'}`
	if (state.tipoDistribucion === 'PORCENTAJE') text += ` · ${total.toFixed(2)}% asignado`
	if (state.tipoDistribucion === 'MONTO_FIJO') text += ` · S/ ${total.toFixed(2)} asignado`
	if (state.tipoDistribucion === 'MIXTA') {
		const fixed = rows.filter((item) => item.modalidad === 'MONTO_FIJO').reduce((sum, item) => sum + (Number(item.valor) || 0), 0)
		const rest = rows.filter((item) => item.modalidad !== 'MONTO_FIJO').length
		text += ` · S/ ${fixed.toFixed(2)} fijo · ${rest} en saldo restante`
	}
	return <div className="mt-5 flex items-center gap-2 rounded-2xl bg-slate-50 p-4 text-xs font-medium text-slate-600"><UsersRound size={15} className="text-[#0f766e]" />{text}</div>
}

function validateStep(step: number, state: FormState, identifiers: Identificador[], selectedMembers: MemberView[]) {
	if (step === 1) {
		if (!state.nombre.trim()) return 'Escribe un nombre para el servicio.'
		if (!state.categoriaId) return 'Selecciona una categoría.'
	}

	if (step === 2) {
		if (!state.proveedorId) return 'Selecciona o crea un proveedor.'
		if (state.metodo === 'FIJO') {
			const amount = Number(state.montoFijo)
			if (!Number.isFinite(amount) || amount <= 0 || !twoDecimals(amount)) return 'El monto fijo debe ser mayor a cero y tener máximo dos decimales.'
		}
		if (state.tipoVencimiento === 'DIA_FIJO') {
			const day = Number(state.diaVencimiento)
			if (!Number.isInteger(day) || day < 1 || day > 31) return 'El día de vencimiento debe estar entre 1 y 31.'
		}
		if (state.metodo === 'AUTOMATICO' && !state.cuentaValor.trim()) return 'Un servicio automático necesita el identificador de la cuenta.'
		if (state.cuentaValor.trim() && !state.cuentaTipoId && !state.cuentaNombre.trim()) return 'Indica qué representa el identificador de la cuenta.'
		if (identifiers.length > 0 && state.cuentaValor.trim() && !state.cuentaTipoId) return 'Selecciona el tipo de identificador del proveedor.'
	}

	if (step === 3) return validateDistribution(state, selectedMembers)
	return null
}

function validateAll(state: FormState, identifiers: Identificador[], selectedMembers: MemberView[]) {
	return validateStep(1, state, identifiers, selectedMembers)
		?? validateStep(2, state, identifiers, selectedMembers)
		?? validateStep(3, state, identifiers, selectedMembers)
}

function validateDistribution(state: FormState, selectedMembers: MemberView[]) {
	if (!selectedMembers.length) return 'Selecciona al menos un integrante.'
	const rows = selectedMembers.map((member) => state.participantes[member.id])

	if (state.tipoDistribucion === 'IGUAL') return null

	if (state.tipoDistribucion === 'PORCENTAJE') {
		if (rows.some((row) => !positive(row.valor))) return 'Todos los participantes deben tener un porcentaje mayor a cero.'
		const sum = rows.reduce((total, row) => total + Number(row.valor), 0)
		if (Math.abs(sum - 100) > 0.0001) return 'Los porcentajes deben sumar exactamente 100%.'
		return null
	}

	if (state.tipoDistribucion === 'MONTO_FIJO') {
		if (state.metodo !== 'FIJO') return 'La división por monto fijo requiere un servicio de monto fijo.'
		if (rows.some((row) => !positiveMoney(row.valor))) return 'Todos los montos deben ser mayores a cero y tener máximo dos decimales.'
		const sum = rows.reduce((total, row) => total + Number(row.valor), 0)
		if (Math.abs(sum - Number(state.montoFijo)) > 0.005) return 'La suma asignada debe coincidir con el monto fijo del servicio.'
		return null
	}

	const fixed = rows.filter((row) => row.modalidad === 'MONTO_FIJO')
	const remainder = rows.filter((row) => row.modalidad !== 'MONTO_FIJO')
	if (!fixed.length || !remainder.length) return 'La división mixta necesita al menos un monto fijo y una persona para el saldo restante.'
	if (fixed.some((row) => !positiveMoney(row.valor))) return 'Los montos fijos deben ser mayores a cero y tener máximo dos decimales.'

	if (state.repartoResto === 'PORCENTAJE') {
		if (remainder.some((row) => !positive(row.valor))) return 'Cada participante del saldo debe tener un porcentaje mayor a cero.'
		const sum = remainder.reduce((total, row) => total + Number(row.valor), 0)
		if (Math.abs(sum - 100) > 0.0001) return 'Los porcentajes del saldo restante deben sumar exactamente 100%.'
	}

	if (state.metodo === 'FIJO') {
		const fixedSum = fixed.reduce((total, row) => total + Number(row.valor), 0)
		if (fixedSum >= Number(state.montoFijo)) return 'Debe quedar un saldo positivo para repartir entre los demás integrantes.'
	}

	return null
}

function remapParticipants(participants: Record<string, ParticipantDraft>, distribution: TipoDistribucion, rest: RepartoResto | null, fixedAmount: string) {
	const next = structuredClone(participants)
	const selectedIds = Object.entries(next).filter(([, item]) => item.selected).map(([id]) => id)

	for (const [index, id] of selectedIds.entries()) {
		if (distribution === 'IGUAL') next[id] = { ...next[id], modalidad: 'IGUAL', valor: '' }
		if (distribution === 'PORCENTAJE') next[id] = { ...next[id], modalidad: 'PORCENTAJE', valor: '' }
		if (distribution === 'MONTO_FIJO') next[id] = { ...next[id], modalidad: 'MONTO_FIJO', valor: '' }
		if (distribution === 'MIXTA') next[id] = { ...next[id], modalidad: index === 0 ? 'MONTO_FIJO' : rest === 'PORCENTAJE' ? 'RESTO_PORCENTAJE' : 'RESTO_IGUAL', valor: '' }
	}

	return normalizeParticipantValues(next, distribution, rest, fixedAmount)
}

function remapMixedRemainder(participants: Record<string, ParticipantDraft>, rest: RepartoResto) {
	const next = structuredClone(participants)
	for (const participant of Object.values(next)) {
		if (!participant.selected || participant.modalidad === 'MONTO_FIJO') continue
		participant.modalidad = rest === 'PORCENTAJE' ? 'RESTO_PORCENTAJE' : 'RESTO_IGUAL'
		participant.valor = ''
	}
	return normalizeParticipantValues(next, 'MIXTA', rest, '')
}

function normalizeParticipantValues(participants: Record<string, ParticipantDraft>, distribution: TipoDistribucion, rest: RepartoResto | null, fixedAmount: string) {
	const next = structuredClone(participants)
	const selected = Object.entries(next).filter(([, item]) => item.selected)

	if (distribution === 'PORCENTAJE') {
		const shares = equalPercentages(selected.length)
		selected.forEach(([id], index) => { next[id].modalidad = 'PORCENTAJE'; next[id].valor = shares[index] ?? '' })
	}

	if (distribution === 'MONTO_FIJO' && positiveMoney(fixedAmount)) {
		const shares = equalMoney(Number(fixedAmount), selected.length)
		selected.forEach(([id], index) => { next[id].modalidad = 'MONTO_FIJO'; next[id].valor = shares[index] ?? '' })
	}

	if (distribution === 'MIXTA' && rest === 'PORCENTAJE') {
		const remainder = selected.filter(([, item]) => item.modalidad !== 'MONTO_FIJO')
		const shares = equalPercentages(remainder.length)
		remainder.forEach(([id], index) => { next[id].modalidad = 'RESTO_PORCENTAJE'; next[id].valor = shares[index] ?? '' })
	}

	if (distribution === 'MIXTA' && rest === 'IGUAL') {
		selected.filter(([, item]) => item.modalidad !== 'MONTO_FIJO').forEach(([id]) => { next[id].modalidad = 'RESTO_IGUAL'; next[id].valor = '' })
	}

	return next
}

function equalPercentages(count: number) {
	if (!count) return []
	const base = Math.floor((100 / count) * 10000) / 10000
	const values = Array.from({ length: count }, () => base)
	values[count - 1] = Number((100 - base * (count - 1)).toFixed(4))
	return values.map((value) => String(value))
}

function equalMoney(total: number, count: number) {
	if (!count) return []
	const cents = Math.round(total * 100)
	const base = Math.floor(cents / count)
	const values = Array.from({ length: count }, () => base)
	values[count - 1] = cents - base * (count - 1)
	return values.map((value) => (value / 100).toFixed(2))
}

function positive(value: string) {
	const number = Number(value)
	return Number.isFinite(number) && number > 0
}

function positiveMoney(value: string) {
	const number = Number(value)
	return Number.isFinite(number) && number > 0 && twoDecimals(number)
}

function twoDecimals(value: number) {
	return Math.abs(value * 100 - Math.round(value * 100)) < 0.000001
}

function distributionDescription(value: TipoDistribucion) {
	if (value === 'IGUAL') return 'Todos pagan partes iguales.'
	if (value === 'PORCENTAJE') return 'Cada integrante tiene un porcentaje.'
	if (value === 'MONTO_FIJO') return 'Cada integrante tiene un monto exacto.'
	return 'Montos fijos y reparto del saldo restante.'
}
