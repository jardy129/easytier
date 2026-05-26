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
DEFAULT_PROTOCOL="udp"
DEFAULT_WEB_PORT="11211"
DEFAULT_WEB_API_HOST="http://127.0.0.1:11211"

ACTION="install"
AUTO_YES="no"
OS_NAME=""
PLATFORM=""
VERSION=""
INSTALL_DIR=""
USERNAME=""
DOMAIN=""
PORT=""
HOSTNAME_VALUE=""
CONFIG_PROTOCOL=""
INSTALL_WEB="no"
WEB_PORT=""
WEB_API_HOST=""

usage() {
  cat <<EOF
Usage:
  sudo ./install-easytier.sh
  sudo ./install-easytier.sh --yes --target linux --username your-user --domain your-server.example.com --port 22020 --hostname your-linux-node
  sudo ./install-easytier.sh --yes --target linux --with-web --username your-user --domain your-server.example.com --port 22020 --hostname your-linux-node
  sudo ./install-easytier.sh --yes --target macos --username your-user --domain your-server.example.com --port 22020 --hostname your-mac-node
  sudo ./install-easytier.sh --yes --target linux --uninstall

默认只安装:
  easytier-core
  easytier-cli

加 --with-web 时额外安装:
  easytier-web-embed

Options:
  --yes                    Run without prompts and accept defaults.
  --target macos|linux     Target operating system.
  --version VERSION        EasyTier version. Default: ${DEFAULT_VERSION}
  --install-dir DIR        Install directory.
  --username USER          Config server username. Default: ${DEFAULT_USERNAME}
  --domain HOST            Config server domain/IP. Default: ${DEFAULT_DOMAIN}
  --port PORT              Config server port. Default: ${DEFAULT_PORT}
  --hostname NAME          Node hostname.
  --protocol udp|tcp|ws    Config server protocol. Default: ${DEFAULT_PROTOCOL}
  --with-web               Install easytier-web-embed and create web service.
  --web-port PORT          Web/API port. Default: ${DEFAULT_WEB_PORT}
  --api-host URL           API URL used by web frontend. Default: ${DEFAULT_WEB_API_HOST}
  --uninstall              Stop services and delete EasyTier services/files.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      -y|--yes|--non-interactive) AUTO_YES="yes"; shift ;;
      --uninstall|-x) ACTION="uninstall"; shift ;;
      --target|--os) OS_NAME="$2"; shift 2 ;;
      --version) VERSION="$2"; shift 2 ;;
      --install-dir) INSTALL_DIR="$2"; shift 2 ;;
      --username) USERNAME="$2"; shift 2 ;;
      --domain|--server) DOMAIN="$2"; shift 2 ;;
      --port) PORT="$2"; shift 2 ;;
      --hostname) HOSTNAME_VALUE="$2"; shift 2 ;;
      --protocol) CONFIG_PROTOCOL="$2"; shift 2 ;;
      --with-web) INSTALL_WEB="yes"; shift ;;
      --web-port) WEB_PORT="$2"; shift 2 ;;
      --api-host) WEB_API_HOST="$2"; shift 2 ;;
      *) error "Unknown option: $1"; usage; exit 1 ;;
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
  local var_name="$1" question="$2" default_value="$3" answer
  read -r -p "${question} [${default_value}]: " answer
  printf -v "$var_name" '%s' "${answer:-$default_value}"
}

prompt_yes_no() {
  local var_name="$1" question="$2" default_value="$3" answer
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
  local choice
  while true; do
    echo
    echo "========== EasyTier 安装器 =========="
    echo "1) 安装到 Mac"
    echo "2) 安装到 Linux"
    echo "3) 安装到 Windows"
    echo "4) 彻底卸载本机 EasyTier"
    echo "5) 退出"
    echo "========================================"
    read -r -p "请选择 [1-5]: " choice
    case "$choice" in
      1) OS_NAME="macos"; return ;;
      2) OS_NAME="linux"; return ;;
      3)
        warning "Windows 请使用管理员 PowerShell 运行:"
        echo "  powershell -ExecutionPolicy Bypass -File .\\install-easytier.ps1"
        exit 0
        ;;
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
      *) warning "无效选项。" ;;
    esac
  done
}

default_install_dir() {
  if [[ "$OS_NAME" == "macos" ]]; then
    echo "/usr/local/bin/easytier"
  else
    echo "/etc/easytier"
  fi
}

default_hostname() {
  hostname -s 2>/dev/null || hostname 2>/dev/null || echo "easytier-node"
}

