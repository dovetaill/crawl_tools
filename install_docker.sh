#!/usr/bin/env bash
# Docker installer/updater for common Linux package manager families
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
HOST_OS_CACHE=""
PKG_MANAGER_CACHE=""
OS_RELEASE_LOADED="false"
OS_RELEASE_ID=""
OS_RELEASE_ID_LIKE=""
OS_RELEASE_VERSION_CODENAME=""
SUDO=""

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

get_uname_s() {
  if [ -n "${AIO_TEST_UNAME_S:-}" ]; then
    printf '%s\n' "${AIO_TEST_UNAME_S}"
    return 0
  fi
  uname -s
}

detect_host_os() {
  local uname_s=""
  uname_s="$(get_uname_s | tr '[:upper:]' '[:lower:]')"
  case "$uname_s" in
    linux*) printf '%s\n' "linux" ;;
    darwin*) printf '%s\n' "darwin" ;;
    *) printf '%s\n' "$uname_s" ;;
  esac
}

load_os_release() {
  if [ "${OS_RELEASE_LOADED}" = "true" ]; then
    return 0
  fi

  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_RELEASE_ID="${ID:-}"
    OS_RELEASE_ID_LIKE="${ID_LIKE:-}"
    OS_RELEASE_VERSION_CODENAME="${VERSION_CODENAME:-}"
  fi
  OS_RELEASE_LOADED="true"
}

detect_package_manager() {
  if [ -n "${PKG_MANAGER_CACHE:-}" ]; then
    printf '%s\n' "${PKG_MANAGER_CACHE}"
    return 0
  fi

  if [ -n "${AIO_TEST_PACKAGE_MANAGER:-}" ]; then
    PKG_MANAGER_CACHE="${AIO_TEST_PACKAGE_MANAGER}"
    printf '%s\n' "${PKG_MANAGER_CACHE}"
    return 0
  fi

  local candidate=""
  for candidate in apt-get dnf yum zypper pacman apk; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      PKG_MANAGER_CACHE="${candidate}"
      printf '%s\n' "${PKG_MANAGER_CACHE}"
      return 0
    fi
  done
  return 1
}

ensure_supported_host() {
  local host_os=""
  local pkg_manager=""

  host_os="$(detect_host_os)"
  HOST_OS_CACHE="${host_os}"

  case "${host_os}" in
    linux)
      if ! pkg_manager="$(detect_package_manager)"; then
        echo "ERROR: 检测到 Linux，但未识别到受支持的包管理器。"
        echo "ERROR: 当前支持 apt / dnf / yum / zypper / pacman / apk"
        exit 1
      fi
      PKG_MANAGER_CACHE="${pkg_manager}"
      ;;
    darwin)
      echo "ERROR: 检测到 macOS。当前脚本仅支持 Linux 各发行版原生安装。"
      echo "ERROR: macOS 仅提供环境检测与提示，请改用 Docker Desktop 或手动部署。"
      exit 1
      ;;
    *)
      echo "ERROR: 当前脚本仅支持 Linux 各发行版原生安装。"
      echo "ERROR: 检测到未支持系统: ${host_os}"
      exit 1
      ;;
  esac
}

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

pkg_update() {
  local pkg_manager=""
  pkg_manager="$(detect_package_manager)"

  case "${pkg_manager}" in
    apt-get)
      apt_run update
      ;;
    dnf)
      run_root dnf -y makecache --refresh
      ;;
    yum)
      run_root yum -y makecache
      ;;
    zypper)
      run_root zypper --non-interactive --gpg-auto-import-keys refresh
      ;;
    pacman)
      run_root pacman -Sy --noconfirm
      ;;
    apk)
      run_root apk update
      ;;
  esac
}

pkg_install() {
  local pkg_manager=""
  pkg_manager="$(detect_package_manager)"

  case "${pkg_manager}" in
    apt-get)
      apt_run install "$@"
      ;;
    dnf)
      run_root dnf -y install "$@"
      ;;
    yum)
      run_root yum -y install "$@"
      ;;
    zypper)
      run_root zypper --non-interactive --gpg-auto-import-keys install --auto-agree-with-licenses "$@"
      ;;
    pacman)
      run_root pacman -S --noconfirm --needed "$@"
      ;;
    apk)
      run_root apk add --no-cache "$@"
      ;;
  esac
}

detect_docker_repo_distribution() {
  local dist="debian"
  load_os_release

  case "${OS_RELEASE_ID:-}" in
    ubuntu|debian)
      dist="${OS_RELEASE_ID}"
      ;;
    *)
      if echo " ${OS_RELEASE_ID_LIKE:-} " | grep -qi ' ubuntu '; then
        dist="ubuntu"
      elif echo " ${OS_RELEASE_ID_LIKE:-} " | grep -qi ' debian '; then
        dist="debian"
      fi
      ;;
  esac
  printf '%s' "$dist"
}

detect_docker_repo_codename() {
  local codename=""
  load_os_release
  codename="${OS_RELEASE_VERSION_CODENAME:-}"
  if [ -z "$codename" ] && command -v lsb_release >/dev/null 2>&1; then
    codename="$(lsb_release -cs 2>/dev/null || true)"
  fi
  if [ -z "$codename" ]; then
    codename="stable"
  fi
  printf '%s' "$codename"
}

