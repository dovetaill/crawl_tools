#!/usr/bin/env bash
# AIO Proxy v6.2 - FlareSolverr + Crawl4AI + Cloudflare WARP (egress only)
# 2025-10-21
set -euo pipefail

# ===== 参数校验 =====
if [ "$#" -lt 7 ] || [ "$#" -gt 8 ]; then
  echo "用法: $0 <FLARE_USER> <FLARE_PASS> <FLARE_PORT> <C4AI_USER> <C4AI_PASS> <C4AI_PORT> <WARP_ON> [WARP_PLUS_KEY]"
  echo "示例: $0 u1 p1 36584 u2 p2 36585 on"
  exit 1
fi
FLARE_USER="$1"; FLARE_PASS="$2"; FLARE_PORT="$3"
C4AI_USER="$4";  C4AI_PASS="$5";  C4AI_PORT="$6"
WARP_SWITCH_RAW="$7"
WARP_PLUS_KEY="${8-}"

normalize_bool() {
  case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
    1|y|yes|on|true)  echo "true" ;;
    0|n|no|off|false) echo "false" ;;
    *) echo "false" ;;
  esac
}
WARP_ENABLED="$(normalize_bool "$WARP_SWITCH_RAW")"

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
apt_run() {
  apt_wait_lock || true
  DEBIAN_FRONTEND=noninteractive apt-get -y "$@"
}

# ===== Docker 安装/启动 =====
if ! command -v docker >/dev/null 2>&1; then
  apt_run update
  apt_run install ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt_run update
  apt_run install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
# 启动 docker 服务
if command -v systemctl >/dev/null 2>&1; then
  systemctl enable --now docker >/dev/null 2>&1 || true
else
  service docker start >/dev/null 2>&1 || true
fi

# 检测 compose 命令
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

# ===== docker-compose.yml（统一 external 网络：aio-proxy-net）=====
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
    depends_on:
      - flaresolverr
      - crawl4ai
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

# ===== docker-compose.warp.yml（warp 明确加入 backend，含健康检查）=====
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
    # 健康检查：尽量用容器自带的 wget/curl；若镜像变动导致缺失，可改为 nc 或 /proc/net/tcp 检测
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:8080 >/dev/null 2>&1 || curl -fsS http://127.0.0.1:8080 >/dev/null 2>&1"]
      interval: 5s
      timeout: 3s
      retries: 12
      start_period: 10s
    networks: [ backend ]

  flaresolverr:
    depends_on:
      warp:
        condition: service_healthy
    environment:
      - PROXY_URL=http://warp:8080

  crawl4ai:
    depends_on:
      warp:
        condition: service_healthy
    environment:
      - HTTP_PROXY=http://warp:8080
      - HTTPS_PROXY=http://warp:8080
      - NO_PROXY=localhost,127.0.0.1,::1

networks:
  backend:
    external: true
    name: aio-proxy-net
EOF

# ===== manage.sh =====
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

case "${1:-start}" in
  start|up)
    ensure_external_net
    if [ "${WARP_ENABLED:-false}" = "true" ]; then
      echo "[manage] 启动（含 WARP）..."
      "${compose_with_warp[@]}" up -d
    else
      echo "[manage] 启动（不含 WARP）..."
      "${compose_base[@]}" up -d
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
    # 显示所有可能的服务，避免漏看 warp
    "${compose_with_warp[@]}" ps;;
  logs)
    # 根据当前 .env 中的开关选择日志集合
    if [ "${WARP_ENABLED:-false}" = "true" ]; then
      "${compose_with_warp[@]}" logs -f --tail=200
    else
      "${compose_base[@]}" logs -f --tail=200
    fi
    ;;
  warp)
    # ./manage.sh warp on|off
    shift || true
    want="${1:-}"
    case "$want" in
      on|enable|true)   sed -i 's/^WARP_ENABLED=.*/WARP_ENABLED=true/' .env ;;
      off|disable|false) sed -i 's/^WARP_ENABLED=.*/WARP_ENABLED=false/' .env ;;
      *) echo "用法: $0 warp {on|off}"; exit 1;;
    esac
    "$0" restart
    ;;
  set-credentials)
    # ./manage.sh set-credentials flaresolverr <user> <pass>
    # ./manage.sh set-credentials crawl4ai    <user> <pass>
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
用法: $0 {start|stop|restart|ps|logs|warp {on|off}|set-credentials <svc> <user> <pass>}
USAGE
    exit 1;;
