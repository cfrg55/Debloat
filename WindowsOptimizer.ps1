<#
.SYNOPSIS
    Windows 10/11 Optimizer & Debloater GUI v6.3 - Tamaño Reducido
.DESCRIPTION
    Herramienta completa para optimizar Windows 10/11 (22H2-24H2)
    Versión con interfaz compacta para monitores pequeños
.NOTES
    Compatible: Windows 10 20H2+, Windows 11 22H2/23H2/24H2
    1009
#>

#region [INICIALIZACION]
$ErrorActionPreference = 'Continue'
$global:ScriptVersion = "6.3"
$global:CurrentJob = $null
$global:RepairRunning = $false
$global:RepairTimer = $null
$global:InstallRunning = $false

# Auto-elevacion (simplificada)
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process PowerShell.exe -ArgumentList $arguments -Verb RunAs
    exit
}

# Detectar version
$global:WindowsVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ProductName
$global:WindowsBuild = [Environment]::OSVersion.Version.Build
$global:IsWindows11 = $global:WindowsBuild -ge 22000
$global:Is24H2 = $global:WindowsBuild -ge 26100

# Verificar Winget
$global:WingetAvailable = $false
try { if (Get-Command winget -ErrorAction SilentlyContinue) { $global:WingetAvailable = $true } } catch { }

# Directorios
$global:LogDir = "C:\Temp\WindowsOptimizer"
$global:DownloadDir = "$global:LogDir\Downloads"
New-Item -Path $global:LogDir -ItemType Directory -Force | Out-Null
New-Item -Path $global:DownloadDir -ItemType Directory -Force | Out-Null

$global:LogFile = "$global:LogDir\optimizer_log.txt"
if (Test-Path $global:LogFile) { Remove-Item $global:LogFile -Force }

function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [$Type] $Message"
    Add-Content -Path $global:LogFile -Value $logEntry
    Write-Host $logEntry
    if ($global:LogTextBox -and !$global:LogTextBox.IsDisposed) {
        $global:LogTextBox.Text = Get-Content -Path $global:LogFile -ErrorAction SilentlyContinue | Out-String
        $global:LogTextBox.SelectionStart = $global:LogTextBox.Text.Length
        $global:LogTextBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }
}
#endregion

#region [LISTAS DE BLOATWARE - REDUCIDAS]
$global:Bloatware = @(
    "Microsoft.BingNews", "Microsoft.BingWeather", "Microsoft.GetHelp", "Microsoft.Getstarted"
    "Microsoft.Microsoft3DViewer", "Microsoft.MicrosoftOfficeHub", "Microsoft.MicrosoftSolitaireCollection"
    "Microsoft.MixedReality.Portal", "Microsoft.Office.OneNote", "Microsoft.People", "Microsoft.Print3D"
    "Microsoft.SkypeApp", "Microsoft.WindowsAlarms", "Microsoft.WindowsFeedbackHub", "Microsoft.WindowsMaps"
    "Microsoft.Xbox.TCUI", "Microsoft.XboxApp", "Microsoft.XboxGameOverlay", "Microsoft.XboxGamingOverlay"
    "Microsoft.XboxIdentityProvider", "Microsoft.YourPhone", "Microsoft.ZuneMusic", "Microsoft.ZuneVideo"
    "CandyCrush", "Facebook", "Twitter", "Spotify", "Netflix", "Disney"
    "MicrosoftTeams", "MicrosoftTeams_8wekyb3d8bbwe"
)
if ($global:Is24H2) { $global:Bloatware += @("Microsoft.Windows.AI.Copilot", "Microsoft.Copilot", "Microsoft.Windows.Recall") }
$global:BloatwareRegex = $global:Bloatware -join '|'
#endregion

#region [FUNCIONES - VERSION COMPACTA]
function Clear-CurrentUserTemp {
    Write-Log "Limpiando Temp del usuario actual..." "TASK"
    if (Test-Path "$env:TEMP") { 
        Get-ChildItem "$env:TEMP" -Recurse -EA 0 | Where-Object { !$_.PSIsContainer } | Remove-Item -Force -EA 0
        Write-Log "Limpieza de Temp completada" "OK"
    }
}

