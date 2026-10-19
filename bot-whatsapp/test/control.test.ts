import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
	LIMITE_COMANDOS,
	LIMITE_LENGUAJE_NATURAL_GRUPO,
	LIMITE_LENGUAJE_NATURAL_REMITENTE,
	LIMITE_NO_VINCULADO,
	RECONEXION_INICIAL_MS,
	RECONEXION_MAX_MS,
} from "../src/config.ts"
import { aleatorioEntre, Deduplicador, EsperaExponencial, LimitadorFrecuencia } from "../src/control.ts"

function relojFalso(inicio = 1_000_000) {
	let ahora = inicio
	return {
		reloj: () => ahora,
		avanzar: (ms: number) => {
			ahora += ms
		},
	}
}

describe("Deduplicador", () => {
	it("ignora IDs repetidos", () => {
		const dedupe = new Deduplicador(10)
		assert.equal(dedupe.visto("a"), false)
		assert.equal(dedupe.visto("a"), true)
		assert.equal(dedupe.visto("b"), false)
	})

	it("respeta el límite y olvida los más antiguos", () => {
		const dedupe = new Deduplicador(3)
		for (const id of ["a", "b", "c", "d"]) dedupe.visto(id)

		assert.equal(dedupe.tamano, 3)
		assert.equal(dedupe.visto("d"), true)
		assert.equal(dedupe.visto("a"), false)
	})
})

describe("LimitadorFrecuencia", () => {
	it("permite 5 comandos por minuto por remitente", () => {
		const { reloj, avanzar } = relojFalso()
		const limite = new LimitadorFrecuencia(LIMITE_COMANDOS.maximo, LIMITE_COMANDOS.ventanaMs, reloj)

		for (let i = 0; i < 5; i++) assert.equal(limite.permitir("liliana"), true)
		assert.equal(limite.permitir("liliana"), false)
		assert.equal(limite.permitir("jhosep"), true)

		avanzar(60_001)
		assert.equal(limite.permitir("liliana"), true)
	})

	it("usa una ventana deslizante", () => {
		const { reloj, avanzar } = relojFalso()
		const limite = new LimitadorFrecuencia(2, 1_000, reloj)

		assert.equal(limite.permitir("x"), true)
		avanzar(600)
		assert.equal(limite.permitir("x"), true)
		avanzar(500)
		assert.equal(limite.permitir("x"), true)
		assert.equal(limite.permitir("x"), false)
	})

	it("responde una sola vez por hora a un grupo no vinculado", () => {
		const { reloj, avanzar } = relojFalso()
		const limite = new LimitadorFrecuencia(LIMITE_NO_VINCULADO.maximo, LIMITE_NO_VINCULADO.ventanaMs, reloj)

		assert.equal(limite.permitir("grupo@g.us"), true)
		avanzar(59 * 60_000)
		assert.equal(limite.permitir("grupo@g.us"), false)
		avanzar(60_001)
		assert.equal(limite.permitir("grupo@g.us"), true)
	})

	it("limita el lenguaje natural por remitente y por grupo", () => {
		const { reloj } = relojFalso()
		const remitente = new LimitadorFrecuencia(LIMITE_LENGUAJE_NATURAL_REMITENTE.maximo, LIMITE_LENGUAJE_NATURAL_REMITENTE.ventanaMs, reloj)
		const grupo = new LimitadorFrecuencia(LIMITE_LENGUAJE_NATURAL_GRUPO.maximo, LIMITE_LENGUAJE_NATURAL_GRUPO.ventanaMs, reloj)

		for (let i = 0; i < 3; i++) assert.equal(remitente.permitir("ana"), true)
		assert.equal(remitente.permitir("ana"), false)

		for (let i = 0; i < 20; i++) assert.equal(grupo.permitir("g"), true)
		assert.equal(grupo.permitir("g"), false)
	})
})

describe("EsperaExponencial", () => {
	it("duplica la espera hasta el máximo y se reinicia al conectar", () => {
		const espera = new EsperaExponencial(RECONEXION_INICIAL_MS, RECONEXION_MAX_MS)
		const valores = Array.from({ length: 7 }, () => espera.siguiente())

		assert.deepEqual(valores, [3_000, 6_000, 12_000, 24_000, 48_000, 60_000, 60_000])

		espera.reiniciar()
		assert.equal(espera.siguiente(), 3_000)
	})
})

describe("aleatorioEntre", () => {
	it("se mantiene dentro del rango del indicador escribiendo", () => {
		assert.equal(aleatorioEntre(1_000, 2_500, () => 0), 1_000)
		assert.equal(aleatorioEntre(1_000, 2_500, () => 0.999999), 2_500)
		for (let i = 0; i < 100; i++) {
			const valor = aleatorioEntre(1_000, 2_500)
			assert.ok(valor >= 1_000 && valor <= 2_500)
		}
	})
})
