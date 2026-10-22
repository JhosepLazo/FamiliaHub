/**
 * FamiliaHub · Recibos digitales
 *
 * Revisa cada hora en este Gmail los recibos digitales de SEDAPAL, Luz del Sur y Cálidda, lee el número de
 * suministro, el monto y el vencimiento, y se los envía a FamiliaHub, que confirma solo el recibo del mes.
 * Envía únicamente esos datos y el identificador del correo; nunca el texto del correo.
 *
 * Instalación (detalle en recibos-digitales/README.md): pega este archivo en https://script.new, guarda,
 * elige la función "instalar" y pulsa Ejecutar. Acepta los permisos que pide Google.
 */

const CONFIG = {
	url: '__FAMILIAHUB_URL__',
	secreto: '__FAMILIAHUB_SECRETO__',
	diasHaciaAtras: 40,
}

const PROVEEDORES = [
	{ codigo: 'SEDAPAL', busqueda: 'from:(sedapal.com.pe)' },
	{ codigo: 'LUZ_DEL_SUR', busqueda: 'from:(luzdelsur.com.pe OR luzdelsur.pe)' },
	{ codigo: 'CALIDDA', busqueda: 'from:(calidda.com.pe)' },
]

const ETIQUETA_LEIDO = 'FamiliaHub/Recibo leído'
const ETIQUETA_REVISAR = 'FamiliaHub/Revisar'
const MAX_PROCESADOS = 300

const MESES = {
	enero: 1, ene: 1, febrero: 2, feb: 2, marzo: 3, mar: 3, abril: 4, abr: 4, mayo: 5, may: 5, junio: 6, jun: 6,
	julio: 7, jul: 7, agosto: 8, ago: 8, septiembre: 9, setiembre: 9, sep: 9, set: 9, octubre: 10, oct: 10,
	noviembre: 11, nov: 11, diciembre: 12, dic: 12,
}

/** Ejecútala una vez: crea la revisión automática cada hora y revisa los recibos de inmediato. */
function instalar() {
	if (CONFIG.url.indexOf('__') === 0 || CONFIG.secreto.indexOf('__') === 0) {
		throw new Error('Este es el archivo plantilla, sin la dirección ni la clave. Pega el script que preparó activar.cmd: ' +
			'queda en el portapapeles y en %LOCALAPPDATA%\\FamiliaHub\\RecibosDigitales-listo.gs.')
	}

	const ping = enviar({ accion: 'ping' })
	if (!ping.ok) throw new Error('No pude conectar con FamiliaHub: ' + (ping.error || 'revisa la dirección y la clave en CONFIG.'))

	ScriptApp.getProjectTriggers()
		.filter((disparador) => disparador.getHandlerFunction() === 'revisarRecibos')
		.forEach((disparador) => ScriptApp.deleteTrigger(disparador))
	ScriptApp.newTrigger('revisarRecibos').timeBased().everyHours(1).create()
	Logger.log('Conectado con FamiliaHub. Revisaré tus recibos digitales cada hora.')
	revisarRecibos()
}

/** La ejecuta el disparador cada hora. También puedes ejecutarla a mano. */
function revisarRecibos() {
	const procesados = leerProcesados()
	const limite = new Date(Date.now() - CONFIG.diasHaciaAtras * 24 * 60 * 60 * 1000)

	PROVEEDORES.forEach((proveedor) => {
		GmailApp.search(proveedor.busqueda + ' newer_than:' + CONFIG.diasHaciaAtras + 'd', 0, 30).forEach((hilo) => {
			hilo.getMessages().forEach((mensaje) => {
				const id = mensaje.getId()
				if (procesados.indexOf(id) !== -1 || mensaje.getDate() < limite) return
				const resultado = procesarMensaje(mensaje, proveedor.codigo)
				if (resultado !== 'REINTENTAR') procesados.push(id)
			})
		})
	})

	guardarProcesados(procesados)
}

