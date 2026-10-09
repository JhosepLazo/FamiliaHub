import { CheckCircle2, Copy, MessageCircle, Unlink } from 'lucide-react'
import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import type { Database, Enums } from '../../types/database'
import { useFamilia } from '../familia/FamiliaContext'

type Tipo = Enums<'tipo_vinculo_whatsapp'>
type Estado = Database['public']['Functions']['estado_whatsapp']['Returns'][number]
type CodigoActivo = { codigo: string; expira_at: string; vinculoPrevio: string | null }

const textos: Record<Tipo, { titulo: string; descripcion: string; boton: string; comando: string; pasos: string[] }> = {
	GRUPO: {
		titulo: 'Grupo de WhatsApp',
		descripcion: 'El asistente avisa en el grupo familiar cuando un recibo está por vencer o venció, y responde /deuda, /vence y /resumen.',
		boton: 'Vincular grupo',
		comando: '/vincular-grupo',
		pasos: ['Agrega el número del bot de FamiliaHub al grupo familiar.', 'Escribe en el grupo este mensaje:'],
	},
	INTEGRANTE: {
		titulo: 'Tu WhatsApp',
		descripcion: 'Vincula tu WhatsApp para que el asistente te reconozca en el grupo familiar y responda /deuda con tus cuotas.',
		boton: 'Vincular mi WhatsApp',
		comando: '/vincular',
		pasos: ['Escribe en el grupo familiar donde está el bot este mensaje:'],
	},
}

