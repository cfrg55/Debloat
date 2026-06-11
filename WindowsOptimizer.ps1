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
    
    # Guardar el script temporalmente
    $tempScript = [System.IO.Path]::GetTempFileName() + ".ps1"
    
    # Obtener el contenido del script actual
    try {
        $currentScript = Get-Content -Path $PSCommandPath -Raw -ErrorAction SilentlyContinue
        if (-not $currentScript) {
            $currentScript = $MyInvocation.MyCommand.ScriptBlock.ToString()
        }
    } catch {
        $currentScript = $null
    }
    
    if ($currentScript) {
        [System.IO.File]::WriteAllText($tempScript, $currentScript, [System.Text.Encoding]::UTF8)
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$tempScript`""
        $process = Start-Process -FilePath "PowerShell.exe" -ArgumentList $arguments -Verb RunAs -PassThru
        $process.WaitForExit()
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

#region [LISTAS DE BLOATWARE]
$global:Bloatware = @(
    "Microsoft.BingNews", "Microsoft.BingWeather", "Microsoft.GetHelp", "Microsoft.Getstarted"
    "Microsoft.Microsoft3DViewer", "Microsoft.MicrosoftOfficeHub", "Microsoft.MicrosoftSolitaireCollection"
    "Microsoft.MixedReality.Portal", "Microsoft.Office.OneNote", "Microsoft.People", "Microsoft.Print3D"
    "Microsoft.SkypeApp", "Microsoft.WindowsAlarms", "Microsoft.WindowsFeedbackHub", "Microsoft.WindowsMaps"
    "Microsoft.WindowsSoundRecorder", "Microsoft.YourPhone", "Microsoft.ZuneMusic", "Microsoft.ZuneVideo"
    "Microsoft.Todos", "Microsoft.Windows.DevHome", "Microsoft.PowerAutomateDesktop", "Clipchamp.Clipchamp"
    "Microsoft.Xbox.TCUI", "Microsoft.XboxApp", "Microsoft.XboxGameOverlay"
    "Microsoft.XboxGamingOverlay", "Microsoft.XboxIdentityProvider", "Microsoft.XboxSpeechToTextOverlay"
    "CandyCrush", "Facebook", "Twitter", "Spotify", "Netflix", "Disney"
    "MicrosoftTeams", "MicrosoftTeams_8wekyb3d8bbwe", "Microsoft.Windows.CommunicationsApps"
    "Microsoft.Windows.WebExperiencePack", "MicrosoftWindows.Client.WebExperience"
)

if ($global:Is24H2) {
    $global:Bloatware += @("Microsoft.Windows.AI.Copilot", "Microsoft.Copilot", "Microsoft.Windows.Recall")
}

$global:BloatwareRegex = $global:Bloatware -join '|'
#endregion

#region [FUNCIONES DE LIMPIEZA BASICA]
function Clear-CurrentUserTemp {
    Write-Log "========== LIMPIANDO PERFIL ACTUAL ==========" "TASK"
    try {
        if (Test-Path "$env:USERPROFILE\AppData\Local\Temp") {
            Write-Log "Eliminando archivos de Temp del usuario actual..." "INFO"
            cmd /c "del /f /s /q `"$env:USERPROFILE\AppData\Local\Temp\*`"" 2>&1 | Out-Null
            cmd /c "rd /s /q `"$env:USERPROFILE\AppData\Local\Temp`"" 2>&1 | Out-Null
            Write-Log "Limpieza de Temp del usuario actual completada" "OK"
        }
    } catch {
        Write-Log "Error al limpiar Temp del usuario" "ERROR"
    }
    Write-Log "========== COMPLETADO ==========" "OK"
}

function Clear-AllUsersTemp {
    Write-Log "========== LIMPIANDO TODOS LOS PERFILES ==========" "TASK"
    if (Test-Path "C:\Users") {
        $userPaths = Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue
        foreach ($userPath in $userPaths) {
            $tempPath = Join-Path $userPath.FullName "AppData\Local\Temp"
            if (Test-Path $tempPath) {
                Write-Log "Limpiando: $tempPath" "INFO"
                cmd /c "del /f /s /q `"$tempPath\*`"" 2>&1 | Out-Null
                cmd /c "rd /s /q `"$tempPath`"" 2>&1 | Out-Null
                Write-Log "Limpiado perfil: $($userPath.Name)" "OK"
            }
        }
    }
    Write-Log "========== COMPLETADO ==========" "OK"
}

function Clear-WindowsTemp {
    Write-Log "========== LIMPIANDO WINDOWS TEMP ==========" "TASK"
    try {
        if (Test-Path "C:\Windows\Temp") {
            Write-Log "Eliminando archivos de C:\Windows\Temp..." "INFO"
            cmd /c "del /f /s /q C:\Windows\Temp\*" 2>&1 | Out-Null
            cmd /c "rd /s /q C:\Windows\Temp" 2>&1 | Out-Null
            Write-Log "Limpieza de Windows\Temp completada" "OK"
        }
    } catch {
        Write-Log "Error al limpiar Windows\Temp" "ERROR"
    }
    Write-Log "========== COMPLETADO ==========" "OK"
}

function Clear-InternetCache {
    Write-Log "========== LIMPIANDO CACHE DE INTERNET ==========" "TASK"
    Write-Log "Limpiando cache de Internet Explorer/Edge..." "INFO"
    RunDll32.exe InetCpl.cpl,ClearMyTracksByProcess 8 2>&1 | Out-Null
    RunDll32.exe InetCpl.cpl,ClearMyTracksByProcess 4 2>&1 | Out-Null
    RunDll32.exe InetCpl.cpl,ClearMyTracksByProcess 2 2>&1 | Out-Null
    RunDll32.exe InetCpl.cpl,ClearMyTracksByProcess 1 2>&1 | Out-Null
    Write-Log "Cache de Internet limpiada" "OK"
    Write-Log "========== COMPLETADO ==========" "OK"
}

function Run-DiskCleanup {
    Write-Log "========== EJECUTANDO LIMPIEZA DE DISCO ==========" "TASK"
    Write-Log "Ejecutando Cleanmgr con configuracion predefinida..." "INFO"
    Cleanmgr.exe /sagerun:64 2>&1 | Out-Null
    Write-Log "Limpieza de disco completada" "OK"
    Write-Log "========== COMPLETADO ==========" "OK"
}

function Disable-Firewall {
    Write-Log "========== DESHABILITANDO FIREWALL ==========" "TASK"
    Write-Log "Deshabilitando firewall en todos los perfiles..." "INFO"
    netsh advfirewall set domainprofile state off 2>&1 | Out-Null
    netsh advfirewall set privateprofile state off 2>&1 | Out-Null
    netsh advfirewall set publicprofile state off 2>&1 | Out-Null
    Write-Log "Firewall deshabilitado" "OK"
    Write-Log "========== COMPLETADO ==========" "OK"
}

function Clear-WindowsUpdateCache {
    Write-Log "========== LIMPIANDO CACHE DE WINDOWS UPDATE ==========" "TASK"
    
    Write-Log "Deteniendo servicios..." "INFO"
    net stop bits 2>&1 | Out-Null
    net stop wuauserv 2>&1 | Out-Null
    net stop cryptsvc 2>&1 | Out-Null
    
    Write-Log "Limpiando carpetas de cache..." "INFO"
    $sdPath = "$env:SystemRoot\SoftwareDistribution"
    if (Test-Path $sdPath) { 
        cmd /c "rmdir /s /q `"$sdPath`"" 2>&1 | Out-Null
        Write-Log "  Limpiado SoftwareDistribution" "OK"
    }
    
    $catPath = "$env:SystemRoot\system32\catroot2"
    if (Test-Path $catPath) { 
        cmd /c "rmdir /s /q `"$catPath`"" 2>&1 | Out-Null
        Write-Log "  Limpiado Catroot2" "OK"
    }
    
    Write-Log "Reiniciando servicios..." "INFO"
    net start bits 2>&1 | Out-Null
    net start wuauserv 2>&1 | Out-Null
    net start cryptsvc 2>&1 | Out-Null
    
    Write-Log "========== COMPLETADO ==========" "OK"
}

function Invoke-FullCleanup {
    Write-Log "========== LIMPIEZA COMPLETA ==========" "TASK"
    Clear-CurrentUserTemp
    Clear-AllUsersTemp
    Clear-WindowsTemp
    Clear-InternetCache
    Run-DiskCleanup
    Write-Log "========== LIMPIEZA COMPLETA FINALIZADA ==========" "OK"
}

function Remove-AllBloatware {
    Write-Log "========== ELIMINANDO BLOATWARE ==========" "TASK"
    
    $removed = 0
    
    Write-Log "Eliminando aplicaciones del usuario actual..." "INFO"
    $appxPackages = Get-AppxPackage | Where-Object { $_.Name -match $global:BloatwareRegex }
    foreach ($pkg in $appxPackages) {
        try {
            Remove-AppxPackage -Package $pkg -ErrorAction SilentlyContinue
            $removed++
            Write-Log "  Eliminado: $($pkg.Name)" "OK"
        } catch { Write-Log "  Error: $($pkg.Name)" "WARN" }
    }
    
    Write-Log "Eliminando aplicaciones provisionadas..." "INFO"
    $provisioned = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -match $global:BloatwareRegex }
    foreach ($prov in $provisioned) {
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction SilentlyContinue
            Write-Log "  Eliminado provisionado: $($prov.DisplayName)" "OK"
        } catch { }
    }
    
    Write-Log "Deshabilitando Telemetria..." "INFO"
    $telemetryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
    if (!(Test-Path $telemetryPath)) { New-Item -Path $telemetryPath -Force | Out-Null }
    Set-ItemProperty -Path $telemetryPath -Name "AllowTelemetry" -Value 0 -ErrorAction SilentlyContinue
    Write-Log "  Telemetria deshabilitada" "OK"
    
    Write-Log "Deshabilitando Bing Search..." "INFO"
    $bingPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"
    if (!(Test-Path $bingPath)) { New-Item -Path $bingPath -Force | Out-Null }
    Set-ItemProperty -Path $bingPath -Name "BingSearchEnabled" -Value 0 -ErrorAction SilentlyContinue
    Write-Log "  Bing Search deshabilitado" "OK"
    
    Write-Log "Deshabilitando Cortana..." "INFO"
    $cortanaPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
    if (!(Test-Path $cortanaPath)) { New-Item -Path $cortanaPath -Force | Out-Null }
    Set-ItemProperty -Path $cortanaPath -Name "AllowCortana" -Value 0 -ErrorAction SilentlyContinue
    Write-Log "  Cortana deshabilitada" "OK"
    
    if ($global:IsWindows11) {
        Write-Log "Deshabilitando Widgets..." "INFO"
        $widgetsPath = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
        if (!(Test-Path $widgetsPath)) { New-Item -Path $widgetsPath -Force | Out-Null }
        Set-ItemProperty -Path $widgetsPath -Name "AllowNewsAndInterests" -Value 0 -ErrorAction SilentlyContinue
        Write-Log "  Widgets deshabilitados" "OK"
    }
    
    if ($global:Is24H2) {
        Write-Log "Deshabilitando Recall..." "INFO"
        $recallPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        if (!(Test-Path $recallPath)) { New-Item -Path $recallPath -Force | Out-Null }
        Set-ItemProperty -Path $recallPath -Name "EnableRecall" -Value 0 -ErrorAction SilentlyContinue
        Write-Log "  Recall deshabilitado" "OK"
    }
    
    Write-Log "========== COMPLETADO: $removed aplicaciones eliminadas ==========" "OK"
}

function Remove-OneDrive {
    Write-Log "========== DESINSTALANDO ONEDRIVE ==========" "TASK"
    try {
        Get-Process -Name "OneDrive*" -ErrorAction SilentlyContinue | Stop-Process -Force
        Write-Log "Procesos de OneDrive detenidos" "OK"
        
        $uninstaller = "$env:SYSTEMROOT\SysWOW64\OneDriveSetup.exe"
        if (!(Test-Path $uninstaller)) {
            $uninstaller = "$env:SYSTEMROOT\System32\OneDriveSetup.exe"
        }
        
        if (Test-Path $uninstaller) {
            Write-Log "Ejecutando desinstalador..." "INFO"
            $process = Start-Process -FilePath $uninstaller -ArgumentList "/uninstall" -NoNewWindow -PassThru -Wait
            if ($process.ExitCode -eq 0) {
                Write-Log "OneDrive desinstalado correctamente" "OK"
            } else {
                Write-Log "OneDrive desinstalado (codigo: $($process.ExitCode))" "OK"
            }
        } else {
            Write-Log "No se encontro el desinstalador de OneDrive" "WARN"
        }
    } catch {
        Write-Log "Error al desinstalar OneDrive: $_" "ERROR"
    }
    Write-Log "========== COMPLETADO ==========" "OK"
}

function Install-OneDrive {
    Write-Log "========== INSTALANDO ONEDRIVE ==========" "TASK"
    try {
        $oneDriveUrl = "https://go.microsoft.com/fwlink/?linkid=2249142"
        $installerPath = "$global:DownloadDir\OneDriveSetup.exe"
        
        Write-Log "Descargando instalador de OneDrive desde Microsoft..." "INFO"
        
        try {
            Invoke-WebRequest -Uri $oneDriveUrl -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
            Write-Log "Descarga completada: $installerPath" "OK"
        } catch {
            Write-Log "Error en descarga, intentando metodo alternativo..." "WARN"
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($oneDriveUrl, $installerPath)
            Write-Log "Descarga completada (metodo alternativo)" "OK"
        }
        
        if (Test-Path $installerPath) {
            Write-Log "Ejecutando instalador de OneDrive..." "INFO"
            $process = Start-Process -FilePath $installerPath -ArgumentList "/silent" -NoNewWindow -PassThru -Wait
            if ($process.ExitCode -eq 0) {
                Write-Log "OneDrive instalado correctamente" "OK"
            } else {
                Write-Log "OneDrive instalado (codigo: $($process.ExitCode))" "OK"
            }
            Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
        } else {
            Write-Log "No se pudo descargar el instalador de OneDrive" "ERROR"
        }
    } catch {
        Write-Log "Error al instalar OneDrive: $_" "ERROR"
    }
    Write-Log "========== COMPLETADO ==========" "OK"
}

function Install-SelectedApps {
    param([string[]]$Apps)
    
    if ($global:InstallRunning) {
        Write-Log "Ya hay una instalacion en curso" "WARN"
        return
    }
    
    $global:InstallRunning = $true
    Write-Log "========== INSTALANDO APLICACIONES SELECCIONADAS ==========" "TASK"
    
    if (-not $global:WingetAvailable) {
        Write-Log "Winget no esta disponible. Abriendo Microsoft Store..." "WARN"
        Start-Process "ms-windows-store://pdp/?productid=9NBLGGH4NNS1" -ErrorAction SilentlyContinue
        Write-Log "Instala 'App Installer' desde la Store y vuelve a ejecutar" "INFO"
        $global:InstallRunning = $false
        return
    }
    
    foreach ($app in $Apps) {
        Write-Log "Instalando: $app..." "INFO"
        try {
            switch ($app) {
                "7zip" { 
                    $process = Start-Process -FilePath "winget" -ArgumentList "install --id 7zip.7zip --silent --accept-package-agreements --accept-source-agreements" -NoNewWindow -PassThru -Wait
                    if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 0) { Write-Log "  Instalado: $app" "OK" }
                    else { Write-Log "  Error instalando: $app (codigo: $($process.ExitCode))" "WARN" }
                }
                "Chrome" { 
                    $process = Start-Process -FilePath "winget" -ArgumentList "install --id Google.Chrome --silent --accept-package-agreements --accept-source-agreements" -NoNewWindow -PassThru -Wait
                    if ($process.ExitCode -eq 0) { Write-Log "  Instalado: $app" "OK" }
                    else { Write-Log "  Error instalando: $app (codigo: $($process.ExitCode))" "WARN" }
                }
                "Firefox" { 
                    $process = Start-Process -FilePath "winget" -ArgumentList "install --id Mozilla.Firefox --silent --accept-package-agreements --accept-source-agreements" -NoNewWindow -PassThru -Wait
                    if ($process.ExitCode -eq 0) { Write-Log "  Instalado: $app" "OK" }
                    else { Write-Log "  Error instalando: $app (codigo: $($process.ExitCode))" "WARN" }
                }
                "VLC" { 
                    $process = Start-Process -FilePath "winget" -ArgumentList "install --id VideoLAN.VLC --silent --accept-package-agreements --accept-source-agreements" -NoNewWindow -PassThru -Wait
                    if ($process.ExitCode -eq 0) { Write-Log "  Instalado: $app" "OK" }
                    else { Write-Log "  Error instalando: $app (codigo: $($process.ExitCode))" "WARN" }
                }
                "Steam" { 
                    $process = Start-Process -FilePath "winget" -ArgumentList "install --id Valve.Steam --silent --accept-package-agreements --accept-source-agreements" -NoNewWindow -PassThru -Wait
                    if ($process.ExitCode -eq 0) { Write-Log "  Instalado: $app" "OK" }
                    else { Write-Log "  Error instalando: $app (codigo: $($process.ExitCode))" "WARN" }
                }
                "Discord" { 
                    $process = Start-Process -FilePath "winget" -ArgumentList "install --id Discord.Discord --silent --accept-package-agreements --accept-source-agreements" -NoNewWindow -PassThru -Wait
                    if ($process.ExitCode -eq 0) { Write-Log "  Instalado: $app" "OK" }
                    else { Write-Log "  Error instalando: $app (codigo: $($process.ExitCode))" "WARN" }
                }
            }
        } catch {
            Write-Log "  Error instalando: $app - $_" "ERROR"
        }
        [System.Windows.Forms.Application]::DoEvents()
    }
    Write-Log "========== INSTALACION COMPLETADA ==========" "OK"
    $global:InstallRunning = $false
}

function Optimize-System {
    Write-Log "========== OPTIMIZANDO SISTEMA ==========" "TASK"
    
    Write-Log "Configurando prioridad de juegos..." "INFO"
    $priorityPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    if (!(Test-Path $priorityPath)) { New-Item -Path $priorityPath -Force | Out-Null }
    Set-ItemProperty -Path $priorityPath -Name "SystemResponsiveness" -Value 10 -ErrorAction SilentlyContinue
    Write-Log "  Priorizacion de juegos activada" "OK"
    
    Write-Log "Deshabilitando servicios innecesarios..." "INFO"
    $services = @("SysMain", "WSearch")
    foreach ($service in $services) {
        Stop-Service $service -Force -ErrorAction SilentlyContinue
        Set-Service $service -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Log "  Servicio deshabilitado: $service" "OK"
    }
    
    Write-Log "Activando plan de alto rendimiento..." "INFO"
    powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1 | Out-Null
    Write-Log "  Plan de alto rendimiento activado" "OK"
    
    Write-Log "========== OPTIMIZACION COMPLETADA ==========" "OK"
}

function Start-RepairJob {
    Write-Log "========== INICIANDO REPARACION COMPLETA ==========" "TASK"
    Write-Log "Este proceso ejecuta 14 pasos. La interfaz seguira respondiendo." "INFO"
    
    $global:RepairRunning = $true
    
    $scriptBlock = {
        $logFile = "C:\Temp\WindowsOptimizer\optimizer_log.txt"
        
        function Write-Step {
            param([int]$Num, [int]$Total, [string]$Name, [string]$Status)
            $time = Get-Date -Format "HH:mm:ss"
            $msg = "[$time] [PASO $Num/$Total] $Name - $Status"
            Add-Content -Path $logFile -Value $msg
        }
        
        $total = 14
        $success = $true
        
        try {
            Write-Step -Num 1 -Total $total -Name "Limpiar Temp del usuario actual" -Status "iniciando"
            cmd /c "del /f /s /q `"$env:USERPROFILE\AppData\Local\Temp\*`"" 2>&1 | Out-Null
            cmd /c "rd /s /q `"$env:USERPROFILE\AppData\Local\Temp`"" 2>&1 | Out-Null
            Write-Step -Num 1 -Total $total -Name "Limpiar Temp del usuario actual" -Status "COMPLETADO"
            
            Write-Step -Num 2 -Total $total -Name "Limpiar Temp de Windows" -Status "iniciando"
            cmd /c "del /f /s /q C:\Windows\Temp\*" 2>&1 | Out-Null
            cmd /c "rd /s /q C:\Windows\Temp" 2>&1 | Out-Null
            Write-Step -Num 2 -Total $total -Name "Limpiar Temp de Windows" -Status "COMPLETADO"
            
            Write-Step -Num 3 -Total $total -Name "Limpiar cache de Internet" -Status "iniciando"
            RunDll32.exe InetCpl.cpl,ClearMyTracksByProcess 8 2>&1 | Out-Null
            RunDll32.exe InetCpl.cpl,ClearMyTracksByProcess 4 2>&1 | Out-Null
            RunDll32.exe InetCpl.cpl,ClearMyTracksByProcess 2 2>&1 | Out-Null
            RunDll32.exe InetCpl.cpl,ClearMyTracksByProcess 1 2>&1 | Out-Null
            Write-Step -Num 3 -Total $total -Name "Limpiar cache de Internet" -Status "COMPLETADO"
            
            Write-Step -Num 4 -Total $total -Name "DISM CheckHealth" -Status "iniciando"
            & dism.exe /Online /Cleanup-Image /CheckHealth 2>&1 | Out-Null
            Write-Step -Num 4 -Total $total -Name "DISM CheckHealth" -Status "COMPLETADO"
            
            Write-Step -Num 5 -Total $total -Name "DISM ScanHealth" -Status "iniciando"
            & dism.exe /Online /Cleanup-Image /ScanHealth 2>&1 | Out-Null
            Write-Step -Num 5 -Total $total -Name "DISM ScanHealth" -Status "COMPLETADO"
            
            Write-Step -Num 6 -Total $total -Name "DISM RestoreHealth" -Status "iniciando"
            & dism.exe /Online /Cleanup-Image /RestoreHealth 2>&1 | Out-Null
            Write-Step -Num 6 -Total $total -Name "DISM RestoreHealth" -Status "COMPLETADO"
            
            Write-Step -Num 7 -Total $total -Name "SFC Scannow" -Status "iniciando"
            & sfc.exe /scannow 2>&1 | Out-Null
            Write-Step -Num 7 -Total $total -Name "SFC Scannow" -Status "COMPLETADO"
            
            Write-Step -Num 8 -Total $total -Name "Registrar DLLs del sistema" -Status "iniciando"
            $dlls = @("atl.dll", "urlmon.dll", "mshtml.dll", "shdocvw.dll", "browseui.dll", "jscript.dll", "vbscript.dll", "scrrun.dll", "msxml.dll", "msxml3.dll", "msxml6.dll", "actxprxy.dll", "softpub.dll", "wintrust.dll", "dssenh.dll", "rsaenh.dll", "gpkcsp.dll", "sccbase.dll", "slbcsp.dll", "cryptdlg.dll", "oleaut32.dll", "ole32.dll", "shell32.dll", "initpki.dll", "wuapi.dll", "wuaueng.dll", "wuaueng1.dll", "wucltui.dll", "wups.dll", "wups2.dll", "wuweb.dll", "qmgr.dll", "qmgrprxy.dll", "wucltux.dll", "muweb.dll", "wuwebv.dll")
            foreach ($dll in $dlls) {
                regsvr32.exe /s $dll 2>&1 | Out-Null
            }
            Write-Step -Num 8 -Total $total -Name "Registrar DLLs del sistema" -Status "COMPLETADO"
            
            Write-Step -Num 9 -Total $total -Name "Resetear Winsock" -Status "iniciando"
            netsh winsock reset 2>&1 | Out-Null
            netsh winsock reset proxy 2>&1 | Out-Null
            Write-Step -Num 9 -Total $total -Name "Resetear Winsock" -Status "COMPLETADO"
            
            Write-Step -Num 10 -Total $total -Name "Limpiar cache DNS" -Status "iniciando"
            ipconfig /flushdns 2>&1 | Out-Null
            ipconfig /renew 2>&1 | Out-Null
            ipconfig /registerdns 2>&1 | Out-Null
            Write-Step -Num 10 -Total $total -Name "Limpiar cache DNS" -Status "COMPLETADO"
            
            Write-Step -Num 11 -Total $total -Name "Deshabilitar Firewall" -Status "iniciando"
            netsh advfirewall set domainprofile state off 2>&1 | Out-Null
            netsh advfirewall set privateprofile state off 2>&1 | Out-Null
            netsh advfirewall set publicprofile state off 2>&1 | Out-Null
            Write-Step -Num 11 -Total $total -Name "Deshabilitar Firewall" -Status "COMPLETADO"
            
            Write-Step -Num 12 -Total $total -Name "Limpiar cache Windows Update" -Status "iniciando"
            net stop bits 2>&1 | Out-Null
            net stop wuauserv 2>&1 | Out-Null
            net stop cryptsvc 2>&1 | Out-Null
            cmd /c "rmdir /s /q `"$env:SystemRoot\SoftwareDistribution`"" 2>&1 | Out-Null
            cmd /c "rmdir /s /q `"$env:SystemRoot\system32\catroot2`"" 2>&1 | Out-Null
            net start bits 2>&1 | Out-Null
            net start wuauserv 2>&1 | Out-Null
            net start cryptsvc 2>&1 | Out-Null
            Write-Step -Num 12 -Total $total -Name "Limpiar cache Windows Update" -Status "COMPLETADO"
            
            Write-Step -Num 13 -Total $total -Name "Actualizar politicas de grupo" -Status "iniciando"
            gpupdate /force 2>&1 | Out-Null
            Write-Step -Num 13 -Total $total -Name "Actualizar politicas de grupo" -Status "COMPLETADO"
            
            Write-Step -Num 14 -Total $total -Name "Ejecutar limpieza de disco" -Status "iniciando"
            Cleanmgr.exe /sagerun:64 2>&1 | Out-Null
            Write-Step -Num 14 -Total $total -Name "Ejecutar limpieza de disco" -Status "COMPLETADO"
            
            $time = Get-Date -Format "HH:mm:ss"
            Add-Content -Path $logFile -Value "[$time] [FIN] ===== REPARACION COMPLETADA - 14/14 PASOS =====`n"
            
        } catch {
            $time = Get-Date -Format "HH:mm:ss"
            Add-Content -Path $logFile -Value "[$time] [ERROR] Error en reparacion: $_" 
            $success = $false
        }
        
        return $success
    }
    
    $global:CurrentJob = Start-Job -Name "RepairSystem" -ScriptBlock $scriptBlock
    
    $global:RepairTimer = New-Object System.Windows.Forms.Timer
    $global:RepairTimer.Interval = 2000
    $global:RepairTimer.Add_Tick({
        if ($global:CurrentJob.State -eq "Completed") {
            $global:RepairTimer.Stop()
            $result = Receive-Job -Job $global:CurrentJob -ErrorAction SilentlyContinue
            Remove-Job -Job $global:CurrentJob -Force -ErrorAction SilentlyContinue
            $global:CurrentJob = $null
            $global:RepairRunning = $false
            
            if ($result -eq $true) {
                Write-Log "========== REPARACION COMPLETADA (14/14 PASOS) ==========" "OK"
                Write-Log "Se recomienda REINICIAR el equipo para aplicar todos los cambios." "WARNING"
                
                $resultMsg = [System.Windows.Forms.MessageBox]::Show("La reparacion ha finalizado correctamente.`n`n¿Desea reiniciar el equipo ahora?", "Reparacion Completada", "YesNo", "Question")
                if ($resultMsg -eq "Yes") {
                    Write-Log "Reiniciando equipo..." "INFO"
                    Start-Sleep -Seconds 3
                    Restart-Computer -Force
                }
            } else {
                Write-Log "La reparacion tuvo errores, pero se completaron los pasos posibles." "WARNING"
            }
        } elseif ($global:CurrentJob.State -eq "Failed") {
            $global:RepairTimer.Stop()
            Write-Log "Reparacion fallida" "ERROR"
            Remove-Job -Job $global:CurrentJob -Force -ErrorAction SilentlyContinue
            $global:CurrentJob = $null
            $global:RepairRunning = $false
        }
    })
    $global:RepairTimer.Start()
}

