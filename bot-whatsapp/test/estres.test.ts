import assert from "node:assert/strict"
import { afterEach, beforeEach, describe, mock, test } from "node:test"
import type { Logger } from "pino"
import { EDAD_MAX_MENSAJE_S, INTERVALO_MIN_ENVIO_MS } from "../src/config.ts"
import { Deduplicador, LimitadorFrecuencia } from "../src/control.ts"
import { ColaEnvios, type SocketEnvio } from "../src/envios.ts"

// Pruebas de estrés de la pasarela del bot con reloj simulado: ráfagas de cientos de mensajes, fallas de
// WhatsApp y desconexiones. Verifican que nunca se envíen dos mensajes a la vez, que se respete la pausa
// entre envíos, que la cola se vacíe y que la memoria no crezca sin límite.

const silencio = { info() {}, warn() {}, error() {}, debug() {} } as unknown as Logger
const pausa = () => new Promise<void>((resolver) => setImmediate(resolver))

type Evento = { tipo: "composing" | "paused" | "mensaje"; grupo: string; texto?: string; momento: number }

function socketFalso(fallaCada = 0) {
	const eventos: Evento[] = []
	let enVuelo = 0
	let maximoEnVuelo = 0
	let mensajes = 0
	const socket: SocketEnvio = {
		async sendPresenceUpdate(tipo, grupo) {
			eventos.push({ tipo, grupo, momento: Date.now() })
		},
		async sendMessage(grupo, contenido) {
			enVuelo++
			maximoEnVuelo = Math.max(maximoEnVuelo, enVuelo)
			await pausa()
			enVuelo--
			mensajes++
			if (fallaCada && mensajes % fallaCada === 0) throw new Error("WhatsApp no respondió")
			eventos.push({ tipo: "mensaje", grupo, texto: (contenido as { text: string }).text, momento: Date.now() })
			return {}
		},
	}
	return { socket, eventos, maximoEnVuelo: () => maximoEnVuelo }
}

// Avanza el reloj simulado de a poco, dejando correr las promesas entre cada paso.
async function avanzar(ms: number, paso = 250) {
	for (let transcurrido = 0; transcurrido < ms; transcurrido += paso) {
		mock.timers.tick(paso)
		await pausa()
		await pausa()
	}
}