export default function WhatsappVinculo({ tipo }: { tipo: Tipo }) {
	const { familia } = useFamilia()
	const [estado, setEstado] = useState<Estado | null>(null)
	const [codigo, setCodigo] = useState<CodigoActivo | null>(null)
	const [restante, setRestante] = useState(0)
	const [loading, setLoading] = useState(false)
	const [message, setMessage] = useState<string | null>(null)
	const texto = textos[tipo]

	const load = useCallback(async () => {
		if (!familia) return
		const { data } = await supabase.rpc('estado_whatsapp', { p_familia_id: familia.id })
		setEstado(data?.[0] ?? null)
	}, [familia])

	useEffect(() => { void load() }, [load])

	const vinculado = Boolean(tipo === 'GRUPO' ? estado?.grupo_vinculado : estado?.integrante_vinculado)
	const vinculadoAt = (tipo === 'GRUPO' ? estado?.grupo_vinculado_at : estado?.integrante_vinculado_at) ?? null

	// Mientras el código está vigente: cuenta regresiva y detección automática del vínculo.
	useEffect(() => {
		if (!codigo) return
		const tick = () => {
			const seconds = Math.max(0, Math.round((new Date(codigo.expira_at).getTime() - Date.now()) / 1000))
			setRestante(seconds)
			if (seconds === 0) {
				setCodigo(null)
				setMessage('El código venció. Genera uno nuevo cuando estés listo.')
			}
		}
		tick()
		const timer = setInterval(tick, 1000)
		const poll = setInterval(() => void load(), 5000)
		return () => {
			clearInterval(timer)
			clearInterval(poll)
		}
	}, [codigo, load])

	useEffect(() => {
		if (codigo && vinculadoAt && vinculadoAt !== codigo.vinculoPrevio) {
			setCodigo(null)
			setMessage(tipo === 'GRUPO' ? 'Listo. El grupo quedó vinculado.' : 'Listo. Tu WhatsApp quedó vinculado.')
		}
	}, [codigo, vinculadoAt, tipo])

	const generar = async () => {
		if (!familia) return
		setLoading(true)
		setMessage(null)
		const { data, error } = await supabase.rpc('generar_codigo_whatsapp', { p_familia_id: familia.id, p_tipo: tipo })
		const nuevo = data?.[0]
		if (error || !nuevo) setMessage(error?.message ?? 'No pudimos generar el código.')
		else setCodigo({ ...nuevo, vinculoPrevio: vinculadoAt })
		setLoading(false)
	}

	const copiar = async () => {
		if (!codigo) return
		await navigator.clipboard.writeText(`${texto.comando} ${codigo.codigo}`)
		setMessage('Mensaje copiado. Pégalo en el grupo de WhatsApp.')
	}

	const desvincular = async () => {
		if (!familia) return
		const pregunta = tipo === 'GRUPO'
			? '¿Desvincular el grupo? El asistente dejará de enviar avisos y responder consultas.'
			: '¿Desvincular tu WhatsApp? El asistente dejará de reconocerte en el grupo.'
		if (!window.confirm(pregunta)) return
		const { error } = await supabase.rpc('desvincular_whatsapp', { p_familia_id: familia.id, p_tipo: tipo })
		setMessage(error ? error.message : tipo === 'GRUPO' ? 'Grupo desvinculado.' : 'Tu WhatsApp fue desvinculado.')
		await load()
	}

	return (
		<section className="mt-6 rounded-3xl border border-slate-200 bg-white p-6 sm:p-8">
			<div className="flex items-start justify-between gap-4">
				<div className="flex items-start gap-3">
					<div className="grid size-10 shrink-0 place-items-center rounded-2xl bg-emerald-50 text-[#0f766e]"><MessageCircle size={20} /></div>
					<div>
						<h2 className="font-semibold">{texto.titulo}</h2>
						<p className="mt-1 text-xs leading-5 text-slate-400">{texto.descripcion}</p>
					</div>
				</div>
				<span className={`shrink-0 rounded-full px-2.5 py-1 text-[10px] font-semibold ${vinculado ? 'bg-emerald-50 text-emerald-700' : 'bg-slate-100 text-slate-500'}`}>{vinculado ? 'Vinculado' : 'Sin vincular'}</span>
			</div>

			{vinculado && vinculadoAt && !codigo && (
				<p className="mt-4 flex items-center gap-1.5 text-xs text-slate-500">
					<CheckCircle2 size={14} className="text-emerald-600" />
					Vinculado el {fechaHora(vinculadoAt)}
					{tipo === 'GRUPO' && estado && ` · ${estado.integrantes_vinculados} de ${estado.integrantes_activos} integrantes con WhatsApp vinculado`}
				</p>
			)}

			{codigo ? (
				<div className="mt-5 rounded-2xl border border-dashed border-emerald-200 bg-emerald-50/60 p-4">
					<ol className="space-y-1 text-xs leading-5 text-slate-600">
						{texto.pasos.map((paso, index) => <li key={paso}>{index + 1}. {paso}</li>)}
					</ol>
					<div className="mt-3 flex flex-wrap items-center gap-3">
						<code className="rounded-xl bg-white px-4 py-2 font-mono text-base font-semibold tracking-wider text-[#0f766e] sm:text-lg">{texto.comando} {codigo.codigo}</code>
						<button type="button" onClick={() => void copiar()} className="fh-button-secondary flex items-center gap-2"><Copy size={15} />Copiar</button>
					</div>
					<p className="mt-3 text-xs text-slate-400">El código vence en {minutos(restante)} y solo sirve una vez. Esta pantalla se actualizará sola al vincularse.</p>
				</div>
			) : (
				<div className="mt-5 flex flex-wrap gap-3">
					<button type="button" onClick={() => void generar()} className="fh-button-primary" disabled={loading || !familia}>{loading ? 'Generando...' : vinculado ? 'Volver a vincular' : texto.boton}</button>
					{vinculado && <button type="button" onClick={() => void desvincular()} className="fh-button-secondary flex items-center gap-2"><Unlink size={15} />Desvincular</button>}
				</div>
			)}

			{message && <p className="fh-alert mt-4">{message}</p>}
		</section>
	)
}

function minutos(seconds: number) {
	return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`
}

function fechaHora(value: string) {
	return new Intl.DateTimeFormat('es-PE', {
		day: '2-digit',
		month: 'short',
		hour: '2-digit',
		minute: '2-digit',
		timeZone: 'America/Lima',
	}).format(new Date(value))
}
