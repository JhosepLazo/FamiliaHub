import { CalendarDays, ShieldCheck, Users, WalletCards } from 'lucide-react'
import type { ReactNode } from 'react'
import { useFamilia } from '../familia/FamiliaContext'

export default function InicioPage() {
	const { familia, membresia } = useFamilia()
	const now = new Intl.DateTimeFormat('es-PE', { month: 'long', year: 'numeric', timeZone: 'America/Lima' }).format(new Date())

	return (
		<div>
			<div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
				<div>
					<p className="text-sm font-semibold text-[#0f766e]">Inicio</p>
					<h1 className="mt-1 text-3xl font-semibold tracking-tight">{familia?.nombre}</h1>
					<p className="mt-2 text-sm text-slate-500">La base familiar está lista para empezar a configurar los servicios.</p>
				</div>
				<p className="capitalize text-sm font-medium text-slate-400">{now}</p>
			</div>

			<div className="mt-8 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
				<Card icon={<Users />} label="Tu rol" value={membresia?.rol === 'ADMINISTRADOR' ? 'Administrador' : 'Integrante'} />
				<Card icon={<WalletCards />} label="Moneda" value={familia?.moneda.trim() || 'PEN'} />
				<Card icon={<CalendarDays />} label="Zona horaria" value={familia?.zona_horaria || 'America/Lima'} />
				<Card icon={<ShieldCheck />} label="Privacidad" value="Familia aislada" />
			</div>

			<div className="mt-8 rounded-3xl border border-slate-200 bg-white p-6">
				<p className="text-sm font-semibold">Siguiente paso</p>
				<h2 className="mt-2 text-xl font-semibold">Configura integrantes y cuenta receptora</h2>
				<p className="mt-2 max-w-2xl text-sm leading-6 text-slate-500">Antes de crear servicios y recibos, FamiliaHub necesita saber quiénes forman parte de la familia y dónde se recibirán las cuotas.</p>
			</div>
		</div>
	)
}

function Card({ icon, label, value }: { icon: ReactNode; label: string; value: string }) {
	return (
		<div className="rounded-2xl border border-slate-200 bg-white p-5">
			<div className="text-[#0f766e] [&>svg]:size-5">{icon}</div>
			<p className="mt-5 text-xs font-medium text-slate-400">{label}</p>
			<p className="mt-1 text-sm font-semibold">{value}</p>
		</div>
	)
}
