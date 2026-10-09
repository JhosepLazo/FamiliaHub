// Bot de WhatsApp de FamiliaHub: pasarela delgada entre el grupo familiar y Supabase.
// No calcula montos ni decide estados: solo reenvía comandos y entrega avisos de la cola.

import makeWASocket, {
	Browsers,
	DisconnectReason,
	isJidGroup,
	normalizeMessageContent,
	useMultiFileAuthState,
} from 'baileys'
import type { GroupMetadata, WAMessage, WAMessageContent, WASocket } from 'baileys'
import { join } from 'node:path'
import pino from 'pino'
import qrcode from 'qrcode-terminal'
import { crearClienteFamiliaHub } from './familiahub.ts'
import { crearLimitador, extraerComando, identificarRemitente, nombreComando, normalizarJid } from './mensajes.ts'

const AUTH_DIR = join(import.meta.dirname, 'auth')
const ESPERA_RECONEXION_MS = 3_000
const INTERVALO_AVISOS_MS = 5 * 60_000
const PAUSA_ENTRE_ENVIOS_MS = 3_000
const VIGENCIA_GRUPO_MS = 10 * 60_000
const MENSAJES_RECORDADOS = 200

const functionUrl = process.env.FAMILIAHUB_FUNCTION_URL
const botSecret = process.env.FAMILIAHUB_BOT_SECRET
const familiahub = functionUrl && botSecret ? crearClienteFamiliaHub(functionUrl, botSecret) : null

const permitirComando = crearLimitador(5, 60_000)
// WhatsApp puede pedir reenviar un mensaje propio; se recuerdan los últimos enviados.
const enviados = new Map<string, WAMessageContent>()
const grupos = new Map<string, { metadata: GroupMetadata; at: number }>()

let socket: WASocket | null = null
let conectado = false
let revisandoAvisos = false

function log(...partes: unknown[]) {
	console.log(new Date().toISOString(), ...partes)
}

function detalle(error: unknown) {
	return error instanceof Error ? error.message : String(error)
}

const esperar = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms))

async function conectar() {
	const { state, saveCreds } = await useMultiFileAuthState(AUTH_DIR)

	const sock = makeWASocket({
		auth: state,
		logger: pino({ level: 'warn' }),
		browser: Browsers.ubuntu('FamiliaHub'),
		markOnlineOnConnect: false,
		syncFullHistory: false,
		shouldSyncHistoryMessage: () => false,
		getMessage: async (key) => (key.id ? enviados.get(key.id) : undefined),
		cachedGroupMetadata: async (jid) => grupos.get(jid)?.metadata,
	})
	socket = sock

	sock.ev.on('creds.update', saveCreds)

	sock.ev.on('connection.update', ({ connection, lastDisconnect, qr }) => {
		if (qr) {
			log('Escanea el QR con el celular del bot: WhatsApp > Dispositivos vinculados > Vincular dispositivo.')
			qrcode.generate(qr, { small: true })
		}

		if (connection === 'open') {
			conectado = true
			log(`Conectado como ${normalizarJid(sock.user?.id) ?? 'bot'}.`)
			void revisarAvisos()
		}

		if (connection === 'close') {
			conectado = false
			const status = (lastDisconnect?.error as { output?: { statusCode?: number } } | undefined)?.output?.statusCode

			if (status === DisconnectReason.loggedOut) {
				log('Sesión cerrada desde el teléfono. Borra la carpeta auth/ y vuelve a escanear el QR.')
				process.exit(1)
			}

			log(`Conexión cerrada (${status ?? 'sin código'}). Reintentando en ${ESPERA_RECONEXION_MS / 1000} s.`)
			setTimeout(() => void conectar().catch((error) => log('No se pudo reconectar:', detalle(error))), ESPERA_RECONEXION_MS)
		}
	})

	sock.ev.on('messages.upsert', ({ messages, type }) => {
		if (type !== 'notify') return
		for (const mensaje of messages) void atenderMensaje(mensaje)
	})

	sock.ev.on('group-participants.update', ({ id }) => grupos.delete(id))
	sock.ev.on('groups.update', (cambios) => {
		for (const cambio of cambios) if (cambio.id) grupos.delete(cambio.id)
	})
}

