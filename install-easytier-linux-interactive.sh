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

INSTALL_DIR="/etc/easytier"
CORE_BIN="${INSTALL_DIR}/easytier-core"
WEB_BIN="${INSTALL_DIR}/easytier-web-embed"
CORE_SERVICE="/etc/systemd/system/easytier-core.service"
WEB_SERVICE="/etc/systemd/system/easytier-web-embed.service"
DEFAULT_VERSION="2.4.5"
GITHUB_PROXY_URL="https://github.misaka.nyc.mn/"

USERNAME=""
CONFIG_SERVER_ADDR=""
HOSTNAME_VALUE="$(hostname)"
MACHINE_ID=""
VERSION=""
INSTALL_CORE="yes"
INSTALL_WEB="yes"
WEB_API_PORT="11211"
WEB_API_ADDR="0.0.0.0"
WEB_API_HOST="http://127.0.0.1:11211"
WEB_CONFIG_PORT="22020"
WEB_CONFIG_PROTOCOL="udp"
USE_PROXY="auto"
UNINSTALL_ONLY="no"

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    error "请使用 root 运行：sudo $0"
    exit 1
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    error "缺少命令：$1"
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

prompt_required() {
  local var_name="$1"
  local question="$2"
  local answer

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
  交互式安装 EasyTier Core 和 EasyTier Web Embed。
  安装目录: ${INSTALL_DIR}
  Core 服务: easytier-core.service
  Web 服务: easytier-web-embed.service
EOF
}

parse_args() {
  case "${1:-}" in
    -h|--help)
      show_help
      exit 0
      ;;
    -x|--uninstall)
      UNINSTALL_ONLY="yes"
      ;;
    "")
      ;;
    *)
      error "未知参数：$1"
      show_help
      exit 1
      ;;
  esac
}

detect_platform() {
  local sys_arch
  sys_arch="$(uname -m)"

  case "$sys_arch" in
    x86_64) echo "x86_64" ;;
    aarch64) echo "aarch64" ;;
    armv7l)
      if grep -q "VFPv3" /proc/cpuinfo 2>/dev/null; then
        echo "armv7hf"
      else
        echo "armv7"
      fi
      ;;
    armhf|armv6l) echo "armhf" ;;
    arm) echo "arm" ;;
    *)
      error "不支持的系统架构：$sys_arch"
      exit 1
      ;;
  esac
}

get_latest_version() {
  local version_info latest_version
  version_info="$(curl -fsSL --connect-timeout 5 --max-time 10 https://api.github.com/repos/EasyTier/EasyTier/releases/latest || true)"
  latest_version="$(echo "$version_info" | grep -oE '"tag_name": *"v?[0-9]+\.[0-9]+\.[0-9]+"' | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"

  if [[ -n "$latest_version" ]]; then
    echo "$latest_version"
  else
    echo "$DEFAULT_VERSION"
  fi
}

detect_proxy() {
  if [[ "$USE_PROXY" != "auto" ]]; then
    return
  fi

  local ip_info
  ip_info="$(curl -fsSL --connect-timeout 3 --max-time 5 myip.ipip.net || true)"
  if echo "$ip_info" | grep -q "中国"; then
    USE_PROXY="yes"
  else
    USE_PROXY="no"
  fi
}

download_and_install() {
  local platform="$1"
  local version="$2"
  local base_url download_url package_name package_path extract_dir

  base_url="https://github.com/EasyTier/EasyTier/releases/download/v${version}/easytier-linux-${platform}-v${version}.zip"
  if [[ "$USE_PROXY" == "yes" ]]; then
    download_url="${GITHUB_PROXY_URL}${base_url#https://}"
  else
    download_url="$base_url"
  fi

  package_name="easytier-linux-${platform}-v${version}.zip"
  package_path="/tmp/${package_name}"
  extract_dir="/tmp/easytier-linux-${platform}"

  info "下载 EasyTier ${version} (${platform})..."
  info "下载地址：${download_url}"
  rm -rf "$package_path" "$extract_dir"
  curl -fL -o "$package_path" "$download_url" --connect-timeout 10 --max-time 120

  info "解压安装包..."
  unzip -q "$package_path" -d /tmp

  mkdir -p "$INSTALL_DIR"

  if [[ "$INSTALL_CORE" == "yes" ]]; then
    if [[ ! -f "${extract_dir}/easytier-core" ]]; then
      error "安装包中未找到 easytier-core"
      exit 1
    fi
    install -m 0755 "${extract_dir}/easytier-core" "$CORE_BIN"
  fi

  if [[ "$INSTALL_WEB" == "yes" ]]; then
    if [[ ! -f "${extract_dir}/easytier-web-embed" ]]; then
      error "安装包中未找到 easytier-web-embed"
      exit 1
    fi
    install -m 0755 "${extract_dir}/easytier-web-embed" "$WEB_BIN"
  fi

  rm -rf "$package_path" "$extract_dir"
}

