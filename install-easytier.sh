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
DEFAULT_USERNAME="your-user"
DEFAULT_DOMAIN="your-server.example.com"
DEFAULT_PORT="22020"
DEFAULT_WEB_PORT="11211"
DEFAULT_PROTOCOL="udp"

OS_CHOICE=""
OS_NAME=""
ACTION="install"
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
AUTO_YES="no"

usage() {
  cat <<EOF
Usage:
  sudo ./install-easytier.sh
  sudo ./install-easytier.sh --yes --target linux --username your-user --domain your-server.example.com --port 22020 --hostname your-linux-node
  sudo ./install-easytier.sh --yes --target macos --username your-user --domain your-server.example.com --port 22020 --hostname your-mac-node
  sudo ./install-easytier.sh --yes --target linux --uninstall

This script installs EasyTier Core and EasyTier Web Embed on macOS or Linux.
For Windows, use install-easytier.ps1 in Administrator PowerShell.

Options:
  --yes                    Run without prompts and accept defaults.
  --target macos|linux     Target operating system.
  --version VERSION        EasyTier version. Default: ${DEFAULT_VERSION}
  --install-dir DIR        Install directory.
  --username USER          Config server username. Default: ${DEFAULT_USERNAME}
  --domain HOST            Config server domain/IP. Default: ${DEFAULT_DOMAIN}
  --port PORT              Config server port. Default: ${DEFAULT_PORT}
  --hostname NAME          Node hostname.
  --web-port PORT          Web/API port. Default: ${DEFAULT_WEB_PORT}
  --protocol udp|tcp|ws    Config server protocol. Default: ${DEFAULT_PROTOCOL}
  --no-web                 Do not install easytier-web-embed.
  --no-core                Do not install easytier-core.
  --uninstall              Stop services and delete EasyTier services/files.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      -y|--yes|--non-interactive)
        AUTO_YES="yes"
        shift
        ;;
      --uninstall|-x)
        ACTION="uninstall"
        shift
        ;;
      --target|--os)
        OS_NAME="$2"
        shift 2
        ;;
      --version)
        VERSION="$2"
        shift 2
        ;;
      --install-dir)
        INSTALL_DIR="$2"
        shift 2
        ;;
      --username)
        USERNAME="$2"
        shift 2
        ;;
      --domain|--server)
        DOMAIN="$2"
        shift 2
        ;;
      --port)
        PORT="$2"
        shift 2
        ;;
      --hostname)
        HOSTNAME_VALUE="$2"
        shift 2
        ;;
      --web-port)
        WEB_PORT="$2"
        shift 2
        ;;
      --protocol)
        CONFIG_PROTOCOL="$2"
        shift 2
        ;;
      --no-web)
        INSTALL_WEB="no"
        shift
        ;;
      --no-core)
        INSTALL_CORE="no"
        shift
        ;;
      *)
        error "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done
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
    echo "4) Thorough uninstall on this machine"
    echo "5) Exit"
    echo "========================================"
    read -r -p "Choose option [1-5]: " OS_CHOICE
    case "$OS_CHOICE" in
      1) OS_NAME="macos"; return ;;
      2) OS_NAME="linux"; return ;;
      3) OS_NAME="windows"; return ;;
      4)
        ACTION="uninstall"
        case "$(uname -s)" in
          Darwin) OS_NAME="macos" ;;
          Linux) OS_NAME="linux" ;;
          *) error "Unsupported current system for uninstall: $(uname -s)"; exit 1 ;;
        esac
        return
        ;;
      5) exit 0 ;;
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

  if [[ "$AUTO_YES" == "yes" ]]; then
    VERSION="${VERSION:-$DEFAULT_VERSION}"
    INSTALL_DIR="${INSTALL_DIR:-$(default_install_dir)}"
    USERNAME="${USERNAME:-$DEFAULT_USERNAME}"
    DOMAIN="${DOMAIN:-$DEFAULT_DOMAIN}"
    PORT="${PORT:-$DEFAULT_PORT}"
    HOSTNAME_VALUE="${HOSTNAME_VALUE:-$(default_hostname)}"
    WEB_PORT="${WEB_PORT:-$DEFAULT_WEB_PORT}"
    CONFIG_PROTOCOL="${CONFIG_PROTOCOL:-$DEFAULT_PROTOCOL}"
  else
    prompt_default VERSION "EasyTier version" "${VERSION:-$DEFAULT_VERSION}"
    prompt_default INSTALL_DIR "Install directory" "${INSTALL_DIR:-$(default_install_dir)}"
    prompt_default USERNAME "Username" "${USERNAME:-$DEFAULT_USERNAME}"
    prompt_default DOMAIN "Config server domain/IP, without udp:// and without /username" "${DOMAIN:-$DEFAULT_DOMAIN}"
    prompt_default PORT "Config server port" "${PORT:-$DEFAULT_PORT}"
    prompt_default HOSTNAME_VALUE "Hostname" "${HOSTNAME_VALUE:-$(default_hostname)}"
    prompt_default WEB_PORT "Web/API port" "${WEB_PORT:-$DEFAULT_WEB_PORT}"
    prompt_default CONFIG_PROTOCOL "Config server protocol" "${CONFIG_PROTOCOL:-$DEFAULT_PROTOCOL}"
    prompt_yes_no INSTALL_WEB "Install easytier-web-embed service?" "$INSTALL_WEB"
    prompt_yes_no INSTALL_CORE "Install easytier-core service?" "$INSTALL_CORE"
  fi

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

  if [[ "$AUTO_YES" == "yes" ]]; then
    return
  fi

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

