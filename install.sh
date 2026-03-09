#!/usr/bin/env bash
# AIO Proxy - FlareSolverr only baseline installer
# 2026-03-08
set -euo pipefail

# ===== 常量 =====
APP_DIR="/opt/aio-proxy"
NGX_DIR="${APP_DIR}/nginx"
HT_FLARE="${NGX_DIR}/htpasswd_flaresolverr"
ENV_FILE="${APP_DIR}/.env"
TZ_DEFAULT="Europe/Berlin"
REMOTE_INSTALL_URL="https://raw.githubusercontent.com/dovetaill/crawl_tools/refs/heads/master/install.sh"
REMOTE_DOCKER_INSTALL_URL="https://raw.githubusercontent.com/dovetaill/crawl_tools/refs/heads/master/install_docker.sh"
SCRIPT_PATH="${BASH_SOURCE[0]-}"
if [ -n "${SCRIPT_PATH}" ] && [ -f "${SCRIPT_PATH}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
else
  SCRIPT_DIR="$(pwd)"
fi

# ===== 参数校验 =====
usage() {
  cat <<'USAGE'
用法:
  install.sh [--yes] [--update-docker] <FLARE_USER> <FLARE_PASS> <FLARE_PORT>
  install.sh [--quick]

说明:
  - 无参数启动时，进入 AIO Proxy 管理菜单（交互模式）
  - 传参启动时，按参数模式执行安装
  - 非交互且无输入时，会自动回退 --quick 一键安装

参数:
  --quick          一键快速安装（自动生成账号/密码/端口，非交互）
  --yes            非交互模式。按默认策略执行（未安装 Docker 默认安装；已安装默认不更新）
  --update-docker  强制执行 Docker 更新（优先级高于默认策略）
USAGE
}

ASSUME_YES="false"
FORCE_UPDATE_DOCKER="false"
QUICK_MODE="false"
POSITIONAL_ARGS=()

# ===== APT 锁等待 & 包管理辅助 =====
apt_wait_lock() {
  local lock="/var/lib/dpkg/lock-frontend"
  local i=0
  echo "[apt] waiting for dpkg lock if needed..."
  while fuser "$lock" >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "$i" -gt 300 ]; then
      echo "[apt] waited >300s for lock; still locked by other process."
      return 1
    fi
    sleep 1
  done
  return 0
}

apt_run() {
  apt_wait_lock || true
  DEBIAN_FRONTEND=noninteractive apt-get -y "$@"
}

detect_docker_repo_distribution() {
  local dist="debian"
  local id_like=""
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
      ubuntu|debian)
        dist="${ID}"
        ;;
      *)
        id_like="${ID_LIKE:-}"
        if echo " ${id_like} " | grep -qi ' ubuntu '; then
          dist="ubuntu"
        elif echo " ${id_like} " | grep -qi ' debian '; then
          dist="debian"
        fi
        ;;
    esac
  fi
  printf '%s' "$dist"
}

detect_docker_repo_codename() {
  local codename=""
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    codename="${VERSION_CODENAME:-}"
  fi
  if [ -z "$codename" ] && command -v lsb_release >/dev/null 2>&1; then
    codename="$(lsb_release -cs 2>/dev/null || true)"
  fi
  if [ -z "$codename" ]; then
    codename="stable"
  fi
  printf '%s' "$codename"
}

run_docker_installer_inline() {
  local action="$1"
  local dist=""
  local codename=""

  dist="$(detect_docker_repo_distribution)"
  codename="$(detect_docker_repo_codename)"

  echo "[install] 使用内置 Docker 安装流程（${dist}/${codename}）..."
  apt_run install ca-certificates curl gnupg lsb-release apt-transport-https
  install -m 0755 -d /etc/apt/keyrings
  rm -f /etc/apt/keyrings/docker.gpg
  curl -fsSL "https://download.docker.com/linux/${dist}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  cat > /etc/apt/sources.list.d/docker.list <<EOF_DOCKER_REPO
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${dist} ${codename} stable
EOF_DOCKER_REPO

  apt_run update
  if [ "$action" = "install" ]; then
    apt_run install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  elif command -v docker >/dev/null 2>&1; then
    apt_run install --only-upgrade docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  else
    echo "[install] update 模式下未检测到 Docker，自动回退 install。"
    apt_run install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi
}

