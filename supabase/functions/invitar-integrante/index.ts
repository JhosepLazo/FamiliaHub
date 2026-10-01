import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "npm:@supabase/supabase-js@2.117.2"

const corsHeaders = {
	"Access-Control-Allow-Origin": "*",
	"Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
	"Access-Control-Allow-Methods": "POST, OPTIONS",
	"Content-Type": "application/json",
}

const json = (body: unknown, status = 200) =>
	new Response(JSON.stringify(body), { status, headers: corsHeaders })

const hashToken = async (token: string) => {
	const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token))
	return Array.from(new Uint8Array(hash)).map((byte) => byte.toString(16).padStart(2, "0")).join("")
}

const randomToken = () => {
	const bytes = crypto.getRandomValues(new Uint8Array(32))
	return Array.from(bytes).map((byte) => byte.toString(16).padStart(2, "0")).join("")
}

Deno.serve(async (req) => {
	if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })
	if (req.method !== "POST") return json({ error: "Método no permitido." }, 405)

	try {
		const authHeader = req.headers.get("Authorization")
		if (!authHeader?.startsWith("Bearer ")) return json({ error: "Sesión requerida." }, 401)

		const publishableKeys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}")
		const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}")
		const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? ""
		const publishableKey = publishableKeys.default
		const secretKey = secretKeys.default

		if (!supabaseUrl || !publishableKey || !secretKey) return json({ error: "Configuración incompleta." }, 500)

		const userClient = createClient(supabaseUrl, publishableKey, {
			global: { headers: { Authorization: authHeader } },
			auth: { persistSession: false, autoRefreshToken: false },
		})
		const adminClient = createClient(supabaseUrl, secretKey, {
			auth: { persistSession: false, autoRefreshToken: false },
		})

		const tokenJwt = authHeader.replace("Bearer ", "")
		const { data: userData, error: userError } = await userClient.auth.getUser(tokenJwt)
		const user = userData.user
		if (userError || !user) return json({ error: "Sesión inválida." }, 401)

		const { familiaId, nombre, email, rol = "INTEGRANTE" } = await req.json()
		const normalizedEmail = String(email ?? "").trim().toLowerCase()
		const normalizedName = String(nombre ?? "").trim()
		const normalizedRole = rol === "ADMINISTRADOR" ? "ADMINISTRADOR" : "INTEGRANTE"

		if (!familiaId || !normalizedName || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizedEmail)) {
			return json({ error: "Nombre, correo y familia son obligatorios." }, 400)
		}

		const { data: membership, error: membershipError } = await userClient
			.from("miembros_familia")
			.select("rol, estado")
			.eq("familia_id", familiaId)
			.eq("usuario_id", user.id)
			.maybeSingle()

		if (membershipError || membership?.rol !== "ADMINISTRADOR" || membership.estado !== "ACTIVO") {
			return json({ error: "Solo un administrador puede invitar integrantes." }, 403)
		}

		const { data: existing, error: existingError } = await adminClient
			.from("invitaciones")
			.select("id, expira_at")
			.eq("familia_id", familiaId)
			.eq("email", normalizedEmail)
			.eq("estado", "PENDIENTE")
			.order("created_at", { ascending: false })
			.limit(1)
			.maybeSingle()

		if (existingError) throw existingError

		if (existing) {
			if (new Date(existing.expira_at).getTime() > Date.now()) {
				return json({ error: "Ya existe una invitación pendiente para este correo." }, 409)
			}

			const { error: expireError } = await adminClient
				.from("invitaciones")
				.update({ estado: "EXPIRADA" })
				.eq("id", existing.id)

			if (expireError) throw expireError
		}

		const token = randomToken()
		const tokenHash = await hashToken(token)
		const expiraAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString()

		const { error: insertError } = await adminClient.from("invitaciones").insert({
			familia_id: familiaId,
			nombre: normalizedName,
			email: normalizedEmail,
			rol: normalizedRole,
			token_hash: tokenHash,
			expira_at: expiraAt,
			creado_por: user.id,
		})

		if (insertError?.code === "23505") {
			return json({ error: "Ya existe una invitación pendiente para este correo." }, 409)
		}
		if (insertError) throw insertError

		return json({ token, expiraAt })
	} catch (error) {
		console.error(error)
		return json({ error: "No pudimos crear la invitación." }, 500)
	}
})