function Clear-AllUsersTemp {
    Write-Log "Limpiando Temp de todos los usuarios..." "TASK"
    Get-ChildItem "C:\Users" -Directory -EA 0 | ForEach-Object {
        $tp = Join-Path $_.FullName "AppData\Local\Temp"
        if (Test-Path $tp) { Get-ChildItem $tp -Recurse -EA 0 | Where-Object { !$_.PSIsContainer } | Remove-Item -Force -EA 0 }
    }
    Write-Log "Limpieza completada" "OK"
}

function Clear-WindowsTemp {
    Write-Log "Limpiando Windows Temp..." "TASK"
    if (Test-Path "C:\Windows\Temp") { 
        Get-ChildItem "C:\Windows\Temp" -Recurse -EA 0 | Where-Object { !$_.PSIsContainer } | Remove-Item -Force -EA 0
        Write-Log "Limpieza completada" "OK"
    }
}

function Clear-InternetCache {
    Write-Log "Limpiando cache de Internet..." "TASK"
    RunDll32.exe InetCpl.cpl,ClearMyTracksByProcess 8 2>&1 | Out-Null
    RunDll32.exe InetCpl.cpl,ClearMyTracksByProcess 2 2>&1 | Out-Null
    Write-Log "Cache limpiada" "OK"
}

function Run-DiskCleanup {
    Write-Log "Ejecutando limpieza de disco..." "TASK"
    Cleanmgr.exe /sagerun:64 2>&1 | Out-Null
    Write-Log "Limpieza completada" "OK"
}

function Disable-Firewall {
    Write-Log "Deshabilitando Firewall..." "TASK"
    netsh advfirewall set domainprofile state off 2>&1 | Out-Null
    netsh advfirewall set privateprofile state off 2>&1 | Out-Null
    netsh advfirewall set publicprofile state off 2>&1 | Out-Null
    Write-Log "Firewall deshabilitado" "OK"
}

function Clear-WindowsUpdateCache {
    Write-Log "Limpiando cache de Windows Update..." "TASK"
    net stop bits 2>&1 | Out-Null; net stop wuauserv 2>&1 | Out-Null; net stop cryptsvc 2>&1 | Out-Null
    if (Test-Path "$env:SystemRoot\SoftwareDistribution") { Remove-Item "$env:SystemRoot\SoftwareDistribution\*" -Recurse -Force -EA 0 }
    if (Test-Path "$env:SystemRoot\system32\catroot2") { Remove-Item "$env:SystemRoot\system32\catroot2\*" -Recurse -Force -EA 0 }
    net start bits 2>&1 | Out-Null; net start wuauserv 2>&1 | Out-Null; net start cryptsvc 2>&1 | Out-Null
    Write-Log "Cache limpiada" "OK"
}

function Invoke-FullCleanup {
    Write-Log "========== LIMPIEZA COMPLETA ==========" "TASK"
    Clear-CurrentUserTemp; Clear-AllUsersTemp; Clear-WindowsTemp; Clear-InternetCache; Run-DiskCleanup
    Write-Log "========== LIMPIEZA COMPLETA FINALIZADA ==========" "OK"
}

function Remove-AllBloatware {
    Write-Log "========== ELIMINANDO BLOATWARE ==========" "TASK"
    $removed = 0
    Get-AppxPackage | Where-Object { $_.Name -match $global:BloatwareRegex } | ForEach-Object {
        Remove-AppxPackage -Package $_ -EA 0; $removed++; Write-Log "  Eliminado: $($_.Name)" "OK"
    }
    Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -match $global:BloatwareRegex } | ForEach-Object {
        Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -EA 0
    }
    $tp = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
    if (!(Test-Path $tp)) { New-Item $tp -Force | Out-Null }
    Set-ItemProperty $tp -Name "AllowTelemetry" -Value 0 -EA 0
    $bp = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"
    if (!(Test-Path $bp)) { New-Item $bp -Force | Out-Null }
    Set-ItemProperty $bp -Name "BingSearchEnabled" -Value 0 -EA 0
    Write-Log "========== COMPLETADO: $removed apps eliminadas ==========" "OK"
}