validate_os() {
  local actual
  actual="$(uname -s)"
  if [[ "$OS_NAME" == "macos" && "$actual" != "Darwin" ]]; then
    error "你选择了 Mac，但当前系统是 ${actual}。"
    exit 1
  fi
  if [[ "$OS_NAME" == "linux" && "$actual" != "Linux" ]]; then
    error "你选择了 Linux，但当前系统是 ${actual}。"
    exit 1
  fi
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
    *) error "Unsupported architecture for ${OS_NAME}: ${machine}"; exit 1 ;;
  esac
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
    CONFIG_PROTOCOL="${CONFIG_PROTOCOL:-$DEFAULT_PROTOCOL}"
  else
    prompt_default VERSION "EasyTier 版本" "${VERSION:-$DEFAULT_VERSION}"
    prompt_default INSTALL_DIR "安装目录" "${INSTALL_DIR:-$(default_install_dir)}"
    prompt_default USERNAME "用户名" "${USERNAME:-$DEFAULT_USERNAME}"
    prompt_default DOMAIN "配置服务器域名/IP，不含协议和用户名" "${DOMAIN:-$DEFAULT_DOMAIN}"
    prompt_default PORT "配置服务器端口" "${PORT:-$DEFAULT_PORT}"
    prompt_default HOSTNAME_VALUE "主机名" "${HOSTNAME_VALUE:-$(default_hostname)}"
    prompt_default CONFIG_PROTOCOL "配置服务器协议" "${CONFIG_PROTOCOL:-$DEFAULT_PROTOCOL}"
    prompt_yes_no INSTALL_WEB "是否额外安装 easytier-web-embed Web 服务？" "$INSTALL_WEB"
    if [[ "$INSTALL_WEB" == "yes" ]]; then
      prompt_default WEB_PORT "Web/API 端口" "${WEB_PORT:-$DEFAULT_WEB_PORT}"
      prompt_default WEB_API_HOST "Web 前端使用的 API 地址" "${WEB_API_HOST:-$DEFAULT_WEB_API_HOST}"
    fi
  fi

  WEB_PORT="${WEB_PORT:-$DEFAULT_WEB_PORT}"
  WEB_API_HOST="${WEB_API_HOST:-$DEFAULT_WEB_API_HOST}"
}

confirm_config() {
  local package_name config_server ok
  package_name="easytier-${OS_NAME}-${PLATFORM}-v${VERSION}.zip"
  config_server="${CONFIG_PROTOCOL}://${DOMAIN}:${PORT}/${USERNAME}"

  echo
  echo "========== 确认安装配置 =========="
  echo "目标系统:           ${OS_NAME}"
  echo "系统架构:           ${PLATFORM}"
  echo "下载文件:           ${package_name}"
  echo "安装目录:           ${INSTALL_DIR}"
  echo "基础文件:           easytier-core, easytier-cli"
  echo "安装 Web 服务:      ${INSTALL_WEB}"
  if [[ "$INSTALL_WEB" == "yes" ]]; then
    echo "Web 文件:           easytier-web-embed"
    echo "Web/API 端口:       ${WEB_PORT}"
    echo "Web API 地址:       ${WEB_API_HOST}"
  fi
  echo "用户名:             ${USERNAME}"
  echo "配置服务器:         ${config_server}"
  echo "主机名:             ${HOSTNAME_VALUE}"
  echo "=========================================="
  echo

  if [[ "$AUTO_YES" == "yes" ]]; then
    return
  fi

  prompt_yes_no ok "确认并开始安装？" "n"
  if [[ "$ok" != "yes" ]]; then
    warning "已取消安装。"
    exit 0
  fi
}

stop_legacy_services() {
  if [[ "$OS_NAME" == "linux" ]]; then
    systemctl stop easytier-core.service 2>/dev/null || true
    systemctl stop easytier-web-embed.service 2>/dev/null || true
    systemctl stop easytier.service 2>/dev/null || true
    systemctl disable easytier-core.service 2>/dev/null || true
    systemctl disable easytier-web-embed.service 2>/dev/null || true
    systemctl disable easytier.service 2>/dev/null || true
    rm -f /etc/systemd/system/easytier-web-embed.service
    rm -f /etc/systemd/system/easytier.service
  else
    launchctl bootout system /Library/LaunchDaemons/easytier-core.plist 2>/dev/null || true
    launchctl bootout system /Library/LaunchDaemons/easytier-web-embed.plist 2>/dev/null || true
    launchctl bootout system /Library/LaunchDaemons/easytier.plist 2>/dev/null || true
    rm -f /Library/LaunchDaemons/easytier-web-embed.plist
    rm -f /Library/LaunchDaemons/easytier.plist
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

  info "Preparing install directory ${INSTALL_DIR}..."
  rm -rf "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  install -m 0755 "${extract_dir}/easytier-core" "${INSTALL_DIR}/easytier-core"
  install -m 0755 "${extract_dir}/easytier-cli" "${INSTALL_DIR}/easytier-cli"
  if [[ "$INSTALL_WEB" == "yes" ]]; then
    install -m 0755 "${extract_dir}/easytier-web-embed" "${INSTALL_DIR}/easytier-web-embed"
  fi

  if [[ "$OS_NAME" == "macos" ]]; then
    xattr -dr com.apple.quarantine "$INSTALL_DIR" 2>/dev/null || true
  fi

  rm -rf "$zip_path" "$extract_dir"
}

