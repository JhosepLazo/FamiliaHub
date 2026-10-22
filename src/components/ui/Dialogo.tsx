import { AlertTriangle, HelpCircle } from 'lucide-react'
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type FormEvent, type ReactNode } from 'react'
import { createPortal } from 'react-dom'

type Opciones = {
	titulo: string
	mensaje?: string
	accion?: string
	// Acciones que anulan o quitan algo: el botón se ve en rojo.
	peligro?: boolean
	// Solo informa: sin botón "Volver".
	informativo?: boolean
}

type OpcionesTexto = Opciones & { etiqueta: string; placeholder?: string }

type Peticion =
	| (Opciones & { tipo: 'confirmar'; resolver: (valor: boolean) => void })
	| (OpcionesTexto & { tipo: 'texto'; resolver: (valor: string | null) => void })

type DialogoContextValue = {
	confirmar: (opciones: Opciones) => Promise<boolean>
	pedirTexto: (opciones: OpcionesTexto) => Promise<string | null>
}

const DialogoContext = createContext<DialogoContextValue | null>(null)

// Cuadros de confirmación con el diseño de FamiliaHub, en lugar de las ventanas grises del navegador
// (window.confirm / window.prompt), que en el celular se ven fuera de lugar.
export function DialogoProvider({ children }: { children: ReactNode }) {
	const [peticion, setPeticion] = useState<Peticion | null>(null)

	const confirmar = useCallback((opciones: Opciones) => new Promise<boolean>((resolver) => {
		setPeticion({ ...opciones, tipo: 'confirmar', resolver })
	}), [])

	const pedirTexto = useCallback((opciones: OpcionesTexto) => new Promise<string | null>((resolver) => {
		setPeticion({ ...opciones, tipo: 'texto', resolver })
	}), [])

	const value = useMemo(() => ({ confirmar, pedirTexto }), [confirmar, pedirTexto])

	return (
		<DialogoContext.Provider value={value}>
			{children}
			{peticion && <Ventana peticion={peticion} cerrar={() => setPeticion(null)} />}
		</DialogoContext.Provider>
	)
}

function Ventana({ peticion, cerrar }: { peticion: Peticion; cerrar: () => void }) {
	const [texto, setTexto] = useState('')
	const campo = useRef<HTMLTextAreaElement>(null)
	const boton = useRef<HTMLButtonElement>(null)

	const cancelar = useCallback(() => {
		if (peticion.tipo === 'confirmar') peticion.resolver(false)
		else peticion.resolver(null)
		cerrar()
	}, [peticion, cerrar])

	useEffect(() => {
		;(peticion.tipo === 'texto' ? campo.current : boton.current)?.focus()
		const alTeclear = (evento: KeyboardEvent) => { if (evento.key === 'Escape') cancelar() }
		window.addEventListener('keydown', alTeclear)
		return () => window.removeEventListener('keydown', alTeclear)
	}, [peticion, cancelar])

	const aceptar = (evento: FormEvent) => {
		evento.preventDefault()
		if (peticion.tipo === 'confirmar') {
			peticion.resolver(true)
		} else {
			if (!texto.trim()) return
			peticion.resolver(texto.trim())
		}
		cerrar()
	}

	return createPortal(
		<div className="fixed inset-0 z-[60] flex items-end justify-center bg-slate-950/50 p-3 backdrop-blur-sm sm:items-center" onMouseDown={(evento) => { if (evento.target === evento.currentTarget) cancelar() }}>
			<form role="dialog" aria-modal="true" aria-labelledby="dialogo-titulo" onSubmit={aceptar} className="fh-entrada w-full max-w-md rounded-3xl bg-white p-6 shadow-[0_30px_60px_-20px_rgb(7_11_20/0.6)]">
				<div className="flex items-start gap-4">
					<div className={`grid size-11 shrink-0 place-items-center rounded-2xl ${peticion.peligro ? 'bg-rose-50 text-rose-600' : 'bg-cyan-50 text-cyan-700'}`}>
						{peticion.peligro ? <AlertTriangle size={20} /> : <HelpCircle size={20} />}
					</div>
					<div className="min-w-0">
						<h2 id="dialogo-titulo" className="text-lg font-semibold text-slate-900">{peticion.titulo}</h2>
						{peticion.mensaje && <p className="mt-1.5 text-sm leading-6 text-slate-500">{peticion.mensaje}</p>}
					</div>
				</div>

				{peticion.tipo === 'texto' && (
					<label className="mt-5 block">
						<span className="fh-label">{peticion.etiqueta}</span>
						<textarea ref={campo} rows={3} maxLength={300} required value={texto} onChange={(evento) => setTexto(evento.target.value)} placeholder={peticion.placeholder} className="fh-input h-auto resize-none py-3" />
					</label>
				)}

				<div className="mt-6 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
					{!peticion.informativo && <button type="button" onClick={cancelar} className="fh-button-secondary">Volver</button>}
					<button ref={boton} type="submit" disabled={peticion.tipo === 'texto' && !texto.trim()} className={peticion.peligro ? 'inline-flex h-10 items-center justify-center rounded-xl bg-rose-600 px-4 text-sm font-semibold text-white transition hover:bg-rose-700 focus-visible:ring-4 focus-visible:ring-rose-100 active:scale-[0.98] disabled:opacity-50' : 'fh-button-primary'}>
						{peticion.accion ?? 'Confirmar'}
					</button>
				</div>
			</form>
		</div>,
		document.body,
	)
}

export function useDialogo() {
	const context = useContext(DialogoContext)
	if (!context) throw new Error('useDialogo debe usarse dentro de DialogoProvider.')
	return context
}
