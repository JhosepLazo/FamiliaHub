import {
	AlertTriangle,
	ArrowRight,
	CalendarClock,
	CheckCircle2,
	CircleDollarSign,
	Clock3,
	ReceiptText,
	ShieldCheck,
	WalletCards,
} from 'lucide-react'
import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { useCurrentFinance, type AdminAttention, type CuotaConRecibo } from '../cuotas/useCurrentFinance'
import { useFamilia } from '../familia/FamiliaContext'
import { dateLabel, money, periodLabel } from '../recibos/reciboUi'

export default function InicioPage() {
	const { familia, membresia } = useFamilia()
	const { periodo, cuotasConRecibo, resumen, adminAttention, pagosParaValidar, loading, error } = useCurrentFinance()
	const isAdmin = membresia?.rol === 'ADMINISTRADOR'
	const pending = cuotasConRecibo.filter(({ cuota }) => cuota.estado !== 'PAGADA' && cuota.estado !== 'ANULADA').slice(0, 3)

	return (
		<div>
			<div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
				<div>
					<p className="text-sm font-semibold text-[#0f766e]">Inicio</p>
					<h1 className="mt-1 text-3xl font-semibold tracking-tight">{familia?.nombre}</h1>
					<p className="mt-2 text-sm text-slate-500">Lo importante de tu hogar, sin tener que buscarlo.</p>
				</div>
				<p className="text-sm font-medium capitalize text-slate-400">{periodo ? periodLabel(periodo.anio, periodo.mes) : 'Periodo actual'}</p>
			</div>

			{loading ? (
				<div className="mt-8 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
					{Array.from({ length: 4 }).map((_, index) => <div key={index} className="h-32 animate-pulse rounded-2xl bg-white" />)}
				</div>
			) : (
				<>
					<div className="mt-8 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
						<SummaryCard icon={<CircleDollarSign />} label="Debes este mes" value={money(resumen.debe)} accent />
						<SummaryCard icon={<WalletCards />} label="Pagaste" value={money(resumen.pagado)} />
						<SummaryCard icon={<Clock3 />} label="Pendientes" value={String(resumen.pendientes)} />
						<SummaryCard
							icon={<CalendarClock />}
							label="Próximo"
							value={resumen.proxima ? resumen.proxima.recibo.nombre_concepto : 'Todo al día'}
							subtitle={resumen.proxima ? dateLabel(resumen.proxima.fechaObjetivo) : undefined}
						/>
					</div>

					<div className="mt-7 grid gap-6 xl:grid-cols-[1.35fr_.85fr]">
						<section className="rounded-3xl border border-slate-200 bg-white p-5 sm:p-6">
							<div className="flex items-start justify-between gap-4">
								<div>
									<p className="text-sm font-semibold">Tu mes</p>
									<h2 className="mt-1 text-xl font-semibold">{pending.length ? 'Esto es lo que sigue' : 'No tienes cuotas pendientes'}</h2>
									<p className="mt-1 text-xs leading-5 text-slate-400">{pending.length ? 'FamiliaHub ordena primero lo vencido y después lo que vence más pronto.' : 'Cuando todo está resuelto, no te mostramos tareas innecesarias.'}</p>
								</div>
								<Link to="/mis-cuotas" className="hidden items-center gap-1 text-xs font-semibold text-[#0f766e] sm:flex">Ver todas<ArrowRight size={14} /></Link>
							</div>

							{pending.length ? (
								<div className="mt-5 space-y-3">
									{pending.map((row) => <PriorityQuota key={row.cuota.id} row={row} />)}
								</div>
							) : (
								<div className="mt-5 flex gap-3 rounded-2xl bg-emerald-50 p-4 text-emerald-800">
									<CheckCircle2 size={20} className="shrink-0" />
									<div><p className="text-sm font-semibold">Todo listo por tu lado</p><p className="mt-1 text-xs text-emerald-700/70">No tienes saldos personales pendientes en el periodo actual.</p></div>
								</div>
							)}

							<Link to="/mis-cuotas" className="fh-button-primary mt-5 inline-flex w-full justify-center sm:hidden">Ver mis cuotas</Link>
						</section>

						{isAdmin ? <AdminAttentionPanel attention={adminAttention} /> : <HomeStatusPanel pagosParaValidar={pagosParaValidar} />}
					</div>

					<section className="mt-6 rounded-3xl border border-slate-200 bg-white p-5 sm:p-6">
						<div className="flex items-center gap-3">
							<div className="grid size-10 place-items-center rounded-xl bg-slate-50 text-slate-500"><ReceiptText size={18} /></div>
							<div><h2 className="font-semibold">Hogar</h2><p className="text-xs text-slate-400">Consulta recibos, distribución familiar y estado del proveedor.</p></div>
						</div>
						<div className="mt-5 flex flex-col gap-3 sm:flex-row">
							<Link to="/recibos" className="fh-button-secondary inline-flex items-center justify-center gap-2">Ver recibos del hogar<ArrowRight size={14} /></Link>
							{isAdmin && <Link to="/servicios" className="fh-button-secondary inline-flex items-center justify-center">Configurar servicios</Link>}
						</div>
					</section>
				</>
			)}

			{error && <p className="fh-alert mt-5">{error}</p>}
	</div>
	)
}

