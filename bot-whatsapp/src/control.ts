type Reloj = () => number

export class Deduplicador {
	private maximo: number
	private ids = new Set<string>()

	constructor(maximo: number) {
		this.maximo = maximo
	}

	// Devuelve true si el ID ya se había visto; si no, lo registra.
	visto(id: string) {
		if (this.ids.has(id)) return true

		this.ids.add(id)
		if (this.ids.size > this.maximo) {
			const masAntiguo = this.ids.values().next().value
			if (masAntiguo !== undefined) this.ids.delete(masAntiguo)
		}

		return false
	}

	get tamano() {
		return this.ids.size
	}
}

export class LimitadorFrecuencia {
	private maximo: number
	private ventanaMs: number
	private reloj: Reloj
	private registros = new Map<string, number[]>()

	constructor(maximo: number, ventanaMs: number, reloj: Reloj = Date.now) {
		this.maximo = maximo
		this.ventanaMs = ventanaMs
		this.reloj = reloj
	}

	// Ventana deslizante: permite como máximo `maximo` eventos por clave dentro de `ventanaMs`.
	permitir(clave: string) {
		const ahora = this.reloj()
		const desde = ahora - this.ventanaMs
		const recientes = (this.registros.get(clave) ?? []).filter((momento) => momento > desde)

		if (recientes.length >= this.maximo) {
			this.registros.set(clave, recientes)
			return false
		}

		recientes.push(ahora)
		this.registros.set(clave, recientes)
		this.limpiar(desde)
		return true
	}

	private limpiar(desde: number) {
		if (this.registros.size <= 500) return

		for (const [clave, momentos] of this.registros) {
			if (!momentos.some((momento) => momento > desde)) this.registros.delete(clave)
		}
	}
}

export class EsperaExponencial {
	private inicialMs: number
	private maximoMs: number
	private actualMs: number

	constructor(inicialMs: number, maximoMs: number) {
		this.inicialMs = inicialMs
		this.maximoMs = maximoMs
		this.actualMs = inicialMs
	}

	// Devuelve la espera para el intento actual y duplica la siguiente, sin superar el máximo.
	siguiente() {
		const espera = this.actualMs
		this.actualMs = Math.min(this.actualMs * 2, this.maximoMs)
		return espera
	}

	reiniciar() {
		this.actualMs = this.inicialMs
	}
}

export function esperar(ms: number) {
	return new Promise<void>((resolve) => setTimeout(resolve, ms))
}

export function aleatorioEntre(minimo: number, maximo: number, azar: () => number = Math.random) {
	return Math.round(minimo + (maximo - minimo) * azar())
}
