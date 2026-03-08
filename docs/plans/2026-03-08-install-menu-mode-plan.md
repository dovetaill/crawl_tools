# Install Menu Mode Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make `install.sh` enter an interactive management menu when launched without positional arguments, while preserving existing argument-driven install behavior.

**Architecture:** Convert script into function-based flows with two entrypoints: `menu_mode` (no args) and `cli_mode` (existing args). Reuse shared helpers for compose detection, status reading, and service operations. Keep `install_docker.sh` dependency model unchanged.

**Tech Stack:** Bash, Docker Compose, htpasswd, Debian/Ubuntu apt utilities.

---

### Task 1: Add failing behavior test for no-arg menu mode

**Files:**
- Create: `tests/install_menu_mode_test.sh`
- Modify: `README.md` (later task)

**Step 1: Write the failing test**

```bash
# Scenario: no args should enter menu, print menu title, and allow immediate exit with 0
printf '0\n' | bash install.sh
```

Assertions:
- output contains `AIO Proxy 管理菜单`
- exit code is 0

**Step 2: Run test to verify it fails**

Run: `bash tests/install_menu_mode_test.sh`
Expected: FAIL (current script prints usage and exits non-zero)

### Task 2: Refactor install.sh into dual mode entrypoints

**Files:**
- Modify: `install.sh`

**Step 1: Implement minimal menu framework**
- Add `menu_mode` with numeric options and `0) 退出`
- No-arg path routes to `menu_mode`
- Keep old positional install path unchanged

**Step 2: Add management functions**
- `show_current_config`
- `menu_install_fresh`
- `menu_update_credentials`
- `menu_update_port`
- `menu_start`, `menu_stop`, `menu_restart`, `menu_uninstall`

**Step 3: Preserve compatibility**
- `install.sh --help` unchanged
- `install.sh [--yes] [--update-docker] user pass port` unchanged

### Task 3: Update docs and verify

**Files:**
- Modify: `README.md`

**Step 1: Document new no-arg menu behavior**
- add examples for `sudo bash install.sh`
- keep parameter mode examples

**Step 2: Verify commands**
- `bash -n install.sh`
- `bash -n install_docker.sh`
- `bash tests/install_menu_mode_test.sh`

