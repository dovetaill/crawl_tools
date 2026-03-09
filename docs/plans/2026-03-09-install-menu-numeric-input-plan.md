# Install Menu Numeric Input Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace arrow-key-driven `install.sh` menu interactions with numeric-only input while preserving existing non-interactive install behavior.

**Architecture:** Remove the arrow-menu branch entirely and make numeric prompts the single interaction model for menu mode, confirmations, and the status page. Keep the CLI install path intact, and drive the change with shell tests that first fail on the old behavior.

**Tech Stack:** Bash, ripgrep, shell test script `tests/install_menu_mode_test.sh`.

---

### Task 1: Lock the intended behavior with failing tests

**Files:**
- Modify: `tests/install_menu_mode_test.sh`
- Test: `tests/install_menu_mode_test.sh`

**Step 1: Write the failing test**

Add assertions that:
- `install.sh` no-arg mode still exits cleanly when fed `0`.
- `install.sh` no longer contains arrow-menu helpers or raw single-key reads.
- status-page help text describes numeric actions instead of auto-refresh and single-key shortcuts.

**Step 2: Run test to verify it fails**

Run: `bash tests/install_menu_mode_test.sh`
Expected: FAIL because `install.sh` still contains arrow-menu functions and old status-page text.

**Step 3: Commit**

```bash
git add tests/install_menu_mode_test.sh
git commit -m "test: define numeric install menu behavior"
```

### Task 2: Replace confirmation and main-menu input with numeric prompts

**Files:**
- Modify: `install.sh`
- Test: `tests/install_menu_mode_test.sh`

**Step 1: Write minimal implementation**

- Make `confirm_with_default` always call numeric confirmation input.
- Remove arrow-specific helper functions and their call sites.
- Make `menu_mode` always render the numbered main menu and read a normal line of input.

**Step 2: Run tests**

Run: `bash tests/install_menu_mode_test.sh`
Expected: partial progress, with any remaining failures isolated to status-page behavior or leftover arrow-specific code.

**Step 3: Commit**

```bash
git add install.sh tests/install_menu_mode_test.sh
git commit -m "refactor: make installer menu numeric only"
```

### Task 3: Convert status page to numeric snapshot actions

**Files:**
- Modify: `install.sh`
- Test: `tests/install_menu_mode_test.sh`

**Step 1: Write minimal implementation**

- Replace auto-refresh loop and single-key reads in `status_dashboard_flow`.
- Render a snapshot page with numbered actions for refresh, start, stop, restart, logs, and back.
- Update the copy to match the numeric model.

**Step 2: Run tests**

Run: `bash tests/install_menu_mode_test.sh`
Expected: PASS

**Step 3: Run syntax verification**

Run: `bash -n install.sh`
Expected: PASS with no output

**Step 4: Commit**

```bash
git add install.sh tests/install_menu_mode_test.sh
git commit -m "fix: simplify installer status page input"
```

### Task 4: Final verification

**Files:**
- Modify: `install.sh`
- Modify: `tests/install_menu_mode_test.sh`

**Step 1: Run targeted verification**

Run: `bash tests/install_menu_mode_test.sh`
Expected: PASS

Run: `bash -n install.sh`
Expected: PASS

Run: `bash -n install_docker.sh`
Expected: PASS

**Step 2: Summarize behavior changes**

- Numeric-only menu interaction
- Numeric-only yes/no prompts
- Numeric snapshot status page

**Step 3: Commit**

```bash
git add install.sh tests/install_menu_mode_test.sh docs/plans/2026-03-09-install-menu-numeric-input-design.md docs/plans/2026-03-09-install-menu-numeric-input-plan.md
git commit -m "fix: switch installer menu to numeric input"
```
