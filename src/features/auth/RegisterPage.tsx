import { FormEvent, useState } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import AuthLayout from '../../components/AuthLayout'
import { safeNext } from '../../lib/navigation'
import { supabase } from '../../lib/supabase'

export default function RegisterPage() {
	const [params] = useSearchParams()
	const navigate = useNavigate()
	const next = safeNext(params.get('next'), '/onboarding')
	const [nombre, setNombre] = useState('')
	const [email, setEmail] = useState('')
	const [password, setPassword] = useState('')
	const [loading, setLoading] = useState(false)
	const [message, setMessage] = useState<string | null>(null)

	const submit = async (event: FormEvent) => {
		event.preventDefault()
		if (password.length < 8) return setMessage('Usa una contraseña de al menos 8 caracteres.')

		setLoading(true)
		setMessage(null)

		const { data, error } = await supabase.auth.signUp({
			email: email.trim(),
			password,
			options: {
				data: { nombre: nombre.trim() },
				emailRedirectTo: window.location.origin,
			},
		})

		if (error) setMessage('No pudimos crear tu acceso. Revisa los datos e inténtalo nuevamente.')
		else if (data.session) navigate(next, { replace: true })
		else setMessage('Cuenta creada. Revisa tu correo para confirmar el acceso y luego vuelve a FamiliaHub.')

		setLoading(false)
	}

	return (
		<AuthLayout title="Crea tu acceso" subtitle="Tu cuenta es personal. Después podrás crear una familia o aceptar una invitación.">
			<form className="space-y-5" onSubmit={submit}>
				<label className="block"><span className="fh-label">Nombre</span><input className="fh-input" required value={nombre} onChange={(e) => setNombre(e.target.value)} placeholder="Tu nombre" /></label>
				<label className="block"><span className="fh-label">Correo</span><input className="fh-input" type="email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} placeholder="nombre@correo.com" /></label>
				<label className="block"><span className="fh-label">Contraseña</span><input className="fh-input" type="password" autoComplete="new-password" required value={password} onChange={(e) => setPassword(e.target.value)} placeholder="Mínimo 8 caracteres" /></label>
				<button className="fh-button-primary w-full" disabled={loading}>{loading ? 'Creando...' : 'Crear acceso'}</button>
			</form>

			{message && <p className="fh-alert mt-4">{message}</p>}
			<p className="mt-7 text-center text-sm text-slate-500">
				¿Ya tienes cuenta? <Link className="font-semibold text-[#0f766e]" to={`/login?next=${encodeURIComponent(next)}`}>Ingresar</Link>
			</p>
		</AuthLayout>
	)
}
