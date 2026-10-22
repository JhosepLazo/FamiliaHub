// Entiende preguntas escritas con palabras ("@FamiliaHub ¿cuánto debo?") y las convierte en los comandos
// equivalentes. No usa IA: corrige faltas comunes, reconoce frases habituales y separa varias preguntas en
// un mismo mensaje. Así la respuesta siempre sale de los datos de FamiliaHub, al instante y sin costo.

export type Intencion = { comando: string; argumento: string }
export type Social = "saludo" | "como_estas" | "gracias" | "despedida"
export type Analisis = { intenciones: Intencion[]; social: Social | null }

const MAX_INTENCIONES = 3
const MAX_LARGO = 400

// Palabras con las que la familia nombra sus servicios. Se pasan a /recibo, que también busca por tipo de
// servicio y por proveedor ("luz" encuentra Luz del Sur). "Claro" y "Win" no están porque en una charla casi
// siempre significan otra cosa ("claro que sí"); se pueden consultar con /recibo claro.
const SERVICIOS = [
	"luz del sur", "luz", "agua", "sedapal", "gas", "calidda", "internet", "wifi", "cable", "telefono", "celular", "movil",
	"netflix", "spotify", "disney", "alquiler", "mantenimiento", "siscom", "movistar", "entel", "bitel", "directv",
]

// Palabras comunes que nunca se corrigen hacia una del vocabulario ("luego" no es "llego").
const COMUNES = [
	"luego", "bueno", "buena", "nada", "ahora", "todo", "todos", "bien", "dinero", "plata", "familia", "grupo", "mensaje",
	"gente", "mama", "papa", "hermano", "hermana", "primero", "despues", "siempre", "nunca", "tengo", "tiene", "tienen",
	"puedo", "puede", "hacer", "quiero", "favor", "porfa", "entonces", "ellos", "nosotros", "usted", "ustedes", "mucho",
	"mucha", "poco", "solo", "cada", "otra", "otro", "cosa", "gusto", "claro", "listo", "dale", "bacan", "chevere", "genial",
	"perfecto", "excelente", "manana", "tarde", "noche", "semanas", "meses", "nuevo", "nueva", "hijo", "hija", "casa",
	"puedes", "sabes", "tienes", "quieres", "haces", "eres", "funciona", "maximo", "pasaste",
]

// Vocabulario de las frases: una palabra mal escrita se cambia por la de aquí que suena igual
// ("devo" → "debo", "recivo" → "recibo") o que difiere en una sola letra ("pendietes" → "pendientes").
const VOCABULARIO = [
	"debo", "debes", "debe", "deben", "deuda", "deudas", "cuota", "cuotas", "cuanto", "cuanta", "cuantos", "cuantas", "cuando",
	"quien", "quienes", "falta", "faltan", "pagar", "pago", "pague", "pagaron", "pagado", "pagos", "yape", "yapear", "yapee",
	"recibo", "recibos", "vence", "vencen", "vencimiento", "vencimientos", "vencido", "vencida", "vencidos", "vencidas",
	"pendiente", "pendientes", "resumen", "validar", "validacion", "ayuda", "comandos", "hola", "gracias", "llego", "llegaron",
	"vino", "salio", "semana", "como", "donde", "numero", "cuenta", "deposito", "transferi", "monto", "montos", "total",
	"saldo", "parte", "aportar", "toca", "estas", "chau", "adios", "buenos", "buenas", "dias", "tardes", "noches", "perfil",
	"tambien", "porque", "mensual", "recaudado", "juntado", "hasta", "yapeo", "transfiero", "pagan", "aporte",
	...SERVICIOS.filter((servicio) => !servicio.includes(" ")),
	...COMUNES,
]

const ABREVIATURAS: Record<string, string> = {
	q: "que", k: "que", ke: "que", xq: "porque", pq: "porque", porq: "porque", x: "por", tb: "tambien", tmb: "tambien",
	tbn: "tambien", cdo: "cuando", cnd: "cuando", cto: "cuanto", grax: "gracias", grx: "gracias", thx: "gracias",
	bn: "bien", msj: "mensaje", dnd: "donde", d: "de",
}

const palabras = (...alternativas: string[]) => new RegExp(`\\b(?:${alternativas.join("|")})\\b`)

