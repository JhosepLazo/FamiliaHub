import { ImageUp, Power } from 'lucide-react'
import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '../../lib/supabase'
import type { Enums, Tables } from '../../types/database'
import { useFamilia } from '../familia/FamiliaContext'
import { metodoPagoLabel, signedFileUrl } from './pagoUi'

type Config = Tables<'configuracion_cobro_miembro'>
type Metodo = Enums<'metodo_pago_familiar'>

export default function MetodosCobroPersonales() {
	const { familia, membresia } = useFamilia()
	const [configs, setConfigs] = useState<Config[]>([])
	const [metodo, setMetodo] = useState<Metodo>('YAPE')
	const [titular, setTitular] = useState('')
	const [referencia, setReferencia] = useState('')
	const [instrucciones, setInstrucciones] = useState('')
	const [qrFile, setQrFile] = useState<File | null>(null)
	const [qrPreview, setQrPreview] = useState<string | null>(null)
	const [saving, setSaving] = useState(false)
	const [message, setMessage] = useState<string | null>(null)

	const current = useMemo(() => configs.find((item) => item.metodo === metodo) ?? null, [configs, metodo])

	const load = useCallback(async () => {
		if (!membresia) return
		const { data } = await supabase
			.from('configuracion_cobro_miembro')
			.select('*')
			.eq('miembro_id', membresia.id)
			.order('created_at')
		setConfigs(data ?? [])
	}, [membresia])

	useEffect(() => { void load() }, [load])

	useEffect(() => {
		setTitular(current?.titular ?? '')
		setReferencia(current?.referencia ?? '')
		setInstrucciones(current?.instrucciones ?? '')
		setQrFile(null)
		setQrPreview(null)
		if (current?.qr_storage_path) {
			void signedFileUrl('familia-cobros', current.qr_storage_path).then(setQrPreview).catch(() => setQrPreview(null))
		}
	}, [current?.id, metodo])

	const save = async (event: FormEvent) => {
		event.preventDefault()
		if (!familia || !membresia || !titular.trim()) return
		setSaving(true)
		setMessage(null)

		let qrPath = current?.qr_storage_path ?? null
		if (qrFile) {
			const ext = qrFile.name.split('.').pop()?.toLowerCase() || 'png'
			const nextPath = `${familia.id}/miembros/${membresia.id}/qr-${metodo.toLowerCase()}-${Date.now()}.${ext}`
			const { error } = await supabase.storage.from('familia-cobros').upload(nextPath, qrFile)
			if (error) {
				setMessage(error.message)
				setSaving(false)
				return
			}
			qrPath = nextPath
		}

		const { error } = await supabase.rpc('guardar_metodo_cobro_personal', {
			p_familia_id: familia.id,
			p_metodo: metodo,
			p_titular: titular.trim(),
			p_referencia: referencia.trim() || undefined,
			p_instrucciones: instrucciones.trim() || undefined,
			p_qr_storage_path: qrPath || undefined,
		})

		setMessage(error ? error.message : 'Método de cobro actualizado.')
		if (!error) {
			if (qrFile && current?.qr_storage_path && current.qr_storage_path !== qrPath) {
				await supabase.storage.from('familia-cobros').remove([current.qr_storage_path])
			}
			await load()
		}
		setSaving(false)
	}

	const toggle = async (config: Config) => {
		const { error } = await supabase.rpc('cambiar_estado_metodo_cobro_personal', {
			p_configuracion_id: config.id,
			p_activo: !config.activo,
		})
		setMessage(error ? error.message : config.activo ? 'Método desactivado.' : 'Método activado.')
		if (!error) await load()
	}

	return (
		<section className="mt-6 rounded-3xl border border-slate-200 bg-white p-6 sm:p-8">
			<h2 className="font-semibold">Cómo recibir reembolsos</h2>
			<p className="mt-1 text-xs leading-5 text-slate-400">Configura tus propios datos de cobro. Solo se mostrarán cuando otro integrante realmente deba reembolsarte.</p>

			<div className="mt-5 flex flex-wrap gap-2">
				{(['YAPE','TRANSFERENCIA','EFECTIVO','OTRO'] as Metodo[]).map((value) => (
					<button key={value} type="button" onClick={() => setMetodo(value)} className={`rounded-xl px-4 py-2 text-xs font-semibold ${metodo === value ? 'bg-[#0f766e] text-white' : 'bg-slate-50 text-slate-500'}`}>{metodoPagoLabel[value]}</button>
				))}
			</div>

			<form onSubmit={save} className="mt-5 grid gap-4 sm:grid-cols-2">
				<label><span className="fh-label">Titular</span><input className="fh-input" required value={titular} onChange={(e) => setTitular(e.target.value)} /></label>
				<label><span className="fh-label">{metodo === 'YAPE' ? 'Celular' : metodo === 'TRANSFERENCIA' ? 'Cuenta / CCI' : 'Referencia'}</span><input className="fh-input" value={referencia} onChange={(e) => setReferencia(e.target.value)} required={metodo === 'TRANSFERENCIA'} placeholder={metodo === 'EFECTIVO' ? 'Opcional' : ''} /></label>
				<label className="sm:col-span-2"><span className="fh-label">Instrucciones</span><input className="fh-input" value={instrucciones} onChange={(e) => setInstrucciones(e.target.value)} placeholder="Opcional" /></label>
				{metodo === 'YAPE' && (
					<label className="sm:col-span-2 flex cursor-pointer items-center gap-4 rounded-2xl border border-dashed border-slate-300 p-4">
						{qrPreview ? <img src={qrPreview} alt="QR personal" className="size-20 rounded-xl object-cover" /> : <div className="grid size-20 place-items-center rounded-xl bg-slate-50 text-slate-400"><ImageUp /></div>}
						<div><p className="text-sm font-semibold">{qrFile ? qrFile.name : 'QR de Yape · opcional si indicas celular'}</p><p className="mt-1 text-xs text-slate-400">PNG, JPG o WEBP · máximo 5 MB</p></div>
						<input type="file" className="hidden" accept="image/png,image/jpeg,image/webp" onChange={(e) => setQrFile(e.target.files?.[0] ?? null)} />
					</label>
				)}
				<div className="sm:col-span-2 flex flex-wrap gap-3">
					<button className="fh-button-primary" disabled={saving}>{saving ? 'Guardando...' : 'Guardar método'}</button>
					{current && <button type="button" onClick={() => void toggle(current)} className="fh-button-secondary flex items-center gap-2"><Power size={15} />{current.activo ? 'Desactivar' : 'Activar'}</button>}
				</div>
			</form>

			{message && <p className="fh-alert mt-4">{message}</p>}
		</section>
	)
}
