# Porting plan

## Phases

1. **UTM validation (current).** Build the native aarch64 Omarchy 4 VM on Apple Silicon using [omarchy-arm-utm](https://github.com/basecamp/omarchy/discussions/7956). Proves the ARM userspace: which packages exist in Arch Linux ARM repos, which need source builds, what the installer assumes about x86.
2. **Patch set.** Turn the findings into commits on the `pi5` branch of our `basecamp/omarchy` fork. Keep it minimal — prefer user-config overrides over editing core files.
3. **Manual Pi 5 install.** Arch Linux ARM + `linux-rpi` kernel on a real Pi 5, install from the `pi5` branch, fight the GPU (see gotchas below). Document every step.
4. **Scripted install.** One script that takes a fresh Arch Linux ARM Pi 5 system to full Omarchy.
5. **Image releases.** CI builds a flashable `.img.xz` (GitHub Actions can build aarch64 images via qemu binfmt). Publish on GitHub Releases; flashable with Raspberry Pi Imager.
6. **aarch64 package repo.** Omarchy's [package build system](https://github.com/omacom-io/omarchy-pkgs) supports aarch64 but only x86_64 is published. Host our own pacman repo (GitHub Releases or Pages) so Pi users get binary updates instead of compiling.

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
