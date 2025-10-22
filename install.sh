#!/usr/bin/env bash
# AIO Proxy v6.3 (selective services) - FlareSolverr + Crawl4AI + Cloudflare WARP (egress only)
# 2025-10-21
set -euo pipefail

# ===== 参数校验 =====
# 新增第 9 个参数：SERVICE_MODE（both|flare|crawl），默认 both
if [ "$#" -lt 7 ] || [ "$#" -gt 9 ]; then
  echo "用法: $0 <FLARE_USER> <FLARE_PASS> <FLARE_PORT> <C4AI_USER> <C4AI_PASS> <C4AI_PORT> <WARP_ON> [WARP_PLUS_KEY] [SERVICE_MODE]"
  echo "示例(两者+WARP on): $0 u1 p1 36584 u2 p2 36585 on"
  echo "示例(仅 FlareSolverr): $0 u1 p1 36584 u2 p2 36585 off '' flare"
  echo "示例(仅 Crawl4AI):    $0 u1 p1 36584 u2 p2 36585 off '' crawl"
  exit 1
fi
FLARE_USER="$1"; FLARE_PASS="$2"; FLARE_PORT="$3"
C4AI_USER="$4";  C4AI_PASS="$5";  C4AI_PORT="$6"
WARP_SWITCH_RAW="$7"
WARP_PLUS_KEY="${8-}"
SERVICE_MODE_RAW="${9:-both}"    # 【新增】

normalize_bool() {
  case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
    1|y|yes|on|true)  echo "true" ;;
    0|n|no|off|false) echo "false" ;;
    *) echo "false" ;;
  esac
}
normalize_mode() {               # 【新增】服务模式归一化
  case "$(echo "${1:-both}" | tr '[:upper:]' '[:lower:]')" in
    flare|flaresolverr) echo "flare" ;;
    crawl|crawl4ai)     echo "crawl" ;;
    both|"")            echo "both" ;;
    *)                  echo "both" ;;
  esac
}

WARP_ENABLED="$(normalize_bool "$WARP_SWITCH_RAW")"
SERVICE_MODE="$(normalize_mode "$SERVICE_MODE_RAW")"   # 【新增】

# ===== 常量 =====
APP_DIR="/opt/aio-proxy"
NGX_DIR="${APP_DIR}/nginx"
HT_FLARE="${NGX_DIR}/htpasswd_flaresolverr"
HT_C4AI="${NGX_DIR}/htpasswd_crawl4ai"
ENV_FILE="${APP_DIR}/.env"
TZ_DEFAULT="Europe/Berlin"
NET_NAME="aio-proxy-net"  # external 网络，所有容器加入

# ===== APT 锁等待 & 包管理辅助 =====
apt_wait_lock() {
  local lock="/var/lib/dpkg/lock-frontend"
  local i=0
  echo "[apt] waiting for dpkg lock if needed..."
  while fuser "$lock" >/dev/null 2>&1; do
    i=$((i+1))
    if [ $i -gt 300 ]; then
      echo "[apt] waited >300s for lock; still locked by other process."
      return 1
    fi
    sleep 1
  done
  return 0
}
apt_run() { apt_wait_lock || true; DEBIAN_FRONTEND=noninteractive apt-get -y "$@"; }

# ===== Docker 安装/启动 =====
if ! command -v docker >/dev/null 2>&1; then
  apt_run update
  apt_run install ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
  apt_run update
  apt_run install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
if command -v systemctl >/dev/null 2>&1; then
  systemctl enable --now docker >/dev/null 2>&1 || true
else
  service docker start >/dev/null 2>&1 || true
fi

detect_compose_bin() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
  else
    apt_run update; apt_run install docker-compose-plugin || true
    if docker compose version >/dev/null 2>&1; then echo "docker compose"; else echo "docker-compose"; fi
  fi
}
COMPOSE_BIN="$(detect_compose_bin)"

# ===== 依赖 =====
apt_run install apache2-utils curl

# ===== 目录与凭据（bcrypt htpasswd）=====
mkdir -p "${APP_DIR}" "${NGX_DIR}"
htpasswd -nbB "${FLARE_USER}" "${FLARE_PASS}" > "${HT_FLARE}"
htpasswd -nbB "${C4AI_USER}"  "${C4AI_PASS}"  > "${HT_C4AI}"

# ===== .env =====
cat > "${ENV_FILE}" <<EOF
# 全局
TZ=${TZ_DEFAULT}

# 对外端口（Nginx 暴露）
FLARE_PUBLIC_PORT=${FLARE_PORT}
CRAWL4AI_PUBLIC_PORT=${C4AI_PORT}

