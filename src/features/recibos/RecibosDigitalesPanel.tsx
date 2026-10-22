import { ChevronRight, MailCheck } from 'lucide-react'
import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { useEnVivo } from '../../lib/enVivo'
import { supabase } from '../../lib/supabase'
import type { Enums, Tables } from '../../types/database'
import { dateLabel, money } from './reciboUi'

type ReciboDigital = Pick<Tables<'recibos_digitales'>, 'id' | 'proveedor_codigo' | 'monto' | 'fecha_vencimiento' | 'estado' | 'detalle' | 'recibo_id' | 'created_at'>
	& { recibo: Pick<Tables<'recibos'>, 'estado'> | null }

const proveedorLabel: Record<string, string> = { SEDAPAL: 'SEDAPAL', LUZ_DEL_SUR: 'Luz del Sur', CALIDDA: 'Cálidda' }

const estadoLabel: Record<Enums<'estado_recibo_digital'>, string> = {
	CONFIRMADO: 'Confirmado solo',
	EN_ESPERA: 'En espera',
	REVISAR: 'Revisar',
	IGNORADO: 'Ignorado',
}

const estadoClass: Record<Enums<'estado_recibo_digital'>, string> = {
	CONFIRMADO: 'bg-emerald-50 text-emerald-700 ring-emerald-200/70',
	EN_ESPERA: 'bg-sky-50 text-sky-700 ring-sky-200/70',
	REVISAR: 'bg-amber-50 text-amber-700 ring-amber-200/70',
	IGNORADO: 'bg-slate-100 text-slate-500 ring-slate-200',
}

// Solo para administradores: muestra lo que el script de Gmail leyó en los últimos recibos digitales y qué hizo
// FamiliaHub con cada uno (confirmarlo solo, esperar al recibo del mes o dejarlo para revisar a mano).
export default function RecibosDigitalesPanel({ familiaId }: { familiaId: string }) {
	const [filas, setFilas] = useState<ReciboDigital[] | null>(null)
	const [version, setVersion] = useState(0)
	// Cuando un recibo digital confirma un monto cambia el recibo: se vuelve a leer la lista.
	useEnVivo(() => setVersion((actual) => actual + 1))

	useEffect(() => {
		let vigente = true
		void supabase
			.from('recibos_digitales')
			.select('id, proveedor_codigo, monto, fecha_vencimiento, estado, detalle, recibo_id, created_at, recibo:recibos(estado)')
			.eq('familia_id', familiaId)
			.order('created_at', { ascending: false })
			.limit(6)
			.then(({ data }) => { if (vigente) setFilas(data ?? []) })
		return () => { vigente = false }
	}, [familiaId, version])

	if (filas === null) return null

	return (
		<section className="mt-8 rounded-3xl border border-slate-200 bg-white p-5 sm:p-6">
			<div className="flex items-center gap-3">
				<div className="grid size-10 place-items-center rounded-xl bg-emerald-50 text-brand"><MailCheck size={18} /></div>
				<div>
					<h2 className="text-sm font-semibold">Recibos digitales</h2>
					<p className="text-xs text-slate-400">Montos que llegaron por correo y se confirmaron sin escribirlos.</p>
				</div>
			</div>

			{filas.length === 0 ? (
				<p className="mt-4 text-sm leading-6 text-slate-500">Aún no llega ningún recibo digital. Cuando SEDAPAL, Luz del Sur o Cálidda envíen el suyo al Gmail de la familia, aquí verás si el monto se confirmó solo.</p>
			) : (
				<ul className="mt-4 divide-y divide-slate-100">
					{filas.map((fila) => {
						// Uno para revisar deja de estar pendiente cuando el administrador ya confirmó el monto en la app.
						const revisado = fila.estado === 'REVISAR' && fila.recibo != null && fila.recibo.estado !== 'ESPERANDO_MONTO'
						const contenido = (
							<>
								<div className="min-w-0">
									<div className="flex flex-wrap items-center gap-2">
										<p className="text-sm font-semibold">{proveedorLabel[fila.proveedor_codigo] ?? fila.proveedor_codigo}</p>
										<span className={`fh-pill ${revisado ? estadoClass.IGNORADO : estadoClass[fila.estado]}`}>{revisado ? 'Revisado' : estadoLabel[fila.estado]}</span>
									</div>
									<p className="mt-1 text-xs text-slate-400">{money(fila.monto)} · vence {dateLabel(fila.fecha_vencimiento)}</p>
									{fila.detalle && !revisado && <p className="mt-1 text-xs leading-5 text-slate-500">{fila.detalle}</p>}
								</div>
								{fila.recibo_id && <ChevronRight className="shrink-0 text-slate-300 transition group-hover:translate-x-1 group-hover:text-slate-500" size={16} />}
							</>
						)
						return (
							<li key={fila.id}>
								{fila.recibo_id
									? <Link to={`/recibos/${fila.recibo_id}`} className="group flex items-center justify-between gap-3 py-3">{contenido}</Link>
									: <div className="flex items-center justify-between gap-3 py-3">{contenido}</div>}
							</li>
						)
					})}
				</ul>
			)}
		</section>
	)
}
