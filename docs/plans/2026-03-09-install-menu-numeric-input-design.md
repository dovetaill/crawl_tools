# Install Menu Numeric Input Design

**Date:** 2026-03-09

**Problem:** `install.sh` currently relies on arrow-key-driven menu rendering in no-argument mode. That causes visible cursor artifacts, sluggish navigation from escape-sequence timeouts, and poor usability on mobile SSH clients or keyboards without dedicated arrow keys.

**Decision:** Make no-argument menu mode fully numeric-input-driven. Numeric entry becomes the primary and only interactive path for the installer console.

## Goals

- Remove dependence on arrow-key navigation for all menu interactions.
- Keep the script usable on low-capability terminals and mobile SSH keyboards.
- Preserve existing CLI install modes such as `--yes`, `--quick`, and positional install arguments.
- Keep menu numbering stable so documentation and user habits remain intact.

## Non-Goals

- Redesigning the installer feature set.
- Changing non-interactive install flows.
- Building a full-screen terminal UI.

## Interaction Model

### Main Menu

- Keep the existing menu entries and numeric mapping:
  - `1` view current config
  - `2` fresh install / reinstall
  - `3` update credentials
  - `4` update external port
  - `5` start service
  - `6` stop service
  - `7` restart service
  - `8` status page
  - `9` logs
  - `10` uninstall
  - `0` exit
- Read input with normal line-based prompts such as `read -r -p`.
- Do not render highlighted selection state.

### Confirmation Prompts

- Standardize all yes/no prompts as numbered input:
  - `1) yes`
  - `2) no`
- Respect existing default behavior by applying the default when the user presses Enter on an empty line.
- Support `q` / `quit` / `exit` as explicit cancellation where already supported.

### Status Page

- Replace auto-refresh and single-key controls with a numeric status page.
- Render a snapshot of current state once per visit or after an explicit refresh/action.
- Present numeric actions such as:
  - `1) refresh`
  - `2) start`
  - `3) stop`
  - `4) restart`
  - `5) logs`
  - `0) back`

## Compatibility

- No-argument menu mode changes from arrow-key-first to numeric-only.
- `--help`, `--yes`, `--update-docker`, positional install mode, and `--quick` remain unchanged.
- Non-TTY fallback logic for menu selection becomes unnecessary because numeric prompts work in all supported interactive terminals.

## Implementation Notes

- Remove or stop using arrow-menu helpers:
  - `can_use_arrow_menu`
  - `confirm_with_arrow_menu`
  - `select_main_menu_with_arrow`
  - `menu_cleanup`
- Remove cursor-hiding and redraw logic based on `tput` and ANSI cursor rewinds.
- Keep page headers and screen clearing only where they improve readability, not as part of an input loop.

## Testing Strategy

- Update shell tests to assert numeric-only menu behavior.
- Verify no-argument mode still exits cleanly with `0`.
- Assert status-page copy reflects numeric actions rather than auto-refresh and single-key hints.
- Assert arrow-navigation implementation details are removed from `install.sh`.

## Acceptance Criteria

- A user can complete all no-argument menu interactions using only numeric input.
- No arrow-key navigation path remains in the script.
- The installer no longer waits on escape-sequence parsing during menu navigation.
- Existing non-interactive and argument-driven install flows still pass their checks.
