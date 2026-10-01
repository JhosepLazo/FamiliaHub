import { LogOut, Settings2, Users } from 'lucide-react'
import { FormEvent, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../auth/AuthContext'
import { useFamilia } from '../familia/FamiliaContext'

export default function ProfilePage() {
	const { user } = useAuth()
	const { membresia } = useFamilia()
	const [nombre, setNombre] = useState('')
	const [loading, setLoading] = useState(false)
	const [message, setMessage] = useState<string | null>(null)

	useEffect(() => {
		if (!user) return
		void supabase.from('perfiles').select('nombre').eq('id', user.id).single().then(({ data }) => setNombre(data?.nombre ?? ''))
	}, [user])

	const save = async (event: FormEvent) => {
		event.preventDefault()
		if (!user) return
		setLoading(true)
		const { error } = await supabase.from('perfiles').update({ nombre: nombre.trim(), updated_at: new Date().toISOString() }).eq('id', user.id)
		setMessage(error ? 'No pudimos guardar tu perfil.' : 'Perfil actualizado.')
		setLoading(false)
	}

	return (
		<div className="max-w-2xl">
			<p className="text-sm font-semibold text-[#0f766e]">Perfil</p>
			<h1 className="mt-1 text-3xl font-semibold tracking-tight">Tu información</h1>
			<p className="mt-2 text-sm text-slate-500">Tu acceso es personal. El correo proviene de Supabase Auth y el nombre se usa dentro de tu familia.</p>

			<form onSubmit={save} className="mt-8 rounded-3xl border border-slate-200 bg-white p-6 sm:p-8">
				<label className="block"><span className="fh-label">Nombre</span><input className="fh-input" required value={nombre} onChange={(e) => setNombre(e.target.value)} /></label>
				<label className="mt-5 block"><span className="fh-label">Correo</span><input className="fh-input bg-slate-50 text-slate-500" value={user?.email ?? ''} disabled /></label>
				<button className="fh-button-primary mt-6" disabled={loading}>{loading ? 'Guardando...' : 'Guardar cambios'}</button>
				{message && <p className="fh-alert mt-4">{message}</p>}
			</form>

			<Link to="/familia" className="fh-button-secondary mt-4 flex items-center gap-2 lg:hidden"><Users size={16} />Familia e integrantes</Link>
			{membresia?.rol === 'ADMINISTRADOR' && (
				<Link to="/configuracion" className="fh-button-secondary mt-3 flex items-center gap-2 lg:hidden"><Settings2 size={16} />Configuración familiar</Link>
			)}
			<button type="button" onClick={() => void supabase.auth.signOut()} className="fh-button-secondary mt-3 flex items-center gap-2 lg:hidden"><LogOut size={16} />Cerrar sesión</button>
		</div>
	)
}
