#!/usr/bin/env bash
# Runs ON the Pi as root: installs the staged /tmp files and starts the service.
# Staged by server/install.sh. Usage: sudo bash /tmp/setup-pi.sh
set -euo pipefail

[ "$(id -u)" = 0 ] || { echo "run as root: sudo bash $0" >&2; exit 1; }

# runtime lib (ALSA ships with the image; Opus does not):
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libopus0

install -m755 /tmp/rhemacastd /usr/local/bin/rhemacastd
install -m644 /tmp/rhemacastd.service /etc/systemd/system/rhemacastd.service
# persist the AP toggle (/tmp is tmpfs — this must survive reboot):
install -m755 /tmp/ap.sh /usr/local/sbin/rhemacast-ap
install -m644 /tmp/hostapd.conf.example /usr/local/sbin/hostapd.conf.example
systemctl daemon-reload
# enable = auto-start on power-on (unit also has Restart=always):
systemctl enable --now rhemacastd

echo "== status:"
systemctl is-active rhemacastd
echo "== capture devices (plug in the USB mic first):"
/usr/local/bin/rhemacastd --list-devices || true
echo "== service is up on the LAN — test it before switching networks:"
echo "   curl http://127.0.0.1:8080/api/status   (or from your laptop: http://$(hostname -I | awk '{print $1}'):8080/listen.html)"
echo
read -r -p "Switch to offline AP mode now? SSH will drop; rejoin via the rhemacast AP at 192.168.4.1 [y/N] " ans || ans=N
if [[ "$ans" =~ ^[Yy]$ ]]; then
    /usr/local/sbin/rhemacast-ap on
else
    echo "staying in LAN client mode (later: sudo rhemacast-ap on)"
fi
