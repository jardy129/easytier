# EasyTier Installers / EasyTier 安装脚本

## 中文说明

这是一个 EasyTier 跨平台安装脚本，支持 Linux、macOS、Windows。

默认安装目录只保留两个基础文件：

```text
easytier-core
easytier-cli
```

Windows 下对应为：

```text
easytier-core.exe
easytier-cli.exe
```

如需安装 Web 配置服务，使用 `--with-web`（Windows 使用 `-WithWeb`），会额外安装：

```text
easytier-web-embed
```

Windows 下对应为：

```text
easytier-web-embed.exe
```

### Linux 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/jardy129/easytier/main/install-easytier.sh | sudo bash -s -- \
  --yes \
  --target linux \
  --username your-user \
  --domain your-server.example.com \
  --port 22020 \
  --hostname your-linux-node
```

### Linux 一键安装并启用 Web

```bash
curl -fsSL https://raw.githubusercontent.com/jardy129/easytier/main/install-easytier.sh | sudo bash -s -- \
  --yes \
  --target linux \
  --with-web \
  --username your-user \
  --domain your-server.example.com \
  --port 22020 \
  --hostname your-linux-node
```

### macOS 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/jardy129/easytier/main/install-easytier.sh | sudo bash -s -- \
  --yes \
  --target macos \
  --username your-user \
  --domain your-server.example.com \
  --port 22020 \
  --hostname your-mac-node
```

### macOS 一键安装并启用 Web

```bash
curl -fsSL https://raw.githubusercontent.com/jardy129/easytier/main/install-easytier.sh | sudo bash -s -- \
  --yes \
  --target macos \
  --with-web \
  --username your-user \
  --domain your-server.example.com \
  --port 22020 \
  --hostname your-mac-node
```

### Windows 一键安装

请使用管理员 PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -Command "iwr https://raw.githubusercontent.com/jardy129/easytier/main/install-easytier.ps1 -OutFile $env:TEMP\install-easytier.ps1; & $env:TEMP\install-easytier.ps1 -Yes -Target Windows -Username your-user -Domain your-server.example.com -Port 22020 -Hostname your-windows-node"
```

### Windows 一键安装并启用 Web

```powershell
powershell -ExecutionPolicy Bypass -Command "iwr https://raw.githubusercontent.com/jardy129/easytier/main/install-easytier.ps1 -OutFile $env:TEMP\install-easytier.ps1; & $env:TEMP\install-easytier.ps1 -Yes -WithWeb -Target Windows -Username your-user -Domain your-server.example.com -Port 22020 -Hostname your-windows-node"
```

### 彻底卸载

Linux：

```bash
curl -fsSL https://raw.githubusercontent.com/jardy129/easytier/main/install-easytier.sh | sudo bash -s -- --yes --target linux --uninstall
```

macOS：

```bash
curl -fsSL https://raw.githubusercontent.com/jardy129/easytier/main/install-easytier.sh | sudo bash -s -- --yes --target macos --uninstall
```

Windows 管理员 PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -Command "iwr https://raw.githubusercontent.com/jardy129/easytier/main/install-easytier.ps1 -OutFile $env:TEMP\install-easytier.ps1; & $env:TEMP\install-easytier.ps1 -Yes -Uninstall"
```

### 默认安装目录

```text
Linux: /etc/easytier
macOS: /usr/local/bin/easytier
Windows: C:\easytier
```

### 生成的服务

默认生成：

```text
Linux: easytier-core.service
macOS: /Library/LaunchDaemons/easytier-core.plist
Windows: easytier-core
```

启用 Web 时额外生成：

```text
Linux: easytier-web-embed.service
macOS: /Library/LaunchDaemons/easytier-web-embed.plist
Windows: easytier-web-embed
```

## English

Cross-platform EasyTier installer for Linux, macOS, and Windows.

By default, the install directory contains only:

```text
easytier-core
easytier-cli
```

On Windows:

```text
easytier-core.exe
easytier-cli.exe
```

To install the embedded Web/config service, use `--with-web` on Linux/macOS or `-WithWeb` on Windows. This additionally installs:

```text
easytier-web-embed
```

### Linux unattended install

```bash
curl -fsSL https://raw.githubusercontent.com/jardy129/easytier/main/install-easytier.sh | sudo bash -s -- \
  --yes \
  --target linux \
  --username your-user \
  --domain your-server.example.com \
  --port 22020 \
  --hostname your-linux-node
```

### Linux unattended install with Web

```bash
curl -fsSL https://raw.githubusercontent.com/jardy129/easytier/main/install-easytier.sh | sudo bash -s -- \
  --yes \
  --target linux \
  --with-web \
  --username your-user \
  --domain your-server.example.com \
  --port 22020 \
  --hostname your-linux-node
```

### macOS unattended install

```bash
curl -fsSL https://raw.githubusercontent.com/jardy129/easytier/main/install-easytier.sh | sudo bash -s -- \
  --yes \
  --target macos \
  --username your-user \
  --domain your-server.example.com \
  --port 22020 \
  --hostname your-mac-node
```

### Windows unattended install

Run PowerShell as Administrator:

```powershell
powershell -ExecutionPolicy Bypass -Command "iwr https://raw.githubusercontent.com/jardy129/easytier/main/install-easytier.ps1 -OutFile $env:TEMP\install-easytier.ps1; & $env:TEMP\install-easytier.ps1 -Yes -Target Windows -Username your-user -Domain your-server.example.com -Port 22020 -Hostname your-windows-node"
```

### Full uninstall

Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/jardy129/easytier/main/install-easytier.sh | sudo bash -s -- --yes --target linux --uninstall
```

macOS:

```bash
curl -fsSL https://raw.githubusercontent.com/jardy129/easytier/main/install-easytier.sh | sudo bash -s -- --yes --target macos --uninstall
```

Windows Administrator PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -Command "iwr https://raw.githubusercontent.com/jardy129/easytier/main/install-easytier.ps1 -OutFile $env:TEMP\install-easytier.ps1; & $env:TEMP\install-easytier.ps1 -Yes -Uninstall"
```
