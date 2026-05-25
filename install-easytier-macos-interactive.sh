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

INSTALL_DIR="/usr/local/bin/easytier"
CORE_BIN="${INSTALL_DIR}/easytier-core"
WEB_BIN="${INSTALL_DIR}/easytier-web-embed"
CORE_PLIST="/Library/LaunchDaemons/easytier-core.plist"
WEB_PLIST="/Library/LaunchDaemons/easytier-web-embed.plist"
CORE_LOG="/var/log/easytier-core.log"
WEB_LOG="/var/log/easytier-web-embed.log"
DEFAULT_VERSION="2.4.5"

USERNAME=""
CONFIG_SERVER_ADDR="192.168.2.2:22020"
HOSTNAME_VALUE="$(hostname -s 2>/dev/null || hostname)"
MACHINE_ID=""
VERSION=""
INSTALL_CORE="yes"
INSTALL_WEB="yes"
WEB_API_PORT="11211"
WEB_API_ADDR="0.0.0.0"
WEB_API_HOST="http://127.0.0.1:11211"
WEB_CONFIG_PORT="22020"
WEB_CONFIG_PROTOCOL="udp"
UNINSTALL_ONLY="no"

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    error "请使用 root 运行：sudo $0"
    exit 1
  fi
}

prompt_default() {
  local var_name="$1" question="$2" default_value="$3" answer
  read -r -p "${question} [${default_value}]: " answer
  printf -v "$var_name" '%s' "${answer:-$default_value}"
}

prompt_required() {
  local var_name="$1" question="$2" answer
  while true; do
    read -r -p "${question}: " answer
    if [[ -n "$answer" ]]; then
      printf -v "$var_name" '%s' "$answer"
      return
    fi
    warning "该项不能为空。"
  done
}

prompt_yes_no() {
  local var_name="$1" question="$2" default_value="$3" answer
  while true; do
    read -r -p "${question} [${default_value}]: " answer
    answer="${answer:-$default_value}"
    case "$answer" in
      y|Y|yes|YES|Yes) printf -v "$var_name" '%s' "yes"; return ;;
      n|N|no|NO|No) printf -v "$var_name" '%s' "no"; return ;;
      *) warning "请输入 y 或 n。" ;;
    esac
  done
}

show_help() {
  cat <<EOF
用法:
  sudo $0
  sudo $0 --uninstall

功能:
  交互式安装 EasyTier Core 和 EasyTier Web Embed 到 macOS launchd。
EOF
}

parse_args() {
  case "${1:-}" in
    -h|--help) show_help; exit 0 ;;
    -x|--uninstall) UNINSTALL_ONLY="yes" ;;
    "") ;;
    *) error "未知参数：$1"; show_help; exit 1 ;;
  esac
}

detect_platform() {
  case "$(uname -m)" in
    x86_64) echo "x86_64" ;;
    arm64|aarch64) echo "aarch64" ;;
    *) error "不支持的 macOS 架构：$(uname -m)"; exit 1 ;;
  esac
}

get_latest_version() {
  local version_info latest_version
  version_info="$(curl -fsSL --connect-timeout 5 --max-time 10 https://api.github.com/repos/EasyTier/EasyTier/releases/latest || true)"
  latest_version="$(echo "$version_info" | grep -oE '"tag_name": *"v?[0-9]+\.[0-9]+\.[0-9]+"' | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
  echo "${latest_version:-$DEFAULT_VERSION}"
}

download_and_install() {
  local platform="$1" version="$2" url zip_path extract_dir
  url="https://github.com/EasyTier/EasyTier/releases/download/v${version}/easytier-macos-${platform}-v${version}.zip"
  zip_path="/tmp/easytier-macos-${platform}-v${version}.zip"
  extract_dir="/tmp/easytier-macos-${platform}"

  info "下载 EasyTier ${version} (${platform})..."
  rm -rf "$zip_path" "$extract_dir"
  curl -fL -o "$zip_path" "$url" --connect-timeout 10 --max-time 120
  unzip -q "$zip_path" -d /tmp

  mkdir -p "$INSTALL_DIR"
  if [[ "$INSTALL_CORE" == "yes" ]]; then
    install -m 0755 "${extract_dir}/easytier-core" "$CORE_BIN"
  fi
  if [[ "$INSTALL_WEB" == "yes" ]]; then
    install -m 0755 "${extract_dir}/easytier-web-embed" "$WEB_BIN"
  fi
  xattr -dr com.apple.quarantine "$INSTALL_DIR" 2>/dev/null || true
  rm -rf "$zip_path" "$extract_dir"
}

bootout_plist() {
  local plist="$1"
  launchctl bootout system "$plist" 2>/dev/null || true
}

write_web_plist() {
  cat > "$WEB_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>easytier-web-embed</string>
  <key>ProgramArguments</key>
  <array>
    <string>${WEB_BIN}</string>
    <string>--db</string><string>${INSTALL_DIR}/et.db</string>
    <string>--api-server-port</string><string>${WEB_API_PORT}</string>
    <string>--api-server-addr</string><string>${WEB_API_ADDR}</string>
    <string>--api-host</string><string>${WEB_API_HOST}</string>
    <string>--config-server-port</string><string>${WEB_CONFIG_PORT}</string>
    <string>--config-server-protocol</string><string>${WEB_CONFIG_PROTOCOL}</string>
  </array>
  <key>WorkingDirectory</key><string>${INSTALL_DIR}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key><string>/var/root</string>
    <key>PATH</key><string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${WEB_LOG}</string>
  <key>StandardErrorPath</key><string>${WEB_LOG}</string>
</dict>
</plist>
EOF
}

