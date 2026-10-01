import { FormEvent, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import AuthLayout from '../../components/AuthLayout'
import { supabase } from '../../lib/supabase'

export default function UpdatePasswordPage() {
	const navigate = useNavigate()
	const [password, setPassword] = useState('')
	const [confirm, setConfirm] = useState('')
	const [loading, setLoading] = useState(false)
	const [message, setMessage] = useState<string | null>(null)

	const submit = async (event: FormEvent) => {
		event.preventDefault()
		if (password.length < 8) return setMessage('La contraseña debe tener al menos 8 caracteres.')
		if (password !== confirm) return setMessage('Las contraseñas no coinciden.')

		setLoading(true)
		const { error } = await supabase.auth.updateUser({ password })

		if (error) setMessage('El enlace no es válido o expiró. Solicita uno nuevo.')
		else navigate('/inicio', { replace: true })

		setLoading(false)
	}

	return (
		<AuthLayout title="Nueva contraseña" subtitle="Define una contraseña nueva para tu acceso personal.">
			<form className="space-y-5" onSubmit={submit}>
				<label className="block"><span className="fh-label">Nueva contraseña</span><input className="fh-input" type="password" required value={password} onChange={(e) => setPassword(e.target.value)} /></label>
				<label className="block"><span className="fh-label">Confirmar contraseña</span><input className="fh-input" type="password" required value={confirm} onChange={(e) => setConfirm(e.target.value)} /></label>
				<button className="fh-button-primary w-full" disabled={loading}>{loading ? 'Guardando...' : 'Guardar contraseña'}</button>
			</form>

			{message && <p className="fh-alert mt-4">{message}</p>}
		</AuthLayout>
	)
}
