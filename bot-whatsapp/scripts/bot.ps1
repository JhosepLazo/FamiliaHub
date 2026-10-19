<#
.SYNOPSIS
Enciende, apaga y revisa el bot de WhatsApp de FamiliaHub en Windows.

.DESCRIPTION
iniciar  : instala dependencias, muestra el QR si falta vincular el WhatsApp del bot y lo deja
           funcionando en segundo plano, con inicio automático al entrar a Windows.
detener  : apaga el bot y quita el inicio automático.
estado   : muestra si está funcionando y las últimas líneas del registro.
ejecutar : uso interno de la tarea programada; reinicia el bot si se cae por un error inesperado.

Códigos de salida del bot: 0 detenido a propósito, 1 necesita intervención (configuración o
sesión cerrada desde el teléfono), cualquier otro es un error inesperado y se reinicia.
#>
param(
	[ValidateSet('iniciar', 'detener', 'estado', 'ejecutar')]
	[string]$Accion = 'iniciar'
)

$ErrorActionPreference = 'Stop'

$DirBot = Split-Path -Parent $PSScriptRoot
$Index = Join-Path $DirBot 'index.ts'
$ArchivoEnv = Join-Path $DirBot '.env'
$DirLogs = Join-Path $DirBot 'logs'
$Log = Join-Path $DirLogs 'bot.log'
$LogAnterior = Join-Path $DirLogs 'bot.anterior.log'
$NombreTarea = 'FamiliaHub Bot WhatsApp'
$NodeMinimo = [version]'22.18.0'
$TamanoMaximoLog = 5MB
$Utf8 = New-Object Text.UTF8Encoding($false)

function Escribir-Paso([string]$Texto) { Write-Host ''; Write-Host "==> $Texto" -ForegroundColor Cyan }
function Escribir-Ok([string]$Texto) { Write-Host "    $Texto" -ForegroundColor Green }
function Escribir-Aviso([string]$Texto) { Write-Host "    $Texto" -ForegroundColor Yellow }

function Agregar-Log([string]$Texto) {
	New-Item -ItemType Directory -Force $DirLogs | Out-Null
	[IO.File]::AppendAllText($Log, ('[{0}] {1}{2}' -f (Get-Date -Format 'dd/MM/yyyy HH:mm:ss'), $Texto, [Environment]::NewLine), $Utf8)
}

function Obtener-Node {
	$comando = Get-Command node.exe -ErrorAction SilentlyContinue
	$ruta = if ($comando) { $comando.Source } else { Join-Path $env:ProgramFiles 'nodejs\node.exe' }
	if (-not (Test-Path $ruta)) {
		throw 'No encontré Node.js. Instálalo con:  winget install OpenJS.NodeJS.LTS  y vuelve a abrir este archivo.'
	}
	$version = [version]((& $ruta -p 'process.versions.node').Trim())
	if ($version -lt $NodeMinimo) {
		throw "Tienes Node.js $version y el bot necesita $NodeMinimo o superior. Actualízalo con:  winget upgrade OpenJS.NodeJS.LTS"
	}
	$ruta
}

function Leer-Env {
	$valores = @{}
	if (Test-Path $ArchivoEnv) {
		foreach ($linea in [IO.File]::ReadAllLines($ArchivoEnv, $Utf8)) {
			if ($linea -match '^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$') { $valores[$Matches[1]] = $Matches[2].Trim([char[]]@('"', "'")) }
		}
	}
	$valores
}

function Obtener-DirSesion($Valores) {
	$dir = if ($Valores['AUTH_DIR']) { $Valores['AUTH_DIR'] } else { 'auth' }
	if ([IO.Path]::IsPathRooted($dir)) { $dir } else { Join-Path $DirBot $dir }
}

function Sesion-Vinculada($Valores) {
	$creds = Join-Path (Obtener-DirSesion $Valores) 'creds.json'
	(Test-Path $creds) -and ([IO.File]::ReadAllText($creds) -match '"me"\s*:')
}

