import { LockKeyhole, UserRound } from 'lucide-react'
import type { ReactNode } from 'react'
import { FormEvent, useEffect, useState } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import AuthLayout from '../../components/AuthLayout'
import { safeNext } from '../../lib/navigation'
import { supabase } from '../../lib/supabase'
import { useAuth } from './AuthContext'

export default function LoginPage() {
	const { user, loading: authLoading } = useAuth()
	const [params] = useSearchParams()
	const navigate = useNavigate()
	const next = safeNext(params.get('next'))
	const [usuario, setUsuario] = useState('')
	const [password, setPassword] = useState('')
	const [loading, setLoading] = useState(false)
	const [message, setMessage] = useState<string | null>(null)

	useEffect(() => {
		if (!authLoading && user) navigate(next, { replace: true })
	}, [authLoading, user, navigate, next])

	const submit = async (event: FormEvent) => {
		event.preventDefault()
		setLoading(true)
		setMessage(null)

		const { data, error } = await supabase.functions.invoke('login-usuario', {
			body: { usuario: usuario.trim(), password },
		})

		const session = data?.session
		if (error || !session?.access_token || !session?.refresh_token) {
			setMessage('No pudimos iniciar sesión. Revisa tu usuario y contraseña.')
			setLoading(false)
			return
		}

		const { error: sessionError } = await supabase.auth.setSession({
			access_token: session.access_token,
			refresh_token: session.refresh_token,
		})

		if (sessionError) setMessage('No pudimos iniciar sesión. Inténtalo nuevamente.')
		else navigate(next, { replace: true })

		setLoading(false)
	}

	return (
		<AuthLayout title="Ingresa a tu familia" subtitle="Consulta tus cuotas y la información del hogar desde tu acceso personal.">
			<form className="space-y-5" onSubmit={submit}>
				<Field label="Usuario" icon={<UserRound size={17} />}>
					<input className="fh-input pl-11" autoComplete="username" required value={usuario} onChange={(e) => setUsuario(e.target.value)} placeholder="Jhosep" />
				</Field>
				<Field label="Contraseña" icon={<LockKeyhole size={17} />}>
					<input className="fh-input pl-11" type="password" autoComplete="current-password" required value={password} onChange={(e) => setPassword(e.target.value)} placeholder="••••••••" />
				</Field>
				<div className="flex justify-end"><Link className="text-sm font-medium text-[#0f766e] hover:underline" to="/recuperar">Olvidé mi contraseña</Link></div>
				<button className="fh-button-primary w-full" disabled={loading}>{loading ? 'Ingresando...' : 'Ingresar'}</button>
			</form>

			{message && <p className="fh-alert mt-4">{message}</p>}

			<div className="mt-8 border-t border-slate-200 pt-6 text-center text-sm text-slate-500">
				¿Vas a crear tu espacio familiar? <Link className="font-semibold text-[#0f766e] hover:underline" to={`/registro?next=${encodeURIComponent(next)}`}>Crear acceso</Link>
			</div>
		</AuthLayout>
	)
}

function Field({ label, icon, children }: { label: string; icon: ReactNode; children: ReactNode }) {
	return (
		<label className="block">
			<span className="mb-2 block text-sm font-medium">{label}</span>
			<div className="relative">
				<span className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-400">{icon}</span>
				{children}
			</div>
		</label>
	)
}
