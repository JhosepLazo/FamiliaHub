import { CircleDollarSign, CreditCard, Home, HousePlug, LogOut, ReceiptText, Settings2, UserRound, Users } from 'lucide-react'
import type { ReactNode } from 'react'
import { NavLink, Outlet } from 'react-router-dom'
import { useAuth } from '../features/auth/AuthContext'
import { useFamilia } from '../features/familia/FamiliaContext'
import { supabase } from '../lib/supabase'
import Brand from './Brand'

const itemClass = ({ isActive }: { isActive: boolean }) =>
	`group flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition duration-200 ${isActive
		? 'bg-linear-to-r from-teal-400/20 to-cyan-400/5 text-white shadow-[inset_2px_0_0_0_#22d3ee] ring-1 ring-inset ring-cyan-300/15 [&_svg]:text-cyan-300'
		: 'text-slate-400 hover:bg-white/5 hover:text-white [&_svg]:text-slate-500 hover:[&_svg]:text-cyan-200'}`

export default function AppShell() {
	const { user } = useAuth()
	const { familia, membresia } = useFamilia()
	const logout = () => void supabase.auth.signOut()
	const isAdmin = membresia?.rol === 'ADMINISTRADOR'

	return (
		<div className="min-h-screen text-slate-900 lg:grid lg:grid-cols-[256px_1fr]">
			<aside className="sticky top-0 hidden h-screen flex-col overflow-hidden bg-fh-night p-5 text-white lg:flex">
				<div className="pointer-events-none absolute inset-0 bg-[radial-gradient(420px_260px_at_0%_0%,rgb(20_184_166/0.22),transparent_70%),radial-gradient(360px_300px_at_100%_100%,rgb(34_211_238/0.14),transparent_70%)]" />
				<div className="pointer-events-none absolute inset-y-0 right-0 w-px bg-linear-to-b from-transparent via-cyan-300/30 to-transparent" />

				<div className="relative"><Brand tone="dark" /></div>
				<nav className="relative mt-10 space-y-1">
					<NavLink to="/inicio" className={itemClass}><Home size={18} />Inicio</NavLink>
					<NavLink to="/mis-cuotas" className={itemClass}><CircleDollarSign size={18} />Mis cuotas</NavLink>
					<NavLink to="/pagos" className={itemClass}><CreditCard size={18} />Pagos</NavLink>
					<NavLink to="/recibos" className={itemClass}><ReceiptText size={18} />Hogar</NavLink>
					<NavLink to="/familia" className={itemClass}><Users size={18} />Familia</NavLink>
					{isAdmin && (
						<>
							<NavLink to="/servicios" className={itemClass}><HousePlug size={18} />Servicios</NavLink>
							<NavLink to="/configuracion" className={itemClass}><Settings2 size={18} />Configuración</NavLink>
						</>
					)}
					<NavLink to="/perfil" className={itemClass}><UserRound size={18} />Perfil</NavLink>
				</nav>

				<div className="relative mt-auto rounded-2xl border border-white/10 bg-white/[0.04] p-4 backdrop-blur">
					<p className="text-[11px] font-medium uppercase tracking-[0.16em] text-cyan-200/60">Familia actual</p>
					<p className="mt-1.5 truncate text-sm font-semibold">{familia?.nombre}</p>
					<p className="mt-1 truncate text-xs text-slate-400">{user?.email}</p>
					<button onClick={logout} className="mt-4 flex items-center gap-2 text-xs font-semibold text-slate-400 transition hover:text-white">
						<LogOut size={15} />Cerrar sesión
					</button>
				</div>
			</aside>

			<div className="min-w-0">
				<header className="sticky top-0 z-20 flex h-16 items-center justify-between border-b border-white/70 bg-white/60 px-5 backdrop-blur-xl lg:px-8">
					<div className="lg:hidden"><Brand compact /></div>
					<div className="hidden lg:block">
						<p className="text-[11px] font-medium uppercase tracking-[0.16em] text-slate-400">Familia</p>
						<p className="text-sm font-semibold">{familia?.nombre}</p>
					</div>
					<div className="flex items-center gap-3">
						<div className="text-right">
							<p className="max-w-44 truncate text-sm font-medium">{user?.email}</p>
							<p className="text-xs text-slate-400">{isAdmin ? 'Administrador' : 'Integrante'}</p>
						</div>
						<span className="relative flex size-2.5" title="Conectado">
							<span className="absolute inline-flex size-full animate-ping rounded-full bg-cyan-400 opacity-60 motion-reduce:animate-none" />
							<span className="relative inline-flex size-2.5 rounded-full bg-cyan-500" />
						</span>
					</div>
				</header>

				<main className="mx-auto max-w-6xl px-5 py-7 pb-32 sm:px-7 lg:px-8 lg:pb-10"><Outlet /></main>
			</div>

			<nav className={`fixed inset-x-3 bottom-3 z-30 grid ${isAdmin ? 'grid-cols-5' : 'grid-cols-4'} rounded-2xl bg-fh-night/90 px-1.5 pt-1.5 pb-[max(6px,env(safe-area-inset-bottom))] shadow-[0_18px_40px_-12px_rgb(7_11_20/0.65)] ring-1 ring-white/10 backdrop-blur-xl lg:hidden`}>
				<MobileLink to="/inicio" label="Inicio" icon={<Home size={19} />} />
				<MobileLink to="/mis-cuotas" label="Mis cuotas" icon={<CircleDollarSign size={19} />} />
				<MobileLink to="/recibos" label="Hogar" icon={<ReceiptText size={19} />} />
				{isAdmin && <MobileLink to="/servicios" label="Servicios" icon={<HousePlug size={19} />} />}
				<MobileLink to="/perfil" label="Perfil" icon={<UserRound size={19} />} />
			</nav>
		</div>
	)
}

function MobileLink({ to, label, icon }: { to: string; label: string; icon: ReactNode }) {
	return (
		<NavLink
			to={to}
			className={({ isActive }) => `flex flex-col items-center gap-1 rounded-xl py-2 text-[11px] font-medium transition ${isActive ? 'bg-white/[0.07] text-cyan-300 [&_svg]:drop-shadow-[0_0_8px_rgb(34_211_238/0.8)]' : 'text-slate-400'}`}
		>
			{icon}{label}
		</NavLink>
	)
}
