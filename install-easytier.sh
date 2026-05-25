#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}$*${NC}"; }
success() { echo -e "${GREEN}$*${NC}"; }
warning() { echo -e "${YELLOW}$*${NC}"; }
error() { echo -e "${RED}$*${NC}" >&2; }

DEFAULT_VERSION="2.6.4"
DEFAULT_USERNAME="jardy"
DEFAULT_DOMAIN="192.168.2.2"
DEFAULT_PORT="22020"
DEFAULT_WEB_PORT="11211"
DEFAULT_PROTOCOL="udp"

OS_CHOICE=""
OS_NAME=""
PLATFORM=""
VERSION=""
INSTALL_DIR=""
USERNAME=""
DOMAIN=""
PORT=""
HOSTNAME_VALUE=""
WEB_PORT=""
CONFIG_PROTOCOL=""
INSTALL_WEB="yes"
INSTALL_CORE="yes"

usage() {
  cat <<EOF
Usage:
  sudo ./install-easytier.sh
  sudo ./install-easytier.sh --uninstall

This script installs EasyTier Core and EasyTier Web Embed on macOS or Linux.
For Windows, use install-easytier.ps1 in Administrator PowerShell.
EOF
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    error "Please run as root: sudo $0"
    exit 1
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    error "Missing command: $1"
    exit 1
  }
}

prompt_default() {
  local var_name="$1"
  local question="$2"
  local default_value="$3"
  local answer
  read -r -p "${question} [${default_value}]: " answer
  printf -v "$var_name" '%s' "${answer:-$default_value}"
}

prompt_yes_no() {
  local var_name="$1"
  local question="$2"
  local default_value="$3"
  local answer
  while true; do
    read -r -p "${question} [${default_value}]: " answer
    answer="${answer:-$default_value}"
    case "$answer" in
      y|Y|yes|YES|Yes) printf -v "$var_name" '%s' "yes"; return ;;
      n|N|no|NO|No) printf -v "$var_name" '%s' "no"; return ;;
      *) warning "Please enter y or n." ;;
    esac
  done
}

main_menu() {
  while true; do
    echo
    echo "========== EasyTier Installer =========="
    echo "1) Mac"
    echo "2) Linux"
    echo "3) Windows"
    echo "4) Exit"
    echo "========================================"
    read -r -p "Choose target system [1-4]: " OS_CHOICE
    case "$OS_CHOICE" in
      1) OS_NAME="macos"; return ;;
      2) OS_NAME="linux"; return ;;
      3) OS_NAME="windows"; return ;;
      4) exit 0 ;;
      *) warning "Invalid option." ;;
    esac
  done
}

detect_platform() {
  local machine
  machine="$(uname -m)"

  case "$OS_NAME:$machine" in
    macos:x86_64) PLATFORM="x86_64" ;;
    macos:arm64|macos:aarch64) PLATFORM="aarch64" ;;
    linux:x86_64|linux:amd64) PLATFORM="x86_64" ;;
    linux:aarch64|linux:arm64) PLATFORM="aarch64" ;;
    linux:armv7l)
      if grep -q "VFPv3" /proc/cpuinfo 2>/dev/null; then
        PLATFORM="armv7hf"
      else
        PLATFORM="armv7"
      fi
      ;;
    linux:armhf|linux:armv6l) PLATFORM="armhf" ;;
    linux:arm) PLATFORM="arm" ;;
    *)
      error "Unsupported architecture for ${OS_NAME}: ${machine}"
      exit 1
      ;;
  esac
}

validate_os() {
  local actual
  actual="$(uname -s)"

  if [[ "$OS_NAME" == "macos" && "$actual" != "Darwin" ]]; then
    error "You chose Mac, but current system is ${actual}."
    exit 1
  fi

  if [[ "$OS_NAME" == "linux" && "$actual" != "Linux" ]]; then
    error "You chose Linux, but current system is ${actual}."
    exit 1
  fi

  if [[ "$OS_NAME" == "windows" ]]; then
    warning "Windows service installation should be run from Administrator PowerShell:"
    echo "  powershell -ExecutionPolicy Bypass -File .\\install-easytier.ps1"
    exit 0
  fi
}

default_install_dir() {
  if [[ "$OS_NAME" == "macos" ]]; then
    echo "/usr/local/bin/easytier"
  else
    echo "/etc/easytier"
  fi
}

default_hostname() {
  if command -v hostname >/dev/null 2>&1; then
    hostname -s 2>/dev/null || hostname
  else
    echo "easytier-node"
  fi
}