const VALIDAR = palabras("por validar", "validar", "validacion", "validaciones", "confirmar pagos?", "pagos? por confirmar")
const PENDIENTES = palabras(
	"quien(?:es)? (?:falta|faltan|debe|deben|no (?:ha|han) pagado|no pago|no pagaron|esta pendiente|me debe|nos debe)",
	"pendientes", "faltan pagar", "falta pagar", "falta aportar", "faltan aportar", "cuanto (?:debe|deben|debes)",
	"(?:cuanto|que) (?:paga|le toca a) cada uno", "cada uno",
)
const DEUDA = palabras(
	"(?:cuanto|que) (?:debo|me toca|me falta|tengo que (?:pagar|aportar|dar|yapear)|pago yo|aporto)",
	"mi (?:deuda|cuota|parte|saldo)", "debo", "cuanto es lo mio", "estoy al dia", "tengo deuda",
)
const COMO_PAGAR = palabras(
	"(?:como|donde|a quien|a que numero) (?:pago|pagar|le pago|yapeo|le yapeo|deposito|transfiero)",
	"numero de (?:cuenta|yape)", "datos para pagar", "ya (?:pague|yapee|deposite|transferi)",
)
const VENCE = palabras(
	"vence", "vencen", "vencimientos?", "vencidos?", "vencidas?", "fecha limite", "hasta cuando",
	"cuando (?:hay que |toca )?pagar", "esta semana", "proximos dias",
)
const RECIBOS = palabras("recibos?", "cuanto (?:llego|llegaron|vino|vinieron|salio|salieron)", "montos?", "cuentas del mes")
const PAGAR = palabras("pagar", "yape", "yapear", "plin")
const RESUMEN = palabras(
	"resumen", "como vamos", "como va el mes", "estado del mes", "balance", "recaudado", "cuanto falta",
	"cuanto (?:se ha |hemos )?(?:juntado|recaudado)",
)
const YO = palabras("quien soy", "mi perfil", "estoy vinculad[oa]")
const AYUDA = palabras("ayuda", "comandos", "que (?:puedes|sabes) hacer", "menu", "opciones", "como funciona", "que haces")

const COMO_ESTAS = palabras("como estas", "como te va", "que tal estas", "todo bien")
const SALUDO = palabras("hola", "holi", "buenas", "buenos dias", "buen dia", "buenas tardes", "buenas noches", "que tal", "hey", "saludos")
const GRACIAS = palabras("gracias", "muchas gracias", "mil gracias", "thanks", "te pasaste", "eres lo maximo")
const DESPEDIDA = palabras("chau", "chao", "adios", "hasta luego", "nos vemos", "bye", "hasta manana")

// Separa "¿cuánto debo y cuándo vence?" en dos preguntas.
const SEPARADOR = /\s*(?:,|;|\by\b|\be\b|\bademas\b|\btambien\b|\bo\b)\s*/

export function normalizarTexto(texto: string) {
	return texto
		.slice(0, MAX_LARGO * 2)
		.normalize("NFD")
		.replace(/[̀-ͯ]/g, "")
		.toLowerCase()
		.replace(/@\d{5,}/g, " ")
		.replace(/[^a-z0-9\s,;]/g, " ")
		.replace(/\s+/g, " ")
		.trim()
		.slice(0, MAX_LARGO)
}

// Cómo suena una palabra: mismas letras para b/v, s/z/c suave, k/c fuerte/qu, y/ll; sin h muda ni letras repetidas.
export function sonido(palabra: string) {
	return palabra
		.replace(/ch/g, "§")
		.replace(/h/g, "")
		.replace(/§/g, "ch")
		.replace(/qu/g, "k")
		.replace(/c(?=[ei])/g, "s")
		.replace(/c/g, "k")
		.replace(/z/g, "s")
		.replace(/v/g, "b")
		.replace(/ll/g, "y")
		.replace(/y$/, "i")
		.replace(/(.)\1+/g, "$1")
}

const SONIDOS = new Map<string, string>()
for (const palabra of VOCABULARIO) if (!SONIDOS.has(sonido(palabra))) SONIDOS.set(sonido(palabra), palabra)
const CONOCIDAS = new Set(VOCABULARIO)

// Distancia de una letra (cambiada, sobrante, faltante o dos letras invertidas).
function difiereEnUna(a: string, b: string) {
	if (a === b || Math.abs(a.length - b.length) > 1) return false
	let i = 0
	while (i < a.length && i < b.length && a[i] === b[i]) i++
	if (a.length === b.length) {
		if (a.slice(i + 1) === b.slice(i + 1)) return true
		return a[i] === b[i + 1] && a[i + 1] === b[i] && a.slice(i + 2) === b.slice(i + 2)
	}
	const [larga, corta] = a.length > b.length ? [a, b] : [b, a]
	return larga.slice(i + 1) === corta.slice(i)
}

function corregirPalabra(palabra: string) {
	if (ABREVIATURAS[palabra]) return ABREVIATURAS[palabra]
	if (CONOCIDAS.has(palabra) || /\d/.test(palabra) || palabra.length < 3) return palabra
	const porSonido = SONIDOS.get(sonido(palabra))
	if (porSonido) return porSonido
	if (palabra.length < 5) return palabra
	return VOCABULARIO.find((conocida) => conocida.length >= 5 && conocida[0] === palabra[0] && difiereEnUna(palabra, conocida)) ?? palabra
}