function Remove-OneDrive {
    Write-Log "Desinstalando OneDrive..." "TASK"
    Get-Process "OneDrive*" -EA 0 | Stop-Process -Force
    $uninstaller = "$env:SYSTEMROOT\SysWOW64\OneDriveSetup.exe"
    if (!(Test-Path $uninstaller)) { $uninstaller = "$env:SYSTEMROOT\System32\OneDriveSetup.exe" }
    if (Test-Path $uninstaller) { Start-Process $uninstaller "/uninstall" -NoNewWindow -Wait }
    Write-Log "OneDrive desinstalado" "OK"
}

function Install-OneDrive {
    Write-Log "Instalando OneDrive..." "TASK"
    $url = "https://go.microsoft.com/fwlink/?linkid=2264368"
    $installer = "$global:DownloadDir\OneDriveSetup.exe"
    (New-Object System.Net.WebClient).DownloadFile($url, $installer)
    if (Test-Path $installer) { Start-Process $installer "/silent" -NoNewWindow -Wait; Remove-Item $installer -Force -EA 0 }
    Write-Log "OneDrive instalado" "OK"
}

function Install-SelectedApps {
    param([string[]]$Apps)
    if (-not $global:WingetAvailable) { Write-Log "Winget no disponible" "WARN"; return }
    foreach ($app in $Apps) {
        Write-Log "Instalando: $app..." "INFO"
        switch ($app) {
            "7zip" { winget install --id 7zip.7zip --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null }
            "Chrome" { winget install --id Google.Chrome --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null }
            "Firefox" { winget install --id Mozilla.Firefox --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null }
            "VLC" { winget install --id VideoLAN.VLC --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null }
        }
        Write-Log "  Instalado: $app" "OK"
    }
}

function Optimize-System {
    Write-Log "Optimizando sistema..." "TASK"
    $pp = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    if (!(Test-Path $pp)) { New-Item $pp -Force | Out-Null }
    Set-ItemProperty $pp -Name "SystemResponsiveness" -Value 10 -EA 0
    @("SysMain", "WSearch") | ForEach-Object { Stop-Service $_ -Force -EA 0; Set-Service $_ -StartupType Disabled -EA 0 }
    powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1 | Out-Null
    Write-Log "Optimizacion completada" "OK"
}

function Repair-System {
    Write-Log "========== REPARANDO SISTEMA ==========" "TASK"
    Write-Log "[1/4] DISM CheckHealth..." "INFO"
    dism /Online /Cleanup-Image /CheckHealth 2>&1 | Out-Null
    Write-Log "[2/4] DISM ScanHealth..." "INFO"
    dism /Online /Cleanup-Image /ScanHealth 2>&1 | Out-Null
    Write-Log "[3/4] DISM RestoreHealth..." "INFO"
    dism /Online /Cleanup-Image /RestoreHealth 2>&1 | Out-Null
    Write-Log "[4/4] SFC Scannow..." "INFO"
    sfc /scannow 2>&1 | Out-Null
    Write-Log "========== REPARACION COMPLETADA ==========" "OK"
}

function Reset-WindowsUpdate {
    Write-Log "Reiniciando Windows Update..." "TASK"
    @("bits", "wuauserv", "appidsvc", "cryptsvc") | ForEach-Object { Stop-Service $_ -Force -EA 0 }
    @("$env:SystemRoot\SoftwareDistribution", "$env:SystemRoot\system32\catroot2") | ForEach-Object { 
        if (Test-Path $_) { Remove-Item "$_\*" -Recurse -Force -EA 0 }
    }
    @("bits", "wuauserv", "appidsvc", "cryptsvc") | ForEach-Object { Start-Service $_ -EA 0 }
    Write-Log "Windows Update reiniciado" "OK"
}

function Create-RestorePoint {
    Write-Log "Creando punto de restauracion..." "TASK"
    Checkpoint-Computer -Description "Windows Optimizer" -EA 0
    Write-Log "Punto creado" "OK"
}

function Kill-HungProcesses {
    Write-Log "Terminando procesos bloqueados..." "TASK"
    @("dism", "sfc", "TiWorker", "TrustedInstaller", "OneDrive", "winget") | ForEach-Object {
        Get-Process $_ -EA 0 | Stop-Process -Force -EA 0
    }
    Write-Log "Procesos terminados" "OK"
}
#endregion