/** Muestra en el registro lo que se leería del último correo de cada proveedor, sin enviar nada. */
function probar() {
	PROVEEDORES.forEach((proveedor) => {
		const hilos = GmailApp.search(proveedor.busqueda, 0, 1)
		if (!hilos.length) return Logger.log(proveedor.codigo + ': no encontré correos todavía.')
		const mensajes = hilos[0].getMessages()
		const mensaje = mensajes[mensajes.length - 1]
		Logger.log(proveedor.codigo + ' (' + mensaje.getSubject() + '): ' + JSON.stringify(leerRecibo(mensaje.getSubject() + '\n' + textoDelCorreo(mensaje), mensaje.getDate())))
	})
}

function procesarMensaje(mensaje, proveedor) {
	const lectura = leerRecibo(mensaje.getSubject() + '\n' + textoDelCorreo(mensaje), mensaje.getDate())

	// Sin monto ni vencimiento no es un recibo (por ejemplo, una promoción): se deja pasar sin marcarlo.
	if (!lectura.monto && !lectura.vencimiento) return 'NO_ES_RECIBO'

	if (!lectura.monto || !lectura.vencimiento || !lectura.suministros.length) {
		etiquetar(mensaje, ETIQUETA_REVISAR)
		return 'INCOMPLETO'
	}

	const respuesta = enviar({
		mensajeId: mensaje.getId(),
		proveedor: proveedor,
		suministros: lectura.suministros,
		monto: lectura.monto,
		vencimiento: lectura.vencimiento,
	})

	if (respuesta.reintentar) return 'REINTENTAR'
	etiquetar(mensaje, respuesta.estado === 'CONFIRMADO' || respuesta.estado === 'EN_ESPERA' ? ETIQUETA_LEIDO : ETIQUETA_REVISAR)
	Logger.log(proveedor + ': ' + (respuesta.estado || 'ERROR') + ' · ' + (respuesta.detalle || respuesta.error || ''))
	return respuesta.estado || 'ERROR'
}

function enviar(cuerpo) {
	try {
		const respuesta = UrlFetchApp.fetch(CONFIG.url, {
			method: 'post',
			contentType: 'application/json',
			headers: { 'x-recibos-secret': CONFIG.secreto },
			payload: JSON.stringify(cuerpo),
			muteHttpExceptions: true,
		})
		const codigo = respuesta.getResponseCode()
		const datos = JSON.parse(respuesta.getContentText() || '{}')
		if (codigo === 200) return datos
		if (codigo >= 500 || codigo === 429) return { reintentar: true, error: datos.error }
		return { error: datos.error || 'Respuesta ' + codigo }
	} catch (error) {
		return { reintentar: true, error: String(error) }
	}
}

function textoDelCorreo(mensaje) {
	const plano = mensaje.getPlainBody() || ''
	if (plano.replace(/\s/g, '').length >= 40) return plano
	return htmlATexto(mensaje.getBody() || '')
}

