import { AtSign, LogOut, Mail } from 'lucide-react'
import { FormEvent, useEffect, useState } from 'react'
import PageHeader from '../../components/ui/PageHeader'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../auth/AuthContext'
import { useFamilia } from '../familia/FamiliaContext'
import MetodosCobroPersonales from '../pagos/MetodosCobroPersonales'
import WhatsAppPerfilSection from '../whatsapp/WhatsAppPerfilSection'

export default function ProfilePage() {
	const { user } = useAuth()
	const { familia, membresia } = useFamilia()
	const [nombre, setNombre] = useState('')
	const [usuario, setUsuario] = useState('')
	const [loading, setLoading] = useState(false)
	const [message, setMessage] = useState<string | null>(null)

	useEffect(() => {
		if (!user) return
		void supabase.from('perfiles').select('nombre,usuario').eq('id', user.id).single().then(({ data }) => {
			setNombre(data?.nombre ?? '')
			setUsuario(data?.usuario ?? '')
		})
	}, [user])

	const save = async (event: FormEvent) => {
		event.preventDefault()
		if (!user) return
		setLoading(true)
		const { error } = await supabase.from('perfiles').update({ nombre: nombre.trim(), updated_at: new Date().toISOString() }).eq('id', user.id)
		setMessage(error ? 'No pudimos guardar tu perfil.' : 'Perfil actualizado.')
		setLoading(false)
	}

	const inicial = (nombre || usuario || user?.email || '?').trim().charAt(0).toUpperCase()

	return (
		<div className="mx-auto max-w-3xl">
			<PageHeader eyebrow="Perfil" title="Tu cuenta" description="Tu acceso es personal. Aquí cambias tu nombre, cómo recibir reembolsos y tu WhatsApp." />

			<section className="fh-card fh-entrada mt-7 overflow-hidden">
				<div className="relative flex items-center gap-4 bg-fh-night p-6 text-white">
					<div className="pointer-events-none absolute inset-0 bg-[radial-gradient(320px_200px_at_0%_0%,rgb(20_184_166/0.35),transparent_70%),radial-gradient(280px_200px_at_100%_100%,rgb(34_211_238/0.22),transparent_70%)]" />
					<div className="relative grid size-14 shrink-0 place-items-center rounded-2xl bg-linear-to-br from-teal-400 to-cyan-600 text-xl font-extrabold shadow-[0_0_26px_-6px_rgb(34_211_238/0.8)] ring-1 ring-white/20">{inicial}</div>
					<div className="relative min-w-0">
						<p className="truncate text-lg font-bold">{nombre || 'Tu nombre'}</p>
						<p className="truncate text-sm text-slate-300">{membresia?.rol === 'ADMINISTRADOR' ? 'Administrador' : 'Integrante'} · {familia?.nombre}</p>
					</div>
				</div>

				<form onSubmit={save} className="grid gap-5 p-6 sm:p-7">
					<label className="block"><span className="fh-label">Nombre</span><input className="fh-input" required value={nombre} onChange={(e) => setNombre(e.target.value)} /></label>
					<div className="grid gap-5 sm:grid-cols-2">
						<label className="block"><span className="fh-label">Usuario para ingresar</span><div className="relative"><AtSign size={15} className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-400" /><input className="fh-input pl-10" value={usuario} disabled /></div></label>
						<label className="block"><span className="fh-label">Correo de recuperación</span><div className="relative"><Mail size={15} className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-400" /><input className="fh-input pl-10" value={user?.email ?? ''} disabled /></div></label>
					</div>
					<div className="flex flex-wrap items-center gap-3">
						<button className="fh-button-primary" disabled={loading}>{loading && <span className="fh-spinner" />}{loading ? 'Guardando…' : 'Guardar cambios'}</button>
						{message && <p className="text-sm font-semibold text-slate-500">{message}</p>}
					</div>
				</form>
			</section>

			<MetodosCobroPersonales />

			<WhatsAppPerfilSection />

			<button type="button" onClick={() => void supabase.auth.signOut()} className="fh-button-danger mt-6 w-full lg:hidden"><LogOut size={16} />Cerrar sesión</button>
		</div>
	)
}