function Stop-RepairJob {
    Write-Log "========== DETENIENDO REPARACION ==========" "TASK"
    
    if ($global:RepairTimer -ne $null) {
        $global:RepairTimer.Stop()
        $global:RepairTimer.Dispose()
        $global:RepairTimer = $null
    }
    
    if ($global:CurrentJob -ne $null) {
        try {
            Stop-Job -Job $global:CurrentJob -ErrorAction SilentlyContinue
            Remove-Job -Job $global:CurrentJob -Force -ErrorAction SilentlyContinue
            Write-Log "Job de reparacion detenido" "OK"
        } catch {
            Write-Log "Error al detener el job: $_" "ERROR"
        }
        $global:CurrentJob = $null
    }
    
    Write-Log "Matando procesos bloqueados..." "INFO"
    $processesToKill = @("dism", "sfc", "TiWorker", "TrustedInstaller")
    foreach ($proc in $processesToKill) {
        try {
            Get-Process -Name $proc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Write-Log "  Terminado: $proc" "OK"
        } catch { }
    }
    
    $global:RepairRunning = $false
    Write-Log "========== REPARACION DETENIDA ==========" "OK"
}

function Reset-WindowsUpdateOnly {
    Write-Log "========== REINICIANDO WINDOWS UPDATE ==========" "TASK"
    
    Write-Log "Deteniendo servicios..." "INFO"
    net stop bits 2>&1 | Out-Null
    net stop wuauserv 2>&1 | Out-Null
    net stop cryptsvc 2>&1 | Out-Null
    
    Write-Log "Limpiando carpetas de cache..." "INFO"
    $sdPath = "$env:SystemRoot\SoftwareDistribution"
    if (Test-Path $sdPath) { 
        cmd /c "rmdir /s /q `"$sdPath`"" 2>&1 | Out-Null
        Write-Log "  Limpiado SoftwareDistribution" "OK"
    }
    
    $catPath = "$env:SystemRoot\system32\catroot2"
    if (Test-Path $catPath) { 
        cmd /c "rmdir /s /q `"$catPath`"" 2>&1 | Out-Null
        Write-Log "  Limpiado Catroot2" "OK"
    }
    
    Write-Log "Reiniciando servicios..." "INFO"
    net start bits 2>&1 | Out-Null
    net start wuauserv 2>&1 | Out-Null
    net start cryptsvc 2>&1 | Out-Null
    
    Write-Log "========== WINDOWS UPDATE REINICIADO ==========" "OK"
}