esac
EOF
chmod +x "${APP_DIR}/manage.sh"

# ===== external 网络兜底 =====
docker network inspect "${NET_NAME}" >/dev/null 2>&1 || \
docker network create --driver bridge "${NET_NAME}" >/dev/null

# ===== 启动（按 .env 的 WARP_ENABLED）=====
cd "${APP_DIR}"
if [ "${WARP_ENABLED}" = "true" ]; then
  ${COMPOSE_BIN} -f docker-compose.yml -f docker-compose.warp.yml up -d
else
  ${COMPOSE_BIN} -f docker-compose.yml up -d
fi

# ===== 自动检测 WARP；不可用则自动回退为直连（修复竞态与探活）=====
auto_warp_check_and_fallback() {
  cd "${APP_DIR}"
  if [ "${WARP_ENABLED}" != "true" ]; then
    echo "[auto] WARP disabled by user choice; skip checking."
    return 0
  fi

  echo "[auto] checking warp reachability..."
  local ok=0

  # 最多 45 次 * 2s ≈ 90 秒，给首次注册/握手留足缓冲
  for try in $(seq 1 45); do
    echo "[auto] try #$try ..."

    # 用 compose 的 label 找容器，避免依赖项目名/目录名
    local warp_id
    warp_id="$(docker ps -q --filter "label=com.docker.compose.service=warp" || true)"

    if [ -n "$warp_id" ]; then
      # 取 IP（多网络时取第一个）
      local warp_ip
      warp_ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$warp_id" 2>/dev/null | awk '{print $1}')"

      if [ -n "${warp_ip}" ]; then
        # A) 纯 TCP 探测：能建连就算可达（不依赖 HTTP）
        if timeout 2 bash -lc "exec 3<>/dev/tcp/${warp_ip}/8080" 2>/dev/null; then
          ok=1; break
        fi
        # B) 普通 GET（避免 -I/HEAD 带来的实现差异）
        curl -sS --connect-timeout 2 "http://${warp_ip}:8080" >/dev/null 2>&1 && { ok=1; break; }
      fi

      # C) 在同一网络内用服务名直连（无需知道 IP）
      # （第一次会拉取小镜像 curlimages/curl，如不想拉可注释掉）
      docker run --rm --network "${NET_NAME}" curlimages/curl:8.8.0 \
        -sS --connect-timeout 2 "http://warp:8080" >/dev/null 2>&1 && { ok=1; break; }
    fi

    sleep 2
  done

  if [ "$ok" -eq 0 ]; then
    echo "[auto] warp seems unreachable; turning it OFF and restarting without warp..."
    sed -i "s/^WARP_ENABLED=.*/WARP_ENABLED=false/" .env
    ${COMPOSE_BIN} -f docker-compose.yml -f docker-compose.warp.yml down || true
    ${COMPOSE_BIN} -f docker-compose.yml up -d
    echo "[auto] fallback done. You can later enable with: cd ${APP_DIR} && ./manage.sh warp on"
  else
    echo "[auto] warp looks reachable."
  fi
}
auto_warp_check_and_fallback

echo
echo "==================== 安装完成 (v6.2) ===================="
echo "FlareSolverr ： http://<服务器>:${FLARE_PORT}    （BasicAuth）"
echo "Crawl4AI     ： http://<服务器>:${C4AI_PORT}     （/playground，BasicAuth）"
echo "WARP 状态    ： $(grep '^WARP_ENABLED=' ${ENV_FILE} | cut -d= -f2)  （切换：cd ${APP_DIR} && ./manage.sh warp on|off）"
echo "改密码       ： cd ${APP_DIR} && ./manage.sh set-credentials flaresolverr <user> <pass>"
echo "               cd ${APP_DIR} && ./manage.sh set-credentials crawl4ai    <user> <pass>"
echo "查看日志     ： cd ${APP_DIR} && ./manage.sh logs"
echo "======================================================="
