# The adapter layer

The goal: an Omarchy release should never be able to break a user's Pi. If
something upstream changes in a way this port cannot absorb, it must break
**us, at build time**, before anything is published.

## Why users are structurally safe

Omarchy publishes packages for **x86_64 only**. A Pi installs `omarchy`,
`omarchy-settings` and the rest from *our* aarch64 repo, with the port's
patches already compiled in. An upstream release has no aarch64 package to
push, so it cannot reach a user's machine at all.

What an upstream release *can* break is our rebase — on our machine, during a
rebuild. That is the property we want, and everything below exists to keep it
that way.

## Three tiers, in order of preference

### Tier 1 — additive files (safest)

We add a file upstream does not ship, and never edit one it does. Nothing to
conflict on, and it survives upstream rewriting its own files.

| What | Where |
|---|---|
| initramfs hooks/modules fixes | [`config/mkinitcpio/zz-omarchy-pi.conf`](../config/mkinitcpio/zz-omarchy-pi.conf) — sorts after Omarchy's drop-ins and edits the arrays |
| Pi pacman configuration | `default/pacman/pacman-pi.conf`, selected with `OMARCHY_MIRROR=pi` — upstream's own extension point, a new file rather than a changed one |
| root filesystem expansion | `omarchy-pi-expand-root.service` |
| firewall/SSH policy | `omarchy-pi-allow-ssh.service` |

Prefer this tier always. Two patches that used to edit
`etc/mkinitcpio.conf.d/*` were moved here precisely because they were the most
likely to conflict.

### Tier 2 — pacman `backup=` files

Omarchy lists its `/etc` files in `backup=()`, so pacman never silently
overwrites a modified one — it writes `.pacnew` and leaves yours in place.
Usable, but it drifts silently from upstream, so prefer Tier 1.

### Tier 3 — source patches on the `pi5` branch (last resort)

Some fixes have to live inside the package because they *are* the package.
These are the ones that can conflict on rebase:

| Patch | Runs when |
|---|---|
| `omarchy-base.packages` — drop x86-only packages | image build |
| `mise-work.sh` — Node tarball architecture | first install, new user |
| `snapper.sh` — skip when snapper absent | install, `omarchy apply system` |
| `fix-spi-keyboard.sh` — machines with no DMI | install, `omarchy apply hardware` |

All four run at **install or provisioning time**, not during a normal
`omarchy-update`. That limits the blast radius: a stale copy on a running
system does nothing until a user is provisioned or hardware is re-applied.

Keep this tier as small as possible. Every patch here is a future merge
conflict.

## Channel policy: stable tags only

Upstream has a single branch, `master` — the development line. This port never
tracks it. `scripts/sync-upstream.sh` resolves the newest tag with no
`alpha`/`beta`/`rc` suffix and rebases the series onto that:

```bash
./scripts/sync-upstream.sh
```

Omarchy itself defines three channels (`stable`, `rc`, `edge`) in
`default/pacman/`. The port adds a fourth variant, `pi`, built from the stable
one. Following `rc` or `edge` would mean debugging upstream's in-flight changes
and a Pi port at the same time.

## Package policy: no third-party rebuilds

The port rebuilds **only packages Omarchy itself publishes**, because upstream
publishes them for x86_64 only and without them there is no Omarchy on ARM.

It does **not** rebuild third-party software that lacks an aarch64 build.
Ghostty was the test case: building it locally needed a pinned older Zig, a
dependency patched out, and a hand-fix to a stale dependency cache. That is not
something anyone wants to re-do every release. Such software is documented as
unsupported instead.

`scripts/build-pkgs.sh` enforces this — it refuses any package with no PKGBUILD
in `omarchy-pkgs` rather than letting the maintenance burden grow quietly.

## The actual guard: the release pipeline

Runtime cleverness cannot save a user from a bad package. Not shipping one can.
The release sequence must be, in order:

1. `git fetch upstream --tags` and rebase `pi5` onto the new tag
2. **A conflict stops here.** This is the intended failure: fix the patch
   against the new upstream, or drop it if upstream fixed it themselves
3. Rebuild the aarch64 packages
4. Build an image and boot it — `scripts/smoke-test.sh` must pass:
   reaches `graphical.target`, zero failed units, SDDM and Hyprland running
5. Only then publish to the repo

A release that fails any step is simply not published. Users stay on the last
good one.

## Checks worth adding

- **Patch-count assertion.** Fail the build if `pi5` carries more commits than
  expected — a silent extra patch is a silent extra liability.
- **Upstream-fixed detection.** If a Tier 3 patch applies as a no-op, upstream
  fixed it; drop the patch instead of carrying it forever.
- **`omarchy-pi-doctor`** *(implemented)* — ships in the image at
  `/usr/local/bin/omarchy-pi-doctor`. Read-only; checks architecture, pacman
  sources, the adapter drop-in, `.pacnew` drift, free space, root expansion,
  the default target, the DRM device and failed units.
- **Repo precedence.** Our `[omarchy-pi]` repo must be listed first, and
  upstream's `[omarchy]` must not appear at all — `omarchy` and
  `omarchy-settings` are `arch=any`, so an upstream repo entry could otherwise
  satisfy them and replace our builds.
