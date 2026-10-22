import { Smartphone, X } from 'lucide-react'
import { useState } from 'react'
import { useInstalarApp } from '../lib/instalarApp'
import { useDialogo } from './ui/Dialogo'

const CLAVE_OCULTO = 'fh-instalar-oculto'

function leerOculto() {
	try {
		return localStorage.getItem(CLAVE_OCULTO) === '1'
	} catch {
		return false
	}
}

// Invita a instalar FamiliaHub en el celular (queda con su ícono, como cualquier app). Se puede cerrar y no
// vuelve a aparecer en ese dispositivo.
export default function InstalarAppAviso() {
	const { puedeInstalar, soloInstrucciones, instalar } = useInstalarApp()
	const { confirmar } = useDialogo()
	const [oculto, setOculto] = useState(leerOculto)

	if (oculto || (!puedeInstalar && !soloInstrucciones)) return null

	const ocultar = () => {
		setOculto(true)
		try {
			localStorage.setItem(CLAVE_OCULTO, '1')
		} catch {
			// Sin almacenamiento solo se oculta mientras la página esté abierta.
		}
	}

	const alInstalar = async () => {
		if (puedeInstalar) {
			if (await instalar()) ocultar()
			return
		}
		await confirmar({
			titulo: 'Instala FamiliaHub en tu iPhone',
			mensaje: 'En Safari, toca el botón Compartir (el cuadrado con una flecha hacia arriba) y elige "Agregar a inicio". FamiliaHub quedará con su ícono, como cualquier app.',
			accion: 'Entendido',
			informativo: true,
		})
	}

	return (
		<section className="fh-entrada mt-6 flex items-center gap-3 rounded-2xl border border-cyan-100 bg-white/80 p-3 pr-2 backdrop-blur sm:p-4">
			<div className="grid size-10 shrink-0 place-items-center rounded-xl bg-linear-to-br from-teal-500 to-cyan-600 text-white"><Smartphone size={18} /></div>
			<div className="min-w-0 flex-1">
				<p className="text-sm font-semibold text-slate-800">Lleva FamiliaHub en tu celular</p>
				<p className="text-xs text-slate-500">Ábrela con un toque desde tu pantalla de inicio.</p>
			</div>
			<button type="button" onClick={() => void alInstalar()} className="fh-button-primary h-9 shrink-0 px-3 text-xs">{puedeInstalar ? 'Instalar' : 'Cómo instalar'}</button>
			<button type="button" onClick={ocultar} aria-label="No mostrar de nuevo" className="grid size-8 shrink-0 place-items-center rounded-lg text-slate-400 transition hover:bg-slate-100 hover:text-slate-600"><X size={16} /></button>
		</section>
	)
}
