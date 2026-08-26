# omarchy-pi

Run [Omarchy](https://omarchy.org) — full experience, latest stable — on the Raspberry Pi 5.

> **Status: pre-alpha / planning.** Nothing flashable exists yet. Follow along or contribute — the porting plan is in [docs/PORTING.md](docs/PORTING.md).

## Goal

A ready-to-flash SD card image (`.img.xz`, flashable with Raspberry Pi Imager) that boots a Pi 5 straight into Omarchy, tracking upstream stable releases with a minimal patch set — not a fork-distro.

## How it's structured

| Piece | What it is |
|---|---|
| **This repo** | Docs, image build tooling, Pi-specific configs, CI |
| [`vincenth19/omarchy`](https://github.com/vincenth19/omarchy) (`pi5` branch) | Fork of `basecamp/omarchy`: upstream stable tag + a few Pi/ARM patch commits, rebased on each upstream release |
| aarch64 package repo *(planned)* | Omarchy's build system [supports aarch64 but only publishes x86_64 today](https://github.com/omacom-io/omarchy-pkgs), so we'll build and host the ARM packages ourselves |

## Approach

- Base: **Arch Linux ARM** with the `linux-rpi` kernel (Pi 5)
- Omarchy installed from our `pi5` fork branch; updates = upstream tag + rebase
- Bootloader: Pi firmware boot (Omarchy's Limine/snapshot layer doesn't apply to Pi)
- Validation happens first in a native aarch64 UTM VM on Apple Silicon, building on [ggalancs/omarchy-arm-utm](https://github.com/basecamp/omarchy/discussions/7956)

## Hardware target

- Raspberry Pi 5, 8 GB (4 GB untested)
- Official 5V/5A USB-C PSU, active cooler
- 32 GB+ microSD (A2-rated recommended) or NVMe HAT

## Prior art & credits

- [Omarchy](https://github.com/basecamp/omarchy) by DHH / Basecamp — the thing itself
- [omarchy-arm-utm](https://github.com/basecamp/omarchy/discussions/7956) — Omarchy 4 native aarch64 UTM build
- [omarchy-arm-fixes](https://github.com/happybigmtn/omarchy-arm-fixes) — ARM package/config fixes (Apple Silicon)
- [Pi 5 install guide (discussion #642)](https://github.com/basecamp/omarchy/discussions/642) — earlier Manjaro-based attempt; source of Pi-specific gotchas

## License

MIT — see [LICENSE](LICENSE). Omarchy itself is MIT-licensed by its authors.
