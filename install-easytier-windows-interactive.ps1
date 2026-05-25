#requires -version 5.1
param(
    [switch]$Uninstall,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

$InstallDir = "C:\Program Files\EasyTier"
$CoreExe = Join-Path $InstallDir "easytier-core.exe"
$WebExe = Join-Path $InstallDir "easytier-web-embed.exe"
$CoreService = "easytier-core"
$WebService = "easytier-web-embed"
$DefaultVersion = "2.4.5"

function Write-Info($Message) { Write-Host $Message -ForegroundColor Cyan }
function Write-Success($Message) { Write-Host $Message -ForegroundColor Green }
function Write-Warn($Message) { Write-Host $Message -ForegroundColor Yellow }
function Write-Fail($Message) { Write-Host $Message -ForegroundColor Red }

function Show-Help {
    @"
Usage:
  powershell -ExecutionPolicy Bypass -File .\install-easytier-windows-interactive.ps1
  powershell -ExecutionPolicy Bypass -File .\install-easytier-windows-interactive.ps1 -Uninstall

Installs EasyTier Core and EasyTier Web Embed as Windows services.
"@ | Write-Host
}

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Fail "请用管理员权限运行 PowerShell。"
        exit 1
    }
}

function Prompt-Default($Question, $Default) {
    $answer = Read-Host "$Question [$Default]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer
}

function Prompt-Required($Question) {
    while ($true) {
        $answer = Read-Host $Question
        if (-not [string]::IsNullOrWhiteSpace($answer)) { return $answer }
        Write-Warn "该项不能为空。"
    }
}

function Prompt-YesNo($Question, $Default) {
    while ($true) {
        $answer = Read-Host "$Question [$Default]"
        if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $Default }
        switch -Regex ($answer) {
            "^(y|yes|Y|YES)$" { return $true }
            "^(n|no|N|NO)$" { return $false }
            default { Write-Warn "请输入 y 或 n。" }
        }
    }
}

function Get-LatestVersion {
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/EasyTier/EasyTier/releases/latest" -TimeoutSec 10
        if ($release.tag_name -match "^v?(\d+\.\d+\.\d+)$") {
            return $Matches[1]
        }
    } catch {
        Write-Warn "无法获取最新版本，将使用默认版本 $DefaultVersion。"
    }
    return $DefaultVersion
}

