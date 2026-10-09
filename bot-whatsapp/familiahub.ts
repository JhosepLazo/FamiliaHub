// Cliente de la Edge Function bot-whatsapp. Es la única puerta del bot hacia FamiliaHub.

import type { Remitente } from './mensajes.ts'

export type Aviso = {
	id: string
	grupoId: string
	mensaje: string
}

export type ClienteFamiliaHub = ReturnType<typeof crearClienteFamiliaHub>

export function crearClienteFamiliaHub(url: string, secreto: string) {
	async function llamar<T>(accion: string, datos: Record<string, unknown> = {}): Promise<T> {
		const respuesta = await fetch(url, {
			method: 'POST',
			headers: {
				'Content-Type': 'application/json',
				'x-familiahub-bot-secret': secreto,
			},
			body: JSON.stringify({ accion, ...datos }),
			signal: AbortSignal.timeout(15_000),
		})

		const cuerpo = await respuesta.json().catch(() => ({}))
		if (!respuesta.ok) throw new Error(cuerpo.error ?? `HTTP ${respuesta.status}`)
		return cuerpo as T
	}

	return {
		async responder(datos: Remitente & { grupoId: string; texto: string }) {
			const { respuesta } = await llamar<{ respuesta: string | null }>('mensaje', datos)
			return respuesta
		},
		async avisosPendientes() {
			const { avisos } = await llamar<{ avisos: Aviso[] }>('avisos_pendientes')
			return avisos
		},
		async marcarAviso(avisoId: string, enviado: boolean, error?: string) {
			await llamar('marcar_aviso', { avisoId, enviado, error })
		},
	}
}
