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

const invalidCredentials = () =>
	json({ error: "Usuario o contraseña incorrectos." }, 401)

Deno.serve(async (req) => {
	if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })
	if (req.method !== "POST") return json({ error: "Método no permitido." }, 405)

	try {
		const { usuario, password } = await req.json()
		const normalizedUser = String(usuario ?? "").trim()
		const normalizedLookup = normalizedUser.toLowerCase()
		const rawPassword = String(password ?? "")

		if (!/^[A-Za-z][A-Za-z0-9._-]{2,29}$/.test(normalizedUser) || rawPassword.length < 8) {
			return invalidCredentials()
		}

		const publishableKeys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}")
		const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}")
		const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? ""
		const publishableKey = publishableKeys.default
		const secretKey = secretKeys.default

		if (!supabaseUrl || !publishableKey || !secretKey) {
			return json({ error: "Configuración de autenticación incompleta." }, 500)
		}

		const admin = createClient(supabaseUrl, secretKey, {
			auth: { persistSession: false, autoRefreshToken: false },
		})

		const { data: profile, error: profileError } = await admin
			.from("perfiles")
			.select("id")
			.eq("usuario_normalizado", normalizedLookup)
			.maybeSingle()

		if (profileError || !profile?.id) {
			await new Promise((resolve) => setTimeout(resolve, 200))
			return invalidCredentials()
		}

		const { data: authUser, error: authUserError } = await admin.auth.admin.getUserById(profile.id)
		const email = authUser.user?.email

		if (authUserError || !email) {
			await new Promise((resolve) => setTimeout(resolve, 200))
			return invalidCredentials()
		}

		const client = createClient(supabaseUrl, publishableKey, {
			auth: { persistSession: false, autoRefreshToken: false },
		})

		const { data, error } = await client.auth.signInWithPassword({
			email,
			password: rawPassword,
		})

		if (error || !data.session) return invalidCredentials()

		return json({
			session: {
				access_token: data.session.access_token,
				refresh_token: data.session.refresh_token,
				expires_at: data.session.expires_at,
				expires_in: data.session.expires_in,
				token_type: data.session.token_type,
			},
		})
	} catch (error) {
		console.error(error)
		return json({ error: "No pudimos iniciar sesión." }, 500)
	}
})
