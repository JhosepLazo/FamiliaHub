import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "npm:@supabase/supabase-js@2.117.2"

// Pasarela entre el bot de WhatsApp y la base de datos.
// El bot solo conoce esta URL y un secreto compartido; nunca la clave secreta de Supabase.

const headers = { "Content-Type": "application/json" }

const json = (body: unknown, status = 200) =>
	new Response(JSON.stringify(body), { status, headers })

const GRUPO = /^[0-9]+(-[0-9]+)?@g\.us$/
const REMITENTE = /^[0-9]+@(s\.whatsapp\.net|lid|hosted|hosted\.lid)$/
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

// Compara resúmenes SHA-256 para no filtrar la longitud ni el contenido por tiempo de respuesta.
const sameSecret = async (received: string, expected: string) => {
	const encoder = new TextEncoder()
	const [left, right] = await Promise.all([
		crypto.subtle.digest("SHA-256", encoder.encode(received)),
		crypto.subtle.digest("SHA-256", encoder.encode(expected)),
	])
	const a = new Uint8Array(left)
	const b = new Uint8Array(right)
	let diff = 0
	for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i]
	return diff === 0
}

Deno.serve(async (req) => {
	if (req.method !== "POST") return json({ error: "Método no permitido." }, 405)

	const botSecret = Deno.env.get("FAMILIAHUB_BOT_SECRET") ?? ""
	const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}")
	const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? ""
	const secretKey = secretKeys.default

	if (botSecret.length < 32 || !supabaseUrl || !secretKey) {
		return json({ error: "Configuración incompleta." }, 500)
	}

	if (!(await sameSecret(req.headers.get("x-familiahub-bot-secret") ?? "", botSecret))) {
		return json({ error: "No autorizado." }, 401)
	}

	const admin = createClient(supabaseUrl, secretKey, {
		auth: { persistSession: false, autoRefreshToken: false },
	})

	try {
		const body = await req.json()

		if (body?.accion === "mensaje") {
			const grupoId = String(body.grupoId ?? "")
			const remitenteId = String(body.remitenteId ?? "")
			const remitenteAlt = body.remitenteAlt ? String(body.remitenteAlt) : null
			const texto = String(body.texto ?? "").slice(0, 500)

			if (!GRUPO.test(grupoId) || !REMITENTE.test(remitenteId) || (remitenteAlt && !REMITENTE.test(remitenteAlt))) {
				return json({ error: "Datos del mensaje inválidos." }, 400)
			}

			const { data, error } = await admin.rpc("responder_comando_whatsapp", {
				p_grupo_id: grupoId,
				p_remitente_id: remitenteId,
				p_comando: texto,
				p_remitente_alt: remitenteAlt,
			})
			if (error) throw error

			return json({ respuesta: data ?? null })
		}

		if (body?.accion === "avisos_pendientes") {
			const { data, error } = await admin.rpc("tomar_avisos_whatsapp")
			if (error) throw error

			return json({
				avisos: (data ?? []).map((aviso: { id: string; grupo_id: string; mensaje: string }) => ({
					id: aviso.id,
					grupoId: aviso.grupo_id,
					mensaje: aviso.mensaje,
				})),
			})
		}

		if (body?.accion === "marcar_aviso") {
			const avisoId = String(body.avisoId ?? "")
			if (!UUID.test(avisoId) || typeof body.enviado !== "boolean") {
				return json({ error: "Datos del aviso inválidos." }, 400)
			}

			const { data, error } = await admin.rpc("marcar_aviso_whatsapp", {
				p_aviso_id: avisoId,
				p_enviado: body.enviado,
				p_error: body.enviado ? null : String(body.error ?? "").slice(0, 500),
			})
			if (error) throw error

			return json({ actualizado: data === true })
		}

		return json({ error: "Acción no soportada." }, 400)
	} catch (error) {
		console.error(error)
		return json({ error: "No pudimos procesar la solicitud." }, 500)
	}
})
