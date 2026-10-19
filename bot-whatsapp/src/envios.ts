import type { AnyMessageContent, MiscMessageGenerationOptions, WAMessage } from "baileys"
import type { Logger } from "pino"
import type { Aviso, ClienteFamiliaHub } from "./api.ts"
import {
	AVISOS_POR_SONDEO,
	COLA_MAX_PARA_SONDEO,
	EDAD_MAX_MENSAJE_S,
	ESCRIBIENDO_MAX_MS,
	ESCRIBIENDO_MIN_MS,
	HEARTBEAT_MS,
	INTERVALO_MIN_ENVIO_MS,
	RESERVA_AVISO_MS,
	SONDEO_AVISOS_MS,
} from "./config.ts"
import { aleatorioEntre, esperar } from "./control.ts"

export type SocketEnvio = {
	sendPresenceUpdate(tipo: "composing" | "paused", jid: string): Promise<void>
	sendMessage(jid: string, contenido: AnyMessageContent, opciones?: MiscMessageGenerationOptions): Promise<unknown>
}

type Envio = {
	grupoId: string
	texto: string
	menciones: string[]
	citado?: WAMessage
	avisoId?: string
	encoladoEn: number
}

type Marca = {
	id: string
	enviado: boolean
	error: string | null
}

export type OpcionesCola = {
	obtenerSocket: () => SocketEnvio | null
	estaConectado: () => boolean
	api: Pick<ClienteFamiliaHub, "marcarAviso">
	logger: Logger
	prepararEnvio?: (grupoId: string) => Promise<void>
}

export function grupoCorto(grupoId: string) {
	return `${grupoId.slice(0, 6)}…`
}

function mensajeDeError(error: unknown) {
	return error instanceof Error ? error.message : String(error)
}

export class ColaEnvios {
	private opciones: OpcionesCola
	private pendientes: Envio[] = []
	private marcasPendientes: Marca[] = []
	private procesando = false
	private ultimoEnvio = 0

	constructor(opciones: OpcionesCola) {
		this.opciones = opciones
	}

	get tamano() {
		return this.pendientes.length
	}

	responder(grupoId: string, texto: string, menciones: string[], citado?: WAMessage) {
		this.pendientes.push({ grupoId, texto, menciones, citado, encoladoEn: Date.now() })
		void this.procesar()
	}

	encolarAviso(aviso: Aviso) {
		if (this.pendientes.some((envio) => envio.avisoId === aviso.id)) return

		this.pendientes.push({
			grupoId: aviso.grupoId,
			texto: aviso.texto,
			menciones: aviso.menciones,
			avisoId: aviso.id,
			encoladoEn: Date.now(),
		})
		void this.procesar()
	}

	reanudar() {
		void this.procesar()
	}

	// Reintenta las confirmaciones que no llegaron a FamiliaHub para no reenviar avisos ya publicados.
	async reintentarMarcas() {
		const marcas = this.marcasPendientes.splice(0)

		for (const marca of marcas) {
			try {
				await this.opciones.api.marcarAviso(marca.id, marca.enviado, marca.error)
			} catch (error) {
				this.guardarMarca(marca)
				this.opciones.logger.warn({ err: mensajeDeError(error) }, "No se pudo confirmar un aviso; se reintentará")
			}
		}
	}

	private guardarMarca(marca: Marca) {
		this.marcasPendientes.push(marca)
		if (this.marcasPendientes.length > 50) this.marcasPendientes.shift()
	}

	private async marcar(id: string, enviado: boolean, error: string | null) {
		try {
			await this.opciones.api.marcarAviso(id, enviado, error)
		} catch (fallo) {
			this.guardarMarca({ id, enviado, error })
			this.opciones.logger.warn({ err: mensajeDeError(fallo) }, "No se pudo confirmar un aviso; se reintentará")
		}
	}

	// Un aviso sin enviar a tiempo se descarta sin marcarlo: al vencer su reserva vuelve a tomarse.
	private vencido(envio: Envio) {
		const edad = Date.now() - envio.encoladoEn
		return envio.avisoId ? edad > RESERVA_AVISO_MS - 60_000 : edad > EDAD_MAX_MENSAJE_S * 1_000
	}