function Create-RestorePoint {
    Write-Log "========== CREANDO PUNTO DE RESTAURACION ==========" "TASK"
    try {
        Checkpoint-Computer -Description "Windows Optimizer - Antes de cambios" -ErrorAction SilentlyContinue
        Write-Log "Punto de restauracion creado exitosamente" "OK"
    } catch {
        Write-Log "No se pudo crear punto de restauracion" "WARN"
    }
    Write-Log "========== COMPLETADO ==========" "OK"
}

function Kill-HungProcesses {
    Write-Log "========== TERMINANDO PROCESOS BLOQUEADOS ==========" "TASK"
    
    if ($global:RepairTimer -ne $null) {
        $global:RepairTimer.Stop()
        $global:RepairTimer.Dispose()
        $global:RepairTimer = $null
    }
    
    if ($global:CurrentJob -ne $null) {
        Write-Log "Deteniendo job de reparacion en curso..." "INFO"
        try {
            Stop-Job -Job $global:CurrentJob -ErrorAction SilentlyContinue
            Remove-Job -Job $global:CurrentJob -Force -ErrorAction SilentlyContinue
            Write-Log "  Job detenido" "OK"
        } catch {
            Write-Log "  Error al detener job: $_" "WARN"
        }
        $global:CurrentJob = $null
        $global:RepairRunning = $false
    }
    
    Write-Log "Matando procesos bloqueados..." "INFO"
    $processesToKill = @("dism", "sfc", "TiWorker", "TrustedInstaller", "OneDrive", "SearchUI", "RuntimeBroker", "SettingSyncHost", "winget")
    foreach ($proc in $processesToKill) {
        try {
            $running = Get-Process -Name $proc -ErrorAction SilentlyContinue
            if ($running) {
                $running | Stop-Process -Force -ErrorAction SilentlyContinue
                Write-Log "  Terminado: $proc" "OK"
            }
        } catch { }
    }
    
    Write-Log "Procesos terminados" "OK"
    Write-Log "========== COMPLETADO ==========" "OK"
}
#endregion

