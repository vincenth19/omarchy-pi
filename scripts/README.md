# Scripts

Planned tooling — none implemented yet. Each lands as its phase in
[docs/PORTING.md](../docs/PORTING.md) is reached, so nothing here pretends to
work before it does.

| Script (planned) | Phase | Purpose |
|---|---|---|
| `build-utm-vm.sh` | 1 | Wrap/adapt the omarchy-arm-utm build for our fork branch |
| `install-pi5.sh` | 4 | Fresh Arch Linux ARM Pi 5 → full Omarchy |
| `build-image.sh` | 5 | Produce the flashable `.img.xz` (runs in CI via qemu binfmt) |
| `build-pkgs.sh` | 6 | Build aarch64 packages missing from upstream's published repo |