write_core_plist() {
  local machine_block=""
  if [[ -n "$MACHINE_ID" ]]; then
    machine_block="    <string>--machine-id</string><string>${MACHINE_ID}</string>"
  fi

  cat > "$CORE_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>easytier-core</string>
  <key>ProgramArguments</key>
  <array>
    <string>${CORE_BIN}</string>
    <string>--config-server</string><string>udp://${CONFIG_SERVER_ADDR}/${USERNAME}</string>
    <string>--hostname</string><string>${HOSTNAME_VALUE}</string>
${machine_block}
  </array>
  <key>WorkingDirectory</key><string>${INSTALL_DIR}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key><string>/var/root</string>
    <key>PATH</key><string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${CORE_LOG}</string>
  <key>StandardErrorPath</key><string>${CORE_LOG}</string>
</dict>
</plist>
EOF
}

uninstall_easytier() {
  info "卸载 EasyTier launchd 服务..."
  bootout_plist "$CORE_PLIST"
  bootout_plist "$WEB_PLIST"
  rm -f "$CORE_PLIST" "$WEB_PLIST"
  prompt_yes_no REMOVE_FILES "是否删除 ${INSTALL_DIR} 下的程序和数据库文件？" "n"
  if [[ "$REMOVE_FILES" == "yes" ]]; then
    rm -rf "$INSTALL_DIR"
  else
    rm -f "$CORE_BIN" "$WEB_BIN"
  fi
  success "卸载完成。"
}

collect_inputs() {
  prompt_yes_no INSTALL_WEB "安装 easytier-web-embed 配置/Web 服务？" "$INSTALL_WEB"
  prompt_yes_no INSTALL_CORE "安装 easytier-core 节点服务？" "$INSTALL_CORE"
  if [[ "$INSTALL_WEB" != "yes" && "$INSTALL_CORE" != "yes" ]]; then
    error "至少需要安装一项。"
    exit 1
  fi

  prompt_default VERSION "EasyTier 版本，留空自动获取最新版，失败则使用 ${DEFAULT_VERSION}" ""
  [[ -z "$VERSION" ]] && VERSION="$(get_latest_version)"

  if [[ "$INSTALL_WEB" == "yes" ]]; then
    prompt_default WEB_API_PORT "API/Web 端口" "$WEB_API_PORT"
    prompt_default WEB_API_ADDR "API/Web 监听地址" "$WEB_API_ADDR"
    prompt_default WEB_API_HOST "前端使用的 API 地址" "$WEB_API_HOST"
    prompt_default WEB_CONFIG_PORT "配置服务器端口" "$WEB_CONFIG_PORT"
    prompt_default WEB_CONFIG_PROTOCOL "配置服务器协议 udp/tcp/ws" "$WEB_CONFIG_PROTOCOL"
  fi

  if [[ "$INSTALL_CORE" == "yes" ]]; then
    prompt_required USERNAME "请输入用户名，例如 jardy"
    local default_server="$CONFIG_SERVER_ADDR"
    [[ "$INSTALL_WEB" == "yes" ]] && default_server="127.0.0.1:${WEB_CONFIG_PORT}"
    prompt_default CONFIG_SERVER_ADDR "配置服务器地址，不要带 udp:// 和 /用户名" "$default_server"
    prompt_default HOSTNAME_VALUE "节点主机名" "$HOSTNAME_VALUE"
    prompt_default MACHINE_ID "Machine ID，可留空" ""
  fi
}

install_services() {
  local platform
  platform="$(detect_platform)"
  bootout_plist "$CORE_PLIST"
  bootout_plist "$WEB_PLIST"
  download_and_install "$platform" "$VERSION"

  if [[ "$INSTALL_WEB" == "yes" ]]; then
    write_web_plist
    chown root:wheel "$WEB_PLIST"
    chmod 644 "$WEB_PLIST"
    launchctl bootstrap system "$WEB_PLIST"
    launchctl kickstart -k system/easytier-web-embed
  fi

  if [[ "$INSTALL_CORE" == "yes" ]]; then
    write_core_plist
    chown root:wheel "$CORE_PLIST"
    chmod 644 "$CORE_PLIST"
    launchctl bootstrap system "$CORE_PLIST"
    launchctl kickstart -k system/easytier-core
  fi

  success "安装完成。"
  echo "检查命令："
  echo "  sudo launchctl list | grep easytier"
  echo "  tail -50 ${CORE_LOG}"
  echo "  tail -50 ${WEB_LOG}"
}

main() {
  parse_args "$@"
  require_root
  command -v curl >/dev/null || { error "缺少 curl"; exit 1; }
  command -v unzip >/dev/null || { error "缺少 unzip"; exit 1; }
  if [[ "$UNINSTALL_ONLY" == "yes" ]]; then
    uninstall_easytier
    exit 0
  fi
  collect_inputs
  install_services
}

main "$@"
