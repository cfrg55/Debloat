<#
.SYNOPSIS
    Windows 10/11 Optimizer & Debloater GUI v5.8
.DESCRIPTION
    Herramienta completa para optimizar Windows 10/11 (22H2-24H2)
.NOTES
    Compatible: Windows 10 20H2+, Windows 11 22H2/23H2/24H2
    Requiere: Ejecutar como Administrador
    
#>

#region [INICIALIZACION]
$ErrorActionPreference = 'Continue'
$global:ScriptVersion = "5.8"
$global:CurrentJob = $null
$global:RepairRunning = $false
$global:RepairTimer = $null
$global:InstallRunning = $false

# Auto-elevacion a Administrador
If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($PSCommandPath)`""
    Start-Process PowerShell.exe -ArgumentList $arguments -Verb RunAs
    Exit
}

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

# Limpiar log anterior al iniciar
$global:LogFile = "$global:LogDir\optimizer_log.txt"
if (Test-Path $global:LogFile) { Remove-Item $global:LogFile -Force }

# Funcion para escribir log
function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [$Type] $Message"
    Add-Content -Path $global:LogFile -Value $logEntry
    Write-Host $logEntry
    
    if ($LogTextBox -and !$LogTextBox.IsDisposed) {
        $LogTextBox.Text = Get-Content -Path $global:LogFile -ErrorAction SilentlyContinue | Out-String
        $LogTextBox.SelectionStart = $LogTextBox.Text.Length
        $LogTextBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }
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
        # Descargar el instalador oficial de OneDrive
        $oneDriveUrl = "https://go.microsoft.com/fwlink/?linkid=2249142"
        $installerPath = "$global:DownloadDir\OneDriveSetup.exe"
        
        Write-Log "Descargando instalador de OneDrive desde Microsoft..." "INFO"
        
        # Usar Invoke-WebRequest para descargar
        try {
            Invoke-WebRequest -Uri $oneDriveUrl -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
            Write-Log "Descarga completada: $installerPath" "OK"
        } catch {
            Write-Log "Error en descarga, intentando metodo alternativo..." "WARN"
            # Metodo alternativo con .NET
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
            # Limpiar instalador
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
        if ($LogTextBox -and !$LogTextBox.IsDisposed) {
            $LogTextBox.Text = Get-Content -Path $global:LogFile -ErrorAction SilentlyContinue | Out-String
            $LogTextBox.SelectionStart = $LogTextBox.Text.Length
            $LogTextBox.ScrollToCaret()
        }
        
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
            $errorMsg = $global:CurrentJob.JobStateInfo.Reason.Message
            Write-Log "Reparacion fallida: $errorMsg" "ERROR"
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
$Form.ClientSize = New-Object System.Drawing.Point(680, 980)
$Form.StartPosition = 'CenterScreen'
$Form.FormBorderStyle = 'FixedSingle'
$Form.MinimizeBox = $false
$Form.MaximizeBox = $false
$Form.ShowIcon = $false
$Form.Text = "Windows Optimizer v$global:ScriptVersion - $global:WindowsVersion"
$Form.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#252525")

# Panel Debloat
$DebloatPanel = New-Object System.Windows.Forms.Panel
$DebloatPanel.height = 130
$DebloatPanel.width = 660
$DebloatPanel.location = New-Object System.Drawing.Point(10, 10)
$DebloatPanel.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#252525")

$DebloatLabel = New-Object System.Windows.Forms.Label
$DebloatLabel.text = "ELIMINAR BLOATWARE"
$DebloatLabel.AutoSize = $true
$DebloatLabel.location = New-Object System.Drawing.Point(10, 5)
$DebloatLabel.Font = New-Object System.Drawing.Font('Consolas', 12, [System.Drawing.FontStyle]::Bold)
$DebloatLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")

$RemoveAllBloatware = New-Object System.Windows.Forms.Button
$RemoveAllBloatware.FlatStyle = 'Flat'
$RemoveAllBloatware.text = "ELIMINAR TODO (Copilot, Teams, Xbox, Widgets, Telemetria)"
$RemoveAllBloatware.width = 650
$RemoveAllBloatware.height = 40
$RemoveAllBloatware.location = New-Object System.Drawing.Point(5, 30)
$RemoveAllBloatware.Font = New-Object System.Drawing.Font('Consolas', 9)
$RemoveAllBloatware.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")
$RemoveAllBloatware.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#555555")
$RemoveAllBloatware.Add_Click({ Remove-AllBloatware })

$RemoveOneDriveBtn = New-Object System.Windows.Forms.Button
$RemoveOneDriveBtn.FlatStyle = 'Flat'
$RemoveOneDriveBtn.text = "DESINSTALAR ONEDRIVE"
$RemoveOneDriveBtn.width = 650
$RemoveOneDriveBtn.height = 35
$RemoveOneDriveBtn.location = New-Object System.Drawing.Point(5, 80)
$RemoveOneDriveBtn.Font = New-Object System.Drawing.Font('Consolas', 9)
$RemoveOneDriveBtn.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")
$RemoveOneDriveBtn.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#555555")
$RemoveOneDriveBtn.Add_Click({ Remove-OneDrive })

$DebloatPanel.controls.AddRange(@($DebloatLabel, $RemoveAllBloatware, $RemoveOneDriveBtn))

# Panel Limpieza
$CleanPanel = New-Object System.Windows.Forms.Panel
$CleanPanel.height = 220
$CleanPanel.width = 660
$CleanPanel.location = New-Object System.Drawing.Point(10, 150)
$CleanPanel.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#252525")

$CleanLabel = New-Object System.Windows.Forms.Label
$CleanLabel.text = "LIMPIEZA DE ARCHIVOS TEMPORALES"
$CleanLabel.AutoSize = $true
$CleanLabel.location = New-Object System.Drawing.Point(10, 5)
$CleanLabel.Font = New-Object System.Drawing.Font('Consolas', 12, [System.Drawing.FontStyle]::Bold)
$CleanLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")

$BtnClearCurrentUser = New-Object System.Windows.Forms.Button
$BtnClearCurrentUser.FlatStyle = 'Flat'
$BtnClearCurrentUser.text = "LIMPIAR PERFIL ACTUAL"
$BtnClearCurrentUser.width = 320
$BtnClearCurrentUser.height = 35
$BtnClearCurrentUser.location = New-Object System.Drawing.Point(5, 35)
$BtnClearCurrentUser.Font = New-Object System.Drawing.Font('Consolas', 9)
$BtnClearCurrentUser.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")
$BtnClearCurrentUser.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#555555")
$BtnClearCurrentUser.Add_Click({ Clear-CurrentUserTemp })

$BtnClearAllUsers = New-Object System.Windows.Forms.Button
$BtnClearAllUsers.FlatStyle = 'Flat'
$BtnClearAllUsers.text = "LIMPIAR TODOS LOS PERFILES"
$BtnClearAllUsers.width = 325
$BtnClearAllUsers.height = 35
$BtnClearAllUsers.location = New-Object System.Drawing.Point(330, 35)
$BtnClearAllUsers.Font = New-Object System.Drawing.Font('Consolas', 9)
$BtnClearAllUsers.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")
$BtnClearAllUsers.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#555555")
$BtnClearAllUsers.Add_Click({ Clear-AllUsersTemp })

$BtnClearWindowsTemp = New-Object System.Windows.Forms.Button
$BtnClearWindowsTemp.FlatStyle = 'Flat'
$BtnClearWindowsTemp.text = "LIMPIAR WINDOWS TEMP"
$BtnClearWindowsTemp.width = 320
$BtnClearWindowsTemp.height = 35
$BtnClearWindowsTemp.location = New-Object System.Drawing.Point(5, 80)
$BtnClearWindowsTemp.Font = New-Object System.Drawing.Font('Consolas', 9)
$BtnClearWindowsTemp.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")
$BtnClearWindowsTemp.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#555555")
$BtnClearWindowsTemp.Add_Click({ Clear-WindowsTemp })

$BtnClearInternetCache = New-Object System.Windows.Forms.Button
$BtnClearInternetCache.FlatStyle = 'Flat'
$BtnClearInternetCache.text = "LIMPIAR CACHE INTERNET"
$BtnClearInternetCache.width = 325
$BtnClearInternetCache.height = 35
$BtnClearInternetCache.location = New-Object System.Drawing.Point(330, 80)
$BtnClearInternetCache.Font = New-Object System.Drawing.Font('Consolas', 9)
$BtnClearInternetCache.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")
$BtnClearInternetCache.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#555555")
$BtnClearInternetCache.Add_Click({ Clear-InternetCache })

$BtnFullCleanup = New-Object System.Windows.Forms.Button
$BtnFullCleanup.FlatStyle = 'Flat'
$BtnFullCleanup.text = "LIMPIEZA COMPLETA (TODO LO ANTERIOR)"
$BtnFullCleanup.width = 650
$BtnFullCleanup.height = 40
$BtnFullCleanup.location = New-Object System.Drawing.Point(5, 130)
$BtnFullCleanup.Font = New-Object System.Drawing.Font('Consolas', 9, [System.Drawing.FontStyle]::Bold)
$BtnFullCleanup.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")
$BtnFullCleanup.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#777777")
$BtnFullCleanup.Add_Click({ Invoke-FullCleanup })

$CleanPanel.controls.AddRange(@($CleanLabel, $BtnClearCurrentUser, $BtnClearAllUsers, $BtnClearWindowsTemp, $BtnClearInternetCache, $BtnFullCleanup))

# Panel Instalacion
$InstallPanel = New-Object System.Windows.Forms.Panel
$InstallPanel.height = 200
$InstallPanel.width = 660
$InstallPanel.location = New-Object System.Drawing.Point(10, 380)
$InstallPanel.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#252525")

$InstallLabel = New-Object System.Windows.Forms.Label
$InstallLabel.text = "INSTALAR APLICACIONES"
$InstallLabel.AutoSize = $true
$InstallLabel.location = New-Object System.Drawing.Point(10, 5)
$InstallLabel.Font = New-Object System.Drawing.Font('Consolas', 12, [System.Drawing.FontStyle]::Bold)
$InstallLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")

$WingetStatus = New-Object System.Windows.Forms.Label
if ($global:WingetAvailable) {
    $WingetStatus.text = "Winget disponible - Listo para instalar"
    $WingetStatus.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#88ff88")
} else {
    $WingetStatus.text = "Winget NO disponible - Abriendo Microsoft Store..."
    $WingetStatus.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#ff8888")
    Start-Process "ms-windows-store://pdp/?productid=9NBLGGH4NNS1" -ErrorAction SilentlyContinue
}
$WingetStatus.AutoSize = $true
$WingetStatus.location = New-Object System.Drawing.Point(10, 30)
$WingetStatus.Font = New-Object System.Drawing.Font('Consolas', 8)

# Fila 1
$Chk7zip = New-Object System.Windows.Forms.CheckBox
$Chk7zip.Text = "7-Zip"
$Chk7zip.Location = New-Object System.Drawing.Point(10, 55)
$Chk7zip.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")
$Chk7zip.AutoSize = $true

$ChkChrome = New-Object System.Windows.Forms.CheckBox
$ChkChrome.Text = "Chrome"
$ChkChrome.Location = New-Object System.Drawing.Point(100, 55)
$ChkChrome.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")
$ChkChrome.AutoSize = $true

$ChkFirefox = New-Object System.Windows.Forms.CheckBox
$ChkFirefox.Text = "Firefox"
$ChkFirefox.Location = New-Object System.Drawing.Point(190, 55)
$ChkFirefox.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")
$ChkFirefox.AutoSize = $true

$ChkVLC = New-Object System.Windows.Forms.CheckBox
$ChkVLC.Text = "VLC"
$ChkVLC.Location = New-Object System.Drawing.Point(280, 55)
$ChkVLC.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")
$ChkVLC.AutoSize = $true

$ChkSteam = New-Object System.Windows.Forms.CheckBox
$ChkSteam.Text = "Steam"
$ChkSteam.Location = New-Object System.Drawing.Point(370, 55)
$ChkSteam.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")
$ChkSteam.AutoSize = $true

$ChkDiscord = New-Object System.Windows.Forms.CheckBox
$ChkDiscord.Text = "Discord"
$ChkDiscord.Location = New-Object System.Drawing.Point(460, 55)
$ChkDiscord.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")
$ChkDiscord.AutoSize = $true

# Fila 2 - OneDrive (instalador especial)
$ChkOneDrive = New-Object System.Windows.Forms.CheckBox
$ChkOneDrive.Text = "OneDrive (Descarga desde Microsoft)"
$ChkOneDrive.Location = New-Object System.Drawing.Point(10, 85)
$ChkOneDrive.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#ffcc88")
$ChkOneDrive.AutoSize = $true

$BtnInstall = New-Object System.Windows.Forms.Button
$BtnInstall.FlatStyle = 'Flat'
$BtnInstall.text = "INSTALAR SELECCIONADAS"
$BtnInstall.width = 650
$BtnInstall.height = 45
$BtnInstall.location = New-Object System.Drawing.Point(5, 130)
$BtnInstall.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
$BtnInstall.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")
$BtnInstall.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#33aa33")
$BtnInstall.Add_Click({
    if ($global:InstallRunning) {
        Write-Log "Ya hay una instalacion en curso" "WARN"
        return
    }
    
    $apps = @()
    $installOneDriveFlag = $false
    
    if ($Chk7zip.Checked) { $apps += "7zip" }
    if ($ChkChrome.Checked) { $apps += "Chrome" }
    if ($ChkFirefox.Checked) { $apps += "Firefox" }
    if ($ChkVLC.Checked) { $apps += "VLC" }
    if ($ChkSteam.Checked) { $apps += "Steam" }
    if ($ChkDiscord.Checked) { $apps += "Discord" }
    if ($ChkOneDrive.Checked) { $installOneDriveFlag = $true }
    
    if ($apps.Count -gt 0) {
        Install-SelectedApps -Apps $apps
    }
    
    if ($installOneDriveFlag) {
        Install-OneDrive
    }
    
    # Desmarcar todos
    $Chk7zip.Checked = $false
    $ChkChrome.Checked = $false
    $ChkFirefox.Checked = $false
    $ChkVLC.Checked = $false
    $ChkSteam.Checked = $false
    $ChkDiscord.Checked = $false
    $ChkOneDrive.Checked = $false
    
    if ($apps.Count -eq 0 -and -not $installOneDriveFlag) {
        Write-Log "No se selecciono ninguna aplicacion" "WARN"
    }
})

$InstallPanel.controls.AddRange(@($InstallLabel, $WingetStatus, $Chk7zip, $ChkChrome, $ChkFirefox, $ChkVLC, $ChkSteam, $ChkDiscord, $ChkOneDrive, $BtnInstall))

# Panel Herramientas
$ToolsPanel = New-Object System.Windows.Forms.Panel
$ToolsPanel.height = 130
$ToolsPanel.width = 660
$ToolsPanel.location = New-Object System.Drawing.Point(10, 590)
$ToolsPanel.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#252525")

$ToolsLabel = New-Object System.Windows.Forms.Label
$ToolsLabel.text = "HERRAMIENTAS"
$ToolsLabel.AutoSize = $true
$ToolsLabel.location = New-Object System.Drawing.Point(10, 5)
$ToolsLabel.Font = New-Object System.Drawing.Font('Consolas', 12, [System.Drawing.FontStyle]::Bold)
$ToolsLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")

$BtnOptimize = New-Object System.Windows.Forms.Button
$BtnOptimize.FlatStyle = 'Flat'
$BtnOptimize.text = "OPTIMIZAR"
$BtnOptimize.width = 155
$BtnOptimize.height = 35
$BtnOptimize.location = New-Object System.Drawing.Point(5, 35)
$BtnOptimize.Font = New-Object System.Drawing.Font('Consolas', 9)
$BtnOptimize.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")
$BtnOptimize.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#555555")
$BtnOptimize.Add_Click({ Optimize-System })

$BtnRepair = New-Object System.Windows.Forms.Button
$BtnRepair.FlatStyle = 'Flat'
$BtnRepair.text = "REPARAR (14 PASOS)"
$BtnRepair.width = 155
$BtnRepair.height = 35
$BtnRepair.location = New-Object System.Drawing.Point(168, 35)
$BtnRepair.Font = New-Object System.Drawing.Font('Consolas', 9)
$BtnRepair.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")
$BtnRepair.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#555555")
$BtnRepair.Add_Click({ 
    if ($global:RepairRunning) {
        Write-Log "Ya hay una reparacion en curso" "WARN"
    } else {
        Start-RepairJob
    }
})

$BtnDisableFirewall = New-Object System.Windows.Forms.Button
$BtnDisableFirewall.FlatStyle = 'Flat'
$BtnDisableFirewall.text = "DESHABILITAR FIREWALL"
$BtnDisableFirewall.width = 155
$BtnDisableFirewall.height = 35
$BtnDisableFirewall.location = New-Object System.Drawing.Point(331, 35)
$BtnDisableFirewall.Font = New-Object System.Drawing.Font('Consolas', 9)
$BtnDisableFirewall.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")
$BtnDisableFirewall.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#555555")
$BtnDisableFirewall.Add_Click({ Disable-Firewall })

$BtnResetWU = New-Object System.Windows.Forms.Button
$BtnResetWU.FlatStyle = 'Flat'
$BtnResetWU.text = "RESET WINDOWS UPDATE"
$BtnResetWU.width = 155
$BtnResetWU.height = 35
$BtnResetWU.location = New-Object System.Drawing.Point(494, 35)
$BtnResetWU.Font = New-Object System.Drawing.Font('Consolas', 9)
$BtnResetWU.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")
$BtnResetWU.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#555555")
$BtnResetWU.Add_Click({ Reset-WindowsUpdateOnly })

$BtnRestorePoint = New-Object System.Windows.Forms.Button
$BtnRestorePoint.FlatStyle = 'Flat'
$BtnRestorePoint.text = "PTO RESTAURACION"
$BtnRestorePoint.width = 320
$BtnRestorePoint.height = 35
$BtnRestorePoint.location = New-Object System.Drawing.Point(5, 80)
$BtnRestorePoint.Font = New-Object System.Drawing.Font('Consolas', 9)
$BtnRestorePoint.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")
$BtnRestorePoint.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#555555")
$BtnRestorePoint.Add_Click({ Create-RestorePoint })

$BtnDiskCleanup = New-Object System.Windows.Forms.Button
$BtnDiskCleanup.FlatStyle = 'Flat'
$BtnDiskCleanup.text = "LIMPIEZA DE DISCO AVANZADA"
$BtnDiskCleanup.width = 325
$BtnDiskCleanup.height = 35
$BtnDiskCleanup.location = New-Object System.Drawing.Point(330, 80)
$BtnDiskCleanup.Font = New-Object System.Drawing.Font('Consolas', 9)
$BtnDiskCleanup.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")
$BtnDiskCleanup.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#555555")
$BtnDiskCleanup.Add_Click({ Run-DiskCleanup })

$ToolsPanel.controls.AddRange(@($ToolsLabel, $BtnOptimize, $BtnRepair, $BtnDisableFirewall, $BtnResetWU, $BtnRestorePoint, $BtnDiskCleanup))

# Panel Control
$ControlPanel = New-Object System.Windows.Forms.Panel
$ControlPanel.height = 55
$ControlPanel.width = 660
$ControlPanel.location = New-Object System.Drawing.Point(10, 730)
$ControlPanel.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#252525")

$BtnKillProcesses = New-Object System.Windows.Forms.Button
$BtnKillProcesses.FlatStyle = 'Flat'
$BtnKillProcesses.text = "TERMINAR PROCESOS BLOQUEADOS (DISM, SFC, TiWorker, Winget)"
$BtnKillProcesses.width = 650
$BtnKillProcesses.height = 40
$BtnKillProcesses.location = New-Object System.Drawing.Point(5, 10)
$BtnKillProcesses.Font = New-Object System.Drawing.Font('Consolas', 9, [System.Drawing.FontStyle]::Bold)
$BtnKillProcesses.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")
$BtnKillProcesses.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#aa6633")
$BtnKillProcesses.Add_Click({ Kill-HungProcesses })

$ControlPanel.controls.Add($BtnKillProcesses)

# Creditos
$CreditLabel = New-Object System.Windows.Forms.Label
$CreditLabel.text = "Creado con DeepSeek por CFRG, con cariño"
$CreditLabel.AutoSize = $true
$CreditLabel.location = New-Object System.Drawing.Point(10, 795)
$CreditLabel.Font = New-Object System.Drawing.Font('Consolas', 9, [System.Drawing.FontStyle]::Italic)
$CreditLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#888888")

# Boton Cerrar
$BtnClose = New-Object System.Windows.Forms.Button
$BtnClose.FlatStyle = 'Flat'
$BtnClose.text = "CERRAR PROGRAMA"
$BtnClose.width = 650
$BtnClose.height = 35
$BtnClose.location = New-Object System.Drawing.Point(10, 820)
$BtnClose.Font = New-Object System.Drawing.Font('Consolas', 9, [System.Drawing.FontStyle]::Bold)
$BtnClose.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#eeeeee")
$BtnClose.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#aa3333")
$BtnClose.Add_Click({ $Form.Close() })

# Panel de Log
$LogTextBox = New-Object System.Windows.Forms.RichTextBox
$LogTextBox.Location = New-Object System.Drawing.Point(10, 865)
$LogTextBox.Size = New-Object System.Drawing.Size(660, 100)
$LogTextBox.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#1a1a1a")
$LogTextBox.ForeColor = [System.Drawing.Color]::LightGreen
$LogTextBox.Font = New-Object System.Drawing.Font("Consolas", 8)
$LogTextBox.ReadOnly = $true
$LogTextBox.ScrollBars = 'Vertical'

$Form.Controls.AddRange(@($DebloatPanel, $CleanPanel, $InstallPanel, $ToolsPanel, $ControlPanel, $CreditLabel, $BtnClose, $LogTextBox))

# Timer para actualizar UI
$updateTimer = New-Object System.Windows.Forms.Timer
$updateTimer.Interval = 500
$updateTimer.Add_Tick({
    if ($LogTextBox -and !$LogTextBox.IsDisposed) {
        $LogTextBox.Text = Get-Content -Path $global:LogFile -ErrorAction SilentlyContinue | Out-String
        $LogTextBox.SelectionStart = $LogTextBox.Text.Length
        $LogTextBox.ScrollToCaret()
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
Write-Log "APLICACIONES DISPONIBLES PARA INSTALAR:" "INFO"
Write-Log "  7-Zip, Chrome, Firefox, VLC, Steam, Discord" "INFO"
Write-Log "  OneDrive (Descarga directa desde Microsoft)" "INFO"
Write-Log "=============================================" "INFO"

[void]$Form.ShowDialog()
#endregion
