import assert from "node:assert/strict"
import { describe, it } from "node:test"
import type { WAMessage } from "baileys"
import {
	analizarMensaje,
	esPing,
	extraerTexto,
	idsDelBot,
	normalizarRemitentes,
	primerToken,
} from "../src/mensajes.ts"

const AHORA = 1_790_000_000
const GRUPO = "120363000000000001@g.us"
const BOT_PN = "51999999999@s.whatsapp.net"
const BOT_LID = "190000000000099@lid"
const BOT_IDS = idsDelBot({ id: "51999999999:7@s.whatsapp.net", lid: "190000000000099:7@lid" })
const OPCIONES = { botIds: BOT_IDS, ahoraS: AHORA }

function mensaje(cambios: Partial<WAMessage> & { texto?: string } = {}): WAMessage {
	const { texto = "/deuda", ...resto } = cambios
	return {
		key: {
			id: "ABC123",
			remoteJid: GRUPO,
			fromMe: false,
			participant: "200000000000002@lid",
			participantAlt: "51900000002@s.whatsapp.net",
		},
		messageTimestamp: AHORA - 5,
		message: { conversation: texto },
		...resto,
	}
}

describe("extraerTexto", () => {
	it("lee conversation y extendedTextMessage", () => {
		assert.equal(extraerTexto({ conversation: "/ayuda" }), "/ayuda")
		assert.equal(extraerTexto({ extendedTextMessage: { text: "/recibo luz" } }), "/recibo luz")
	})

	it("desenvuelve mensajes temporales", () => {
		assert.equal(extraerTexto({ ephemeralMessage: { message: { conversation: "/vence" } } }), "/vence")
	})

	it("ignora multimedia, reacciones, encuestas, ediciones y eliminaciones", () => {
		assert.equal(extraerTexto({ imageMessage: { caption: "/deuda" } }), null)
		assert.equal(extraerTexto({ reactionMessage: { text: "👍" } }), null)
		assert.equal(extraerTexto({ pollCreationMessage: { name: "/deuda" } }), null)
		assert.equal(extraerTexto({ editedMessage: { message: { conversation: "/deuda" } } }), null)
		assert.equal(extraerTexto({ protocolMessage: { type: 0 } }), null)
		assert.equal(extraerTexto(null), null)
	})
})

describe("analizarMensaje", () => {
	it("acepta un comando del grupo", () => {
		const resultado = analizarMensaje(mensaje(), OPCIONES)
		assert.deepEqual(resultado, {
			id: "ABC123",
			grupoId: GRUPO,
			remitenteIds: ["200000000000002@lid", "51900000002@s.whatsapp.net"],
			texto: "/deuda",
			esComando: true,
			mencionaBot: false,
			respondeBot: false,
		})
	})

	it("descarta mensajes propios", () => {
		const propio = mensaje()
		propio.key.fromMe = true
		assert.equal(analizarMensaje(propio, OPCIONES), null)
	})

	it("descarta chats privados", () => {
		const privado = mensaje()
		privado.key.remoteJid = "51900000002@s.whatsapp.net"
		assert.equal(analizarMensaje(privado, OPCIONES), null)
	})

	it("descarta mensajes de más de 10 minutos", () => {
		assert.equal(analizarMensaje(mensaje({ messageTimestamp: AHORA - 601 }), OPCIONES), null)
		assert.notEqual(analizarMensaje(mensaje({ messageTimestamp: AHORA - 600 }), OPCIONES), null)
		assert.equal(analizarMensaje(mensaje({ messageTimestamp: undefined }), OPCIONES), null)
	})

	it("acepta marcas de tiempo tipo Long", () => {
		const largo = { toNumber: () => AHORA - 1 } as unknown as WAMessage["messageTimestamp"]
		assert.notEqual(analizarMensaje(mensaje({ messageTimestamp: largo }), OPCIONES), null)
	})

	it("descarta textos vacíos o de más de 500 caracteres", () => {
		assert.equal(analizarMensaje(mensaje({ texto: "   " }), OPCIONES), null)
		assert.equal(analizarMensaje(mensaje({ texto: `/recibo ${"a".repeat(493)}` }), OPCIONES), null)
		assert.notEqual(analizarMensaje(mensaje({ texto: `/recibo ${"a".repeat(492)}` }), OPCIONES), null)
	})

	it("descarta multimedia aunque tenga texto en la leyenda", () => {
		assert.equal(analizarMensaje(mensaje({ message: { imageMessage: { caption: "/deuda" } } }), OPCIONES), null)
	})

	it("descarta texto común que no menciona ni responde al bot", () => {
		assert.equal(analizarMensaje(mensaje({ texto: "hola familia" }), OPCIONES), null)
	})

	it("detecta una mención al bot por LID o número", () => {
		for (const jid of [BOT_LID, BOT_PN]) {
			const resultado = analizarMensaje(
				mensaje({ message: { extendedTextMessage: { text: "@bot cuánto debo", contextInfo: { mentionedJid: [jid] } } } }),
				OPCIONES,
			)
			assert.equal(resultado?.mencionaBot, true)
			assert.equal(resultado?.esComando, false)
		}
	})

	it("detecta una respuesta a un mensaje del bot", () => {
		const resultado = analizarMensaje(
			mensaje({ message: { extendedTextMessage: { text: "y el agua?", contextInfo: { participant: "51999999999:3@s.whatsapp.net", stanzaId: "X" } } } }),
			OPCIONES,
		)
		assert.equal(resultado?.respondeBot, true)
		assert.equal(resultado?.mencionaBot, false)
	})

	it("no confunde la mención de otra persona con la del bot", () => {
		const resultado = analizarMensaje(
			mensaje({ message: { extendedTextMessage: { text: "@ana mira", contextInfo: { mentionedJid: ["300000000000003@lid"] } } } }),
			OPCIONES,
		)
		assert.equal(resultado, null)
	})
})

describe("normalizarRemitentes", () => {
	it("quita nulos, sufijos de dispositivo y duplicados", () => {
		assert.deepEqual(
			normalizarRemitentes(["51900000002:12@s.whatsapp.net", null, "200000000000002@lid", "51900000002@s.whatsapp.net", undefined]),
			["51900000002@s.whatsapp.net", "200000000000002@lid"],
		)
	})

	it("obtiene los IDs del bot sin sufijo de dispositivo", () => {
		assert.deepEqual(BOT_IDS, [BOT_PN, BOT_LID])
		assert.deepEqual(idsDelBot(undefined), [])
	})
})

describe("comandos", () => {
	it("reconoce /ping exacto sin importar mayúsculas", () => {
		assert.equal(esPing("/ping"), true)
		assert.equal(esPing("  /PING "), true)
		assert.equal(esPing("/ping familia"), false)
		assert.equal(esPing("ping"), false)
	})

	it("extrae solo el comando para los logs", () => {
		assert.equal(primerToken("/Recibo luz del mes"), "recibo")
		assert.equal(primerToken("hola"), "")
	})
})
