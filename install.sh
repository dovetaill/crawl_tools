#!/usr/bin/env bash
# AIO Proxy - FlareSolverr only baseline installer
# 2026-03-08
set -euo pipefail

# ===== 参数校验 =====
usage() {
  cat <<'USAGE'
用法:
  install.sh [--yes] [--update-docker] <FLARE_USER> <FLARE_PASS> <FLARE_PORT>

参数:
  --yes            非交互模式。按默认策略执行（未安装 Docker 默认安装；已安装默认不更新）
  --update-docker  强制执行 Docker 更新（优先级高于默认策略）
USAGE
}

ASSUME_YES="false"
FORCE_UPDATE_DOCKER="false"
POSITIONAL_ARGS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
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

set -- "${POSITIONAL_ARGS[@]}"
if [ "$#" -ne 3 ]; then
  usage
  exit 1
fi

FLARE_USER="$1"
FLARE_PASS="$2"
FLARE_PORT="$3"

# ===== 常量 =====
APP_DIR="/opt/aio-proxy"
NGX_DIR="${APP_DIR}/nginx"
HT_FLARE="${NGX_DIR}/htpasswd_flaresolverr"
ENV_FILE="${APP_DIR}/.env"
TZ_DEFAULT="Europe/Berlin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

is_interactive_terminal() {
  [ -t 0 ] && [ -t 1 ]
}

can_use_arrow_menu() {
  is_interactive_terminal && command -v tput >/dev/null 2>&1 && [ "${TERM:-dumb}" != "dumb" ]
}

menu_cleanup() {
  tput cnorm >/dev/null 2>&1 || true
  tput sgr0 >/dev/null 2>&1 || true
}

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

confirm_with_arrow_menu() {
  local prompt="$1"
  local default_choice="$2"
  local options=("yes" "no")
  local selected=0
  local default_index=0
  local key=""
  local key_rest=""
  local idx=0
  local prev_exit_trap=""

  if [ "$default_choice" = "no" ]; then
    default_index=1
    selected=1
  fi

  prev_exit_trap="$(trap -p EXIT || true)"
  trap 'menu_cleanup' EXIT
  tput civis >/dev/null 2>&1 || true
  tput sc >/dev/null 2>&1 || true

  while true; do
    tput rc >/dev/null 2>&1 || true
    tput ed >/dev/null 2>&1 || true
    printf "%s\n" "${prompt}"
    for idx in "${!options[@]}"; do
      if [ "$idx" -eq "$selected" ]; then
        printf "> %s" "${options[$idx]}"
      else
        printf "  %s" "${options[$idx]}"
      fi
      if [ "$idx" -eq "$default_index" ]; then
        printf " (default)"
      fi
      printf "\n"
    done
    printf "使用 ↑/↓ 选择，Enter 确认，q 退出。\n"

    IFS= read -rsn1 key || true
    case "$key" in
      "")
        break
        ;;
      q|Q)
        menu_cleanup
        [ -n "$prev_exit_trap" ] && eval "$prev_exit_trap" || trap - EXIT
        echo
        echo "[install] 用户取消操作。"
        exit 130
        ;;
      $'\x1b')
        IFS= read -rsn2 -t 0.1 key_rest || true
        key="${key}${key_rest:-}"
        case "$key" in
          $'\x1b[A')
            selected=$((selected - 1))
            if [ "$selected" -lt 0 ]; then
              selected=$((${#options[@]} - 1))
            fi
            ;;
          $'\x1b[B')
            selected=$((selected + 1))
            if [ "$selected" -ge "${#options[@]}" ]; then
              selected=0
            fi
            ;;
        esac
        ;;
    esac
  done

  menu_cleanup
  [ -n "$prev_exit_trap" ] && eval "$prev_exit_trap" || trap - EXIT
  tput rc >/dev/null 2>&1 || true
  tput ed >/dev/null 2>&1 || true

  [ "$selected" -eq 0 ]
}

confirm_with_default() {
  local prompt="$1"
  local default_choice="$2"

  if can_use_arrow_menu; then
    confirm_with_arrow_menu "$prompt" "$default_choice"
  else
    if ! is_interactive_terminal; then
      echo "[install] 非 TTY 终端，回退到数字输入模式。"
    fi
    confirm_with_number_input "$prompt" "$default_choice"
  fi
}

run_docker_installer() {
  local action="$1"
  local installer="${SCRIPT_DIR}/install_docker.sh"
  local cmd=(bash "$installer" --action "$action")

  if [ ! -f "$installer" ]; then
    echo "[install] 未找到 Docker 安装器: $installer"
    exit 1
  fi
  if [ "$ASSUME_YES" = "true" ]; then
    cmd+=(--yes)
  fi
  "${cmd[@]}"
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

# ===== Docker 安装/更新策略 =====
ensure_docker_runtime

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

COMPOSE_BIN="$(detect_compose_bin)"

# ===== 依赖 =====
apt_run install apache2-utils curl

# ===== 目录与凭据（bcrypt htpasswd） =====
mkdir -p "${APP_DIR}" "${NGX_DIR}"
htpasswd -nbB "${FLARE_USER}" "${FLARE_PASS}" > "${HT_FLARE}"

# ===== .env =====
cat > "${ENV_FILE}" <<EOF_ENV
# 全局
TZ=${TZ_DEFAULT}

# 对外端口（Nginx 暴露）
FLARE_PUBLIC_PORT=${FLARE_PORT}

# 内部端口（容器内固定）
FLARE_INTERNAL_PORT=8191
EOF_ENV

# ===== Nginx 配置 =====
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

# ===== docker-compose.yml =====
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

# ===== manage.sh =====
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

case "${1:-start}" in
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
  *)
    cat <<USAGE
用法: $0 {start|stop|restart|ps|logs|set-credentials <user> <pass>}
USAGE
    exit 1
    ;;
esac
EOF_MANAGE
chmod +x "${APP_DIR}/manage.sh"

# ===== 启动服务 =====
cd "${APP_DIR}"
${COMPOSE_BIN} -f docker-compose.yml up -d flaresolverr edge

echo
echo "==================== 安装完成 ===================="
echo "FlareSolverr ： http://<服务器>:${FLARE_PORT}    （BasicAuth）"
echo "改密码       ： cd ${APP_DIR} && ./manage.sh set-credentials <user> <pass>"
echo "启停/日志    ： cd ${APP_DIR} && ./manage.sh {start|stop|restart|ps|logs}"
echo "=================================================="