#region [INTERFAZ GRAFICA - TAMAÑO REDUCIDO]
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Fuentes
$fontBold = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
$fontNorm = New-Object System.Drawing.Font("Consolas", 8, [System.Drawing.FontStyle]::Regular)
$fontSmall = New-Object System.Drawing.Font("Consolas", 7, [System.Drawing.FontStyle]::Regular)

# Formulario compacto (520x700)
$Form = New-Object System.Windows.Forms.Form
$Form.ClientSize = New-Object System.Drawing.Point(520, 700)
$Form.StartPosition = 'CenterScreen'
$Form.FormBorderStyle = 'FixedSingle'
$Form.MinimizeBox = $false
$Form.MaximizeBox = $false
$Form.ShowIcon = $false
$Form.Text = "Windows Optimizer v$global:ScriptVersion"
$Form.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)

$currentY = 5

# ==================== PANEL DEBLOAT ====================
$DebloatPanel = New-Object System.Windows.Forms.Panel
$DebloatPanel.Size = New-Object System.Drawing.Size(500, 85)
$DebloatPanel.Location = New-Object System.Drawing.Point(10, $currentY)
$DebloatPanel.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)

$lblDebloat = New-Object System.Windows.Forms.Label
$lblDebloat.Text = "ELIMINAR BLOATWARE"
$lblDebloat.Location = New-Object System.Drawing.Point(10, 5)
$lblDebloat.Font = $fontBold
$lblDebloat.ForeColor = [System.Drawing.Color]::White

$btnRemoveAll = New-Object System.Windows.Forms.Button
$btnRemoveAll.Text = "ELIMINAR TODO (Copilot, Teams, Xbox)"
$btnRemoveAll.Size = New-Object System.Drawing.Size(480, 30)
$btnRemoveAll.Location = New-Object System.Drawing.Point(10, 30)
$btnRemoveAll.FlatStyle = 'Flat'
$btnRemoveAll.Font = $fontNorm
$btnRemoveAll.ForeColor = [System.Drawing.Color]::White
$btnRemoveAll.BackColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
$btnRemoveAll.Add_Click({ Remove-AllBloatware })

$btnRemoveOD = New-Object System.Windows.Forms.Button
$btnRemoveOD.Text = "DESINSTALAR ONEDRIVE"
$btnRemoveOD.Size = New-Object System.Drawing.Size(480, 25)
$btnRemoveOD.Location = New-Object System.Drawing.Point(10, 65)
$btnRemoveOD.FlatStyle = 'Flat'
$btnRemoveOD.Font = $fontNorm
$btnRemoveOD.ForeColor = [System.Drawing.Color]::White
$btnRemoveOD.BackColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
$btnRemoveOD.Add_Click({ Remove-OneDrive })

$DebloatPanel.Controls.AddRange(@($lblDebloat, $btnRemoveAll, $btnRemoveOD))
$currentY += 95

# ==================== PANEL LIMPIEZA ====================
$CleanPanel = New-Object System.Windows.Forms.Panel
$CleanPanel.Size = New-Object System.Drawing.Size(500, 140)
$CleanPanel.Location = New-Object System.Drawing.Point(10, $currentY)
$CleanPanel.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)

$lblClean = New-Object System.Windows.Forms.Label
$lblClean.Text = "LIMPIEZA DE ARCHIVOS"
$lblClean.Location = New-Object System.Drawing.Point(10, 5)
$lblClean.Font = $fontBold
$lblClean.ForeColor = [System.Drawing.Color]::White

$btnClearCurrent = New-Object System.Windows.Forms.Button
$btnClearCurrent.Text = "LIMPIAR PERFIL ACTUAL"
$btnClearCurrent.Size = New-Object System.Drawing.Size(245, 28)
$btnClearCurrent.Location = New-Object System.Drawing.Point(10, 30)
$btnClearCurrent.FlatStyle = 'Flat'
$btnClearCurrent.Font = $fontNorm
$btnClearCurrent.ForeColor = [System.Drawing.Color]::White
$btnClearCurrent.BackColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
$btnClearCurrent.Add_Click({ Clear-CurrentUserTemp })