is_interactive_terminal() {
  [ -t 0 ] && [ -t 1 ]
}

setup_ui_palette() {
  UI_RESET=""
  UI_BOLD=""
  UI_DIM=""
  UI_CYAN=""
  UI_GREEN=""
  UI_YELLOW=""
  if is_interactive_terminal && [ "${TERM:-dumb}" != "dumb" ]; then
    UI_RESET=$'\033[0m'
    UI_BOLD=$'\033[1m'
    UI_DIM=$'\033[2m'
    UI_CYAN=$'\033[36m'
    UI_GREEN=$'\033[32m'
    UI_YELLOW=$'\033[33m'
  fi
}
setup_ui_palette

confirm_with_number_input() {
  local prompt="$1"
  local default_choice="$2"
  local default_index="1"
  local answer=""

  if [ "$default_choice" = "no" ]; then
    default_index="2"
  fi

  echo "${prompt}"
  echo "  1) yes"
  echo "  2) no"
  while true; do
    read -r -p "请输入序号 [${default_index}]（q 退出）: " answer || true
    answer="$(echo "${answer:-}" | tr '[:upper:]' '[:lower:]')"
    if [ -z "$answer" ]; then
      [ "$default_index" = "1" ] && return 0 || return 1
    fi
    case "$answer" in
      1|y|yes) return 0 ;;
      2|n|no) return 1 ;;
      q|quit|exit)
        echo "[install] 用户取消操作。"
        exit 130
        ;;
      *)
        echo "请输入 1/2 或 q。"
        ;;
    esac
  done
}

confirm_with_default() {
  local prompt="$1"
  local default_choice="$2"
  confirm_with_number_input "$prompt" "$default_choice"
}

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "[install] 请使用 root 或 sudo 运行。"
    exit 1
  fi
}

