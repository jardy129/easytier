#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="easytier"
PLIST_PATH="/Library/LaunchDaemons/${SERVICE_NAME}.plist"
EASYTIER_DIR="/usr/local/bin/easytier"
EASYTIER_CORE="${EASYTIER_DIR}/easytier-core"
CONFIG_SERVER="udp://192.168.2.2:22020/jardy"
HOSTNAME_VALUE="MacBook-Mini"
LOG_PATH="/var/log/easytier.log"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Please run as root:"
  echo "  sudo $0"
  exit 1
fi

if [[ ! -x "${EASYTIER_CORE}" ]]; then
  echo "Missing executable: ${EASYTIER_CORE}"
  echo "Please put easytier-core in ${EASYTIER_DIR} first."
  exit 1
fi

echo "Preparing EasyTier binary..."
xattr -dr com.apple.quarantine "${EASYTIER_DIR}" 2>/dev/null || true
chmod +x "${EASYTIER_CORE}"
mkdir -p "$(dirname "${LOG_PATH}")"
touch "${LOG_PATH}"

echo "Stopping old service if it exists..."
launchctl bootout system "${PLIST_PATH}" 2>/dev/null || true

echo "Writing ${PLIST_PATH}..."
cat > "${PLIST_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${SERVICE_NAME}</string>

  <key>ProgramArguments</key>
  <array>
    <string>${EASYTIER_CORE}</string>
    <string>--config-server</string>
    <string>${CONFIG_SERVER}</string>
    <string>--hostname</string>
    <string>${HOSTNAME_VALUE}</string>
  </array>

  <key>WorkingDirectory</key>
  <string>${EASYTIER_DIR}</string>

  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>/var/root</string>
    <key>PATH</key>
    <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <true/>

  <key>StandardOutPath</key>
  <string>${LOG_PATH}</string>

  <key>StandardErrorPath</key>
  <string>${LOG_PATH}</string>
</dict>
</plist>
EOF

chown root:wheel "${PLIST_PATH}"
chmod 644 "${PLIST_PATH}"

echo "Starting EasyTier service..."
launchctl bootstrap system "${PLIST_PATH}"
launchctl kickstart -k "system/${SERVICE_NAME}"

echo
echo "Done."
echo "Service status:"
launchctl list | grep "${SERVICE_NAME}" || true
echo
echo "Logs:"
echo "  tail -50 ${LOG_PATH}"
