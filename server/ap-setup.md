# AP setup — Pi as offline WiFi AP (192.168.4.1/24)

Phones connect to the Pi's hotspot; no internet needed.

## 1. Install + configure

```sh
sudo apt install -y hostapd dnsmasq
sudo cp server/hostapd.conf.example /etc/hostapd/hostapd.conf
# edit SSID/country_code inside; add a wpa_passphrase for private events
```

`/etc/dnsmasq.conf` (minimal):

```conf
interface=wlan0
dhcp-range=192.168.4.10,192.168.4.100,255.255.255.0,24h
```

Static IP + enable AP (Bookworm uses NetworkManager — set AP via
`nmtui` or `nmcli` instead of editing dhcpcd.conf; on legacy images add
`static ip_address=192.168.4.1/24` for wlan0, then unmask/start hostapd).

## 2. Match MediaMTX

`webrtcAdditionalHosts` in `/etc/mediamtx.yml` must contain `192.168.4.1`
(already the default) or phones will stall at ICE "connecting".

## 3. Notes

- 5 GHz: Pi 3B+/4/5 support it (`hw_mode=a`, channel 36/40/44/48), but
  range is shorter; prefer 2.4 GHz for crowds/outdoors. Set `country_code`
  correctly or 5 GHz won't come up.
- x86 mini-PC caveat: Intel AX200/AX210 (iwlwifi) **cannot do AP mode**
  reliably — hostapd will fail. Use a USB dongle with AP support instead.
- Suggested dongle: MT7612U-based (e.g. ALFA AWUS036ACM) — works on
  Pi (Armbian/RPiOS) and x86, supports AP + 5 GHz, in-kernel `mt76x2u`
  driver, no firmware hassle.
- Firewall: allow TCP 8554 (RTSP), TCP 8889 (WebRTC/WHEP), TCP+UDP 8189
  (ICE), UDP 8000-8010 (RTP/RTCP).
