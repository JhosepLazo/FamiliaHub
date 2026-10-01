import { CheckCircle2, ChevronRight, CircleDollarSign, Clock3, ReceiptText, WalletCards } from 'lucide-react'
import { useMemo, useState, type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { cuotaEstadoLabel, dateLabel, money, quotaBadgeClass } from '../recibos/reciboUi'
import { useCurrentFinance, type CuotaConRecibo } from './useCurrentFinance'

type Filter = 'PENDIENTES' | 'PAGADAS' | 'TODAS'

export default function MisCuotasPage() {
	const { periodo, cuotasConRecibo, resumen, loading, error } = useCurrentFinance()
	const [filter, setFilter] = useState<Filter>('PENDIENTES')

	const visible = useMemo(() => {
		if (filter === 'PENDIENTES') return cuotasConRecibo.filter(({ cuota }) => cuota.estado !== 'PAGADA' && cuota.estado !== 'ANULADA')
		if (filter === 'PAGADAS') return cuotasConRecibo.filter(({ cuota }) => cuota.estado === 'PAGADA')
		return cuotasConRecibo.filter(({ cuota }) => cuota.estado !== 'ANULADA')
	}, [filter, cuotasConRecibo])

	return (
		<div>
			<div>
				<p className="text-sm font-semibold text-[#0f766e]">Personal</p>
				<h1 className="mt-1 text-3xl font-semibold tracking-tight">Mis cuotas</h1>
				<p className="mt-2 max-w-2xl text-sm leading-6 text-slate-500">Aquí solo aparece lo que te corresponde. El total del recibo sigue visible para que siempre tengas contexto.</p>
			</div>

			<div className="mt-7 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
				<SummaryCard icon={<CircleDollarSign />} label="Debes este mes" value={money(resumen.debe)} accent />
				<SummaryCard icon={<WalletCards />} label="Pagaste" value={money(resumen.pagado)} />
				<SummaryCard icon={<Clock3 />} label="Pendientes" value={String(resumen.pendientes)} />
				<SummaryCard icon={<CheckCircle2 />} label="Pagadas" value={String(resumen.pagadas)} />
			</div>

			<div className="mt-7 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
				<div className="flex rounded-2xl border border-slate-200 bg-white p-1">
					<FilterButton active={filter === 'PENDIENTES'} onClick={() => setFilter('PENDIENTES')}>Pendientes</FilterButton>
					<FilterButton active={filter === 'PAGADAS'} onClick={() => setFilter('PAGADAS')}>Pagadas</FilterButton>
					<FilterButton active={filter === 'TODAS'} onClick={() => setFilter('TODAS')}>Todas</FilterButton>
				</div>
				{periodo && <p className="text-xs font-medium text-slate-400">Periodo actual · {String(periodo.mes).padStart(2, '0')}/{periodo.anio}</p>}
			</div>

			{loading ? (
				<div className="mt-6 grid gap-4 lg:grid-cols-2"><div className="h-52 animate-pulse rounded-3xl bg-white" /><div className="h-52 animate-pulse rounded-3xl bg-white" /></div>
			) : visible.length === 0 ? (
				<section className="mt-6 rounded-3xl border border-dashed border-slate-300 bg-white p-8 text-center">
					<div className="mx-auto grid size-12 place-items-center rounded-2xl bg-emerald-50 text-[#0f766e]"><ReceiptText /></div>
					<h2 className="mt-4 text-lg font-semibold">{filter === 'PENDIENTES' ? 'No tienes cuotas pendientes' : filter === 'PAGADAS' ? 'Aún no tienes cuotas pagadas este mes' : 'Todavía no tienes cuotas en este periodo'}</h2>
					<p className="mx-auto mt-2 max-w-lg text-sm leading-6 text-slate-500">{filter === 'PENDIENTES' ? 'Cuando todo está pagado, FamiliaHub deja de ponerte tareas innecesarias.' : 'Las cuotas aparecerán aquí cuando participes en un recibo del hogar.'}</p>
				</section>
			) : (
				<div className="mt-6 grid gap-4 lg:grid-cols-2">
					{visible.map((row) => <QuotaCard key={row.cuota.id} row={row} />)}
				</div>
			)}

			{error && <p className="fh-alert mt-5">{error}</p>}
		</div>
	)
}

function QuotaCard({ row }: { row: CuotaConRecibo }) {
	const { cuota, recibo, fechaObjetivo, diasRestantes, vencida } = row
	const action = cuota.estado === 'POR_VALIDAR'
		? 'Ver pago enviado'
		: cuota.estado === 'PAGADA'
			? 'Ver detalle'
			: (cuota.saldo_pendiente ?? 0) > 0
				? 'Pagar saldo'
				: 'Ver detalle'

	return (
		<Link to={`/recibos/${recibo.id}`} className="group rounded-3xl border border-slate-200 bg-white p-5 transition hover:border-slate-300 sm:p-6">
			<div className="flex items-start justify-between gap-4">
				<div className="min-w-0">
					<div className="flex flex-wrap items-center gap-2">
						<h2 className="truncate text-lg font-semibold">{recibo.nombre_concepto}</h2>
						<span className={`rounded-full px-2.5 py-1 text-[10px] font-semibold ${quotaBadgeClass(cuota.estado)}`}>{cuotaEstadoLabel[cuota.estado]}</span>
						{vencida && <span className="rounded-full bg-rose-50 px-2.5 py-1 text-[10px] font-semibold text-rose-600">Vencida</span>}
					</div>
					<p className="mt-1 text-xs text-slate-400">{recibo.proveedor_nombre}</p>
				</div>
				<ChevronRight size={18} className="shrink-0 text-slate-300 transition group-hover:translate-x-1 group-hover:text-slate-500" />
			</div>

			<div className="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-3">
				<Data label="Total recibo" value={money(recibo.monto_total)} />
				<Data label="Tu cuota" value={money(cuota.monto_asignado)} accent />
				<Data label="Te falta" value={money(cuota.saldo_pendiente)} wideMobile />
			</div>

			<div className="mt-5 flex flex-col gap-3 border-t border-slate-100 pt-4 sm:flex-row sm:items-center sm:justify-between">
				<div>
					<p className="text-[10px] font-semibold uppercase tracking-wide text-slate-400">Tu fecha límite</p>
					<p className={`mt-1 text-xs font-semibold ${vencida ? 'text-rose-600' : 'text-slate-600'}`}>{dateLabel(fechaObjetivo)}{relativeDate(diasRestantes)}</p>
				</div>
				<span className="text-xs font-semibold text-[#0f766e]">{action}</span>
			</div>
		</Link>
	)
}

function SummaryCard({ icon, label, value, accent = false }: { icon: ReactNode; label: string; value: string; accent?: boolean }) {
	return (
		<div className={`rounded-2xl border p-5 ${accent ? 'border-emerald-100 bg-emerald-50/60' : 'border-slate-200 bg-white'}`}>
			<div className={accent ? 'text-[#0f766e]' : 'text-slate-400'}>{icon}</div>
			<p className="mt-5 text-xs font-medium text-slate-400">{label}</p>
			<p className={`mt-1 text-xl font-semibold ${accent ? 'text-[#0f766e]' : 'text-slate-800'}`}>{value}</p>
		</div>
	)
}

function Data({ label, value, accent = false, wideMobile = false }: { label: string; value: string; accent?: boolean; wideMobile?: boolean }) {
	return <div className={`rounded-2xl p-3 ${accent ? 'bg-emerald-50 text-[#0f766e]' : 'bg-slate-50 text-slate-700'} ${wideMobile ? 'col-span-2 sm:col-span-1' : ''}`}><p className="text-[10px] font-semibold uppercase tracking-wide opacity-60">{label}</p><p className="mt-1 text-sm font-semibold">{value}</p></div>
}

function FilterButton({ active, onClick, children }: { active: boolean; onClick: () => void; children: ReactNode }) {
	return <button type="button" onClick={onClick} className={`rounded-xl px-4 py-2 text-xs font-semibold transition ${active ? 'bg-[#0f766e] text-white' : 'text-slate-500 hover:bg-slate-50'}`}>{children}</button>
}

function relativeDate(days: number | null) {
	if (days == null) return ''
	if (days < 0) return ` · hace ${Math.abs(days)} día${Math.abs(days) === 1 ? '' : 's'}`
	if (days === 0) return ' · hoy'
	if (days === 1) return ' · mañana'
	return ` · en ${days} días`
}