write_web_service() {
  cat > "$WEB_SERVICE" <<EOF
[Unit]
Description=EasyTier Web Embedded Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${WEB_BIN} --api-server-port ${WEB_API_PORT} --api-server-addr ${WEB_API_ADDR} --api-host ${WEB_API_HOST} --config-server-port ${WEB_CONFIG_PORT} --config-server-protocol ${WEB_CONFIG_PROTOCOL}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

write_core_service() {
  local exec_start
  exec_start="${CORE_BIN} --config-server udp://${CONFIG_SERVER_ADDR}/${USERNAME} --hostname ${HOSTNAME_VALUE}"
  if [[ -n "$MACHINE_ID" ]]; then
    exec_start="${exec_start} --machine-id ${MACHINE_ID}"
  fi

  cat > "$CORE_SERVICE" <<EOF
[Unit]
Description=EasyTier Core Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
Environment=HOME=/root
ExecStart=${exec_start}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

stop_disable_remove() {
  local service_name="$1"
  local service_file="$2"

  if systemctl list-unit-files "$service_name" >/dev/null 2>&1; then
    systemctl stop "$service_name" 2>/dev/null || true
    systemctl disable "$service_name" 2>/dev/null || true
  fi
  rm -f "$service_file"
}

uninstall_easytier() {
  info "卸载 EasyTier 服务..."
  stop_disable_remove "easytier-core.service" "$CORE_SERVICE"
  stop_disable_remove "easytier-web-embed.service" "$WEB_SERVICE"
  stop_disable_remove "easytier.service" "/etc/systemd/system/easytier.service"
  systemctl daemon-reload

  prompt_yes_no REMOVE_FILES "是否删除 ${INSTALL_DIR} 下的程序和数据库文件？" "n"
  if [[ "$REMOVE_FILES" == "yes" ]]; then
    rm -rf "$INSTALL_DIR"
  else
    rm -f "$CORE_BIN" "$WEB_BIN"
  fi

  success "卸载完成。"
}

collect_inputs() {
  echo
  info "请选择安装内容"
  prompt_yes_no INSTALL_WEB "安装 easytier-web-embed 配置/Web 服务？" "$INSTALL_WEB"
  prompt_yes_no INSTALL_CORE "安装 easytier-core 节点服务？" "$INSTALL_CORE"

  if [[ "$INSTALL_WEB" != "yes" && "$INSTALL_CORE" != "yes" ]]; then
    error "至少需要安装一项。"
    exit 1
  fi

  prompt_default VERSION "EasyTier 版本，留空自动获取最新版，失败则使用 ${DEFAULT_VERSION}" ""
  if [[ -z "$VERSION" ]]; then
    VERSION="$(get_latest_version)"
  fi

  prompt_default USE_PROXY "是否使用 GitHub 代理下载？可选 yes/no/auto" "$USE_PROXY"

  if [[ "$INSTALL_WEB" == "yes" ]]; then
    echo
    info "Web Embed 配置"
    prompt_default WEB_API_PORT "API/Web 端口" "$WEB_API_PORT"
    prompt_default WEB_API_ADDR "API/Web 监听地址" "$WEB_API_ADDR"
    prompt_default WEB_API_HOST "前端使用的 API 地址" "$WEB_API_HOST"
    prompt_default WEB_CONFIG_PORT "配置服务器端口" "$WEB_CONFIG_PORT"
    prompt_default WEB_CONFIG_PROTOCOL "配置服务器协议 udp/tcp/ws" "$WEB_CONFIG_PROTOCOL"
  fi

  if [[ "$INSTALL_CORE" == "yes" ]]; then
    echo
    info "Core 节点配置"
    prompt_required USERNAME "请输入用户名，例如 jardy"

    local default_config_server
    if [[ "$INSTALL_WEB" == "yes" ]]; then
      default_config_server="127.0.0.1:${WEB_CONFIG_PORT}"
    else
      default_config_server="192.168.2.2:22020"
    fi

    prompt_default CONFIG_SERVER_ADDR "配置服务器地址，不要带 udp:// 和 /用户名" "$default_config_server"
    prompt_default HOSTNAME_VALUE "节点主机名" "$HOSTNAME_VALUE"
    prompt_default MACHINE_ID "Machine ID，可留空" ""
  fi
}

install_services() {
  local platform
  platform="$(detect_platform)"
  detect_proxy

  info "停止旧服务..."
  stop_disable_remove "easytier-core.service" "$CORE_SERVICE"
  stop_disable_remove "easytier-web-embed.service" "$WEB_SERVICE"
  stop_disable_remove "easytier.service" "/etc/systemd/system/easytier.service"

  download_and_install "$platform" "$VERSION"

  if [[ "$INSTALL_WEB" == "yes" ]]; then
    write_web_service
  fi

  if [[ "$INSTALL_CORE" == "yes" ]]; then
    write_core_service
  fi

  systemctl daemon-reload

  if [[ "$INSTALL_WEB" == "yes" ]]; then
    systemctl enable --now easytier-web-embed.service
  fi

  if [[ "$INSTALL_CORE" == "yes" ]]; then
    systemctl enable --now easytier-core.service
  fi

  echo
  success "安装完成。"
  echo
  info "服务状态："
  [[ "$INSTALL_WEB" == "yes" ]] && systemctl --no-pager --full status easytier-web-embed.service || true
  [[ "$INSTALL_CORE" == "yes" ]] && systemctl --no-pager --full status easytier-core.service || true

  echo
  info "常用命令："
  echo "  systemctl status easytier-web-embed.service"
  echo "  systemctl status easytier-core.service"
  echo "  journalctl -u easytier-web-embed.service -f"
  echo "  journalctl -u easytier-core.service -f"
}

main() {
  parse_args "$@"
  require_root
  require_cmd curl
  require_cmd unzip
  require_cmd systemctl

  if [[ "$UNINSTALL_ONLY" == "yes" ]]; then
    uninstall_easytier
    exit 0
  fi

  collect_inputs
  install_services
}

main "$@"