# WARP 开关与 Warp+
WARP_ENABLED=${WARP_ENABLED}
WARP_PLUS_KEY=${WARP_PLUS_KEY:-}

# 服务选择（both|flare|crawl）
SERVICE_MODE=${SERVICE_MODE}
# 内部端口（容器内固定）
FLARE_INTERNAL_PORT=8191
CRAWL4AI_INTERNAL_PORT=11235
EOF

# ===== Nginx 配置 =====
cat > "${NGX_DIR}/nginx.conf" <<'EOF'
worker_processes auto;

events { worker_connections 1024; }

http {
  include       /etc/nginx/mime.types;
  default_type  application/octet-stream;
  sendfile      on;
  keepalive_timeout 65;
  server_tokens off;

  # FlareSolverr
  server {
    listen 8081;
    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/htpasswd_flaresolverr;
    location / {
      proxy_set_header Host              $host;
      proxy_set_header X-Real-IP         $remote_addr;
      proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_http_version 1.1;
      proxy_set_header Connection "";
      proxy_pass http://flaresolverr:8191/;
    }
  }

  # Crawl4AI
  server {
    listen 8082;
    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/htpasswd_crawl4ai;
    location / {
      proxy_set_header Host              $host;
      proxy_set_header X-Real-IP         $remote_addr;
      proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_http_version 1.1;
      proxy_set_header Connection "";
      proxy_pass http://crawl4ai:11235/;
    }
  }
}
EOF

# ===== docker-compose.yml（external 网络；移除 edge 的 depends_on 以支持选择性启动）=====
cat > "${APP_DIR}/docker-compose.yml" <<'EOF'
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

  crawl4ai:
    image: unclecode/crawl4ai:latest
    restart: unless-stopped
    shm_size: "1g"
    expose:
      - "11235"
    networks: [ backend ]

  edge:
    image: nginx:alpine
    restart: unless-stopped
    # （移除 depends_on，便于只启其中一个上游）
    ports:
      - "${FLARE_PUBLIC_PORT}:8081"
      - "${CRAWL4AI_PUBLIC_PORT}:8082"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/htpasswd_flaresolverr:/etc/nginx/htpasswd_flaresolverr:ro
      - ./nginx/htpasswd_crawl4ai:/etc/nginx/htpasswd_crawl4ai:ro
    environment:
      - TZ=${TZ}
    networks: [ backend ]

networks:
  backend:
    external: true
    name: aio-proxy-net
EOF

# ===== docker-compose.warp.yml（保留业务对 warp 的 depends_on）=====
cat > "${APP_DIR}/docker-compose.warp.yml" <<'EOF'
services:
  warp:
    image: shahradel/cfw-proxy:latest
    restart: unless-stopped
    privileged: true
    cap_add: [ NET_ADMIN, SYS_MODULE ]
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv6.conf.all.disable_ipv6=0
    environment:
      - TZ=${TZ}
      - HTTP_PORT=8080
      - SOCKS5_PORT=1080
      - WGCF_LICENSE_KEY=${WARP_PLUS_KEY}
    networks: [ backend ]

  flaresolverr:
    depends_on: [ warp ]
    environment:
      - PROXY_URL=http://warp:8080

  crawl4ai:
    depends_on: [ warp ]
    environment:
      - HTTP_PROXY=http://warp:8080
      - HTTPS_PROXY=http://warp:8080
      - NO_PROXY=localhost,127.0.0.1,::1

networks:
  backend:
    external: true
    name: aio-proxy-net
EOF

# ===== manage.sh（按 SERVICE_MODE 选择性启动服务）=====
cat > "${APP_DIR}/manage.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

[ -f ".env" ] || { echo "未找到 .env"; exit 1; }
# shellcheck disable=SC1091
source .env

NET_NAME="aio-proxy-net"

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

compose_base=($COMPOSE_BIN -f docker-compose.yml)
compose_with_warp=($COMPOSE_BIN -f docker-compose.yml -f docker-compose.warp.yml)

ensure_external_net() {
  docker network inspect "${NET_NAME}" >/dev/null 2>&1 || \
  docker network create --driver bridge "${NET_NAME}" >/dev/null
}

normalize_mode() {
  case "$(echo "${1:-both}" | tr '[:upper:]' '[:lower:]')" in
    flare|flaresolverr) echo "flare" ;;
    crawl|crawl4ai)     echo "crawl" ;;
    both|"")            echo "both" ;;
    *)                  echo "both" ;;
  esac
}