	private async procesar() {
		if (this.procesando) return
		this.procesando = true

		try {
			while (this.pendientes.length && this.opciones.estaConectado()) {
				const socket = this.opciones.obtenerSocket()
				if (!socket) break

				const envio = this.pendientes.shift()!
				if (this.vencido(envio)) {
					this.opciones.logger.warn({ grupo: grupoCorto(envio.grupoId), aviso: Boolean(envio.avisoId) }, "Envío descartado por antigüedad")
					continue
				}

				await this.enviar(socket, envio)
			}
		} finally {
			this.procesando = false
		}
	}

	private async enviar(socket: SocketEnvio, envio: Envio) {
		const espera = this.ultimoEnvio + INTERVALO_MIN_ENVIO_MS - Date.now()
		if (espera > 0) await esperar(espera)

		const inicio = Date.now()

		try {
			await this.opciones.prepararEnvio?.(envio.grupoId)
			await socket.sendPresenceUpdate("composing", envio.grupoId)
			await esperar(aleatorioEntre(ESCRIBIENDO_MIN_MS, ESCRIBIENDO_MAX_MS))
			await socket.sendMessage(
				envio.grupoId,
				{ text: envio.texto, mentions: envio.menciones },
				envio.citado ? { quoted: envio.citado } : undefined,
			)

			this.opciones.logger.info({ grupo: grupoCorto(envio.grupoId), aviso: Boolean(envio.avisoId), ms: Date.now() - inicio }, "Mensaje enviado")
			if (envio.avisoId) await this.marcar(envio.avisoId, true, null)
		} catch (error) {
			this.opciones.logger.error({ grupo: grupoCorto(envio.grupoId), aviso: Boolean(envio.avisoId), err: mensajeDeError(error) }, "No se pudo enviar el mensaje")
			if (envio.avisoId) await this.marcar(envio.avisoId, false, mensajeDeError(error))
		} finally {
			this.ultimoEnvio = Date.now()

			try {
				await socket.sendPresenceUpdate("paused", envio.grupoId)
			} catch {
				// El estado "escribiendo" expira solo; no vale la pena fallar por esto.
			}
		}
	}
}

export type OpcionesCiclos = {
	api: Pick<ClienteFamiliaHub, "tomarAvisos" | "heartbeat">
	cola: ColaEnvios
	estaConectado: () => boolean
	version: string
	logger: Logger
}

export type Ciclos = {
	sondear: () => Promise<void>
	latido: () => Promise<void>
	detener: () => void
}

export function iniciarCiclos(opciones: OpcionesCiclos): Ciclos {
	let sondeando = false

	const sondear = async () => {
		if (sondeando || !opciones.estaConectado()) return
		sondeando = true

		try {
			await opciones.cola.reintentarMarcas()
			if (opciones.cola.tamano >= COLA_MAX_PARA_SONDEO) return

			const avisos = await opciones.api.tomarAvisos(AVISOS_POR_SONDEO)
			for (const aviso of avisos) opciones.cola.encolarAviso(aviso)
			if (avisos.length) opciones.logger.info({ avisos: avisos.length }, "Avisos tomados")
		} catch (error) {
			opciones.logger.warn({ err: mensajeDeError(error) }, "No se pudieron tomar los avisos; se reintentará en el siguiente sondeo")
		} finally {
			sondeando = false
		}
	}

	const latido = async () => {
		if (!opciones.estaConectado()) return

		try {
			await opciones.api.heartbeat(opciones.version)
		} catch (error) {
			opciones.logger.warn({ err: mensajeDeError(error) }, "No se pudo registrar el heartbeat")
		}
	}

	const temporizadorAvisos = setInterval(() => void sondear(), SONDEO_AVISOS_MS)
	const temporizadorLatido = setInterval(() => void latido(), HEARTBEAT_MS)

	return {
		sondear,
		latido,
		detener() {
			clearInterval(temporizadorAvisos)
			clearInterval(temporizadorLatido)
		},
	}
}
