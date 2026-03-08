#!/usr/bin/env bash
# Docker installer/updater for Debian-like systems
set -euo pipefail

usage() {
  cat <<'USAGE'
用法:
  install_docker.sh [--action install|update] [--yes]

参数:
  --action install   安装 Docker（默认）
  --action update    更新现有 Docker（若未安装则自动执行安装）
  --yes              非交互确认（为后续自动化调用预留）
USAGE
}

ACTION="install"
ASSUME_YES="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --action)
      ACTION="${2:-}"
      shift 2
      ;;
    --yes|-y)
      ASSUME_YES="true"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: 未知参数: $1"
      usage
      exit 1
      ;;
  esac
done

case "$ACTION" in
  install|update) ;;
  *)
    echo "ERROR: --action 仅支持 install 或 update"
    exit 1
    ;;
esac

SUDO=""
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "ERROR: 当前非 root 且未安装 sudo，无法继续。"
    exit 1
  fi
fi

run_root() {
  if [ -n "$SUDO" ]; then
    "$SUDO" "$@"
  else
    "$@"
  fi
}

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
  run_root env DEBIAN_FRONTEND=noninteractive apt-get -y "$@"
}

ensure_docker_repo() {
  echo "INFO: 配置 Docker APT 软件源..."
  apt_run install ca-certificates curl gnupg lsb-release apt-transport-https
  run_root install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | run_root gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  run_root chmod a+r /etc/apt/keyrings/docker.gpg
  run_root /bin/bash -lc "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(. /etc/os-release && echo \\\"\$VERSION_CODENAME\\\") stable\" > /etc/apt/sources.list.d/docker.list"
}

install_docker_engine() {
  echo "INFO: 安装 Docker 引擎与 Compose 插件..."
  apt_run update
  apt_run install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

update_docker_engine() {
  echo "INFO: 更新 Docker 引擎与 Compose 插件..."
  apt_run update
  apt_run install --only-upgrade docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

ensure_service_running() {
  if command -v systemctl >/dev/null 2>&1; then
    run_root systemctl enable --now docker >/dev/null 2>&1 || run_root systemctl restart docker >/dev/null 2>&1 || true
  else
    run_root service docker start >/dev/null 2>&1 || true
  fi
}

echo "INFO: Docker 执行动作: $ACTION"
if [ "$ASSUME_YES" = "true" ]; then
  echo "INFO: --yes 已启用（非交互模式）。"
fi

ensure_docker_repo
if [ "$ACTION" = "install" ]; then
  install_docker_engine
elif command -v docker >/dev/null 2>&1; then
  update_docker_engine
else
  echo "WARN: 检测不到 Docker，update 动作自动回退为 install。"
  install_docker_engine
fi

ensure_service_running

echo "✅ Docker ${ACTION} 流程完成。"
echo "   可执行: docker --version && docker compose version"
