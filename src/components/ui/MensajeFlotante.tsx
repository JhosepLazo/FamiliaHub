import { Info, X } from 'lucide-react'
import { useEffect, useState } from 'react'
import { createPortal } from 'react-dom'


// Errores técnicos (casi siempre en inglés) que llegan del navegador o de Supabase, en palabras simples.
const TRADUCCIONES: Array<[RegExp, string]> = [
	[/failed to fetch|networkerror|load failed|network request failed/i, 'Sin conexión. Revisa tu internet e inténtalo de nuevo.'],
	[/jwt expired|invalid jwt|refresh token|session.*(expired|missing)/i, 'Tu sesión venció. Vuelve a iniciar sesión.'],
	[/row-level security|permission denied|not authorized/i, 'No tienes permiso para hacer esto.'],
	[/duplicate key/i, 'Eso ya estaba registrado.'],
	[/payload too large|maximum allowed size|exceeded/i, 'El archivo es demasiado grande.'],
	[/mime type|invalid_mime_type/i, 'Ese tipo de archivo no está permitido.'],
	[/could not find the function|schema cache/i, 'Esta opción todavía no está activa en el servidor. Ejecuta publicar-cambios.cmd para activarla.'],
]

export function traducirMensaje(texto: string) {
	return TRADUCCIONES.find(([patron]) => patron.test(texto))?.[1] ?? texto
}

// Aviso que aparece abajo de la pantalla (encima del menú en el celular) y se va solo. Reemplaza los
// mensajes al final de la página, que en el celular quedaban fuera de la vista.
export default function MensajeFlotante({ mensaje, alCerrar }: { mensaje: string | null | undefined; alCerrar?: () => void }) {
	const [visible, setVisible] = useState<string | null>(null)

	useEffect(() => {
		if (!mensaje) {
			setVisible(null)
			return
		}
		const texto = traducirMensaje(mensaje)
		setVisible(texto)
		// Los mensajes largos se quedan más tiempo en pantalla (entre 5 y 12 segundos).
		const temporizador = setTimeout(() => {
			setVisible(null)
			alCerrar?.()
		}, Math.min(12_000, Math.max(5_000, texto.length * 70)))
		return () => clearTimeout(temporizador)
		// alCerrar suele ser una función nueva en cada render; solo importa cuando cambia el mensaje.
	}, [mensaje])

	if (!visible) return null

	return createPortal(
		<div role="status" aria-live="polite" className="pointer-events-none fixed inset-x-3 bottom-24 z-50 flex justify-center lg:inset-x-auto lg:right-8 lg:bottom-8">
			<div className="fh-aviso pointer-events-auto flex w-full max-w-md items-start gap-3 rounded-2xl bg-fh-night/95 px-4 py-3.5 text-sm text-white shadow-[0_20px_40px_-16px_rgb(7_11_20/0.7)] ring-1 ring-white/10 backdrop-blur-xl">
				<Info size={18} className="mt-0.5 shrink-0 text-cyan-300" />
				<p className="min-w-0 flex-1 leading-5">{visible}</p>
				<button type="button" aria-label="Cerrar aviso" onClick={() => { setVisible(null); alCerrar?.() }} className="-m-1 grid size-7 shrink-0 place-items-center rounded-lg text-slate-400 transition hover:bg-white/10 hover:text-white">
					<X size={15} />
				</button>
			</div>
		</div>,
		document.body,
	)
}
