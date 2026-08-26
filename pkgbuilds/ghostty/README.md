# Ghostty on aarch64

Ghostty is not in Arch Linux ARM's repositories, but Arch's own package
declares `arch=(x86_64 aarch64 i686)` — it builds fine on ARM. Three
adjustments are needed, none of them ARM code problems.

## 1. Zig version

Ghostty 1.3.1 requires **Zig 0.15.2**; Arch Linux ARM ships 0.16.0, and the
build fails at comptime with:

```
Your Zig version v0.16.0 does not meet the required build version of v0.15.2
```

The same mismatch is why AUR's `ghostty-git` (`zig<0.16.0`) refuses to build.
Zig publishes official aarch64 Linux builds, so use one:

```bash
curl -fsSL -o zig.tar.xz https://ziglang.org/download/0.15.2/zig-aarch64-linux-0.15.2.tar.xz
tar xf zig.tar.xz && export PATH="$PWD/zig-aarch64-linux-0.15.2:$PATH"
```

## 2. pandoc

`pandoc-cli` is x86_64-only in Arch and has no aarch64 build anywhere (the
Haskell toolchain is not built for ARM). It is only used for man pages.

In `--system` package mode Ghostty **defaults `emit_docs` to true**, so simply
removing `-Demit-docs` is not enough — it must be turned off explicitly. This
PKGBUILD drops `pandoc-cli` from `makedepends` and passes `-Demit-docs=false`.

## 3. A missing Zig dependency

`nix/build-support/fetch-zig-cache.sh` in 1.3.1-2 prefetches `uucode-0.1.0`,
while `build.zig.zon` requires `0.2.0`, so the build stops with
`package not found`. Fetch and unpack it into the cache before building:

```bash
cd src/ghostty-1.3.1
H=uucode-0.2.0-ZZjBPqZVVABQepOqZHR7vV_NcaN-wats0IB6o-Exj6m9
ZIG_GLOBAL_CACHE_DIR="$srcdir/zig-global-cache/" zig fetch "https://deps.files.ghostty.org/$H.tar.gz"
cd "$srcdir/zig-global-cache/p" && mkdir -p "$H" && tar xzf "$H.tar.gz" -C "$H" --strip-components=1
```

## Result

Builds `ghostty`, `ghostty-terminfo`, `ghostty-shell-integration` and
`ghostty-nautilus` for aarch64. After installing, Omarchy's own
`omarchy install terminal ghostty` sets it as the default terminal, and
Super+Return opens it with the active theme applied.

Note the build needs several GB of free disk and a few GB of RAM.
