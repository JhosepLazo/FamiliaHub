import { Copy, ExternalLink, Search } from 'lucide-react'
import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../../lib/supabase'

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

type Datos = {
	codigo: string | null
	proveedor: string
	identificadorNombre: string
	identificador: string | null
}

export default function ConsultaProveedor({ conceptoId }: { conceptoId: string | null }) {
	const [datos, setDatos] = useState<Datos | null>(null)
	const [copiado, setCopiado] = useState(false)

	useEffect(() => {
		setDatos(null)
		setCopiado(false)
		if (!conceptoId) return
		let vigente = true

		void supabase
			.from('conceptos_pago')
			.select('proveedor:proveedores(codigo, nombre), cuenta:cuentas_servicio(identificador_valor, identificador_nombre, tipo:tipos_identificador_proveedor(nombre))')
			.eq('id', conceptoId)
			.maybeSingle()
			.then(({ data }) => {
				if (!vigente || !data?.proveedor) return
				const cuenta = data.cuenta
				setDatos({
					codigo: data.proveedor.codigo,
					proveedor: data.proveedor.nombre,
					identificadorNombre: cuenta?.tipo?.nombre ?? cuenta?.identificador_nombre ?? 'Número de suministro',
					identificador: cuenta?.identificador_valor ?? null,
				})
			})

		return () => { vigente = false }
	}, [conceptoId])

	if (!datos) return null
	const consulta = datos.codigo ? consultaPorProveedor[datos.codigo] : undefined
	if (!consulta && !datos.identificador) return null

	const copiar = () => {
		if (!datos.identificador) return
		void navigator.clipboard.writeText(datos.identificador).then(() => setCopiado(true), () => setCopiado(false))
	}

	// La copia empieza antes de abrir la pestaña: después la página pierde el foco y el navegador ya no deja copiar.
	const abrir = () => {
		copiar()
		if (consulta) window.open(consulta.url, '_blank', 'noopener,noreferrer')
	}

	return (
		<div className="mt-5 rounded-2xl border border-amber-200 bg-white p-4 text-slate-700">
			<div className="flex items-start gap-3">
				<Search size={18} className="mt-0.5 shrink-0 text-[#0f766e]" />
				<div className="min-w-0 flex-1">
					<p className="text-sm font-semibold">Consulta el monto en {datos.proveedor}</p>
					{datos.identificador ? (
						<p className="mt-1 text-xs text-slate-500">{datos.identificadorNombre}: <span className="font-mono font-semibold text-slate-700">{datos.identificador}</span></p>
					) : (
						<p className="mt-1 text-xs text-slate-500">Este servicio no tiene guardado su {datos.identificadorNombre.toLowerCase()}. <Link className="font-semibold text-[#0f766e]" to={`/servicios/${conceptoId}/editar`}>Agrégalo</Link> para copiarlo desde aquí.</p>
					)}
					<div className="mt-3 flex flex-wrap gap-2">
						{consulta && <button type="button" className="fh-button-primary flex items-center gap-2" onClick={abrir}><ExternalLink size={15} />{datos.identificador ? 'Copiar y abrir' : 'Abrir'} {datos.proveedor}</button>}
						{datos.identificador && <button type="button" className="fh-button-secondary flex items-center gap-2" onClick={copiar}><Copy size={15} />{copiado ? 'Copiado' : 'Copiar número'}</button>}
					</div>
					{consulta && <p className="mt-3 text-xs leading-5 text-slate-500">{consulta.pasos} Luego escribe abajo el total a pagar y la fecha de vencimiento.</p>}
				</div>
			</div>
		</div>
	)
}