install_linux_service() {
  local core_service core_bin config_server
  core_service="/etc/systemd/system/easytier-core.service"
  core_bin="${INSTALL_DIR}/easytier-core"
  config_server="${CONFIG_PROTOCOL}://${DOMAIN}:${PORT}/${USERNAME}"

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

  systemctl daemon-reload
  systemctl enable --now easytier-core.service
}

install_linux_web_service() {
  local web_service="/etc/systemd/system/easytier-web-embed.service"
  cat > "$web_service" <<EOF
[Unit]
Description=EasyTier Web Embed Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/easytier-web-embed --db ${INSTALL_DIR}/et.db --api-server-port ${WEB_PORT} --api-server-addr 0.0.0.0 --api-host ${WEB_API_HOST} --config-server-port ${PORT} --config-server-protocol ${CONFIG_PROTOCOL}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now easytier-web-embed.service
}

write_macos_plist() {
  local plist_path="/Library/LaunchDaemons/easytier-core.plist"
  local config_server="${CONFIG_PROTOCOL}://${DOMAIN}:${PORT}/${USERNAME}"

  cat > "$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>easytier-core</string>
  <key>ProgramArguments</key>
  <array>
    <string>${INSTALL_DIR}/easytier-core</string>
    <string>--config-server</string>
    <string>${config_server}</string>
    <string>--hostname</string>
    <string>${HOSTNAME_VALUE}</string>
  </array>
  <key>WorkingDirectory</key><string>${INSTALL_DIR}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key><string>/var/root</string>
    <key>PATH</key><string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/var/log/easytier-core.log</string>
  <key>StandardErrorPath</key><string>/var/log/easytier-core.log</string>
</dict>
</plist>
EOF

  chown root:wheel "$plist_path"
  chmod 644 "$plist_path"
  launchctl bootstrap system "$plist_path"
  launchctl kickstart -k system/easytier-core
}

write_macos_web_plist() {
  local plist_path="/Library/LaunchDaemons/easytier-web-embed.plist"
  cat > "$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>easytier-web-embed</string>
  <key>ProgramArguments</key>
  <array>
    <string>${INSTALL_DIR}/easytier-web-embed</string>
    <string>--db</string><string>${INSTALL_DIR}/et.db</string>
    <string>--api-server-port</string><string>${WEB_PORT}</string>
    <string>--api-server-addr</string><string>0.0.0.0</string>
    <string>--api-host</string><string>${WEB_API_HOST}</string>
    <string>--config-server-port</string><string>${PORT}</string>
    <string>--config-server-protocol</string><string>${CONFIG_PROTOCOL}</string>
  </array>
  <key>WorkingDirectory</key><string>${INSTALL_DIR}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key><string>/var/root</string>
    <key>PATH</key><string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/var/log/easytier-web-embed.log</string>
  <key>StandardErrorPath</key><string>/var/log/easytier-web-embed.log</string>
</dict>
</plist>
EOF
  chown root:wheel "$plist_path"
  chmod 644 "$plist_path"
  launchctl bootstrap system "$plist_path"
  launchctl kickstart -k system/easytier-web-embed
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
  INSTALL_DIR="${INSTALL_DIR:-$(default_install_dir)}"

  info "Stopping and deleting EasyTier services..."
  stop_legacy_services
  if [[ "$OS_NAME" == "linux" ]]; then
    rm -f /etc/systemd/system/easytier-core.service
    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null || true
  else
    rm -f /Library/LaunchDaemons/easytier-core.plist
    rm -f /var/log/easytier-core.log /var/log/easytier-web-embed.log /var/log/easytier.log
  fi

  info "Deleting ${INSTALL_DIR}..."
  rm -rf "$INSTALL_DIR"
  success "EasyTier has been fully uninstalled."
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
  stop_legacy_services
  download_package

  if [[ "$OS_NAME" == "linux" ]]; then
    install_linux_service
    [[ "$INSTALL_WEB" == "yes" ]] && install_linux_web_service
  else
    write_macos_plist
    [[ "$INSTALL_WEB" == "yes" ]] && write_macos_web_plist
  fi

  success "安装完成。"
  echo "安装目录内容:"
  ls -la "$INSTALL_DIR"
  echo "检查服务:"
  if [[ "$OS_NAME" == "linux" ]]; then
    echo "  systemctl status easytier-core.service"
  else
    echo "  sudo launchctl list | grep easytier"
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
