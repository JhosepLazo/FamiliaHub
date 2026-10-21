import { CheckCircle2, MessageCircle, Unlink, Users } from 'lucide-react'
import { FormEvent, useEffect, useRef, useState, type ReactNode } from 'react'
import { CodigoWhatsApp } from './WhatsAppPerfilSection'
import {
	CONFIGURACION_POR_DEFECTO,
	DIAS_SEMANA,
	codigoVigente,
	estadoBot,
	fechaHora,
	useConsultaPeriodica,
	useWhatsApp,
	validarConfiguracion,
	type ConfiguracionWhatsApp,
} from './useWhatsApp'

type ClaveBooleana = {
	[K in keyof ConfiguracionWhatsApp]: ConfiguracionWhatsApp[K] extends boolean ? K : never
}[keyof ConfiguracionWhatsApp]

const DIAS_PREVIOS = Array.from({ length: 15 }, (_, indice) => indice + 1)

export default function WhatsAppFamiliaSection() {
	const { estado, loading, error, recargar, generarCodigo, desvincular, guardarConfiguracion } = useWhatsApp()
	const [formulario, setFormulario] = useState<ConfiguracionWhatsApp>(CONFIGURACION_POR_DEFECTO)
	const [trabajando, setTrabajando] = useState(false)
	const [guardando, setGuardando] = useState(false)
	const [message, setMessage] = useState<string | null>(null)
	const [esperandoGrupo, setEsperandoGrupo] = useState(false)
	const [ahora, setAhora] = useState(() => Date.now())
	const inicializado = useRef(false)

	const vigente = codigoVigente(estado?.grupo)
	const bot = estadoBot(estado?.bot.ultimoHeartbeatAt ?? null, ahora)

	useConsultaPeriodica(vigente && !estado?.grupo.vinculado, recargar)

	useEffect(() => {
		const intervalo = window.setInterval(() => setAhora(Date.now()), 60_000)
		return () => window.clearInterval(intervalo)
	}, [])

	// Se carga una sola vez: las consultas periódicas no deben borrar cambios sin guardar.
	useEffect(() => {
		if (estado?.configuracion && !inicializado.current) {
			inicializado.current = true
			setFormulario(estado.configuracion)
		}
	}, [estado?.configuracion])

	useEffect(() => {
		if (esperandoGrupo && estado?.grupo.vinculado) {
			setEsperandoGrupo(false)
			setMessage('Grupo vinculado.')
		}
	}, [esperandoGrupo, estado?.grupo.vinculado])

	const actualizar = <K extends keyof ConfiguracionWhatsApp>(clave: K, valor: ConfiguracionWhatsApp[K]) => {
		setFormulario((actual) => ({ ...actual, [clave]: valor }))
	}

	const alternarDia = (dia: number) => {
		setFormulario((actual) => {
			const dias = actual.diasAvisoPrevio.includes(dia)
				? actual.diasAvisoPrevio.filter((valor) => valor !== dia)
				: [...actual.diasAvisoPrevio, dia]
			return { ...actual, diasAvisoPrevio: dias.sort((a, b) => b - a) }
		})
	}

	const vincularGrupo = async () => {
		setTrabajando(true)
		setMessage(null)
		try {
			await generarCodigo('GRUPO')
			setEsperandoGrupo(true)
		} catch (fallo) {
			setMessage(fallo instanceof Error ? fallo.message : 'No pudimos generar el código.')
		}
		setTrabajando(false)
	}

	const desvincularGrupo = async () => {
		if (!window.confirm('¿Desvincular el grupo de WhatsApp? El bot dejará de enviar avisos y responder en ese grupo. Los integrantes conservan su vínculo.')) return
		setTrabajando(true)
		setMessage(null)
		try {
			await desvincular('GRUPO')
			setMessage('El grupo quedó desvinculado.')
		} catch (fallo) {
			setMessage(fallo instanceof Error ? fallo.message : 'No pudimos desvincular el grupo.')
		}
		setTrabajando(false)
	}

	const guardar = async (event: FormEvent) => {
		event.preventDefault()
		const invalido = validarConfiguracion(formulario)
		if (invalido) {
			setMessage(invalido)
			return
		}

		setGuardando(true)
		setMessage(null)
		try {
			const { lenguajeNatural: _lenguajeNatural, ...cambios } = formulario
			await guardarConfiguracion(cambios)
			setMessage('Configuración de avisos guardada.')
		} catch (fallo) {
			setMessage(fallo instanceof Error ? fallo.message : 'No pudimos guardar la configuración.')
		}
		setGuardando(false)
	}

	const alternarLenguajeNatural = async () => {
		const valor = !formulario.lenguajeNatural
		setTrabajando(true)
		setMessage(null)
		try {
			await guardarConfiguracion({ lenguajeNatural: valor })
			actualizar('lenguajeNatural', valor)
			setMessage(valor ? 'Preguntas en lenguaje natural activadas.' : 'Preguntas en lenguaje natural desactivadas.')
		} catch (fallo) {
			setMessage(fallo instanceof Error ? fallo.message : 'No pudimos cambiar esta opción.')
		}
		setTrabajando(false)
	}

	const casilla = (clave: ClaveBooleana, etiqueta: string, ayuda?: string) => (
		<label key={clave} className="flex cursor-pointer items-start gap-3 rounded-xl px-1 py-2">
			<input type="checkbox" className="mt-0.5 size-4 accent-brand" checked={formulario[clave]} onChange={(e) => actualizar(clave, e.target.checked)} />
			<span><span className="block text-sm font-medium text-slate-700">{etiqueta}</span>{ayuda && <span className="mt-0.5 block text-xs text-slate-400">{ayuda}</span>}</span>
		</label>
	)

	return (
		<section className="mt-6 rounded-3xl border border-slate-200 bg-white p-6">
			<div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
				<div className="flex items-center gap-3">
					<div className="grid size-10 place-items-center rounded-xl bg-emerald-50 text-brand"><MessageCircle size={19} /></div>
					<div><h2 className="font-semibold">Asistente de WhatsApp</h2><p className="text-xs leading-5 text-slate-400">Avisa en el grupo familiar y responde consultas. Pagar, validar y editar se sigue haciendo aquí.</p></div>
				</div>
				{estado && <span className={`self-start rounded-full px-3 py-1.5 text-xs font-semibold ${bot.activo ? 'bg-emerald-50 text-emerald-700' : 'bg-amber-50 text-amber-700'}`}>Bot: {bot.texto}</span>}
			</div>

			{loading ? (
				<div className="mt-6 h-40 animate-pulse rounded-2xl bg-slate-50" />
			) : estado && (
				<>
					<div className="mt-6 grid gap-6 lg:grid-cols-2">
						<div className="rounded-2xl border border-slate-100 p-5">
							<h3 className="text-sm font-semibold">Grupo familiar</h3>
							{estado.grupo.vinculado ? (
								<div className="mt-4 flex flex-col gap-3">
									<div className="flex gap-3 rounded-2xl bg-emerald-50 p-4 text-emerald-800">
										<CheckCircle2 size={20} className="shrink-0" />
										<div><p className="text-sm font-semibold">Grupo vinculado</p><p className="mt-1 text-xs text-emerald-700/70">Desde {fechaHora(estado.grupo.vinculadoAt)}</p></div>
									</div>
									<button type="button" disabled={trabajando} onClick={() => void desvincularGrupo()} className="fh-button-secondary flex items-center gap-2 self-start"><Unlink size={15} />Desvincular grupo</button>
								</div>
							) : (
								<>
									<p className="mt-2 text-xs leading-5 text-slate-400">Primero agrega el número del bot al grupo familiar.</p>
									{vigente && estado.grupo.codigo && estado.grupo.codigoExpiraAt ? (
										<CodigoWhatsApp codigo={estado.grupo.codigo} expiraAt={estado.grupo.codigoExpiraAt} comando="/vincular-grupo" onVencido={recargar} />
									) : (
										<button type="button" disabled={trabajando} onClick={() => void vincularGrupo()} className="fh-button-primary mt-4">{trabajando ? 'Generando...' : 'Vincular grupo'}</button>
									)}
								</>
							)}
						</div>

						<div className="rounded-2xl border border-slate-100 p-5">
							<div className="flex items-center gap-2"><Users size={16} className="text-slate-400" /><h3 className="text-sm font-semibold">Integrantes</h3></div>
							<div className="mt-4 space-y-2">
								{estado.integrantes.map((integrante) => (
									<div key={integrante.miembroId} className="flex items-center justify-between gap-3 rounded-xl bg-slate-50 px-4 py-3">
										<div className="min-w-0"><p className="truncate text-sm font-medium text-slate-700">{integrante.nombre}</p><p className="text-[11px] text-slate-400">{integrante.rol === 'ADMINISTRADOR' ? 'Administrador' : 'Integrante'}</p></div>
										<span className={`shrink-0 rounded-full px-2.5 py-1 text-[10px] font-semibold ${integrante.vinculado ? 'bg-emerald-50 text-emerald-700' : 'bg-slate-100 text-slate-500'}`}>{integrante.vinculado ? 'Vinculado' : 'Sin vincular'}</span>
									</div>
								))}
							</div>
							<p className="mt-3 text-xs leading-5 text-slate-400">Cada integrante se vincula desde Perfil &gt; WhatsApp.</p>
						</div>
					</div>

					<form className="mt-6" onSubmit={guardar}>
						<div className="flex flex-col gap-3 rounded-2xl bg-slate-50 p-4 sm:flex-row sm:items-center sm:justify-between">
							{casilla('avisosActivos', 'Avisos automáticos activos', 'Si los pausas, el bot sigue respondiendo comandos.')}
							<div className="grid grid-cols-2 gap-3 sm:w-72">
								<label><span className="fh-label">Desde</span><input type="time" className="fh-input" value={formulario.horaInicioEnvio} onChange={(e) => actualizar('horaInicioEnvio', e.target.value)} required /></label>
								<label><span className="fh-label">Hasta</span><input type="time" className="fh-input" value={formulario.horaFinEnvio} onChange={(e) => actualizar('horaFinEnvio', e.target.value)} required /></label>
							</div>
						</div>

						<div className="mt-5 grid gap-5 lg:grid-cols-2">
							<Grupo titulo="Recordatorios">
								<p className="fh-label">Días antes de la fecha para aportar (máximo 5)</p>
								<div className="flex flex-wrap gap-1.5">
									{DIAS_PREVIOS.map((dia) => {
										const activo = formulario.diasAvisoPrevio.includes(dia)
										const bloqueado = !activo && formulario.diasAvisoPrevio.length >= 5
										return <button key={dia} type="button" disabled={bloqueado} onClick={() => alternarDia(dia)} className={`size-9 rounded-xl text-xs font-semibold transition disabled:opacity-40 ${activo ? 'bg-brand text-white' : 'bg-slate-50 text-slate-500'}`}>{dia}</button>
									})}
								</div>
								{casilla('avisarVenceHoy', 'Avisar el día límite')}
								<label className="block"><span className="fh-label">Recordar vencidos cada (días, 0 = solo una vez)</span><input type="number" min={0} max={15} step={1} className="fh-input" value={formulario.frecuenciaVencidosDias} onChange={(e) => actualizar('frecuenciaVencidosDias', Number(e.target.value))} required /></label>
								{casilla('mencionarIntegrantes', 'Mencionar a quienes tienen saldo', 'Solo a integrantes con WhatsApp vinculado; al resto se le nombra.')}
							</Grupo>

							<Grupo titulo="Movimientos">
								{casilla('avisarInicioMes', 'Recibos del nuevo mes')}
								{casilla('avisarMonto', 'Llegó o se corrigió un monto')}
								{casilla('avisarPagoEnviado', 'Pago registrado para validar')}
								{casilla('avisarPagoConfirmado', 'Pago confirmado')}
								{casilla('avisarRecaudacionCompleta', 'Recaudación completa')}
								{casilla('avisarPagoProveedor', 'Pago a la empresa')}
								{casilla('avisarCambiosRecibo', 'Cambios de vencimiento, reparto o anulación')}
							</Grupo>

							<Grupo titulo="Administración">
								{casilla('avisarPendientesAdmin', 'Pendientes de administración', 'Pagos por validar, montos y fechas faltantes, vencidos.')}
								<label className="block"><span className="fh-label">Hora del aviso</span><input type="time" className="fh-input" value={formulario.horaPendientesAdmin} onChange={(e) => actualizar('horaPendientesAdmin', e.target.value)} required /></label>
								{casilla('avisarCierreMes', 'Cierre de mes')}
							</Grupo>

							<Grupo titulo="Resumen">
								{casilla('resumenSemanal', 'Resumen semanal del mes')}
								<div className="grid grid-cols-2 gap-3">
									<label><span className="fh-label">Día</span><select className="fh-input" value={formulario.diaResumen} onChange={(e) => actualizar('diaResumen', Number(e.target.value))}>{DIAS_SEMANA.map((nombre, indice) => <option key={nombre} value={indice}>{nombre}</option>)}</select></label>
									<label><span className="fh-label">Hora</span><input type="time" className="fh-input" value={formulario.horaResumen} onChange={(e) => actualizar('horaResumen', e.target.value)} required /></label>
								</div>
							</Grupo>
						</div>

						<button className="fh-button-primary mt-5" disabled={guardando}>{guardando ? 'Guardando...' : 'Guardar'}</button>
					</form>

					<div className="mt-6 flex flex-col gap-4 rounded-2xl border border-slate-100 p-5 sm:flex-row sm:items-start sm:justify-between">
						<div>
							<h3 className="text-sm font-semibold">Preguntas en lenguaje natural</h3>
							<p className="mt-1 max-w-xl text-xs leading-5 text-slate-400">Permite preguntar al bot sin comandos, mencionándolo o respondiendo a sus mensajes. Privacidad: la pregunta y los datos consultados se envían a la API de Claude (Anthropic) para redactar la respuesta.</p>
						</div>
						<button
							type="button"
							role="switch"
							aria-checked={formulario.lenguajeNatural}
							disabled={trabajando}
							onClick={() => void alternarLenguajeNatural()}
							className={`relative h-7 w-12 shrink-0 rounded-full transition disabled:opacity-60 ${formulario.lenguajeNatural ? 'bg-brand' : 'bg-slate-200'}`}
						>
							<span className={`absolute top-1 size-5 rounded-full bg-white shadow transition ${formulario.lenguajeNatural ? 'left-6' : 'left-1'}`} />
							<span className="sr-only">Preguntas en lenguaje natural</span>
						</button>
					</div>
				</>
			)}

			{(message || error) && <p className="fh-alert mt-5">{message ?? error}</p>}
		</section>
	)
}

function Grupo({ titulo, children }: { titulo: string; children: ReactNode }) {
	return (
		<fieldset className="space-y-3 rounded-2xl border border-slate-100 p-5">
			<legend className="px-1 text-sm font-semibold">{titulo}</legend>
			{children}
		</fieldset>
	)
}
