import type { RealtimeChannel } from '@supabase/supabase-js'
import { useEffect, useRef } from 'react'
import { supabase } from './supabase'

// Cambios en vivo: cuando cambia un recibo, una cuota o un pago de la familia (o se vuelve a la pestaña),
// las páginas abiertas recargan sus datos sin mostrar la pantalla de carga. Supabase Realtime respeta las
// políticas RLS, así que cada persona solo recibe avisos de lo que ya puede ver.

const TABLAS = ['recibos', 'cuotas', 'pagos_familiares'] as const
const ESPERA_MS = 600
const MINIMO_ENTRE_VISITAS_MS = 15_000

const oyentes = new Set<() => void>()
let canal: RealtimeChannel | null = null
let familiaConectada: string | null = null
let temporizador: ReturnType<typeof setTimeout> | undefined
let ultimaVisita = 0

// Un pago toca varias filas a la vez (pago, cuotas, recibo): se agrupan en una sola recarga.
function avisar() {
	clearTimeout(temporizador)
	temporizador = setTimeout(() => oyentes.forEach((oyente) => oyente()), ESPERA_MS)
}

function alVolver() {
	if (document.visibilityState !== 'visible' || Date.now() - ultimaVisita < MINIMO_ENTRE_VISITAS_MS) return
	ultimaVisita = Date.now()
	avisar()
}

if (typeof window !== 'undefined') {
	document.addEventListener('visibilitychange', alVolver)
	window.addEventListener('online', avisar)
}

// La llama FamiliaProvider cuando se conoce (o cambia) la familia de quien entró.
export function conectarEnVivo(familiaId: string | null) {
	if (familiaId === familiaConectada) return
	if (canal) void supabase.removeChannel(canal)
	canal = null
	familiaConectada = familiaId
	if (!familiaId) return

	let nuevo = supabase.channel(`familia-${familiaId}`)
	for (const tabla of TABLAS) {
		nuevo = nuevo.on('postgres_changes', { event: '*', schema: 'public', table: tabla, filter: `familia_id=eq.${familiaId}` }, avisar)
	}
	canal = nuevo.subscribe()
}

// Llama a `recargar` cada vez que llega un cambio. Debe recargar en silencio (sin esqueleto de carga).
export function useEnVivo(recargar: () => void) {
	const actual = useRef(recargar)
	useEffect(() => { actual.current = recargar })

	useEffect(() => {
		const oyente = () => actual.current()
		oyentes.add(oyente)
		return () => { oyentes.delete(oyente) }
	}, [])
}
