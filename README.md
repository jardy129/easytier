# EasyTier Installers

Interactive installers for EasyTier Core and EasyTier Web Embed.

## Recommended Scripts

### macOS / Linux

Run on the target machine:

```bash
sudo ./install-easytier.sh
```

The script starts with this menu:

```text
1) Mac
2) Linux
3) Windows
4) Exit
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

The Windows script uses the same menu and confirmation flow. It detects `x86_64`, `arm64`, or `i686`, downloads the matching Windows zip, and installs Windows services.

Default install directory:

```text
C:\easytier
```

## Parameters

When prompted for the config server domain/IP, enter only the host:

```text
192.168.2.2
jardy.top
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
udp://192.168.2.2:22020/jardy
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