selected_services() {
  local mode="$(normalize_mode "${SERVICE_MODE:-both}")"
  local arr=(edge)
  case "$mode" in
    flare) arr+=(flaresolverr) ;;
    crawl) arr+=(crawl4ai) ;;
    both)  arr+=(flaresolverr crawl4ai) ;;
  esac
  # 如果需要 WARP，业务容器会通过 depends_on 自动拉起 warp；无需显式添加。
  printf "%s\n" "${arr[@]}"
}

case "${1:-start}" in
  start|up)
    ensure_external_net
    mapfile -t SVC < <(selected_services)
    echo "[manage] SERVICE_MODE=${SERVICE_MODE:-both}  WARP_ENABLED=${WARP_ENABLED:-false}"
    echo "[manage] 即将启动服务: ${SVC[*]}"
    if [ "${WARP_ENABLED:-false}" = "true" ]; then
      "${compose_with_warp[@]}" up -d "${SVC[@]}"
    else
      "${compose_base[@]}" up -d "${SVC[@]}"
    fi
    ;;
  stop|down)
    echo "[manage] 停止..."
    "${compose_with_warp[@]}" down || true
    "${compose_base[@]}" down || true
    ;;
  restart)
    "$0" stop; "$0" start;;
  ps|status)
    "${compose_with_warp[@]}" ps;;
  logs)
    if [ "${WARP_ENABLED:-false}" = "true" ]; then
      "${compose_with_warp[@]}" logs -f --tail=200
    else
      "${compose_base[@]}" logs -f --tail=200
    fi
    ;;
  warp)
    shift || true
    want="${1:-}"
    case "$want" in
      on|enable|true)   sed -i 's/^WARP_ENABLED=.*/WARP_ENABLED=true/' .env ;;
      off|disable|false) sed -i 's/^WARP_ENABLED=.*/WARP_ENABLED=false/' .env ;;
      *) echo "用法: $0 warp {on|off}"; exit 1;;
    esac
    "$0" restart
    ;;
  set-mode)
    # ./manage.sh set-mode {both|flare|crawl}
    shift || true
    mode="${1:-both}"
    case "$(echo "$mode" | tr '[:upper:]' '[:lower:]')" in
      flare|flaresolverr) sed -i 's/^SERVICE_MODE=.*/SERVICE_MODE=flare/' .env ;;
      crawl|crawl4ai)     sed -i 's/^SERVICE_MODE=.*/SERVICE_MODE=crawl/' .env ;;
      both|"")            sed -i 's/^SERVICE_MODE=.*/SERVICE_MODE=both/' .env ;;
      *) echo "用法: $0 set-mode {both|flare|crawl}"; exit 1;;
    esac
    "$0" restart
    ;;
  set-credentials)
    svc="${2:-}"; user="${3:-}"; pass="${4:-}"
    if [ -z "${svc}" ] || [ -z "${user}" ] || [ -z "${pass}" ]; then
      echo "用法: $0 set-credentials {flaresolverr|crawl4ai} <user> <pass>"; exit 1
    fi
    case "$svc" in
      flaresolverr) ht=./nginx/htpasswd_flaresolverr;;
      crawl4ai)    ht=./nginx/htpasswd_crawl4ai;;
      *) echo "未知服务: $svc"; exit 1;;
    esac
    command -v htpasswd >/dev/null 2>&1 || { echo "需要安装 apache2-utils"; exit 1; }
    htpasswd -nbB "$user" "$pass" > "$ht"
    echo "[manage] 已更新 $svc 凭据，重启 edge ..."
    ${COMPOSE_BIN} restart edge
    ;;
  *)
    cat <<USAGE
用法: $0 {start|stop|restart|ps|logs|warp {on|off}|set-mode {both|flare|crawl}|set-credentials <svc> <user> <pass>}
USAGE
    exit 1;;
esac
EOF
chmod +x "${APP_DIR}/manage.sh"

# ===== external 网络兜底 =====
docker network inspect "${NET_NAME}" >/dev/null 2>&1 || docker network create --driver bridge "${NET_NAME}" >/dev/null

# ===== 选择性启动（按 .env 的 SERVICE_MODE + WARP_ENABLED）=====
cd "${APP_DIR}"
select_services() {            # 与 manage.sh 保持一致
  case "$(echo "${SERVICE_MODE}" | tr '[:upper:]' '[:lower:]')" in
    flare|flaresolverr) echo "edge flaresolverr" ;;
    crawl|crawl4ai)     echo "edge crawl4ai" ;;
    *)                  echo "edge flaresolverr crawl4ai" ;;
  esac
}
SVC_LIST=( $(select_services) )
echo "[install] SERVICE_MODE=${SERVICE_MODE}  WARP_ENABLED=${WARP_ENABLED}"
echo "[install] 首次启动服务: ${SVC_LIST[*]}"
if [ "${WARP_ENABLED}" = "true" ]; then
  ${COMPOSE_BIN} -f docker-compose.yml -f docker-compose.warp.yml up -d "${SVC_LIST[@]}"
