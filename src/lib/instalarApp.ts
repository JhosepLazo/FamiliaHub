import { useEffect, useState } from 'react'

// Instalar FamiliaHub como app en el celular. Android/Chrome avisa con "beforeinstallprompt" apenas carga la
// página, así que el evento se guarda aquí desde el inicio. En iPhone no existe ese evento: se explica cómo
// agregarla desde el botón Compartir de Safari.

type EventoInstalacion = Event & { prompt: () => Promise<void>; userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }> }

let eventoGuardado: EventoInstalacion | null = null
const oyentes = new Set<() => void>()
const avisar = () => oyentes.forEach((oyente) => oyente())

if (typeof window !== 'undefined') {
	window.addEventListener('beforeinstallprompt', (evento) => {
		evento.preventDefault()
		eventoGuardado = evento as EventoInstalacion
		avisar()
	})
	window.addEventListener('appinstalled', () => {
		eventoGuardado = null
		avisar()
	})
}

function yaInstalada() {
	return window.matchMedia('(display-mode: standalone)').matches || (navigator as Navigator & { standalone?: boolean }).standalone === true
}

function esIPhone() {
	return /iphone|ipad|ipod/i.test(navigator.userAgent)
}

export function useInstalarApp() {
	const [, setVersion] = useState(0)

	useEffect(() => {
		const oyente = () => setVersion((actual) => actual + 1)
		oyentes.add(oyente)
		return () => { oyentes.delete(oyente) }
	}, [])

	const instalada = yaInstalada()
	return {
		// Android/Chrome: se puede abrir el cuadro de instalación del sistema.
		puedeInstalar: !instalada && eventoGuardado !== null,
		// iPhone en Safari: hay que explicar los pasos.
		soloInstrucciones: !instalada && eventoGuardado === null && esIPhone(),
		instalar: async () => {
			if (!eventoGuardado) return false
			await eventoGuardado.prompt()
			const { outcome } = await eventoGuardado.userChoice
			eventoGuardado = null
			avisar()
			return outcome === 'accepted'
		},
	}
}
