// Pruebas del lector de RecibosDigitales.gs fuera de Google: node --test recibos-digitales/lector.test.mjs
// Los correos son de ejemplo, escritos a mano con las formas más comunes de los recibos peruanos.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { describe, test } from 'node:test'
import vm from 'node:vm'

const codigo = readFileSync(new URL('./RecibosDigitales.gs', import.meta.url), 'utf8')
const contexto = {}
vm.runInNewContext(codigo + '\n;globalThis.__f = { leerRecibo, aNumero, htmlATexto };', contexto)
const { leerRecibo, aNumero, htmlATexto } = contexto.__f

const OCTUBRE = new Date('2026-10-10T15:00:00Z')
const leer = (texto, fecha = OCTUBRE) => {
	const r = leerRecibo(texto, fecha)
	return { suministros: [...r.suministros], monto: r.monto, vencimiento: r.vencimiento }
}

describe('recibos completos', () => {
	const casos = [
		['Luz del Sur: total a pagar con S/ y fecha numérica', 'N° de suministro: 1876543\nTotal a pagar: S/ 142.60\nFecha de vencimiento: 28/10/2026', ['1876543'], 142.6, '2026-10-28'],
		['SEDAPAL: coma decimal y fecha en letras', 'Suministro 2345678\nImporte a pagar S/. 55,90\nVence el 05 de noviembre de 2026', ['2345678'], 55.9, '2026-11-05'],
		['Cálidda: miles con coma y fecha con guiones', 'Número de cliente: 600123456\nMonto total a pagar: S/ 1,234.50\nFecha límite de pago: 15-11-2026', ['600123456'], 1234.5, '2026-11-15'],
		['Miles con punto y decimales con coma', 'Cliente 600123456 · Importe total: S/ 1.234,50 · Vencimiento: 1/12/26', ['600123456'], 1234.5, '2026-12-01'],
		['"Total" con S/', 'Suministro 1876543 — Total S/ 98.40 — pagar hasta el 30/10/2026', ['1876543'], 98.4, '2026-10-30'],
		['Correo en HTML', htmlATexto('<table><tr><td>N&deg; de suministro</td><td>1876543</td></tr><tr><td>Total a pagar</td><td>S/&nbsp;142.60</td></tr><tr><td>Fecha de vencimiento</td><td>28/10/2026</td></tr></table>'), ['1876543'], 142.6, '2026-10-28'],
		['Asunto con todo', 'Tu recibo de octubre por S/ 87.30 vence el 27/10/2026\nSuministro: 2345678', ['2345678'], 87.3, '2026-10-27'],
	]
	for (const [nombre, texto, suministros, monto, vencimiento] of casos) {
		test(nombre, () => assert.deepEqual(leer(texto), { suministros, monto, vencimiento }))
	}
})

describe('suministro oculto', () => {
	test('con asteriscos', () => assert.deepEqual(leer('Suministro: ****6543 · Total a pagar S/ 120.00 · Vence: 28/10/2026').suministros, ['*6543']))
	test('con X', () => assert.deepEqual(leer('Número de cliente XXXXX23456 Monto a pagar S/ 40.00 Vencimiento 15/11/2026').suministros, ['*23456']))
	test('suelto sin etiqueta', () => assert.deepEqual(leer('Tu recibo ****6543 ya está listo. Total a pagar S/ 70.00. Vence: 02/11/2026').suministros, ['*6543']))
	test('demasiado corto no cuenta', () => assert.deepEqual(leer('Suministro: ****543 Total a pagar S/ 70.00 Vence: 02/11/2026').suministros, []))
})