$btnClearAll = New-Object System.Windows.Forms.Button
$btnClearAll.Text = "LIMPIAR TODOS PERFILES"
$btnClearAll.Size = New-Object System.Drawing.Size(245, 28)
$btnClearAll.Location = New-Object System.Drawing.Point(260, 30)
$btnClearAll.FlatStyle = 'Flat'
$btnClearAll.Font = $fontNorm
$btnClearAll.ForeColor = [System.Drawing.Color]::White
$btnClearAll.BackColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
$btnClearAll.Add_Click({ Clear-AllUsersTemp })

$btnClearWinTemp = New-Object System.Windows.Forms.Button
$btnClearWinTemp.Text = "LIMPIAR WINDOWS TEMP"
$btnClearWinTemp.Size = New-Object System.Drawing.Size(245, 28)
$btnClearWinTemp.Location = New-Object System.Drawing.Point(10, 65)
$btnClearWinTemp.FlatStyle = 'Flat'
$btnClearWinTemp.Font = $fontNorm
$btnClearWinTemp.ForeColor = [System.Drawing.Color]::White
$btnClearWinTemp.BackColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
$btnClearWinTemp.Add_Click({ Clear-WindowsTemp })

$btnClearCache = New-Object System.Windows.Forms.Button
$btnClearCache.Text = "LIMPIAR CACHE INTERNET"
$btnClearCache.Size = New-Object System.Drawing.Size(245, 28)
$btnClearCache.Location = New-Object System.Drawing.Point(260, 65)
$btnClearCache.FlatStyle = 'Flat'
$btnClearCache.Font = $fontNorm
$btnClearCache.ForeColor = [System.Drawing.Color]::White
$btnClearCache.BackColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
$btnClearCache.Add_Click({ Clear-InternetCache })

$btnFullClean = New-Object System.Windows.Forms.Button
$btnFullClean.Text = "LIMPIEZA COMPLETA"
$btnFullClean.Size = New-Object System.Drawing.Size(480, 35)
$btnFullClean.Location = New-Object System.Drawing.Point(10, 100)
$btnFullClean.FlatStyle = 'Flat'
$btnFullClean.Font = $fontBold
$btnFullClean.ForeColor = [System.Drawing.Color]::White
$btnFullClean.BackColor = [System.Drawing.Color]::FromArgb(119, 119, 119)
$btnFullClean.Add_Click({ Invoke-FullCleanup })

$CleanPanel.Controls.AddRange(@($lblClean, $btnClearCurrent, $btnClearAll, $btnClearWinTemp, $btnClearCache, $btnFullClean))
$currentY += 150

# ==================== PANEL INSTALACION ====================
$InstallPanel = New-Object System.Windows.Forms.Panel
$InstallPanel.Size = New-Object System.Drawing.Size(500, 100)
$InstallPanel.Location = New-Object System.Drawing.Point(10, $currentY)
$InstallPanel.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)

$lblInstall = New-Object System.Windows.Forms.Label
$lblInstall.Text = "INSTALAR APLICACIONES"
$lblInstall.Location = New-Object System.Drawing.Point(10, 5)
$lblInstall.Font = $fontBold
$lblInstall.ForeColor = [System.Drawing.Color]::White

$chk7zip = New-Object System.Windows.Forms.CheckBox
$chk7zip.Text = "7-Zip"; $chk7zip.Location = New-Object System.Drawing.Point(10, 30); $chk7zip.ForeColor = [System.Drawing.Color]::White; $chk7zip.Font = $fontNorm
$chkChrome = New-Object System.Windows.Forms.CheckBox
$chkChrome.Text = "Chrome"; $chkChrome.Location = New-Object System.Drawing.Point(90, 30); $chkChrome.ForeColor = [System.Drawing.Color]::White; $chkChrome.Font = $fontNorm
$chkFirefox = New-Object System.Windows.Forms.CheckBox
$chkFirefox.Text = "Firefox"; $chkFirefox.Location = New-Object System.Drawing.Point(180, 30); $chkFirefox.ForeColor = [System.Drawing.Color]::White; $chkFirefox.Font = $fontNorm
$chkVLC = New-Object System.Windows.Forms.CheckBox
$chkVLC.Text = "VLC"; $chkVLC.Location = New-Object System.Drawing.Point(270, 30); $chkVLC.ForeColor = [System.Drawing.Color]::White; $chkVLC.Font = $fontNorm
$chkOneDrive = New-Object System.Windows.Forms.CheckBox
$chkOneDrive.Text = "OneDrive"; $chkOneDrive.Location = New-Object System.Drawing.Point(350, 30); $chkOneDrive.ForeColor = [System.Drawing.Color]::White; $chkOneDrive.Font = $fontNorm

