// Entiende preguntas escritas con palabras ("@FamiliaHub ¿cuánto debo?") y las convierte en el comando
// equivalente. No usa IA: son frases comunes, así la respuesta siempre sale de los datos de FamiliaHub.

export type Intencion = { comando: string; argumento: string }

// Palabras con las que la familia nombra sus servicios. Se pasan a /recibo, que también busca por tipo de
// servicio y por proveedor ("luz" encuentra Luz del Sur).
const SERVICIOS = [
	"luz del sur", "luz", "agua", "sedapal", "gas", "calidda", "internet", "wifi", "cable", "telefono", "celular", "movil",
	"netflix", "spotify", "disney", "alquiler", "mantenimiento", "siscom", "movistar", "claro", "entel", "bitel", "win", "directv",
]

const palabras = (...alternativas: string[]) => new RegExp(`\\b(?:${alternativas.join("|")})\\b`)

const VALIDAR = palabras("por validar", "validar", "validacion", "validaciones", "confirmar pagos?", "pagos? por confirmar")
const PENDIENTES = palabras(
	"quien(?:es)? (?:falta|faltan|debe|deben|no (?:ha|han) pagado|no pago|no pagaron|esta pendiente)",
	"pendientes", "faltan pagar", "falta pagar", "falta aportar", "faltan aportar",
)
const DEUDA = palabras(
	"(?:cuanto|que) (?:debo|me toca|me falta|tengo que (?:pagar|aportar|dar|yapear)|pago yo|aporto)",
	"mi (?:deuda|cuota|parte|saldo)", "debo", "cuanto es lo mio",
)
const COMO_PAGAR = palabras(
	"(?:como|donde|a quien|a que numero) (?:pago|pagar|le pago|yapeo|le yapeo|deposito|transfiero)",
	"numero de (?:cuenta|yape)", "datos para pagar",
)
const VENCE = palabras(
	"vence", "vencen", "vencimientos?", "vencidos?", "vencidas?", "fecha limite", "hasta cuando", "cuando (?:hay que |toca )?pagar",
)
const RECIBOS = palabras("recibos?", "cuanto (?:llego|llegaron|vino|vinieron|salio|salieron)", "montos?", "cuentas del mes")
const PAGAR = palabras("pagar", "yape", "yapear", "plin")
const RESUMEN = palabras("resumen", "como vamos", "como va el mes", "estado del mes", "balance", "recaudado", "cuanto (?:se ha |hemos )?(?:juntado|recaudado)")
const YO = palabras("quien soy", "mi perfil", "estoy vinculad[oa]")
const AYUDA = palabras("ayuda", "comandos", "que (?:puedes|sabes) hacer", "menu", "opciones", "hola", "buenas", "buenos dias", "buenas tardes", "buenas noches")

export function normalizarTexto(texto: string) {
	return texto
		.normalize("NFD")
		.replace(/[̀-ͯ]/g, "")
		.toLowerCase()
		.replace(/@\d{5,}/g, " ")
		.replace(/[^a-z0-9\s]/g, " ")
		.replace(/\s+/g, " ")
		.trim()
}

function servicioMencionado(texto: string) {
	return SERVICIOS.find((servicio) => palabras(servicio).test(texto)) ?? null
}

// El orden importa: lo más específico primero ("¿quién falta pagar?" es pendientes, no cómo pagar).
export function detectarIntencion(textoOriginal: string): Intencion | null {
	const texto = normalizarTexto(textoOriginal)
	if (!texto) return null

	if (VALIDAR.test(texto)) return { comando: "porvalidar", argumento: "" }
	if (PENDIENTES.test(texto)) return { comando: "pendientes", argumento: "" }
	if (DEUDA.test(texto)) return { comando: "deuda", argumento: "" }
	if (COMO_PAGAR.test(texto)) return { comando: "pagar", argumento: "" }

	const servicio = servicioMencionado(texto)
	if (servicio) return { comando: "recibo", argumento: servicio }

	if (VENCE.test(texto)) return { comando: "vence", argumento: "" }
	if (RECIBOS.test(texto)) return { comando: "recibos", argumento: "" }
	if (PAGAR.test(texto)) return { comando: "pagar", argumento: "" }
	if (RESUMEN.test(texto)) return { comando: "resumen", argumento: "" }
	if (YO.test(texto)) return { comando: "yo", argumento: "" }
	if (AYUDA.test(texto)) return { comando: "ayuda", argumento: "" }
	return null
}

export const NO_ENTENDI = [
	"🤔 No te entendí del todo. Pregúntame, por ejemplo:",
	"• ¿Cuánto debo?",
	"• ¿Quién falta pagar?",
	"• ¿Cuándo vence?",
	"• ¿Cuánto llegó la luz?",
	"O escribe /ayuda para ver todo lo que puedo hacer.",
].join("\n")
