# Booting omarchy-pi from NVMe

The image is built to boot from NVMe, and the NVMe boot path has been verified
under emulation (`scripts/test-a76-nvme.sh`): the image boots from an emulated
NVMe controller by PARTUUID on a Cortex-A76 and reaches the desktop. Real
BCM2712 PCIe is the one part of that chain only a Pi 5 can exercise.

Nothing in the image is SD-specific:

- **Filesystems are mounted by label** (`LABEL=omarchy-root`, `LABEL=OMARCHYPI`),
  and the kernel finds the root by **PARTUUID**, assigned at build time. No
  device node (`mmcblk0p2` / `nvme0n1p2` / `sda2`) is hardcoded anywhere.
- **The drivers are built into `linux-rpi`**, not modules: `pcie-brcmstb` (the
  BCM2712 PCIe controller) and `nvme`. The initramfs also names `nvme` and
  `nvme_core` as insurance against a modular kernel rebuild.
- **The Pi 5 device tree ships** — `bcm2712-rpi-5-b.dtb` plus seven other
  BCM2712 variants, and the whole of `/boot` is mirrored to the FAT partition
  including `overlays/`.
- **First-boot expansion understands NVMe naming**, so the root filesystem
  grows to fill a 512 GB SSD the same way it fills an SD card.

## Using an NVMe drive for storage

Attach the HAT, boot from the SD card as usual, and the drive appears as
`/dev/nvme0n1`. Nothing else is required.

PCIe Gen 3 is faster but officially unsupported by Raspberry Pi and unstable on
some drive/cable combinations. To try it, uncomment in `/boot/config.txt`:

```
dtparam=pciex1_gen=3
```

Revert it if the drive disappears under load or throws I/O errors.

## Booting from the NVMe drive

One thing the image cannot do for you: the boot order lives in the Pi's **SPI
EEPROM**, not on the card. Set it once, from a working SD boot:

```bash
sudo rpi-eeprom-config --edit
```

Set `BOOT_ORDER=0xf416` — the Pi tries each nibble right to left, so this means
NVMe (6), then SD (1), then USB (4), then retry (f). Keeping SD after NVMe
means a bad NVMe install still falls back to a working card.

Then copy the image onto the SSD, remove the SD card, and reboot.

`arm-peripherals-firmware`/`rpi-eeprom` provides `rpi-eeprom-config`. If it is
not installed, do the EEPROM step from Raspberry Pi OS instead — it is a
one-time firmware setting, independent of which distribution you then run.

## Verifying

```bash
omarchy-pi-doctor        # reports the root device and whether it fills the disk
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
```
