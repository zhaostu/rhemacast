#!/usr/bin/env bash
# Local install driver for rhemacastd on netplan/Armbian boards.
# Given the Pi IP it: (1) cross-builds the ARM64 binary,
# (2) copies binary + service unit + AP files to /tmp on the Pi,
# (3) prints the exact commands to run ON the Pi (sudo needs its
# password interactively, so the remote steps stay manual).
# Usage: ./server/install.sh <pi-ip> [user]   (default user: stu)
set -euo pipefail

PI_IP="${1:-}"
PI_USER="${2:-stu}"
[ -n "$PI_IP" ] || { echo "usage: $0 <pi-ip> [user]" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$SCRIPT_DIR/target/aarch64-unknown-linux-gnu/release/rhemacastd"

echo "== 1/3 build (aarch64)"
"$SCRIPT_DIR/build-aarch64.sh" >/dev/null
echo "built: $BIN"

echo "== 2/3 copy to $PI_USER@$PI_IP:/tmp/"
scp "$BIN" "$PI_USER@$PI_IP:/tmp/rhemacastd"
scp "$SCRIPT_DIR/rhemacastd.service" "$SCRIPT_DIR/ap.sh" "$SCRIPT_DIR/setup-pi.sh" \
    "$SCRIPT_DIR/hostapd.conf.example" "$PI_USER@$PI_IP:/tmp/"
ssh "$PI_USER@$PI_IP" 'chmod +x /tmp/rhemacastd /tmp/ap.sh /tmp/setup-pi.sh && ls -la /tmp/rhemacastd /tmp/ap.sh /tmp/setup-pi.sh'

cat <<EOF
== 3/3 run ON the Pi (ssh $PI_USER@$PI_IP) — one command:

sudo bash /tmp/setup-pi.sh    # installs + enables (auto-start on power-on),
                             # verifies, then prompts for AP mode

# verify:
systemctl is-active rhemacastd
curl http://127.0.0.1:8080/api/status

# optional offline hotspot (reversible):
sudo bash /tmp/ap.sh on    # or once installed: sudo rhemacast-ap on
# way back to wifi client (AP toggle persists at /usr/local/sbin/rhemacast-ap):
#   join the AP (or LAN), ssh in, then:  sudo rhemacast-ap off
EOF
