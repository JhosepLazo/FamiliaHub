import assert from "node:assert/strict"
import { test } from "node:test"
import { detectarIntencion } from "../../supabase/functions/bot-whatsapp/intenciones.ts"

const casos: Array<[string, string | null, string?]> = [
	["@51987654321 ¿cuánto debo?", "deuda"],
	["Cuanto me toca este mes", "deuda"],
	["mi cuota", "deuda"],
	["cuánto debo de luz", "deuda"],
	["¿Quién falta pagar?", "pendientes"],
	["quienes no han pagado", "pendientes"],
	["¿Cómo pago?", "pagar"],
	["a que numero le yapeo", "pagar"],
	["como pago la luz", "pagar"],
	["¿Cuánto llegó la luz?", "recibo", "luz"],
	["cuando vence el agua", "recibo", "agua"],
	["recibo de Luz del Sur", "recibo", "luz del sur"],
	["cuánto vino el internet", "recibo", "internet"],
	["¿Cuándo vence?", "vence"],
	["que hay vencido", "vence"],
	["cuánto llegaron los recibos", "recibos"],
	["pagos por validar", "porvalidar"],
	["¿cómo vamos este mes?", "resumen"],
	["quien soy", "yo"],
	["hola", "ayuda"],
	["¿qué puedes hacer?", "ayuda"],
	["jajaja qué buen día", null],
	["", null],
]

for (const [texto, comando, argumento = ""] of casos) {
	test(`"${texto}" → ${comando ?? "sin intención"}`, () => {
		const intencion = detectarIntencion(texto)
		if (comando === null) {
			assert.equal(intencion, null)
			return
		}
		assert.deepEqual(intencion, { comando, argumento })
	})
}