validate_port() {
  local port="$1"
  if ! [[ "$port" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    return 1
  fi
  return 0
}

is_port_in_use() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltnH "( sport = :${port} )" 2>/dev/null | grep -q .
    return $?
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
    return $?
  fi
  if command -v netstat >/dev/null 2>&1; then
    netstat -ltn 2>/dev/null | awk '{print $4}' | grep -E "(^|[.:])${port}$" >/dev/null
    return $?
  fi
  return 1
}

get_existing_app_port() {
  if app_installed; then
    awk -F= '/^FLARE_PUBLIC_PORT=/{print $2}' "$ENV_FILE" 2>/dev/null || true
  fi
}

is_port_available_for_install() {
  local port="$1"
  local allow_existing_same="${2:-false}"
  local existing_port=""

  if ! is_port_in_use "$port"; then
    return 0
  fi
  if [ "$allow_existing_same" = "true" ]; then
    existing_port="$(get_existing_app_port)"
    if [ -n "${existing_port:-}" ] && [ "$existing_port" = "$port" ]; then
      return 0
    fi
  fi
  return 1
}

random_from_charset() {
  local length="$1"
  local charset="$2"
  local out=""
  local i=0
  local idx=0
  for ((i = 0; i < length; i++)); do
    idx=$((RANDOM % ${#charset}))
    out+="${charset:idx:1}"
  done
  printf '%s' "$out"
}

generate_random_username() {
  printf 'user_%s' "$(random_from_charset 6 'abcdefghijklmnopqrstuvwxyz0123456789')"
}

generate_random_password() {
  random_from_charset 16 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@#%+=_-'
}

generate_random_port() {
  local i=0
  local candidate=0
  for ((i = 0; i < 300; i++)); do
    candidate=$((20000 + RANDOM % 30000))
    if validate_port "$candidate" && is_port_available_for_install "$candidate" "false"; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  for ((candidate = 20000; candidate <= 65000; candidate++)); do
    if is_port_available_for_install "$candidate" "false"; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  printf '36584'
}

read_password_non_empty() {
  local prompt="$1"
  local value=""
  while true; do
    read -r -p "$prompt" value || true
    if [ -n "${value:-}" ]; then
      printf '%s' "$value"
      return 0
    fi
    echo "密码不能为空，请重试。"
  done
}

read_port_with_default() {
  local prompt="$1"
  local default_port="$2"
  local port_input=""
  while true; do
    read -r -p "$prompt [$default_port]: " port_input || true
    port_input="${port_input:-$default_port}"
    if validate_port "$port_input"; then
      printf '%s' "$port_input"
      return 0
    fi
    echo "端口必须为 1-65535 的数字。"
  done
}

run_docker_installer() {
  local action="$1"
  local installer="${SCRIPT_DIR}/install_docker.sh"
  local cmd=(bash "$installer" --action "$action")

  if [ -f "$installer" ]; then
    if [ "$ASSUME_YES" = "true" ]; then
      cmd+=(--yes)
    fi
    "${cmd[@]}"
    return 0
  fi

  echo "[install] 未找到 Docker 安装器: $installer"
  echo "[install] 回退到内置 Docker 安装流程（单脚本模式）。"
  run_docker_installer_inline "$action"
}

ensure_docker_runtime() {
  local should_update="false"

  if ! command -v docker >/dev/null 2>&1; then
    if [ "$ASSUME_YES" = "true" ] || confirm_with_default "未检测到 Docker，是否立即安装 Docker？" "yes"; then
      echo "[install] 开始安装 Docker..."
      run_docker_installer install
    else
      echo "[install] Docker 未安装，安装流程终止。"
      exit 1
    fi
  else
    if [ "$FORCE_UPDATE_DOCKER" = "true" ]; then
      should_update="true"
      echo "[install] 已启用 --update-docker，执行 Docker 更新。"
    elif [ "$ASSUME_YES" = "true" ]; then
      echo "[install] --yes 模式下，已安装 Docker 默认不更新。"
    elif confirm_with_default "检测到已安装 Docker，是否替换更新 Docker？" "no"; then
      should_update="true"
    fi

    if [ "$should_update" = "true" ]; then
      run_docker_installer update
    else
      echo "[install] 保留当前 Docker 版本。"
    fi
  fi

  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now docker >/dev/null 2>&1 || true
  else
    service docker start >/dev/null 2>&1 || true
  fi
}

detect_compose_bin() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
  else
    apt_run update
    apt_run install docker-compose-plugin || true
    if docker compose version >/dev/null 2>&1; then
      echo "docker compose"
    else
      echo "docker-compose"
    fi
  fi
}

app_installed() {
  [ -f "${APP_DIR}/docker-compose.yml" ] && [ -f "$ENV_FILE" ] && [ -f "$HT_FLARE" ]
}

run_manage() {
  local action="$1"
  if [ ! -x "${APP_DIR}/manage.sh" ]; then
    echo "[menu] 未检测到管理脚本: ${APP_DIR}/manage.sh"
    return 1
  fi
  "${APP_DIR}/manage.sh" "$action"
}

render_page_header() {
  local title="$1"
  local subtitle="${2:-}"
  if is_interactive_terminal; then
    printf '\033[H\033[2J'
  fi
  echo "${UI_CYAN}============================================================${UI_RESET}"
  echo "${UI_BOLD} ${title}${UI_RESET}"
  if [ -n "$subtitle" ]; then
    echo "${UI_DIM} ${subtitle}${UI_RESET}"
  fi
  echo "${UI_CYAN}------------------------------------------------------------${UI_RESET}"
}

render_page_footer() {
  echo "${UI_CYAN}============================================================${UI_RESET}"
}

show_current_config() {
  local current_user="(未安装)"
  local current_port="(未安装)"
  local docker_state="未安装"

  if command -v docker >/dev/null 2>&1; then
    docker_state="已安装"
  fi

  if app_installed; then
    current_user="$(cut -d: -f1 "$HT_FLARE" 2>/dev/null || echo '(读取失败)')"
    current_port="$(awk -F= '/^FLARE_PUBLIC_PORT=/{print $2}' "$ENV_FILE" 2>/dev/null || echo '(读取失败)')"
  fi

  render_page_header "当前配置" "密码仅显示为已设置状态，不回显明文。"
  echo "安装状态      : $(app_installed && echo 已安装 || echo 未安装)"
  echo "Docker 状态    : ${docker_state}"
  echo "用户名         : ${current_user}"
  echo "密码           : 已设置（密文存储，不可回显明文）"
  echo "对外端口       : ${current_port}"
  if app_installed && command -v docker >/dev/null 2>&1; then
    echo "服务状态       :"
    run_manage ps || true
  fi
  render_page_footer
}

install_or_reinstall_flow() {
  local user=""
  local pass=""
  local port=""
  local user_input=""
  local pass_input=""
  local port_input=""
  local random_user=""
  local random_pass=""
  local random_port=""

  require_root

  render_page_header "全新安装 / 重装" "留空可自动生成用户名、密码、端口。"

  if app_installed; then
    if ! confirm_with_default "检测到已有安装，继续将覆盖配置并重启服务，是否继续？" "no"; then
      echo "[menu] 已取消安装。"
      return 0
    fi
  fi

  random_user="$(generate_random_username)"
  random_pass="$(generate_random_password)"
  random_port="$(generate_random_port)"

  read -r -p "请输入 BasicAuth 用户名（留空自动生成） [${random_user}]: " user_input || true
  if [ -n "${user_input:-}" ]; then
    user="$user_input"
  else
    user="$random_user"
    echo "[menu] 未输入用户名，已自动生成: ${user}"
  fi

  read -r -p "请输入 BasicAuth 密码（留空自动生成） [按回车自动生成]: " pass_input || true
  if [ -n "${pass_input:-}" ]; then
    pass="$pass_input"
  else
    pass="$random_pass"
    echo "[menu] 未输入密码，已自动生成: ${pass}"
  fi

  while true; do
    read -r -p "请输入对外端口（留空自动生成） [${random_port}]: " port_input || true
    if [ -z "${port_input:-}" ]; then
      port="$random_port"
      echo "[menu] 未输入端口，已自动生成: ${port}"
      break
    fi
    if ! validate_port "$port_input"; then
      echo "端口必须为 1-65535 的数字。"
      continue
    fi
    if is_port_available_for_install "$port_input" "true"; then
      port="$port_input"
      break
    fi
    echo "端口已被占用，请重新输入或留空自动生成。"
  done

  perform_install "$user" "$pass" "$port"
}

update_credentials_flow() {
  local user=""
  local pass=""

  require_root
  render_page_header "修改账号密码" "密码为可见输入，修改后会自动重启 edge。"

  if ! app_installed; then
    echo "[menu] 尚未安装服务，请先执行安装。"
    return 1
  fi

  read -r -p "请输入新用户名 [admin]: " user || true
  user="${user:-admin}"
  pass="$(read_password_non_empty '请输入新密码: ')"

  apt_run install apache2-utils
  htpasswd -nbB "$user" "$pass" > "$HT_FLARE"
  echo "[menu] 凭据已更新，正在重启 edge..."
  run_manage restart
}

update_port_flow() {
  local current_port="36584"
  local new_port=""

  require_root
  render_page_header "修改对外端口" "变更后会自动重启服务。"

  if ! app_installed; then
    echo "[menu] 尚未安装服务，请先执行安装。"
    return 1
  fi

  current_port="$(awk -F= '/^FLARE_PUBLIC_PORT=/{print $2}' "$ENV_FILE" 2>/dev/null || echo '36584')"
  while true; do
    new_port="$(read_port_with_default '请输入新的对外端口' "$current_port")"
    if [ "$new_port" = "$current_port" ] || is_port_available_for_install "$new_port" "false"; then
      break
    fi
    echo "[menu] 新端口已被占用，请更换。"
  done

  sed -i "s/^FLARE_PUBLIC_PORT=.*/FLARE_PUBLIC_PORT=${new_port}/" "$ENV_FILE"
  echo "[menu] 端口已更新为 ${new_port}，正在重启服务..."
  run_manage restart
}

service_logs_flow() {
  if ! app_installed; then
    echo "[menu] 尚未安装服务。"
    return 1
  fi
  run_manage logs
}

uninstall_flow() {
  require_root
  render_page_header "卸载删除服务" "将删除 /opt/aio-proxy 及相关容器数据。"

  if ! app_installed; then
    echo "[menu] 未检测到已安装服务。"
    return 0
  fi

  if ! confirm_with_default "确认卸载并删除 ${APP_DIR} 及相关容器数据？" "no"; then
    echo "[menu] 已取消卸载。"
    return 0
  fi

  run_manage stop || true
  if command -v docker >/dev/null 2>&1; then
    docker compose -f "${APP_DIR}/docker-compose.yml" down -v || true
  fi
  rm -rf "$APP_DIR"
  echo "[menu] 卸载完成。"
}

pause_enter() {
  if is_interactive_terminal; then
    read -r -p "按 Enter 返回菜单..." _ || true
  fi
}

status_dashboard_snapshot() {
  local current_user="(未安装)"
  local current_port="(未安装)"
  local docker_state="未安装"

  if command -v docker >/dev/null 2>&1; then
    docker_state="已安装"
  fi
  if app_installed; then
    current_user="$(cut -d: -f1 "$HT_FLARE" 2>/dev/null || echo '(读取失败)')"
    current_port="$(awk -F= '/^FLARE_PUBLIC_PORT=/{print $2}' "$ENV_FILE" 2>/dev/null || echo '(读取失败)')"
  fi

  render_page_header "状态页" "使用数字选择刷新或服务操作。"
  echo "安装状态      : $(app_installed && echo 已安装 || echo 未安装)"
  echo "Docker 状态    : ${docker_state}"
  echo "用户名         : ${current_user}"
  echo "对外端口       : ${current_port}"
  echo
  echo "服务状态:"
  if app_installed && command -v docker >/dev/null 2>&1; then
    run_manage ps || true
  else
    echo "  （未安装或 Docker 不可用）"
  fi
  if [ -n "${STATUS_LAST_ACTION_MSG:-}" ]; then
    echo
    echo "${UI_YELLOW}${STATUS_LAST_ACTION_MSG}${UI_RESET}"
  fi
  echo
  echo " 1) 刷新"
  echo " 2) 启动服务"
  echo " 3) 停止服务"
  echo " 4) 重启服务"
  echo " 5) 查看实时日志"
  echo " 0) 返回上一级"
  render_page_footer
}

status_dashboard_flow() {
  local choice=""
  STATUS_LAST_ACTION_MSG=""

  while true; do
    status_dashboard_snapshot
    read -r -p "请选择操作 [0-5]: " choice || true
    case "${choice:-}" in
      0|q|Q|exit|quit)
        return 0
        ;;
      1|"")
        ;;
      2)
        if run_manage start >/dev/null 2>&1; then
          STATUS_LAST_ACTION_MSG="[status] 已执行启动。"
        else
          STATUS_LAST_ACTION_MSG="[status] 启动失败，请检查日志。"
        fi
        ;;
      3)
        if run_manage stop >/dev/null 2>&1; then
          STATUS_LAST_ACTION_MSG="[status] 已执行停止。"
        else
          STATUS_LAST_ACTION_MSG="[status] 停止失败，请检查日志。"
        fi
        ;;
      4)
        if run_manage restart >/dev/null 2>&1; then
          STATUS_LAST_ACTION_MSG="[status] 已执行重启。"
        else
          STATUS_LAST_ACTION_MSG="[status] 重启失败，请检查日志。"
        fi
        ;;
      5)
        if app_installed; then
          run_manage logs || true
          STATUS_LAST_ACTION_MSG="[status] 已退出日志查看。"
        else
          STATUS_LAST_ACTION_MSG="[status] 未安装服务，无法查看日志。"
        fi
        ;;
      *)
        STATUS_LAST_ACTION_MSG="[status] 无效选项，请输入 0-5。"
        ;;
    esac
  done
}

