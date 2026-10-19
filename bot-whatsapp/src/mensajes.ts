import { areJidsSameUser, jidNormalizedUser } from "baileys"
import type { proto, WAMessage } from "baileys"
import { EDAD_MAX_MENSAJE_S, LARGO_MAX_TEXTO } from "./config.ts"

export type MensajeEntrante = {
	id: string
	grupoId: string
	remitenteIds: string[]
	texto: string
	esComando: boolean
	mencionaBot: boolean
	respondeBot: boolean
}

export type OpcionesAnalisis = {
	botIds: string[]
	ahoraS: number
}

// Solo se desenvuelven los mensajes temporales. Ediciones, eliminaciones, reacciones,
// encuestas y multimedia no traen conversation ni extendedTextMessage en el primer nivel.
export function contenidoMensaje(mensaje: proto.IMessage | null | undefined) {
	let actual = mensaje ?? undefined

	for (let i = 0; i < 3 && actual?.ephemeralMessage?.message; i++) {
		actual = actual.ephemeralMessage.message
	}

	return actual
}

export function extraerTexto(mensaje: proto.IMessage | null | undefined) {
	const contenido = contenidoMensaje(mensaje)
	const texto = contenido?.conversation ?? contenido?.extendedTextMessage?.text

	return typeof texto === "string" ? texto : null
}

export function extraerContexto(mensaje: proto.IMessage | null | undefined) {
	return contenidoMensaje(mensaje)?.extendedTextMessage?.contextInfo ?? null
}

export function marcaDeTiempo(valor: WAMessage["messageTimestamp"]) {
	if (typeof valor === "number") return valor
	if (valor && typeof (valor as { toNumber?: () => number }).toNumber === "function") {
		return (valor as { toNumber: () => number }).toNumber()
	}
	const numero = Number(valor)
	return Number.isFinite(numero) && numero > 0 ? numero : null
}

export function normalizarRemitentes(ids: Array<string | null | undefined>) {
	const resultado: string[] = []

	for (const id of ids) {
		if (!id) continue
		const normalizado = jidNormalizedUser(id)
		if (normalizado && !resultado.includes(normalizado)) resultado.push(normalizado)
	}

	return resultado
}

export function idsDelBot(usuario: { id?: string | null; lid?: string | null } | null | undefined) {
	return normalizarRemitentes([usuario?.id, usuario?.lid])
}

export function esDelBot(jid: string | null | undefined, botIds: string[]) {
	if (!jid) return false
	return botIds.some((botId) => areJidsSameUser(jid, botId))
}

export function esPing(texto: string) {
	return texto.trim().toLowerCase() === "/ping"
}

export function primerToken(texto: string) {
	const token = texto.trim().split(/\s+/)[0] ?? ""
	return token.startsWith("/") ? token.slice(1).toLowerCase().slice(0, 20) : ""
}

export function analizarMensaje(mensaje: WAMessage, opciones: OpcionesAnalisis): MensajeEntrante | null {
	const clave = mensaje.key
	const grupoId = clave?.remoteJid ?? ""

	if (!clave?.id || clave.fromMe) return null
	if (!grupoId.endsWith("@g.us")) return null

	const marca = marcaDeTiempo(mensaje.messageTimestamp)
	if (marca == null || opciones.ahoraS - marca > EDAD_MAX_MENSAJE_S) return null

	const textoCrudo = extraerTexto(mensaje.message)
	if (textoCrudo == null) return null

	const texto = textoCrudo.trim()
	if (!texto || textoCrudo.length > LARGO_MAX_TEXTO) return null

	const remitenteIds = normalizarRemitentes([clave.participant, clave.participantAlt])
	if (!remitenteIds.length || remitenteIds.some((id) => esDelBot(id, opciones.botIds))) return null

	const contexto = extraerContexto(mensaje.message)
	const mencionaBot = (contexto?.mentionedJid ?? []).some((jid) => esDelBot(jid, opciones.botIds))
	const respondeBot = esDelBot(contexto?.participant, opciones.botIds)
	const esComando = texto.startsWith("/")

	if (!esComando && !mencionaBot && !respondeBot) return null

	return {
		id: clave.id,
		grupoId,
		remitenteIds,
		texto,
		esComando,
		mencionaBot,
		respondeBot,
	}
}
