// Funciones puras para interpretar mensajes del grupo. No conocen reglas de negocio.

export type Contenido = {
	conversation?: string | null
	extendedTextMessage?: {
		text?: string | null
		contextInfo?: { mentionedJid?: string[] | null } | null
	} | null
}

export type Remitente = {
	remitenteId: string
	remitenteAlt: string | null
}

// Equivalente a jidNormalizedUser de Baileys: quita dispositivo y agente.
export function normalizarJid(jid: string | null | undefined): string | null {
	if (!jid) return null
	const separador = jid.indexOf('@')
	if (separador <= 0) return null
	const usuario = jid.slice(0, separador).split(':')[0].split('_')[0]
	const servidor = jid.slice(separador + 1)
	if (!usuario || !servidor) return null
	return `${usuario}@${servidor === 'c.us' ? 's.whatsapp.net' : servidor}`
}

// Devuelve el comando a enviar o null si el mensaje debe ignorarse.
// Solo se atienden mensajes que empiezan con "/" o que mencionan al bot.
export function extraerComando(contenido: Contenido | null | undefined, idsBot: string[]): string | null {
	const texto = (contenido?.conversation ?? contenido?.extendedTextMessage?.text ?? '').trim()
	if (!texto) return null
	if (texto.startsWith('/')) return texto

	const menciones = contenido?.extendedTextMessage?.contextInfo?.mentionedJid ?? []
	const mencionaAlBot = menciones.some((jid) => {
		const normalizado = normalizarJid(jid)
		return normalizado !== null && idsBot.includes(normalizado)
	})
	if (!mencionaAlBot) return null

	const sinMenciones = texto.replace(/@\d+/g, '').trim()
	return sinMenciones.startsWith('/') ? sinMenciones : '/ayuda'
}

// WhatsApp migra a identificadores internos (LID). Se prefiere el LID y se envía el número como alterno.
export function identificarRemitente(participante?: string | null, participanteAlt?: string | null): Remitente | null {
	const ids = [participante, participanteAlt]
		.map(normalizarJid)
		.filter((id): id is string => id !== null)
	const lid = ids.find((id) => id.endsWith('@lid') || id.endsWith('@hosted.lid'))
	const numero = ids.find((id) => id.endsWith('@s.whatsapp.net') || id.endsWith('@hosted'))
	const principal = lid ?? numero
	if (!principal) return null
	return { remitenteId: principal, remitenteAlt: lid && numero ? numero : null }
}

export function nombreComando(comando: string) {
	return comando.split(/\s+/)[0].toLowerCase()
}

// Ventana deslizante en memoria: máximo de comandos por remitente en un minuto.
export function crearLimitador(maximo = 5, ventanaMs = 60_000, ahora = () => Date.now()) {
	const historial = new Map<string, number[]>()

	return (clave: string) => {
		const momento = ahora()
		const recientes = (historial.get(clave) ?? []).filter((marca) => momento - marca < ventanaMs)
		const permitido = recientes.length < maximo
		if (permitido) recientes.push(momento)
		historial.set(clave, recientes)

		if (historial.size > 1_000) {
			for (const [otraClave, marcas] of historial) {
				if (!marcas.some((marca) => momento - marca < ventanaMs)) historial.delete(otraClave)
			}
		}

		return permitido
	}
}
