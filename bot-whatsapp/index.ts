import { chmodSync, mkdirSync } from "node:fs"
import makeWASocket, { DisconnectReason, fetchLatestWaWebVersion, useMultiFileAuthState } from "baileys"
import type { BaileysEventMap, ConnectionState, GroupMetadata, WAMessage, WASocket } from "baileys"
import pino from "pino"
import qrcode from "qrcode-terminal"
import { ClienteFamiliaHub } from "./src/api.ts"
import {
	CACHE_GRUPO_MS,
	LIMITE_COMANDOS,
	LIMITE_LENGUAJE_NATURAL_GRUPO,
	LIMITE_LENGUAJE_NATURAL_REMITENTE,
	LIMITE_NO_VINCULADO,
	DEDUPE_MAX,
	MENSAJE_SIN_CONEXION,
	RECONEXION_INICIAL_MS,
	RECONEXION_MAX_MS,
	TIMEOUT_HTTP_LENGUAJE_NATURAL_MS,
	TIMEOUT_HTTP_MS,
	leerConfiguracion,
	type Configuracion,
} from "./src/config.ts"
import { Deduplicador, EsperaExponencial, LimitadorFrecuencia } from "./src/control.ts"
import { ColaEnvios, grupoCorto, iniciarCiclos, type Ciclos } from "./src/envios.ts"
import { analizarMensaje, esDelBot, esPing, idsDelBot, primerToken } from "./src/mensajes.ts"

let config: Configuracion

// Con --vincular solo se muestra el QR y el proceso termina al quedar vinculado (lo usa scripts/bot.ps1).
const soloVincular = process.argv.includes("--vincular")

try {
	config = leerConfiguracion()
} catch (error) {
	console.error(error instanceof Error ? error.message : error)
	process.exit(1)
}

const logger = pino({ level: config.logLevel })
const api = new ClienteFamiliaHub(config.functionUrl, config.botSecret)
const deduplicador = new Deduplicador(DEDUPE_MAX)
const limiteComandos = new LimitadorFrecuencia(LIMITE_COMANDOS.maximo, LIMITE_COMANDOS.ventanaMs)
const limiteNoVinculado = new LimitadorFrecuencia(LIMITE_NO_VINCULADO.maximo, LIMITE_NO_VINCULADO.ventanaMs)
const limiteNaturalRemitente = new LimitadorFrecuencia(LIMITE_LENGUAJE_NATURAL_REMITENTE.maximo, LIMITE_LENGUAJE_NATURAL_REMITENTE.ventanaMs)
const limiteNaturalGrupo = new LimitadorFrecuencia(LIMITE_LENGUAJE_NATURAL_GRUPO.maximo, LIMITE_LENGUAJE_NATURAL_GRUPO.ventanaMs)
const espera = new EsperaExponencial(RECONEXION_INICIAL_MS, RECONEXION_MAX_MS)
const cacheGrupos = new Map<string, { datos: GroupMetadata; expira: number }>()

let socket: WASocket | null = null
let conectado = false
let terminando = false
let botIds: string[] = []
let ciclos: Ciclos | null = null
let temporizadorReconexion: ReturnType<typeof setTimeout> | undefined

const cola = new ColaEnvios({
	obtenerSocket: () => socket,
	estaConectado: () => conectado,
	api,
	logger,
	prepararEnvio,
})

// La carpeta de sesión equivale a tener el WhatsApp del chip abierto: solo el usuario del bot puede leerla.
mkdirSync(config.authDir, { recursive: true, mode: 0o700 })
try {
	chmodSync(config.authDir, 0o700)
} catch {
	// En Windows los permisos POSIX no aplican.
}

const estadoAuth = await useMultiFileAuthState(config.authDir)

async function metadatosGrupo(jid: string) {
	const entrada = cacheGrupos.get(jid)
	return entrada && entrada.expira > Date.now() ? entrada.datos : undefined
}

