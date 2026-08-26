# Porting plan

## Phases

| # | Phase | Status |
|---|---|---|
| 1 | Establish the aarch64 build environment (Docker, native arm64 on Apple Silicon) | done |
| 2 | Determine package availability and rebuild what upstream ships x86_64-only | done — 23 built, see below |
| 3 | Build a bootable VM image and run Omarchy's own installer on ARM | in progress |
| 4 | Verify on real Pi 5 hardware (GPU, firmware boot, thermals) | not started |
| 5 | Automated image releases via CI | scaffolded ([workflow](../.github/workflows/build-image.yml)) |
| 6 | Host an aarch64 pacman repo so installed systems get package updates | not started |

### Package findings (Omarchy 4.0.1)

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

## Known Pi/ARM gotchas

### Found and fixed in this port

These were hit while getting Omarchy 4.0.1 to install on aarch64. Each is fixed
on the [`pi5` branch](https://github.com/vincenth19/omarchy/tree/pi5).

| Symptom | Cause | Fix |
|---|---|---|
| `bundled Node.js tarball missing` on first install | `install/user/mise-work.sh` globs `node-v*-linux-x64.tar.gz` unconditionally | Derive the suffix from `uname -m` |
| Install step dies before doing anything | `install/hardware/apple/fix-spi-keyboard.sh` reads `/sys/class/dmi/id/product_name`; the Pi has no DMI, so the assignment fails under `bash -eE` | `\|\| true` on the read |
| `Hook 'btrfs-overlayfs' cannot be found` | `omarchy_hooks.conf` HOOKS ends in a hook shipped by the Limine/snapper stack we do not install | Drop it from HOOKS |
| `module not found: 'thunderbolt'` | `thunderbolt_module.conf` adds a module the Pi kernel lacks | Add it only when `modinfo` finds it |
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
