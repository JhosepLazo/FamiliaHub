<#
.SYNOPSIS
Publica en Supabase los cambios del servidor y reinicia el bot de WhatsApp.

.DESCRIPTION
En orden: prepara la CLI de Supabase, revisa la sesión, aplica las migraciones que falten (con
confirmación), publica las funciones bot-whatsapp y recibos-digitales, y reinicia el bot para que use
su versión nueva. La app web no necesita esto: Vercel la publica sola al subir el código.

Se puede ejecutar cuantas veces quieras: si no hay nada nuevo, no cambia nada.
#>
param(
	[string]$ProyectoRef = 'dqddeokbxzbmlbsltige'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$VersionCli = '2.119.0'
$Sha256Cli = 'b16827fcad9260bb31ae4bb316962ac897a677966fca2b0503c7399356969231'
$DirRepo = Split-Path -Parent $PSScriptRoot
$ScriptBot = Join-Path $DirRepo 'bot-whatsapp\scripts\bot.ps1'
$Funciones = @('bot-whatsapp', 'recibos-digitales')
$Utf8 = New-Object Text.UTF8Encoding($false)
$TotalPasos = 5
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

# Igual que en bot-whatsapp\scripts\configurar-supabase.ps1: los avisos de la CLI en stderr no deben
# detener el script, así que se decide con $LASTEXITCODE.
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

function Ejecutar-Bot([string]$Accion) {
	$ErrorActionPreference = 'Continue'
	# Su salida va a la pantalla; la función solo devuelve si terminó bien.
	& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptBot -Accion $Accion | Out-Host
	$LASTEXITCODE -eq 0
}

Push-Location $DirRepo
try {
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
	$enlazado = Join-Path $DirRepo 'supabase\.temp\project-ref'
	if (-not (Test-Path $enlazado) -or [IO.File]::ReadAllText($enlazado).Trim() -ne $ProyectoRef) {
		Write-Host '    Si la CLI pide la contraseña de la base de datos, presiona Enter para usar el acceso temporal.'
		Supabase link --project-ref $ProyectoRef
	}
	Escribir-Ok "Proyecto $ProyectoRef enlazado"

	Escribir-Paso 'Migraciones de la base de datos'
	Write-Host '    Estas son las migraciones que faltan en tu base:'
	Supabase db push --linked --dry-run
	Write-Host ''
	Write-Host '    Ahora se aplican. Confirma con Y cuando te lo pregunte.'
	Supabase db push --linked
	Escribir-Ok 'Base de datos al día'

	Escribir-Paso 'Funciones del servidor'
	foreach ($funcion in $Funciones) {
		Supabase functions deploy $funcion --use-api
		Escribir-Ok "$funcion publicada"
	}

	Escribir-Paso 'Reiniciar el bot de WhatsApp'
	if (-not (Test-Path (Join-Path $DirRepo 'bot-whatsapp\.env'))) {
		Escribir-Aviso 'El bot no está configurado en esta PC; se omite.'
	} elseif ((Ejecutar-Bot 'detener') -and (Ejecutar-Bot 'iniciar')) {
		Escribir-Ok 'El bot ya usa su versión nueva'
	} else {
		Escribir-Aviso 'No pude reiniciar el bot. Ejecuta bot-whatsapp\iniciar-bot.cmd.'
	}

	Write-Host ''
	Write-Host 'Listo. Todo quedó publicado.' -ForegroundColor Green
	Write-Host 'Prueba en el grupo de WhatsApp mencionando al bot: "¿cuánto debo?" o escribe /ayuda.'
} catch {
	Write-Host ''
	Write-Host $_.Exception.Message -ForegroundColor Red
	exit 1
} finally {
	Pop-Location
}
