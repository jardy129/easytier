# EasyTier Installers

Interactive installers for EasyTier Core and EasyTier Web Embed on Linux, macOS, and Windows.

## Linux

```bash
sudo ./install-easytier-linux-interactive.sh
sudo ./install-easytier-linux-interactive.sh --uninstall
```

Services:

```text
easytier-web-embed.service
easytier-core.service
```

Install directory:

```text
/etc/easytier
```

## macOS

```bash
sudo ./install-easytier-macos-interactive.sh
sudo ./install-easytier-macos-interactive.sh --uninstall
```

LaunchDaemons:

```text
/Library/LaunchDaemons/easytier-web-embed.plist
/Library/LaunchDaemons/easytier-core.plist
```

Install directory:

```text
/usr/local/bin/easytier
```

## Windows

Run PowerShell as Administrator:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-easytier-windows-interactive.ps1
powershell -ExecutionPolicy Bypass -File .\install-easytier-windows-interactive.ps1 -Uninstall
```

Services:

```text
easytier-web-embed
easytier-core
```

Install directory:

```text
C:\Program Files\EasyTier
```

## Parameter Notes

When prompted for config server address, enter only host and port:

```text
192.168.x.x:22020
aaa.com:22020
```

Do not include `udp://` or `/username`; the scripts add those automatically.
