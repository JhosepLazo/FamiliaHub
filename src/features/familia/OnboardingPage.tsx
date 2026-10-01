import { ArrowRight, UsersRound } from 'lucide-react'
import { FormEvent, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import Brand from '../../components/Brand'
import { supabase } from '../../lib/supabase'
import { useFamilia } from './FamiliaContext'

export default function OnboardingPage() {
	const navigate = useNavigate()
	const { refresh } = useFamilia()
	const [nombre, setNombre] = useState('')
	const [loading, setLoading] = useState(false)
	const [message, setMessage] = useState<string | null>(null)

	const submit = async (event: FormEvent) => {
		event.preventDefault()
		setLoading(true)
		setMessage(null)

		const { error } = await supabase.rpc('crear_familia_inicial', { p_nombre: nombre.trim() })

		if (error) setMessage(error.message || 'No pudimos crear la familia.')
		else {
			await refresh()
			navigate('/inicio', { replace: true })
		}

		setLoading(false)
	}

	return (
		<main className="min-h-screen bg-[#f4f6f2] px-5 py-10">
			<div className="mx-auto max-w-2xl">
				<Brand />

				<div className="mt-12 rounded-3xl border border-slate-200 bg-white p-6 shadow-sm sm:p-9">
					<div className="grid size-12 place-items-center rounded-2xl bg-emerald-50 text-[#0f766e]"><UsersRound size={23} /></div>
					<h1 className="mt-5 text-3xl font-semibold tracking-tight">Crea tu familia</h1>
					<p className="mt-3 max-w-xl text-sm leading-6 text-slate-500">Este será el espacio privado donde organizarán integrantes, servicios, cuotas y pagos. Solo tendrás que hacerlo una vez.</p>

					<form className="mt-8" onSubmit={submit}>
						<label className="block">
							<span className="fh-label">Nombre de la familia</span>
							<input className="fh-input" required maxLength={80} value={nombre} onChange={(e) => setNombre(e.target.value)} placeholder="Ej. Familia Silva Lazo" />
						</label>
						<p className="mt-3 text-xs leading-5 text-slate-400">FamiliaHub configurará automáticamente PEN, America/Lima, el periodo actual y categorías familiares iniciales.</p>
						<button className="fh-button-primary mt-6 flex w-full items-center justify-center gap-2" disabled={loading}>
							{loading ? 'Creando...' : 'Crear familia'}<ArrowRight size={17} />
						</button>
					</form>

					{message && <p className="fh-alert mt-4">{message}</p>}
				</div>
			</div>
		</main>
	)
}
