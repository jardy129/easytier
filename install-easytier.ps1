#requires -version 5.1
param(
    [switch]$Help,
    [switch]$Uninstall,
    [switch]$Yes,
    [string]$Target = "",
    [string]$InstallDir = "",
    [string]$Version = "",
    [string]$Username = "",
    [string]$Domain = "",
    [string]$Port = "",
    [string]$Hostname = "",
    [string]$Protocol = ""
)

$ErrorActionPreference = "Stop"

$DefaultVersion = "2.6.4"
$DefaultUsername = "your-user"
$DefaultDomain = "your-server.example.com"
$DefaultPort = "22020"
$DefaultProtocol = "udp"
$CoreService = "easytier-core"
$LegacyWebService = "easytier-web-embed"

function Write-Info($Message) { Write-Host $Message -ForegroundColor Cyan }
function Write-Success($Message) { Write-Host $Message -ForegroundColor Green }
function Write-Warn($Message) { Write-Host $Message -ForegroundColor Yellow }
function Write-Fail($Message) { Write-Host $Message -ForegroundColor Red }

function Show-Help {
    @"
Usage:
  powershell -ExecutionPolicy Bypass -File .\install-easytier.ps1
  powershell -ExecutionPolicy Bypass -File .\install-easytier.ps1 -Yes -Target Windows -Username your-user -Domain your-server.example.com -Port 22020 -Hostname your-windows-node
  powershell -ExecutionPolicy Bypass -File .\install-easytier.ps1 -Yes -Uninstall

Installs only these files into the install directory:
  easytier-core.exe
  easytier-cli.exe
"@ | Write-Host
}

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Fail "Please run PowerShell as Administrator."
        exit 1
    }
}

function Prompt-Default($Question, $Default) {
    $answer = Read-Host "$Question [$Default]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer
}

function Prompt-YesNo($Question, $Default) {
    while ($true) {
        $answer = Read-Host "$Question [$Default]"
        if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $Default }
        switch -Regex ($answer) {
            "^(y|yes|Y|YES)$" { return $true }
            "^(n|no|N|NO)$" { return $false }
            default { Write-Warn "Please enter y or n." }
        }
    }
}

function Main-Menu {
    while ($true) {
        Write-Host ""
        Write-Host "========== EasyTier Installer =========="
        Write-Host "1) Mac"
        Write-Host "2) Linux"
        Write-Host "3) Windows"
        Write-Host "4) Thorough uninstall on this machine"
        Write-Host "5) Exit"
        Write-Host "========================================"
        $choice = Read-Host "Choose option [1-5]"
        switch ($choice) {
            "1" {
                Write-Warn "Mac installation should be run on macOS:"
                Write-Host "  sudo ./install-easytier.sh"
                exit 0
            }
            "2" {
                Write-Warn "Linux installation should be run on Linux:"
                Write-Host "  sudo ./install-easytier.sh"
                exit 0
            }
            "3" { return }
            "4" { $script:Uninstall = $true; return }
            "5" { exit 0 }
            default { Write-Warn "Invalid option." }
        }
    }
}

function Get-WindowsPlatform {
    $arch = (Get-CimInstance Win32_OperatingSystem).OSArchitecture
    if ($arch -match "ARM64") { return "arm64" }
    if ($arch -match "64") { return "x86_64" }
    return "i686"
}

function Stop-RemoveService($Name) {
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($null -ne $svc) {
        if ($svc.Status -ne "Stopped") {
            Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        }
        sc.exe delete $Name | Out-Null
        Start-Sleep -Seconds 1
    }
}

