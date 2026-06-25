# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

CampiOS is a **custom immutable Linux desktop OS image**, not an application. The "build" produces an OCI container image that is itself a bootable operating system (a [bootc](https://github.com/bootc-dev/bootc) image). It derives from the Universal Blue [`image-template`](https://github.com/ublue-os/image-template) and is based on `ghcr.io/rakuos/rakuos-base-nvidia` (a Fedora Atomic / ublue NVIDIA base).

There is no compiled application and there are no unit tests. Changing the OS means editing a Containerfile + bash, then building the image and booting it in a VM to verify.

Source comments and git commit messages are written in **Italian** — match that when editing existing files.

## Where changes go

**`build_files/build.sh` is the build-time orchestrator.** The `Containerfile` does little more than bind-mount `build_files/` and run it. `build.sh` defines the *order* of operations (load-bearing — e.g. Secure Boot signing must precede initramfs regeneration), keeps only short order-sensitive glue inline, and delegates each self-contained subsystem to a script in `build_files/scripts/`:

| Subsystem | Script |
|---|---|
| Dev-box (distrobox: VSCode + Rust/Cargo + Python, first-login creator + service) | `setup-devbox.sh` |
| KDE Connect (firewall ports + DMS plugin) | `setup-kdeconnect.sh` |
| greetd display manager | `setup-greetd.sh` |
| Default user session — DMS + niri, new *and* existing users | `setup-user-configs.sh` |
| Plymouth boot splash (theme + kargs) | `setup-plymouth.sh` |
| Default Flatpaks (first-boot installer + service) | `setup-flatpaks.sh` |
| Secure Boot signing / MOK enroll helper | `sign-secureboot.sh`, `install-mok-enroll-script.sh` |
| initramfs regeneration (runs *after* signing) | `regenerate-initramfs.sh` |

To change one subsystem, edit its script. To change *ordering* or add a new subsystem, edit `build.sh`. Inline glue that stays in `build.sh` on purpose: the dnf package install, the DMS COPR install, fish-as-default-shell, `policy.json`, the podman socket, `waybar` removal, glib schemas, and cleanup.

Files under `build_files/` are copied into the build context (stage `ctx`) and referenced as `/ctx/...` (so a script reads e.g. `/ctx/dot_config/niri/config.kdl`). Scripts invoked during the build must be executable — commit them as mode `755`. New extracted scripts follow the existing style: `#!/usr/bin/env bash`, `set -euo pipefail`, and an `echo "=== CampiOS: … ==="` banner (no `set -x`).

**Package lists are data, not code.** Plain DNF packages live in `build_files/packages/install.txt` (one per line, `#` comments), installed by a single generic loop in `build.sh` — add or remove a normal package *there*, not in `build.sh`. Flatpaks follow the same data-driven pattern (applied at first boot) via `build_files/flatpaks/{default,remove}-apps.txt`. Only genuinely special installs stay inline in `build.sh`: the DMS desktop group (needs the `avengemedia/dms` COPR repo + `--allowerasing`) and the post-DMS `waybar` removal. **The repo's factoring rule:** pull out list-like **data** (package/flatpak lists), **runtime-only** operations, and **complex, independently-testable** subsystems; keep order-sensitive, one-off glue inline and linear in `build.sh`.

## Common commands

All workflows go through `just` (the `Justfile`). Local prerequisites: `just`, `podman`; `shellcheck` + `shfmt` for lint/format; disk-image builds need `sudo` and privileged podman.

```bash
just build                # Build the OS container image (podman) -> localhost campios:latest
just build-qcow2          # Build a QCOW2 VM disk via bootc-image-builder (uses disk_config/disk.toml)
just build-iso            # Build an installer ISO (uses disk_config/iso.toml)
just rebuild-qcow2        # build + build-qcow2 in one step
just run-vm-qcow2         # Boot the QCOW2 in a browser-accessible QEMU VM (http://localhost:8006+)
just spawn-vm             # Boot via systemd-vmspawn instead

just lint                 # shellcheck every *.sh
just format               # shfmt --write every *.sh
just check / just fix     # Check / autofix Justfile syntax
just clean                # Remove build artifacts (output/, _build*, manifests)
```

Image name/tag are overridable via env: `IMAGE_NAME` (default `campios`), `DEFAULT_TAG` (default `latest`), `BIB_IMAGE`.

**Verification** has three layers, in increasing cost: `just lint` → `bootc container lint` (runs automatically as the last step of every image build) → building a disk image and booting it with `just run-vm-qcow2`. There is no faster "single test"; a real change is only proven by booting a VM.

## Build pipeline (Containerfile → build.sh)

1. `build.sh` runs under `set -ouex pipefail` with cache mounts for `/var/cache`,`/var/log` and the MOK private key mounted as a build secret at `/run/secrets/campios_mok_key`.
2. It installs packages, writes systemd units and configs, signs for Secure Boot, then **regenerates the initramfs last** (ordering matters — see Secure Boot below).
3. The Containerfile then **rewrites `/etc/os-release`** to masquerade as Fedora (`ID=fedora`, `NAME="CampiOS"`). This is required because `bootc-image-builder` doesn't recognize the `rakuos` ID and would refuse to generate ISO/QCOW2 images otherwise.
4. `bootc container lint` validates the final image.

`build.sh` picks the dnf binary defensively (`dnf5.real` if the base has wrapped `dnf`); use the `$DNF` variable, don't hardcode `dnf`.

## Architecture & non-obvious patterns

### Immutable-OS config model
`/usr` is read-only at runtime, so user-facing defaults are applied two ways and **both must be kept in sync**:
- **New users:** seed files in `/etc/skel` (niri config, DMS plugin settings, the per-user `campios-dev-box` service symlink).
- **Existing users:** reconciled at boot by `campios-sync-user-configs.service` → `/usr/libexec/campios-sync-user-configs`, which sets the login shell to fish, symlinks `~/.config/niri/config.kdl` to the managed `/usr/share/campios/niri/config.kdl` (backing up any real file), and enables the DankKDEConnect plugin via a **non-destructive `jq` merge** (never clobbers a user's explicit choice).

Anything that must not be baked into read-only `/usr` is **bootstrapped at runtime into the home dir**: the **dev-box** is the canonical example — the image ships only `distrobox` plus the assemble manifest `build_files/distrobox/dev-box.ini` (installed to `/usr/share/campios/distrobox/`), and `campios-dev-box.service` (per-user oneshot, first login) runs `/usr/libexec/campios-create-devbox`, which `distrobox assemble create`s a `dev-box` container (`fedora-toolbox` base) holding VSCode, Rust/Cargo and Python in the user's rootless podman storage. The creator self-guards (skips if the box already exists) and retries until the network is up; VSCode is exported to the host menu via `exported_apps`. The toolchain thus lives in the mutable home and can be updated without rebuilding the image.

First-boot system services also: install/remove Flatpaks from Flathub (`campios-install-flatpaks.service`, driven by `build_files/flatpaks/{default,remove}-apps.txt`), and set up the desktop (DMS enabled globally; greetd replaces `display-manager.service` and launches `dms-greeter --command niri`).

### Secure Boot (the most fragile part — change carefully)
- The **public** MOK cert is committed (`build_files/secureboot/campios-mok.{der,pem}`). The **private key is never committed**: it's a build secret `campios_mok_key`, sourced in CI from the GitHub secret `CAMPIOS_MOK_KEY_B64` (base64-encoded).
- `sign-secureboot.sh` signs the kernel (`sbsign`) and all kernel modules (`sign-file`, handling `.ko` / `.ko.xz` / `.ko.zst`), then **verifies** that kernel and NVIDIA modules are signed with an expected key — the build **fails** if anything is unsigned or wrongly signed.
- **Critical ordering:** the initramfs is rebuilt at the *end* of `build.sh`, *after* signing, so the signed NVIDIA modules (and the CampiOS Plymouth theme) end up inside it. Do not reorder these steps.
- MOK enrollment happens on the target machine: `install-mok-enroll-script.sh` installs the `/usr/libexec/campios-enroll-mok` helper, and the ISO's anaconda kickstart (`disk_config/iso.toml`) queues enrollment in a `%post`. The enrollment password is `campios`.

### Desktop stack
niri (Wayland compositor) + Dank Material Shell / quickshell, greetd + dms-greeter login, kitty terminal, **fish as default shell**, nautilus/dolphin, KDE Connect.

### ISO install flow
The ISO installs a generic image and, in the kickstart `%post`, runs `bootc switch --mutate-in-place` to the published image `ghcr.io/campio97/campios:latest`, then adopts/updates the EFI bootloader via `bootupctl`.

## CI/CD
- `.github/workflows/build.yml` — builds with buildah and pushes to GHCR on push to `main`, on PRs, and on a daily cron (10:05 UTC). Signs with cosign (`SIGNING_SECRET`) and injects the MOK key (`CAMPIOS_MOK_KEY_B64`). The published image is `ghcr.io/campio97/campios`.
- `.github/workflows/build-disk.yml` — builds `qcow2` + `anaconda-iso` via `bootc-image-builder-action`, with optional upload to S3 (configured via repo secrets).

## Gotchas
- **fish ignores `/etc/profile.d/*.sh`.** Any PATH/env change for login shells must be added in *both* `/etc/profile.d/*.sh` and `/etc/fish/conf.d/*.fish`.
- **`disk_config/iso-gnome.toml` and `iso-kde.toml` are not referenced anywhere** — builds use `iso.toml` (ISO) and `disk.toml` (qcow2/raw). Don't assume editing the gnome/kde variants changes a build.
- Firewall rules at build time use `firewall-offline-cmd` (the firewalld daemon isn't running during the build); KDE Connect needs TCP+UDP `1714-1764` open.
- Never commit `cosign.key` or the MOK private key. `.gitignore` already excludes `cosign.key`, `output/`, `_build*`, and `secureboot/private/`.
- The container signature policy (`build_files/etc/containers/policy.json`) defaults to `reject` and only trusts `ghcr.io/rakuos`, `ghcr.io/campio97/campios`, the rakuos GitLab registry, and `registry.fedoraproject.org` (the dev-box `fedora-toolbox` base) — update it if the base image, publish target, or a distrobox base from a new registry changes. **Any rootless `podman`/`distrobox` pull is governed by this policy too:** pulling from an untrusted registry fails with `Source image rejected: ... rejected by policy`.