function PriorityQuota({ row }: { row: CuotaConRecibo }) {
	const { cuota, recibo, fechaObjetivo, diasRestantes, vencida } = row
	const label = cuota.estado === 'POR_VALIDAR' ? 'Pago enviado' : vencida ? 'Vencida' : relativeDue(diasRestantes)
	return (
		<Link to={`/recibos/${recibo.id}`} className="group flex items-center gap-4 rounded-2xl border border-slate-100 p-4 transition hover:border-slate-200 hover:bg-slate-50/60">
			<div className={`grid size-10 shrink-0 place-items-center rounded-xl ${vencida ? 'bg-rose-50 text-rose-600' : 'bg-emerald-50 text-[#0f766e]'}`}><ReceiptText size={17} /></div>
			<div className="min-w-0 flex-1">
				<div className="flex flex-wrap items-center gap-2"><p className="truncate text-sm font-semibold">{recibo.nombre_concepto}</p><span className={`rounded-full px-2 py-1 text-[10px] font-semibold ${vencida ? 'bg-rose-50 text-rose-600' : cuota.estado === 'POR_VALIDAR' ? 'bg-amber-50 text-amber-700' : 'bg-slate-100 text-slate-500'}`}>{label}</span></div>
				<p className="mt-1 text-xs text-slate-400">{dateLabel(fechaObjetivo)} · Falta {money(cuota.saldo_pendiente)}</p>
			</div>
			<ArrowRight size={15} className="shrink-0 text-slate-300 transition group-hover:translate-x-1" />
		</Link>
	)
}