// Evita pedir los datos del grupo a WhatsApp en cada envío.
async function prepararEnvio(grupoId: string) {
	if (await metadatosGrupo(grupoId)) return
	const actual = socket
	if (!actual) return

	try {
		const datos = await actual.groupMetadata(grupoId)
		cacheGrupos.set(grupoId, { datos, expira: Date.now() + CACHE_GRUPO_MS })
	} catch (error) {
		logger.warn({ grupo: grupoCorto(grupoId), err: error instanceof Error ? error.message : String(error) }, "No se pudieron obtener los datos del grupo")
	}
}

// Muestra "escribiendo…" en el grupo mientras se consulta FamiliaHub. WhatsApp lo quita solo al llegar la
// respuesta; si no hay respuesta se quita a mano. Un fallo aquí nunca impide responder.
function mostrarEscribiendo(grupoId: string, estado: "composing" | "paused") {
	const actual = socket
	if (!actual || !conectado) return
	actual.sendPresenceUpdate(estado, grupoId).catch(() => {})
}

async function manejarMensaje(mensaje: WAMessage) {
	const entrante = analizarMensaje(mensaje, { botIds, ahoraS: Math.floor(Date.now() / 1_000) })
	if (!entrante || deduplicador.visto(entrante.id)) return

	const remitente = entrante.remitenteIds[0]
	const permitido = entrante.esComando
		? limiteComandos.permitir(remitente)
		: limiteNaturalRemitente.permitir(remitente) && limiteNaturalGrupo.permitir(entrante.grupoId)

	if (!permitido) return

	if (esPing(entrante.texto)) {
		cola.responder(entrante.grupoId, "pong 🏠", [], mensaje)
		return
	}

	const etiqueta = entrante.esComando ? `/${primerToken(entrante.texto)}` : "mención"
	const inicio = Date.now()
	let respondio = false
	mostrarEscribiendo(entrante.grupoId, "composing")

	try {
		const resultado = await api.mensaje(
			{
				grupoId: entrante.grupoId,
				remitenteIds: entrante.remitenteIds,
				texto: entrante.texto,
				mencionaBot: entrante.mencionaBot,
				respondeBot: entrante.respondeBot,
			},
			entrante.esComando ? TIMEOUT_HTTP_MS : TIMEOUT_HTTP_LENGUAJE_NATURAL_MS,
		)

		logger.info({ grupo: grupoCorto(entrante.grupoId), comando: etiqueta, ms: Date.now() - inicio }, "Mensaje procesado")

		if (!resultado.respuesta) return
		if (!resultado.grupoVinculado && !limiteNoVinculado.permitir(entrante.grupoId)) return

		cola.responder(entrante.grupoId, resultado.respuesta.texto, resultado.respuesta.menciones, mensaje)
		respondio = true
	} catch (error) {
		logger.error(
			{ grupo: grupoCorto(entrante.grupoId), comando: etiqueta, ms: Date.now() - inicio, err: error instanceof Error ? error.message : String(error) },
			"No se pudo consultar FamiliaHub",
		)
		cola.responder(entrante.grupoId, MENSAJE_SIN_CONEXION, [], mensaje)
		respondio = true
	} finally {
		if (!respondio) mostrarEscribiendo(entrante.grupoId, "paused")
	}
}

async function manejarParticipantes(evento: BaileysEventMap["group-participants.update"]) {
	cacheGrupos.delete(evento.id)
	if (evento.action !== "remove") return

	const retirado = evento.participants.some((participante) => {
		const ids = typeof participante === "string"
			? [participante]
			: [participante.id, participante.lid, participante.phoneNumber]
		return ids.some((id) => esDelBot(id, botIds))
	})

	if (!retirado) return

	try {
		await api.grupoSalida(evento.id)
		logger.warn({ grupo: grupoCorto(evento.id) }, "El bot fue retirado del grupo; se desvinculó en FamiliaHub")
	} catch (error) {
		logger.error({ grupo: grupoCorto(evento.id), err: error instanceof Error ? error.message : String(error) }, "No se pudo registrar la salida del grupo")
	}
}

