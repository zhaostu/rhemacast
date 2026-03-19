# Rhemacast

Real-time voice broadcasting for on-site translation. A Linux server captures a microphone and streams audio to Flutter mobile apps (Android + iOS) via WebRTC over a local WiFi network. Audience members hear the translation through their phone headphones.

## Architecture

```
sounddevice (mic capture)
  → asyncio queue
    → BroadcastManager (fan-out)
      → per-peer asyncio.Queue
        → MicrophoneAudioTrack.recv()
          → aiortc → Opus/UDP → phone
```

**Signaling**: Flutter opens a WebSocket, sends an SDP offer, receives an answer, and ICE negotiation completes — all on LAN with no STUN/TURN required.

**Reconnect**: The Flutter app reconnects automatically with exponential backoff (1s → 2s → 4s → 8s → 16s → 30s) if the connection drops.

## Stack

| Component | Library | Version |
|---|---|---|
| Python audio capture | `sounddevice` | latest |
| Python WebRTC | `aiortc` | 1.14.0 |
| Python HTTP/WS | `aiohttp` | 3.13.3 |
| Flutter WebRTC | `flutter_webrtc` | ^0.9.0 |
| Flutter WebSocket | `web_socket_channel` | ^2.4.0 |
| Flutter audio route | `audio_session` | ^0.1.21 |

Audio: 48 kHz, mono, 16-bit PCM, 20 ms frames (960 samples), Opus codec.

## Directory Structure

```
rhemacast/
├── server/
│   ├── server.py          # Entry point: CLI args, sounddevice capture, aiohttp app
│   ├── audio_track.py     # MicrophoneAudioTrack — wraps per-peer queue as aiortc AudioStreamTrack
│   ├── broadcast.py       # BroadcastManager — fan-out audio to all connected peers
│   ├── signaling.py       # WebSocket handler — SDP offer/answer, peer lifecycle
│   ├── web_ui.py          # Debug UI handler + stats WebSocket
│   ├── static/index.html  # Browser debug UI: peer count, streaming status, VU meter
│   ├── requirements.txt
│   ├── test_load.py       # Load test: N concurrent aiortc clients
│   └── tests/
├── mobile/rhemacast/
│   ├── lib/
│   │   ├── main.dart
│   │   ├── webrtc_client.dart   # RTCPeerConnection, signaling, reconnect logic
│   │   ├── audio_route.dart     # Headphone detection via audio_session
│   │   └── ui/
│   │       ├── home_screen.dart
│   │       └── status_widget.dart
│   └── test/
└── test/
    ├── browser_client.html      # Standalone JS WebRTC client for server validation
    ├── android_test_checklist.md
    └── ios_test_checklist.md
```

## Running the Server

```bash
cd server
pip install -r requirements.txt
python server.py
```

Options:
- `--port 8080` — port to listen on (default: 8080)
- `--host 0.0.0.0` — host to bind (default: 0.0.0.0)
- `--device N` — sounddevice input device index (default: system default)

The debug UI is available at `http://localhost:8080/` and shows connected peer count, streaming status, and a live VU meter.

### Network Setup

The server expects a static IP of `192.168.4.1` (a dedicated WiFi access point). The Flutter app and browser client both hardcode this address. To use a different IP, update:

- `mobile/rhemacast/lib/webrtc_client.dart` — `_serverWsUrl`
- `test/browser_client.html` — the WebSocket URL constant

## Running the Mobile App

```bash
cd mobile/rhemacast
flutter pub get
flutter run          # runs on connected device or emulator
```

The app connects automatically on launch. If headphones are not detected, a warning banner is shown.

## Testing

### Python (server)

```bash
cd server
python -m pytest tests/ -v
```

### Load test (requires a running server)

```bash
cd server
python test_load.py --clients 5 --duration 30
```

### Flutter

```bash
cd mobile/rhemacast
flutter test
flutter analyze
```

## Building for Release

See [`mobile/rhemacast/BUILD.md`](mobile/rhemacast/BUILD.md) for full build commands.

**Android release** — requires `android/key.properties` (see `android/key.properties.template`):
```bash
flutter build apk --release
```

**iOS release** — requires Apple Developer account, provisioning profile, and Xcode:
```bash
flutter build ipa
```

## Manual Integration Tests

- Android: [`test/android_test_checklist.md`](test/android_test_checklist.md)
- iOS: [`test/ios_test_checklist.md`](test/ios_test_checklist.md)
- Browser: open `test/browser_client.html` in Chrome while the server is running
