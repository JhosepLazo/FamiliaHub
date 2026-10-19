import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import type { Enums, Json } from '../../types/database'
import { useFamilia } from '../familia/FamiliaContext'

export type TipoVinculoWhatsApp = Enums<'tipo_vinculo_whatsapp'>

export type ConfiguracionWhatsApp = {
	avisosActivos: boolean
	diasAvisoPrevio: number[]
	avisarVenceHoy: boolean
	frecuenciaVencidosDias: number
	horaInicioEnvio: string
	horaFinEnvio: string
	avisarInicioMes: boolean
	avisarMonto: boolean
	avisarPagoEnviado: boolean
	avisarPagoConfirmado: boolean
	avisarRecaudacionCompleta: boolean
	avisarPagoProveedor: boolean
	avisarCambiosRecibo: boolean
	avisarPendientesAdmin: boolean
	horaPendientesAdmin: string
	resumenSemanal: boolean
	diaResumen: number
	horaResumen: string
	avisarCierreMes: boolean
	mencionarIntegrantes: boolean
	lenguajeNatural: boolean
}

export type VinculoWhatsApp = {
	vinculado: boolean
	vinculadoAt: string | null
	codigo: string | null
	codigoExpiraAt: string | null
}

export type IntegranteWhatsApp = {
	miembroId: string
	nombre: string
	rol: Enums<'rol_familia'>
	vinculado: boolean
}

export type EstadoWhatsApp = {
	esAdmin: boolean
	bot: { ultimoHeartbeatAt: string | null }
	grupo: VinculoWhatsApp
	yo: VinculoWhatsApp
	integrantes: IntegranteWhatsApp[]
	configuracion: ConfiguracionWhatsApp | null
}

export type CodigoGenerado = {
	codigo: string
	expiraAt: string
}

export const CONFIGURACION_POR_DEFECTO: ConfiguracionWhatsApp = {
	avisosActivos: true,
	diasAvisoPrevio: [3, 1],
	avisarVenceHoy: true,
	frecuenciaVencidosDias: 3,
	horaInicioEnvio: '08:00',
	horaFinEnvio: '21:00',
	avisarInicioMes: true,
	avisarMonto: true,
	avisarPagoEnviado: true,
	avisarPagoConfirmado: true,
	avisarRecaudacionCompleta: true,
	avisarPagoProveedor: true,
	avisarCambiosRecibo: true,
	avisarPendientesAdmin: true,
	horaPendientesAdmin: '09:00',
	resumenSemanal: true,
	diaResumen: 0,
	horaResumen: '19:00',
	avisarCierreMes: true,
	mencionarIntegrantes: true,
	lenguajeNatural: false,
}

const CLAVES_SERVIDOR: Record<keyof ConfiguracionWhatsApp, string> = {
	avisosActivos: 'avisos_activos',
	diasAvisoPrevio: 'dias_aviso_previo',
	avisarVenceHoy: 'avisar_vence_hoy',
	frecuenciaVencidosDias: 'frecuencia_vencidos_dias',
	horaInicioEnvio: 'hora_inicio_envio',
	horaFinEnvio: 'hora_fin_envio',
	avisarInicioMes: 'avisar_inicio_mes',
	avisarMonto: 'avisar_monto',
	avisarPagoEnviado: 'avisar_pago_enviado',
	avisarPagoConfirmado: 'avisar_pago_confirmado',
	avisarRecaudacionCompleta: 'avisar_recaudacion_completa',
	avisarPagoProveedor: 'avisar_pago_proveedor',
	avisarCambiosRecibo: 'avisar_cambios_recibo',
	avisarPendientesAdmin: 'avisar_pendientes_admin',
	horaPendientesAdmin: 'hora_pendientes_admin',
	resumenSemanal: 'resumen_semanal',
	diaResumen: 'dia_resumen',
	horaResumen: 'hora_resumen',
	avisarCierreMes: 'avisar_cierre_mes',
	mencionarIntegrantes: 'mencionar_integrantes',
	lenguajeNatural: 'lenguaje_natural',
}

export const DIAS_SEMANA = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado']

const HORA = /^([01][0-9]|2[0-3]):[0-5][0-9]$/

// Mismas reglas que guardar_configuracion_whatsapp en la base de datos.
export function validarConfiguracion(configuracion: ConfiguracionWhatsApp): string | null {
	const { diasAvisoPrevio: dias } = configuracion

	if (dias.length > 5) return 'Puedes configurar como máximo 5 días de aviso previo.'
	if (dias.some((dia) => !Number.isInteger(dia) || dia < 1 || dia > 15)) return 'Cada día de aviso previo debe estar entre 1 y 15.'
	if (!Number.isInteger(configuracion.frecuenciaVencidosDias) || configuracion.frecuenciaVencidosDias < 0 || configuracion.frecuenciaVencidosDias > 15) {
		return 'La frecuencia de recordatorios de vencidos debe estar entre 0 y 15 días.'
	}
	if (!Number.isInteger(configuracion.diaResumen) || configuracion.diaResumen < 0 || configuracion.diaResumen > 6) return 'Elige un día válido para el resumen.'

	const horas = [configuracion.horaInicioEnvio, configuracion.horaFinEnvio, configuracion.horaPendientesAdmin, configuracion.horaResumen]
	if (horas.some((hora) => !HORA.test(hora))) return 'Las horas deben tener el formato HH:MM.'

	if (configuracion.horaInicioEnvio >= configuracion.horaFinEnvio) return 'La hora de inicio de envío debe ser menor que la hora de fin.'
	if (configuracion.horaPendientesAdmin < configuracion.horaInicioEnvio || configuracion.horaPendientesAdmin >= configuracion.horaFinEnvio) {
		return 'La hora de pendientes de administración debe estar dentro del horario de envío.'
	}
	if (configuracion.horaResumen < configuracion.horaInicioEnvio || configuracion.horaResumen >= configuracion.horaFinEnvio) {
		return 'La hora del resumen semanal debe estar dentro del horario de envío.'
	}

	return null
}