print_main_menu_numbered() {
  echo
  echo "${UI_CYAN}============================================================${UI_RESET}"
  echo "${UI_BOLD} AIO Proxy 控制台${UI_RESET}"
  echo "${UI_DIM} 说明: 账号/密码/端口支持留空自动生成${UI_RESET}"
  echo "${UI_CYAN}------------------------------------------------------------${UI_RESET}"
  echo " 1) 查看当前配置"
  echo " 2) 全新安装 / 重装"
  echo " 3) 修改账号密码"
  echo " 4) 修改对外端口"
  echo " 5) 启动服务"
  echo " 6) 停止服务"
  echo " 7) 重启服务"
  echo " 8) 状态页"
  echo " 9) 查看实时日志"
  echo "10) 卸载删除服务"
  echo " 0) 退出"
  echo "${UI_CYAN}============================================================${UI_RESET}"
}

menu_mode() {
  local choice=""

  while true; do
    print_main_menu_numbered
    read -r -p "请选择操作 [0-10]: " choice || true

    case "$choice" in
      1)
        show_current_config
        pause_enter
        ;;
      2)
        install_or_reinstall_flow
        pause_enter
        ;;
      3)
        update_credentials_flow || true
        pause_enter
        ;;
      4)
        update_port_flow || true
        pause_enter
        ;;
      5)
        run_manage start || true
        pause_enter
        ;;
      6)
        run_manage stop || true
        pause_enter
        ;;
      7)
        run_manage restart || true
        pause_enter
        ;;
      8)
        status_dashboard_flow || true
        ;;
      9)
        service_logs_flow || true
        ;;
      10)
        uninstall_flow || true
        pause_enter
        ;;
      0|q|Q|exit|quit)
        echo "[menu] 已退出。"
        return 0
        ;;
      *)
        echo "[menu] 无效选项，请重试。"
        pause_enter
        ;;
    esac
  done
}

