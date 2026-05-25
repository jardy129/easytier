# EasyTier Installers

Interactive installers for EasyTier Core and EasyTier Web Embed.

## Recommended Scripts

### macOS / Linux

Run on the target machine:

```bash
sudo ./install-easytier.sh
```

Unattended Linux example:

```bash
curl -fsSL https://raw.githubusercontent.com/jardy129/easytier/main/install-easytier.sh | sudo bash -s -- \
  --yes \
  --target linux \
  --username your-user \
  --domain your-server.example.com \
  --port 22020 \
  --hostname your-linux-node
```

Unattended Linux full uninstall:

```bash
curl -fsSL https://raw.githubusercontent.com/jardy129/easytier/main/install-easytier.sh | sudo bash -s -- \
  --yes \
  --target linux \
  --uninstall
```

Unattended macOS example:

```bash
curl -fsSL https://raw.githubusercontent.com/jardy129/easytier/main/install-easytier.sh | sudo bash -s -- \
  --yes \
  --target macos \
  --username your-user \
  --domain your-server.example.com \
  --port 22020 \
  --hostname your-mac-node
```

Unattended macOS full uninstall:

```bash
curl -fsSL https://raw.githubusercontent.com/jardy129/easytier/main/install-easytier.sh | sudo bash -s -- \
  --yes \
  --target macos \
  --uninstall
```

The script starts with this menu:

```text
1) Mac
2) Linux
3) Windows
4) Thorough uninstall on this machine
5) Exit
```

For macOS and Linux it will:

```text
Detect x86_64/aarch64/arm automatically
Download the matching EasyTier release zip
Ask for install directory
Ask for domain/IP, port, username, hostname
Ask whether to install easytier-web-embed and easytier-core
Show a confirmation page before installing
Create auto-start services
```

Default install directories:

```text
macOS: /usr/local/bin/easytier
Linux: /etc/easytier
```

### Windows

Run PowerShell as Administrator:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-easytier.ps1
```

Unattended Windows example:

```powershell
powershell -ExecutionPolicy Bypass -Command "iwr https://raw.githubusercontent.com/jardy129/easytier/main/install-easytier.ps1 -OutFile $env:TEMP\install-easytier.ps1; & $env:TEMP\install-easytier.ps1 -Yes -Target Windows -Username your-user -Domain your-server.example.com -Port 22020 -Hostname your-windows-node"
```

Unattended Windows full uninstall:

```powershell
powershell -ExecutionPolicy Bypass -Command "iwr https://raw.githubusercontent.com/jardy129/easytier/main/install-easytier.ps1 -OutFile $env:TEMP\install-easytier.ps1; & $env:TEMP\install-easytier.ps1 -Yes -Uninstall"
```

The Windows script uses the same menu and confirmation flow. It detects `x86_64`, `arm64`, or `i686`, downloads the matching Windows zip, and installs Windows services.

Default install directory:

```text
C:\easytier
```

## Parameters

When prompted for the config server domain/IP, enter only the host:

```text
192.168.x.x
aaa.com
```

When prompted for the port, enter only the port:

```text
22020
```

The scripts build the final config server URL automatically:

```text
udp://<domain>:<port>/<username>
```

Example:

```text
udp://192.168.x.x:22020/xxxxx
```

## Generated Services

Linux:

```text
easytier-web-embed.service
easytier-core.service
```

macOS:

```text
/Library/LaunchDaemons/easytier-web-embed.plist
/Library/LaunchDaemons/easytier-core.plist
```

Windows:

```text
easytier-web-embed
easytier-core
```