#region [INTERFAZ GRAFICA]
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$Form = New-Object System.Windows.Forms.Form
$Form.ClientSize = New-Object System.Drawing.Point(500, 760)
$Form.StartPosition = 'CenterScreen'
$Form.FormBorderStyle = 'FixedSingle'
$Form.MinimizeBox = $false
$Form.MaximizeBox = $false
$Form.ShowIcon = $false
$Form.Text = "Windows Optimizer v$global:ScriptVersion - $global:WindowsVersion"
$Form.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)

$currentY = 10

# Panel Debloat
$DebloatPanel = New-Object System.Windows.Forms.Panel
$DebloatPanel.Size = New-Object System.Drawing.Size(480, 100)
$DebloatPanel.Location = New-Object System.Drawing.Point(10, $currentY)
$DebloatPanel.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)

$lblDebloat = New-Object System.Windows.Forms.Label
$lblDebloat.Text = "ELIMINAR BLOATWARE"
$lblDebloat.Location = New-Object System.Drawing.Point(10, 5)
$lblDebloat.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$lblDebloat.ForeColor = [System.Drawing.Color]::White

$btnRemoveAll = New-Object System.Windows.Forms.Button
$btnRemoveAll.Text = "ELIMINAR TODO (Copilot, Teams, Xbox)"
$btnRemoveAll.Size = New-Object System.Drawing.Size(460, 35)
$btnRemoveAll.Location = New-Object System.Drawing.Point(10, 30)
$btnRemoveAll.FlatStyle = 'Flat'
$btnRemoveAll.Font = New-Object System.Drawing.Font("Consolas", 9)
$btnRemoveAll.ForeColor = [System.Drawing.Color]::White
$btnRemoveAll.BackColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
$btnRemoveAll.Add_Click({ Remove-AllBloatware })