write_env_file() {
  local flare_port="$1"
  cat > "${ENV_FILE}" <<EOF_ENV
# 全局
TZ=${TZ_DEFAULT}

# 对外端口（Nginx 暴露）
FLARE_PUBLIC_PORT=${flare_port}

# 内部端口（容器内固定）
FLARE_INTERNAL_PORT=8191
EOF_ENV
}

write_nginx_conf() {
  cat > "${NGX_DIR}/nginx.conf" <<'EOF_NGINX'
worker_processes auto;

events { worker_connections 1024; }

http {
  include       /etc/nginx/mime.types;
  default_type  application/octet-stream;
  sendfile      on;
  keepalive_timeout 65;
  server_tokens off;

  resolver 127.0.0.11 valid=30s ipv6=off;

  server {
    listen 8081;
    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/htpasswd_flaresolverr;

    location / {
      set $flare_upstream "flaresolverr:8191";
      proxy_set_header Host              $host;
      proxy_set_header X-Real-IP         $remote_addr;
      proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_http_version 1.1;
      proxy_set_header Connection "";
      proxy_pass http://$flare_upstream;
    }
  }
}
EOF_NGINX
}

write_compose_file() {
  cat > "${APP_DIR}/docker-compose.yml" <<'EOF_COMPOSE'
services:
  flaresolverr:
    image: flaresolverr/flaresolverr:latest
    restart: unless-stopped
    environment:
      - LOG_LEVEL=info
      - TZ=${TZ}
    expose:
      - "8191"
    shm_size: "1g"
    networks: [ backend ]

  edge:
    image: nginx:alpine
    restart: unless-stopped
    ports:
      - "${FLARE_PUBLIC_PORT}:8081"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/htpasswd_flaresolverr:/etc/nginx/htpasswd_flaresolverr:ro
    environment:
      - TZ=${TZ}
    networks: [ backend ]

networks:
  backend:
    driver: bridge
    name: aio-proxy-net
EOF_COMPOSE
}