export function corregir(texto: string) {
	return texto.split(" ").map(corregirPalabra).join(" ")
}

function servicioMencionado(texto: string) {
	return SERVICIOS.find((servicio) => palabras(servicio).test(texto)) ?? null
}

// El orden importa: lo más específico primero ("¿quién falta pagar?" es pendientes, no cómo pagar).
function intencionDe(texto: string): Intencion | null {
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

function socialDe(texto: string): Social | null {
	if (COMO_ESTAS.test(texto)) return "como_estas"
	if (GRACIAS.test(texto)) return "gracias"
	if (DESPEDIDA.test(texto)) return "despedida"
	if (SALUDO.test(texto)) return "saludo"
	return null
}

export function analizarPregunta(textoOriginal: string): Analisis {
	const texto = corregir(normalizarTexto(textoOriginal))
	const social = socialDe(texto)

	const intenciones: Intencion[] = []
	const agregar = (intencion: Intencion | null) => {
		if (!intencion || intenciones.length >= MAX_INTENCIONES) return
		if (intenciones.some((actual) => actual.comando === intencion.comando && actual.argumento === intencion.argumento)) return
		intenciones.push(intencion)
	}

	for (const parte of texto.split(SEPARADOR)) agregar(intencionDe(parte.trim()))
	// Si al separar se rompió una frase ("luz del sur"), se intenta con el mensaje completo.
	if (!intenciones.length) agregar(intencionDe(texto.replace(/[,;]/g, " ")))
	// La ayuda solo tiene sentido sola.
	const utiles = intenciones.length > 1 ? intenciones.filter((intencion) => intencion.comando !== "ayuda") : intenciones
	return { intenciones: utiles, social }
}

// Compatibilidad: la primera intención del mensaje.
export function detectarIntencion(textoOriginal: string): Intencion | null {
	return analizarPregunta(textoOriginal).intenciones[0] ?? null
}

export function primerNombre(nombre: unknown) {
	return typeof nombre === "string" && nombre.trim() ? nombre.trim().split(/\s+/)[0] : null
}

function saludoSegunHora(hora: number) {
	if (hora >= 5 && hora < 12) return "Buenos días"
	if (hora >= 12 && hora < 19) return "Buenas tardes"
	return "Buenas noches"
}

const con = (nombre: string | null) => (nombre ? `, ${nombre}` : "")

const EJEMPLOS = ["• ¿Cuánto debo?", "• ¿Quién falta pagar?", "• ¿Cuándo vence?", "• ¿Cuánto llegó la luz?"]

// Línea que antecede a las respuestas cuando el mensaje empieza con un saludo ("hola, ¿cuánto debo?").
export function encabezadoSaludo(nombre: string | null, hora: number) {
	return `¡${saludoSegunHora(hora)}${con(nombre)}! 👋`
}

export function respuestaSocial(social: Social, nombre: string | null, hora: number) {
	switch (social) {
		case "saludo":
			return [`¡${saludoSegunHora(hora)}${con(nombre)}! 👋 Soy el asistente de FamiliaHub. Puedes preguntarme:`, ...EJEMPLOS].join("\n")
		case "como_estas":
			return `¡Muy bien, gracias por preguntar${con(nombre)}! 😊 ¿Te ayudo con algo? Por ejemplo: "¿cuánto debo?"`
		case "gracias":
			return `¡De nada${con(nombre)}! 😊 Aquí estoy para lo que necesites.`
		case "despedida":
			return `¡Hasta luego${con(nombre)}! 👋`
	}
}

const ACUSES = new Set([
	"ok", "okey", "oki", "okis", "okay", "listo", "dale", "ya", "si", "sip", "no", "va", "vale", "bueno", "entendido", "perfecto",
	"genial", "claro", "bacan", "chevere", "excelente", "super", "jaja", "jajaja", "jajajaja", "jeje", "jejeje", "xd", "ah", "oh",
	"mmm", "uy", "wow", "yap", "ya ya", "de acuerdo", "a ya",
])

// "ok", "jaja", "👍": respuestas a un aviso del bot que no esperan contestación.
export function esAcuse(textoOriginal: string) {
	const texto = normalizarTexto(textoOriginal).replace(/[,;]/g, " ").replace(/\s+/g, " ").trim()
	if (!texto) return true
	return ACUSES.has(texto) || texto.split(" ").every((palabra) => ACUSES.has(palabra))
}

export function noEntendi(nombre: string | null) {
	return [`🤔 No te entendí del todo${con(nombre)}. Pregúntame, por ejemplo:`, ...EJEMPLOS, "O escribe /ayuda para ver todo lo que puedo hacer."].join("\n")
}