function manejarConexion(sock: WASocket, actualizacion: Partial<ConnectionState>) {
	if (sock !== socket) return

	if (actualizacion.qr) {
		console.log("Escanea este QR desde el celular del chip: WhatsApp > Dispositivos vinculados > Vincular dispositivo.")
		qrcode.generate(actualizacion.qr, { small: true })
	}

	if (actualizacion.connection === "open") {
		conectado = true
		espera.reiniciar()
		botIds = idsDelBot(sock.user)
		console.log(`Conectado a WhatsApp. FamiliaHub bot ${config.version}.`)

		if (soloVincular) {
			// Da tiempo a que la sesión termine de guardarse en auth/.
			setTimeout(() => void terminar(), 3_000)
			return
		}

		if (!ciclos) {
			ciclos = iniciarCiclos({ api, cola, estaConectado: () => conectado, version: config.version, logger })
		}

		void ciclos.latido()
		void ciclos.sondear()
		cola.reanudar()
	}

	if (actualizacion.connection === "close") {
		conectado = false
		if (terminando) return

		const codigo = (actualizacion.lastDisconnect?.error as { output?: { statusCode?: number } } | undefined)?.output?.statusCode

		if (codigo === DisconnectReason.loggedOut) {
			console.error("Sesión cerrada desde el teléfono. Borra la carpeta auth/ y vuelve a escanear el QR.")
			ciclos?.detener()
			process.exit(1)
		}

		programarReconexion(codigo)
	}
}

function programarReconexion(codigo?: number) {
	const ms = espera.siguiente()
	logger.warn({ codigo, reintentoMs: ms }, "Conexión con WhatsApp cerrada; se reintentará")
	clearTimeout(temporizadorReconexion)
	temporizadorReconexion = setTimeout(() => {
		conectar().catch((error) => {
			logger.error({ err: error instanceof Error ? error.message : String(error) }, "No se pudo reconectar")
			programarReconexion()
		})
	}, ms)
}

async function conectar() {
	const { version, error } = await fetchLatestWaWebVersion()
	if (error) logger.warn("No se pudo consultar la última versión de WhatsApp Web; se usa la incluida en Baileys")

	const sock = makeWASocket({
		auth: estadoAuth.state,
		version,
		logger,
		cachedGroupMetadata: metadatosGrupo,
	})

	socket = sock

	sock.ev.on("creds.update", estadoAuth.saveCreds)
	sock.ev.on("connection.update", (actualizacion) => manejarConexion(sock, actualizacion))
	sock.ev.on("messages.upsert", ({ messages, type }) => {
		if (type !== "notify" || soloVincular) return

		for (const mensaje of messages) {
			manejarMensaje(mensaje).catch((fallo) => {
				logger.error({ err: fallo instanceof Error ? fallo.message : String(fallo) }, "Error al procesar un mensaje")
			})
		}
	})
	sock.ev.on("group-participants.update", (evento) => void manejarParticipantes(evento))
	sock.ev.on("groups.update", (cambios) => {
		for (const cambio of cambios) if (cambio.id) cacheGrupos.delete(cambio.id)
	})
}

async function terminar() {
	if (terminando) return
	terminando = true
	conectado = false
	ciclos?.detener()
	clearTimeout(temporizadorReconexion)

	try {
		await socket?.end(undefined)
	} catch {
		// El proceso termina de todas formas.
	}

	process.exit(0)
}

process.on("SIGINT", () => void terminar())
process.on("SIGTERM", () => void terminar())
process.on("unhandledRejection", (error) => {
	logger.error({ err: error instanceof Error ? error.message : String(error) }, "Promesa rechazada sin manejar")
})
// El código 1 queda para lo que necesita intervención (configuración o sesión cerrada); con 2, pm2 y scripts/bot.ps1 reinician.
process.on("uncaughtException", (error) => {
	logger.fatal({ err: error.message }, "Error inesperado; el proceso termina para reiniciarse")
	process.exit(2)
})

await conectar()