else
  ${COMPOSE_BIN} -f docker-compose.yml up -d "${SVC_LIST[@]}"
fi

# ===== 公网 IP 提取工具 =====
parse_first_ip() {
  local s; s="$(cat || true)"
  local v4; v4="$(printf "%s" "$s" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1 || true)"
  if [ -n "$v4" ]; then printf "%s" "$v4"; return 0; fi
  local v6; v6="$(printf "%s" "$s" | grep -Eo '([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}' | head -n1 || true)"
  [ -n "$v6" ] && printf "%s" "$v6"
}

get_public_ip_host() { curl -sS -A Mozilla --max-time 5 https://api.ip.sb/ip | parse_first_ip || true; }
get_public_ip_via_warp_proxy() {
  docker run --rm --network "${NET_NAME}" curlimages/curl:8.8.0 \
    -sS -A Mozilla --max-time 5 -x http://warp:8080 https://api.ip.sb/ip | parse_first_ip || true
}

# ===== 安装期：自动检测 WARP（对比 IP），失败则自动回退 =====
auto_warp_check_and_fallback_ip() {
  cd "${APP_DIR}"
  # 若未开启 WARP 或 SERVICE_MODE 无业务（不会发生）则跳过
  if [ "${WARP_ENABLED}" != "true" ]; then
    echo "[auto] WARP disabled by user choice; skip checking."
    return 0
  fi
  # 仅当实际启动了 flaresolverr 或 crawl4ai 才有意义
  case "${SERVICE_MODE}" in
    flare|crawl|both) : ;;
    *) echo "[auto] no business service selected; skip checking."; return 0 ;;
  esac

  echo "[auto] checking WARP egress by comparing public IPs..."
  local host_ip warp_ip ok=0
  host_ip="$(get_public_ip_host || true)"
  echo "[auto] host public IP: ${host_ip:-<empty>}"
  sleep 6
  for try in $(seq 1 20); do
    echo "[auto] try #$try ..."
    warp_ip="$(get_public_ip_via_warp_proxy || true)"
    echo "[auto] warp(proxied) IP: ${warp_ip:-<empty>}"
    if [ -n "${warp_ip:-}" ] && { [ -z "${host_ip:-}" ] || [ "${warp_ip}" != "${host_ip}" ]; }; then
      ok=1; echo "[auto] WARP egress looks active (IP differs)."; break
    fi
    sleep 3
  done

  if [ "$ok" -eq 0 ]; then
    echo "[auto] WARP egress check failed; switching OFF and restarting without WARP..."
    sed -i "s/^WARP_ENABLED=.*/WARP_ENABLED=false/" .env
    ${COMPOSE_BIN} -f docker-compose.yml -f docker-compose.warp.yml down || true
    ${COMPOSE_BIN} -f docker-compose.yml up -d "${SVC_LIST[@]}"
    echo "[auto] fallback done. 以后可运行：cd ${APP_DIR} && ./manage.sh warp on"
  else
    echo "[auto] WARP OK."
  fi
}
auto_warp_check_and_fallback_ip

echo
echo "==================== 安装完成 (v6.3 selective) ===================="
echo "FlareSolverr ： http://<服务器>:${FLARE_PORT}    （BasicAuth）"
echo "Crawl4AI     ： http://<服务器>:${C4AI_PORT}     （/playground，BasicAuth）"
echo "WARP 状态    ： $(grep '^WARP_ENABLED=' ${ENV_FILE} | cut -d= -f2)"
echo "服务模式     ： $(grep '^SERVICE_MODE=' ${ENV_FILE} | cut -d= -f2)  （切换：cd ${APP_DIR} && ./manage.sh set-mode {both|flare|crawl}）"
echo "改密码       ： cd ${APP_DIR} && ./manage.sh set-credentials flaresolverr <user> <pass>"
echo "               cd ${APP_DIR} && ./manage.sh set-credentials crawl4ai    <user> <pass>"
echo "启停/日志    ： cd ${APP_DIR} && ./manage.sh {start|stop|restart|ps|logs}"
echo "WARP 开关    ： cd ${APP_DIR} && ./manage.sh warp {on|off}"
echo "==============================================================="
