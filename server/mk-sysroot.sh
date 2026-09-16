#!/usr/bin/env bash
# Assemble an ARM64 sysroot from Debian bookworm packages (no Docker, no root).
# Provides target-arch ALSA + Opus headers/libs so -sys crates link for
# aarch64-unknown-linux-gnu. Idempotent: skips packages already extracted.
# Output: server/.sysroot-aarch64/  (gitignored, ~5MB)
# NB: no pipefail — stanza parsers exit after the first match, SIGPIPEing
# curl; curl -f and the empty-result check already catch real failures.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYSROOT="$SCRIPT_DIR/.sysroot-aarch64"
MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
SUITE="${DEBIAN_SUITE:-bookworm}"
PKGS="libasound2 libasound2-dev libopus0 libopus-dev"

need_deb() { # $1 = package name; prints pool path or nothing
  local pkg="$1" idx
  # (|| true: awk exits after the first match, SIGPIPEing curl — not an error)
  idx="$(curl -fsSL "$MIRROR/dists/$SUITE/main/binary-arm64/Packages.gz" | gzip -dc || true)"
  echo "$idx" | awk -v p="^Package: $pkg\$" '
    $0 ~ p {found=1; next}
    found && /^Filename: / {print $2; exit}
    found && /^$/ {found=0}'
}

mkdir -p "$SYSROOT" "$SCRIPT_DIR/.dl"
for pkg in $PKGS; do
  if [ -f "$SYSROOT/.done-$pkg" ]; then
    echo "(sysroot: $pkg already extracted)"
    continue
  fi
  echo "-> resolving $pkg ..."
  pool_path="$(need_deb "$pkg")"
  [ -n "$pool_path" ] || { echo "ERROR: $pkg not in $SUITE/arm64 index" >&2; exit 1; }
  deb="$SCRIPT_DIR/.dl/$(basename "$pool_path")"
  [ -f "$deb" ] || curl -fSL -o "$deb" "$MIRROR/$pool_path"
  echo "-> extracting $(basename "$deb") ..."
  tmpd="$(mktemp -d)"
  (cd "$tmpd" && ar x "$deb" && bsdtar -xf data.tar.* -C "$SYSROOT")
  rm -rf "$tmpd"
  touch "$SYSROOT/.done-$pkg"
done

echo "sysroot ready: $SYSROOT"
ls "$SYSROOT/usr/lib/aarch64-linux-gnu/pkgconfig/" | grep -E '^(alsa|opus)\.pc$'
