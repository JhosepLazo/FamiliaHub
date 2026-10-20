<#
.SYNOPSIS
Prepara Supabase para el bot de WhatsApp de FamiliaHub.

.DESCRIPTION
En orden: descarga la CLI de Supabase (verificada con su checksum), inicia sesión, revisa que el proyecto
esté activo, lo enlaza, aplica las migraciones, guarda los secretos, publica la función bot-whatsapp,
escribe bot-whatsapp\.env, comprueba la función y regenera src\types\database.ts.

Se puede ejecutar de nuevo sin problema: reutiliza el secreto que ya esté en bot-whatsapp\.env.
#>
param(
	[string]$ProyectoRef = 'dqddeokbxzbmlbsltige'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$VersionCli = '2.119.0'
$Sha256Cli = 'b16827fcad9260bb31ae4bb316962ac897a677966fca2b0503c7399356969231'
# Commit del patch anterior del asistente (rama fase-12-whatsapp, 9 de octubre de 2026).
$CommitPatchAnterior = '8d40a1ac3a9c3a48e489aeb402efc8c973ac0876'
$MigracionesPatchAnterior = @(
	'20261009120000_whatsapp_vinculos_cola.sql',
	'20261009121000_whatsapp_avisos.sql',
	'20261009122000_whatsapp_comandos.sql'
)
$DirBot = Split-Path -Parent $PSScriptRoot
$DirRepo = Split-Path -Parent $DirBot
$ArchivoEnv = Join-Path $DirBot '.env'
$ArchivoTipos = Join-Path $DirRepo 'src\types\database.ts'
# Solo en esta PC (no va al repositorio): la usan este script y lanzar.ps1.
$ArchivoAppUrl = Join-Path $env:LOCALAPPDATA 'FamiliaHub\app-url.txt'
$UrlFuncion = "https://$ProyectoRef.supabase.co/functions/v1/bot-whatsapp"
$Utf8 = New-Object Text.UTF8Encoding($false)
$TotalPasos = 8
$script:Paso = 0

try { [Console]::OutputEncoding = $Utf8 } catch { }
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Escribir-Paso([string]$Texto) {
	$script:Paso++
	Write-Host ''
	Write-Host "==> [$($script:Paso)/$TotalPasos] $Texto" -ForegroundColor Cyan
}
function Escribir-Ok([string]$Texto) { Write-Host "    $Texto" -ForegroundColor Green }
function Escribir-Aviso([string]$Texto) { Write-Host "    $Texto" -ForegroundColor Yellow }

function Texto-Plano([Security.SecureString]$Seguro) {
	$puntero = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Seguro)
	try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($puntero) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($puntero) }
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

function Obtener-Git {
	$comando = Get-Command git.exe -ErrorAction SilentlyContinue
	if ($comando) { return $comando.Source }
	foreach ($ruta in (Join-Path $env:ProgramFiles 'Git\cmd\git.exe'), (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe')) {
		if (Test-Path $ruta) { return $ruta }
	}
	$null
}

function Obtener-Cli {
	$dir = Join-Path $env:LOCALAPPDATA "FamiliaHub\supabase-cli\$VersionCli"
	$exe = Join-Path $dir 'supabase.exe'
	if (Test-Path $exe) { return $exe }

	New-Item -ItemType Directory -Force $dir | Out-Null
	$paquete = Join-Path $dir 'supabase.tar.gz'
	Write-Host "    Descargando la CLI de Supabase $VersionCli (unos 60 MB)..."
	Invoke-WebRequest -Uri "https://github.com/supabase/cli/releases/download/v$VersionCli/supabase_${VersionCli}_windows_amd64.tar.gz" -OutFile $paquete -UseBasicParsing
	if ((Get-FileHash $paquete -Algorithm SHA256).Hash -ne $Sha256Cli) {
		Remove-Item $paquete -Force
		throw 'La descarga de la CLI de Supabase no coincide con su checksum. Vuelve a intentarlo.'
	}
	& tar.exe -xzf $paquete -C $dir
	if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exe)) { throw 'No pude descomprimir la CLI de Supabase.' }
	Remove-Item $paquete -Force
	$exe
}

# Los programas externos escriben avisos en stderr (por ejemplo, que hay una CLI más nueva). Con
# ErrorActionPreference = Stop, PowerShell 5.1 los trataría como errores cuando stderr está redirigido,
# así que en estas funciones se usa Continue y se decide con $LASTEXITCODE.
function Supabase {
	$ErrorActionPreference = 'Continue'
	& $script:Cli @args
	if ($LASTEXITCODE -ne 0) { throw "Falló 'supabase $($args -join ' ')'. Revisa el mensaje de arriba." }
}