async function atenderMensaje(mensaje: WAMessage) {
	const grupoId = mensaje.key.remoteJid
	const sock = socket
	// Solo grupos: el bot no opera en chats privados.
	if (!sock || !grupoId || !isJidGroup(grupoId) || mensaje.key.fromMe) return

	const idsBot = [sock.user?.id, sock.user?.lid]
		.map(normalizarJid)
		.filter((id): id is string => id !== null)
	const comando = extraerComando(normalizeMessageContent(mensaje.message), idsBot)
	if (!comando) return

	const remitente = identificarRemitente(mensaje.key.participant, mensaje.key.participantAlt)
	if (!remitente || !permitirComando(remitente.remitenteId)) return

	try {
		let respuesta: string | null = null

		if (nombreComando(comando) === '/ping') respuesta = 'pong 🏠'
		else if (familiahub) respuesta = await familiahub.responder({ grupoId, ...remitente, texto: comando })

		if (respuesta) await enviar(grupoId, respuesta, mensaje)
	} catch (error) {
		// Solo se registra el nombre del comando: los códigos de vinculación no van a los logs.
		log(`No se pudo atender ${nombreComando(comando)}:`, detalle(error))
	}
}

async function enviar(grupoId: string, texto: string, citado?: WAMessage) {
	const sock = socket
	if (!sock || !conectado) throw new Error('Sin conexión con WhatsApp.')

	const cache = grupos.get(grupoId)
	if (!cache || Date.now() - cache.at > VIGENCIA_GRUPO_MS) {
		grupos.set(grupoId, { metadata: await sock.groupMetadata(grupoId), at: Date.now() })
	}

	const enviado = await sock.sendMessage(grupoId, { text: texto }, citado ? { quoted: citado } : undefined)

	if (enviado?.key.id && enviado.message) {
		enviados.set(enviado.key.id, enviado.message)
		if (enviados.size > MENSAJES_RECORDADOS) enviados.delete(enviados.keys().next().value!)
	}
}

async function marcarAviso(avisoId: string, enviado: boolean, error?: string) {
	for (let intento = 1; intento <= 3; intento++) {
		try {
			await familiahub!.marcarAviso(avisoId, enviado, error)
			return
		} catch (fallo) {
			if (intento === 3) log(`No se pudo registrar el aviso ${avisoId}:`, detalle(fallo))
			else await esperar(2_000)
		}
	}
}

// La base de datos decide qué avisos tocan y respeta la ventana horaria; el bot solo los entrega.
async function revisarAvisos() {
	if (!familiahub || !conectado || revisandoAvisos) return
	revisandoAvisos = true

	try {
		const avisos = await familiahub.avisosPendientes()

		for (const aviso of avisos) {
			if (!conectado) break

			try {
				await enviar(aviso.grupoId, aviso.mensaje)
				await marcarAviso(aviso.id, true)
			} catch (error) {
				log(`No se pudo enviar el aviso ${aviso.id}:`, detalle(error))
				await marcarAviso(aviso.id, false, detalle(error))
			}

			await esperar(PAUSA_ENTRE_ENVIOS_MS)
		}
	} catch (error) {
		log('No se pudo consultar la cola de avisos:', detalle(error))
	} finally {
		revisandoAvisos = false
	}
}

if (!familiahub) {
	log('Modo mínimo: solo responde /ping. Configura FAMILIAHUB_FUNCTION_URL y FAMILIAHUB_BOT_SECRET en .env para activar FamiliaHub.')
}

setInterval(() => void revisarAvisos(), INTERVALO_AVISOS_MS)
await conectar()
