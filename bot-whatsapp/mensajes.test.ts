import assert from 'node:assert/strict'
import { test } from 'node:test'
import { crearLimitador, extraerComando, identificarRemitente, nombreComando, normalizarJid } from './mensajes.ts'

const BOT = '51900000000@s.whatsapp.net'
const BOT_LID = '199999999999999@lid'

test('normaliza dispositivo, agente y servidor antiguo', () => {
	assert.equal(normalizarJid('51900000000:12@s.whatsapp.net'), BOT)
	assert.equal(normalizarJid('51900000000_1:3@s.whatsapp.net'), BOT)
	assert.equal(normalizarJid('51900000000@c.us'), BOT)
	assert.equal(normalizarJid('199999999999999:4@lid'), BOT_LID)
	assert.equal(normalizarJid('sin-servidor'), null)
	assert.equal(normalizarJid(undefined), null)
})

test('atiende mensajes que empiezan con /', () => {
	assert.equal(extraerComando({ conversation: '  /deuda ' }, [BOT]), '/deuda')
	assert.equal(extraerComando({ extendedTextMessage: { text: '/vincular ABC234' } }, [BOT]), '/vincular ABC234')
})

test('ignora mensajes comunes del grupo', () => {
	assert.equal(extraerComando({ conversation: '¿Cuánto llegó la luz?' }, [BOT]), null)
	assert.equal(extraerComando({ conversation: '' }, [BOT]), null)
	assert.equal(extraerComando(null, [BOT]), null)
	assert.equal(
		extraerComando({ extendedTextMessage: { text: '@51911111111 hola', contextInfo: { mentionedJid: ['51911111111@s.whatsapp.net'] } } }, [BOT]),
		null,
	)
})

test('una mención al bot sin comando devuelve la ayuda', () => {
	const contenido = { extendedTextMessage: { text: '@199999999999999 ¿cuánto debo?', contextInfo: { mentionedJid: ['199999999999999@lid'] } } }
	assert.equal(extraerComando(contenido, [BOT, BOT_LID]), '/ayuda')
})

test('una mención al bot con comando lo conserva', () => {
	const contenido = { extendedTextMessage: { text: '@51900000000 /resumen', contextInfo: { mentionedJid: ['51900000000:2@s.whatsapp.net'] } } }
	assert.equal(extraerComando(contenido, [BOT]), '/resumen')
})

test('prefiere el LID y envía el número como alterno', () => {
	assert.deepEqual(identificarRemitente('211111111111111@lid', '51911111111@s.whatsapp.net'), {
		remitenteId: '211111111111111@lid',
		remitenteAlt: '51911111111@s.whatsapp.net',
	})
	assert.deepEqual(identificarRemitente('51911111111:3@s.whatsapp.net', '211111111111111@lid'), {
		remitenteId: '211111111111111@lid',
		remitenteAlt: '51911111111@s.whatsapp.net',
	})
	assert.deepEqual(identificarRemitente('51911111111@s.whatsapp.net', undefined), {
		remitenteId: '51911111111@s.whatsapp.net',
		remitenteAlt: null,
	})
	assert.equal(identificarRemitente(undefined, undefined), null)
	assert.equal(identificarRemitente('120363000000000001@g.us', null), null)
})

test('nombre del comando sin argumentos y en minúsculas', () => {
	assert.equal(nombreComando('/VINCULAR ABC234'), '/vincular')
	assert.equal(nombreComando('/ping'), '/ping')
})

test('máximo 5 comandos por minuto por remitente', () => {
	let ahora = 0
	const permitir = crearLimitador(5, 60_000, () => ahora)

	for (let i = 0; i < 5; i++) assert.equal(permitir('ana'), true)
	assert.equal(permitir('ana'), false)
	assert.equal(permitir('luis'), true)

	ahora = 59_999
	assert.equal(permitir('ana'), false)

	ahora = 60_000
	assert.equal(permitir('ana'), true)
})