function htmlATexto(html) {
	return html
		.replace(/<(script|style)[\s\S]*?<\/\1>/gi, ' ')
		.replace(/<br\s*\/?>|<\/(p|div|tr|li|h\d)>/gi, '\n')
		.replace(/<\/t[dh]>/gi, ' ')
		.replace(/<[^>]+>/g, ' ')
		.replace(/&nbsp;/gi, ' ')
		.replace(/&amp;/gi, '&')
		.replace(/&aacute;/gi, 'á').replace(/&eacute;/gi, 'é').replace(/&iacute;/gi, 'í').replace(/&oacute;/gi, 'ó').replace(/&uacute;/gi, 'ú')
		.replace(/&ntilde;/gi, 'ñ').replace(/&deg;/gi, '°').replace(/&ordm;/gi, 'º')
		.replace(/&#(\d+);/g, (_, codigo) => String.fromCharCode(Number(codigo)))
}

/* ---------- Lectura del recibo (funciones puras: se prueban fuera de Google) ---------- */

function leerRecibo(texto, fechaCorreo) {
	const limpio = String(texto || '').replace(/\u00a0/g, ' ').replace(/[ \t]+/g, ' ')
	return {
		suministros: buscarSuministros(limpio),
		monto: buscarMonto(limpio),
		vencimiento: buscarVencimiento(limpio, fechaCorreo && typeof fechaCorreo.getTime === 'function' ? fechaCorreo : new Date()),
	}
}

const CANTIDAD = '([0-9]{1,3}(?:[.,][0-9]{3})+(?:[.,][0-9]{2})?|[0-9]+(?:[.,][0-9]{2})?)(?![0-9])'
const MONEDA = '(?:S\\/\\.?|PEN|soles)'

// De más seguro a menos: primero las frases típicas de "total a pagar"; luego "importe", "monto" o "deuda"
// seguidos del número; luego "total" con S/; y por último, si el correo tiene un solo monto en soles, ese.
function buscarMonto(texto) {
	const intentos = [
		new RegExp('(?:total\\s+a\\s+pagar|importe\\s+(?:total\\s+)?a\\s+pagar|monto\\s+(?:total\\s+)?a\\s+pagar|total\\s+a\\s+cancelar|deuda\\s+total|importe\\s+total|monto\\s+total|saldo\\s+a\\s+pagar|total\\s+de(?:l)?\\s+(?:mes|recibo|periodo))\\s*:?\\s*(?:es\\s+de\\s+)?' + MONEDA + '?\\s*' + CANTIDAD, 'i'),
		new RegExp('\\b(?:importe|monto|deuda(?!\\s+anterior)|a\\s+pagar|por\\s+pagar)\\b(?:\\s+(?:del\\s+mes|del\\s+recibo|de\\s+tu\\s+recibo|de\\s+su\\s+recibo))?\\s*:?\\s*(?:es\\s+de\\s+)?' + MONEDA + '\\s*' + CANTIDAD, 'i'),
		new RegExp('\\btotal\\b[^\\n0-9S]{0,20}' + MONEDA + '\\s*' + CANTIDAD, 'i'),
	]
	for (const regla of intentos) {
		const encontrado = texto.match(regla)
		const valor = encontrado && aNumero(encontrado[1])
		if (valor && valor > 0 && valor <= 100000) return valor
	}
	const montos = []
	const enSoles = new RegExp(MONEDA + '\\s*' + CANTIDAD, 'gi')
	let encontrado
	while ((encontrado = enSoles.exec(texto)) !== null) {
		const valor = aNumero(encontrado[1])
		if (valor && valor > 0 && valor <= 100000 && montos.indexOf(valor) === -1) montos.push(valor)
	}
	return montos.length === 1 ? montos[0] : null
}

function aNumero(cantidad) {
	let texto = cantidad
	const coma = texto.lastIndexOf(',')
	const punto = texto.lastIndexOf('.')
	if (coma !== -1 && punto !== -1) {
		texto = coma > punto ? texto.replace(/\./g, '').replace(',', '.') : texto.replace(/,/g, '')
	} else if (coma !== -1) {
		texto = /,[0-9]{2}$/.test(texto) ? texto.replace(/,(?=[0-9]{3}(?:,|$))/g, '').replace(',', '.') : texto.replace(/,/g, '')
	} else if (punto !== -1 && !/\.[0-9]{2}$/.test(texto)) {
		texto = texto.replace(/\./g, '')
	}
	const valor = Math.round(parseFloat(texto) * 100) / 100
	return isNaN(valor) ? null : valor
}

function buscarVencimiento(texto, fechaCorreo) {
	const etiqueta = '(?:fecha\\s+de\\s+vencimiento|vencimiento|vencer[aá](?:\\s+el)?|vence(?:\\s+el)?|fecha\\s+l[ií]mite(?:\\s+de\\s+pago)?|pag(?:ar|a|ue)\\s+(?:hasta|antes\\s+del?)(?:\\s+el)?|hasta\\s+el|[uú]ltimo\\s+d[ií]a\\s+de\\s+pago|fecha\\s+de\\s+pago)'
	const numerica = new RegExp(etiqueta + '[^0-9\\n]{0,30}([0-9]{1,2})[\\/\\-.]([0-9]{1,2})[\\/\\-.]([0-9]{2,4})', 'i')
	const enLetras = new RegExp(etiqueta + '[^0-9\\n]{0,30}([0-9]{1,2})\\s+(?:de\\s+)?([a-záéíóú]+)\\.?(?:\\s+(?:de(?:l)?\\s+)?([0-9]{4}))?', 'i')
	const sinAnio = new RegExp(etiqueta + '[^0-9\\n]{0,30}([0-9]{1,2})[\\/\\-]([0-9]{1,2})(?![0-9\\/\\-.])', 'i')

	const a = texto.match(numerica)
	if (a) return fechaIso(Number(a[1]), Number(a[2]), Number(a[3]))
	const b = texto.match(enLetras)
	if (b) {
		const mes = MESES[b[2].toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '')]
		if (mes) return b[3] ? fechaIso(Number(b[1]), mes, Number(b[3])) : conAnioProbable(Number(b[1]), mes, fechaCorreo)
	}
	const c = texto.match(sinAnio)
	if (c) return conAnioProbable(Number(c[1]), Number(c[2]), fechaCorreo)
	return null
}