detect_rpm_repo_distribution() {
  local repo_dist="rhel"
  load_os_release

  case "${OS_RELEASE_ID:-}" in
    fedora)
      repo_dist="fedora"
      ;;
    centos)
      repo_dist="centos"
      ;;
    rhel|rocky|almalinux|ol)
      repo_dist="rhel"
      ;;
    *)
      if echo " ${OS_RELEASE_ID_LIKE:-} " | grep -Eqi ' fedora '; then
        repo_dist="fedora"
      elif [ "$(detect_package_manager)" = "yum" ]; then
        repo_dist="centos"
      fi
      ;;
  esac
  printf '%s' "$repo_dist"
}

configure_docker_repo_for_apt() {
  local dist=""
  local codename=""

  dist="$(detect_docker_repo_distribution)"
  codename="$(detect_docker_repo_codename)"

  echo "INFO: 配置 Docker 官方仓库（${dist}/${codename}）..."
  apt_run install ca-certificates curl gnupg lsb-release apt-transport-https
  run_root install -m 0755 -d /etc/apt/keyrings
  run_root rm -f /etc/apt/keyrings/docker.gpg
  curl -fsSL "https://download.docker.com/linux/${dist}/gpg" | run_root gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  run_root chmod a+r /etc/apt/keyrings/docker.gpg
  run_root /bin/bash -lc "cat > /etc/apt/sources.list.d/docker.list <<'EOF_DOCKER_REPO'
deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${dist} ${codename} stable
EOF_DOCKER_REPO"
  apt_run update
}

configure_docker_repo_for_rpm() {
  local pkg_manager=""
  local repo_dist=""
  local repo_url=""

  pkg_manager="$(detect_package_manager)"
  repo_dist="$(detect_rpm_repo_distribution)"
  repo_url="https://download.docker.com/linux/${repo_dist}/docker-ce.repo"

  echo "INFO: 配置 Docker RPM 软件源（${repo_dist}）..."
  if [ "${pkg_manager}" = "dnf" ]; then
    pkg_install dnf-plugins-core
    if run_root dnf config-manager --help 2>/dev/null | grep -q -- '--add-repo'; then
      run_root dnf config-manager --add-repo "${repo_url}"
    else
      run_root dnf config-manager addrepo --from-repofile="${repo_url}"
    fi
  else
    pkg_install yum-utils
    run_root yum-config-manager --add-repo "${repo_url}"
  fi
}

install_docker_engine() {
  local pkg_manager=""
  pkg_manager="$(detect_package_manager)"

  case "${pkg_manager}" in
    apt-get)
      configure_docker_repo_for_apt
      apt_run install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    dnf)
      configure_docker_repo_for_rpm
      run_root dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    yum)
      configure_docker_repo_for_rpm
      run_root yum -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    zypper)
      pkg_update
      pkg_install docker
      pkg_install docker-compose docker-compose-switch || pkg_install docker-compose || true
      ;;
    pacman)
      pkg_update
      run_root pacman -S --noconfirm docker docker-compose
      ;;
    apk)
      pkg_update
      pkg_install docker docker-cli-compose
      ;;
  esac
}

update_docker_engine() {
  local pkg_manager=""
  pkg_manager="$(detect_package_manager)"

  case "${pkg_manager}" in
    apt-get)
      configure_docker_repo_for_apt
      apt_run install --only-upgrade docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || \
        apt_run install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    dnf)
      configure_docker_repo_for_rpm
      run_root dnf -y upgrade docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || \
        run_root dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    yum)
      configure_docker_repo_for_rpm
      run_root yum -y update docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || \
        run_root yum -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    zypper)
      pkg_update
      run_root zypper --non-interactive update docker docker-compose docker-compose-switch || \
        (pkg_install docker && (pkg_install docker-compose docker-compose-switch || pkg_install docker-compose || true))
      ;;
    pacman)
      pkg_update
      run_root pacman -S --noconfirm docker docker-compose
      ;;
    apk)
      run_root apk upgrade docker docker-cli-compose || pkg_install docker docker-cli-compose
      ;;
  esac
}

enable_and_start_service() {
  local service_name="$1"

  if command -v systemctl >/dev/null 2>&1; then
    run_root systemctl enable --now "${service_name}" >/dev/null 2>&1 || run_root systemctl restart "${service_name}" >/dev/null 2>&1 || true
    return 0
  fi
  if command -v rc-update >/dev/null 2>&1 && command -v rc-service >/dev/null 2>&1; then
    run_root rc-update add "${service_name}" default >/dev/null 2>&1 || true
    run_root rc-service "${service_name}" start >/dev/null 2>&1 || run_root rc-service "${service_name}" restart >/dev/null 2>&1 || true
    return 0
  fi
  if command -v service >/dev/null 2>&1; then
    run_root service "${service_name}" start >/dev/null 2>&1 || run_root service "${service_name}" restart >/dev/null 2>&1 || true
  fi
}

ensure_supported_host

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "ERROR: 当前非 root 且未安装 sudo，无法继续。"
    exit 1
  fi
fi

echo "INFO: Docker 执行动作: $ACTION"
if [ "$ASSUME_YES" = "true" ]; then
  echo "INFO: --yes 已启用（非交互模式）。"
fi

if [ "$ACTION" = "install" ]; then
  install_docker_engine
elif command -v docker >/dev/null 2>&1; then
  update_docker_engine
else
  echo "WARN: 检测不到 Docker，update 动作自动回退为 install。"
  install_docker_engine
fi

enable_and_start_service docker

echo "✅ Docker ${ACTION} 流程完成。"
echo "   可执行: docker --version && docker compose version"
