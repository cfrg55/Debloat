<#
.SYNOPSIS
    Windows 10/11 Optimizer & Debloater GUI v6.0 - Remote Ready
.DESCRIPTION
    Herramienta completa para optimizar Windows 10/11 (22H2-24H2)
    Compatible con ejecucion remota via iwr | iex
.NOTES
    Compatible: Windows 10 20H2+, Windows 11 22H2/23H2/24H2
#>

#region [INICIALIZACION - VERSION REMOTA]
$ErrorActionPreference = 'Continue'
$global:ScriptVersion = "6.0-Remote"
$global:CurrentJob = $null
$global:RepairRunning = $false
$global:RepairTimer = $null
$global:InstallRunning = $false

# VERIFICAR Y SOLICITAR ELEVACION (METODO COMPATIBLE CON EJECUCION REMOTA)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Solicitando privilegios de administrador..." -ForegroundColor Yellow
    
    # Guardar el script temporalmente (porque en ejecucion remota no hay archivo)
    $tempScript = [System.IO.Path]::GetTempFileName() + ".ps1"
    
    # Obtener el contenido del script actual (desde la ejecucion remota)
    $currentScript = Get-Content -Path $PSCommandPath -ErrorAction SilentlyContinue
    if (-not $currentScript) {
        # Si no podemos obtener la ruta, usamos el script que está en memoria
        $myInvocation = $MyInvocation.MyCommand.ScriptBlock
        if ($myInvocation) {
            $currentScript = $myInvocation.ToString()
        }
    }
    
    if ($currentScript) {
        # Guardar script temporal
        [System.IO.File]::WriteAllText($tempScript, $currentScript, [System.Text.Encoding]::UTF8)
        
        # Ejecutar con elevacion
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$tempScript`""
        $process = Start-Process -FilePath "PowerShell.exe" -ArgumentList $arguments -Verb RunAs -PassThru
        $process.WaitForExit()
        
        # Limpiar archivo temporal
        Start-Sleep -Seconds 2
        Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "No se pudo guardar el script temporal. Ejecuta manualmente como administrador." -ForegroundColor Red
        Read-Host "Presiona Enter para salir"
    }
    exit
}

Write-Host "Ejecutando con privilegios de administrador..." -ForegroundColor Green

# Detectar version de Windows
$global:WindowsVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ProductName
$global:WindowsBuild = [Environment]::OSVersion.Version.Build
$global:IsWindows11 = $global:WindowsBuild -ge 22000
$global:Is24H2 = $global:WindowsBuild -ge 26100

# Verificar Winget
$global:WingetAvailable = $false
try {
    $wingetPath = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetPath) { $global:WingetAvailable = $true }
} catch { $global:WingetAvailable = $false }

# Crear directorio de logs y descargas
$global:LogDir = "C:\Temp\WindowsOptimizer"
$global:DownloadDir = "C:\Temp\WindowsOptimizer\Downloads"
If (!(Test-Path $global:LogDir)) { New-Item -Path $global:LogDir -ItemType Directory -Force | Out-Null }
If (!(Test-Path $global:DownloadDir)) { New-Item -Path $global:DownloadDir -ItemType Directory -Force | Out-Null }

# Limpiar log anterior
$global:LogFile = "$global:LogDir\optimizer_log.txt"
if (Test-Path $global:LogFile) { Remove-Item $global:LogFile -Force }

# Funcion para escribir log
function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [$Type] $Message"
    Add-Content -Path $global:LogFile -Value $logEntry
    Write-Host $logEntry
}
#endregion

# [A PARTIR DE AQUÍ, EL RESTO DEL SCRIPT ES EXACTAMENTE IGUAL AL QUE YA FUNCIONA]
# [INCLUYE TODAS LAS FUNCIONES: Clear-CurrentUserTemp, Remove-AllBloatware, etc.]
# [Y LA INTERFAZ GRÁFICA COMPLETA]
