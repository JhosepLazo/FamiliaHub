import { CheckCircle2, Copy, MessageCircle, Unlink } from 'lucide-react'
import { useEffect, useState } from 'react'
import { codigoVigente, fechaHora, useConsultaPeriodica, useCuentaRegresiva, useWhatsApp } from './useWhatsApp'

export function CodigoWhatsApp({ codigo, expiraAt, comando, onVencido }: { codigo: string; expiraAt: string; comando: string; onVencido: () => void }) {
	const segundos = useCuentaRegresiva(expiraAt)
	const [copiado, setCopiado] = useState(false)
	const instruccion = `${comando} ${codigo}`

	useEffect(() => {
		if (segundos === 0) onVencido()
	}, [segundos, onVencido])

	const copiar = async () => {
		try {
			await navigator.clipboard.writeText(instruccion)
			setCopiado(true)
			window.setTimeout(() => setCopiado(false), 2000)
		} catch {
			setCopiado(false)
		}
	}

	const minutos = Math.floor(segundos / 60)
	const resto = String(segundos % 60).padStart(2, '0')

	return (
		<div className="mt-5 rounded-2xl bg-slate-50 p-4">
			<p className="text-xs font-medium text-slate-500">Escribe esto en el grupo familiar de WhatsApp:</p>
			<p className="mt-2 break-all font-mono text-2xl font-semibold tracking-wider text-slate-800">{instruccion}</p>
			<div className="mt-4 flex flex-wrap items-center gap-3">
				<button type="button" className="fh-button-secondary flex items-center gap-2" onClick={() => void copiar()}><Copy size={15} />{copiado ? 'Copiado' : 'Copiar'}</button>
				<p className="text-xs text-slate-400">{segundos > 0 ? `Vence en ${minutos}:${resto}` : 'El código venció. Genera uno nuevo.'}</p>
			</div>
		</div>
	)
}

export default function WhatsAppPerfilSection() {
	const { estado, loading, error, recargar, generarCodigo, desvincular } = useWhatsApp()
	const [trabajando, setTrabajando] = useState(false)
	const [message, setMessage] = useState<string | null>(null)
	const vigente = codigoVigente(estado?.yo)
	const [esperandoVinculo, setEsperandoVinculo] = useState(false)

	useConsultaPeriodica(vigente && !estado?.yo.vinculado, recargar)

	useEffect(() => {
		if (esperandoVinculo && estado?.yo.vinculado) {
			setEsperandoVinculo(false)
			setMessage('Tu WhatsApp quedó vinculado.')
		}
	}, [esperandoVinculo, estado?.yo.vinculado])

	const vincular = async () => {
		setTrabajando(true)
		setMessage(null)
		try {
			await generarCodigo('INTEGRANTE')
			setEsperandoVinculo(true)
		} catch (fallo) {
			setMessage(fallo instanceof Error ? fallo.message : 'No pudimos generar el código.')
		}
		setTrabajando(false)
	}

	const quitarVinculo = async () => {
		if (!window.confirm('¿Desvincular tu WhatsApp? Dejarás de recibir menciones y no podrás consultar tu deuda desde el grupo.')) return
		setTrabajando(true)
		setMessage(null)
		try {
			await desvincular('INTEGRANTE')
			setMessage('Tu WhatsApp ya no está vinculado.')
		} catch (fallo) {
			setMessage(fallo instanceof Error ? fallo.message : 'No pudimos desvincular tu WhatsApp.')
		}
		setTrabajando(false)
	}

	return (
		<section className="mt-6 rounded-3xl border border-slate-200 bg-white p-6 sm:p-8">
			<div className="flex items-center gap-3">
				<div className="grid size-10 place-items-center rounded-xl bg-emerald-50 text-[#0f766e]"><MessageCircle size={19} /></div>
				<div><h2 className="font-semibold">WhatsApp</h2><p className="text-xs leading-5 text-slate-400">Vincula tu WhatsApp para consultar tu deuda con /deuda y recibir menciones en el grupo familiar.</p></div>
			</div>

			{loading ? (
				<div className="mt-5 h-20 animate-pulse rounded-2xl bg-slate-50" />
			) : estado && (
				<>
					{!estado.grupo.vinculado && <p className="fh-alert mt-5">Tu familia aún no vinculó el grupo de WhatsApp.</p>}

					{estado.yo.vinculado ? (
						<div className="mt-5 flex flex-col gap-3 rounded-2xl bg-emerald-50 p-4 sm:flex-row sm:items-center sm:justify-between">
							<div className="flex gap-3 text-emerald-800">
								<CheckCircle2 size={20} className="shrink-0" />
								<div><p className="text-sm font-semibold">WhatsApp vinculado</p><p className="mt-1 text-xs text-emerald-700/70">Desde {fechaHora(estado.yo.vinculadoAt)}</p></div>
							</div>
							<button type="button" disabled={trabajando} onClick={() => void quitarVinculo()} className="fh-button-secondary flex items-center gap-2"><Unlink size={15} />Desvincular</button>
						</div>
					) : vigente && estado.yo.codigo && estado.yo.codigoExpiraAt ? (
						<CodigoWhatsApp codigo={estado.yo.codigo} expiraAt={estado.yo.codigoExpiraAt} comando="/vincular" onVencido={recargar} />
					) : (
						<button type="button" disabled={trabajando} onClick={() => void vincular()} className="fh-button-primary mt-5">{trabajando ? 'Generando...' : 'Vincular mi WhatsApp'}</button>
					)}
				</>
			)}

			{(message || error) && <p className="fh-alert mt-4">{message ?? error}</p>}
		</section>
	)
}