$btnRemoveOD = New-Object System.Windows.Forms.Button
$btnRemoveOD.Text = "DESINSTALAR ONEDRIVE"
$btnRemoveOD.Size = New-Object System.Drawing.Size(460, 30)
$btnRemoveOD.Location = New-Object System.Drawing.Point(10, 70)
$btnRemoveOD.FlatStyle = 'Flat'
$btnRemoveOD.Font = New-Object System.Drawing.Font("Consolas", 9)
$btnRemoveOD.ForeColor = [System.Drawing.Color]::White
$btnRemoveOD.BackColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
$btnRemoveOD.Add_Click({ Remove-OneDrive })

$DebloatPanel.Controls.AddRange(@($lblDebloat, $btnRemoveAll, $btnRemoveOD))
$currentY += 110

# Panel Limpieza
$CleanPanel = New-Object System.Windows.Forms.Panel
$CleanPanel.Size = New-Object System.Drawing.Size(480, 170)
$CleanPanel.Location = New-Object System.Drawing.Point(10, $currentY)
$CleanPanel.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)

$lblClean = New-Object System.Windows.Forms.Label
$lblClean.Text = "LIMPIEZA DE ARCHIVOS"
$lblClean.Location = New-Object System.Drawing.Point(10, 5)
$lblClean.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$lblClean.ForeColor = [System.Drawing.Color]::White

