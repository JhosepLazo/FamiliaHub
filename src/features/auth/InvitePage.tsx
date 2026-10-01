import { CheckCircle2, Mail } from 'lucide-react'
import { useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import AuthLayout from '../../components/AuthLayout'
import { supabase } from '../../lib/supabase'
import { useAuth } from './AuthContext'

export default function InvitePage() {
	const { token = '' } = useParams()
	const { user, loading: authLoading } = useAuth()
	const navigate = useNavigate()
	const [loading, setLoading] = useState(false)
	const [message, setMessage] = useState<string | null>(null)
	const next = `/invitacion/${token}`

	const accept = async () => {
		setLoading(true)
		setMessage(null)

		const { error } = await supabase.functions.invoke('aceptar-invitacion', { body: { token } })

		if (error) setMessage('No pudimos aceptar la invitación. Verifica que corresponda a tu correo y que siga vigente.')
		else navigate('/inicio', { replace: true })

		setLoading(false)
	}

	return (
		<AuthLayout title="Invitación familiar" subtitle="Este enlace permite unirte de forma privada a una familia en FamiliaHub.">
			<div className="rounded-2xl border border-emerald-100 bg-emerald-50 p-5">
				<CheckCircle2 className="text-[#0f766e]" size={24} />
				<p className="mt-3 font-semibold">Invitación protegida</p>
				<p className="mt-1 text-sm leading-6 text-slate-600">El enlace es de un solo uso, vence automáticamente y debe coincidir con el correo invitado.</p>
			</div>

			{!authLoading && !user && (
				<div className="mt-6 space-y-3">
					<Link className="fh-button-primary flex w-full justify-center" to={`/login?next=${encodeURIComponent(next)}`}>Ya tengo cuenta</Link>
					<Link className="fh-button-secondary flex w-full justify-center" to={`/registro?next=${encodeURIComponent(next)}`}>Crear mi acceso</Link>
				</div>
			)}

			{user && (
				<div className="mt-6">
					<div className="mb-4 flex items-center gap-3 rounded-xl bg-white p-4 text-sm text-slate-600">
						<Mail size={18} className="text-slate-400" />
						<span className="truncate">{user.email}</span>
					</div>
					<button className="fh-button-primary w-full" onClick={accept} disabled={loading}>{loading ? 'Uniéndote...' : 'Aceptar invitación'}</button>
				</div>
			)}

			{message && <p className="fh-alert mt-4">{message}</p>}
		</AuthLayout>
	)
}
