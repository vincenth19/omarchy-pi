# Pi-specific config overrides

Configs that differ from stock Omarchy on the Pi 5. These get applied by the
installer/image on top of the stock Omarchy config, so the `pi5` fork branch
stays as small as possible.

Expected contents as porting progresses:

- `hypr/monitors.conf` — integer scaling only (fractional scaling breaks V3D rendering)
- `pacman/` — Arch Linux ARM mirrors + our aarch64 package repo entry (once it exists)
- `boot/config.txt` — Pi firmware boot settings (GPU memory, KMS overlay)
