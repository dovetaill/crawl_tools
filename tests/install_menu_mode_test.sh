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
if [[ "$output" != *"AIO Proxy 控制台"* ]]; then
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

# Test 3: password prompt should be visible (not silent `read -s`)
if rg -n 'read -r -s -p "\$prompt" value' ./install.sh >/dev/null 2>&1; then
  fail "password input is still hidden; expected visible input prompt"
fi
pass "password input prompt is visible"

# Test 4: install.sh should provide random generation helpers for menu install flow
if ! rg -n '^generate_random_username\(\)' ./install.sh >/dev/null 2>&1; then
  fail "missing generate_random_username helper"
fi
if ! rg -n '^generate_random_password\(\)' ./install.sh >/dev/null 2>&1; then
  fail "missing generate_random_password helper"
fi
if ! rg -n '^generate_random_port\(\)' ./install.sh >/dev/null 2>&1; then
  fail "missing generate_random_port helper"
fi
pass "random generation helpers exist"

# Test 5: menu prompts should clearly explain auto-generation when input is empty
if ! rg -n '留空自动生成' ./install.sh >/dev/null 2>&1; then
  fail "missing auto-generation hint in prompts"
fi
pass "auto-generation hints exist in prompts"

# Test 6: arrow menu renderer should avoid tput sc/rc cursor save/restore redraw pattern
if rg -n 'tput sc|tput rc' ./install.sh >/dev/null 2>&1; then
  fail "arrow menu still uses tput sc/rc redraw path"
fi
pass "arrow menu redraw path avoids tput sc/rc"

# Test 7: main menu should support arrow-key highlighted selection
if ! rg -n '^select_main_menu_with_arrow\(\)' ./install.sh >/dev/null 2>&1; then
  fail "missing arrow-key selector for main menu"
fi
if ! rg -n 'select_main_menu_with_arrow' ./install.sh >/dev/null 2>&1; then
  fail "main menu does not call arrow-key selector"
fi
if rg -n 'choice="\$\(select_main_menu_with_arrow\)"' ./install.sh >/dev/null 2>&1; then
  fail "main menu still captures arrow renderer output via command substitution"
fi
pass "main menu arrow-key selector exists and is wired"

# Test 8: status page should support single-screen dynamic refresh
if ! rg -n '^status_dashboard_flow\(\)' ./install.sh >/dev/null 2>&1; then
  fail "missing status_dashboard_flow"
fi
if ! rg -n '状态仪表盘（自动刷新）' ./install.sh >/dev/null 2>&1; then
  fail "main menu missing dynamic status dashboard entry"
fi
if ! rg -n '按键: q 返回, r 刷新, s 启动, t 停止, x 重启, l 日志' ./install.sh >/dev/null 2>&1; then
  fail "status dashboard missing key hints"
fi
pass "status dashboard dynamic refresh hooks exist"

# Test 9: other pages should use unified page header helper
if ! rg -n '^render_page_header\(\)' ./install.sh >/dev/null 2>&1; then
  fail "missing render_page_header helper"
fi
if ! rg -n 'render_page_header "当前配置"' ./install.sh >/dev/null 2>&1; then
  fail "show_current_config is not using unified page header"
fi
pass "page rendering helper is wired"

# Test 10: install.sh should work standalone without requiring install_docker.sh beside it
if ! rg -n '^run_docker_installer_inline\(\)' ./install.sh >/dev/null 2>&1; then
  fail "missing inline docker installer fallback"
fi
if ! rg -n '回退到内置 Docker 安装流程' ./install.sh >/dev/null 2>&1; then
  fail "missing fallback message for standalone install.sh mode"
fi
pass "standalone install.sh docker fallback exists"

# Test 11: README remote install should support single-script download path
if ! rg -n 'curl -fsSL .*install\\.sh \\| sudo bash' ./README.md >/dev/null 2>&1; then
  fail "README is missing simplified single-script remote install command"
fi
pass "README includes simplified single-script remote install command"

# Test 12: quick mode should exist for newbie one-liner install
if ! rg -n '^quick_install_flow\(\)' ./install.sh >/dev/null 2>&1; then
  fail "missing quick_install_flow"
