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

		const jwt = authHeader.replace("Bearer ", "")
		const { data: userData, error: userError } = await userClient.auth.getUser(jwt)
		const user = userData.user
		if (userError || !user?.email) return json({ error: "Sesión inválida." }, 401)

		const { token } = await req.json()
		const rawToken = String(token ?? "").trim()
		if (rawToken.length < 40) return json({ error: "Invitación inválida." }, 400)

		const tokenHash = await hashToken(rawToken)
		const { data: invitation, error: invitationError } = await adminClient
			.from("invitaciones")
			.select("id, familia_id, nombre, email, rol, estado, expira_at")
			.eq("token_hash", tokenHash)
			.maybeSingle()

		if (invitationError || !invitation) return json({ error: "Invitación no encontrada." }, 404)
		if (invitation.estado !== "PENDIENTE") return json({ error: "Esta invitación ya no está disponible." }, 409)
		if (new Date(invitation.expira_at).getTime() <= Date.now()) {
			await adminClient.from("invitaciones").update({ estado: "EXPIRADA" }).eq("id", invitation.id)
			return json({ error: "La invitación venció." }, 410)
		}
		if (invitation.email.toLowerCase() !== user.email.toLowerCase()) {
			return json({ error: "La invitación pertenece a otro correo." }, 403)
		}

		const { data: activeMembership } = await adminClient
			.from("miembros_familia")
			.select("familia_id")
			.eq("usuario_id", user.id)
			.eq("estado", "ACTIVO")
			.maybeSingle()

		if (activeMembership && activeMembership.familia_id !== invitation.familia_id) {
			return json({ error: "Ya perteneces a otra familia activa." }, 409)
		}

		if (!activeMembership) {
			const { error: memberError } = await adminClient.from("miembros_familia").insert({
				familia_id: invitation.familia_id,
				usuario_id: user.id,
				rol: invitation.rol,
			})
			if (memberError) throw memberError
		}

		if (invitation.nombre) {
			const { data: profile } = await adminClient.from("perfiles").select("nombre").eq("id", user.id).maybeSingle()
			if (!profile?.nombre) {
				await adminClient.from("perfiles").update({ nombre: invitation.nombre, updated_at: new Date().toISOString() }).eq("id", user.id)
			}
		}

		const { error: updateError } = await adminClient
			.from("invitaciones")
			.update({ estado: "ACEPTADA", aceptada_at: new Date().toISOString() })
			.eq("id", invitation.id)

		if (updateError) throw updateError

		return json({ familiaId: invitation.familia_id })
	} catch (error) {
		console.error(error)
		return json({ error: "No pudimos aceptar la invitación." }, 500)
	}
})
