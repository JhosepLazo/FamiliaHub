import { ImageUp, Plus } from 'lucide-react'
import { FormEvent, useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import type { Enums, Tables } from '../../types/database'
import { useFamilia } from './FamiliaContext'

type Category = Tables<'categorias'>
type PaymentConfig = Tables<'configuracion_pago_familiar'>

export default function FamiliaSettingsPage() {
	const { familia, refresh: refreshFamilia } = useFamilia()
	const [familyName, setFamilyName] = useState(familia?.nombre ?? '')
	const [categories, setCategories] = useState<Category[]>([])
	const [newCategory, setNewCategory] = useState('')
	const [config, setConfig] = useState<PaymentConfig | null>(null)
	const [metodo, setMetodo] = useState<Enums<'metodo_pago_familiar'>>('YAPE')
	const [titular, setTitular] = useState('')
	const [referencia, setReferencia] = useState('')
	const [instrucciones, setInstrucciones] = useState('')
	const [qrFile, setQrFile] = useState<File | null>(null)
	const [qrPreview, setQrPreview] = useState<string | null>(null)
	const [message, setMessage] = useState<string | null>(null)
	const [saving, setSaving] = useState(false)

	useEffect(() => {
		if (!familia) return
		setFamilyName(familia.nombre)
		void load()
	}, [familia?.id])

	const load = async () => {
		if (!familia) return

		const [{ data: cats }, { data: payment }] = await Promise.all([
			supabase.from('categorias').select('*').eq('familia_id', familia.id).order('created_at'),
			supabase.from('configuracion_pago_familiar').select('*').eq('familia_id', familia.id).maybeSingle(),
		])

		setCategories(cats ?? [])
		setConfig(payment ?? null)

		if (payment) {
			setMetodo(payment.metodo)
			setTitular(payment.titular)
			setReferencia(payment.referencia)
			setInstrucciones(payment.instrucciones ?? '')

			if (payment.qr_storage_path) {
				const { data } = await supabase.storage.from('familia-configuracion').download(payment.qr_storage_path)
				if (data) setQrPreview(URL.createObjectURL(data))
			}
		}
	}

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

		if (!familia || !titular.trim() || !referencia.trim()) {
			setMessage('Titular y referencia de pago son obligatorios.')
			return
		}

		setSaving(true)
		let qrPath = config?.qr_storage_path ?? null

		if (qrFile) {
			const extension = qrFile.name.split('.').pop()?.toLowerCase() || 'png'
			const nextPath = `${familia.id}/pagos/qr-${Date.now()}.${extension}`
			const { error: uploadError } = await supabase.storage.from('familia-configuracion').upload(nextPath, qrFile)

			if (uploadError) {
				setMessage('No pudimos subir el QR.')
				setSaving(false)
				return
			}

			if (qrPath) await supabase.storage.from('familia-configuracion').remove([qrPath])
			qrPath = nextPath
		}

		const values = {
			metodo,
			titular: titular.trim(),
			referencia: referencia.trim(),
			instrucciones: instrucciones.trim() || null,
			qr_storage_path: qrPath,
			updated_at: new Date().toISOString(),
		}

		const result = config
			? await supabase.from('configuracion_pago_familiar').update(values).eq('id', config.id)
			: await supabase.from('configuracion_pago_familiar').insert({ familia_id: familia.id, ...values })

		setMessage(result.error ? 'No pudimos guardar la cuenta receptora.' : 'Cuenta receptora actualizada.')
		setQrFile(null)
		await load()
		setSaving(false)
	}

	return (
		<div>
			<p className="text-sm font-semibold text-[#0f766e]">Configuración</p>
			<h1 className="mt-1 text-3xl font-semibold tracking-tight">Familia y pagos</h1>
			<p className="mt-2 max-w-2xl text-sm leading-6 text-slate-500">Configura únicamente datos familiares reutilizables. Los servicios y recibos se agregarán en la siguiente fase.</p>

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
				<h2 className="font-semibold">Cuenta receptora familiar</h2>
				<p className="mt-1 text-xs text-slate-400">Aquí llegarán las cuotas cuando usemos Yape, transferencia u otro método familiar.</p>

				<form className="mt-6 grid gap-5 lg:grid-cols-2" onSubmit={savePayment}>
					<label className="block"><span className="fh-label">Método</span><select className="fh-input" value={metodo} onChange={(e) => setMetodo(e.target.value as Enums<'metodo_pago_familiar'>)}><option value="YAPE">Yape</option><option value="TRANSFERENCIA">Transferencia</option><option value="EFECTIVO">Efectivo</option><option value="OTRO">Otro</option></select></label>
					<label className="block"><span className="fh-label">Titular</span><input className="fh-input" value={titular} onChange={(e) => setTitular(e.target.value)} required /></label>
					<label className="block"><span className="fh-label">Número / referencia</span><input className="fh-input" value={referencia} onChange={(e) => setReferencia(e.target.value)} required placeholder="Ej. 999 999 999" /></label>
					<label className="block"><span className="fh-label">Instrucciones</span><input className="fh-input" value={instrucciones} onChange={(e) => setInstrucciones(e.target.value)} placeholder="Opcional" /></label>

					<div className="lg:col-span-2">
						<span className="fh-label">QR de pago</span>
						<label className="flex cursor-pointer items-center gap-4 rounded-2xl border border-dashed border-slate-300 p-4 transition hover:border-[#0f766e]">
							{qrPreview ? <img src={qrPreview} alt="QR actual" className="size-20 rounded-xl object-cover" /> : <div className="grid size-20 place-items-center rounded-xl bg-slate-50 text-slate-400"><ImageUp /></div>}
							<div><p className="text-sm font-semibold">{qrFile ? qrFile.name : 'Seleccionar imagen QR'}</p><p className="mt-1 text-xs text-slate-400">PNG, JPG o WEBP · máximo 5 MB</p></div>
							<input className="hidden" type="file" accept="image/png,image/jpeg,image/webp" onChange={(e) => setQrFile(e.target.files?.[0] ?? null)} />
						</label>
					</div>

					<div className="lg:col-span-2"><button className="fh-button-primary" disabled={saving}>{saving ? 'Guardando...' : 'Guardar cuenta receptora'}</button></div>
				</form>
			</section>

			{message && <p className="fh-alert mt-5">{message}</p>}
		</div>
	)
}
