<#
.SYNOPSIS
Lanza el bot de WhatsApp de FamiliaHub de principio a fin.

.DESCRIPTION
1. Revisa Node.js y Git (los instala con winget si faltan).
2. Comprueba que el proyecto de Supabase responda; si está pausado, abre el panel para restaurarlo y espera.
3. Configura Supabase con configurar-supabase.ps1, solo si todavía no está configurado.
4. Sube la rama a GitHub y, si lo apruebas, la publica en main (o abre el Pull Request).
5. Espera a que la app publicada tenga las pantallas de WhatsApp.
6. Enciende el bot con bot.ps1 (muestra el QR si falta vincular el WhatsApp del bot).

Se puede ejecutar de nuevo: salta lo que ya está hecho. El avance queda en logs\lanzamiento.log (sin secretos).
#>
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ProyectoRef = 'dqddeokbxzbmlbsltige'
$ClavePublica = 'sb_publishable_bv2ksC-5obhzAuXYppAuaw_2IhsdHjY'
$RepoGitHub = 'JhosepLazo/FamiliaHub'
$Rama = 'fase-12-whatsapp'
$DirBot = Split-Path -Parent $PSScriptRoot
$DirRepo = Split-Path -Parent $DirBot
$ArchivoEnv = Join-Path $DirBot '.env'
$ArchivoAppUrl = Join-Path $env:LOCALAPPDATA 'FamiliaHub\app-url.txt'
$UrlFuncion = "https://$ProyectoRef.supabase.co/functions/v1/bot-whatsapp"
$DirLogs = Join-Path $DirBot 'logs'
$LogLanzamiento = Join-Path $DirLogs 'lanzamiento.log'
$NodeMinimo = [version]'22.18.0'
$Utf8 = New-Object Text.UTF8Encoding($false)
$TotalPasos = 6
$script:Paso = 0

try { [Console]::OutputEncoding = $Utf8 } catch { }
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Registrar([string]$Texto) {
	New-Item -ItemType Directory -Force $DirLogs | Out-Null
	[IO.File]::AppendAllText($LogLanzamiento, ('[{0}] {1}{2}' -f (Get-Date -Format 'dd/MM/yyyy HH:mm:ss'), $Texto, [Environment]::NewLine), $Utf8)
}
function Escribir-Paso([string]$Texto) {
	$script:Paso++
	Write-Host ''
	Write-Host "==> [$($script:Paso)/$TotalPasos] $Texto" -ForegroundColor Cyan
	Registrar "PASO $($script:Paso) $Texto"
}
function Escribir-Ok([string]$Texto) { Write-Host "    $Texto" -ForegroundColor Green; Registrar "  ok: $Texto" }
function Escribir-Aviso([string]$Texto) { Write-Host "    $Texto" -ForegroundColor Yellow; Registrar "  aviso: $Texto" }