# Solo el usuario actual (y el sistema) pueden leer la sesión: equivale a tener el WhatsApp del chip abierto.
function Proteger-Ruta([string]$Ruta) {
	if (-not (Test-Path $Ruta)) { return }
	$usuario = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
	$permiso = if ((Get-Item $Ruta).PSIsContainer) { '(OI)(CI)F' } else { 'F' }
	& icacls.exe $Ruta /inheritance:r /grant:r "*${usuario}:$permiso" "*S-1-5-18:$permiso" | Out-Null
	if ($LASTEXITCODE -ne 0) { Escribir-Aviso "No pude restringir los permisos de $Ruta." }
}

# Quien llame debe envolver el resultado en @(): con un solo proceso, PowerShell 5.1 devuelve el objeto
# suelto y su .Count queda vacío.
function Obtener-ProcesosBot {
	@(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" | Where-Object {
		$_.CommandLine -and $_.CommandLine.IndexOf($Index, [StringComparison]::OrdinalIgnoreCase) -ge 0
	})
}

function Obtener-Lanzadores {
	@(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" | Where-Object {
		$_.ProcessId -ne $PID -and $_.CommandLine -and
		$_.CommandLine.IndexOf($PSCommandPath, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
		$_.CommandLine -match '-Accion ejecutar'
	})
}

function Leer-LogDesde([long]$Posicion) {
	if (-not (Test-Path $Log)) { return '' }
	$flujo = [IO.File]::Open($Log, 'Open', 'Read', 'ReadWrite')
	try {
		if ($flujo.Length -lt $Posicion) { $Posicion = 0 }
		[void]$flujo.Seek($Posicion, 'Begin')
		(New-Object IO.StreamReader($flujo, $Utf8)).ReadToEnd()
	} finally {
		$flujo.Dispose()
	}
}

function Formatear-Linea([string]$Linea) {
	if ($Linea.StartsWith('{')) {
		try {
			$dato = $Linea | ConvertFrom-Json
			$hora = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$dato.time).LocalDateTime.ToString('dd/MM/yyyy HH:mm:ss')
			$nivel = switch ([int]$dato.level) { 60 { 'FATAL' } 50 { 'ERROR' } 40 { 'AVISO' } 30 { 'INFO' } default { 'DEBUG' } }
			$detalle = if ($dato.err -is [string]) { " ($($dato.err))" } elseif ($dato.err.message) { " ($($dato.err.message))" } else { '' }
			return "    [$hora] $nivel $($dato.msg)$detalle"
		} catch {
			# Si no es JSON de pino se muestra tal cual.
		}
	}
	"    $Linea"
}

# npm y node escriben avisos en stderr; con Stop, PowerShell 5.1 los trataría como errores si stderr
# está redirigido. Aquí se usa Continue y se decide con $LASTEXITCODE.
function Preparar {
	$ErrorActionPreference = 'Continue'
	Escribir-Paso 'Revisando requisitos'
	$node = Obtener-Node
	Escribir-Ok "Node.js $((& $node -p 'process.versions.node').Trim())"

	$valores = Leer-Env
	if (-not $valores['FAMILIAHUB_BOT_SECRET'] -or -not $valores['FAMILIAHUB_FUNCTION_URL']) {
		throw 'Falta configurar el bot. Primero ejecuta configurar-supabase.cmd: crea el archivo .env con el secreto.'
	}
	Escribir-Ok 'Archivo .env listo'

	$lock = Join-Path $DirBot 'package-lock.json'
	$lockInstalado = Join-Path $DirBot 'node_modules\.package-lock.json'
	if (-not (Test-Path $lockInstalado) -or (Get-Item $lock).LastWriteTime -gt (Get-Item $lockInstalado).LastWriteTime) {
		Escribir-Paso 'Instalando dependencias del bot (solo la primera vez)'
		Push-Location $DirBot
		try {
			& (Join-Path (Split-Path $node) 'npm.cmd') ci --no-audit --no-fund
			if ($LASTEXITCODE -ne 0) { throw 'npm ci falló. Revisa tu conexión a internet y vuelve a intentarlo.' }
		} finally {
			Pop-Location
		}
	}
	Escribir-Ok 'Dependencias instaladas'

	@{ Node = $node; Env = $valores }
}