function Quote-Arg($Value) {
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Collect-Config {
    if ($Yes) {
        if ([string]::IsNullOrWhiteSpace($InstallDir)) { $script:InstallDir = "C:\easytier" }
        if ([string]::IsNullOrWhiteSpace($Version)) { $script:Version = $DefaultVersion }
        if ([string]::IsNullOrWhiteSpace($Username)) { $script:Username = $DefaultUsername }
        if ([string]::IsNullOrWhiteSpace($Domain)) { $script:Domain = $DefaultDomain }
        if ([string]::IsNullOrWhiteSpace($Port)) { $script:Port = $DefaultPort }
        if ([string]::IsNullOrWhiteSpace($Hostname)) { $script:Hostname = $env:COMPUTERNAME }
        if ([string]::IsNullOrWhiteSpace($Protocol)) { $script:Protocol = $DefaultProtocol }
    } else {
        $script:InstallDir = Prompt-Default "Install directory" "C:\easytier"
        $script:Version = Prompt-Default "EasyTier version" $DefaultVersion
        $script:Username = Prompt-Default "Username" $DefaultUsername
        $script:Domain = Prompt-Default "Config server domain/IP, without protocol and username" $DefaultDomain
        $script:Port = Prompt-Default "Config server port" $DefaultPort
        $script:Hostname = Prompt-Default "Hostname" $env:COMPUTERNAME
        $script:Protocol = Prompt-Default "Config server protocol" $DefaultProtocol
    }
}

function Confirm-Config($Platform) {
    $asset = "easytier-windows-$Platform-v$Version.zip"
    $configServer = "${Protocol}://${Domain}:${Port}/${Username}"

    Write-Host ""
    Write-Host "========== Confirm Installation =========="
    Write-Host "Target OS:          windows"
    Write-Host "Architecture:       $Platform"
    Write-Host "Download package:   $asset"
    Write-Host "Install directory:  $InstallDir"
    Write-Host "Files kept:         easytier-core.exe, easytier-cli.exe"
    Write-Host "Username:           $Username"
    Write-Host "Config server:      $configServer"
    Write-Host "Hostname:           $Hostname"
    Write-Host "=========================================="
    Write-Host ""

    if (-not $Yes -and -not (Prompt-YesNo "Confirm and start installation?" "n")) {
        Write-Warn "Installation cancelled."
        exit 0
    }
}

function Download-Install($Platform) {
    $asset = "easytier-windows-$Platform-v$Version.zip"
    $url = "https://github.com/EasyTier/EasyTier/releases/download/v$Version/$asset"
    $zipPath = Join-Path $env:TEMP $asset
    $extractDir = Join-Path $env:TEMP "easytier-windows-$Platform"

    Write-Info "Downloading $url"
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    Invoke-WebRequest -Uri $url -OutFile $zipPath
    Expand-Archive -LiteralPath $zipPath -DestinationPath $env:TEMP -Force

    Write-Info "Preparing install directory $InstallDir..."
    Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

    Copy-Item (Join-Path $extractDir "easytier-core.exe") (Join-Path $InstallDir "easytier-core.exe") -Force
    Copy-Item (Join-Path $extractDir "easytier-cli.exe") (Join-Path $InstallDir "easytier-cli.exe") -Force

    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
}

function Install-EasyTier {
    $platform = Get-WindowsPlatform
    Collect-Config
    Confirm-Config $platform

    Stop-RemoveService $CoreService
    Stop-RemoveService $LegacyWebService
    Download-Install $platform

    $coreExe = Join-Path $InstallDir "easytier-core.exe"
    $configServer = "${Protocol}://${Domain}:${Port}/${Username}"
    $coreArgs = @(
        Quote-Arg $coreExe,
        "--config-server", Quote-Arg $configServer,
        "--hostname", Quote-Arg $Hostname,
        "--machine-id", Quote-Arg $Hostname
    ) -join " "

    New-Service -Name $CoreService -BinaryPathName $coreArgs -DisplayName "EasyTier Core" -StartupType Automatic | Out-Null
    Start-Service -Name $CoreService

    Write-Success "Installation completed."
    Write-Host "Install directory contains:"
    Get-ChildItem -LiteralPath $InstallDir
    Write-Host "Check:"
    Write-Host "  Get-Service easytier-core"
}

function Uninstall-EasyTier {
    if ([string]::IsNullOrWhiteSpace($InstallDir)) { $InstallDir = "C:\easytier" }
    if (-not $Yes) {
        $script:InstallDir = Prompt-Default "Install directory to delete" $InstallDir
        if (-not (Prompt-YesNo "Confirm full uninstall and delete $InstallDir ?" "n")) {
            Write-Warn "Uninstall cancelled."
            exit 0
        }
    }

    Write-Info "Stopping and deleting Windows EasyTier services..."
    Stop-RemoveService $CoreService
    Stop-RemoveService $LegacyWebService

    Write-Info "Deleting $InstallDir..."
    Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Success "EasyTier has been fully uninstalled from Windows."
}

if ($Help) {
    Show-Help
    exit 0
}

Assert-Admin
if ($Yes) {
    if (-not [string]::IsNullOrWhiteSpace($Target) -and $Target -notmatch "^(Windows|windows|win)$") {
        Write-Fail "This PowerShell installer only supports Windows. Use install-easytier.sh for macOS/Linux."
        exit 1
    }
} else {
    Main-Menu
}

if ($Uninstall) {
    Uninstall-EasyTier
} else {
    Install-EasyTier
}