# Si esta ventana se abrió antes de instalar algo, su PATH no lo incluye.
function Actualizar-Path {
	$env:Path = (@([Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User')) | Where-Object { $_ }) -join ';'
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

function Version-Node {
	$comando = Get-Command node.exe -ErrorAction SilentlyContinue
	if (-not $comando) { return $null }
	[version]((& $comando.Source -p 'process.versions.node').Trim())
}

function Asegurar-Herramientas {
	$ErrorActionPreference = 'Continue'
	Actualizar-Path

	$version = Version-Node
	if (-not $version -or $version -lt $NodeMinimo) {
		Escribir-Aviso 'Instalo Node.js con winget. Acepta el aviso de Windows si aparece.'
		$verbo = if ($version) { 'upgrade' } else { 'install' }
		& winget.exe $verbo --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements
		Actualizar-Path
		$version = Version-Node
		if (-not $version -or $version -lt $NodeMinimo) { throw 'No se pudo instalar Node.js 22.18 o superior. Instálalo con:  winget install OpenJS.NodeJS.LTS' }
	}
	Escribir-Ok "Node.js $version"

	if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
		Escribir-Aviso 'Instalo Git con winget. Acepta el aviso de Windows si aparece.'
		& winget.exe install --id Git.Git -e --accept-package-agreements --accept-source-agreements
		Actualizar-Path
		if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) { throw 'No se pudo instalar Git. Instálalo con:  winget install Git.Git' }
	}
	Escribir-Ok ((& git.exe --version) -join ' ')
}

# El proyecto responde si su API contesta algo (aunque sea "sin permiso"); si está pausado, su dirección no existe.
function Proyecto-Responde {
	try {
		$null = Invoke-WebRequest -Uri "https://$ProyectoRef.supabase.co/rest/v1/" -Headers @{ apikey = $ClavePublica } -UseBasicParsing -TimeoutSec 20
		return $true
	} catch [Net.WebException] {
		$respuesta = $_.Exception.Response
		return [bool]($respuesta -and [int]$respuesta.StatusCode -lt 500)
	} catch {
		return $false
	}
}

function Asegurar-Proyecto {
	if (Proyecto-Responde) {
		Escribir-Ok 'El proyecto de Supabase está activo'
		return
	}

	Escribir-Aviso 'Tu proyecto de Supabase está pausado (Supabase pausa los proyectos gratuitos tras 7 días sin uso).'
	Write-Host '    Abro el panel en el navegador: entra con tu cuenta y pulsa "Restore project".'
	Write-Host '    Tarda unos minutos. Esta ventana sigue sola cuando el proyecto vuelva.'
	Start-Process "https://supabase.com/dashboard/project/$ProyectoRef"
	Registrar '  esperando que restaures el proyecto'

	$limite = (Get-Date).AddMinutes(30)
	while ((Get-Date) -lt $limite) {
		Start-Sleep -Seconds 15
		# Windows recuerda unos minutos que la dirección "no existía"; se limpia para notar el cambio.
		try { Clear-DnsClientCache -ErrorAction Stop } catch { & ipconfig.exe /flushdns | Out-Null }
		if (Proyecto-Responde) {
			Escribir-Ok 'El proyecto de Supabase volvió y está activo'
			return
		}
		Write-Host '    Todavía no responde; vuelvo a revisar en 15 segundos...'
	}
	throw 'El proyecto sigue sin responder después de 30 minutos. Revisa el panel de Supabase y vuelve a ejecutar lanzar-bot.cmd.'
}

function Llamar-Funcion($Cuerpo, [string]$Secreto) {
	$cabeceras = @{}
	if ($Secreto) { $cabeceras['x-bot-secret'] = $Secreto }
	try {
		$respuesta = Invoke-WebRequest -Method Post -Uri $UrlFuncion -Headers $cabeceras -ContentType 'application/json' `
			-Body ([Text.Encoding]::UTF8.GetBytes(($Cuerpo | ConvertTo-Json -Compress))) -UseBasicParsing -TimeoutSec 30
		@{ Estado = [int]$respuesta.StatusCode; Json = ($Utf8.GetString($respuesta.RawContentStream.ToArray()) | ConvertFrom-Json) }
	} catch [Net.WebException] {
		if (-not $_.Exception.Response) { return @{ Estado = 0; Json = $null } }
		@{ Estado = [int]$_.Exception.Response.StatusCode; Json = $null }
	}
}

# Configurado = hay .env con secreto y la función publicada lo acepta (y rechaza a quien no lo tiene).
function Supabase-Configurado {
	$secreto = (Leer-Env)['FAMILIAHUB_BOT_SECRET']
	if (-not $secreto) { return $false }
	$prueba = @{ accion = 'mensaje'; grupoId = '120363000000000000@g.us'; remitenteIds = @('0@s.whatsapp.net'); texto = '/ayuda'; mencionaBot = $false; respondeBot = $false }
	$sinSecreto = Llamar-Funcion $prueba $null
	$conSecreto = Llamar-Funcion $prueba $secreto
	$sinSecreto.Estado -eq 401 -and $conSecreto.Estado -eq 200 -and $conSecreto.Json.respuesta.texto
}

function Asegurar-Supabase {
	if (Supabase-Configurado) {
		Escribir-Ok 'Supabase ya estaba configurado y la función del bot responde bien'
		Write-Host '    (Si quieres cambiar el secreto, la dirección de la app o la clave de Anthropic, usa configurar-supabase.cmd.)'
		return
	}
	$ErrorActionPreference = 'Continue'
	$env:FAMILIAHUB_LANZADOR = '1'
	& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'configurar-supabase.ps1')
	$codigo = $LASTEXITCODE
	Remove-Item Env:FAMILIAHUB_LANZADOR -ErrorAction SilentlyContinue
	if ($codigo -ne 0) { throw 'La configuración de Supabase no terminó. Corrige lo indicado arriba y vuelve a ejecutar lanzar-bot.cmd.' }
	Escribir-Ok 'Supabase configurado'
}

function En-Main([string]$Git) {
	& $Git merge-base --is-ancestor HEAD origin/main
	if ($LASTEXITCODE -eq 0) { return $true }
	# Un Pull Request unido con "squash" no conserva los commits, pero sí los archivos.
	& $Git diff --quiet HEAD origin/main -- src/features/whatsapp supabase/migrations supabase/functions/bot-whatsapp
	$LASTEXITCODE -eq 0
}

function Publicar-Codigo {
	$ErrorActionPreference = 'Continue'
	$git = (Get-Command git.exe).Source
	Push-Location $DirRepo
	try {
		if (& $git status --porcelain) { Escribir-Aviso 'Hay cambios sin guardar en un commit; se suben solo los commits.' }
		& $git fetch -q origin
		if ($LASTEXITCODE -ne 0) { throw 'No pude conectar con GitHub. Revisa tu conexión a internet.' }

		if (En-Main $git) {
			Escribir-Ok 'main ya tiene los cambios de WhatsApp'
			return
		}

		Write-Host '    Subo la rama a GitHub. La primera vez se abre el navegador para que inicies sesión en GitHub.'
		& $git push -u origin "HEAD:refs/heads/$Rama"
		if ($LASTEXITCODE -ne 0) { throw 'No se pudo subir la rama a GitHub. Revisa el mensaje de arriba.' }
		Escribir-Ok "Rama $Rama subida"

		Write-Host ''
		Write-Host '    Para que la app muestre las pantallas de WhatsApp, estos cambios tienen que llegar a main.'
		Write-Host '    GitHub Actions publica la app sola cuando main cambia.'
		$respuesta = Read-Host '    ¿Los publico en main ahora? (s = sí / n = prefiero revisarlos en un Pull Request)'
		if ($respuesta -match '^[sS]') {
			& $git push origin "HEAD:refs/heads/main"
			if ($LASTEXITCODE -eq 0) {
				Escribir-Ok 'Cambios publicados en main'
				return
			}
			Escribir-Aviso 'GitHub no aceptó subir directo a main (puede estar protegida). Te abro el Pull Request.'
		}

		Start-Process "https://github.com/$RepoGitHub/compare/main...$($Rama)?expand=1"
		Registrar '  esperando que unas el Pull Request'
		while ($true) {
			Read-Host '    Crea y une el Pull Request en GitHub (botón "Merge"). Cuando termines, presiona Enter aquí' | Out-Null
			& $git fetch -q origin
			if (En-Main $git) {
				Escribir-Ok 'Pull Request unido a main'
				return
			}
			Escribir-Aviso 'Todavía no veo los cambios en main.'
		}
	} finally {
		Pop-Location
	}
}

function Obtener-AppUrl {
	if (Test-Path $ArchivoAppUrl) { return [IO.File]::ReadAllText($ArchivoAppUrl).Trim() }
	while ($true) {
		$url = (Read-Host '    Dirección web de tu FamiliaHub (por ejemplo https://algo.vercel.app)').Trim().TrimEnd('/')
		if ($url -match '^https://[^\s/]+') {
			New-Item -ItemType Directory -Force (Split-Path $ArchivoAppUrl) | Out-Null
			[IO.File]::WriteAllText($ArchivoAppUrl, $url, $Utf8)
			return $url
		}
		Escribir-Aviso 'Debe empezar con https://'
	}
}

function App-TieneWhatsApp([string]$AppUrl) {
	try {
		$html = $Utf8.GetString((Invoke-WebRequest -Uri "$AppUrl/?v=$([guid]::NewGuid().ToString('N'))" -UseBasicParsing -TimeoutSec 20).RawContentStream.ToArray())
		$scripts = [regex]::Matches($html, '(?:src|href)="(/assets/[^"]+\.js)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
		foreach ($ruta in $scripts) {
			$js = $Utf8.GetString((Invoke-WebRequest -Uri "$AppUrl$ruta" -UseBasicParsing -TimeoutSec 30).RawContentStream.ToArray())
			if ($js.Contains('Asistente de WhatsApp')) { return $true }
		}
	} catch {
		# Mientras se publica la app puede fallar; se vuelve a intentar.
	}
	$false
}

function Esperar-App([string]$AppUrl) {
	if (App-TieneWhatsApp $AppUrl) {
		Escribir-Ok "La app ($AppUrl) ya tiene las pantallas de WhatsApp"
		return
	}
	Write-Host '    GitHub Actions compila la app y Vercel la publica; suele tardar de 2 a 5 minutos...'
	$limite = (Get-Date).AddMinutes(15)
	while ((Get-Date) -lt $limite) {
		Start-Sleep -Seconds 20
		if (App-TieneWhatsApp $AppUrl) {
			Escribir-Ok "La app ($AppUrl) ya tiene las pantallas de WhatsApp"
			return
		}
	}
	Escribir-Aviso "La app todavía no muestra las pantallas nuevas. Revisa https://github.com/$RepoGitHub/actions. El bot se enciende igual."
}

function Encender-Bot {
	$ErrorActionPreference = 'Continue'
	& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'bot.ps1') -Accion iniciar
	if ($LASTEXITCODE -ne 0) { throw 'El bot no pudo encenderse. Corrige lo indicado arriba y vuelve a ejecutar lanzar-bot.cmd.' }
	Escribir-Ok 'Bot encendido'
}

try {
	Registrar '=== Lanzamiento iniciado'
	Write-Host 'Lanzamiento del bot de WhatsApp de FamiliaHub. Ten a mano el celular con el chip del bot,' -ForegroundColor White
	Write-Host 'la contraseña de la base de datos de Supabase y la dirección web de tu FamiliaHub.' -ForegroundColor White

	Escribir-Paso 'Herramientas (Node.js y Git)'
	Asegurar-Herramientas

	Escribir-Paso 'Proyecto de Supabase'
	Asegurar-Proyecto

	Escribir-Paso 'Base de datos, secretos y función del bot'
	Asegurar-Supabase

	Escribir-Paso 'Código en GitHub'
	Publicar-Codigo

	Escribir-Paso 'App publicada'
	$appUrl = Obtener-AppUrl
	Esperar-App $appUrl

	Escribir-Paso 'Bot de WhatsApp'
	Encender-Bot

	Write-Host ''
	Write-Host '¡Listo! Falta lo que se hace en WhatsApp y en la app:' -ForegroundColor Green
	Write-Host '  1. Agrega el número del chip del bot al grupo familiar y escribe /ping (responde "pong").'
	Write-Host '  2. En FamiliaHub (como administrador): Configuración > Asistente de WhatsApp > Vincular grupo.'
	Write-Host '     Escribe en el grupo el comando que te muestra: /vincular-grupo CÓDIGO'
	Write-Host '  3. Cada integrante: Perfil > WhatsApp > Vincular mi WhatsApp, y escribe en el grupo /vincular CÓDIGO'
	Write-Host '  4. Prueba /ayuda y /deuda.'
	Write-Host ''
	Write-Host 'Abro la configuración de FamiliaHub en el navegador.'
	Start-Process "$appUrl/configuracion"
	Registrar '=== LANZAMIENTO TERMINADO'
} catch {
	Write-Host ''
	Write-Host $_.Exception.Message -ForegroundColor Red
	Registrar "=== FALLO en el paso $($script:Paso): $($_.Exception.Message)"
	exit 1
}