export function configuracionParaServidor(configuracion: Partial<ConfiguracionWhatsApp>): { [clave: string]: Json } {
	const resultado: { [clave: string]: Json } = {}

	for (const [clave, valor] of Object.entries(configuracion) as [keyof ConfiguracionWhatsApp, Json][]) {
		if (valor !== undefined) resultado[CLAVES_SERVIDOR[clave]] = valor
	}

	return resultado
}

export function estadoBot(ultimoHeartbeatAt: string | null, ahora = Date.now()) {
	if (!ultimoHeartbeatAt) return { activo: false, texto: 'Aún no se ha conectado' }

	const minutos = (ahora - new Date(ultimoHeartbeatAt).getTime()) / 60_000
	if (minutos < 10) return { activo: true, texto: 'Activo' }

	return { activo: false, texto: `Sin conexión desde ${tiempoDesde(ultimoHeartbeatAt, ahora)}` }
}

export function tiempoDesde(fecha: string, ahora = Date.now()) {
	const minutos = Math.max(0, Math.round((ahora - new Date(fecha).getTime()) / 60_000))
	if (minutos < 60) return `hace ${minutos} minuto${minutos === 1 ? '' : 's'}`

	const horas = Math.round(minutos / 60)
	if (horas < 24) return `hace ${horas} hora${horas === 1 ? '' : 's'}`

	const dias = Math.round(horas / 24)
	return `hace ${dias} día${dias === 1 ? '' : 's'}`
}

export function fechaHora(valor: string | null) {
	if (!valor) return ''
	return new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(valor))
}

export function codigoVigente(vinculo: VinculoWhatsApp | null | undefined, ahora = Date.now()) {
	return Boolean(vinculo?.codigo && vinculo.codigoExpiraAt && new Date(vinculo.codigoExpiraAt).getTime() > ahora)
}

export function useCuentaRegresiva(expiraAt: string | null) {
	const calcular = useCallback(() => (expiraAt ? Math.max(0, Math.ceil((new Date(expiraAt).getTime() - Date.now()) / 1000)) : 0), [expiraAt])
	const [segundos, setSegundos] = useState(calcular)

	useEffect(() => {
		setSegundos(calcular())
		if (!expiraAt) return
		const intervalo = window.setInterval(() => setSegundos(calcular()), 1000)
		return () => window.clearInterval(intervalo)
	}, [expiraAt, calcular])

	return segundos
}

// Mientras haya un código vigente, consulta el estado cada 5 segundos para detectar el vínculo.
export function useConsultaPeriodica(activa: boolean, consultar: () => Promise<void>) {
	useEffect(() => {
		if (!activa) return
		const intervalo = window.setInterval(() => void consultar(), 5000)
		return () => window.clearInterval(intervalo)
	}, [activa, consultar])
}

export function useWhatsApp() {
	const { familia } = useFamilia()
	const [estado, setEstado] = useState<EstadoWhatsApp | null>(null)
	const [loading, setLoading] = useState(true)
	const [error, setError] = useState<string | null>(null)

	const cargar = useCallback(async (silencioso = false) => {
		if (!familia) return
		if (!silencioso) setLoading(true)

		const { data, error: rpcError } = await supabase.rpc('obtener_estado_whatsapp', { p_familia_id: familia.id })

		if (rpcError) {
			setError(rpcError.message)
		} else {
			setError(null)
			setEstado(data as unknown as EstadoWhatsApp)
		}

		if (!silencioso) setLoading(false)
	}, [familia])

	useEffect(() => { void cargar() }, [cargar])

	const recargar = useCallback(() => cargar(true), [cargar])

	const generarCodigo = useCallback(async (tipo: TipoVinculoWhatsApp) => {
		if (!familia) throw new Error('No hay una familia activa.')
		const { data, error: rpcError } = await supabase.rpc('generar_codigo_whatsapp', { p_familia_id: familia.id, p_tipo: tipo })
		if (rpcError) throw new Error(rpcError.message)
		await cargar(true)
		return data as unknown as CodigoGenerado
	}, [familia, cargar])

	const desvincular = useCallback(async (tipo: TipoVinculoWhatsApp) => {
		if (!familia) throw new Error('No hay una familia activa.')
		const { error: rpcError } = await supabase.rpc('desvincular_whatsapp', { p_familia_id: familia.id, p_tipo: tipo })
		if (rpcError) throw new Error(rpcError.message)
		await cargar(true)
	}, [familia, cargar])

	const guardarConfiguracion = useCallback(async (cambios: Partial<ConfiguracionWhatsApp>) => {
		if (!familia) throw new Error('No hay una familia activa.')
		const { error: rpcError } = await supabase.rpc('guardar_configuracion_whatsapp', {
			p_familia_id: familia.id,
			p_configuracion: configuracionParaServidor(cambios),
		})
		if (rpcError) throw new Error(rpcError.message)
		await cargar(true)
	}, [familia, cargar])

	return {
		estado,
		loading,
		error,
		recargar,
		generarCodigo,
		desvincular,
		guardarConfiguracion,
	}
}
