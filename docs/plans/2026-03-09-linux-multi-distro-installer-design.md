# Linux Multi-Distro Installer Design

**Date:** 2026-03-09

**Problem:** `install.sh` and `install_docker.sh` are currently Debian/Ubuntu-oriented. They assume `apt-get`, Debian package names, APT repository layout, and Linux service conventions that do not hold across other Linux distributions. The scripts also currently provide no explicit macOS detection path.

**Decision:** Keep a single installer entrypoint, but introduce a Linux platform abstraction layer for package management, dependency package naming, Docker installation, and service startup. Treat `macOS` as detection-only: the script should identify it early, print a clear message, and stop before attempting installation.

## Goals

- Support native Linux installation flows across common package manager families:
  - `apt`
  - `dnf`
  - `yum`
  - `zypper`
  - `pacman`
  - `apk`
- Remove direct `apt` assumptions from the main install flow.
- Keep the existing menu mode, `--quick`, `--yes`, and positional install flows.
- Preserve Docker install/update behavior under a unified interface.
- Make `macOS` behavior explicit and safe.

## Non-Goals

- Native Windows support.
- Native macOS deployment support.
- Replacing Docker with Podman or another runtime.
- Full support for every niche Linux derivative with custom repository policies.

## Support Model

### Linux

- `install.sh` remains the main entrypoint.
- The script detects the current package manager and routes package installation accordingly.
- Dependency package names vary by distro family:
  - Debian/Ubuntu: `apache2-utils`
  - RHEL/Fedora family: `httpd-tools`
  - Arch: `apache`
  - Alpine/openSUSE: `apache2-utils`
- Docker installation strategy:
  - `apt`: Docker official APT repository.
  - `dnf`: Docker official RPM repository for Fedora or RHEL-like systems.
  - `yum`: Docker official RPM repository for CentOS-like systems.
  - `zypper`: distro packages (`docker`, `docker-compose`, `docker-compose-switch`).
  - `pacman`: distro packages (`docker`, `docker-compose`).
  - `apk`: distro packages (`docker`, `docker-cli-compose`).

### macOS

- Detect via `uname -s`.
- Print a clear message that native deployment is not supported by this script.
- Mention Docker Desktop/manual deployment as the expected route.
- Exit before root checks, package installation, or menu flow execution.

## Architecture

### Host Detection Layer

Add small helper functions to normalize host details:

- `get_uname_s`
- `detect_host_os`
- `detect_package_manager`
- `ensure_supported_host`

The main flow should stop calling distro-specific logic directly. Instead it should validate the host first and then rely on abstract package/runtime helpers.

### Package Abstraction Layer

Replace direct `apt_run` usage in the main script with generic helpers:

- `pkg_update`
- `pkg_install`
- `install_runtime_dependencies`
- `install_compose_plugin_if_needed`

This keeps `perform_install`, credential updates, and compose detection distro-agnostic.

### Docker Runtime Layer

Unify Docker actions behind these interfaces:

- `install_docker_engine`
- `update_docker_engine`
- `enable_and_start_service`

`install_docker.sh` should own the package-manager-specific Docker installation logic. `install.sh` should call it as an implementation detail.

## Error Handling

- Unsupported OS: fail early with a direct explanation.
- Linux with unknown package manager: fail early and list the supported managers.
- Missing compose plugin after installation: attempt the distro-appropriate package install fallback, then re-check.
- Service startup should try `systemctl`, then `service`, then `rc-service` for OpenRC hosts.

## Testing Strategy

- Add shell tests that assert:
  - macOS detection exits early with a detection-only message.
  - Linux abstraction helpers exist in both scripts.
  - direct `apt`-only dependency installation is removed from `perform_install`.
  - README documents Linux support scope and macOS detection-only behavior.
- Keep tests structure-focused because the installer cannot safely exercise real package managers in CI-like environments.

## Acceptance Criteria

- A user on Debian/Ubuntu, Fedora/RHEL-like, openSUSE, Arch, or Alpine can reach a package-manager-aware install path.
- `macOS` users see a clear, explicit stop message instead of Linux-specific failures.
- `install.sh` no longer hardcodes `apt` for runtime dependency installation.
- `install_docker.sh` no longer describes itself as Debian-only.
