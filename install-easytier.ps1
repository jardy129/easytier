#requires -version 5.1
param(
    [switch]$Help
)

$ErrorActionPreference = "Stop"

$DefaultVersion = "2.6.4"
$DefaultUsername = "jardy"
$DefaultDomain = "192.168.2.2"
$DefaultPort = "22020"
$DefaultWebPort = "11211"
$DefaultProtocol = "udp"
$CoreService = "easytier-core"
$WebService = "easytier-web-embed"

function Write-Info($Message) { Write-Host $Message -ForegroundColor Cyan }
function Write-Success($Message) { Write-Host $Message -ForegroundColor Green }
function Write-Warn($Message) { Write-Host $Message -ForegroundColor Yellow }
function Write-Fail($Message) { Write-Host $Message -ForegroundColor Red }

function Show-Help {
    @"
Usage:
  powershell -ExecutionPolicy Bypass -File .\install-easytier.ps1

This script installs EasyTier Core and EasyTier Web Embed as Windows services.
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
        Write-Host "4) Exit"
        Write-Host "========================================"
        $choice = Read-Host "Choose target system [1-4]"
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
            "4" { exit 0 }
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

function Download-Install($Version, $Platform, $InstallDir, $InstallCore, $InstallWeb) {
    $asset = "easytier-windows-$Platform-v$Version.zip"
    $url = "https://github.com/EasyTier/EasyTier/releases/download/v$Version/$asset"
    $zipPath = Join-Path $env:TEMP $asset
    $extractDir = Join-Path $env:TEMP "easytier-windows-$Platform"

    Write-Info "Downloading $url"
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    Invoke-WebRequest -Uri $url -OutFile $zipPath
    Expand-Archive -LiteralPath $zipPath -DestinationPath $env:TEMP -Force

    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

    if ($InstallCore) {
        $src = Join-Path $extractDir "easytier-core.exe"
        if (-not (Test-Path $src)) { throw "Cannot find easytier-core.exe in package." }
        Copy-Item $src (Join-Path $InstallDir "easytier-core.exe") -Force
    }

    if ($InstallWeb) {
        $src = Join-Path $extractDir "easytier-web-embed.exe"
        if (-not (Test-Path $src)) { throw "Cannot find easytier-web-embed.exe in package." }
        Copy-Item $src (Join-Path $InstallDir "easytier-web-embed.exe") -Force
    }

    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
}

function Install-EasyTier {
    $platform = Get-WindowsPlatform
    $installDir = Prompt-Default "Install directory" "C:\easytier"
    $version = Prompt-Default "EasyTier version" $DefaultVersion
    $username = Prompt-Default "Username" $DefaultUsername
    $domain = Prompt-Default "Config server domain/IP, without udp:// and without /username" $DefaultDomain
    $port = Prompt-Default "Config server port" $DefaultPort
    $hostnameValue = Prompt-Default "Hostname" $env:COMPUTERNAME
    $webPort = Prompt-Default "Web/API port" $DefaultWebPort
    $protocol = Prompt-Default "Config server protocol" $DefaultProtocol
    $installWeb = Prompt-YesNo "Install easytier-web-embed service?" "y"
    $installCore = Prompt-YesNo "Install easytier-core service?" "y"

    if (-not $installWeb -and -not $installCore) {
        throw "Nothing selected to install."
    }

    $asset = "easytier-windows-$platform-v$version.zip"
    $configServer = "${protocol}://${domain}:${port}/${username}"
    $webApiHost = "http://127.0.0.1:$webPort"

    Write-Host ""
    Write-Host "========== Confirm Installation =========="
    Write-Host "Target OS:          windows"
    Write-Host "Architecture:       $platform"
    Write-Host "Download package:   $asset"
    Write-Host "Install directory:  $installDir"
    Write-Host "Username:           $username"
    Write-Host "Config server:      $configServer"
    Write-Host "Hostname:           $hostnameValue"
    Write-Host "Web/API port:       $webPort"
    Write-Host "Web API host:       $webApiHost"
    Write-Host "Install Web Embed:  $installWeb"
    Write-Host "Install Core:       $installCore"
    Write-Host "=========================================="
    Write-Host ""

    if (-not (Prompt-YesNo "Confirm and start installation?" "n")) {
        Write-Warn "Installation cancelled."
        exit 0
    }

    Stop-RemoveService $CoreService
    Stop-RemoveService $WebService
    Download-Install -Version $version -Platform $platform -InstallDir $installDir -InstallCore:$installCore -InstallWeb:$installWeb

    if ($installWeb) {
        $webExe = Join-Path $installDir "easytier-web-embed.exe"
        $dbPath = Join-Path $installDir "et.db"
        $webArgs = @(
            Quote-Arg $webExe,
            "--db", Quote-Arg $dbPath,
            "--api-server-port", $webPort,
            "--api-server-addr", "0.0.0.0",
            "--api-host", Quote-Arg $webApiHost,
            "--config-server-port", $port,
            "--config-server-protocol", $protocol
        ) -join " "
        New-Service -Name $WebService -BinaryPathName $webArgs -DisplayName "EasyTier Web Embed" -StartupType Automatic | Out-Null
        Start-Service -Name $WebService
    }

    if ($installCore) {
        $coreExe = Join-Path $installDir "easytier-core.exe"
        $coreArgs = @(
            Quote-Arg $coreExe,
            "--config-server", Quote-Arg $configServer,
            "--hostname", Quote-Arg $hostnameValue,
            "--machine-id", Quote-Arg $hostnameValue
        ) -join " "
        New-Service -Name $CoreService -BinaryPathName $coreArgs -DisplayName "EasyTier Core" -StartupType Automatic | Out-Null
        Start-Service -Name $CoreService
    }

    Write-Success "Installation completed."
    Write-Host "Check:"
    Write-Host "  Get-Service easytier-core,easytier-web-embed"
}

if ($Help) {
    Show-Help
    exit 0
}

Assert-Admin
Main-Menu
Install-EasyTier