function Probar-Supabase {
	$anterior = $ErrorActionPreference
	$ErrorActionPreference = 'Continue'
	try {
		& $script:Cli @args *> $null
		$LASTEXITCODE -eq 0
	} finally {
		$ErrorActionPreference = $anterior
	}
}

function Revisar-Proyecto {
	$ErrorActionPreference = 'Continue'
	$salida = (& $script:Cli projects list -o json) -join "`n"
	try {
		$proyectos = $salida | ConvertFrom-Json -ErrorAction Stop
	} catch {
		Escribir-Aviso 'No pude leer la lista de proyectos; sigo de todas formas.'
		return
	}
	$proyecto = @($proyectos) | Where-Object { $_.ref -eq $ProyectoRef -or $_.id -eq $ProyectoRef } | Select-Object -First 1
	if (-not $proyecto) {
		throw "Tu cuenta de Supabase no tiene el proyecto $ProyectoRef. Cierra la sesión con '$script:Cli logout' y vuelve a ejecutar este archivo con la cuenta correcta."
	}
	if ($proyecto.status -and $proyecto.status -ne 'ACTIVE_HEALTHY') {
		if ($proyecto.status -match 'INACTIVE|PAUSED') {
			throw ("Tu proyecto de Supabase está pausado (Supabase pausa los proyectos gratuitos tras 7 días sin uso).`n" +
				"Abre https://supabase.com/dashboard/project/$ProyectoRef, pulsa 'Restore project', espera a que termine y vuelve a ejecutar este archivo.`n" +
				'Con el bot funcionando ya no se volverá a pausar: el bot usa la base cada pocos minutos.')
		}
		throw "Tu proyecto de Supabase está en estado $($proyecto.status). Espera a que quede activo en el panel y vuelve a ejecutar este archivo."
	}
	Escribir-Ok "Proyecto $($proyecto.name) activo"
}

# Si la base tiene aplicado el patch anterior, sus migraciones deben estar en el repositorio para que
# db push acepte el historial; 20261019115900 lo retira y 20261019120400 conserva los vínculos.
function Recuperar-PatchAnterior {
	$ErrorActionPreference = 'Continue'
	$historial = (& $script:Cli migration list --linked) -join "`n"
	if ($LASTEXITCODE -ne 0) { throw 'No pude leer el historial de migraciones de la base. Revisa la contraseña y vuelve a intentarlo.' }

	$faltan = @($MigracionesPatchAnterior | Where-Object {
		$historial.Contains($_.Substring(0, 14)) -and -not (Test-Path (Join-Path $DirRepo "supabase\migrations\$_"))
	})
	if ($faltan.Count -eq 0) { return }

	Escribir-Aviso 'Tu base ya tiene aplicado el patch anterior del asistente (9 de octubre).'
	Escribir-Aviso 'Recupero esas migraciones en el repositorio; las nuevas lo transforman y conservan los vínculos.'
	$git = Obtener-Git
	if (-not $git -or -not (Test-Path (Join-Path $DirRepo '.git'))) {
		throw 'Necesito Git para recuperar esas migraciones. Instálalo con  winget install Git.Git  y vuelve a ejecutar este archivo.'
	}
	$rutas = $faltan | ForEach-Object { "supabase/migrations/$_" }
	& $git -C $DirRepo checkout $CommitPatchAnterior -- @rutas
	if ($LASTEXITCODE -ne 0) { throw 'No pude recuperar las migraciones del patch anterior desde git.' }
	& $git -C $DirRepo commit -m 'chore: conservar las migraciones ya aplicadas del patch anterior' -- @rutas | Out-Null
	if ($LASTEXITCODE -eq 0) { Escribir-Ok 'Migraciones recuperadas en un commit. Súbelo junto con lo demás (git push).' }
}

function Generar-Tipos {
	$ErrorActionPreference = 'Continue'
	$salida = & $script:Cli gen types typescript --linked --schema public
	$tipos = (@($salida) -join "`n").Trim() + "`n"
	if ($LASTEXITCODE -ne 0 -or -not $tipos.StartsWith('export type Json')) {
		Escribir-Aviso 'No pude regenerar los tipos. No afecta al bot; puedes intentarlo después con este mismo archivo.'
		return
	}
	if ([IO.File]::ReadAllText($ArchivoTipos).Replace("`r`n", "`n") -eq $tipos) {
		Escribir-Ok 'Ya estaban al día'
		return
	}
	[IO.File]::WriteAllText($ArchivoTipos, $tipos, $Utf8)
	Escribir-Ok 'Tipos actualizados'
	$git = Obtener-Git
	if ($git -and (Test-Path (Join-Path $DirRepo '.git'))) {
		& $git -C $DirRepo commit -m 'chore: regenerar tipos de Supabase' -- src/types/database.ts | Out-Null
		if ($LASTEXITCODE -eq 0) { Escribir-Ok 'Guardados en un commit: chore: regenerar tipos de Supabase' }
	}
}