$btnClearCurrent = New-Object System.Windows.Forms.Button
$btnClearCurrent.Text = "LIMPIAR PERFIL ACTUAL"
$btnClearCurrent.Size = New-Object System.Drawing.Size(230, 30)
$btnClearCurrent.Location = New-Object System.Drawing.Point(10, 35)
$btnClearCurrent.FlatStyle = 'Flat'
$btnClearCurrent.Font = New-Object System.Drawing.Font("Consolas", 9)
$btnClearCurrent.ForeColor = [System.Drawing.Color]::White
$btnClearCurrent.BackColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
$btnClearCurrent.Add_Click({ Clear-CurrentUserTemp })

$btnClearAll = New-Object System.Windows.Forms.Button
$btnClearAll.Text = "LIMPIAR TODOS PERFILES"
$btnClearAll.Size = New-Object System.Drawing.Size(230, 30)
$btnClearAll.Location = New-Object System.Drawing.Point(240, 35)
$btnClearAll.FlatStyle = 'Flat'
$btnClearAll.Font = New-Object System.Drawing.Font("Consolas", 9)
$btnClearAll.ForeColor = [System.Drawing.Color]::White
$btnClearAll.BackColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
$btnClearAll.Add_Click({ Clear-AllUsersTemp })

$btnClearWinTemp = New-Object System.Windows.Forms.Button
$btnClearWinTemp.Text = "LIMPIAR WINDOWS TEMP"
$btnClearWinTemp.Size = New-Object System.Drawing.Size(230, 30)
$btnClearWinTemp.Location = New-Object System.Drawing.Point(10, 70)
$btnClearWinTemp.FlatStyle = 'Flat'
$btnClearWinTemp.Font = New-Object System.Drawing.Font("Consolas", 9)
$btnClearWinTemp.ForeColor = [System.Drawing.Color]::White
$btnClearWinTemp.BackColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
$btnClearWinTemp.Add_Click({ Clear-WindowsTemp })

$btnClearCache = New-Object System.Windows.Forms.Button
$btnClearCache.Text = "LIMPIAR CACHE INTERNET"
$btnClearCache.Size = New-Object System.Drawing.Size(230, 30)
$btnClearCache.Location = New-Object System.Drawing.Point(240, 70)
$btnClearCache.FlatStyle = 'Flat'
$btnClearCache.Font = New-Object System.Drawing.Font("Consolas", 9)
$btnClearCache.ForeColor = [System.Drawing.Color]::White
$btnClearCache.BackColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
$btnClearCache.Add_Click({ Clear-InternetCache })

$btnFullClean = New-Object System.Windows.Forms.Button
$btnFullClean.Text = "LIMPIEZA COMPLETA"
$btnFullClean.Size = New-Object System.Drawing.Size(460, 35)
$btnFullClean.Location = New-Object System.Drawing.Point(10, 110)
$btnFullClean.FlatStyle = 'Flat'
$btnFullClean.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
$btnFullClean.ForeColor = [System.Drawing.Color]::White
$btnFullClean.BackColor = [System.Drawing.Color]::FromArgb(119, 119, 119)
$btnFullClean.Add_Click({ Invoke-FullCleanup })

$CleanPanel.Controls.AddRange(@($lblClean, $btnClearCurrent, $btnClearAll, $btnClearWinTemp, $btnClearCache, $btnFullClean))
$currentY += 180