collect_config() {
  detect_platform
  prompt_default VERSION "EasyTier version" "$DEFAULT_VERSION"
  prompt_default INSTALL_DIR "Install directory" "$(default_install_dir)"
  prompt_default USERNAME "Username" "$DEFAULT_USERNAME"
  prompt_default DOMAIN "Config server domain/IP, without udp:// and without /username" "$DEFAULT_DOMAIN"
  prompt_default PORT "Config server port" "$DEFAULT_PORT"
  prompt_default HOSTNAME_VALUE "Hostname" "$(default_hostname)"
  prompt_default WEB_PORT "Web/API port" "$DEFAULT_WEB_PORT"
  prompt_default CONFIG_PROTOCOL "Config server protocol" "$DEFAULT_PROTOCOL"
  prompt_yes_no INSTALL_WEB "Install easytier-web-embed service?" "y"
  prompt_yes_no INSTALL_CORE "Install easytier-core service?" "y"

  if [[ "$INSTALL_WEB" != "yes" && "$INSTALL_CORE" != "yes" ]]; then
    error "Nothing selected to install."
    exit 1
  fi
}

confirm_config() {
  local package_name config_server web_api_host
  package_name="easytier-${OS_NAME}-${PLATFORM}-v${VERSION}.zip"
  config_server="${CONFIG_PROTOCOL}://${DOMAIN}:${PORT}/${USERNAME}"
  web_api_host="http://127.0.0.1:${WEB_PORT}"

  echo
  echo "========== Confirm Installation =========="
  echo "Target OS:          ${OS_NAME}"
  echo "Architecture:       ${PLATFORM}"
  echo "Download package:   ${package_name}"
  echo "Install directory:  ${INSTALL_DIR}"
  echo "Username:           ${USERNAME}"
  echo "Config server:      ${config_server}"
  echo "Hostname:           ${HOSTNAME_VALUE}"
  echo "Web/API port:       ${WEB_PORT}"
  echo "Web API host:       ${web_api_host}"
  echo "Install Web Embed:  ${INSTALL_WEB}"
  echo "Install Core:       ${INSTALL_CORE}"
  echo "=========================================="
  echo

  local ok
  prompt_yes_no ok "Confirm and start installation?" "n"
  if [[ "$ok" != "yes" ]]; then
    warning "Installation cancelled."
    exit 0
  fi
}

download_package() {
  local package_name url zip_path extract_dir
  package_name="easytier-${OS_NAME}-${PLATFORM}-v${VERSION}.zip"
  url="https://github.com/EasyTier/EasyTier/releases/download/v${VERSION}/${package_name}"
  zip_path="/tmp/${package_name}"
  extract_dir="/tmp/easytier-${OS_NAME}-${PLATFORM}"

  info "Downloading ${url}"
  rm -rf "$zip_path" "$extract_dir"
  curl -fL -o "$zip_path" "$url" --connect-timeout 10 --max-time 180

  info "Extracting package..."
  unzip -q "$zip_path" -d /tmp
  mkdir -p "$INSTALL_DIR"

  if [[ "$INSTALL_CORE" == "yes" ]]; then
    install -m 0755 "${extract_dir}/easytier-core" "${INSTALL_DIR}/easytier-core"
  fi

  if [[ "$INSTALL_WEB" == "yes" ]]; then
    install -m 0755 "${extract_dir}/easytier-web-embed" "${INSTALL_DIR}/easytier-web-embed"
  fi

  if [[ "$OS_NAME" == "macos" ]]; then
    xattr -dr com.apple.quarantine "$INSTALL_DIR" 2>/dev/null || true
  fi

  rm -rf "$zip_path" "$extract_dir"
}

install_linux_services() {
  local core_service web_service core_bin web_bin web_api_host config_server
  core_service="/etc/systemd/system/easytier-core.service"
  web_service="/etc/systemd/system/easytier-web-embed.service"
  core_bin="${INSTALL_DIR}/easytier-core"
  web_bin="${INSTALL_DIR}/easytier-web-embed"
  web_api_host="http://127.0.0.1:${WEB_PORT}"
  config_server="${CONFIG_PROTOCOL}://${DOMAIN}:${PORT}/${USERNAME}"

  systemctl stop easytier-core.service 2>/dev/null || true
  systemctl stop easytier-web-embed.service 2>/dev/null || true
  systemctl disable easytier-core.service 2>/dev/null || true
  systemctl disable easytier-web-embed.service 2>/dev/null || true

  if [[ "$INSTALL_WEB" == "yes" ]]; then
    cat > "$web_service" <<EOF
[Unit]
Description=EasyTier Web Embedded Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${web_bin} --db ${INSTALL_DIR}/et.db --api-server-port ${WEB_PORT} --api-server-addr 0.0.0.0 --api-host ${web_api_host} --config-server-port ${PORT} --config-server-protocol ${CONFIG_PROTOCOL}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  fi

  if [[ "$INSTALL_CORE" == "yes" ]]; then
    cat > "$core_service" <<EOF
[Unit]
Description=EasyTier Core Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
Environment=HOME=/root
ExecStart=${core_bin} --config-server ${config_server} --hostname ${HOSTNAME_VALUE}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  fi

  systemctl daemon-reload
  [[ "$INSTALL_WEB" == "yes" ]] && systemctl enable --now easytier-web-embed.service
  [[ "$INSTALL_CORE" == "yes" ]] && systemctl enable --now easytier-core.service
}

