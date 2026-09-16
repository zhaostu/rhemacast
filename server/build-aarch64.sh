#!/usr/bin/env bash
# Cross-compile rhemacastd for 64-bit ARM boards (Orange Pi 3 LTS, Pi 3B/4
# running a 64-bit OS) — no Docker. Needs: aarch64-linux-gnu-gcc in PATH
# (Arch: sudo pacman -S aarch64-linux-gnu-gcc) + rust target (already in repo CI).
# Usage: ./server/build-aarch64.sh   (run from repo root or anywhere)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYSROOT="$SCRIPT_DIR/.sysroot-aarch64"

command -v aarch64-linux-gnu-gcc >/dev/null \
  || { echo "ERROR: aarch64-linux-gnu-gcc not found (Arch: sudo pacman -S aarch64-linux-gnu-gcc)" >&2; exit 1; }
rustup target list --installed 2>/dev/null | grep -q aarch64-unknown-linux-gnu \
  || rustup target add aarch64-unknown-linux-gnu

"$SCRIPT_DIR/mk-sysroot.sh"

# Target-suffixed SYSROOT_DIR: only affects aarch64 probes (host builds untouched).
# PKG_CONFIG_PATH is scoped to this one cargo invocation.
export PKG_CONFIG_SYSROOT_DIR_aarch64_unknown_linux_gnu="$SYSROOT"
export PKG_CONFIG_PATH="$SYSROOT/usr/lib/aarch64-linux-gnu/pkgconfig"

(cd "$SCRIPT_DIR" && cargo build --release --target aarch64-unknown-linux-gnu)

BIN="$SCRIPT_DIR/target/aarch64-unknown-linux-gnu/release/rhemacastd"
echo "== $(file -b "$BIN")"
ls -la "$BIN"
echo "deploy: scp $BIN pi@<pi-ip>:/tmp/ && ssh pi@<pi-ip> 'sudo install -m755 /tmp/rhemacastd /usr/local/bin/'"
