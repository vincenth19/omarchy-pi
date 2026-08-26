# Tests

```bash
./test/run.sh            # fast: seconds, no Docker
./test/run.sh container  # + aarch64 container checks (minutes)
./test/run.sh all        # + boot a built image and smoke-test it
```

Three tiers, cheapest first, so a regression is caught as early as possible.

## fast.d — static checks, no Docker

| File | Guards against |
|---|---|
| `10-script-syntax.sh` | An unparseable script. bash reads scripts incrementally, so a syntax error can corrupt a build halfway through rather than failing at launch |
| `20-pacman-config.sh` | The pacman failures hit during the port: missing `DatabaseOptional` (every sync 404s on `core.db.sig`), `[multilib]` present, an upstream x86_64 repo that could replace our `arch=any` builds |
| `30-patch-series.sh` | Series drift: not on the latest stable tag, tracking `master`, growing past its budget, or patching files an additive drop-in already covers |
| `40-build-policy.sh` | Scope creep: rebuilding third-party packages, carrying a non-Omarchy PKGBUILD, or reintroducing the Limine/snapper dependencies the Pi cannot use |
| `50-image-builder.sh` | Bugs that produced unbootable images: `autodetect` stripping the target's drivers, a stale pacman cache silently ignoring rebuilds, the x86 pacman config being restored, creating the user before `/etc/skel` is populated, wrong kernel name per variant |
| `60-upstream-channel.sh` | Following a pre-release or a branch, and CI publishing something that never booted |

## container.d — behavioural checks in an aarch64 container

| File | Verifies |
|---|---|
| `10-dropin-behaviour.sh` | The initramfs drop-in is *sourced* the way mkinitcpio does it and really strips `btrfs-overlayfs`, `thunderbolt` and `encrypt` while preserving the essential hooks. Grepping the file only proves the text exists |
| `20-package-availability.sh` | Every package in Omarchy's base list resolves on aarch64 or is one we rebuild |

## Integration

`scripts/smoke-test.sh` boots a built image and asserts it reaches
`graphical.target` with no failed units, SDDM autologin, and Hyprland running.
This is the release gate — CI will not publish an image that fails it.

## Adding a test

Every check here exists because something actually broke. When you fix a bug,
add the check that would have caught it, and say in a comment what the failure
looked like — the symptom is usually far from the cause in this codebase.