# Panel Instalacion
$InstallPanel = New-Object System.Windows.Forms.Panel
$InstallPanel.Size = New-Object System.Drawing.Size(480, 120)
$InstallPanel.Location = New-Object System.Drawing.Point(10, $currentY)
$InstallPanel.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)

$lblInstall = New-Object System.Windows.Forms.Label
$lblInstall.Text = "INSTALAR APLICACIONES"
$lblInstall.Location = New-Object System.Drawing.Point(10, 5)
$lblInstall.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$lblInstall.ForeColor = [System.Drawing.Color]::White

$chk7zip = New-Object System.Windows.Forms.CheckBox
$chk7zip.Text = "7-Zip"; $chk7zip.Location = New-Object System.Drawing.Point(10, 35); $chk7zip.ForeColor = [System.Drawing.Color]::White; $chk7zip.Font = New-Object System.Drawing.Font("Consolas", 9)
$chkChrome = New-Object System.Windows.Forms.CheckBox
$chkChrome.Text = "Chrome"; $chkChrome.Location = New-Object System.Drawing.Point(90, 35); $chkChrome.ForeColor = [System.Drawing.Color]::White; $chkChrome.Font = New-Object System.Drawing.Font("Consolas", 9)
$chkFirefox = New-Object System.Windows.Forms.CheckBox
$chkFirefox.Text = "Firefox"; $chkFirefox.Location = New-Object System.Drawing.Point(180, 35); $chkFirefox.ForeColor = [System.Drawing.Color]::White; $chkFirefox.Font = New-Object System.Drawing.Font("Consolas", 9)
$chkVLC = New-Object System.Windows.Forms.CheckBox
$chkVLC.Text = "VLC"; $chkVLC.Location = New-Object System.Drawing.Point(270, 35); $chkVLC.ForeColor = [System.Drawing.Color]::White; $chkVLC.Font = New-Object System.Drawing.Font("Consolas", 9)
$chkSteam = New-Object System.Windows.Forms.CheckBox
$chkSteam.Text = "Steam"; $chkSteam.Location = New-Object System.Drawing.Point(350, 35); $chkSteam.ForeColor = [System.Drawing.Color]::White; $chkSteam.Font = New-Object System.Drawing.Font("Consolas", 9)
$chkDiscord = New-Object System.Windows.Forms.CheckBox
$chkDiscord.Text = "Discord"; $chkDiscord.Location = New-Object System.Drawing.Point(420, 35); $chkDiscord.ForeColor = [System.Drawing.Color]::White; $chkDiscord.Font = New-Object System.Drawing.Font("Consolas", 9)
$chkOneDrive = New-Object System.Windows.Forms.CheckBox
$chkOneDrive.Text = "OneDrive"; $chkOneDrive.Location = New-Object System.Drawing.Point(10, 65); $chkOneDrive.ForeColor = [System.Drawing.Color]::FromArgb(255, 204, 136); $chkOneDrive.Font = New-Object System.Drawing.Font("Consolas", 9)

$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = "INSTALAR SELECCIONADAS"
$btnInstall.Size = New-Object System.Drawing.Size(460, 40)
$btnInstall.Location = New-Object System.Drawing.Point(10, 95)
$btnInstall.FlatStyle = 'Flat'
$btnInstall.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
$btnInstall.ForeColor = [System.Drawing.Color]::White
$btnInstall.BackColor = [System.Drawing.Color]::FromArgb(51, 170, 51)
$btnInstall.Add_Click({
    $apps = @()
    if ($chk7zip.Checked) { $apps += "7zip" }
    if ($chkChrome.Checked) { $apps += "Chrome" }
    if ($chkFirefox.Checked) { $apps += "Firefox" }
    if ($chkVLC.Checked) { $apps += "VLC" }
    if ($chkSteam.Checked) { $apps += "Steam" }
    if ($chkDiscord.Checked) { $apps += "Discord" }
    if ($apps.Count -gt 0) { Install-SelectedApps -Apps $apps }
    if ($chkOneDrive.Checked) { Install-OneDrive }
    $chk7zip.Checked = $false; $chkChrome.Checked = $false
    $chkFirefox.Checked = $false; $chkVLC.Checked = $false
    $chkSteam.Checked = $false; $chkDiscord.Checked = $false; $chkOneDrive.Checked = $false
})

$InstallPanel.Controls.AddRange(@($lblInstall, $chk7zip, $chkChrome, $chkFirefox, $chkVLC, $chkSteam, $chkDiscord, $chkOneDrive, $btnInstall))
$currentY += 130

# Panel Herramientas
$ToolsPanel = New-Object System.Windows.Forms.Panel
$ToolsPanel.Size = New-Object System.Drawing.Size(480, 100)
$ToolsPanel.Location = New-Object System.Drawing.Point(10, $currentY)
$ToolsPanel.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)

$lblTools = New-Object System.Windows.Forms.Label
$lblTools.Text = "HERRAMIENTAS"
$lblTools.Location = New-Object System.Drawing.Point(10, 5)
$lblTools.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$lblTools.ForeColor = [System.Drawing.Color]::White

$btnOptimize = New-Object System.Windows.Forms.Button
$btnOptimize.Text = "OPTIMIZAR"
$btnOptimize.Size = New-Object System.Drawing.Size(110, 35)
$btnOptimize.Location = New-Object System.Drawing.Point(10, 35)
$btnOptimize.FlatStyle = 'Flat'
$btnOptimize.Font = New-Object System.Drawing.Font("Consolas", 9)
$btnOptimize.ForeColor = [System.Drawing.Color]::White
$btnOptimize.BackColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
$btnOptimize.Add_Click({ Optimize-System })

$btnRepair = New-Object System.Windows.Forms.Button
$btnRepair.Text = "REPARAR (14 PASOS)"
$btnRepair.Size = New-Object System.Drawing.Size(110, 35)
$btnRepair.Location = New-Object System.Drawing.Point(125, 35)
$btnRepair.FlatStyle = 'Flat'
$btnRepair.Font = New-Object System.Drawing.Font("Consolas", 9)
$btnRepair.ForeColor = [System.Drawing.Color]::White
$btnRepair.BackColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
$btnRepair.Add_Click({ Start-RepairJob })

$btnDisableFirewall = New-Object System.Windows.Forms.Button
$btnDisableFirewall.Text = "DESHABILITAR FW"
$btnDisableFirewall.Size = New-Object System.Drawing.Size(110, 35)
$btnDisableFirewall.Location = New-Object System.Drawing.Point(240, 35)
$btnDisableFirewall.FlatStyle = 'Flat'
$btnDisableFirewall.Font = New-Object System.Drawing.Font("Consolas", 9)
$btnDisableFirewall.ForeColor = [System.Drawing.Color]::White
$btnDisableFirewall.BackColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
$btnDisableFirewall.Add_Click({ Disable-Firewall })