fi
if ! rg -n -- '--quick' ./install.sh >/dev/null 2>&1; then
  fail "install.sh missing --quick option"
fi
if ! rg -n 'bash -s -- --quick' ./README.md >/dev/null 2>&1; then
  fail "README missing --quick one-liner example"
fi
pass "quick mode hooks and docs exist"

# Test 13: all install modes should enforce port occupancy checks
if ! rg -n '^is_port_in_use\(\)' ./install.sh >/dev/null 2>&1; then
  fail "missing is_port_in_use helper"
fi
if ! rg -n '^is_port_available_for_install\(\)' ./install.sh >/dev/null 2>&1; then
  fail "missing is_port_available_for_install helper"
fi
if ! rg -n 'if ! is_port_available_for_install "\$flare_port" "true"; then' ./install.sh >/dev/null 2>&1; then
  fail "perform_install is missing pre-install port occupancy guard"
fi
if ! rg -n '\[quick\] 端口 .* 已被占用，自动重试为:' ./install.sh >/dev/null 2>&1; then
  fail "quick mode missing automatic port retry message"
fi
if ! rg -n '端口已被占用，请重新输入或留空自动生成。' ./install.sh >/dev/null 2>&1; then
  fail "manual menu install missing occupied-port prompt"
fi
if ! rg -n '新端口已被占用，请更换。' ./install.sh >/dev/null 2>&1; then
  fail "manual port-update flow missing occupied-port prompt"
fi
pass "port occupancy validation is wired for quick, one-click and manual flows"

# Test 14: generated manage.sh should default to menu mode and proxy to install.sh interactive console
if ! rg -n 'case "\$\{1:-menu\}" in' ./install.sh >/dev/null 2>&1; then
  fail "generated manage.sh is not defaulting to menu mode"
fi
if ! rg -n '"\$0" install-menu' ./install.sh >/dev/null 2>&1; then
  fail "generated manage.sh missing self-dispatch install-menu entry"
fi
if ! rg -n 'exec bash \./install\.sh' ./install.sh >/dev/null 2>&1; then
  fail "generated manage.sh missing install.sh interactive delegation"
fi
pass "generated manage.sh defaults to install-like interactive menu"

# Test 15: manage command compatibility should keep legacy subcommands and include uninstall
if ! rg -n 'start\|up\)' ./install.sh >/dev/null 2>&1; then
  fail "generated manage.sh missing start/up subcommand"
fi
if ! rg -n 'set-credentials\)' ./install.sh >/dev/null 2>&1; then
  fail "generated manage.sh missing set-credentials subcommand"
fi
if ! rg -n 'uninstall\)' ./install.sh >/dev/null 2>&1; then
  fail "generated manage.sh missing uninstall subcommand"
fi
if ! rg -n '用法: \$0 \{menu\|start\|stop\|restart\|ps\|logs\|set-credentials <user> <pass>\|uninstall\}' ./install.sh >/dev/null 2>&1; then
  fail "generated manage.sh usage is not documenting compatibility and uninstall"
fi
pass "manage compatibility commands and uninstall command are documented"

# Test 16: installer should copy install scripts to /opt/aio-proxy for runtime menu maintenance
if ! rg -n '^write_runtime_install_scripts\(\)' ./install.sh >/dev/null 2>&1; then
  fail "missing runtime install script copy helper"
fi
if ! rg -n 'write_runtime_install_scripts' ./install.sh >/dev/null 2>&1; then
  fail "perform_install is not invoking runtime install script copy helper"
fi
pass "runtime install scripts are prepared in install target dir"

# Test 17: README should document no-arg manage menu and uninstall command
if ! rg -n '^\./manage\.sh$' ./README.md >/dev/null 2>&1; then
  fail "README missing no-arg manage menu command"
fi
if ! rg -n '与 `install\.sh` 相同的交互控制台' ./README.md >/dev/null 2>&1; then
  fail "README missing manage/install interactive parity note"
fi
if ! rg -n '^\./manage\.sh uninstall$' ./README.md >/dev/null 2>&1; then
  fail "README missing manage uninstall command"
fi
pass "README documents manage menu parity and uninstall"

echo "All tests passed"