write_manage_script() {
  cat > "${APP_DIR}/manage.sh" <<'EOF_MANAGE'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

[ -f ".env" ] || { echo "未找到 .env"; exit 1; }

detect_compose_bin() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
  else
    echo "docker compose"
  fi
}

COMPOSE_BIN="$(detect_compose_bin)"
compose_cmd=($COMPOSE_BIN -f docker-compose.yml)

open_install_menu() {
  if [ -x "./install.sh" ]; then
    exec bash ./install.sh
  fi
  echo "[manage] 未找到 ./install.sh，无法进入完整交互控制台。"
  echo "[manage] 可改为使用子命令维护：start/stop/restart/ps/logs/set-credentials/uninstall"
  exit 1
}

uninstall_runtime() {
  local assume_yes="${1:-}"
  local answer=""

  if [ "${assume_yes}" != "--yes" ]; then
    echo "将停止容器并删除 /opt/aio-proxy。"
    read -r -p "确认继续？[y/N]: " answer || true
    answer="$(echo "${answer:-}" | tr '[:upper:]' '[:lower:]')"
    case "${answer}" in
      y|yes) ;;
      *)
        echo "[manage] 已取消卸载。"
        return 0
        ;;
    esac
  fi

  "${compose_cmd[@]}" down -v --remove-orphans || true
  cd /
  rm -rf /opt/aio-proxy
  echo "[manage] 卸载完成。"
}

