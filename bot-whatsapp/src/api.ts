import { TIMEOUT_HTTP_MS } from "./config.ts"

export type Respuesta = {
	texto: string
	menciones: string[]
}

export type ResultadoMensaje = {
	respuesta: Respuesta | null
	grupoVinculado: boolean
}

export type Aviso = {
	id: string
	grupoId: string
	texto: string
	menciones: string[]
}

export type DatosMensaje = {
	grupoId: string
	remitenteIds: string[]
	texto: string
	mencionaBot: boolean
	respondeBot: boolean
}

export class ErrorApi extends Error {
	status: number

	constructor(status: number, mensaje: string) {
		super(mensaje)
		this.name = "ErrorApi"
		this.status = status
	}
}

type Fetch = typeof fetch

function textos(valor: unknown) {
	return Array.isArray(valor) ? valor.filter((item): item is string => typeof item === "string") : []
}

export class ClienteFamiliaHub {
	private url: string
	private secreto: string
	private fetchImpl: Fetch

	constructor(url: string, secreto: string, fetchImpl: Fetch = fetch) {
		this.url = url
		this.secreto = secreto
		this.fetchImpl = fetchImpl
	}

	private async llamar(cuerpo: Record<string, unknown>, timeoutMs = TIMEOUT_HTTP_MS): Promise<Record<string, unknown>> {
		const respuesta = await this.fetchImpl(this.url, {
			method: "POST",
			headers: {
				"content-type": "application/json",
				"x-bot-secret": this.secreto,
			},
			body: JSON.stringify(cuerpo),
			signal: AbortSignal.timeout(timeoutMs),
		})

		if (!respuesta.ok) {
			let detalle = ""
			try {
				const error = await respuesta.json()
				detalle = typeof error?.error === "string" ? error.error : ""
			} catch {
				// Cuerpo no JSON: basta con el código HTTP.
			}
			throw new ErrorApi(respuesta.status, `FamiliaHub respondió ${respuesta.status}${detalle ? `: ${detalle}` : ""}`)
		}

		const datos = await respuesta.json()
		return datos && typeof datos === "object" ? datos as Record<string, unknown> : {}
	}

	async mensaje(datos: DatosMensaje, timeoutMs: number): Promise<ResultadoMensaje> {
		const resultado = await this.llamar({ accion: "mensaje", ...datos }, timeoutMs)
		const respuesta = resultado.respuesta as Record<string, unknown> | null | undefined

		return {
			respuesta: respuesta && typeof respuesta.texto === "string" && respuesta.texto.trim()
				? { texto: respuesta.texto, menciones: textos(respuesta.menciones) }
				: null,
			grupoVinculado: resultado.grupoVinculado !== false,
		}
	}

	async tomarAvisos(limite: number): Promise<Aviso[]> {
		const resultado = await this.llamar({ accion: "avisos_tomar", limite })
		const avisos = Array.isArray(resultado.avisos) ? resultado.avisos : []

		return avisos
			.filter((aviso): aviso is Record<string, unknown> => Boolean(aviso) && typeof aviso === "object")
			.filter((aviso) => typeof aviso.id === "string" && typeof aviso.grupoId === "string" && typeof aviso.texto === "string")
			.map((aviso) => ({
				id: aviso.id as string,
				grupoId: aviso.grupoId as string,
				texto: aviso.texto as string,
				menciones: textos(aviso.menciones),
			}))
	}

	async marcarAviso(id: string, enviado: boolean, error: string | null = null) {
		await this.llamar({ accion: "avisos_marcar", id, enviado, error })
	}

	async grupoSalida(grupoId: string) {
		await this.llamar({ accion: "grupo_salida", grupoId })
	}

	async heartbeat(version: string) {
		await this.llamar({ accion: "heartbeat", version })
	}
}
