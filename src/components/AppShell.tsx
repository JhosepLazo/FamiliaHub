import { Home, HousePlug, LogOut, Settings2, UserRound, Users } from 'lucide-react'
import type { ReactNode } from 'react'
import { NavLink, Outlet } from 'react-router-dom'
import { useAuth } from '../features/auth/AuthContext'
import { useFamilia } from '../features/familia/FamiliaContext'
import { supabase } from '../lib/supabase'
import Brand from './Brand'

const itemClass = ({ isActive }: { isActive: boolean }) =>
	`flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition ${isActive ? 'bg-[#e7f3ef] text-[#0f766e]' : 'text-slate-500 hover:bg-slate-50 hover:text-slate-900'}`

export default function AppShell() {
	const { user } = useAuth()
	const { familia, membresia } = useFamilia()
	const logout = () => void supabase.auth.signOut()

	return (
		<div className="min-h-screen bg-[#f4f6f2] text-slate-900 lg:grid lg:grid-cols-[248px_1fr]">
			<aside className="hidden border-r border-slate-200/80 bg-white p-5 lg:flex lg:flex-col">
				<Brand />
				<nav className="mt-10 space-y-1">
					<NavLink to="/inicio" className={itemClass}><Home size={18} />Inicio</NavLink>
					<NavLink to="/familia" className={itemClass}><Users size={18} />Familia</NavLink>
					{membresia?.rol === 'ADMINISTRADOR' && (
						<>
							<NavLink to="/servicios" className={itemClass}><HousePlug size={18} />Servicios</NavLink>
							<NavLink to="/configuracion" className={itemClass}><Settings2 size={18} />Configuración</NavLink>
						</>
					)}
					<NavLink to="/perfil" className={itemClass}><UserRound size={18} />Perfil</NavLink>
				</nav>

				<div className="mt-auto rounded-2xl border border-slate-200 bg-slate-50 p-4">
					<p className="text-xs font-medium text-slate-400">Familia actual</p>
					<p className="mt-1 truncate text-sm font-semibold">{familia?.nombre}</p>
					<p className="mt-1 truncate text-xs text-slate-500">{user?.email}</p>
					<button onClick={logout} className="mt-4 flex items-center gap-2 text-xs font-semibold text-slate-500 hover:text-slate-900">
						<LogOut size={15} />Cerrar sesión
					</button>
				</div>
			</aside>

			<div className="min-w-0">
				<header className="sticky top-0 z-20 flex h-16 items-center justify-between border-b border-slate-200/80 bg-white/90 px-5 backdrop-blur lg:px-8">
					<div className="lg:hidden"><Brand compact /></div>
					<div className="hidden lg:block">
						<p className="text-xs font-medium text-slate-400">Familia</p>
						<p className="text-sm font-semibold">{familia?.nombre}</p>
					</div>
					<div className="text-right">
						<p className="max-w-44 truncate text-sm font-medium">{user?.email}</p>
						<p className="text-xs text-slate-400">{membresia?.rol === 'ADMINISTRADOR' ? 'Administrador' : 'Integrante'}</p>
					</div>
				</header>

				<main className="mx-auto max-w-6xl px-5 py-7 pb-28 sm:px-7 lg:px-8 lg:pb-10"><Outlet /></main>
			</div>

			<nav className={`fixed inset-x-0 bottom-0 z-30 grid ${membresia?.rol === 'ADMINISTRADOR' ? 'grid-cols-5' : 'grid-cols-3'} border-t border-slate-200 bg-white/95 px-2 pb-[max(8px,env(safe-area-inset-bottom))] pt-2 backdrop-blur lg:hidden`}>
				<MobileLink to="/inicio" label="Inicio" icon={<Home size={19} />} />
				<MobileLink to="/familia" label="Familia" icon={<Users size={19} />} />
				{membresia?.rol === 'ADMINISTRADOR' && <MobileLink to="/servicios" label="Servicios" icon={<HousePlug size={19} />} />}
				{membresia?.rol === 'ADMINISTRADOR' && <MobileLink to="/configuracion" label="Config." icon={<Settings2 size={19} />} />}
				<MobileLink to="/perfil" label="Perfil" icon={<UserRound size={19} />} />
			</nav>
		</div>
	)
}

function MobileLink({ to, label, icon }: { to: string; label: string; icon: ReactNode }) {
	return (
		<NavLink to={to} className={({ isActive }) => `flex flex-col items-center gap-1 rounded-xl py-2 text-[11px] font-medium ${isActive ? 'text-[#0f766e]' : 'text-slate-400'}`}>
			{icon}{label}
		</NavLink>
	)
}
