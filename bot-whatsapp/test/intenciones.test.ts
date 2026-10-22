import assert from "node:assert/strict"
import { describe, test } from "node:test"
import {
	analizarPregunta,
	corregir,
	detectarIntencion,
	encabezadoSaludo,
	noEntendi,
	normalizarTexto,
	primerNombre,
	respuestaSocial,
} from "../../supabase/functions/bot-whatsapp/intenciones.ts"

const comandos = (texto: string) => analizarPregunta(texto).intenciones.map(({ comando, argumento }) => argumento ? `${comando} ${argumento}` : comando)

describe("una pregunta", () => {
	const casos: Array<[string, string | null, string?]> = [
		["@51987654321 ¿cuánto debo?", "deuda"],
		["Cuanto me toca este mes", "deuda"],
		["mi cuota", "deuda"],
		["cuánto debo de luz", "deuda"],
		["¿estoy al día?", "deuda"],
		["¿Quién falta pagar?", "pendientes"],
		["quienes no han pagado", "pendientes"],
		["cuanto debe liliana", "pendientes"],
		["cuánto paga cada uno", "pendientes"],
		["¿Cómo pago?", "pagar"],
		["a que numero le yapeo", "pagar"],
		["como pago la luz", "pagar"],
		["ya pagué", "pagar"],
		["¿Cuánto llegó la luz?", "recibo", "luz"],
		["cuando vence el agua", "recibo", "agua"],
		["recibo de Luz del Sur", "recibo", "luz del sur"],
		["cuánto vino el internet", "recibo", "internet"],
		["¿Cuándo vence?", "vence"],
		["que hay vencido", "vence"],
		["qué toca pagar esta semana", "vence"],
		["cuánto llegaron los recibos", "recibos"],
		["pagos por validar", "porvalidar"],
		["¿cómo vamos este mes?", "resumen"],
		["cuanto falta", "resumen"],
		["quien soy", "yo"],
		["¿qué puedes hacer?", "ayuda"],
		["jajaja qué buen día", null],
		["ok", null],
		["sí", null],
		["", null],
	]
	for (const [texto, comando, argumento = ""] of casos) {
		test(`"${texto}" → ${comando ?? "nada"}`, () => {
			const intencion = detectarIntencion(texto)
			if (comando === null) assert.equal(intencion, null)
			else assert.deepEqual(intencion, { comando, argumento })
		})
	}
})

describe("faltas de ortografía y abreviaturas", () => {
	const casos: Array<[string, string]> = [
		["kuanto devo", "deuda"],
		["cuanto debooo??", "deuda"],
		["cuamto debo", "deuda"],
		["kien falta pagar", "pendientes"],
		["q falta pagar", "pendientes"],
		["recivo de la lus", "recibo luz"],
		["cuando es el vensimiento", "vence"],
		["que se vencio", "vence"],
		["pendietes", "pendientes"],
		["resumem del mes", "resumen"],
		["komo pago", "pagar"],
		["cnd vence", "vence"],
	]
	for (const [texto, esperado] of casos) {
		test(`"${texto}" → ${esperado}`, () => assert.deepEqual(comandos(texto), [esperado]))
	}

	test("no cambia palabras comunes que no son del vocabulario", () => {
		assert.equal(corregir(normalizarTexto("tengo una duda con el grupo")), "tengo una duda con el grupo")
	})
})

describe("varias preguntas en un mensaje", () => {
	const casos: Array<[string, string[]]> = [
		["¿cuánto debo y cuándo vence?", ["deuda", "vence"]],
		["cuánto llegó la luz y el agua", ["recibo luz", "recibo agua"]],
		["cuanto debo, como pago", ["deuda", "pagar"]],
		["quién falta pagar y cuánto", ["pendientes"]],
		["luz, agua, gas e internet", ["recibo luz", "recibo agua", "recibo gas"]],
		["ayuda y cuánto debo", ["deuda"]],
		["cuánto debo y cuánto debo", ["deuda"]],
	]
	for (const [texto, esperado] of casos) {
		test(`"${texto}" → ${esperado.join(" + ")}`, () => assert.deepEqual(comandos(texto), esperado))
	}
})

