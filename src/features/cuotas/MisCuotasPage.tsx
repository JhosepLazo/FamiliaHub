import { ArrowRight, ChevronRight, ReceiptText } from 'lucide-react'
import { useMemo, useState, type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import EmptyState from '../../components/ui/EmptyState'
import { cuotaEstadoLabel, dateLabel, money, periodLabel, quotaBadgeClass } from '../recibos/reciboUi'
import { useCurrentFinance, type CuotaConRecibo } from './useCurrentFinance'

type Filter = 'PENDIENTES' | 'PAGADAS' | 'TODAS'

// Pestaña "Por pagar" del módulo Pagos: las cuotas propias del periodo y el acceso a pagarlas.
export default function MisCuotasPage() {
	const { periodo, cuotasConRecibo, anteriores, resumen, loading, error } = useCurrentFinance()
	const [filter, setFilter] = useState<Filter>('PENDIENTES')

	const visible = useMemo(() => {
		if (filter === 'PENDIENTES') return cuotasConRecibo.filter(({ cuota }) => cuota.estado !== 'PAGADA' && cuota.estado !== 'ANULADA')
		if (filter === 'PAGADAS') return cuotasConRecibo.filter(({ cuota }) => cuota.estado === 'PAGADA')
		return cuotasConRecibo.filter(({ cuota }) => cuota.estado !== 'ANULADA')
	}, [filter, cuotasConRecibo])

	const payable = useMemo(
		() => [...anteriores, ...cuotasConRecibo].filter(({ cuota }) =>
			cuota.estado !== 'PAGADA'
			&& cuota.estado !== 'ANULADA'
			&& cuota.estado !== 'POR_VALIDAR'
			&& (cuota.saldo_pendiente ?? 0) > 0,
		),
		[anteriores, cuotasConRecibo],
	)
	const payAllUrl = payable.length ? `/pagar?cuotas=${payable.map(({ cuota }) => cuota.id).join(',')}` : null
	const payAllTotal = payable.reduce((sum, { cuota }) => sum + (cuota.saldo_pendiente ?? 0), 0)

	return (
		<div className="fh-entrada">
			<section className="fh-card flex flex-col gap-5 p-5 sm:p-6 lg:flex-row lg:items-center lg:justify-between">
				<div className="grid grid-cols-2 gap-x-6 gap-y-4 sm:grid-cols-4 sm:divide-x sm:divide-slate-200/70">
					<Metric label="Debes este mes" value={money(resumen.debe)} accent />
					<Metric label="Pagaste" value={money(resumen.pagado)} />
					<Metric label="Pendientes" value={String(resumen.pendientes)} />
					<Metric label="Pagadas" value={String(resumen.pagadas)} />
				</div>
				{payAllUrl && (
					<Link to={payAllUrl} className="fh-button-primary w-full lg:w-auto">
						{payable.length >= 2 ? `Pagar todo · ${money(payAllTotal)}` : `Pagar ${money(payAllTotal)}`}<ArrowRight size={16} />
					</Link>
				)}
			</section>

			<div className="mt-6 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
				<div className="inline-flex self-start rounded-xl border border-white/90 bg-white/70 p-1 shadow-sm backdrop-blur">
					<FilterButton active={filter === 'PENDIENTES'} onClick={() => setFilter('PENDIENTES')}>Pendientes</FilterButton>
					<FilterButton active={filter === 'PAGADAS'} onClick={() => setFilter('PAGADAS')}>Pagadas</FilterButton>
					<FilterButton active={filter === 'TODAS'} onClick={() => setFilter('TODAS')}>Todas</FilterButton>
				</div>
				{periodo && <p className="text-xs font-semibold text-slate-400">Periodo {String(periodo.mes).padStart(2, '0')}/{periodo.anio}</p>}
			</div>

			{loading ? (
				<div className="mt-5 grid gap-4 lg:grid-cols-2"><div className="h-52 animate-pulse rounded-3xl bg-white/60" /><div className="h-52 animate-pulse rounded-3xl bg-white/60" /></div>
			) : visible.length === 0 && !(filter === 'PENDIENTES' && anteriores.length) ? (
				<EmptyState
					className="mt-5"
					icon={<ReceiptText size={20} />}
					title={filter === 'PENDIENTES' ? 'No tienes cuotas pendientes' : filter === 'PAGADAS' ? 'Aún no tienes cuotas pagadas este mes' : 'Todavía no tienes cuotas en este periodo'}
					description={filter === 'PENDIENTES' ? 'Estás al día. Te avisaremos cuando llegue un recibo nuevo.' : 'Las cuotas aparecerán aquí cuando participes en un recibo del hogar.'}
				/>
			) : (
				<>
					{filter === 'PENDIENTES' && anteriores.length > 0 && (
						<section className="mt-5">
							<div className="flex items-baseline justify-between gap-3">
								<h2 className="text-sm font-bold text-slate-800">De meses anteriores</h2>
								<p className="text-xs font-bold text-rose-600 tabular-nums">{money(resumen.debeAnteriores)}</p>
							</div>
							<div className="mt-3 grid gap-4 lg:grid-cols-2">
								{anteriores.map((row) => <QuotaCard key={row.cuota.id} row={row} />)}
							</div>
							{visible.length > 0 && <h2 className="mt-8 text-sm font-bold text-slate-800">Este mes</h2>}
						</section>
					)}
					{visible.length > 0 && (
						<div className={`grid gap-4 lg:grid-cols-2 ${filter === 'PENDIENTES' && anteriores.length > 0 ? 'mt-3' : 'mt-5'}`}>
							{visible.map((row) => <QuotaCard key={row.cuota.id} row={row} />)}
						</div>
					)}
				</>
			)}

			{error && <p className="fh-alert mt-5">{error}</p>}
		</div>
	)
}

function QuotaCard({ row }: { row: CuotaConRecibo }) {
	const { cuota, recibo, fechaObjetivo, diasRestantes, vencida, periodoAnterior } = row
	const canPay = cuota.estado !== 'POR_VALIDAR' && cuota.estado !== 'PAGADA' && cuota.estado !== 'ANULADA' && (cuota.saldo_pendiente ?? 0) > 0
	const actionUrl = cuota.estado === 'POR_VALIDAR' ? '/pagos?tab=mis-pagos' : canPay ? `/pagar?cuotas=${cuota.id}` : `/recibos/${recibo.id}`
	const action = cuota.estado === 'POR_VALIDAR' ? 'Ver pago enviado' : canPay ? 'Pagar' : 'Ver detalle'

	return (
		<article className="fh-card group p-5 transition duration-200 hover:-translate-y-0.5 sm:p-6">
			<div className="flex items-start justify-between gap-4">
				<div className="min-w-0">
					<div className="flex flex-wrap items-center gap-2">
						<Link to={`/recibos/${recibo.id}`} className="truncate text-lg font-bold text-slate-900 transition hover:text-brand">{recibo.nombre_concepto}</Link>
						<span className={`fh-pill ${quotaBadgeClass(cuota.estado)}`}>{cuotaEstadoLabel[cuota.estado]}</span>
						{vencida && <span className="fh-pill bg-rose-50 text-rose-600 ring-rose-200/70">Vencida</span>}
						{periodoAnterior && <span className="fh-pill bg-slate-100 text-slate-600 ring-slate-200">{mayuscula(periodLabel(periodoAnterior.anio, periodoAnterior.mes))}</span>}
					</div>
					<p className="mt-1 text-xs text-slate-400">{recibo.proveedor_nombre}</p>
				</div>
				<Link to={`/recibos/${recibo.id}`} aria-label="Ver recibo" className="grid size-8 place-items-center rounded-lg text-slate-300 transition hover:bg-slate-100 hover:text-slate-600"><ChevronRight size={18} /></Link>
			</div>

			<div className="mt-5 flex items-end justify-between gap-4">
				<div>
					<p className="text-[11px] font-bold uppercase tracking-wide text-slate-400">Te falta</p>
					<p className={`mt-0.5 text-3xl font-extrabold tracking-tight tabular-nums ${(cuota.saldo_pendiente ?? 0) > 0 ? 'text-slate-900' : 'text-emerald-600'}`}>{money(cuota.saldo_pendiente)}</p>
				</div>
				<div className="text-right text-xs text-slate-500">
					<p>Tu cuota <span className="font-bold text-slate-700 tabular-nums">{money(cuota.monto_asignado)}</span></p>
					<p className="mt-0.5">Recibo <span className="font-bold text-slate-700 tabular-nums">{money(recibo.monto_total)}</span></p>
				</div>
			</div>

			<div className="mt-5 flex flex-col gap-3 border-t border-slate-200/70 pt-4 sm:flex-row sm:items-center sm:justify-between">
				<div>
					<p className="text-[11px] font-bold uppercase tracking-wide text-slate-400">Tu fecha límite</p>
					<p className={`mt-0.5 text-sm font-bold ${vencida ? 'text-rose-600' : 'text-slate-700'}`}>{dateLabel(fechaObjetivo)}<span className="font-medium text-slate-400">{relativeDate(diasRestantes)}</span></p>
				</div>
				<Link to={actionUrl} className={canPay ? 'fh-button-primary' : 'fh-button-secondary'}>{action}{canPay && <ArrowRight size={15} />}</Link>
			</div>
		</article>
	)
}

function Metric({ label, value, accent = false }: { label: string; value: string; accent?: boolean }) {
	return (
		<div className="min-w-0 sm:px-6 sm:first:pl-0">
			<p className="text-[11px] font-bold uppercase tracking-wide text-slate-400">{label}</p>
			<p className={`mt-1 truncate text-xl font-extrabold tracking-tight tabular-nums ${accent ? 'text-brand' : 'text-slate-800'}`}>{value}</p>
		</div>
	)
}

function FilterButton({ active, onClick, children }: { active: boolean; onClick: () => void; children: ReactNode }) {
	return <button type="button" onClick={onClick} className={`rounded-lg px-4 py-2 text-xs font-bold transition active:scale-[0.97] ${active ? 'bg-slate-900 text-white shadow-sm' : 'text-slate-500 hover:bg-white hover:text-slate-900'}`}>{children}</button>
}

function mayuscula(texto: string) {
	return texto.charAt(0).toUpperCase() + texto.slice(1)
}

function relativeDate(days: number | null) {
	if (days == null) return ''
	if (days < 0) return ` · hace ${Math.abs(days)} día${Math.abs(days) === 1 ? '' : 's'}`
	if (days === 0) return ' · hoy'
	if (days === 1) return ' · mañana'
	return ` · en ${days} días`
}