function Registrar-Tarea {
	$usuario = [Security.Principal.WindowsIdentity]::GetCurrent().Name
	$argumentos = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -Accion ejecutar"
	$accion = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argumentos -WorkingDirectory $DirBot
	$disparador = New-ScheduledTaskTrigger -AtLogOn -User $usuario
	# Sin límite de tiempo: por defecto Windows detiene las tareas a los 3 días.
	$ajustes = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)
	$principal = New-ScheduledTaskPrincipal -UserId $usuario -LogonType Interactive -RunLevel Limited
	Register-ScheduledTask -TaskName $NombreTarea -Description 'Bot de WhatsApp de FamiliaHub. Se administra con iniciar-bot.cmd y detener-bot.cmd.' `
		-Action $accion -Trigger $disparador -Settings $ajustes -Principal $principal -Force | Out-Null
}

function Vincular-WhatsApp([string]$Node) {
	$ErrorActionPreference = 'Continue'
	Push-Location $DirBot
	try {
		& $Node --env-file-if-exists=.env $Index --vincular
	} finally {
		Pop-Location
	}
}

function Iniciar {
	$listo = Preparar

	if (@(Obtener-ProcesosBot).Count -gt 0) {
		Escribir-Aviso 'El bot ya está funcionando.'
		Mostrar-Estado
		return
	}

	if (-not (Sesion-Vinculada $listo.Env)) {
		Escribir-Paso 'Vincular el WhatsApp del bot'
		Write-Host '    1. Toma el celular con el chip del bot y abre WhatsApp.'
		Write-Host '    2. Ve a Ajustes (o al menú de tres puntos) > Dispositivos vinculados > Vincular un dispositivo.'
		Write-Host '    3. Escanea el código QR que aparece abajo. Si caduca, aparece otro solo.'
		Write-Host '    Para cancelar presiona Ctrl+C.'
		Write-Host ''
		Vincular-WhatsApp $listo.Node
		if ($LASTEXITCODE -ne 0 -or -not (Sesion-Vinculada $listo.Env)) {
			throw 'No se completó la vinculación. Vuelve a ejecutar iniciar-bot.cmd para intentarlo de nuevo.'
		}
		Escribir-Ok 'WhatsApp del bot vinculado.'
	}

	Proteger-Ruta (Obtener-DirSesion $listo.Env)
	Proteger-Ruta $ArchivoEnv

	Escribir-Paso 'Dejando el bot en segundo plano'
	Registrar-Tarea
	$posicion = if (Test-Path $Log) { (Get-Item $Log).Length } else { 0 }
	Start-ScheduledTask -TaskName $NombreTarea
	Write-Host '    Conectando con WhatsApp...'

	$limite = (Get-Date).AddSeconds(90)
	while ((Get-Date) -lt $limite) {
		Start-Sleep -Seconds 2
		$nuevo = Leer-LogDesde $posicion
		if ($nuevo -match 'Conectado a WhatsApp') {
			Escribir-Ok 'El bot está funcionando y se encenderá solo cada vez que entres a Windows.'
			Write-Host ''
			Write-Host '    Prueba escribiendo /ping en el grupo familiar.'
			Write-Host '    Ver estado: estado-bot.cmd   |   Apagar: detener-bot.cmd'
			return
		}
		if ($nuevo -match 'No se reinicia|Error del lanzador') {
			Escribir-Aviso 'El bot no pudo arrancar. Esto dice el registro:'
			$nuevo -split "`r?`n" | Where-Object { $_ } | Select-Object -Last 10 | ForEach-Object { Formatear-Linea $_ }
			throw 'Corrige lo indicado y vuelve a ejecutar iniciar-bot.cmd.'
		}
	}

	Escribir-Aviso 'El bot sigue intentando conectarse. Revisa estado-bot.cmd en un par de minutos.'
}

function Detener {
	Escribir-Paso 'Apagando el bot'
	$tarea = Get-ScheduledTask -TaskName $NombreTarea -ErrorAction SilentlyContinue
	if ($tarea) {
		Stop-ScheduledTask -TaskName $NombreTarea -ErrorAction SilentlyContinue
		Unregister-ScheduledTask -TaskName $NombreTarea -Confirm:$false
		Escribir-Ok 'Inicio automático quitado.'
	}

	# Primero el lanzador, para que no vuelva a encender el bot.
	foreach ($proceso in Obtener-Lanzadores) { Stop-Process -Id $proceso.ProcessId -Force -ErrorAction SilentlyContinue }
	$procesos = @(Obtener-ProcesosBot)
	foreach ($proceso in $procesos) { Stop-Process -Id $proceso.ProcessId -Force -ErrorAction SilentlyContinue }

	if ($procesos.Count -gt 0) {
		Agregar-Log 'Bot detenido con detener-bot.cmd'
		Escribir-Ok 'Bot apagado. Para volver a encenderlo usa iniciar-bot.cmd.'
	} elseif (-not $tarea) {
		Escribir-Aviso 'El bot no estaba funcionando.'
	}
}

function Mostrar-Estado {
	Escribir-Paso 'Estado del bot'
	$procesos = @(Obtener-ProcesosBot)
	if ($procesos.Count -gt 0) {
		Escribir-Ok "Funcionando desde el $($procesos[0].CreationDate.ToString('dd/MM/yyyy HH:mm'))."
	} else {
		Escribir-Aviso 'No está funcionando. Enciéndelo con iniciar-bot.cmd.'
	}

	if (Get-ScheduledTask -TaskName $NombreTarea -ErrorAction SilentlyContinue) {
		Escribir-Ok 'Inicio automático al entrar a Windows: activado.'
	} else {
		Escribir-Aviso 'Inicio automático al entrar a Windows: desactivado.'
	}

	if (Sesion-Vinculada (Leer-Env)) {
		Escribir-Ok 'WhatsApp del bot: vinculado.'
	} else {
		Escribir-Aviso 'WhatsApp del bot: sin vincular (iniciar-bot.cmd muestra el QR).'
	}

	if (Test-Path $Log) {
		Escribir-Paso "Últimas líneas de $Log"
		Get-Content $Log -Tail 15 -Encoding UTF8 | ForEach-Object { Formatear-Linea $_ }
	}
}

function Ejecutar {
	Set-Location $DirBot
	$espera = 5

	while ($true) {
		if ((Test-Path $Log) -and (Get-Item $Log).Length -gt $TamanoMaximoLog) { Move-Item $Log $LogAnterior -Force }

		if (@(Obtener-ProcesosBot).Count -gt 0) {
			Agregar-Log 'Ya hay otro bot funcionando con esta sesión; esta copia no se inicia.'
			return
		}

		$node = Obtener-Node
		Agregar-Log 'Iniciando el bot'
		$inicio = Get-Date
		# cmd /s quita las comillas externas y deja la salida del bot en el registro.
		$argumentos = '/d /s /c ""{0}" --env-file-if-exists=.env "{1}" >>"{2}" 2>&1"' -f $node, $Index, $Log
		$proceso = Start-Process -FilePath $env:ComSpec -ArgumentList $argumentos -WorkingDirectory $DirBot -WindowStyle Hidden -PassThru
		$null = $proceso.Handle
		$proceso.WaitForExit()
		$codigo = $proceso.ExitCode

		if ($codigo -eq 0 -or $codigo -eq 1) {
			Agregar-Log "El bot terminó con código $codigo. No se reinicia: revisa el mensaje anterior y vuelve a ejecutar iniciar-bot.cmd."
			return
		}

		$espera = if (((Get-Date) - $inicio).TotalMinutes -ge 10) { 10 } else { [Math]::Min($espera * 2, 300) }
		Agregar-Log "El bot terminó por un error (código $codigo). Se reinicia en $espera segundos."
		Start-Sleep -Seconds $espera
	}
}

try {
	switch ($Accion) {
		'iniciar' { Iniciar }
		'detener' { Detener }
		'estado' { Mostrar-Estado }
		'ejecutar' { Ejecutar }
	}
} catch {
	if ($Accion -eq 'ejecutar') {
		Agregar-Log "Error del lanzador: $($_.Exception.Message)"
	} else {
		Write-Host ''
		Write-Host $_.Exception.Message -ForegroundColor Red
	}
	exit 1
}
