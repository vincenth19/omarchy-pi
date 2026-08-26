# Application testing

Every app was launched in the built aarch64 image and driven through the real
desktop (QEMU input injection + framebuffer capture), not just checked for a
running process. "Window" means Hyprland reported a mapped window; "renders"
means it was confirmed visually in a screenshot.

![Omarchy menu](images/app-omarchy-menu.png)
*Super+Space — the Omarchy menu, nerd-font icons intact.*

## Out-of-the-box, nothing installed

| App | Result |
|---|---|
| **foot** (default terminal) | Renders, themed, starship prompt |
| **Omarchy menu** (Super+Space) | Full menu, nerd-font icons correct |
| **hyprlock** | **Works** — blurred wallpaper, password unlock |
| **Chromium** | Works, dark theme, loaded omarchy.org over HTTPS with webfonts, images and embedded video |
| **Neovim** (LazyVim config) | Loads, 5/52 plugins in 34 ms |
| **btop** | Full render — CPU, memory, disk, network, process tree |
| **Nautilus** | Renders, icon theme correct |
| **Evince** | Renders |
| **Xournal++** | Renders, full toolbar |
| **LocalSend** | Renders |
| **omacalc** | Renders |
| **omawrite** | Renders |
| **omacut** | Window |
| **Aether** (theme editor) | Renders, target list populated |
| **cliamp** | Runs (TUI, no window — expected) |
| **Xwayland** | Running, so X11 apps are supported |

![Chromium](images/app-chromium.png)
*Chromium on aarch64 with omarchy.org fully rendered.*

![GTK apps](images/app-gtk-apps.png)
*Nautilus, Evince, Xournal++ and LocalSend tiled together.*

![Omarchy tools](images/app-omarchy-tools.png)
*omacalc, omawrite and Aether — Omarchy's own applications.*

![btop](images/app-btop.png)
*btop, showing the running session and 1.1 GB of 5.8 GB in use.*

No crashes. Idle memory use was **1.1 GB of 5.8 GB**, which leaves comfortable
headroom on an 8 GB Pi 5.

Two things the earlier Pi guides warned about did **not** reproduce:
`hyprlock` did not crash, and Chromium was not unstable.

## Installing extra software

`omarchy-pkg-add` (used by `omarchy install ...`) is repository-only, and `yay`
is available for the AUR.

| Package | Result |
|---|---|
| **Ghostty** | **Not available on ARM.** Not in Arch Linux ARM's repositories, and the AUR package will not build |

### Why Ghostty does not install

`omarchy install terminal ghostty` fails because nothing provides a Ghostty
package for aarch64:

- Arch ships `ghostty` in `extra` for **x86_64 only**; Arch Linux ARM has no
  build of it, so `pacman -S ghostty` finds nothing.
- AUR's `ghostty-git` pins `zig<0.16.0`, and Arch Linux ARM ships Zig 0.16.0,
  so `yay` refuses to build it.

This is a packaging gap, not an ARM code problem — Arch's own PKGBUILD declares
`arch=(x86_64 aarch64 i686)`. It becomes installable the normal Omarchy way as
soon as an aarch64 build is published, either by Arch Linux ARM or by this
project's own package repo (phase 6).

The same reasoning applies to any other package missing on ARM: the fix is to
publish a proper aarch64 build, not to hand-patch a one-off local build.

## Caveats

This is a VM: no real GPU, so Hyprland runs on software rendering. Application
*correctness* transfers to the Pi; rendering performance and anything that
depends on the V3D driver does not.
