# Linux Multi-Distro Installer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the installer support native Linux multi-distro package managers while treating macOS as detection-only with a clear stop message.

**Architecture:** Keep one Bash entrypoint, but move distro differences behind package-management and Docker-runtime helper functions. `install.sh` should become host-agnostic at the main-flow level, while `install_docker.sh` encapsulates Docker installation/update logic per Linux package-manager family.

**Tech Stack:** Bash, Docker Engine/Compose, distro package managers (`apt`, `dnf`, `yum`, `zypper`, `pacman`, `apk`), shell-based regression tests.

---

### Task 1: Document the design and scope

**Files:**
- Create: `docs/plans/2026-03-09-linux-multi-distro-installer-design.md`
- Create: `docs/plans/2026-03-09-linux-multi-distro-installer-plan.md`

**Step 1: Write the design doc**

Capture:
- supported Linux package manager families
- macOS detection-only behavior
- Docker install strategy per family
- dependency package-name mapping

**Step 2: Verify the docs exist**

Run: `test -f docs/plans/2026-03-09-linux-multi-distro-installer-design.md && test -f docs/plans/2026-03-09-linux-multi-distro-installer-plan.md`
Expected: exit code `0`

### Task 2: Add failing shell regression tests

**Files:**
- Create: `tests/install_platform_support_test.sh`

**Step 1: Write the failing test**

Add tests that check:
- `install.sh` exits early on macOS detection
- `install.sh` defines host/package-manager abstraction helpers
- `install_docker.sh` defines package-manager abstraction helpers
- `README.md` documents Linux support scope and macOS detection-only behavior
- `install.sh` no longer hardcodes `apt_run install apache2-utils curl`

**Step 2: Run test to verify it fails**

Run: `bash tests/install_platform_support_test.sh`
Expected: fail because the abstraction helpers and macOS path do not exist yet.

**Step 3: Commit**

```bash
git add tests/install_platform_support_test.sh docs/plans/2026-03-09-linux-multi-distro-installer-design.md docs/plans/2026-03-09-linux-multi-distro-installer-plan.md
git commit -m "test: cover linux multi-distro installer scope"
```

### Task 3: Add host detection and package abstraction to `install.sh`

**Files:**
- Modify: `install.sh`
- Test: `tests/install_platform_support_test.sh`

**Step 1: Write minimal implementation**

Add:
- `get_uname_s`
- `detect_host_os`
- `detect_package_manager`
- `ensure_supported_host`
- `pkg_update`
- `pkg_install`
- `install_runtime_dependencies`
- `install_compose_plugin_if_needed`
- `enable_and_start_service`

Update the main flow so host validation runs before menu, quick install, or positional install execution.

**Step 2: Run targeted test**

Run: `bash tests/install_platform_support_test.sh`
Expected: some checks still fail because `install_docker.sh` and README are not updated yet.

### Task 4: Make `install_docker.sh` multi-distro-aware

**Files:**
- Modify: `install_docker.sh`
- Test: `tests/install_platform_support_test.sh`

**Step 1: Write minimal implementation**

Replace Debian-specific assumptions with:
- Linux/macOS detection
- package-manager detection
- Docker install/update per Linux family
- generic service startup helper

**Step 2: Run targeted test**

Run: `bash tests/install_platform_support_test.sh`
Expected: only README-related checks may still fail.

### Task 5: Update documentation

**Files:**
- Modify: `README.md`
- Test: `tests/install_platform_support_test.sh`

**Step 1: Update support and prerequisite sections**

Document:
- Linux support matrix/package-manager families
- macOS detection-only behavior
- no Windows support

**Step 2: Run test to verify it passes**

Run: `bash tests/install_platform_support_test.sh`
Expected: PASS

### Task 6: Run full verification

**Files:**
- Test: `tests/install_menu_mode_test.sh`
- Test: `tests/install_platform_support_test.sh`

**Step 1: Run the installer regression suite**

Run: `bash tests/install_menu_mode_test.sh && bash tests/install_platform_support_test.sh`
Expected: all tests pass

**Step 2: Review diff**

Run: `git diff -- install.sh install_docker.sh README.md tests/install_platform_support_test.sh docs/plans/2026-03-09-linux-multi-distro-installer-design.md docs/plans/2026-03-09-linux-multi-distro-installer-plan.md`
Expected: only the planned files changed

**Step 3: Commit**

```bash
git add install.sh install_docker.sh README.md tests/install_platform_support_test.sh docs/plans/2026-03-09-linux-multi-distro-installer-design.md docs/plans/2026-03-09-linux-multi-distro-installer-plan.md
git commit -m "feat: support linux multi-distro installer flows"
```
