<#
.SYNOPSIS
Activa los recibos digitales automáticos de FamiliaHub.

.DESCRIPTION
En orden: prepara la CLI de Supabase, revisa la sesión, aplica la migración de recibos digitales, guarda la
clave que comparten Gmail y FamiliaHub, publica la función recibos-digitales, la comprueba y deja listo el
script de Gmail (copiado al portapapeles) para pegarlo en https://script.new.

Se puede ejecutar de nuevo sin problema: reutiliza la clave guardada en esta PC.
#>
param(
	[string]$ProyectoRef = 'dqddeokbxzbmlbsltige'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$VersionCli = '2.119.0'
$Sha256Cli = 'b16827fcad9260bb31ae4bb316962ac897a677966fca2b0503c7399356969231'
$DirRepo = Split-Path -Parent $PSScriptRoot
$ArchivoScript = Join-Path $PSScriptRoot 'RecibosDigitales.gs'
# Solo en esta PC (no van al repositorio): la clave y el script ya completado con ella.
$DirLocal = Join-Path $env:LOCALAPPDATA 'FamiliaHub'
$ArchivoSecreto = Join-Path $DirLocal 'recibos-secreto.txt'
$ArchivoScriptListo = Join-Path $DirLocal 'RecibosDigitales-listo.gs'
$UrlFuncion = "https://$ProyectoRef.supabase.co/functions/v1/recibos-digitales"
$Utf8 = New-Object Text.UTF8Encoding($false)
$TotalPasos = 7
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

function Solo-MiUsuario([string]$Ruta) {
	$usuario = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
	& icacls.exe $Ruta /inheritance:r /grant:r "*${usuario}:F" '*S-1-5-18:F' | Out-Null
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

function Obtener-Secreto {
	if (Test-Path $ArchivoSecreto) {
		$guardado = [IO.File]::ReadAllText($ArchivoSecreto).Trim()
		if ($guardado -match '^[0-9a-f]{64}$') {
			Escribir-Ok 'Se reutiliza la clave guardada en esta PC'
			return $guardado
		}
	}
	$bytes = New-Object byte[] 32
	$generador = [Security.Cryptography.RandomNumberGenerator]::Create()
	try { $generador.GetBytes($bytes) } finally { $generador.Dispose() }
	$secreto = -join ($bytes | ForEach-Object { $_.ToString('x2') })
	New-Item -ItemType Directory -Force $DirLocal | Out-Null
	[IO.File]::WriteAllText($ArchivoSecreto, $secreto, $Utf8)
	Solo-MiUsuario $ArchivoSecreto
	Escribir-Ok 'Clave nueva generada (solo tu usuario puede leerla)'
	$secreto
}

function Llamar-Funcion([string]$Secreto) {
	$cabeceras = @{}
	if ($Secreto) { $cabeceras['x-recibos-secret'] = $Secreto }
	try {
		$respuesta = Invoke-WebRequest -Method Post -Uri $UrlFuncion -Headers $cabeceras -ContentType 'application/json' `
			-Body '{"accion":"ping"}' -UseBasicParsing -TimeoutSec 30
		@{ Estado = [int]$respuesta.StatusCode; Json = ($Utf8.GetString($respuesta.RawContentStream.ToArray()) | ConvertFrom-Json) }
	} catch [Net.WebException] {
		if (-not $_.Exception.Response) { throw }
		@{ Estado = [int]$_.Exception.Response.StatusCode; Json = $null }
	}
}

Push-Location $DirRepo
try {
	if (-not (Test-Path $ArchivoScript)) { throw "No encontré $ArchivoScript." }

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

	Escribir-Paso 'Migración de recibos digitales'
	Write-Host '    Estas son las migraciones que faltan en tu base (debería aparecer 20261020200000_recibos_digitales.sql):'
	Supabase db push --linked --dry-run
	Write-Host ''
	Write-Host '    Ahora se aplican. Confirma con Y cuando te lo pregunte.'
	Supabase db push --linked
	Escribir-Ok 'Base de datos al día'

	Escribir-Paso 'Clave entre Gmail y FamiliaHub'
	$secreto = Obtener-Secreto
	$temporal = Join-Path $env:TEMP ('familiahub-recibos-{0}.env' -f [guid]::NewGuid())
	try {
		[IO.File]::WriteAllLines($temporal, [string[]]@("FAMILIAHUB_RECIBOS_SECRET=$secreto"), $Utf8)
		Supabase secrets set --env-file $temporal
	} finally {
		Remove-Item $temporal -Force -ErrorAction SilentlyContinue
	}
	Escribir-Ok 'Clave guardada en Supabase: FAMILIAHUB_RECIBOS_SECRET'

	Escribir-Paso 'Publicar la función recibos-digitales'
	Supabase functions deploy recibos-digitales --use-api
	Escribir-Ok 'Función publicada'

	Escribir-Paso 'Comprobar la función'
	$sinSecreto = $null
	$conSecreto = $null
	for ($intento = 1; $intento -le 4; $intento++) {
		$sinSecreto = Llamar-Funcion $null
		$conSecreto = Llamar-Funcion $secreto
		if ($sinSecreto.Estado -eq 401 -and $conSecreto.Estado -eq 200) { break }
		Start-Sleep -Seconds 5
	}
	if ($sinSecreto.Estado -ne 401) { throw "La función respondió $($sinSecreto.Estado) sin la clave; esperaba 401." }
	if ($conSecreto.Estado -ne 200 -or $conSecreto.Json.ok -ne $true) {
		throw "La función respondió $($conSecreto.Estado) con la clave. Revisa Supabase > Edge Functions > recibos-digitales > Logs."
	}
	Escribir-Ok 'Responde bien: rechaza sin la clave y contesta con ella'

	Escribir-Paso 'Script de Gmail'
	$codigo = [IO.File]::ReadAllText($ArchivoScript, $Utf8).Replace('__FAMILIAHUB_URL__', $UrlFuncion).Replace('__FAMILIAHUB_SECRETO__', $secreto)
	New-Item -ItemType Directory -Force $DirLocal | Out-Null
	[IO.File]::WriteAllText($ArchivoScriptListo, $codigo, $Utf8)
	Solo-MiUsuario $ArchivoScriptListo
	Set-Clipboard -Value $codigo
	Escribir-Ok 'Script completado con la dirección y la clave, y copiado al portapapeles'
	Write-Host "    (Si se te borra el portapapeles, está en $ArchivoScriptListo)"

	Write-Host ''
	Write-Host 'FamiliaHub ya puede recibir los recibos digitales.' -ForegroundColor Green
	Write-Host ''
	Write-Host 'Falta instalar el script en el Gmail donde llegan los recibos (5 minutos):' -ForegroundColor Cyan
	Write-Host '  1. Se abrirá https://script.new. Entra con ESE Gmail.'
	Write-Host '  2. Borra lo que aparece, pega con Ctrl+V y guarda con Ctrl+S (ponle de nombre "FamiliaHub Recibos").'
	Write-Host '  3. Arriba, en la lista de funciones, elige "instalar" y pulsa Ejecutar.'
	Write-Host '  4. Google pedirá permisos: Revisar permisos > tu cuenta > "Configuración avanzada" >'
	Write-Host '     "Ir a FamiliaHub Recibos (no seguro)" > Permitir. Sale ese aviso porque el script es tuyo'
	Write-Host '     y no pasó por la revisión de Google; solo lo usa tu cuenta.'
	Write-Host '  5. En el registro debe salir "Conectado con FamiliaHub". Desde ahí revisa tu correo cada hora.'
	Write-Host ''
	Write-Host 'Si aún no recibes los recibos por correo, afíliate al recibo digital con ese mismo Gmail:' -ForegroundColor Cyan
	Write-Host '  SEDAPAL      https://www.gob.pe/12767-afiliarse-al-recibo-digital-de-sedapal'
	Write-Host '  Luz del Sur  https://www.luzdelsur.pe/es/ReciboDigital'
	Write-Host '  Cálidda      https://www.calidda.com.pe/recibo-digital'
	Write-Host ''
	Write-Host 'Más detalles en recibos-digitales\README.md.'
	if ((Read-Host 'Presiona Enter para abrir https://script.new (o escribe n para no abrirlo)') -notmatch '^[nN]') {
		Start-Process 'https://script.new'
	}
} catch {
	Write-Host ''
	Write-Host $_.Exception.Message -ForegroundColor Red
	exit 1
} finally {
	Pop-Location
}
