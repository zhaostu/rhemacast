# AP setup — Pi as offline WiFi AP (192.168.4.1/24)

Phones connect to the Pi's hotspot; no internet needed.

Stack matches what Armbian already runs: **netplan → systemd-networkd**
for the address, **hostapd** for AP mode, **dnsmasq** for DHCP.
No NetworkManager involved (it isn't installed on this image).

## 1. Check the radio can do AP mode

```sh
sudo apt install -y iw
iw list | grep -A8 'Supported interface modes'
# must list AP. Orange Pi 3 LTS uses a Spreadtrum/Unisoc chip
# (sprdwl_ng) — AP support there is flaky; if AP is missing or
# hostapd fails below, run the Pi as a LAN client instead (it already
# works: phones reach rhemacastd at its 192.168.99.x address).
```

## 2. Switch on (reversible)

```sh
# copy server/ to the Pi (or just ap.sh + hostapd.conf.example), then:
sudo ./ap.sh on
# edit /etc/hostapd/hostapd.conf first if you want a custom
# ssid/country_code (re-run ap.sh on afterwards).
```

What it does: installs hostapd+dnsmasq, stashes
`/etc/netplan/30-wifis-dhcp.yaml` (so netplan stops `netplan-wpa@wlan0`
and frees the radio), applies a static `192.168.4.1/24` via netplan,
sets Debian's `DAEMON_CONF`, unmasks + enables hostapd and dnsmasq.

Back to wifi client: `sudo ./ap.sh off` (restores the stashed config).
Once installed, the toggle lives at `/usr/local/sbin/rhemacast-ap`
(`setup-pi.sh` puts it there — `/tmp` is tmpfs and does not survive reboot).

### Lost control?

Rebooting does **not** recover you: AP mode persists by design (enabled
services + netplan file in `/etc`), the Pi just comes back as a hotspot.
Instead, in order of convenience:

1. Join the `rhemacast` AP from your laptop/phone, `ssh stu@192.168.4.1`,
   run `sudo rhemacast-ap off` — Pi rejoins home wifi, ssh back at its
   LAN address.
2. AP itself broken (can't join): HDMI + USB keyboard, log in, same command.
   Last resort: UART serial console (115200 8N1 on the debug header).

## 2. ICE reachability

Phones stall at ICE "connecting" unless they can reach the Pi. When the
AP is up at `192.168.4.1`, `rhemacastd` gathers that address as a host
candidate automatically — no extra config (no STUN needed offline).

## 3. Notes

- 5 GHz: Pi 3B+/4/5 support it (`hw_mode=a`, channel 36/40/44/48), but
  range is shorter; prefer 2.4 GHz for crowds/outdoors. Set `country_code`
  correctly or 5 GHz won't come up.
- x86 mini-PC caveat: Intel AX200/AX210 (iwlwifi) **cannot do AP mode**
  reliably — hostapd will fail. Use a USB dongle with AP support instead.
- Suggested dongle: MT7612U-based (e.g. ALFA AWUS036ACM) — works on
  Pi (Armbian/RPiOS) and x86, supports AP + 5 GHz, in-kernel `mt76x2u`
  driver, no firmware hassle.
- Firewall: allow TCP 8080 (HTTP+WHEP+API+web) and UDP 1024-65535 (ICE/SRTP).