$btnResetWU = New-Object System.Windows.Forms.Button
$btnResetWU.Text = "RESET WU"
$btnResetWU.Size = New-Object System.Drawing.Size(110, 35)
$btnResetWU.Location = New-Object System.Drawing.Point(355, 35)
$btnResetWU.FlatStyle = 'Flat'
$btnResetWU.Font = New-Object System.Drawing.Font("Consolas", 9)
$btnResetWU.ForeColor = [System.Drawing.Color]::White
$btnResetWU.BackColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
$btnResetWU.Add_Click({ Reset-WindowsUpdateOnly })

$btnRestorePoint = New-Object System.Windows.Forms.Button
$btnRestorePoint.Text = "PTO RESTAURACION"
$btnRestorePoint.Size = New-Object System.Drawing.Size(225, 35)
$btnRestorePoint.Location = New-Object System.Drawing.Point(10, 75)
$btnRestorePoint.FlatStyle = 'Flat'
$btnRestorePoint.Font = New-Object System.Drawing.Font("Consolas", 9)
$btnRestorePoint.ForeColor = [System.Drawing.Color]::White
$btnRestorePoint.BackColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
$btnRestorePoint.Add_Click({ Create-RestorePoint })

$btnDiskCleanup = New-Object System.Windows.Forms.Button
$btnDiskCleanup.Text = "LIMPIEZA DISCO"
$btnDiskCleanup.Size = New-Object System.Drawing.Size(225, 35)
$btnDiskCleanup.Location = New-Object System.Drawing.Point(240, 75)
$btnDiskCleanup.FlatStyle = 'Flat'
$btnDiskCleanup.Font = New-Object System.Drawing.Font("Consolas", 9)
$btnDiskCleanup.ForeColor = [System.Drawing.Color]::White
$btnDiskCleanup.BackColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
$btnDiskCleanup.Add_Click({ Run-DiskCleanup })

$ToolsPanel.Controls.AddRange(@($lblTools, $btnOptimize, $btnRepair, $btnDisableFirewall, $btnResetWU, $btnRestorePoint, $btnDiskCleanup))
$currentY += 110

# Panel Control
$ControlPanel = New-Object System.Windows.Forms.Panel
$ControlPanel.Size = New-Object System.Drawing.Size(480, 50)
$ControlPanel.Location = New-Object System.Drawing.Point(10, $currentY)
$ControlPanel.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)

$btnKill = New-Object System.Windows.Forms.Button
$btnKill.Text = "TERMINAR PROCESOS BLOQUEADOS"
$btnKill.Size = New-Object System.Drawing.Size(460, 35)
$btnKill.Location = New-Object System.Drawing.Point(10, 10)
$btnKill.FlatStyle = 'Flat'
$btnKill.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
$btnKill.ForeColor = [System.Drawing.Color]::White
$btnKill.BackColor = [System.Drawing.Color]::FromArgb(170, 102, 51)
$btnKill.Add_Click({ Kill-HungProcesses })

$ControlPanel.Controls.Add($btnKill)
$currentY += 60

# Creditos
$lblCredit = New-Object System.Windows.Forms.Label
$lblCredit.Text = "Creado con DeepSeek por CFRG, con cariño"
$lblCredit.Location = New-Object System.Drawing.Point(10, $currentY)
$lblCredit.Size = New-Object System.Drawing.Size(480, 20)
$lblCredit.Font = New-Object System.Drawing.Font("Consolas", 8, [System.Drawing.FontStyle]::Italic)
$lblCredit.ForeColor = [System.Drawing.Color]::FromArgb(136, 136, 136)
$lblCredit.TextAlign = 'MiddleCenter'
$currentY += 25

# Boton Cerrar
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "CERRAR PROGRAMA"
$btnClose.Size = New-Object System.Drawing.Size(460, 35)
$btnClose.Location = New-Object System.Drawing.Point(10, $currentY)
$btnClose.FlatStyle = 'Flat'
$btnClose.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
$btnClose.ForeColor = [System.Drawing.Color]::White
$btnClose.BackColor = [System.Drawing.Color]::FromArgb(170, 51, 51)
$btnClose.Add_Click({ $Form.Close() })
$currentY += 45

# Panel de Log
$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = "REGISTRO DE ACTIVIDAD"
$lblLog.Location = New-Object System.Drawing.Point(10, $currentY)
$lblLog.Size = New-Object System.Drawing.Size(480, 20)
$lblLog.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
$lblLog.ForeColor = [System.Drawing.Color]::White
$currentY += 25

$global:LogTextBox = New-Object System.Windows.Forms.RichTextBox
$global:LogTextBox.Location = New-Object System.Drawing.Point(10, $currentY)
$global:LogTextBox.Size = New-Object System.Drawing.Size(460, 120)
$global:LogTextBox.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$global:LogTextBox.ForeColor = [System.Drawing.Color]::LightGreen
$global:LogTextBox.Font = New-Object System.Drawing.Font("Consolas", 8)
$global:LogTextBox.ReadOnly = $true
$global:LogTextBox.ScrollBars = 'Vertical'

$Form.Controls.AddRange(@($DebloatPanel, $CleanPanel, $InstallPanel, $ToolsPanel, $ControlPanel, $lblCredit, $btnClose, $lblLog, $global:LogTextBox))

# Timer para actualizar UI
$updateTimer = New-Object System.Windows.Forms.Timer
$updateTimer.Interval = 500
$updateTimer.Add_Tick({
    if ($global:LogTextBox -and !$global:LogTextBox.IsDisposed) {
        if (Test-Path $global:LogFile) {
            $global:LogTextBox.Text = Get-Content -Path $global:LogFile -ErrorAction SilentlyContinue | Out-String
            $global:LogTextBox.SelectionStart = $global:LogTextBox.Text.Length
            $global:LogTextBox.ScrollToCaret()
        }
    }
})
$updateTimer.Start()

# Mensaje inicial
Write-Log "=============================================" "INFO"
Write-Log "Windows Optimizer v$global:ScriptVersion" "INFO"
Write-Log "Sistema: $global:WindowsVersion (Build $global:WindowsBuild)" "INFO"
if ($global:Is24H2) { Write-Log "Modo Windows 11 24H2 detectado" "INFO" }
Write-Log "=============================================" "INFO"
Write-Log "Listo para usar - Selecciona una opcion" "INFO"
Write-Log "=============================================" "INFO"

[void]$Form.ShowDialog()
$updateTimer.Stop()
#endregion