$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = "INSTALAR SELECCIONADAS"
$btnInstall.Size = New-Object System.Drawing.Size(480, 35)
$btnInstall.Location = New-Object System.Drawing.Point(10, 60)
$btnInstall.FlatStyle = 'Flat'
$btnInstall.Font = $fontNorm
$btnInstall.ForeColor = [System.Drawing.Color]::White
$btnInstall.BackColor = [System.Drawing.Color]::FromArgb(51, 170, 51)
$btnInstall.Add_Click({
    $apps = @()
    if ($chk7zip.Checked) { $apps += "7zip" }
    if ($chkChrome.Checked) { $apps += "Chrome" }
    if ($chkFirefox.Checked) { $apps += "Firefox" }
    if ($chkVLC.Checked) { $apps += "VLC" }
    if ($apps.Count -gt 0) { Install-SelectedApps -Apps $apps }
    if ($chkOneDrive.Checked) { Install-OneDrive }
    $chk7zip.Checked = $false; $chkChrome.Checked = $false
    $chkFirefox.Checked = $false; $chkVLC.Checked = $false; $chkOneDrive.Checked = $false
})

$InstallPanel.Controls.AddRange(@($lblInstall, $chk7zip, $chkChrome, $chkFirefox, $chkVLC, $chkOneDrive, $btnInstall))
$currentY += 110

# ==================== PANEL HERRAMIENTAS ====================
$ToolsPanel = New-Object System.Windows.Forms.Panel
$ToolsPanel.Size = New-Object System.Drawing.Size(500, 80)
$ToolsPanel.Location = New-Object System.Drawing.Point(10, $currentY)
$ToolsPanel.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)

$lblTools = New-Object System.Windows.Forms.Label
$lblTools.Text = "HERRAMIENTAS"
$lblTools.Location = New-Object System.Drawing.Point(10, 5)
$lblTools.Font = $fontBold
$lblTools.ForeColor = [System.Drawing.Color]::White

$btnOptimize = New-Object System.Windows.Forms.Button
$btnOptimize.Text = "OPTIMIZAR"
$btnOptimize.Size = New-Object System.Drawing.Size(155, 30)
$btnOptimize.Location = New-Object System.Drawing.Point(10, 30)
$btnOptimize.FlatStyle = 'Flat'
$btnOptimize.Font = $fontNorm
$btnOptimize.ForeColor = [System.Drawing.Color]::White
$btnOptimize.BackColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
$btnOptimize.Add_Click({ Optimize-System })

$btnRepair = New-Object System.Windows.Forms.Button
$btnRepair.Text = "REPARAR"
$btnRepair.Size = New-Object System.Drawing.Size(155, 30)
$btnRepair.Location = New-Object System.Drawing.Point(170, 30)
$btnRepair.FlatStyle = 'Flat'
$btnRepair.Font = $fontNorm
$btnRepair.ForeColor = [System.Drawing.Color]::White
$btnRepair.BackColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
$btnRepair.Add_Click({ Repair-System })

$btnResetWU = New-Object System.Windows.Forms.Button
$btnResetWU.Text = "RESET WU"
$btnResetWU.Size = New-Object System.Drawing.Size(155, 30)
$btnResetWU.Location = New-Object System.Drawing.Point(330, 30)
$btnResetWU.FlatStyle = 'Flat'
$btnResetWU.Font = $fontNorm
$btnResetWU.ForeColor = [System.Drawing.Color]::White
$btnResetWU.BackColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
$btnResetWU.Add_Click({ Reset-WindowsUpdate })

$ToolsPanel.Controls.AddRange(@($lblTools, $btnOptimize, $btnRepair, $btnResetWU))
$currentY += 90