function Pedir-AppUrl {
	$guardada = if (Test-Path $ArchivoAppUrl) { [IO.File]::ReadAllText($ArchivoAppUrl).Trim() } else { '' }
	$pregunta = '    Dirección web de tu FamiliaHub (la que abres en el navegador, por ejemplo https://algo.vercel.app)'
	if ($guardada) { $pregunta += " [Enter = $guardada]" }
	while ($true) {
		$url = (Read-Host $pregunta).Trim().TrimEnd('/')
		if (-not $url) { $url = $guardada }
		if ($url -notmatch '^https://[^\s/]+') {
			Escribir-Aviso 'Debe empezar con https://'
			continue
		}
		try {
			$pagina = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20
			if ($pagina.Content -match '<title>FamiliaHub</title>') { return $url }
			Escribir-Aviso 'Esa página no parece ser FamiliaHub.'
		} catch {
			Escribir-Aviso "No pude abrir esa dirección: $($_.Exception.Message)"
		}
		if ((Read-Host '    ¿Usarla de todas formas? (s/n)') -match '^[sS]') { return $url }
	}
}

function Llamar-Funcion($Cuerpo, [string]$Secreto) {
	$cabeceras = @{}
	if ($Secreto) { $cabeceras['x-bot-secret'] = $Secreto }
	try {
		$respuesta = Invoke-WebRequest -Method Post -Uri $UrlFuncion -Headers $cabeceras -ContentType 'application/json' `
			-Body ([Text.Encoding]::UTF8.GetBytes(($Cuerpo | ConvertTo-Json -Compress))) -UseBasicParsing -TimeoutSec 30
		@{ Estado = [int]$respuesta.StatusCode; Json = ($Utf8.GetString($respuesta.RawContentStream.ToArray()) | ConvertFrom-Json) }
	} catch [Net.WebException] {
		if (-not $_.Exception.Response) { throw }
		@{ Estado = [int]$_.Exception.Response.StatusCode; Json = $null }
	}
}

Push-Location $DirRepo
try {
	if (-not (Test-Path (Join-Path $DirRepo 'supabase\migrations'))) { throw "No encontré supabase\migrations en $DirRepo." }

	Escribir-Paso 'CLI de Supabase'
	$script:Cli = Obtener-Cli
	Escribir-Ok "CLI $VersionCli lista"

	Escribir-Paso 'Sesión en Supabase'
	if (Probar-Supabase projects list) {
		Escribir-Ok 'Ya tenías la sesión iniciada'
	} else {
		Write-Host '    Se abrirá el navegador: entra con tu cuenta de Supabase y copia aquí el código que te muestre.'
		Supabase login
	}
	Revisar-Proyecto

	Escribir-Paso 'Enlazar el proyecto'
	Write-Host '    Necesito la contraseña de la base de datos de tu proyecto.'
	Write-Host '    La encuentras (o la cambias) en Supabase > Project Settings > Database > Database password.'
	$clave = Texto-Plano (Read-Host '    Contraseña' -AsSecureString)
	if (-not $clave) { throw 'La contraseña no puede quedar vacía.' }
	$env:SUPABASE_DB_PASSWORD = $clave
	Supabase link --project-ref $ProyectoRef
	Escribir-Ok "Proyecto $ProyectoRef enlazado"

	Escribir-Paso 'Migraciones de la base de datos'
	Recuperar-PatchAnterior
	Write-Host '    Estas son las migraciones que faltan en tu base:'
	Supabase db push --linked --dry-run
	Write-Host ''
	Write-Host '    Ahora se aplican. Confirma con Y cuando te lo pregunte.'
	Supabase db push --linked
	Escribir-Ok 'Base de datos al día'

	Escribir-Paso 'Secretos de la función'
	$valores = Leer-Env
	$secreto = $valores['FAMILIAHUB_BOT_SECRET']
	if ($secreto) {
		Escribir-Ok 'Se reutiliza el secreto que ya estaba en bot-whatsapp\.env'
	} else {
		$bytes = New-Object byte[] 32
		$generador = [Security.Cryptography.RandomNumberGenerator]::Create()
		try { $generador.GetBytes($bytes) } finally { $generador.Dispose() }
		$secreto = -join ($bytes | ForEach-Object { $_.ToString('x2') })
		Escribir-Ok 'Secreto nuevo generado'
	}
	$appUrl = Pedir-AppUrl
	New-Item -ItemType Directory -Force (Split-Path $ArchivoAppUrl) | Out-Null
	[IO.File]::WriteAllText($ArchivoAppUrl, $appUrl, $Utf8)
	Write-Host ''
	Write-Host '    Opcional: para que el bot responda preguntas libres (por ejemplo "@bot cuánto debo?")'
	Write-Host '    pega una clave de API de Anthropic (console.anthropic.com). Deja vacío para omitir.'
	$claveAnthropic = (Texto-Plano (Read-Host '    Clave de Anthropic' -AsSecureString)).Trim()

	$temporal = Join-Path $env:TEMP ('familiahub-secretos-{0}.env' -f [guid]::NewGuid())
	try {
		$lineas = @("FAMILIAHUB_BOT_SECRET=$secreto", "APP_URL=$appUrl")
		if ($claveAnthropic) { $lineas += "ANTHROPIC_API_KEY=$claveAnthropic" }
		[IO.File]::WriteAllLines($temporal, [string[]]$lineas, $Utf8)
		Supabase secrets set --env-file $temporal
	} finally {
		Remove-Item $temporal -Force -ErrorAction SilentlyContinue
	}
	Escribir-Ok ('Secretos guardados: FAMILIAHUB_BOT_SECRET, APP_URL' + $(if ($claveAnthropic) { ', ANTHROPIC_API_KEY' } else { '' }))

	Escribir-Paso 'Publicar la función bot-whatsapp'
	Supabase functions deploy bot-whatsapp --use-api
	Escribir-Ok 'Función publicada'

	Escribir-Paso 'Archivo .env del bot y comprobación'
	$authDir = if ($valores['AUTH_DIR']) { $valores['AUTH_DIR'] } else { 'auth' }
	$nivel = if ($valores['LOG_LEVEL']) { $valores['LOG_LEVEL'] } else { 'warn' }
	$contenido = "FAMILIAHUB_FUNCTION_URL=$UrlFuncion`nFAMILIAHUB_BOT_SECRET=$secreto`nAUTH_DIR=$authDir`nLOG_LEVEL=$nivel`n"
	[IO.File]::WriteAllText($ArchivoEnv, $contenido, $Utf8)
	$usuario = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
	& icacls.exe $ArchivoEnv /inheritance:r /grant:r "*${usuario}:F" '*S-1-5-18:F' | Out-Null
	Escribir-Ok 'bot-whatsapp\.env escrito (solo tu usuario puede leerlo)'

	# Un grupo inventado: la función debe responder que no está vinculado, sin cambiar nada en la base.
	$prueba = @{ accion = 'mensaje'; grupoId = '120363000000000000@g.us'; remitenteIds = @('0@s.whatsapp.net'); texto = '/ayuda'; mencionaBot = $false; respondeBot = $false }
	$sinSecreto = $null
	$conSecreto = $null
	for ($intento = 1; $intento -le 4; $intento++) {
		$sinSecreto = Llamar-Funcion $prueba $null
		$conSecreto = Llamar-Funcion $prueba $secreto
		if ($sinSecreto.Estado -eq 401 -and $conSecreto.Estado -eq 200) { break }
		Start-Sleep -Seconds 5
	}
	if ($sinSecreto.Estado -ne 401) { throw "La función respondió $($sinSecreto.Estado) sin secreto; esperaba 401." }
	if ($conSecreto.Estado -ne 200 -or $conSecreto.Json.grupoVinculado -ne $false -or -not $conSecreto.Json.respuesta.texto) {
		throw "La función respondió $($conSecreto.Estado) con el secreto. Revisa los registros en Supabase > Edge Functions > bot-whatsapp > Logs."
	}
	Escribir-Ok 'La función responde bien: rechaza sin secreto y contesta con el secreto'

	Escribir-Paso 'Tipos de la app (src\types\database.ts)'
	Generar-Tipos

	Write-Host ''
	Write-Host 'Supabase quedó listo.' -ForegroundColor Green
	if (-not $env:FAMILIAHUB_LANZADOR) {
		Write-Host 'Siguiente paso: sube el código a GitHub (git push) y luego ejecuta iniciar-bot.cmd.'
	}
} catch {
	Write-Host ''
	Write-Host $_.Exception.Message -ForegroundColor Red
	exit 1
} finally {
	Remove-Item Env:SUPABASE_DB_PASSWORD -ErrorAction SilentlyContinue
	Pop-Location
}