write_plist() {
  local plist_path="$1"
  local label="$2"
  local log_path="$3"
  shift 3
  local args=("$@")

  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    echo '<plist version="1.0">'
    echo '<dict>'
    echo "  <key>Label</key><string>${label}</string>"
    echo '  <key>ProgramArguments</key>'
    echo '  <array>'
    for arg in "${args[@]}"; do
      printf '    <string>%s</string>\n' "$arg"
    done
    echo '  </array>'
    echo "  <key>WorkingDirectory</key><string>${INSTALL_DIR}</string>"
    echo '  <key>EnvironmentVariables</key>'
    echo '  <dict>'
    echo '    <key>HOME</key><string>/var/root</string>'
    echo '    <key>PATH</key><string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>'
    echo '  </dict>'
    echo '  <key>RunAtLoad</key><true/>'
    echo '  <key>KeepAlive</key><true/>'
    echo "  <key>StandardOutPath</key><string>${log_path}</string>"
    echo "  <key>StandardErrorPath</key><string>${log_path}</string>"
    echo '</dict>'
    echo '</plist>'
  } > "$plist_path"

  chown root:wheel "$plist_path"
  chmod 644 "$plist_path"
}

install_macos_services() {
  local core_plist web_plist core_bin web_bin web_api_host config_server
  core_plist="/Library/LaunchDaemons/easytier-core.plist"
  web_plist="/Library/LaunchDaemons/easytier-web-embed.plist"
  core_bin="${INSTALL_DIR}/easytier-core"
  web_bin="${INSTALL_DIR}/easytier-web-embed"
  web_api_host="http://127.0.0.1:${WEB_PORT}"
  config_server="${CONFIG_PROTOCOL}://${DOMAIN}:${PORT}/${USERNAME}"

  launchctl bootout system "$core_plist" 2>/dev/null || true
  launchctl bootout system "$web_plist" 2>/dev/null || true

  if [[ "$INSTALL_WEB" == "yes" ]]; then
    write_plist "$web_plist" "easytier-web-embed" "/var/log/easytier-web-embed.log" \
      "$web_bin" \
      "--db" "${INSTALL_DIR}/et.db" \
      "--api-server-port" "$WEB_PORT" \
      "--api-server-addr" "0.0.0.0" \
      "--api-host" "$web_api_host" \
      "--config-server-port" "$PORT" \
      "--config-server-protocol" "$CONFIG_PROTOCOL"
    launchctl bootstrap system "$web_plist"
    launchctl kickstart -k system/easytier-web-embed
  fi

  if [[ "$INSTALL_CORE" == "yes" ]]; then
    write_plist "$core_plist" "easytier-core" "/var/log/easytier-core.log" \
      "$core_bin" \
      "--config-server" "$config_server" \
      "--hostname" "$HOSTNAME_VALUE"
    launchctl bootstrap system "$core_plist"
    launchctl kickstart -k system/easytier-core
  fi
}

run_install() {
  validate_os
  require_root
  require_cmd curl
  require_cmd unzip

  if [[ "$OS_NAME" == "linux" ]]; then
    require_cmd systemctl
  fi

  collect_config
  confirm_config
  download_package

  if [[ "$OS_NAME" == "linux" ]]; then
    install_linux_services
  else
    install_macos_services
  fi

  success "Installation completed."
  if [[ "$OS_NAME" == "linux" ]]; then
    echo "Check:"
    echo "  systemctl status easytier-web-embed.service"
    echo "  systemctl status easytier-core.service"
  else
    echo "Check:"
    echo "  sudo launchctl list | grep easytier"
    echo "  tail -50 /var/log/easytier-core.log"
    echo "  tail -50 /var/log/easytier-web-embed.log"
  fi
}

main() {
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    *) ;;
  esac

  main_menu
  run_install
}

main "$@"
