import {
	AlertTriangle,
	ArrowRight,
	CalendarClock,
	CheckCircle2,
	Clock3,
	ReceiptText,
	Search,
	ShieldCheck,
	Sparkles,
	WalletCards,
} from 'lucide-react'
import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { useCurrentFinance, type AdminAttention, type CuotaConRecibo } from '../cuotas/useCurrentFinance'
import { useFamilia } from '../familia/FamiliaContext'
import { ConsultaRapida } from '../recibos/ConsultaProveedor'
import { dateLabel, money, periodLabel } from '../recibos/reciboUi'

export default function InicioPage() {
	const { familia, membresia } = useFamilia()
	const { periodo, recibos, cuotasConRecibo, anteriores, resumen, adminAttention, pagosParaValidar, loading, error } = useCurrentFinance()
	const isAdmin = membresia?.rol === 'ADMINISTRADOR'
	const pending = cuotasConRecibo.filter(({ cuota }) => cuota.estado !== 'PAGADA' && cuota.estado !== 'ANULADA').slice(0, 3)
	const esperandoMonto = recibos.filter((recibo) => recibo.estado === 'ESPERANDO_MONTO')
	const totalMes = resumen.debe + resumen.pagado
	const avance = totalMes > 0 ? Math.min(100, Math.round((resumen.pagado / totalMes) * 100)) : 100
	const anterioresPorPagar = anteriores.filter(({ cuota }) => cuota.estado !== 'POR_VALIDAR')

	return (
		<div>
			<section className="relative overflow-hidden rounded-3xl bg-fh-night p-6 text-white shadow-[0_30px_60px_-30px_rgb(7_11_20/0.7)] sm:p-8">
				<div className="pointer-events-none absolute inset-0 bg-[radial-gradient(520px_300px_at_0%_0%,rgb(20_184_166/0.35),transparent_65%),radial-gradient(460px_320px_at_100%_100%,rgb(34_211_238/0.25),transparent_65%)]" />
				<div className="pointer-events-none absolute inset-0 bg-[linear-gradient(rgb(255_255_255/0.035)_1px,transparent_1px),linear-gradient(90deg,rgb(255_255_255/0.035)_1px,transparent_1px)] bg-[size:36px_36px] [mask-image:linear-gradient(to_bottom,black,transparent)]" />

				<div className="relative flex flex-col gap-8 lg:flex-row lg:items-end lg:justify-between">
					<div>
						<p className="inline-flex items-center gap-2 rounded-full border border-cyan-300/20 bg-cyan-300/10 px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.18em] text-cyan-200">
							<Sparkles size={12} />{periodo ? periodLabel(periodo.anio, periodo.mes) : 'Periodo actual'}
						</p>
						<h1 className="mt-4 text-3xl font-semibold tracking-tight sm:text-4xl">{familia?.nombre}</h1>
						<p className="mt-2 max-w-md text-sm text-slate-300/80">Lo importante de tu hogar, sin tener que buscarlo.</p>
					</div>

					<div className="min-w-64">
						<p className="text-xs font-medium uppercase tracking-[0.16em] text-slate-400">Debes este mes</p>
						<p className="mt-1 text-4xl font-semibold tracking-tight sm:text-5xl"><span className="fh-glow-text">{loading ? '—' : money(resumen.debe)}</span></p>
						<div className="mt-4 h-1.5 overflow-hidden rounded-full bg-white/10">
							<div className="h-full rounded-full bg-linear-to-r from-teal-400 to-cyan-300 shadow-[0_0_12px_rgb(34_211_238/0.8)] transition-all duration-700" style={{ width: `${loading ? 0 : avance}%` }} />
						</div>
						<p className="mt-2 text-xs text-slate-400">{loading ? 'Calculando…' : `Pagaste ${money(resumen.pagado)} · ${avance}% de tu mes`}</p>
						{!loading && resumen.debeAnteriores > 0 && <p className="mt-1 text-xs font-semibold text-rose-300">Además debes {money(resumen.debeAnteriores)} de meses anteriores</p>}
					</div>
				</div>
			</section>

			{loading ? (
				<div className="mt-6 grid gap-4 sm:grid-cols-3">
					{Array.from({ length: 3 }).map((_, index) => <div key={index} className="h-28 animate-pulse rounded-2xl bg-white/60" />)}
				</div>
			) : (
				<>
					<div className="mt-6 grid gap-3 sm:grid-cols-3 sm:gap-4">
						<SummaryCard icon={<WalletCards size={18} />} label="Pagaste" value={money(resumen.pagado)} />
						<SummaryCard icon={<Clock3 size={18} />} label="Pendientes" value={String(resumen.pendientes)} />
						<SummaryCard
							icon={<CalendarClock size={18} />}
							label="Próximo"
							value={resumen.proxima ? resumen.proxima.recibo.nombre_concepto : 'Todo al día'}
							subtitle={resumen.proxima ? dateLabel(resumen.proxima.fechaObjetivo) : undefined}
						/>
					</div>

					{anteriores.length > 0 && (
						<section className="mt-6 flex flex-col gap-4 rounded-3xl border border-rose-100 bg-rose-50/70 p-5 sm:flex-row sm:items-center sm:justify-between sm:p-6">
							<div className="flex items-center gap-3">
								<div className="grid size-10 shrink-0 place-items-center rounded-xl bg-white text-rose-600 ring-1 ring-rose-100"><AlertTriangle size={18} /></div>
								<div>
									<h2 className="font-semibold text-rose-900">Pendiente de meses anteriores · {money(resumen.debeAnteriores)}</h2>
									<p className="text-xs text-rose-700/80">{anteriores.map(({ recibo }) => recibo.nombre_concepto).join(' · ')}</p>
								</div>
							</div>
							{anterioresPorPagar.length > 0
								? <Link to={`/pagar?cuotas=${anterioresPorPagar.map(({ cuota }) => cuota.id).join(',')}`} className="fh-button-primary shrink-0">Pagar ahora<ArrowRight size={15} /></Link>
								: <Link to="/pagos?tab=mis-pagos" className="fh-button-secondary shrink-0">Ver pago enviado</Link>}
						</section>
					)}

					{isAdmin && esperandoMonto.length > 0 && (
						<section className="mt-6 rounded-3xl border border-cyan-100/80 bg-linear-to-br from-white/90 to-cyan-50/70 p-5 shadow-[0_20px_40px_-28px_rgb(8_145_178/0.7)] backdrop-blur sm:p-6">
							<div className="flex items-center gap-3">
								<div className="grid size-10 place-items-center rounded-xl bg-linear-to-br from-teal-500 to-cyan-600 text-white shadow-[0_0_20px_-4px_rgb(34_211_238/0.7)]"><Search size={18} /></div>
								<div>
									<h2 className="font-semibold">Montos por consultar</h2>
									<p className="text-xs text-slate-500">{esperandoMonto.length === 1 ? 'Un recibo espera su monto.' : `${esperandoMonto.length} recibos esperan su monto.`} "Consultar" copia el número y abre la página del proveedor.</p>
								</div>
							</div>
							<div className="mt-5 space-y-2.5">
								{esperandoMonto.map((recibo) => <ConsultaRapida key={recibo.id} recibo={recibo} />)}
							</div>
						</section>
					)}

					<div className="mt-6 grid gap-6 xl:grid-cols-[1.35fr_.85fr]">
						<section className="rounded-3xl border border-slate-200 bg-white p-5 sm:p-6">
							<div className="flex items-start justify-between gap-4">
								<div>
									<p className="text-xs font-semibold uppercase tracking-[0.16em] text-teal-700">Tu mes</p>
									<h2 className="mt-1 text-xl font-semibold">{pending.length ? 'Esto es lo que sigue' : 'No tienes cuotas pendientes'}</h2>
									<p className="mt-1 text-xs leading-5 text-slate-400">{pending.length ? 'FamiliaHub ordena primero lo vencido y después lo que vence más pronto.' : 'Cuando todo está resuelto, no te mostramos tareas innecesarias.'}</p>
								</div>
								<Link to="/pagos" className="fh-button-ghost hidden sm:inline-flex">Ver todas<ArrowRight size={14} /></Link>
							</div>

							{pending.length ? (
								<div className="mt-5 space-y-3">
									{pending.map((row) => <PriorityQuota key={row.cuota.id} row={row} />)}
								</div>
							) : (
								<div className="mt-5 flex gap-3 rounded-2xl bg-emerald-50/80 p-4 text-emerald-800">
									<CheckCircle2 size={20} className="shrink-0" />
									<div><p className="text-sm font-semibold">Todo listo por tu lado</p><p className="mt-1 text-xs text-emerald-700/70">No tienes saldos personales pendientes en el periodo actual.</p></div>
								</div>
							)}

							<Link to="/pagos" className="fh-button-primary mt-5 w-full sm:hidden">Ir a mis pagos</Link>
						</section>

						{isAdmin ? <AdminAttentionPanel attention={adminAttention} /> : <HomeStatusPanel pagosParaValidar={pagosParaValidar} />}
					</div>

					<section className="mt-6 rounded-3xl border border-slate-200 bg-white p-5 sm:p-6">
						<div className="flex items-center gap-3">
							<IconChip><ReceiptText size={18} /></IconChip>
							<div><h2 className="font-bold">Recibos del hogar</h2><p className="text-xs text-slate-400">Total, vencimiento y reparto de cada recibo del mes.</p></div>
						</div>
						<div className="mt-5 flex flex-col gap-3 sm:flex-row">
							<Link to="/recibos" className="fh-button-secondary gap-2">Ver recibos<ArrowRight size={14} /></Link>
							{isAdmin && <Link to="/administrar?tab=servicios" className="fh-button-secondary">Configurar servicios</Link>}
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
		<Link to={`/recibos/${recibo.id}`} className="group flex items-center gap-4 rounded-2xl border border-white/80 bg-white/60 p-4 transition duration-200 hover:-translate-y-0.5 hover:border-cyan-100 hover:bg-white hover:shadow-[0_14px_30px_-20px_rgb(8_145_178/0.6)]">
			<div className={`grid size-10 shrink-0 place-items-center rounded-xl ${vencida ? 'bg-rose-50 text-rose-600' : 'bg-linear-to-br from-teal-50 to-cyan-50 text-teal-700'}`}><ReceiptText size={17} /></div>
			<div className="min-w-0 flex-1">
				<div className="flex flex-wrap items-center gap-2"><p className="truncate text-sm font-semibold">{recibo.nombre_concepto}</p><span className={`rounded-full px-2 py-1 text-[10px] font-semibold ${vencida ? 'bg-rose-50 text-rose-600' : cuota.estado === 'POR_VALIDAR' ? 'bg-amber-50 text-amber-700' : 'bg-slate-100 text-slate-500'}`}>{label}</span></div>
				<p className="mt-1 text-xs text-slate-400">{dateLabel(fechaObjetivo)} · Falta {money(cuota.saldo_pendiente)}</p>
			</div>
			<ArrowRight size={15} className="shrink-0 text-slate-300 transition group-hover:translate-x-1 group-hover:text-cyan-500" />
		</Link>
	)
}

function AdminAttentionPanel({ attention }: { attention: AdminAttention }) {
	const items = [
		{ label: 'Recibos esperando monto', count: attention.recibosEsperandoMonto, to: '/recibos' },
		{ label: 'Vencimientos por completar', count: attention.vencimientosFaltantes, to: '/recibos' },
		{ label: 'Pagos por validar', count: attention.pagosPorValidar, to: '/pagos?tab=validar' },
		{ label: 'Recibos vencidos', count: attention.recibosVencidos, to: '/recibos' },
		{ label: 'Recaudaciones fuera de fecha', count: attention.recaudacionesAtrasadas, to: '/recibos' },
	].filter((item) => item.count > 0)

	return (
		<section className="rounded-3xl border border-slate-200 bg-white p-5 sm:p-6">
			<div className="flex items-center gap-3">
				<div className={`grid size-10 place-items-center rounded-xl ${items.length ? 'bg-amber-50 text-amber-700' : 'bg-emerald-50 text-emerald-700'}`}>{items.length ? <AlertTriangle size={18} /> : <ShieldCheck size={18} />}</div>
				<div><p className="text-sm font-semibold">Necesita tu atención</p><p className="text-xs text-slate-400">{items.length ? 'Solo mostramos excepciones que requieren intervención.' : 'No hay excepciones operativas pendientes.'}</p></div>
			</div>

			{items.length ? (
				<div className="mt-5 space-y-2">
					{items.map((item) => (
						<Link key={item.label} to={item.to} className="group flex items-center justify-between rounded-xl border border-transparent bg-slate-50/80 px-4 py-3 transition hover:border-cyan-100 hover:bg-white">
							<span className="text-xs font-medium text-slate-600">{item.label}</span>
							<span className="flex items-center gap-2"><span className="grid min-w-6 place-items-center rounded-full bg-linear-to-br from-teal-500 to-cyan-600 px-2 py-1 text-[10px] font-bold text-white">{item.count}</span><ArrowRight size={13} className="text-slate-300 transition group-hover:translate-x-0.5 group-hover:text-cyan-500" /></span>
						</Link>
					))}
				</div>
			) : (
				<div className="mt-5 rounded-2xl bg-emerald-50/80 p-4"><p className="text-sm font-semibold text-emerald-800">Todo está al día ✓</p><p className="mt-1 text-xs text-emerald-700/70">FamiliaHub no necesita que hagas nada ahora.</p></div>
			)}
		</section>
	)
}

function HomeStatusPanel({ pagosParaValidar }: { pagosParaValidar: number }) {
	return (
		<section className="rounded-3xl border border-slate-200 bg-white p-5 sm:p-6">
			<div className="flex items-center gap-3"><div className={`grid size-10 place-items-center rounded-xl ${pagosParaValidar ? 'bg-amber-50 text-amber-700' : 'bg-emerald-50 text-emerald-700'}`}><ShieldCheck size={18} /></div><div><p className="text-sm font-semibold">{pagosParaValidar ? 'Necesita tu atención' : 'Estado del hogar'}</p><p className="text-xs text-slate-400">{pagosParaValidar ? 'Eres el receptor responsable de confirmar pagos.' : 'FamiliaHub mantiene tus cuotas y recibos sincronizados.'}</p></div></div>
			{pagosParaValidar ? (
				<div className="mt-5 rounded-2xl bg-amber-50 p-4"><p className="text-sm font-semibold text-amber-800">{pagosParaValidar} pago{pagosParaValidar === 1 ? '' : 's'} por validar</p><Link to="/pagos?tab=validar" className="mt-2 inline-flex items-center gap-1 text-xs font-semibold text-amber-800">Revisar pagos<ArrowRight size={14} /></Link></div>
			) : (
				<div className="mt-5 rounded-2xl bg-slate-50/80 p-4"><p className="text-xs leading-5 text-slate-500">Tú solo necesitas revisar tus cuotas y registrar un pago cuando corresponda. La administración del recibo permanece separada.</p></div>
			)}
		</section>
	)
}

function IconChip({ children }: { children: ReactNode }) {
	return <div className="grid size-10 shrink-0 place-items-center rounded-xl bg-linear-to-br from-teal-50 to-cyan-100 text-teal-700 ring-1 ring-cyan-100">{children}</div>
}

function SummaryCard({ icon, label, value, subtitle }: { icon: ReactNode; label: string; value: string; subtitle?: string }) {
	return (
		<div className="flex items-center gap-4 rounded-2xl border border-slate-200 bg-white p-4 transition duration-200 hover:-translate-y-0.5 sm:block sm:p-5">
			<IconChip>{icon}</IconChip>
			<div className="min-w-0 sm:mt-4">
				<p className="text-xs font-medium text-slate-400">{label}</p>
				<p className="mt-0.5 truncate text-lg font-semibold text-slate-800 sm:mt-1 sm:text-xl">{value}</p>
				{subtitle && <p className="mt-0.5 text-[11px] text-slate-400 sm:mt-1">{subtitle}</p>}
			</div>
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
