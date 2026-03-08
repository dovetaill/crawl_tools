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

# Test 1: no-arg mode should enter menu and allow exit with code 0
set +e
output="$(printf '0\n' | bash ./install.sh 2>&1)"
status=$?
set -e

if [ "$status" -ne 0 ]; then
  fail "expected no-arg menu exit code 0, got $status; output=$output"
fi
if [[ "$output" != *"AIO Proxy 管理菜单"* ]]; then
  fail "expected menu title in output, got: $output"
fi
pass "no-arg mode enters menu and exits cleanly"

# Test 2: CLI mode should still require 3 positional args when flags present
set +e
output2="$(bash ./install.sh --yes 2>&1)"
status2=$?
set -e
if [ "$status2" -eq 0 ]; then
  fail "expected missing positional args in CLI mode to fail"
fi
if [[ "$output2" != *"用法:"* ]]; then
  fail "expected usage output for invalid CLI invocation"
fi
pass "cli mode argument validation still works"

echo "All tests passed"
