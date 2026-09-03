# Porting plan

## Phases

| # | Phase | Status |
|---|---|---|
| 1 | Establish the aarch64 build environment (Docker, native arm64 on Apple Silicon) | done |
| 2 | Determine package availability and rebuild what upstream ships x86_64-only | done — 23 built, see below |
| 3 | Build a bootable VM image and run Omarchy's own installer on ARM | done — 4.0.2, zero failed steps |
| 3b | Verify the Pi boot chain as far as emulation allows (see below) | done |
| 4 | Verify on real Pi 5 hardware (V3D GPU, firmware boot, thermals) | not started — needs a Pi |
| 5 | Automated image releases via CI | scaffolded ([workflow](../.github/workflows/build-image.yml)) |
| 6 | Host an aarch64 pacman repo so installed systems get package updates | not started |

### Package findings (Omarchy 4.0.2)

Of the 148 packages in `install/omarchy-base.packages`, 122 install directly
from Arch Linux ARM. The rest:

- **19 rebuilt** from [omarchy-pkgs](https://github.com/omacom-io/omarchy-pkgs)
  PKGBUILDs. Most already declared `aarch64`; the rest needed only an `arch=`
  addition, not code changes.
- **4 core packages** built separately: `omarchy`, `omarchy-settings`,
  `omarchy-keyring`, `ttf-jetbrains-mono-nerd-basic`. The `omarchy` package is
  `arch=any` but hard-depends on the Limine bootloader stack, so we build a
  [patched PKGBUILD](../pkgbuilds/omarchy/PKGBUILD).
- **`nvim`** needs nothing — Arch Linux ARM's `neovim` already provides it.
- **6 dropped** on the `pi5` branch: `asdcontrol`, `qemu-user-static-binfmt`
  (x86-only, no Pi relevance) and `dotnet-runtime`, `pinta`, `obs-studio`,
  `obsidian` (no aarch64 build). None are needed for the desktop.
- **`herdr`** builds on ARM but gets OOM-killed while linking under Docker
  Desktop's default 4 GB. Not an architecture problem — it needs more memory.

### How close to a Pi 5 can we get without one?

No emulator models the BCM2712: QEMU tops out at `raspi4b` (BCM2711, a
hardwired Cortex-A72, no PCIe, no GPU), and this QEMU build has no virgl. So
the Pi-specific risks are split across two harnesses that each cover a slice:

| Harness | Models | Verified |
|---|---|---|
| `scripts/test-raspi4b.sh` | Pi-family SoC (BCM2711), SD controller, the real `linux-rpi` kernel + initramfs from the image | Kernel boots, SD card found (as `mmc1`), root located by **PARTUUID**, ext4 mounted rw, systemd reaches `System Initialization`. Userspace console is invisible there (QEMU cannot clock the BCM2711 PL011), so progress is read from the journal the boot writes onto the image's own root filesystem |
| `scripts/test-a76-nvme.sh` | The Pi 5's **Cortex-A76** core (TCG), root on an emulated **NVMe** controller — the exact path an NVMe HAT takes | Boots by PARTUUID from `nvme0n1p2`; every shipped binary runs with **no illegal-instruction faults**; Hyprland and quickshell start and render; 0 failed units. `omacalc`/`omawrite` exit 134 (SIGABRT) when run with no display — Qt aborting, not an ISA fault; both run under `QT_QPA_PLATFORM=offscreen` |

Not covered by anything virtual: BCM2712 peripherals, RP1, the V3D GPU driver,
and the real firmware's `config.txt` handling. Those need the board.

## Known Pi/ARM gotchas

### Found and fixed in this port

These were hit while getting Omarchy 4.0.1 to install on aarch64. Each is fixed
on the [`pi5` branch](https://github.com/vincenth19/omarchy/tree/pi5).

| Symptom | Cause | Fix |
|---|---|---|
| `bundled Node.js tarball missing` on first install | `install/user/mise-work.sh` globs `node-v*-linux-x64.tar.gz` unconditionally | Derive the suffix from `uname -m` |
| Install step dies before doing anything | `install/hardware/apple/fix-spi-keyboard.sh` reads `/sys/class/dmi/id/product_name`; the Pi has no DMI, so the assignment fails under `bash -eE` | `\|\| true` on the read |
| `Hook 'btrfs-overlayfs' cannot be found` | `omarchy_hooks.conf` HOOKS ends in a hook shipped by the Limine/snapper stack we do not install | Removed by our additive drop-in, not by editing their file |
| `module not found: 'thunderbolt'` | `thunderbolt_module.conf` adds a module the Pi kernel lacks | Removed by our additive drop-in |
| `snapper.sh` exits 127 | snapper is not installed on this port | Skip when the binary is absent |
| pacman left pointing at x86 mirrors | `post-install/pacman.sh` restores `default/pacman/pacman-$OMARCHY_MIRROR.conf`, defaulting to `stable` (Omarchy's Arch mirror has no aarch64 tree, and `[multilib]` does not exist for ARM) | Add a `pi` mirror variant and set `OMARCHY_MIRROR=pi` |

### Build-environment traps (not Omarchy bugs)

| Symptom | Cause |
|---|---|
| Kernel panics with no root device | `mkinitcpio`'s `autodetect` hook trims modules to the *build* machine's hardware. Generic images must not autodetect |
| A rebuilt package has no effect | pacman installs the stale cached tarball, since a rebuild keeps the same version-release. Evict it from the cache first |
| Package build killed while linking | Docker Desktop's 4 GB default. Not an ARM issue — raise the memory or build with `JOBS=1` |
| Script dies mid-run with a syntax error | bash reads scripts incrementally; editing a mounted script while a container runs it corrupts that run. `build-all.sh` snapshots them |

### Expected on real hardware (not yet verified)

| Issue | Mitigation |
|---|---|
| Fractional scaling breaks rendering (black waybar) | Integer scaling only — see [config/hypr/monitors.conf](../config/hypr/monitors.conf) |
| `hyprlock` reported to crash on ARM | Use `hyprlock-git` if it reproduces |
| Chromium unstable on ARM | Brave or Firefox |

Re-verify the third group against current Omarchy and Mesa before carrying the
workaround forward — some may already be fixed upstream.

## Keeping upstream updates safe

How the port avoids letting an Omarchy release break a user's Pi — the
three tiers of patching and the release gate — is in
[ADAPTER.md](ADAPTER.md).

## Update workflow

**Omarchy 4 ships itself as pacman packages, not a git checkout.** The `omarchy`
package installs to `/usr/share/omarchy`, and `omarchy-update` upgrades it from
`pkgs.omarchy.org` — which publishes x86_64 only. So tracking upstream means
rebuilding packages, not pulling a repo.

Two pieces:

**1. Source patches** live on the `pi5` branch of our
[omarchy fork](https://github.com/vincenth19/omarchy), based on the upstream
stable tag. On each upstream release:

```
git fetch upstream --tags
git rebase v<new-tag> pi5
git push --force-with-lease origin pi5
```

**2. Packages** are rebuilt from that branch for aarch64 and published to our
own repo. The upstream PKGBUILD supports `OMARCHY_SRC=/path/to/checkout`, so we
build the patched tree directly rather than maintaining a source fork of the
packaging.

Our `omarchy` PKGBUILD ([pkgbuilds/omarchy](../pkgbuilds/omarchy/PKGBUILD))
drops the `limine` / `limine-mkinitcpio-hook` / `limine-snapper-sync` / `snapper`
hard dependencies. Those assume PC-style UEFI boot and a btrfs root; the Pi
boots from its own firmware off the FAT partition.

Users then update normally — pacman pulls from our aarch64 repo instead of
upstream's x86_64 one. That is what makes this painless for people who are not
maintaining the port.

## Non-goals

- Supporting Pi 4 or other SBCs (until Pi 5 works well)
- Diverging from upstream behavior beyond what ARM/Pi strictly requires