uninstall_linux() {
  local dir
  dir="${INSTALL_DIR:-$(default_install_dir)}"

  info "Stopping and deleting Linux EasyTier services..."
  systemctl stop easytier-core.service 2>/dev/null || true
  systemctl stop easytier-web-embed.service 2>/dev/null || true
  systemctl stop easytier.service 2>/dev/null || true
  systemctl disable easytier-core.service 2>/dev/null || true
  systemctl disable easytier-web-embed.service 2>/dev/null || true
  systemctl disable easytier.service 2>/dev/null || true
  rm -f /etc/systemd/system/easytier-core.service
  rm -f /etc/systemd/system/easytier-web-embed.service
  rm -f /etc/systemd/system/easytier.service
  systemctl daemon-reload
  systemctl reset-failed 2>/dev/null || true

  info "Deleting ${dir}..."
  rm -rf "$dir"
  success "EasyTier has been fully uninstalled from Linux."
}

uninstall_macos() {
  local dir
  dir="${INSTALL_DIR:-$(default_install_dir)}"

  info "Stopping and deleting macOS EasyTier LaunchDaemons..."
  launchctl bootout system /Library/LaunchDaemons/easytier-core.plist 2>/dev/null || true
  launchctl bootout system /Library/LaunchDaemons/easytier-web-embed.plist 2>/dev/null || true
  launchctl bootout system /Library/LaunchDaemons/easytier.plist 2>/dev/null || true
  rm -f /Library/LaunchDaemons/easytier-core.plist
  rm -f /Library/LaunchDaemons/easytier-web-embed.plist
  rm -f /Library/LaunchDaemons/easytier.plist

  info "Deleting ${dir}..."
  rm -rf "$dir"
  rm -f /var/log/easytier-core.log /var/log/easytier-web-embed.log /var/log/easytier.log
  success "EasyTier has been fully uninstalled from macOS."
}

run_uninstall() {
  validate_os
  require_root
  if [[ -z "$INSTALL_DIR" && "$AUTO_YES" != "yes" ]]; then
    prompt_default INSTALL_DIR "Install directory to delete" "$(default_install_dir)"
    local ok
    prompt_yes_no ok "Confirm full uninstall and delete ${INSTALL_DIR}?" "n"
    if [[ "$ok" != "yes" ]]; then
      warning "Uninstall cancelled."
      exit 0
    fi
  fi

  if [[ "$OS_NAME" == "linux" ]]; then
    require_cmd systemctl
    uninstall_linux
  else
    uninstall_macos
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
  parse_args "$@"

  if [[ -z "$OS_NAME" ]]; then
    if [[ "$AUTO_YES" == "yes" ]]; then
      case "$(uname -s)" in
        Darwin) OS_NAME="macos" ;;
        Linux) OS_NAME="linux" ;;
        *) error "Cannot auto-detect target OS. Use --target macos or --target linux."; exit 1 ;;
      esac
    else
      main_menu
    fi
  fi

  if [[ "$ACTION" == "uninstall" ]]; then
    run_uninstall
  else
    run_install
  fi
}

main "$@"
