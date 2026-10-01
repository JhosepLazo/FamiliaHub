import { FormEvent, useState } from 'react'
import { Link } from 'react-router-dom'
import AuthLayout from '../../components/AuthLayout'
import { supabase } from '../../lib/supabase'

export default function ForgotPasswordPage() {
	const [email, setEmail] = useState('')
	const [loading, setLoading] = useState(false)
	const [message, setMessage] = useState<string | null>(null)

	const submit = async (event: FormEvent) => {
		event.preventDefault()
		setLoading(true)

		const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), {
			redirectTo: `${window.location.origin}/actualizar-contrasena`,
		})

		setMessage(error ? 'No pudimos enviar el enlace. Inténtalo nuevamente.' : 'Si el correo pertenece a una cuenta, recibirás un enlace para cambiar tu contraseña.')
		setLoading(false)
	}

	return (
		<AuthLayout title="Recupera tu contraseña" subtitle="Te enviaremos un enlace seguro para establecer una nueva contraseña.">
			<form className="space-y-5" onSubmit={submit}>
				<label className="block"><span className="fh-label">Correo</span><input className="fh-input" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} placeholder="nombre@correo.com" /></label>
				<button className="fh-button-primary w-full" disabled={loading}>{loading ? 'Enviando...' : 'Enviar enlace'}</button>
			</form>

			{message && <p className="fh-alert mt-4">{message}</p>}
			<p className="mt-7 text-center text-sm"><Link className="font-semibold text-[#0f766e]" to="/login">Volver al ingreso</Link></p>
		</AuthLayout>
	)
}
