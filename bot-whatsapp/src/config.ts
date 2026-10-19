import { readFileSync } from "node:fs"

export const SONDEO_AVISOS_MS = 60_000
export const HEARTBEAT_MS = 300_000
export const RECONEXION_INICIAL_MS = 3_000
export const RECONEXION_MAX_MS = 60_000
export const INTERVALO_MIN_ENVIO_MS = 2_000
export const ESCRIBIENDO_MIN_MS = 1_000
export const ESCRIBIENDO_MAX_MS = 2_500
export const EDAD_MAX_MENSAJE_S = 600
export const LARGO_MAX_TEXTO = 500
export const LIMITE_COMANDOS = { maximo: 5, ventanaMs: 60_000 }
export const LIMITE_NO_VINCULADO = { maximo: 1, ventanaMs: 3_600_000 }
export const LIMITE_LENGUAJE_NATURAL_REMITENTE = { maximo: 3, ventanaMs: 60_000 }
export const LIMITE_LENGUAJE_NATURAL_GRUPO = { maximo: 20, ventanaMs: 3_600_000 }
export const DEDUPE_MAX = 1_000
export const TIMEOUT_HTTP_MS = 15_000
export const TIMEOUT_HTTP_LENGUAJE_NATURAL_MS = 30_000
export const AVISOS_POR_SONDEO = 5
export const COLA_MAX_PARA_SONDEO = 5
export const RESERVA_AVISO_MS = 5 * 60_000
export const CACHE_GRUPO_MS = 5 * 60_000

export const MENSAJE_SIN_CONEXION = "No pude consultar FamiliaHub en este momento. Intenta en unos minutos."

const NIVELES_LOG = ["fatal", "error", "warn", "info", "debug", "trace", "silent"]

export type Configuracion = {
	functionUrl: string
	botSecret: string
	authDir: string
	logLevel: string
	version: string
}

export function leerVersion() {
	const paquete = JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf8"))
	return String(paquete.version ?? "0.0.0")
}

export function leerConfiguracion(env: NodeJS.ProcessEnv = process.env): Configuracion {
	const faltantes = ["FAMILIAHUB_FUNCTION_URL", "FAMILIAHUB_BOT_SECRET"].filter((nombre) => !env[nombre]?.trim())

	if (faltantes.length) {
		throw new Error(`Faltan variables de entorno obligatorias: ${faltantes.join(", ")}. Copia .env.example a .env y complétalo.`)
	}

	const functionUrl = env.FAMILIAHUB_FUNCTION_URL!.trim()
	let url: URL

	try {
		url = new URL(functionUrl)
	} catch {
		throw new Error("FAMILIAHUB_FUNCTION_URL no es una URL válida.")
	}

	const local = url.hostname === "localhost" || url.hostname === "127.0.0.1"
	if (url.protocol !== "https:" && !(local && url.protocol === "http:")) {
		throw new Error("FAMILIAHUB_FUNCTION_URL debe usar https (http solo para Supabase local).")
	}

	const logLevel = env.LOG_LEVEL?.trim() || "warn"
	if (!NIVELES_LOG.includes(logLevel)) {
		throw new Error(`LOG_LEVEL debe ser uno de: ${NIVELES_LOG.join(", ")}.`)
	}

	return {
		functionUrl,
		botSecret: env.FAMILIAHUB_BOT_SECRET!.trim(),
		authDir: env.AUTH_DIR?.trim() || "auth",
		logLevel,
		version: leerVersion(),
	}
}