describe("conversación", () => {
	const casos: Array<[string, string | null, string[]]> = [
		["hola", "saludo", []],
		["holaaa", "saludo", []],
		["Buenas tardes", "saludo", []],
		["hola, ¿cuánto debo?", "saludo", ["deuda"]],
		["¿cómo estás?", "como_estas", []],
		["gracias!!", "gracias", []],
		["grax", "gracias", []],
		["muchas gracias, ¿y cuánto debo?", "gracias", ["deuda"]],
		["chau", "despedida", []],
		["hasta luego", "despedida", []],
		["hasta cuándo hay que pagar", null, ["vence"]],
	]
	for (const [texto, social, esperado] of casos) {
		test(`"${texto}" → ${social ?? "sin saludo"} ${esperado.join("+")}`, () => {
			const analisis = analizarPregunta(texto)
			assert.equal(analisis.social, social)
			assert.deepEqual(analisis.intenciones.map(({ comando }) => comando), esperado)
		})
	}

	test("saluda según la hora de Lima y por el primer nombre", () => {
		assert.equal(encabezadoSaludo("Liliana", 9), "¡Buenos días, Liliana! 👋")
		assert.equal(encabezadoSaludo(null, 15), "¡Buenas tardes! 👋")
		assert.equal(encabezadoSaludo("Jhosep", 22), "¡Buenas noches, Jhosep! 👋")
		assert.equal(encabezadoSaludo("Jhosep", 3), "¡Buenas noches, Jhosep! 👋")
		assert.equal(primerNombre("  Liliana Lazo "), "Liliana")
		assert.equal(primerNombre(""), null)
		assert.equal(primerNombre(null), null)
	})

	test("respuestas sociales y de duda tienen texto y nombre", () => {
		for (const social of ["saludo", "como_estas", "gracias", "despedida"] as const) {
			assert.match(respuestaSocial(social, "Liliana", 10), /Liliana/)
			assert.doesNotMatch(respuestaSocial(social, null, 10), /, !|undefined|null/)
		}
		assert.match(noEntendi("Liliana"), /Liliana.*\n• ¿Cuánto debo\?/s)
		assert.match(noEntendi(null), /^🤔 No te entendí del todo\./)
	})
})

describe("estrés", () => {
	const alfabeto = "abcdefghijklmnñopqrstuvwxyzáéíóúü0123456789 ,;¿?¡!@#$%&/()=+*-_.:'\"\n\t😀🏠💰"
	const azar = (semilla: number) => () => {
		semilla = (semilla * 1_103_515_245 + 12_345) % 2_147_483_648
		return semilla / 2_147_483_648
	}

	test("20 000 mensajes al azar: nunca falla y siempre devuelve una forma válida", () => {
		const aleatorio = azar(42)
		const validos = new Set(["porvalidar", "pendientes", "deuda", "pagar", "recibo", "vence", "recibos", "resumen", "yo", "ayuda"])
		for (let i = 0; i < 20_000; i++) {
			const largo = Math.floor(aleatorio() * 300)
			let texto = ""
			for (let j = 0; j < largo; j++) texto += alfabeto[Math.floor(aleatorio() * alfabeto.length)]
			const analisis = analizarPregunta(texto)
			assert.ok(analisis.intenciones.length <= 3)
			for (const intencion of analisis.intenciones) {
				assert.ok(validos.has(intencion.comando), intencion.comando)
				assert.equal(typeof intencion.argumento, "string")
			}
		}
	})

	test("mensajes larguísimos o repetitivos se analizan en menos de 20 ms", () => {
		const peores = [
			"a".repeat(100_000),
			"cuanto ".repeat(20_000),
			"y ".repeat(50_000),
			"quien quien quien falta ".repeat(5_000),
			"vencimiento".repeat(10_000),
			", ; , ; ".repeat(20_000),
			"😀".repeat(30_000),
		]
		for (const texto of peores) {
			const inicio = performance.now()
			analizarPregunta(texto)
			const ms = performance.now() - inicio
			assert.ok(ms < 20, `${ms.toFixed(1)} ms con "${texto.slice(0, 12)}…"`)
		}
	})

	test("1 000 preguntas reales seguidas en menos de 1 segundo", () => {
		const frases = ["¿cuánto debo?", "kien falta pagar", "cuánto llegó la luz y el agua", "hola, cuándo vence", "gracias"]
		const inicio = performance.now()
		for (let i = 0; i < 1_000; i++) analizarPregunta(frases[i % frases.length])
		assert.ok(performance.now() - inicio < 1_000)
	})
})
