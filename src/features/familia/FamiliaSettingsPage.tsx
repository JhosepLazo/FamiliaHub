import { ImageUp, Plus, Power } from 'lucide-react'
import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '../../lib/supabase'
import type { Enums, Tables } from '../../types/database'
import { metodoPagoLabel, signedFileUrl } from '../pagos/pagoUi'
import WhatsappVinculo from '../whatsapp/WhatsappVinculo'
import { useFamilia } from './FamiliaContext'

type Category = Tables<'categorias'>
type PaymentConfig = Tables<'configuracion_pago_familiar'>
type Metodo = Enums<'metodo_pago_familiar'>

type MemberView = {
	id: string
	nombre: string
}

export default function FamiliaSettingsPage() {
	const { familia, refresh: refreshFamilia } = useFamilia()
	const [familyName, setFamilyName] = useState(familia?.nombre ?? '')
	const [categories, setCategories] = useState<Category[]>([])
	const [newCategory, setNewCategory] = useState('')
	const [configs, setConfigs] = useState<PaymentConfig[]>([])
	const [members, setMembers] = useState<MemberView[]>([])
	const [metodo, setMetodo] = useState<Metodo>('YAPE')
	const [titular, setTitular] = useState('')
	const [referencia, setReferencia] = useState('')
	const [instrucciones, setInstrucciones] = useState('')
	const [responsable, setResponsable] = useState('')
	const [qrFile, setQrFile] = useState<File | null>(null)
	const [qrPreview, setQrPreview] = useState<string | null>(null)
	const [message, setMessage] = useState<string | null>(null)
	const [saving, setSaving] = useState(false)

	const current = useMemo(() => configs.find((item) => item.metodo === metodo) ?? null, [configs, metodo])

	const load = useCallback(async () => {
		if (!familia) return

		const [{ data: cats }, { data: paymentRows }, { data: memberRows }] = await Promise.all([
			supabase.from('categorias').select('*').eq('familia_id', familia.id).order('created_at'),
			supabase.from('configuracion_pago_familiar').select('*').eq('familia_id', familia.id).order('created_at'),
			supabase.from('miembros_familia').select('id,usuario_id').eq('familia_id', familia.id).eq('estado', 'ACTIVO').order('joined_at'),
		])

		const userIds = (memberRows ?? []).map((row) => row.usuario_id)
		let profiles: { id: string; nombre: string | null }[] = []
		if (userIds.length) profiles = (await supabase.from('perfiles').select('id,nombre').in('id', userIds)).data ?? []
		const names = new Map(profiles.map((profile) => [profile.id, profile.nombre ?? 'Integrante']))

		setCategories(cats ?? [])
		setConfigs(paymentRows ?? [])
		setMembers((memberRows ?? []).map((row) => ({ id: row.id, nombre: names.get(row.usuario_id) ?? 'Integrante' })))
	}, [familia])

	useEffect(() => {
		if (!familia) return
		setFamilyName(familia.nombre)
		void load()
	}, [familia?.id, load])

	useEffect(() => {
		setTitular(current?.titular ?? '')
		setReferencia(current?.referencia ?? '')
		setInstrucciones(current?.instrucciones ?? '')
		setResponsable(current?.responsable_miembro_id ?? members[0]?.id ?? '')
		setQrFile(null)
		setQrPreview(null)
		if (current?.qr_storage_path) {
			void signedFileUrl('familia-configuracion', current.qr_storage_path).then(setQrPreview).catch(() => setQrPreview(null))
		}
	}, [current?.id, metodo, members])

	const saveFamily = async (event: FormEvent) => {
		event.preventDefault()
		if (!familia) return

		setSaving(true)
		const { error } = await supabase.from('familias').update({ nombre: familyName.trim(), updated_at: new Date().toISOString() }).eq('id', familia.id)
		setMessage(error ? 'No pudimos actualizar la familia.' : 'Datos de la familia actualizados.')
		if (!error) await refreshFamilia()
		setSaving(false)
	}

	const addCategory = async (event: FormEvent) => {
		event.preventDefault()
		if (!familia || !newCategory.trim()) return

		const { error } = await supabase.from('categorias').insert({ familia_id: familia.id, nombre: newCategory.trim() })
		setMessage(error ? 'No pudimos crear la categoría. Puede que ya exista.' : 'Categoría creada.')
		if (!error) setNewCategory('')
		await load()
	}

	const toggleCategory = async (category: Category) => {
		await supabase.from('categorias').update({ activo: !category.activo }).eq('id', category.id)
		await load()
	}

	const savePayment = async (event: FormEvent) => {
		event.preventDefault()
		if (!familia || !titular.trim() || !responsable) return
		setSaving(true)
		setMessage(null)

		let qrPath = current?.qr_storage_path ?? null
		if (qrFile) {
			const extension = qrFile.name.split('.').pop()?.toLowerCase() || 'png'
			const nextPath = `${familia.id}/metodos/${metodo.toLowerCase()}/qr-${Date.now()}.${extension}`
			const { error: uploadError } = await supabase.storage.from('familia-configuracion').upload(nextPath, qrFile)

			if (uploadError) {
				setMessage(uploadError.message)
				setSaving(false)
				return
			}
			qrPath = nextPath
		}

		const { error } = await supabase.rpc('guardar_metodo_cobro_familiar', {
			p_familia_id: familia.id,
			p_metodo: metodo,
			p_titular: titular.trim(),
			p_referencia: referencia.trim() || undefined,
			p_instrucciones: instrucciones.trim() || undefined,
			p_qr_storage_path: qrPath || undefined,
			p_responsable_miembro_id: responsable,
		})

		setMessage(error ? error.message : 'Método familiar actualizado.')
		if (!error) {
			if (qrFile && current?.qr_storage_path && current.qr_storage_path !== qrPath) {
				await supabase.storage.from('familia-configuracion').remove([current.qr_storage_path])
			}
			await load()
		}
		setSaving(false)
	}

	const togglePayment = async (config: PaymentConfig) => {
		const { error } = await supabase.rpc('cambiar_estado_metodo_cobro_familiar', {
			p_configuracion_id: config.id,
			p_activo: !config.activo,
		})
		setMessage(error ? error.message : config.activo ? 'Método desactivado.' : 'Método activado.')
		if (!error) await load()
	}

	return (
		<div>
			<p className="text-sm font-semibold text-[#0f766e]">Configuración</p>
			<h1 className="mt-1 text-3xl font-semibold tracking-tight">Familia y pagos</h1>
			<p className="mt-2 max-w-2xl text-sm leading-6 text-slate-500">Configura datos generales y las formas en que la familia recibe aportes. Cada método tiene un responsable real de validación.</p>

			<div className="mt-8 grid gap-6 xl:grid-cols-2">
				<section className="rounded-3xl border border-slate-200 bg-white p-6">
					<h2 className="font-semibold">Datos familiares</h2>
					<form className="mt-5" onSubmit={saveFamily}>
						<label className="block"><span className="fh-label">Nombre</span><input className="fh-input" value={familyName} onChange={(e) => setFamilyName(e.target.value)} required /></label>
						<div className="mt-4 grid gap-4 sm:grid-cols-2">
							<label><span className="fh-label">Moneda</span><input className="fh-input bg-slate-50 text-slate-500" value={familia?.moneda.trim() ?? 'PEN'} disabled /></label>
							<label><span className="fh-label">Zona horaria</span><input className="fh-input bg-slate-50 text-slate-500" value={familia?.zona_horaria ?? 'America/Lima'} disabled /></label>
						</div>
						<button className="fh-button-primary mt-5" disabled={saving}>Guardar</button>
					</form>
				</section>

				<section className="rounded-3xl border border-slate-200 bg-white p-6">
					<h2 className="font-semibold">Categorías</h2>
					<p className="mt-1 text-xs text-slate-400">Sirven para ordenar gastos; no determinan quién participa en una cuota.</p>
					<form className="mt-5 flex gap-2" onSubmit={addCategory}><input className="fh-input" value={newCategory} onChange={(e) => setNewCategory(e.target.value)} placeholder="Nueva categoría" /><button className="fh-button-secondary shrink-0"><Plus size={17} /></button></form>
					<div className="mt-5 flex flex-wrap gap-2">
						{categories.map((category) => (
							<button type="button" key={category.id} onClick={() => void toggleCategory(category)} className={`rounded-full border px-3 py-1.5 text-xs font-medium ${category.activo ? 'border-emerald-200 bg-emerald-50 text-[#0f766e]' : 'border-slate-200 bg-slate-50 text-slate-400'}`}>{category.nombre}</button>
						))}
					</div>
				</section>
			</div>

			<section className="mt-6 rounded-3xl border border-slate-200 bg-white p-6">
				<h2 className="font-semibold">Métodos de cobro familiares</h2>
				<p className="mt-1 text-xs leading-5 text-slate-400">Puedes tener Yape, transferencia, efectivo y otro método activos al mismo tiempo. El pagador elegirá uno disponible.</p>

				<div className="mt-5 flex flex-wrap gap-2">
					{(['YAPE','TRANSFERENCIA','EFECTIVO','OTRO'] as Metodo[]).map((value) => (
						<button key={value} type="button" onClick={() => setMetodo(value)} className={`rounded-xl px-4 py-2 text-xs font-semibold ${metodo === value ? 'bg-[#0f766e] text-white' : 'bg-slate-50 text-slate-500'}`}>{metodoPagoLabel[value]}</button>
					))}
				</div>

				<form className="mt-6 grid gap-5 lg:grid-cols-2" onSubmit={savePayment}>
					<label><span className="fh-label">Titular</span><input className="fh-input" value={titular} onChange={(e) => setTitular(e.target.value)} required /></label>
					<label><span className="fh-label">{metodo === 'YAPE' ? 'Celular' : metodo === 'TRANSFERENCIA' ? 'Cuenta / CCI' : 'Referencia'}</span><input className="fh-input" value={referencia} onChange={(e) => setReferencia(e.target.value)} required={metodo === 'TRANSFERENCIA'} /></label>
					<label><span className="fh-label">Responsable de validar</span><select className="fh-input" value={responsable} onChange={(e) => setResponsable(e.target.value)} required><option value="">Selecciona</option>{members.map((member) => <option key={member.id} value={member.id}>{member.nombre}</option>)}</select></label>
					<label><span className="fh-label">Instrucciones</span><input className="fh-input" value={instrucciones} onChange={(e) => setInstrucciones(e.target.value)} placeholder="Opcional" /></label>

					{metodo === 'YAPE' && (
						<label className="lg:col-span-2 flex cursor-pointer items-center gap-4 rounded-2xl border border-dashed border-slate-300 p-4">
							{qrPreview ? <img src={qrPreview} alt="QR familiar" className="size-20 rounded-xl object-cover" /> : <div className="grid size-20 place-items-center rounded-xl bg-slate-50 text-slate-400"><ImageUp /></div>}
							<div><p className="text-sm font-semibold">{qrFile ? qrFile.name : 'QR de Yape · opcional si indicas celular'}</p><p className="mt-1 text-xs text-slate-400">PNG, JPG o WEBP · máximo 5 MB</p></div>
							<input className="hidden" type="file" accept="image/png,image/jpeg,image/webp" onChange={(e) => setQrFile(e.target.files?.[0] ?? null)} />
						</label>
					)}

					<div className="lg:col-span-2 flex flex-wrap gap-3">
						<button className="fh-button-primary" disabled={saving}>{saving ? 'Guardando...' : 'Guardar método'}</button>
						{current && <button type="button" onClick={() => void togglePayment(current)} className="fh-button-secondary flex items-center gap-2"><Power size={15} />{current.activo ? 'Desactivar' : 'Activar'}</button>}
					</div>
				</form>

				{configs.length > 0 && (
					<div className="mt-6 grid gap-3 sm:grid-cols-2">
						{configs.map((config) => (
							<div key={config.id} className="rounded-2xl border border-slate-100 p-4">
								<div className="flex items-center justify-between gap-3"><div><p className="text-sm font-semibold">{metodoPagoLabel[config.metodo]}</p><p className="mt-1 text-xs text-slate-400">{config.titular} · {config.activo ? 'Activo' : 'Inactivo'}</p></div><button type="button" onClick={() => { setMetodo(config.metodo); }} className="text-xs font-semibold text-[#0f766e]">Editar</button></div>
							</div>
						))}
					</div>
				)}
			</section>

			<WhatsappVinculo tipo="GRUPO" />

			{message && <p className="fh-alert mt-5">{message}</p>}
		</div>
	)
}