describe("cola de envíos bajo estrés", () => {
	beforeEach(() => mock.timers.enable({ apis: ["setTimeout", "Date"], now: 1_800_000_000_000 }))
	afterEach(() => mock.timers.reset())

	test("ráfaga de 300 respuestas en 5 grupos: en orden, de a una, con pausa mínima y sin mensajes viejos", async () => {
		const { socket, eventos, maximoEnVuelo } = socketFalso()
		const cola = new ColaEnvios({ obtenerSocket: () => socket, estaConectado: () => true, api: { marcarAviso: async () => {} }, logger: silencio })

		for (let i = 0; i < 300; i++) cola.responder(`12036300000000000${i % 5}@g.us`, `respuesta ${i}`, [])
		await avanzar((EDAD_MAX_MENSAJE_S + 120) * 1_000, 500)

		const enviados = eventos.filter((evento) => evento.tipo === "mensaje")
		assert.equal(cola.tamano, 0, "la cola debe quedar vacía")
		assert.equal(maximoEnVuelo(), 1, "nunca dos envíos a la vez")
		assert.ok(enviados.length > 100, `se enviaron ${enviados.length}`)

		// En orden de llegada: los números de respuesta siempre crecen.
		const numeros = enviados.map((evento) => Number(evento.texto?.split(" ")[1]))
		assert.deepEqual(numeros, [...numeros].sort((a, b) => a - b))
		// Pausa mínima entre mensajes (contando el "escribiendo…").
		for (let i = 1; i < enviados.length; i++) {
			assert.ok(enviados[i].momento - enviados[i - 1].momento >= INTERVALO_MIN_ENVIO_MS, `envío ${i} demasiado seguido`)
		}
		// Lo que esperó más de 10 minutos se descartó en vez de contestar algo viejo.
		const primero = 1_800_000_000_000
		for (const evento of enviados) assert.ok(evento.momento - primero <= (EDAD_MAX_MENSAJE_S + 5) * 1_000)
		// Cada mensaje tuvo su "escribiendo…" antes y su "pausa" después.
		assert.equal(eventos.filter((evento) => evento.tipo === "composing").length, enviados.length)
		assert.equal(eventos.filter((evento) => evento.tipo === "paused").length, enviados.length)
	})

	test("si WhatsApp falla cada 3 envíos, sigue con los demás y marca los avisos fallidos", async () => {
		const { socket, eventos } = socketFalso(3)
		const marcas: Array<[string, boolean]> = []
		const cola = new ColaEnvios({
			obtenerSocket: () => socket,
			estaConectado: () => true,
			api: { marcarAviso: async (id, enviado) => { marcas.push([id, enviado]) } },
			logger: silencio,
		})

		for (let i = 0; i < 30; i++) cola.encolarAviso({ id: `aviso-${i}`, grupoId: "120363000000000001@g.us", texto: `aviso ${i}`, menciones: [] })
		await avanzar(200_000, 500)

		assert.equal(cola.tamano, 0)
		assert.equal(marcas.length, 30, "todos los avisos quedan marcados")
		assert.equal(marcas.filter(([, enviado]) => !enviado).length, 10, "un tercio falló")
		assert.equal(eventos.filter((evento) => evento.tipo === "mensaje").length, 20)
	})

	test("un aviso repetido no se encola dos veces", async () => {
		const { socket, eventos } = socketFalso()
		const cola = new ColaEnvios({ obtenerSocket: () => socket, estaConectado: () => true, api: { marcarAviso: async () => {} }, logger: silencio })
		const aviso = { id: "a1", grupoId: "120363000000000001@g.us", texto: "Llegó la luz", menciones: [] }
		cola.encolarAviso(aviso)
		cola.encolarAviso(aviso)
		cola.encolarAviso(aviso)
		await avanzar(20_000)
		assert.equal(eventos.filter((evento) => evento.tipo === "mensaje").length, 1)
	})

	test("un aviso ya enviado que vuelve a llegar (su confirmación no llegó) no se publica de nuevo", async () => {
		const { socket, eventos } = socketFalso()
		const cola = new ColaEnvios({ obtenerSocket: () => socket, estaConectado: () => true, api: { marcarAviso: async () => { throw new Error("sin red") } }, logger: silencio })
		const aviso = { id: "a2", grupoId: "120363000000000001@g.us", texto: "Vence hoy", menciones: [] }
		cola.encolarAviso(aviso)
		await avanzar(20_000)
		cola.encolarAviso(aviso)
		await avanzar(20_000)
		assert.equal(eventos.filter((evento) => evento.tipo === "mensaje").length, 1)
	})

	test("desconectado no envía nada; al reconectar envía lo pendiente", async () => {
		const { socket, eventos } = socketFalso()
		let conectado = false
		const cola = new ColaEnvios({ obtenerSocket: () => socket, estaConectado: () => conectado, api: { marcarAviso: async () => {} }, logger: silencio })

		for (let i = 0; i < 5; i++) cola.responder("120363000000000001@g.us", `r${i}`, [])
		await avanzar(30_000)
		assert.equal(eventos.length, 0)
		assert.equal(cola.tamano, 5)

		conectado = true
		cola.reanudar()
		await avanzar(60_000)
		assert.equal(eventos.filter((evento) => evento.tipo === "mensaje").length, 5)
		assert.equal(cola.tamano, 0)
	})

	test("si FamiliaHub no recibe las confirmaciones, guarda como máximo 50 y las reintenta", async () => {
		const { socket } = socketFalso()
		let caido = true
		const confirmadas: string[] = []
		const cola = new ColaEnvios({
			obtenerSocket: () => socket,
			estaConectado: () => true,
			api: { marcarAviso: async (id) => { if (caido) throw new Error("sin red"); confirmadas.push(id) } },
			logger: silencio,
		})

		for (let i = 0; i < 80; i++) cola.encolarAviso({ id: `m-${i}`, grupoId: "120363000000000001@g.us", texto: `aviso ${i}`, menciones: [] })
		await avanzar(400_000, 1_000)
		const guardadas = (cola as unknown as { marcasPendientes: unknown[] }).marcasPendientes.length
		assert.ok(guardadas <= 50, `guardó ${guardadas}`)

		caido = false
		await cola.reintentarMarcas()
		assert.equal(confirmadas.length, guardadas)
		assert.equal((cola as unknown as { marcasPendientes: unknown[] }).marcasPendientes.length, 0)
	})
})

describe("memoria acotada", () => {
	test("el deduplicador recuerda como máximo su límite aunque lleguen 100 000 mensajes", () => {
		const deduplicador = new Deduplicador(1_000)
		for (let i = 0; i < 100_000; i++) assert.equal(deduplicador.visto(`mensaje-${i}`), false)
		assert.equal(deduplicador.tamano, 1_000)
		assert.equal(deduplicador.visto("mensaje-99999"), true, "recuerda los más recientes")
		assert.equal(deduplicador.visto("mensaje-0"), false, "olvida los más antiguos")
	})

	test("el limitador no acumula remitentes viejos (10 000 personas distintas en un día)", () => {
		let ahora = 0
		const limitador = new LimitadorFrecuencia(5, 60_000, () => ahora)
		for (let i = 0; i < 10_000; i++) {
			ahora += 9_000
			limitador.permitir(`persona-${i}`)
		}
		const registros = (limitador as unknown as { registros: Map<string, number[]> }).registros
		assert.ok(registros.size <= 510, `quedaron ${registros.size} remitentes en memoria`)
	})

	test("el limitador corta a una misma persona que escribe 1 000 comandos seguidos", () => {
		let ahora = 0
		const limitador = new LimitadorFrecuencia(5, 60_000, () => ahora)
		let permitidos = 0
		for (let i = 0; i < 1_000; i++) {
			ahora += 10
			if (limitador.permitir("insistente")) permitidos++
		}
		assert.equal(permitidos, 5)
	})
})
