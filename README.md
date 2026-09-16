# rhemacast — near-realtime translator broadcast (mic -> Pi -> phones)

Audio-only live broadcast for English->Chinese translation. Translator speaks into a mic on a Linux box; 5-20 phones listen with <500ms latency, fully offline.

Stack: single Rust binary **`rhemacastd`** (`ALSA mic -> Opus 48kHz mono 32kbps -> WebRTC/WHEP fan-out`), unicast (not IP multicast — WiFi multicast is lossy). Optional raw `RTP/Opus` UDP out for future ESP32 receivers. Built natively per board (`x86_64` laptop, `arm64`/`armv7` Pi).

## Layout

- `server/` — Rust crate (`Cargo.toml` + `src/`), systemd unit, AP setup. See `server/README.md`.
- `server/web/listen.html` — browser test player (embedded in binary): `http://<pi-ip>:8080/listen.html`.
- `server/web/admin.html` — translator dashboard (embedded): `http://<pi-ip>:8080/admin.html` (LIVE dot, mic meter, listeners, start/stop, logs).
- `ios/` — SwiftUI + WebRTC audio-only listener (`192.168.4.1` default). See `ios/README.md`.
- `android/` — Kotlin + Compose + libwebrtc listener + foreground service. See `android/README.md`.

Both phone apps have a `Translator controls` link opening the admin page for the entered IP.

## Quickstart

1. Local test (no hardware): `cd server && cargo run -- --tone 440`, open `http://127.0.0.1:8080/listen.html`.
2. Pi: `./server/build-aarch64.sh`, scp binary over, `sudo systemctl enable --now rhemacastd`.
3. On phones: same LAN/AP, open app, enter Pi IP, Connect.

Ports: `8080/TCP` (WHEP + API + web), `UDP` ephemeral (ICE/SRTP).
