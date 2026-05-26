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
    [string]$Protocol = "",
    [switch]$WithWeb,
    [string]$WebPort = "",
    [string]$ApiHost = ""
)

$ErrorActionPreference = "Stop"

$DefaultVersion = "2.6.4"
$DefaultUsername = "your-user"
$DefaultDomain = "your-server.example.com"
$DefaultPort = "22020"
$DefaultProtocol = "udp"
$DefaultWebPort = "11211"
$DefaultApiHost = "http://127.0.0.1:11211"
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
  powershell -ExecutionPolicy Bypass -File .\install-easytier.ps1 -Yes -Target Windows -Username your-user -Domain your-server.example.com -Port 22020 -Hostname your-windows-node
  powershell -ExecutionPolicy Bypass -File .\install-easytier.ps1 -Yes -WithWeb -Target Windows -Username your-user -Domain your-server.example.com -Port 22020 -Hostname your-windows-node
  powershell -ExecutionPolicy Bypass -File .\install-easytier.ps1 -Yes -Uninstall

默认安装:
  easytier-core.exe
  easytier-cli.exe

加 -WithWeb 时额外安装:
  easytier-web-embed.exe
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
            default { Write-Warn "请输入 y 或 n。" }
        }
    }
}

function Main-Menu {
    while ($true) {
        Write-Host ""
        Write-Host "========== EasyTier 安装器 =========="
        Write-Host "1) 安装到 Mac"
        Write-Host "2) 安装到 Linux"
        Write-Host "3) 安装到 Windows"
        Write-Host "4) 彻底卸载本机 EasyTier"
        Write-Host "5) 退出"
        Write-Host "========================================"
        $choice = Read-Host "请选择 [1-5]"
        switch ($choice) {
            "1" {
                Write-Warn "Mac 请在 macOS 上运行:"
                Write-Host "  sudo ./install-easytier.sh"
                exit 0
            }
            "2" {
                Write-Warn "Linux 请在 Linux 上运行:"
                Write-Host "  sudo ./install-easytier.sh"
                exit 0
            }
            "3" { return }
            "4" { $script:Uninstall = $true; return }
            "5" { exit 0 }
            default { Write-Warn "无效选项。" }
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
        if ([string]::IsNullOrWhiteSpace($WebPort)) { $script:WebPort = $DefaultWebPort }
        if ([string]::IsNullOrWhiteSpace($ApiHost)) { $script:ApiHost = $DefaultApiHost }
    } else {
        $script:InstallDir = Prompt-Default "安装目录" "C:\easytier"
        $script:Version = Prompt-Default "EasyTier 版本" $DefaultVersion
        $script:Username = Prompt-Default "用户名" $DefaultUsername
        $script:Domain = Prompt-Default "配置服务器域名/IP，不含协议和用户名" $DefaultDomain
        $script:Port = Prompt-Default "配置服务器端口" $DefaultPort
        $script:Hostname = Prompt-Default "主机名" $env:COMPUTERNAME
        $script:Protocol = Prompt-Default "配置服务器协议" $DefaultProtocol
        $script:WithWeb = Prompt-YesNo "是否额外安装 easytier-web-embed Web 服务？" "n"
        if ($WithWeb) {
            $script:WebPort = Prompt-Default "Web/API 端口" $DefaultWebPort
            $script:ApiHost = Prompt-Default "Web 前端使用的 API 地址" $DefaultApiHost
        }
    }
}

function Confirm-Config($Platform) {
    $asset = "easytier-windows-$Platform-v$Version.zip"
    $configServer = "${Protocol}://${Domain}:${Port}/${Username}"

    Write-Host ""
    Write-Host "========== 确认安装配置 =========="
    Write-Host "目标系统:           windows"
    Write-Host "系统架构:           $Platform"
    Write-Host "下载文件:           $asset"
    Write-Host "安装目录:           $InstallDir"
    Write-Host "基础文件:           easytier-core.exe, easytier-cli.exe"
    Write-Host "安装 Web 服务:      $WithWeb"
    if ($WithWeb) {
        Write-Host "Web 文件:           easytier-web-embed.exe"
        Write-Host "Web/API 端口:       $WebPort"
        Write-Host "Web API 地址:       $ApiHost"
    }
    Write-Host "用户名:             $Username"
    Write-Host "配置服务器:         $configServer"
    Write-Host "主机名:             $Hostname"
    Write-Host "=========================================="
    Write-Host ""

    if (-not $Yes -and -not (Prompt-YesNo "确认并开始安装？" "n")) {
        Write-Warn "已取消安装。"
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
    if ($WithWeb) {
        Copy-Item (Join-Path $extractDir "easytier-web-embed.exe") (Join-Path $InstallDir "easytier-web-embed.exe") -Force
    }

    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
}

function Install-EasyTier {
    $platform = Get-WindowsPlatform
    Collect-Config
    Confirm-Config $platform

    Stop-RemoveService $CoreService
    Stop-RemoveService $WebService
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

    if ($WithWeb) {
        $webExe = Join-Path $InstallDir "easytier-web-embed.exe"
        $dbPath = Join-Path $InstallDir "et.db"
        $webArgs = @(
            Quote-Arg $webExe,
            "--db", Quote-Arg $dbPath,
            "--api-server-port", $WebPort,
            "--api-server-addr", "0.0.0.0",
            "--api-host", Quote-Arg $ApiHost,
            "--config-server-port", $Port,
            "--config-server-protocol", $Protocol
        ) -join " "
        New-Service -Name $WebService -BinaryPathName $webArgs -DisplayName "EasyTier Web Embed" -StartupType Automatic | Out-Null
        Start-Service -Name $WebService
    }

    Write-Success "安装完成。"
    Write-Host "安装目录内容:"
    Get-ChildItem -LiteralPath $InstallDir
    Write-Host "检查:"
    Write-Host "  Get-Service easytier-core"
}

function Uninstall-EasyTier {
    if ([string]::IsNullOrWhiteSpace($InstallDir)) { $InstallDir = "C:\easytier" }
    if (-not $Yes) {
        $script:InstallDir = Prompt-Default "要删除的安装目录" $InstallDir
        if (-not (Prompt-YesNo "确认彻底卸载并删除 $InstallDir ?" "n")) {
            Write-Warn "已取消卸载。"
            exit 0
        }
    }

    Write-Info "正在停止并删除 Windows EasyTier 服务..."
    Stop-RemoveService $CoreService
    Stop-RemoveService $WebService

    Write-Info "正在删除 $InstallDir..."
    Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Success "Windows EasyTier 已彻底卸载。"
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