case "${1:-menu}" in
  menu|"")
    "$0" install-menu
    ;;
  install-menu)
    open_install_menu
    ;;
  start|up)
    "${compose_cmd[@]}" up -d flaresolverr edge
    ;;
  stop|down)
    "${compose_cmd[@]}" down || true
    ;;
  restart)
    "$0" stop
    "$0" start
    ;;
  ps|status)
    "${compose_cmd[@]}" ps
    ;;
  logs)
    "${compose_cmd[@]}" logs -f --tail=200
    ;;
  set-credentials)
    user="${2:-}"
    pass="${3:-}"
    if [ -z "${user}" ] || [ -z "${pass}" ]; then
      echo "用法: $0 set-credentials <user> <pass>"
      exit 1
    fi
    command -v htpasswd >/dev/null 2>&1 || { echo "需要安装 apache2-utils"; exit 1; }
    htpasswd -nbB "$user" "$pass" > ./nginx/htpasswd_flaresolverr
    echo "[manage] 已更新 flaresolverr 凭据，重启 edge ..."
    ${COMPOSE_BIN} restart edge
    ;;
  uninstall)
    uninstall_runtime "${2:-}"
    ;;
  *)
    cat <<USAGE
用法: $0 {menu|start|stop|restart|ps|logs|set-credentials <user> <pass>|uninstall}
  $0 menu            # 进入与 install.sh 相同的交互控制台
  $0 uninstall       # 交互确认后删除 /opt/aio-proxy
  $0 uninstall --yes # 非交互卸载
USAGE
    exit 1
    ;;
esac
EOF_MANAGE
  chmod +x "${APP_DIR}/manage.sh"
}

write_runtime_install_scripts() {
  local source_install="${SCRIPT_DIR}/install.sh"
  local source_docker_install="${SCRIPT_DIR}/install_docker.sh"
  local target_install="${APP_DIR}/install.sh"
  local target_docker_install="${APP_DIR}/install_docker.sh"

  if [ -f "${source_install}" ] && cp "${source_install}" "${target_install}"; then
    chmod +x "${target_install}"
  elif curl -fsSL "${REMOTE_INSTALL_URL}" -o "${target_install}"; then
    chmod +x "${target_install}"
    echo "[install] 已从远端补充 ${target_install}。"
  else
    cat > "${target_install}" <<'EOF_INSTALL_STUB'
#!/usr/bin/env bash
set -euo pipefail
REMOTE_INSTALL_URL="https://raw.githubusercontent.com/dovetaill/crawl_tools/refs/heads/master/install.sh"
TMP_SCRIPT="$(mktemp /tmp/aio-proxy-install.XXXXXX.sh)"
trap 'rm -f "${TMP_SCRIPT}"' EXIT
curl -fsSL "${REMOTE_INSTALL_URL}" -o "${TMP_SCRIPT}"
chmod +x "${TMP_SCRIPT}"
exec bash "${TMP_SCRIPT}" "$@"
EOF_INSTALL_STUB
    chmod +x "${target_install}"
    echo "[install] 本地源缺失且远端下载失败，已写入 ${target_install} 引导脚本。"
  fi

  if [ -f "${source_docker_install}" ] && cp "${source_docker_install}" "${target_docker_install}"; then
    chmod +x "${target_docker_install}"
  elif curl -fsSL "${REMOTE_DOCKER_INSTALL_URL}" -o "${target_docker_install}"; then
    chmod +x "${target_docker_install}"
    echo "[install] 已从远端补充 ${target_docker_install}。"
  fi
}

