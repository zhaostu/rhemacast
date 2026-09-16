# rhemacast server — `rhemacastd` single binary (Rust)

One binary does everything: mic/tone → Opus → WebRTC fan-out + admin API + web UI.
No MediaMTX, no GStreamer, no Python. Fully offline.

```
[USB mic | --tone] -> cpal -> Opus 48kHz mono 32kbps -> RTP packets
    +-> WebRTC (WHEP POST /whep)  — phones + browsers, one PeerConnection each
    +-> UDP (optional --udp-out)  — future ESP32 receivers
[HTTP :8080]  /whep  /api/status|level|logs  /api/publish/{start,stop,restart}
              /listen.html  /admin.html  (embedded at compile time from web/)
```

## Local test (no mic, no Pi, no Docker)

```sh
cargo run -- --tone 440
# open http://127.0.0.1:8080/listen.html  → Play, hear the tone via WebRTC
# open http://127.0.0.1:8080/admin.html   → LIVE dot, mic meter, listeners
curl http://127.0.0.1:8080/api/status
```

Other useful flags: `--list-devices`, `--device <name-match>`, `--bitrate 24000`,
`--port 8080`, `--udp-out 192.168.4.50:5005`, `ADMIN_TOKEN=secret` env for `/api/*` auth.

## On-mic run (laptop or Pi)

```sh
cargo run --release
# or: ./target/release/rhemacastd
```

## ARM64 build for Orange Pi 3 LTS / Pi 3B/4 (from this laptop, no Docker)

All three boards are ARM64, so one target covers them (needs a 64-bit OS on the Pi side).
Needs `aarch64-linux-gnu-gcc` in PATH (Arch: `sudo pacman -S aarch64-linux-gnu-gcc`):

```sh
./server/build-aarch64.sh
```

This assembles a tiny ARM64 sysroot from Debian packages (`mk-sysroot.sh`,
`server/.sysroot-aarch64/`, ~5MB, gitignored — ALSA + Opus headers/libs),
then `cargo build --release --target aarch64-unknown-linux-gnu`.
Result: `server/target/aarch64-unknown-linux-gnu/release/rhemacastd`
(~14MB, needs `libasound2` + `libopus0` on the board — both preinstalled on
Raspberry Pi OS/Armbian; if minimal: `sudo apt install -y libasound2 libopus0`).

Deploy:

```sh
scp server/target/aarch64-unknown-linux-gnu/release/rhemacastd pi@<pi-ip>:/tmp/
ssh pi@<pi-ip> 'sudo install -m755 /tmp/rhemacastd /usr/local/bin/ &&
  sudo install -m644 server/rhemacastd.service /etc/systemd/system/ &&
  sudo systemctl enable --now rhemacastd'
```

## Native Pi build (fallback, no cross toolchain)

```sh
# one-time deps on the Pi:
sudo apt install -y build-essential pkg-config autoconf automake libtool \
  libasound2-dev libopus-dev curl
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source ~/.cargo/env

# copy this repo (or just server/) to the Pi, then:
cd server
cargo build --release   # ~10-20 min on a Pi 4/5, one time
sudo install -m755 target/release/rhemacastd /usr/local/bin/
sudo install -m644 rhemacastd.service /etc/systemd/system/
sudo systemctl enable --now rhemacastd
```
Pi-as-AP setup is unchanged: see `ap-setup.md` / `hostapd.conf.example`.

## Files

| File | Purpose |
|---|---|
| `Cargo.toml` / `src/` | the whole server: `main.rs` CLI, `audio.rs` capture+Opus, `hub.rs` WebRTC+HTTP |
| `rhemacastd.service` | systemd unit (single service) |
| `web/listen.html` / `web/admin.html` | embedded UI (single source of truth, also served) |
| `ap-setup.md` / `hostapd.conf.example` | Pi-as-AP docs (unchanged) |

## Troubleshooting

- `arecord -l` shows nothing → reseat USB mic; `./rhemacastd --list-devices` lists what cpal sees.
- Silence → check `--device` match; test locally first (`arecord -D ... test.wav`).
- Browser stuck connecting → phones/laptops need a reachable ICE host candidate:
  run on the Pi's LAN IP / AP IP (`webrtc` gathers all interface addresses; no STUN needed offline).
- Firewall → allow TCP 8080 (HTTP+WHEP) and UDP 1024-65535 (ICE/SRTP); narrow later if needed.
- Logs → `journalctl -u rhemacastd -f`, or `GET /api/logs` in a browser.
- Latency/clap test: clap into the mic, time it on a phone — expect ~0.3–0.8 s.