function Get-Platform {
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

function Uninstall-EasyTier {
    Write-Info "卸载 EasyTier Windows 服务..."
    Stop-RemoveService $CoreService
    Stop-RemoveService $WebService

    if (Prompt-YesNo "是否删除 $InstallDir 下的程序和数据库文件？" "n") {
        Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Remove-Item -LiteralPath $CoreExe -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $WebExe -Force -ErrorAction SilentlyContinue
    }
    Write-Success "卸载完成。"
}

function Download-Install($Version, $InstallCore, $InstallWeb) {
    $platform = Get-Platform
    $asset = "easytier-windows-$platform-v$Version.zip"
    $url = "https://github.com/EasyTier/EasyTier/releases/download/v$Version/$asset"
    $zipPath = Join-Path $env:TEMP $asset
    $extractDir = Join-Path $env:TEMP "easytier-windows-$platform"

    Write-Info "下载 EasyTier $Version ($platform)..."
    Write-Info $url
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    Invoke-WebRequest -Uri $url -OutFile $zipPath
    Expand-Archive -LiteralPath $zipPath -DestinationPath $env:TEMP -Force

    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

    if ($InstallCore) {
        $src = Join-Path $extractDir "easytier-core.exe"
        if (-not (Test-Path $src)) { throw "安装包中未找到 easytier-core.exe" }
        Copy-Item $src $CoreExe -Force
    }

    if ($InstallWeb) {
        $src = Join-Path $extractDir "easytier-web-embed.exe"
        if (-not (Test-Path $src)) { throw "安装包中未找到 easytier-web-embed.exe" }
        Copy-Item $src $WebExe -Force
    }

    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
}

function Quote-Arg($Value) {
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Install-Services {
    $installWeb = Prompt-YesNo "安装 easytier-web-embed 配置/Web 服务？" "y"
    $installCore = Prompt-YesNo "安装 easytier-core 节点服务？" "y"
    if (-not $installWeb -and -not $installCore) {
        throw "至少需要安装一项。"
    }

    $version = Prompt-Default "EasyTier 版本，留空自动获取最新版，失败则使用 $DefaultVersion" ""
    if ([string]::IsNullOrWhiteSpace($version)) { $version = Get-LatestVersion }

    $webApiPort = "11211"
    $webApiAddr = "0.0.0.0"
    $webApiHost = "http://127.0.0.1:11211"
    $webConfigPort = "22020"
    $webConfigProtocol = "udp"

    if ($installWeb) {
        Write-Info "Web Embed 配置"
        $webApiPort = Prompt-Default "API/Web 端口" $webApiPort
        $webApiAddr = Prompt-Default "API/Web 监听地址" $webApiAddr
        $webApiHost = Prompt-Default "前端使用的 API 地址" $webApiHost
        $webConfigPort = Prompt-Default "配置服务器端口" $webConfigPort
        $webConfigProtocol = Prompt-Default "配置服务器协议 udp/tcp/ws" $webConfigProtocol
    }

    $username = ""
    $configServerAddr = "192.168.2.2:22020"
    $hostNameValue = $env:COMPUTERNAME
    $machineId = $env:COMPUTERNAME

    if ($installCore) {
        Write-Info "Core 节点配置"
        $username = Prompt-Required "请输入用户名，例如 jardy"
        if ($installWeb) { $configServerAddr = "127.0.0.1:$webConfigPort" }
        $configServerAddr = Prompt-Default "配置服务器地址，不要带 udp:// 和 /用户名" $configServerAddr
        $hostNameValue = Prompt-Default "节点主机名" $hostNameValue
        $machineId = Prompt-Default "Machine ID，建议固定" $machineId
    }

    Stop-RemoveService $CoreService
    Stop-RemoveService $WebService
    Download-Install -Version $version -InstallCore:$installCore -InstallWeb:$installWeb

    if ($installWeb) {
        $dbPath = Join-Path $InstallDir "et.db"
        $webArgs = @(
            Quote-Arg $WebExe,
            "--db", Quote-Arg $dbPath,
            "--api-server-port", $webApiPort,
            "--api-server-addr", $webApiAddr,
            "--api-host", Quote-Arg $webApiHost,
            "--config-server-port", $webConfigPort,
            "--config-server-protocol", $webConfigProtocol
        ) -join " "
        New-Service -Name $WebService -BinaryPathName $webArgs -DisplayName "EasyTier Web Embed" -StartupType Automatic | Out-Null
        Start-Service -Name $WebService
    }

    if ($installCore) {
        $coreArgs = @(
            Quote-Arg $CoreExe,
            "--config-server", Quote-Arg "udp://$configServerAddr/$username",
            "--hostname", Quote-Arg $hostNameValue
        )
        if (-not [string]::IsNullOrWhiteSpace($machineId)) {
            $coreArgs += @("--machine-id", (Quote-Arg $machineId))
        }
        New-Service -Name $CoreService -BinaryPathName ($coreArgs -join " ") -DisplayName "EasyTier Core" -StartupType Automatic | Out-Null
        Start-Service -Name $CoreService
    }

    Write-Success "安装完成。"
    Write-Info "检查命令："
    Write-Host "  Get-Service easytier-core,easytier-web-embed"
    Write-Host "  sc.exe query easytier-core"
    Write-Host "  sc.exe query easytier-web-embed"
}

if ($Help) {
    Show-Help
    exit 0
}

Assert-Admin

if ($Uninstall) {
    Uninstall-EasyTier
    exit 0
}

Install-Services