// "Vence el 25/10" sin año: el del correo; si así quedaría más de 2 meses antes del correo, el siguiente.
function conAnioProbable(dia, mes, fechaCorreo) {
	const anio = fechaCorreo.getFullYear()
	const fecha = fechaIso(dia, mes, anio)
	if (!fecha) return null
	const limite = new Date(fechaCorreo.getTime() - 60 * 24 * 60 * 60 * 1000)
	return new Date(fecha + 'T12:00:00Z') < limite ? fechaIso(dia, mes, anio + 1) : fecha
}

function fechaIso(dia, mes, anio) {
	const completo = anio < 100 ? 2000 + anio : anio
	const fecha = new Date(Date.UTC(completo, mes - 1, dia))
	if (fecha.getUTCFullYear() !== completo || fecha.getUTCMonth() !== mes - 1 || fecha.getUTCDate() !== dia) return null
	return completo + '-' + String(mes).padStart(2, '0') + '-' + String(dia).padStart(2, '0')
}

// Números de suministro o de cliente. Si el correo los muestra ocultos ("****6543"), se envían como "*6543"
// y FamiliaHub los reconoce por sus últimas cifras solo si coinciden con un único servicio.
function buscarSuministros(texto) {
	const candidatos = []
	const etiqueta = '(?:n[°ºo]?\\.?\\s*(?:de\\s+)?suministro|suministro|n[°ºo]?\\.?\\s*(?:de\\s+)?cliente|c[oó]digo\\s+de\\s+(?:cliente|suministro)|n[uú]mero\\s+de\\s+(?:cliente|suministro)|cuenta\\s+contrato|\\bnis\\b)'
	const etiquetados = new RegExp(etiqueta + '\\s*:?\\s*([*xX•·#]{2,}[ \\-]?[0-9]{3,12}|[0-9][0-9 \\-]{3,18}[0-9])', 'gi')
	let encontrado
	while ((encontrado = etiquetados.exec(texto)) !== null) agregar(candidatos, encontrado[1])

	if (!candidatos.length) {
		// Respaldo: números sueltos de 6 a 12 dígitos, u ocultos como "****6543". FamiliaHub solo acepta uno
		// que coincida con un suministro registrado de ese proveedor, así que un número cualquiera no confirma nada.
		const sueltos = texto.match(/(?<![0-9.,\/\-])[0-9]{6,12}(?![0-9.,\/\-])|[*xX•·#]{3,}[0-9]{4,12}(?![0-9])/g) || []
		sueltos.forEach((numero) => agregar(candidatos, numero))
	}
	return candidatos.slice(0, 10)
}

function agregar(lista, valor) {
	const oculto = /[*xX•·#]/.test(valor)
	const digitos = String(valor).replace(/[^0-9]/g, '')
	const final = oculto ? '*' + digitos : digitos
	if ((oculto ? digitos.length >= 4 : digitos.length >= 5) && digitos.length <= 14 && lista.indexOf(final) === -1) lista.push(final)
}

/* ---------- Apoyo ---------- */

function etiquetar(mensaje, nombre) {
	const etiqueta = GmailApp.getUserLabelByName(nombre) || GmailApp.createLabel(nombre)
	mensaje.getThread().addLabel(etiqueta)
}

function leerProcesados() {
	try {
		return JSON.parse(PropertiesService.getScriptProperties().getProperty('procesados') || '[]')
	} catch (error) {
		return []
	}
}

function guardarProcesados(lista) {
	PropertiesService.getScriptProperties().setProperty('procesados', JSON.stringify(lista.slice(-MAX_PROCESADOS)))
}
