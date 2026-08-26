# Testing the VM image

The VM runs the same aarch64 userspace as the Pi, at native speed on Apple
Silicon. It validates everything except the Pi's GPU driver and boot firmware.

## Build it

Needs Docker (native arm64 containers) and QEMU:

```bash
brew install qemu
git clone https://github.com/omacom-io/omarchy-pkgs.git ../omarchy-pkgs
git clone -b pi5 https://github.com/vincenth19/omarchy.git ../omarchy
./scripts/build-all.sh
```

## Run it

```bash
./scripts/run-vm.sh
```

A window opens and boots to the Omarchy desktop. Log in as `omarchy` /
`omarchy`.

For scripted testing without a window:

```bash
HEADLESS=1 ./scripts/run-vm.sh
ssh -p 2222 omarchy@localhost
```

## What the VM does and does not prove

| Proven in the VM | Only provable on the Pi |
|---|---|
| Every package resolves and installs on aarch64 | V3D GPU driver behaviour |
| Omarchy's installer runs to completion | Fractional-scaling rendering bugs |
| systemd services start cleanly | Pi firmware boot path |
| Hyprland, SDDM and the shell come up | Thermals and real-world performance |

The VM has no real GPU, so Hyprland runs on software rendering. Do not judge
animation smoothness there.

## Known limitations

Docker Desktop defaults to a small memory allocation (4 GB). Some Rust packages
— `herdr` in particular — get OOM-killed while linking. Raise Docker's memory to
8 GB or more in Docker Desktop → Settings → Resources if you need those built.