describe('más formas de escribir el monto', () => {
	const casos = [
		['Importe: S/ 55.90', 55.9],
		['Monto: S/ 120', 120],
		['Importe del mes S/ 63.20', 63.2],
		['Tu deuda es de S/ 41.10', 41.1],
		['Saldo a pagar: S/ 15.00', 15],
		['Total del recibo: 88.80', 88.8],
		['Recibo de octubre. A pagar: S/ 33.33', 33.33],
		['Hola, tu recibo está listo por S/ 74.50. Gracias por tu preferencia.', 74.5],
	]
	for (const [texto, monto] of casos) test(texto, () => assert.equal(leer(texto).monto, monto))

	test('deuda anterior en cero no se toma como monto', () => assert.equal(leer('Deuda anterior: S/ 0.00\nTotal a pagar: S/ 90.00').monto, 90))
	test('dos montos sin etiqueta: no adivina', () => assert.equal(leer('Consumo S/ 80.00, cargo fijo S/ 5.00').monto, null))
	test('kWh no es dinero', () => assert.equal(leer('Suministro: 1876543\nTotal consumo 120 kWh\nVence: 28 oct 2026').monto, null))
})

describe('más formas de escribir el vencimiento', () => {
	const casos = [
		['Paga hasta el 28/10/2026', '2026-10-28'],
		['Pague antes del 3 de noviembre de 2026', '2026-11-03'],
		['Vencerá el 15-11-2026', '2026-11-15'],
		['Vence el 25/10', '2026-10-25'],
		['Vence: 28 oct', '2026-10-28'],
		['Fecha de pago: 30/10/2026', '2026-10-30'],
	]
	for (const [texto, fecha] of casos) test(texto, () => assert.equal(leer(texto).vencimiento, fecha))

	test('sin año en diciembre: el año siguiente si ya pasó', () => assert.equal(leer('Vence el 05/01', new Date('2026-12-20T15:00:00Z')).vencimiento, '2027-01-05'))
	test('fecha imposible se descarta', () => assert.equal(leer('Fecha de vencimiento 31/02/2026').vencimiento, null))
})

describe('correos que no son recibos', () => {
	test('promoción', () => assert.deepEqual(leer('Conoce nuestras nuevas ofertas en gasodomésticos. Visita nuestra tienda.'), { suministros: [], monto: null, vencimiento: null }))
	test('bienvenida de SEDAPAL', () => {
		const r = leer('Le damos la bienvenida al recibo digital de SEDAPAL. A partir del próximo mes le estaremos enviando sus recibos en formato digital. AQUAFONO 317-8000.')
		assert.equal(r.monto, null)
		assert.equal(r.vencimiento, null)
	})
})

describe('números', () => {
	for (const [entrada, salida] of [['1,234.50', 1234.5], ['1.234,50', 1234.5], ['55,90', 55.9], ['142.60', 142.6], ['1.234', 1234], ['1,234', 1234], ['80', 80]]) {
		test(`${entrada} → ${salida}`, () => assert.equal(aNumero(entrada), salida))
	}
})

describe('estrés', () => {
	test('5 000 correos al azar en menos de 2 segundos y sin fallar', () => {
		const piezas = ['Total a pagar', 'S/', '123.45', 'Vence', '28/10/2026', 'Suministro', '****6543', '1876543', 'kWh', 'de', '\n', ':', 'Importe', 'Monto', 'Deuda', '01/13/2026']
		let semilla = 7
		const azar = () => (semilla = (semilla * 1103515245 + 12345) % 2147483648) / 2147483648
		const inicio = performance.now()
		for (let i = 0; i < 5000; i++) {
			let texto = ''
			for (let j = 0; j < 40; j++) texto += piezas[Math.floor(azar() * piezas.length)] + ' '
			const r = leerRecibo(texto, OCTUBRE)
			assert.ok(r.monto === null || (r.monto > 0 && r.monto <= 100000))
			assert.ok(r.vencimiento === null || /^\d{4}-\d{2}-\d{2}$/.test(r.vencimiento))
			assert.ok(r.suministros.length <= 10)
		}
		assert.ok(performance.now() - inicio < 2000)
	})

	test('correo de 200 KB se lee en menos de 200 ms', () => {
		const texto = 'Estimado cliente '.repeat(12000) + ' Total a pagar S/ 99.90 Vence: 28/10/2026 Suministro: 1876543'
		const inicio = performance.now()
		assert.equal(leer(texto).monto, 99.9)
		assert.ok(performance.now() - inicio < 200)
	})
})
