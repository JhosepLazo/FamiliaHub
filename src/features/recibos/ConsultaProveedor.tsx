import { ArrowRight, Check, Copy, ExternalLink, History, Search } from 'lucide-react'
import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import type { Tables } from '../../types/database'
import { dateLabel, money } from './reciboUi'

// Páginas oficiales donde se ve el monto con el número de suministro. Las tres exigen resolver un CAPTCHA,
// así que la consulta la hace una persona: FamiliaHub solo copia el número y abre la página.
const consultaPorProveedor: Record<string, { url: string; pasos: string }> = {
	SEDAPAL: {
		url: 'https://webapp16.sedapal.com.pe/socv/#/suministro',
		pasos: 'Pega el número de suministro, marca "No soy un robot" y consulta.',
	},
	LUZ_DEL_SUR: {
		url: 'https://www.luzdelsur.pe/es/VerPagarRecibo',
		pasos: 'Elige "Con Nº de suministro", pega el número, completa la verificación y consulta.',
	},
	CALIDDA: {
		url: 'https://appadmin.calidda.com.pe/frontov/withoutlogin',
		pasos: 'Pega el número de cliente, completa la verificación y consulta.',
	},
}

type DatosConsulta = {
	proveedor: string
	identificadorNombre: string
	identificador: string | null
	url: string | null
	pasos: string | null
	ultimoMonto: number | null
	ultimoVencimiento: string | null
}

function useDatosConsulta(conceptoId: string | null) {
	const [datos, setDatos] = useState<DatosConsulta | null>(null)

	useEffect(() => {
		setDatos(null)
		if (!conceptoId) return
		let vigente = true

		void Promise.all([
			supabase
				.from('conceptos_pago')
				.select('proveedor:proveedores(codigo, nombre), cuenta:cuentas_servicio(identificador_valor, identificador_nombre, tipo:tipos_identificador_proveedor(nombre))')
				.eq('id', conceptoId)
				.maybeSingle(),
			// Referencia real del mes anterior (no una estimación): ayuda a notar un monto fuera de lo normal.
			supabase
				.from('recibos')
				.select('monto_total, fecha_vencimiento')
				.eq('concepto_id', conceptoId)
				.neq('estado', 'ANULADO')
				.not('monto_total', 'is', null)
				.order('monto_confirmado_at', { ascending: false, nullsFirst: false })
				.limit(1)
				.maybeSingle(),
		]).then(([{ data }, { data: anterior }]) => {
			if (!vigente || !data?.proveedor) return
			const cuenta = data.cuenta
			const consulta = data.proveedor.codigo ? consultaPorProveedor[data.proveedor.codigo] : undefined
			setDatos({
				proveedor: data.proveedor.nombre,
				identificadorNombre: cuenta?.tipo?.nombre ?? cuenta?.identificador_nombre ?? 'Número de suministro',
				identificador: cuenta?.identificador_valor ?? null,
				url: consulta?.url ?? null,
				pasos: consulta?.pasos ?? null,
				ultimoMonto: anterior?.monto_total ?? null,
				ultimoVencimiento: anterior?.fecha_vencimiento ?? null,
			})
		})

		return () => { vigente = false }
	}, [conceptoId])

	return datos
}

function useAcciones(datos: DatosConsulta | null) {
	const [copiado, setCopiado] = useState(false)

	const copiar = () => {
		if (!datos?.identificador) return
		void navigator.clipboard.writeText(datos.identificador).then(() => setCopiado(true), () => setCopiado(false))
	}

	// La copia empieza antes de abrir la pestaña: después la página pierde el foco y el navegador ya no deja copiar.
	const abrir = () => {
		copiar()
		if (datos?.url) window.open(datos.url, '_blank', 'noopener,noreferrer')
	}

	return { copiado, copiar, abrir }
}