function AdminAttentionPanel({ attention }: { attention: AdminAttention }) {
	const items = [
		{ label: 'Recibos esperando monto', count: attention.recibosEsperandoMonto },
		{ label: 'Vencimientos por completar', count: attention.vencimientosFaltantes },
		{ label: 'Pagos por validar', count: attention.pagosPorValidar },
		{ label: 'Recibos vencidos', count: attention.recibosVencidos },
		{ label: 'Recaudaciones fuera de fecha', count: attention.recaudacionesAtrasadas },
	].filter((item) => item.count > 0)

	return (
		<section className="rounded-3xl border border-slate-200 bg-white p-5 sm:p-6">
			<div className="flex items-center gap-3">
				<div className={`grid size-10 place-items-center rounded-xl ${items.length ? 'bg-amber-50 text-amber-700' : 'bg-emerald-50 text-emerald-700'}`}>{items.length ? <AlertTriangle size={18} /> : <ShieldCheck size={18} />}</div>
				<div><p className="text-sm font-semibold">Necesita tu atención</p><p className="text-xs text-slate-400">{items.length ? 'Solo mostramos excepciones que requieren intervención.' : 'No hay excepciones operativas pendientes.'}</p></div>
			</div>

			{items.length ? (
				<div className="mt-5 space-y-2">
					{items.map((item) => <div key={item.label} className="flex items-center justify-between rounded-xl bg-slate-50 px-4 py-3"><span className="text-xs font-medium text-slate-600">{item.label}</span><span className="grid min-w-6 place-items-center rounded-full bg-white px-2 py-1 text-[10px] font-bold text-slate-600">{item.count}</span></div>)}
					<div className="mt-4 flex flex-wrap gap-3">
						<Link to="/pagos" className="inline-flex items-center gap-1 text-xs font-semibold text-[#0f766e]">Validar pagos<ArrowRight size={14} /></Link>
						<Link to="/recibos" className="inline-flex items-center gap-1 text-xs font-semibold text-slate-500">Resolver recibos<ArrowRight size={14} /></Link>
					</div>
				</div>
			) : (
				<div className="mt-5 rounded-2xl bg-emerald-50 p-4"><p className="text-sm font-semibold text-emerald-800">Todo está al día ✓</p><p className="mt-1 text-xs text-emerald-700/70">FamiliaHub no necesita que hagas nada ahora.</p></div>
			)}
		</section>
	)
}

function HomeStatusPanel({ pagosParaValidar }: { pagosParaValidar: number }) {
	return (
		<section className="rounded-3xl border border-slate-200 bg-white p-5 sm:p-6">
			<div className="flex items-center gap-3"><div className={`grid size-10 place-items-center rounded-xl ${pagosParaValidar ? 'bg-amber-50 text-amber-700' : 'bg-emerald-50 text-emerald-700'}`}><ShieldCheck size={18} /></div><div><p className="text-sm font-semibold">{pagosParaValidar ? 'Necesita tu atención' : 'Estado del hogar'}</p><p className="text-xs text-slate-400">{pagosParaValidar ? 'Eres el receptor responsable de confirmar pagos.' : 'FamiliaHub mantiene tus cuotas y recibos sincronizados.'}</p></div></div>
			{pagosParaValidar ? (
				<div className="mt-5 rounded-2xl bg-amber-50 p-4"><p className="text-sm font-semibold text-amber-800">{pagosParaValidar} pago{pagosParaValidar === 1 ? '' : 's'} por validar</p><Link to="/pagos" className="mt-2 inline-flex items-center gap-1 text-xs font-semibold text-amber-800">Revisar pagos<ArrowRight size={14} /></Link></div>
			) : (
				<div className="mt-5 rounded-2xl bg-slate-50 p-4"><p className="text-xs leading-5 text-slate-500">Tú solo necesitas revisar tus cuotas y registrar un pago cuando corresponda. La administración del recibo permanece separada.</p></div>
			)}
		</section>
	)
}

function SummaryCard({ icon, label, value, subtitle, accent = false }: { icon: ReactNode; label: string; value: string; subtitle?: string; accent?: boolean }) {
	return (
		<div className={`rounded-2xl border p-5 ${accent ? 'border-emerald-100 bg-emerald-50/60' : 'border-slate-200 bg-white'}`}>
			<div className={accent ? 'text-[#0f766e]' : 'text-slate-400'}>{icon}</div>
			<p className="mt-5 text-xs font-medium text-slate-400">{label}</p>
			<p className={`mt-1 truncate text-xl font-semibold ${accent ? 'text-[#0f766e]' : 'text-slate-800'}`}>{value}</p>
			{subtitle && <p className="mt-1 text-[11px] text-slate-400">{subtitle}</p>}
		</div>
	)
}

function relativeDue(days: number | null) {
	if (days == null) return 'Pendiente'
	if (days < 0) return 'Vencida'
	if (days === 0) return 'Vence hoy'
	if (days === 1) return 'Vence mañana'
	return `Vence en ${days} días`
}
