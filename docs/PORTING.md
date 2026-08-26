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

| Issue | Cause | Fix |
|---|---|---|
| Fractional scaling breaks waybar/rendering | Pi's V3D Mesa driver mishandles the render-high-then-downsample path | Integer scaling only: `monitor = ..., scale, 1` (or 2) |
| `hyprlock` crashes | ARM/driver issue in the release build | Use `hyprlock-git` |
| Chromium unstable on ARM | Library mismatches | Brave or Firefox as default browser |
| Limine bootloader + btrfs snapshot layer | Pi boots via its own firmware reading a FAT partition, no UEFI/Limine | Skip entirely; Pi-native boot config instead |
| Some x86_64-only packages | No aarch64 build exists | Substitute or build from source (see omarchy-arm-fixes and the UTM build script for the known list) |

Re-verify each of these against current Omarchy stable + current Mesa before carrying the workaround forward — some may be fixed upstream.

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