# ==================== PANEL CONTROL ====================
$ControlPanel = New-Object System.Windows.Forms.Panel
$ControlPanel.Size = New-Object System.Drawing.Size(500, 45)
$ControlPanel.Location = New-Object System.Drawing.Point(10, $currentY)
$ControlPanel.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)

$btnKill = New-Object System.Windows.Forms.Button
$btnKill.Text = "TERMINAR PROCESOS BLOQUEADOS"
$btnKill.Size = New-Object System.Drawing.Size(480, 35)
$btnKill.Location = New-Object System.Drawing.Point(10, 5)
$btnKill.FlatStyle = 'Flat'
$btnKill.Font = $fontNorm
$btnKill.ForeColor = [System.Drawing.Color]::White
$btnKill.BackColor = [System.Drawing.Color]::FromArgb(170, 102, 51)
$btnKill.Add_Click({ Kill-HungProcesses })

$ControlPanel.Controls.Add($btnKill)
$currentY += 55

# ==================== CREDITOS ====================
$lblCredit = New-Object System.Windows.Forms.Label
$lblCredit.Text = "Creado con DeepSeek por CFRG, con cariño"
$lblCredit.Location = New-Object System.Drawing.Point(10, $currentY)
$lblCredit.Size = New-Object System.Drawing.Size(500, 15)
$lblCredit.Font = New-Object System.Drawing.Font("Consolas", 7, [System.Drawing.FontStyle]::Italic)
$lblCredit.ForeColor = [System.Drawing.Color]::FromArgb(136, 136, 136)
$lblCredit.TextAlign = 'MiddleCenter'
$currentY += 20

# ==================== BOTON CERRAR ====================
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "CERRAR PROGRAMA"
$btnClose.Size = New-Object System.Drawing.Size(480, 30)
$btnClose.Location = New-Object System.Drawing.Point(10, $currentY)
$btnClose.FlatStyle = 'Flat'
$btnClose.Font = $fontNorm
$btnClose.ForeColor = [System.Drawing.Color]::White
$btnClose.BackColor = [System.Drawing.Color]::FromArgb(170, 51, 51)
$btnClose.Add_Click({ $Form.Close() })
$currentY += 40

# ==================== PANEL DE LOG ====================
$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = "REGISTRO"
$lblLog.Location = New-Object System.Drawing.Point(10, $currentY)
$lblLog.Size = New-Object System.Drawing.Size(500, 15)
$lblLog.Font = $fontBold
$lblLog.ForeColor = [System.Drawing.Color]::White
$currentY += 20

$global:LogTextBox = New-Object System.Windows.Forms.RichTextBox
$global:LogTextBox.Location = New-Object System.Drawing.Point(10, $currentY)
$global:LogTextBox.Size = New-Object System.Drawing.Size(500, 100)
$global:LogTextBox.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$global:LogTextBox.ForeColor = [System.Drawing.Color]::LightGreen
$global:LogTextBox.Font = $fontSmall
$global:LogTextBox.ReadOnly = $true
$global:LogTextBox.ScrollBars = 'Vertical'

$Form.Controls.AddRange(@($DebloatPanel, $CleanPanel, $InstallPanel, $ToolsPanel, $ControlPanel, $lblCredit, $btnClose, $lblLog, $global:LogTextBox))

# Timer para actualizar UI
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 500
$timer.Add_Tick({
    if ($global:LogTextBox -and !$global:LogTextBox.IsDisposed -and (Test-Path $global:LogFile)) {
        $global:LogTextBox.Text = Get-Content -Path $global:LogFile -ErrorAction SilentlyContinue | Out-String
        $global:LogTextBox.SelectionStart = $global:LogTextBox.Text.Length
        $global:LogTextBox.ScrollToCaret()
    }
})
$timer.Start()

# Mensaje inicial
Write-Log "=============================================" "INFO"
Write-Log "Windows Optimizer v$global:ScriptVersion" "INFO"
Write-Log "Sistema: $global:WindowsVersion" "INFO"
Write-Log "=============================================" "INFO"
Write-Log "Listo - Selecciona una opcion" "INFO"
Write-Log "=============================================" "INFO"

[void]$Form.ShowDialog()
$timer.Stop()
#endregion
