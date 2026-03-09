#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "[FAIL] $1" >&2
  exit 1
}

pass() {
  echo "[PASS] $1"
}

# Test 1: install.sh should reject macOS early with a detection-only message
set +e
output="$(printf '0\n' | AIO_TEST_UNAME_S=Darwin bash ./install.sh 2>&1)"
status=$?
set -e
if [ "$status" -eq 0 ]; then
  fail "expected macOS detection path to exit non-zero"
fi
if [[ "$output" != *"macOS"* ]] || [[ "$output" != *"仅支持 Linux"* ]]; then
  fail "expected macOS detection-only guidance, got: $output"
fi
pass "install.sh rejects macOS with a clear detection-only message"

# Test 2: install.sh should define Linux host/package-manager abstraction helpers
if ! rg -n '^get_uname_s\(\)' ./install.sh >/dev/null 2>&1; then
  fail "missing get_uname_s helper in install.sh"
fi
if ! rg -n '^detect_host_os\(\)' ./install.sh >/dev/null 2>&1; then
  fail "missing detect_host_os helper in install.sh"
fi
if ! rg -n '^detect_package_manager\(\)' ./install.sh >/dev/null 2>&1; then
  fail "missing detect_package_manager helper in install.sh"
fi
if ! rg -n '^ensure_supported_host\(\)' ./install.sh >/dev/null 2>&1; then
  fail "missing ensure_supported_host helper in install.sh"
fi
if ! rg -n '^pkg_install\(\)' ./install.sh >/dev/null 2>&1; then
  fail "missing pkg_install helper in install.sh"
fi
if ! rg -n '^install_runtime_dependencies\(\)' ./install.sh >/dev/null 2>&1; then
  fail "missing install_runtime_dependencies helper in install.sh"
fi
pass "install.sh declares Linux abstraction helpers"

# Test 3: install.sh should not keep apt-only runtime dependency installation
if rg -n 'apt_run install apache2-utils curl' ./install.sh >/dev/null 2>&1; then
  fail "install.sh still hardcodes apt-only runtime dependency installation"
fi
pass "install.sh removes apt-only runtime dependency installation"

# Test 4: install_docker.sh should no longer be Debian-only
if rg -n 'Debian-like systems|Docker APT 软件源|download.docker.com/linux/debian' ./install_docker.sh >/dev/null 2>&1; then
  fail "install_docker.sh still contains Debian-only wording or repository setup"
fi
if ! rg -n '^detect_package_manager\(\)' ./install_docker.sh >/dev/null 2>&1; then
  fail "missing detect_package_manager helper in install_docker.sh"
fi
if ! rg -n '^install_docker_engine\(\)' ./install_docker.sh >/dev/null 2>&1; then
  fail "missing install_docker_engine helper in install_docker.sh"
fi
if ! rg -n '^enable_and_start_service\(\)' ./install_docker.sh >/dev/null 2>&1; then
  fail "missing enable_and_start_service helper in install_docker.sh"
fi
pass "install_docker.sh declares multi-distro docker helpers"

# Test 5: README should document Linux support scope and macOS detection-only behavior
if ! rg -n 'Linux .*apt.*dnf.*yum.*zypper.*pacman.*apk|apt.*dnf.*yum.*zypper.*pacman.*apk' ./README.md >/dev/null 2>&1; then
  fail "README is missing Linux package-manager support scope"
fi
if ! rg -n 'macOS .*仅.*检测.*提示|macOS .*不支持原生安装' ./README.md >/dev/null 2>&1; then
  fail "README is missing macOS detection-only note"
fi
pass "README documents Linux support scope and macOS detection-only behavior"

echo "All tests passed"
