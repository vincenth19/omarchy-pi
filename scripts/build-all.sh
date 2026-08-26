#!/usr/bin/env bash
# Host-side orchestrator: packages -> rootfs -> bootable image.
#
# Runs on an Apple Silicon Mac with Docker (native aarch64 containers, so no
# emulation penalty). Produces work/out/omarchy-pi.img.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
VARIANT="${VARIANT:-vm}"
PKGS_REPO="${PKGS_REPO:-$ROOT/../omarchy-pkgs}"
OMARCHY="${OMARCHY:-$ROOT/../omarchy}"
WORK="$ROOT/work"
mkdir -p "$WORK/out"

[ -d "$PKGS_REPO" ] || { echo "Missing $PKGS_REPO (git clone omacom-io/omarchy-pkgs)" >&2; exit 1; }
[ -d "$OMARCHY" ]   || { echo "Missing $OMARCHY (clone of our omarchy fork)" >&2; exit 1; }

echo "### Stage 0: container images"
docker build --quiet --platform linux/arm64 -t alarm-work  -f docker/Dockerfile.alarm  docker/ >/dev/null
docker build --quiet --platform linux/arm64 -t alarm-build -f docker/Dockerfile.build docker/ >/dev/null

echo "### Stage 1: build rootfs ($VARIANT)"
docker rm -f omarchy-rootfs >/dev/null 2>&1 || true
# Persistent package cache: a rebuild otherwise re-downloads several GB.
docker volume create omarchy-pi-pacman-cache >/dev/null

# Snapshot the scripts rather than bind-mounting them live. bash reads a script
# incrementally as it executes, so editing one mid-run corrupts that run.
SNAP="$WORK/.scripts"
rm -rf "$SNAP" && cp -r "$ROOT/scripts" "$SNAP"

docker run --name omarchy-rootfs --platform linux/arm64 \
  -v omarchy-pi-pacman-cache:/var/cache/pacman/pkg \
  -v "$SNAP:/scripts:ro" \
  -v "$ROOT/config:/config:ro" \
  -v "$OMARCHY:/omarchy:ro" \
  -v "$WORK/out:/pkgs:ro" \
  -e VARIANT="$VARIANT" \
  alarm-work bash /scripts/build-rootfs.sh

echo "### Stage 2: export rootfs"
docker export omarchy-rootfs -o "$WORK/rootfs.tar"

echo "### Stage 3: assemble image"
docker run --rm --platform linux/arm64 \
  -v "$SNAP:/scripts:ro" \
  -v "$ROOT/config:/config:ro" \
  -v "$WORK:/work" \
  -e VARIANT="$VARIANT" \
  alarm-work bash -c '
    set -e
    pacman -S --noconfirm --needed e2fsprogs dosfstools mtools gptfdisk util-linux >/dev/null 2>&1
    rm -rf /rootfs && mkdir -p /rootfs
    tar -xf /work/rootfs.tar -C /rootfs
    # Docker-injected files that must not ship in the image
    rm -f /rootfs/.dockerenv /rootfs/etc/hostname /rootfs/etc/hosts /rootfs/etc/resolv.conf
    printf "omarchy-pi\n" > /rootfs/etc/hostname
    printf "127.0.0.1 localhost\n::1 localhost\n127.0.1.1 omarchy-pi\n" > /rootfs/etc/hosts
    ln -sf /run/systemd/resolve/stub-resolv.conf /rootfs/etc/resolv.conf
    OUT=/work/out/omarchy-pi.img ROOTFS=/rootfs bash /scripts/build-image.sh
  '

echo
echo "### Done: $WORK/out/omarchy-pi.img"
echo "    Boot it:  ./scripts/run-vm.sh"