export default function ConsultaProveedor({ conceptoId }: { conceptoId: string | null }) {
	const datos = useDatosConsulta(conceptoId)
	const { copiado, copiar, abrir } = useAcciones(datos)

	if (!datos || (!datos.url && !datos.identificador)) return null

	return (
		<div className="mt-5 rounded-2xl border border-cyan-100 bg-white/80 p-4 text-slate-700 shadow-[0_12px_30px_-20px_rgb(8_145_178/0.6)] backdrop-blur">
			<div className="flex items-start gap-3">
				<div className="grid size-9 shrink-0 place-items-center rounded-xl bg-linear-to-br from-teal-500 to-cyan-600 text-white shadow-[0_0_18px_-4px_rgb(34_211_238/0.7)]"><Search size={16} /></div>
				<div className="min-w-0 flex-1">
					<p className="text-sm font-semibold">Consulta el monto en {datos.proveedor}</p>
					{datos.identificador ? (
						<p className="mt-1 text-xs text-slate-500">{datos.identificadorNombre}: <span className="font-mono font-semibold tracking-wide text-slate-800">{datos.identificador}</span></p>
					) : (
						<p className="mt-1 text-xs text-slate-500">Este servicio no tiene guardado su {datos.identificadorNombre.toLowerCase()}. <Link className="font-semibold text-teal-700" to={`/servicios/${conceptoId}/editar`}>Agrégalo</Link> para copiarlo desde aquí.</p>
					)}
					{datos.ultimoMonto != null && (
						<p className="mt-2 inline-flex items-center gap-1.5 rounded-full bg-slate-100/80 px-2.5 py-1 text-[11px] font-medium text-slate-500">
							<History size={12} />Último monto: {money(datos.ultimoMonto)}{datos.ultimoVencimiento ? ` · venció ${dateLabel(datos.ultimoVencimiento)}` : ''}
						</p>
					)}
					<div className="mt-3 flex flex-wrap gap-2">
						{datos.url && <button type="button" className="fh-button-primary gap-2" onClick={abrir}><ExternalLink size={15} />{datos.identificador ? 'Copiar y abrir' : 'Abrir'} {datos.proveedor}</button>}
						{datos.identificador && <button type="button" className="fh-button-secondary gap-2" onClick={copiar}>{copiado ? <Check size={15} /> : <Copy size={15} />}{copiado ? 'Copiado' : 'Copiar número'}</button>}
					</div>
					{datos.pasos && <p className="mt-3 text-xs leading-5 text-slate-500">{datos.pasos} Luego escribe abajo el total a pagar y la fecha de vencimiento.</p>}
				</div>
			</div>
		</div>
	)
}

// Fila compacta para Inicio: un recibo que espera monto, con su consulta a un clic.
export function ConsultaRapida({ recibo }: { recibo: Tables<'recibos'> }) {
	const datos = useDatosConsulta(recibo.concepto_id)
	const { copiado, abrir } = useAcciones(datos)

	return (
		<div className="flex flex-col gap-3 rounded-2xl border border-white/80 bg-white/70 p-4 sm:flex-row sm:items-center">
			<div className="min-w-0 flex-1">
				<p className="truncate text-sm font-semibold">{recibo.nombre_concepto}</p>
				<p className="mt-0.5 truncate text-xs text-slate-400">
					{recibo.proveedor_nombre}
					{datos?.identificador ? ` · ${datos.identificador}` : ''}
					{datos?.ultimoMonto != null ? ` · último ${money(datos.ultimoMonto)}` : ''}
				</p>
			</div>
			<div className="flex shrink-0 gap-2">
				{datos?.url && (
					<button type="button" className="fh-button-secondary h-9 gap-1.5 px-3 text-xs" onClick={abrir}>
						{copiado ? <Check size={14} /> : <ExternalLink size={14} />}Consultar
					</button>
				)}
				<Link to={`/recibos/${recibo.id}`} className="fh-button-primary h-9 gap-1.5 px-3 text-xs">Registrar<ArrowRight size={14} /></Link>
			</div>
		</div>
	)
}