perform_install() {
  local flare_user="$1"
  local flare_pass="$2"
  local flare_port="$3"
  local compose_bin=""
  local retry_port=""
  local i=0

  require_root

  if ! validate_port "$flare_port"; then
    echo "[install] 端口非法: ${flare_port}"
    exit 1
  fi
  if ! is_port_available_for_install "$flare_port" "true"; then
    if [ "$QUICK_MODE" = "true" ]; then
      for ((i = 0; i < 30; i++)); do
        retry_port="$(generate_random_port)"
        if is_port_available_for_install "$retry_port" "false"; then
          echo "[quick] 端口 ${flare_port} 已被占用，自动重试为: ${retry_port}"
          flare_port="$retry_port"
          break
        fi
      done
      if ! is_port_available_for_install "$flare_port" "false"; then
        echo "[install] 无法找到可用端口，请稍后重试或手动指定。"
        exit 1
      fi
    else
      echo "[install] 端口已被占用: ${flare_port}"
      exit 1
    fi
  fi

  ensure_docker_runtime
  compose_bin="$(detect_compose_bin)"

  # ===== 依赖 =====
  apt_run install apache2-utils curl

  # ===== 目录与凭据（bcrypt htpasswd） =====
  mkdir -p "${APP_DIR}" "${NGX_DIR}"
  htpasswd -nbB "${flare_user}" "${flare_pass}" > "${HT_FLARE}"

  write_env_file "$flare_port"
  write_nginx_conf
  write_compose_file
  write_manage_script
  write_runtime_install_scripts

  # ===== 启动服务 =====
  cd "${APP_DIR}"
  ${compose_bin} -f docker-compose.yml up -d flaresolverr edge

  echo
  echo "${UI_GREEN}==================== 安装完成 ====================${UI_RESET}"
  echo "FlareSolverr ： http://<服务器>:${flare_port}    （BasicAuth）"
  echo "访问账号     ： ${flare_user}"
  echo "访问密码     ： ${flare_pass}"
  echo "说明         ：若账号/密码为自动生成，请立即保存。"
  echo "交互控制台   ： cd ${APP_DIR} && ./manage.sh"
  echo "改密码       ： cd ${APP_DIR} && ./manage.sh set-credentials <user> <pass>"
  echo "启停/日志    ： cd ${APP_DIR} && ./manage.sh {start|stop|restart|ps|logs}"
  echo "卸载删除     ： cd ${APP_DIR} && ./manage.sh uninstall"
  echo "${UI_GREEN}==================================================${UI_RESET}"
}

quick_install_flow() {
  local quick_user=""
  local quick_pass=""
  local quick_port=""

  require_root
  QUICK_MODE="true"
  ASSUME_YES="true"

  quick_user="$(generate_random_username)"
  quick_pass="$(generate_random_password)"
  quick_port="$(generate_random_port)"

  echo "[quick] 已启用一键快速安装（非交互）。"
  echo "[quick] 账号: ${quick_user}"
  echo "[quick] 密码: ${quick_pass}"
  echo "[quick] 端口: ${quick_port}"

  perform_install "${quick_user}" "${quick_pass}" "${quick_port}"
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --quick)
        QUICK_MODE="true"
        shift
        ;;
      --yes|-y)
        ASSUME_YES="true"
        shift
        ;;
      --update-docker)
        FORCE_UPDATE_DOCKER="true"
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      --)
        shift
        while [ "$#" -gt 0 ]; do
          POSITIONAL_ARGS+=("$1")
          shift
        done
        ;;
      -*)
        echo "未知参数: $1"
        usage
        exit 1
        ;;
      *)
        POSITIONAL_ARGS+=("$1")
        shift
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  if [ "$QUICK_MODE" = "true" ]; then
    quick_install_flow
    return 0
  fi

  # 无参数进入菜单模式
  if [ "${#POSITIONAL_ARGS[@]}" -eq 0 ] && [ "$ASSUME_YES" = "false" ] && [ "$FORCE_UPDATE_DOCKER" = "false" ]; then
    if ! is_interactive_terminal; then
      if ! IFS= read -r -t 0; then
        echo "[install] 检测到非交互终端且无可读输入，自动切换 --quick。"
        quick_install_flow
        return 0
      fi
    fi
    menu_mode
    return 0
  fi

  set -- "${POSITIONAL_ARGS[@]}"
  if [ "$#" -ne 3 ]; then
    usage
    return 1
  fi

  perform_install "$1" "$2" "$3"
}

main "$@"
