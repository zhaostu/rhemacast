#!/usr/bin/env bash
# rhemacast AP toggle for netplan-managed boards (Orange Pi 3 LTS / Armbian).
# Uses the same stack the OS already runs: netplan -> systemd-networkd for
# the address, hostapd for AP mode, dnsmasq for DHCP. No NetworkManager.
# Usage (on the Pi):  sudo ./ap.sh on   |   sudo ./ap.sh off
set -euo pipefail

# SSH dies at `netplan apply` (wlan0 leaves the LAN and takes the session
# with it). The script runs on past that point, so ignore hangup; rejoin
# via the AP at 192.168.4.1 afterwards.
trap '' HUP

MODE="${1:-}"
WIFI_YAML=/etc/netplan/30-wifis-dhcp.yaml
WIFI_BAK=/etc/netplan/30-wifis-dhcp.yaml.rhemacast-bak  # non-.yaml: netplan ignores it
AP_YAML=/etc/netplan/30-rhemacast-ap.yaml
HOSTAPD_CONF=/etc/hostapd/hostapd.conf
DNSMASQ_DROPIN=/etc/dnsmasq.d/rhemacast-ap.conf
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

[ "$(id -u)" = 0 ] || { echo "run as root: sudo $0 on|off" >&2; exit 1; }

# Post-drop output goes to a persistent trace (SSH is dead past
# `netplan apply`, so terminal output would vanish). Pre-drop output stays
# on the terminal AND is tee'd here — never exec-redirect from the top:
# that hid everything, including the wifi payload.
LOG=/var/log/rhemacast-ap.log
echo "=== $(date -Is) ap.sh $MODE" | tee -a "$LOG" >/dev/null

ap_on() {
    # Packages (hostapd, dnsmasq) come from setup-pi.sh — AP toggle only.
    # 1. Free the radio: stash the wifi-client config so netplan stops
    #    netplan-wpa@wlan0. Kept verbatim for a clean revert.
    if [ -f "$WIFI_YAML" ]; then
        mv "$WIFI_YAML" "$WIFI_BAK"
        echo "stashed wifi-client config -> $WIFI_BAK"
    fi
    # 2. Static AP address via netplan (same manager as before).
    # NOTE: this must be an `ethernets` entry, not `wifis` — netplan rejects
    # a wifis device with no access-points, and ethernets only sets L3,
    # leaving the radio free for hostapd (no wpa_supplicant is started).
    # Mode 0600: netplan refuses files accessible by others.
    cat > "$AP_YAML" <<'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    wlan0:
      dhcp4: false
      dhcp6: false
      addresses: [192.168.4.1/24]
EOF
    chmod 600 "$AP_YAML"
    # NOTE: `netplan apply` runs at the END (see below) — it drops SSH.
    # 3. hostapd config: install the example only when there is no config
    # yet (never overwrite an operator-edited one).
    if [ ! -f "$HOSTAPD_CONF" ]; then
        if [ -f "$SCRIPT_DIR/hostapd.conf.example" ]; then
            install -m644 "$SCRIPT_DIR/hostapd.conf.example" "$HOSTAPD_CONF"
            echo "installed $HOSTAPD_CONF from example (edit ssid/country_code!)"
        else
            echo "ERROR: no $HOSTAPD_CONF and no example alongside; copy one into place" >&2
            exit 1
        fi
    else
        echo "keeping existing $HOSTAPD_CONF"
    fi
    # WPA password: generate once (alphanumeric => QR-safe, no escaping),
    # keep across re-runs so already-printed codes stay valid.
    if ! grep -qE '^wpa_passphrase=' "$HOSTAPD_CONF"; then
        # NOTE: `|| true` — head closing the pipe SIGPIPEs tr, which
        # pipefail+errexit would otherwise treat as fatal (this killed
        # the very first on-site run: conf installed, nothing after it).
        AP_PASS="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16 || true)"
        sed -i '/^[#[:space:]]*wpa=/d; /^[#[:space:]]*wpa_passphrase=/d; /^[#[:space:]]*wpa_key_mgmt=/d; /^[#[:space:]]*rsn_pairwise=/d' "$HOSTAPD_CONF"
        cat >> "$HOSTAPD_CONF" <<EOF
wpa=2
wpa_passphrase=$AP_PASS
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF
        echo "generated AP password"
    fi
    # Print the payload BEFORE netplan apply: that step drops SSH (wlan0
    # leaves the LAN), so anything printed later is never seen remotely.
    AP_SSID="$(grep -E '^ssid=' "$HOSTAPD_CONF" | cut -d= -f2-)"
    AP_PW="$(grep -E '^wpa_passphrase=' "$HOSTAPD_CONF" | cut -d= -f2-)"
    esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/;/\\;/g; s/,/\\,/g; s/:/\\:/g; s/"/\\"/g'; }
    { echo "feed this to your QR generator:";
      echo "WIFI:T:WPA;S:$(esc "$AP_SSID");P:$(esc "$AP_PW");;";
      echo "app deep-link (QR this to tune+play):";
      echo "rhemacast://listen?ip=192.168.4.1"; } | tee -a "$LOG"
    # Debian starts hostapd with no config unless DAEMON_CONF is set.
    if grep -q '^#\?DAEMON_CONF=' /etc/default/hostapd 2>/dev/null; then
        sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
    else
        echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' >> /etc/default/hostapd
    fi
    # 4. DHCP for listeners (drop-in; ensure the conf-dir is active).
    cat > "$DNSMASQ_DROPIN" <<'EOF'
interface=wlan0
bind-dynamic
dhcp-range=192.168.4.10,192.168.4.100,255.255.255.0,24h
EOF
    grep -q '^conf-dir=/etc/dnsmasq.d' /etc/dnsmasq.conf 2>/dev/null \
        || echo 'conf-dir=/etc/dnsmasq.d/,*.conf' >> /etc/dnsmasq.conf
    # Address switch LAST: wlan0 leaves the LAN here and takes this SSH
    # session with it (trap HUP keeps the script running). Password payload
    # was already printed above, so nothing after this point is seen remotely.
    netplan apply
    # Past the SSH drop: log only from here on.
    exec >>"$LOG" 2>&1
    # Debian ships hostapd masked; enable would silently do nothing.
    systemctl unmask hostapd >/dev/null 2>&1 || true
    systemctl enable --now hostapd dnsmasq
    # Fail LOUD if hostapd didn't survive (past the SSH drop nobody sees
    # this live — it lands in the ap log). Revert with: $0 off
    sleep 3
    if ! systemctl is-active -q hostapd; then
        echo "ERROR: hostapd failed to start — auto-reverting to wifi client" >&2
        journalctl -u hostapd -n 10 --no-pager >&2 || true
        ap_off
        exit 1
    fi
    echo "AP up: ssid from $HOSTAPD_CONF, Pi at 192.168.4.1 (join it; ssh stu@192.168.4.1)"
}

ap_off() {
    systemctl disable --now hostapd dnsmasq || true
    rm -f "$AP_YAML" "$DNSMASQ_DROPIN"
    if [ -f "$WIFI_BAK" ]; then
        mv "$WIFI_BAK" "$WIFI_YAML"
        echo "restored wifi-client config"
    fi
    netplan apply
    # Session over AP drops here too when reverting remotely; log the rest.
    exec >>"$LOG" 2>&1
    echo "back to wifi client"
}

case "$MODE" in
    on) ap_on ;;
    off) ap_off ;;
    *) echo "usage: sudo $0 on|off" >&2; exit 1 ;;
esac
