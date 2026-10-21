import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "npm:@supabase/supabase-js@2.117.2"

// Recibe del script de Gmail lo leído en un recibo digital (suministro, monto y vencimiento) y se lo pasa a
// registrar_recibo_digital, que decide si confirma el recibo del mes. No guarda el texto del correo.

const LARGO_MAX_CUERPO = 4_096
const PROVEEDORES = new Set(["SEDAPAL", "LUZ_DEL_SUR", "CALIDDA"])

class SolicitudInvalida extends Error {}

const json = (body: unknown, status = 200) =>
	new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } })

const codificador = new TextEncoder()
const secretoRecibos = Deno.env.get("FAMILIAHUB_RECIBOS_SECRET") ?? ""
const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}")
const supabase = createClient(
	Deno.env.get("SUPABASE_URL") ?? "",
	secretKeys.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
	{ auth: { persistSession: false, autoRefreshToken: false } },
)

async function resumenSha256(valor: string) {
	return new Uint8Array(await crypto.subtle.digest("SHA-256", codificador.encode(valor)))
}

// Se comparan los resúmenes SHA-256 byte a byte para que el tiempo no dependa del contenido.
async function secretoValido(recibido: string | null) {
	if (!recibido || !secretoRecibos) return false
	const [a, b] = await Promise.all([resumenSha256(recibido), resumenSha256(secretoRecibos)])
	let diferencia = 0
	for (let i = 0; i < a.length; i++) diferencia |= a[i] ^ b[i]
	return diferencia === 0
}

function texto(valor: unknown, largoMaximo: number) {
	if (typeof valor !== "string" || !valor.trim() || valor.length > largoMaximo) throw new SolicitudInvalida()
	return valor.trim()
}

function suministros(valor: unknown) {
	if (!Array.isArray(valor) || valor.length === 0 || valor.length > 10) throw new SolicitudInvalida()
	return valor.map((item) => texto(item, 30))
}

function monto(valor: unknown) {
	if (typeof valor !== "number" || !Number.isFinite(valor) || valor <= 0 || valor > 100_000) throw new SolicitudInvalida()
	return Math.round(valor * 100) / 100
}

function fecha(valor: unknown) {
	const iso = texto(valor, 10)
	if (!/^\d{4}-\d{2}-\d{2}$/.test(iso) || Number.isNaN(Date.parse(`${iso}T00:00:00Z`))) throw new SolicitudInvalida()
	return iso
}

Deno.serve(async (req) => {
	if (req.method !== "POST") return json({ error: "Método no permitido." }, 405)
	if (!(await secretoValido(req.headers.get("x-recibos-secret")))) return json({ error: "No autorizado." }, 401)

	try {
		const crudo = await req.text()
		if (crudo.length > LARGO_MAX_CUERPO) throw new SolicitudInvalida()
		const cuerpo = JSON.parse(crudo) as Record<string, unknown>

		// Sirve para que el script compruebe la conexión al instalarse, sin registrar nada.
		if (cuerpo.accion === "ping") return json({ ok: true })

		const proveedor = texto(cuerpo.proveedor, 20)
		if (!PROVEEDORES.has(proveedor)) throw new SolicitudInvalida()

		const { data, error } = await supabase.rpc("registrar_recibo_digital", {
			p_mensaje_id: texto(cuerpo.mensajeId, 200),
			p_proveedor: proveedor,
			p_suministros: suministros(cuerpo.suministros),
			p_monto: monto(cuerpo.monto),
			p_fecha_vencimiento: fecha(cuerpo.vencimiento),
		})

		if (error) {
			if (error.code === "P0001") return json({ error: error.message }, 422)
			throw error
		}

		console.log(JSON.stringify({ proveedor, estado: (data as { estado?: string })?.estado }))
		return json(data)
	} catch (error) {
		if (error instanceof SolicitudInvalida || error instanceof SyntaxError) return json({ error: "Solicitud inválida." }, 400)
		console.error(error instanceof Error ? error.message : String(error))
		return json({ error: "Error interno." }, 500)
	}
})
