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
	const [usuario, setUsuario] = useState('')
	const [password, setPassword] = useState('')
	const [confirmPassword, setConfirmPassword] = useState('')
	const [loading, setLoading] = useState(false)
	const [message, setMessage] = useState<string | null>(null)

	const submit = async (event: FormEvent) => {
		event.preventDefault()
		if (!/^[A-Za-z][A-Za-z0-9._-]{2,29}$/.test(usuario.trim())) return setMessage('El usuario debe tener entre 3 y 30 caracteres y usar solo letras, números, punto, guion o guion bajo.')
		if (password.length < 8) return setMessage('Usa una contraseña de al menos 8 caracteres.')
		if (password !== confirmPassword) return setMessage('Las contraseñas no coinciden.')

		setLoading(true)
		setMessage(null)

		const { data, error } = await supabase.auth.signUp({
			email: email.trim(),
			password,
			options: {
				data: { nombre: nombre.trim(), usuario: usuario.trim() },
				emailRedirectTo: `${window.location.origin}${next}`,
			},
		})

		if (error) setMessage('No pudimos crear tu acceso. Revisa que el correo y usuario estén disponibles.')
		else if (data.session) navigate(next, { replace: true })
		else setMessage('Cuenta creada. Revisa tu correo para confirmar el acceso y luego ingresa con tu usuario.')

		setLoading(false)
	}

	return (
		<AuthLayout title="Crea tu acceso" subtitle="Tu correo protege y recupera tu cuenta; tu usuario será el dato que usarás para ingresar.">
			<form className="space-y-5" onSubmit={submit}>
				<label className="block"><span className="fh-label">Nombre</span><input className="fh-input" required value={nombre} onChange={(e) => setNombre(e.target.value)} placeholder="Tu nombre" /></label>
				<label className="block"><span className="fh-label">Correo</span><input className="fh-input" type="email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} placeholder="nombre@correo.com" /></label>
				<label className="block"><span className="fh-label">Usuario</span><input className="fh-input" autoComplete="username" required value={usuario} onChange={(e) => setUsuario(e.target.value)} placeholder="Ej. Jhosep" /></label>
				<label className="block"><span className="fh-label">Contraseña</span><input className="fh-input" type="password" autoComplete="new-password" required value={password} onChange={(e) => setPassword(e.target.value)} placeholder="Mínimo 8 caracteres" /></label>
				<label className="block"><span className="fh-label">Confirmar contraseña</span><input className="fh-input" type="password" autoComplete="new-password" required value={confirmPassword} onChange={(e) => setConfirmPassword(e.target.value)} placeholder="Repite tu contraseña" /></label>
				<button className="fh-button-primary w-full" disabled={loading}>{loading ? 'Creando...' : 'Crear acceso'}</button>
			</form>

			{message && <p className="fh-alert mt-4">{message}</p>}
			<p className="mt-7 text-center text-sm text-slate-500">
				¿Ya tienes cuenta? <Link className="font-semibold text-[#0f766e]" to={`/login?next=${encodeURIComponent(next)}`}>Ingresar</Link>
			</p>
		</AuthLayout>
	)
}
