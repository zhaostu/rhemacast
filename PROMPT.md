# Rhemacast — Self-Guided Implementation Loop

## LOOP INSTRUCTIONS
Find the FIRST unchecked task `- [ ]` in the Tasks section below.
Implement it completely using the tools available to you.
As part of the implementation, write unit tests for the code you produce (see each task for specific test requirements).
Run the tests and verify they ALL PASS before proceeding.
If tests fail, fix the code (not the tests) until they pass.
When done and tests are green, change `- [ ]` to `- [x]` for that task only.
Then run `git add -A && git commit -m "Task N: <short description>"` where N is the task number and the description is a concise summary of what was implemented.
Then STOP — do not implement any further tasks.

---

## Project Context

### Purpose
Real-time voice broadcasting for on-site translation. A Linux server captures a microphone and streams to Flutter mobile apps (Android + iOS) via WebRTC over a local WiFi network. Audience members hear the translation through their phone's headphones.

### Stack & Pinned Versions
| Component | Library | Version |
|---|---|---|
| Python audio capture | `sounddevice` | latest stable |
| Python WebRTC | `aiortc` | 1.14.0 |
| Python HTTP/WS | `aiohttp` | 3.13.3 |
| Python AV | `av` | latest compatible with aiortc 1.14.0 |
| Flutter WebRTC | `flutter_webrtc` | ^0.9.0 |
| Flutter WS | `web_socket_channel` | ^2.4.0 |
| Flutter audio route | `audio_session` | ^0.1.21 |
| Flutter provider | `provider` | ^6.1.0 |
| Python test runner | `pytest` | latest stable |
| Python async tests | `pytest-asyncio` | latest stable |

### Audio Parameters
- Sample rate: 48000 Hz
- Channels: 1 (mono)
- Format: int16 (signed 16-bit PCM)
- Frame size: 960 samples = 20ms at 48kHz (WebRTC/Opus native frame size)
- Codec: Opus (aiortc default for AudioStreamTrack)

### Network
- Server static IP: `192.168.4.1`
- Port: `8080`
- WebSocket signaling: `ws://192.168.4.1:8080/ws`
- Debug UI: `http://192.168.4.1:8080/`
- ICE: No STUN/TURN — local WiFi only, host candidates only

### Key Architectural Patterns

**Fan-out broadcast**:
```
sounddevice.InputStream callback
  → loop.call_soon_threadsafe → asyncio queue (broadcast_queue)
    → BroadcastManager.distribute()
      → per-peer asyncio.Queue (one per connected RTCPeerConnection)
        → MicrophoneAudioTrack.recv() awaits its peer's queue
          → returns av.AudioFrame to aiortc → encodes Opus → UDP to phone
```

**Signaling flow**:
1. Flutter opens WebSocket to `ws://192.168.4.1:8080/ws`
2. Flutter creates RTCPeerConnection (no STUN servers), adds remote track handler
3. Flutter creates offer SDP, sends JSON: `{"type": "offer", "sdp": "..."}`
4. Server receives offer, creates RTCPeerConnection, adds MicrophoneAudioTrack
5. Server sets remote description, creates answer, sets local description
6. Server sends JSON: `{"type": "answer", "sdp": "..."}`
7. Flutter sets remote description → ICE negotiation → UDP media flows
8. Flutter `onTrack` fires → audio plays through device

**Flutter reconnect**: Exponential backoff (1s, 2s, 4s, 8s, max 30s) triggered when `RTCPeerConnection.connectionState` becomes `failed` or `disconnected`. Dispose old PC, create new one, re-run signaling flow.

**Headphone detection**: `audio_session` package exposes route change events. If no wired/BT headphones detected on connection, show warning banner: "Please connect headphones to avoid disturbing others."

---

## Directory Structure
```
rhemacast/
├── PROMPT.md                          ← this file
├── server/
│   ├── requirements.txt
│   ├── server.py                      ← entry point: asyncio app, CLI args
│   ├── audio_track.py                 ← MicrophoneAudioTrack(AudioStreamTrack)
│   ├── broadcast.py                   ← BroadcastManager fan-out
│   ├── signaling.py                   ← WS handler, offer/answer, PC lifecycle
│   ├── web_ui.py                      ← aiohttp routes, stats endpoint
│   ├── static/
│   │   └── index.html                 ← debug UI: connections, VU meter
│   └── tests/
│       ├── __init__.py
│       ├── test_scaffolding.py
│       ├── test_audio_track.py
│       ├── test_broadcast.py
│       ├── test_signaling.py
│       ├── test_server.py
│       ├── test_web_ui.py
│       └── test_browser_client.py
├── mobile/
│   └── rhemacast/                     ← Flutter project root
│       ├── pubspec.yaml
│       ├── android/
│       │   └── app/src/main/
│       │       └── AndroidManifest.xml
│       ├── ios/
│       │   └── Runner/
│       │       └── Info.plist
│       ├── lib/
│       │   ├── main.dart
│       │   ├── webrtc_client.dart     ← RTCPeerConnection + signaling + reconnect
│       │   ├── audio_route.dart       ← headphone detection via audio_session
│       │   └── ui/
│       │       ├── home_screen.dart
│       │       └── status_widget.dart
│       └── test/
│           ├── webrtc_client_test.dart
│           ├── audio_route_test.dart
│           ├── home_screen_test.dart
│           └── status_widget_test.dart
└── test/
    └── browser_client.html            ← standalone JS WebRTC client for server validation
```

---

## File Responsibilities

### server/requirements.txt
```
aiortc==1.14.0
aiohttp==3.13.3
sounddevice
av
numpy
pytest
pytest-asyncio
aiohttp[test]
```

### server/audio_track.py
- Class `MicrophoneAudioTrack(AudioStreamTrack)` from `aiortc`
- `kind = "audio"`
- Constructor takes a per-peer `asyncio.Queue`
- `async def recv(self)` — awaits the queue, gets raw bytes (int16 mono 960 samples), creates `av.AudioFrame`, sets `pts` and `time_base = fractions.Fraction(1, 48000)`, increments pts by 960 each call, returns frame
- Must handle `av.AudioFrame.from_ndarray(array, format='s16', layout='mono')` and set `sample_rate = 48000`

### server/broadcast.py
- Class `BroadcastManager`
- `self._peers: dict[str, asyncio.Queue]` — keyed by peer_id
- `def add_peer(peer_id, queue)` — register a peer's queue
- `def remove_peer(peer_id)` — unregister
- `async def distribute(data: bytes)` — put data into all peer queues (non-blocking: use `put_nowait`, catch `QueueFull` silently to avoid blocking on slow peers)

### server/signaling.py
- `async def ws_handler(request)` — aiohttp WebSocket handler
- Creates `RTCPeerConnection()` with no ICE servers
- Generates unique `peer_id = str(uuid.uuid4())`
- Creates `asyncio.Queue(maxsize=10)` for this peer
- Registers queue with `BroadcastManager`
- Creates `MicrophoneAudioTrack(peer_queue)`, adds to PC with `pc.addTrack(track)`
- Receives JSON offer, sets remote description, creates answer, sends JSON answer
- Monitors `pc.connectionState` — on `failed`/`closed` cleans up peer from BroadcastManager
- Keeps WS open until peer disconnects

### server/web_ui.py
- `async def index_handler(request)` — serves `static/index.html`
- `async def ws_ui_handler(request)` — WebSocket pushing stats JSON every second:
  `{"peer_count": N, "streaming": true/false, "vu_db": float}`
- VU meter: compute dBFS from recent audio frames stored in a rolling buffer on BroadcastManager

### server/server.py
- `argparse` CLI: `--device` (sounddevice device index, default None = system default), `--host`, `--port`
- Creates `BroadcastManager` singleton
- `sounddevice.InputStream` callback: receives numpy int16 array → converts to bytes → `loop.call_soon_threadsafe(broadcast_queue.put_nowait, data)`
- asyncio main loop: start aiohttp app + sounddevice stream together
- Routes: `GET /` → `index_handler`, `GET /ws` → `ws_handler`, `GET /ws-ui` → `ws_ui_handler`

### server/static/index.html
- Single-page HTML/JS debug UI
- Connects to `/ws-ui` WebSocket
- Displays: "Connected peers: N", "Streaming: yes/no", VU meter (canvas bar)
- Auto-reconnects to `/ws-ui` if disconnected

### mobile/rhemacast/lib/webrtc_client.dart
- Class `WebRTCClient` with `ChangeNotifier`
- State enum: `idle`, `connecting`, `connected`, `reconnecting`, `error`
- `RTCPeerConnection` created with empty ICE servers: `{'iceServers': []}`
- Mandatory constraints: `{'audio': true, 'video': false}`
- `connect()`: create PC → create offer → send via WS → receive answer → setRemoteDescription
- `pc.onConnectionState`: if `failed`/`disconnected` → start reconnect loop
- Reconnect: exponential backoff (1s, 2s, 4s, 8s, 16s, 30s max), call `dispose()` then `connect()`
- `onTrack`: receive remote audio track (aiortc sends audio), set on `RTCVideoRenderer` — actually for audio just confirm track received; flutter_webrtc handles audio playback automatically via native path
- Expose `connectionState` string, `peerCount` (from server WS-UI), `errorMessage`

### mobile/rhemacast/lib/audio_route.dart
- Class `AudioRouteDetector` with `ChangeNotifier`
- Uses `audio_session` package
- `AudioSession.instance` → `configure(AudioSessionConfiguration.speech())`
- Listen to `session.devicesChangedEventStream` or check `session.isOtherAppPlaying`
- Actually: use `AudioSession` to detect if headphones are connected via platform-specific checks
- Expose `bool headphonesConnected` — true if wired or BT headphones are active output device
- On iOS: check `AVAudioSession.currentRoute.outputs` for headphone port types
- On Android: use `AudioManager.isWiredHeadsetOn` or `AudioManager.isBluetoothA2dpOn`
- `audio_session` abstracts this — listen to route changes

### mobile/rhemacast/lib/ui/home_screen.dart
- `StatefulWidget` using `WebRTCClient` and `AudioRouteDetector` via `Provider`
- On `initState`: call `webRTCClient.connect()`
- Shows `StatusWidget` with current connection state
- Shows warning `Banner` or `Card` if `!audioRouteDetector.headphonesConnected`: "Connect headphones to avoid disturbing others"
- Shows peer count from server (fetched via WS-UI connection in `WebRTCClient`)

### mobile/rhemacast/lib/ui/status_widget.dart
- Displays colored indicator: green=connected, yellow=reconnecting, red=error, grey=idle
- Shows state label and optional error message

### mobile/rhemacast/lib/main.dart
- `MultiProvider` with `WebRTCClient` and `AudioRouteDetector`
- `HomeScreen` as home

### test/browser_client.html
- Pure HTML/JS (no build tools)
- Creates `RTCPeerConnection({iceServers: []})`
- Adds `addTransceiver('audio', {direction: 'recvonly'})`
- Creates offer, sends to server via WebSocket, receives answer
- Sets remote description → audio plays in browser
- Shows connection state, error log

---

## Tasks

- [x] Task 1: Scaffolding
  - Create `server/` directory with empty stub files: `requirements.txt`, `server.py`, `audio_track.py`, `broadcast.py`, `signaling.py`, `web_ui.py`, `static/index.html`
  - Create `server/tests/__init__.py` (empty)
  - Create `test/` directory with empty `browser_client.html`
  - Create `mobile/` directory
  - Run `flutter create rhemacast` inside `mobile/` to scaffold the Flutter project (use `--org com.rhemacast` and `--project-name rhemacast`)
  - If `flutter` is not available, create the Flutter project structure manually: `pubspec.yaml`, `lib/main.dart`, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`
  - Write `server/requirements.txt` with pinned deps: `aiortc==1.14.0`, `aiohttp==3.13.3`, `sounddevice`, `av`, `numpy`, `pytest`, `pytest-asyncio`, `aiohttp[test]`
  - **Tests** — write `server/tests/test_scaffolding.py`:
    - Test that all required server files exist: `server.py`, `audio_track.py`, `broadcast.py`, `signaling.py`, `web_ui.py`, `static/index.html`
    - Test that `server/requirements.txt` contains `aiortc==1.14.0` and `aiohttp==3.13.3`
    - Test that `mobile/rhemacast/` directory exists
    - Test that `test/browser_client.html` exists
  - **Run tests**: `cd server && python -m pytest tests/test_scaffolding.py -v` — must pass before committing

- [x] Task 2: MicrophoneAudioTrack
  - Implement `server/audio_track.py` fully
  - Import: `asyncio`, `fractions`, `numpy`, `av`, `aiortc.mediastreams.AudioStreamTrack`
  - Class `MicrophoneAudioTrack(AudioStreamTrack)`:
    - `kind = "audio"`
    - `__init__(self, queue: asyncio.Queue)`: store queue, init `_pts = 0`, `_sample_rate = 48000`, `_samples_per_frame = 960`
    - `async def recv(self) -> av.AudioFrame`:
      - `data = await self._queue.get()` — blocks until audio available
      - Convert bytes to numpy int16 array: `np.frombuffer(data, dtype=np.int16)`
      - Reshape to `(1, 960)` (channels, samples)
      - `frame = av.AudioFrame.from_ndarray(array, format='s16', layout='mono')`
      - `frame.sample_rate = 48000`
      - `frame.pts = self._pts`
      - `frame.time_base = fractions.Fraction(1, 48000)`
      - `self._pts += 960`
      - `return frame`
  - **Tests** — write `server/tests/test_audio_track.py` using `pytest-asyncio`:
    - Test `kind == "audio"`
    - Test first `recv()`: put 960 int16 samples (1920 bytes) into queue, call recv(), assert `frame.pts == 0`, `frame.sample_rate == 48000`, `frame.time_base == fractions.Fraction(1, 48000)`, `frame.format.name == 's16'`
    - Test pts increments: call recv() twice, assert second frame pts == 960
    - Test frame shape: assert `frame.to_ndarray().shape == (1, 960)`
    - Test `recv()` blocks until data is available (put data after a short delay using asyncio.create_task)
  - **Run tests**: `cd server && python -m pytest tests/test_audio_track.py -v` — must pass before committing

- [x] Task 3: BroadcastManager + sounddevice capture
  - Implement `server/broadcast.py` fully:
    - Class `BroadcastManager`:
      - `__init__`: `self._peers = {}` (dict[str, asyncio.Queue]), `self._recent_frames = collections.deque(maxlen=50)`, `self.streaming = False`
      - `add_peer(peer_id: str, queue: asyncio.Queue)`: add to dict
      - `remove_peer(peer_id: str)`: remove from dict
      - `async def distribute(self, data: bytes)`: iterate peers, call `queue.put_nowait(data)` wrapped in try/except `asyncio.QueueFull`; store data in `_recent_frames`; set `self.streaming = True` if data
      - `def get_vu_db(self) -> float`: compute dBFS from recent frames — convert bytes to numpy int16, compute RMS, convert to dB: `20 * log10(rms / 32768)`, return -96.0 if silent
  - Update `server/server.py` with sounddevice capture:
    - At module level, create `broadcast_manager = BroadcastManager()`
    - `setup_audio_capture(loop, device=None)`:
      - Creates `asyncio.Queue(maxsize=100)` as `broadcast_queue`
      - Defines `audio_callback(indata, frames, time, status)`: converts `indata` to int16 bytes, calls `loop.call_soon_threadsafe(broadcast_queue.put_nowait, data)`
      - Creates `sounddevice.InputStream(samplerate=48000, channels=1, dtype='int16', blocksize=960, callback=audio_callback, device=device)`
      - Returns stream and an async task that reads from `broadcast_queue` and calls `await broadcast_manager.distribute(data)`
    - `async def main()`: parse args, setup audio, start aiohttp app
  - **Tests** — write `server/tests/test_broadcast.py` using `pytest-asyncio`:
    - Test `add_peer` / `remove_peer`: add 2 peers, verify dict length; remove one, verify dict length decreases
    - Test `distribute` fan-out: add 2 peers with real asyncio.Queues, call distribute(data), assert both queues have the data
    - Test `distribute` with no peers: should not raise
    - Test `QueueFull` is silently ignored: add a peer with `maxsize=1`, fill the queue, call distribute again — must not raise
    - Test `streaming` flag: starts False, becomes True after first distribute call
    - Test `get_vu_db` with silence (all-zero bytes): returns -96.0
    - Test `get_vu_db` with max amplitude (all 32767 int16): returns value close to 0.0 dBFS
    - Test `get_vu_db` with no frames yet (empty deque): returns -96.0
  - **Run tests**: `cd server && python -m pytest tests/test_broadcast.py -v` — must pass before committing

- [x] Task 4: WebSocket signaling
  - Implement `server/signaling.py` fully:
    - Imports: `asyncio`, `json`, `uuid`, `logging`, `aiohttp.web`, `aiortc` (RTCPeerConnection, RTCSessionDescription)
    - Import `BroadcastManager` from `broadcast`, `MicrophoneAudioTrack` from `audio_track`
    - `async def ws_handler(request, broadcast_manager: BroadcastManager)`:
      - Upgrade to WebSocket: `ws = aiohttp.web.WebSocketResponse(); await ws.prepare(request)`
      - `peer_id = str(uuid.uuid4())`
      - `peer_queue = asyncio.Queue(maxsize=10)`
      - `broadcast_manager.add_peer(peer_id, peer_queue)`
      - `pc = RTCPeerConnection()` — no ICE servers needed for LAN
      - `track = MicrophoneAudioTrack(peer_queue)`
      - `pc.addTrack(track)`
      - Receive first message: parse JSON, expect `{"type": "offer", "sdp": "..."}`
      - `await pc.setRemoteDescription(RTCSessionDescription(sdp=msg['sdp'], type='offer'))`
      - `answer = await pc.createAnswer()`
      - `await pc.setLocalDescription(answer)`
      - Send: `await ws.send_json({"type": "answer", "sdp": pc.localDescription.sdp})`
      - Keep WS open: async for loop on remaining messages (handle ICE candidates if any)
      - On WS close or error: `broadcast_manager.remove_peer(peer_id)`, `await pc.close()`
      - Wrap entire handler body in try/finally to guarantee cleanup
      - Log peer connect/disconnect with peer_id
  - **Tests** — write `server/tests/test_signaling.py` using `pytest-asyncio` and `aiohttp.test_utils`:
    - Test peer registration: when WS connects and sends a valid offer, verify `broadcast_manager._peers` has exactly 1 entry during the connection
    - Test peer cleanup: after WS closes, verify `broadcast_manager._peers` is empty
    - Test answer response: send a synthetic SDP offer (create one with aiortc client-side RTCPeerConnection), verify the server responds with JSON containing `{"type": "answer", "sdp": ...}`
    - For SDP generation: use `aiortc.RTCPeerConnection` to create a real offer SDP for testing
    - Use `aiohttp.test_utils.TestServer` + `aiohttp.test_utils.TestClient` to run the server in-process
  - **Run tests**: `cd server && python -m pytest tests/test_signaling.py -v` — must pass before committing

- [x] Task 5: Server entry point
  - Implement `server/server.py` fully (replacing stub):
    - `argparse` with `--device` (int, default None), `--host` (default '0.0.0.0'), `--port` (int, default 8080)
    - Import and wire together: `BroadcastManager`, `ws_handler` (from signaling), `index_handler`, `ws_ui_handler` (from web_ui)
    - `app = aiohttp.web.Application()`
    - Routes: `app.router.add_get('/', index_handler)`, `add_get('/ws', ws_handler_wrapper)`, `add_get('/ws-ui', ws_ui_handler_wrapper)`, `add_static('/static', 'static/')`
    - Pass `broadcast_manager` to handlers via `app['broadcast_manager'] = broadcast_manager`
    - `def create_app(broadcast_manager=None) -> aiohttp.web.Application`: extract app factory for testability
    - Start sounddevice stream before running app
    - Graceful shutdown: stop sounddevice stream on SIGINT/SIGTERM
    - Print startup message: `"Rhemacast server starting on http://{host}:{port}"`
    - Implement `web_ui.py` basic stub: `async def index_handler` serves static/index.html, `async def ws_ui_handler` sends stats JSON every second
  - **Tests** — write `server/tests/test_server.py`:
    - Test argparse defaults: call `parse_args([])`, assert `host == '0.0.0.0'`, `port == 8080`, `device is None`
    - Test argparse overrides: call `parse_args(['--port', '9000', '--host', '127.0.0.1', '--device', '2'])`, assert correct values
    - Test app routes: call `create_app()`, assert routes include `/`, `/ws`, `/ws-ui`
    - Test `app['broadcast_manager']` is a `BroadcastManager` instance
  - **Run tests**: `cd server && python -m pytest tests/test_server.py -v` — must pass before committing

- [x] Task 6: Debug web UI
  - Implement `server/static/index.html` fully:
    - Standalone HTML page, no external dependencies (inline CSS/JS)
    - Connects to `ws://` + location.host + `/ws-ui`
    - Displays: "Rhemacast Debug" title, "Connected peers: N" counter, "Streaming: YES/NO" indicator, VU meter as `<canvas>` bar graph
    - Auto-reconnects WS every 3s if disconnected
    - VU meter: draw green bar proportional to dB value (map -60dB..0dB to 0..100%)
    - Style: dark background, clean monospace font
  - Implement `server/web_ui.py` fully:
    - `index_handler`: reads and serves `static/index.html` with content-type text/html
    - `ws_ui_handler`: upgrades to WS, every 1 second sends `{"peer_count": N, "streaming": bool, "vu_db": float}` from broadcast_manager stats
    - Handles WS disconnect gracefully
  - **Tests** — write `server/tests/test_web_ui.py` using `pytest-asyncio` and `aiohttp.test_utils`:
    - Test `index_handler`: GET `/` returns status 200, content-type `text/html`, body contains `"Rhemacast"`
    - Test `index_handler`: body contains `<canvas` (VU meter element)
    - Test `index_handler`: body contains `ws-ui` (WebSocket endpoint reference)
    - Test `ws_ui_handler`: connect via WS, receive first message within 2 seconds, parse JSON, assert keys `peer_count`, `streaming`, `vu_db` are present
    - Test `ws_ui_handler`: `peer_count` is an int, `streaming` is a bool, `vu_db` is a float
  - **Run tests**: `cd server && python -m pytest tests/test_web_ui.py -v` — must pass before committing

- [x] Task 7: Flutter setup
  - Edit `mobile/rhemacast/pubspec.yaml`:
    - Add dependencies: `flutter_webrtc: ^0.9.0`, `web_socket_channel: ^2.4.0`, `audio_session: ^0.1.21`, `provider: ^6.1.0`
    - Ensure `flutter: sdk: flutter` is present
  - Edit `mobile/rhemacast/android/app/src/main/AndroidManifest.xml`:
    - Add permissions: `INTERNET`, `RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS`, `ACCESS_NETWORK_STATE`, `BLUETOOTH`, `BLUETOOTH_CONNECT`
    - Add `android:usesCleartextTraffic="true"` to `<application>` tag (needed for ws:// on Android 9+)
  - Edit `mobile/rhemacast/ios/Runner/Info.plist`:
    - Add `NSMicrophoneUsageDescription`: "Rhemacast uses the microphone for audio translation"
    - Add `NSBluetoothAlwaysUsageDescription`: "Rhemacast uses Bluetooth for wireless headphones"
    - Add `NSBluetoothPeripheralUsageDescription`: same
  - Create `mobile/rhemacast/ios/Podfile` if it doesn't exist with appropriate Flutter iOS setup
  - Run `flutter pub get` in `mobile/rhemacast/`
  - Create stub files: `lib/webrtc_client.dart`, `lib/audio_route.dart`, `lib/ui/home_screen.dart`, `lib/ui/status_widget.dart`
  - Create `mobile/rhemacast/test/` directory with placeholder test files
  - **Tests**:
    - Run `flutter pub get` in `mobile/rhemacast/` — must succeed with exit code 0
    - Run `flutter analyze mobile/rhemacast/` — must report zero errors (warnings OK)
    - Write `server/tests/test_scaffolding.py` additions (or a separate `test_flutter_setup.py`): verify `pubspec.yaml` contains `flutter_webrtc`, `web_socket_channel`, `audio_session`, `provider`; verify `AndroidManifest.xml` contains `INTERNET` permission and `usesCleartextTraffic`; verify `Info.plist` contains `NSMicrophoneUsageDescription`
    - Run: `cd server && python -m pytest tests/test_flutter_setup.py -v`
  - **Run all tests**: `cd server && python -m pytest tests/ -v` — must pass before committing

- [x] Task 8: Flutter WebRTC client
  - Implement `mobile/rhemacast/lib/webrtc_client.dart` fully:
    - Imports: `flutter_webrtc`, `web_socket_channel`, `provider` (ChangeNotifier), `dart:convert`, `dart:async`
    - `enum ClientConnectionState { idle, connecting, connected, reconnecting, error }` (avoid clash with Flutter's `ConnectionState`)
    - Class `WebRTCClient extends ChangeNotifier`:
      - Constants: `static const _serverWsUrl = 'ws://192.168.4.1:8080/ws'`
      - Fields: `RTCPeerConnection? _pc`, `WebSocketChannel? _ws`, `ClientConnectionState state`, `String? errorMessage`, `int peerCount = 0`, `Timer? _reconnectTimer`, `int _reconnectAttempts = 0`
      - `static const List<int> _backoffSeconds = [1, 2, 4, 8, 16, 30]`
      - `Future<void> connect()`:
        - Cancel any pending reconnect timer: `_reconnectTimer?.cancel()`
        - Set state to `connecting`, call `notifyListeners()`
        - `_pc = await createPeerConnection({'iceServers': []}, {'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': false}})`
        - `_pc!.onConnectionState = (state) { if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed || state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) _scheduleReconnect(); }`
        - `_pc!.onTrack = (event) { _setState(ClientConnectionState.connected); }`
        - Create offer: `final offer = await _pc!.createOffer({'offerToReceiveAudio': 1})`
        - `await _pc!.setLocalDescription(offer)`
        - Open WS: `_ws = WebSocketChannel.connect(Uri.parse(_serverWsUrl))`
        - Send offer: `_ws!.sink.add(jsonEncode({'type': 'offer', 'sdp': offer.sdp}))`
        - Listen for answer: `_ws!.stream.first` → parse JSON → `RTCSessionDescription(sdp, 'answer')` → `_pc!.setRemoteDescription(answer)`
        - Set state to `connected`, reset reconnect counter, call `notifyListeners()`
      - `void _scheduleReconnect()`: use `_backoffSeconds`, cap at 30s, set state `reconnecting`, schedule `connect()` via `Timer`
      - `void _setState(ClientConnectionState s)`: set state and call `notifyListeners()`
      - `@override Future<void> dispose()`: cancel timer, `_ws?.sink.close()`, `await _pc?.close()`, call `super.dispose()`
  - **Tests** — write `mobile/rhemacast/test/webrtc_client_test.dart`:
    - Test initial state is `ClientConnectionState.idle`
    - Test `_backoffSeconds` list equals `[1, 2, 4, 8, 16, 30]`
    - Test `dispose()` is safe to call when no connection is open (no exception thrown)
    - Test `dispose()` is idempotent (call twice, no exception)
    - Test `notifyListeners` is called on state change: use a `ChangeNotifier` listener to track notifications
    - Note: full integration tests (actual WebRTC) are deferred to Task 12/13; these are pure unit tests of logic
  - **Run tests**: `cd mobile/rhemacast && flutter test test/webrtc_client_test.dart` — must pass before committing

- [x] Task 9: Flutter home screen
  - Implement `mobile/rhemacast/lib/ui/status_widget.dart`:
    - `StatelessWidget` taking `connectionState` and optional `errorMessage`
    - Shows colored circle (green/yellow/red/grey) + label text
    - Green = connected, Yellow = connecting/reconnecting, Red = error, Grey = idle
    - Export a `statusColor(ClientConnectionState state) -> Color` helper for testability
  - Implement `mobile/rhemacast/lib/ui/home_screen.dart`:
    - `StatefulWidget`
    - `initState`: `WidgetsBinding.instance.addPostFrameCallback((_) => context.read<WebRTCClient>().connect())`
    - `Consumer<WebRTCClient>` for connection state
    - `Consumer<AudioRouteDetector>` for headphone state
    - Layout: centered column with app title "Rhemacast", `StatusWidget`, peer count text, headphone warning card (yellow) if `!headphonesConnected`
    - Headphone warning text: "Please connect headphones to avoid disturbing others"
    - Use `Key`s on key widgets (e.g., `Key('headphone_warning')`) for testability
  - Implement `mobile/rhemacast/lib/main.dart`:
    - `void main() => runApp(RhemacastApp())`
    - `RhemacastApp` is a `StatelessWidget` returning `MultiProvider` with `WebRTCClient` and `AudioRouteDetector` providers
    - `MaterialApp` with `HomeScreen()` as home, title "Rhemacast", dark theme
  - **Tests** — write `mobile/rhemacast/test/status_widget_test.dart` and `mobile/rhemacast/test/home_screen_test.dart`:
    - `test_status_widget.dart`:
      - Test `statusColor(connected)` returns `Colors.green`
      - Test `statusColor(error)` returns `Colors.red`
      - Test `statusColor(idle)` returns `Colors.grey`
      - Test `statusColor(connecting)` and `statusColor(reconnecting)` return `Colors.yellow` or orange
      - Widget test: render `StatusWidget(connectionState: connected)`, find green circle
    - `test_home_screen.dart`:
      - Widget test: render `HomeScreen` with mock providers where `headphonesConnected = false`, assert `find.byKey(Key('headphone_warning'))` is present
      - Widget test: render `HomeScreen` with mock providers where `headphonesConnected = true`, assert headphone warning is absent
      - Widget test: render `HomeScreen`, assert "Rhemacast" title is visible
  - **Run tests**: `cd mobile/rhemacast && flutter test test/` — must pass before committing

- [x] Task 10: Flutter headphone detection
  - Implement `mobile/rhemacast/lib/audio_route.dart` fully:
    - Imports: `audio_session`, `dart:async`
    - Class `AudioRouteDetector extends ChangeNotifier`:
      - `bool headphonesConnected = false`
      - `AudioSession? _session`
      - `StreamSubscription? _subscription`
      - `Future<void> initialize()`:
        - `_session = await AudioSession.instance`
        - `await _session!.configure(AudioSessionConfiguration.speech())`
        - Call `_updateHeadphoneState()` for initial state
        - `_subscription = _session!.devicesChangedEventStream.listen((_) => _updateHeadphoneState())`
      - `void _updateHeadphoneState()`:
        - Check active audio devices for headphone types: `AudioDeviceType.headphones`, `AudioDeviceType.headset`, `AudioDeviceType.bluetoothA2dp`, `AudioDeviceType.bluetoothHfp`
        - If `audio_session` doesn't expose device list directly, use a platform-appropriate fallback: default to `false` (assume speaker), update on route change events
        - Set `headphonesConnected` and call `notifyListeners()`
      - `@override void dispose()`: `_subscription?.cancel()`, call `super.dispose()`
  - **Tests** — write `mobile/rhemacast/test/audio_route_test.dart`:
    - Test initial `headphonesConnected` is `false`
    - Test `dispose()` does not throw when `initialize()` was never called
    - Test `dispose()` cancels subscription (call dispose twice, no exception)
    - Test that `notifyListeners()` is called when `headphonesConnected` changes: create a mock subclass that overrides `_updateHeadphoneState` and manually sets the field, verify listener fires
    - Note: full device-detection tests require a real device (deferred to Task 12/13)
  - **Run tests**: `cd mobile/rhemacast && flutter test test/` — must pass before committing

- [x] Task 11: Browser integration test
  - Implement `test/browser_client.html` fully:
    - Standalone HTML page (no build tools, no npm)
    - Hardcoded server URL: `ws://192.168.4.1:8080/ws`
    - On page load, show "Ready to connect" and a "Connect" button
    - On connect click:
      - `pc = new RTCPeerConnection({iceServers: []})`
      - `pc.addTransceiver('audio', {direction: 'recvonly'})`
      - `pc.ontrack = (e) => { audioElement.srcObject = e.streams[0]; }`
      - `pc.onconnectionstatechange = () => updateStatus(pc.connectionState)`
      - Create offer, send via WebSocket, receive answer, setRemoteDescription
      - Create `<audio autoplay>` element for playback
    - Status log: append timestamped messages for each state change
    - "Disconnect" button: closes PC and WS
    - Error display for WS connection failures
    - Style: clean, functional, dark theme matching debug UI
  - **Tests** — write `server/tests/test_browser_client.py`:
    - Test `test/browser_client.html` exists
    - Parse the HTML with Python's `html.parser` — must be valid (no parser errors)
    - Test body contains the string `RTCPeerConnection`
    - Test body contains `WebSocket`
    - Test body contains `addTransceiver`
    - Test body contains `recvonly`
    - Test body contains `<audio` element
    - Test body contains `192.168.4.1:8080/ws` (hardcoded server URL)
  - **Run tests**: `cd server && python -m pytest tests/test_browser_client.py -v` — must pass before committing

- [x] Task 12: Android integration test checklist
  - Create `test/android_test_checklist.md` with step-by-step manual test procedure:
    - Prerequisites: Android device on same WiFi as server (192.168.4.1), headphones connected
    - Steps:
      1. Start server: `cd server && python server.py`
      2. Verify debug UI: open `http://192.168.4.1:8080/` in browser, confirm "Streaming: YES"
      3. Open `test/browser_client.html` in Chrome on laptop, confirm audio plays
      4. Build Flutter app: `cd mobile/rhemacast && flutter build apk --debug`
      5. Install on device: `flutter install` or `flutter run`
      6. App auto-connects: confirm status widget shows green "Connected"
      7. Audio test: speak into server mic, confirm audio in headphones
      8. Reconnect test: kill server → app shows "Reconnecting" → restart server → app reconnects within 30s
      9. Headphone warning: unplug headphones → warning banner appears
      10. Multi-client test: connect 2+ Android devices simultaneously, all receive audio
    - Known issues section (fill in during testing)
    - Fix log section
  - **Tests** — run the full server Python test suite and Flutter test suite to confirm nothing regressed:
    - `cd server && python -m pytest tests/ -v` — all tests must pass
    - `cd mobile/rhemacast && flutter test` — all tests must pass
    - `cd mobile/rhemacast && flutter analyze` — zero errors

- [x] Task 13: iOS integration test checklist
  - Create `test/ios_test_checklist.md` with step-by-step manual test procedure:
    - Prerequisites: iOS device on same WiFi as server, Xcode installed, Apple Developer account
    - Steps:
      1. Build: `cd mobile/rhemacast && flutter build ios --debug`
      2. Run on device: `flutter run` with iOS device connected
      3. iOS-specific: confirm microphone permission dialog appears (NSMicrophoneUsageDescription)
      4. iOS audio session: confirm audio plays through headphones (AVAudioSession configured correctly)
      5. Background audio: test if audio continues when app is backgrounded (may need UIBackgroundModes: audio in Info.plist)
      6. Reconnect test: same as Android
      7. Headphone warning: AirPods count as headphones — confirm no false warning
    - Add to `ios/Runner/Info.plist` if not present: `UIBackgroundModes` array with `audio` value
    - Known issues section
    - Note: `flutter_webrtc` on iOS requires `IPHONEOS_DEPLOYMENT_TARGET = 12.0` minimum in Podfile
  - **Tests** — same regression suite as Task 12:
    - `cd server && python -m pytest tests/ -v` — all tests must pass
    - `cd mobile/rhemacast && flutter test` — all tests must pass
    - `cd mobile/rhemacast && flutter analyze` — zero errors

- [x] Task 14: Load testing and hardening
  - Create `server/test_load.py`:
    - Asyncio script that simulates N concurrent WebRTC clients
    - Uses `aiortc` to create client-side RTCPeerConnections
    - Each client: connect → receive audio for 30 seconds → disconnect
    - Default N=5, configurable via `--clients` arg and `--duration` arg (default 30s)
    - Measures: connection time, audio frame receive rate per client, any dropped frames
    - Reports summary: "N/N clients connected, avg frame rate: X fps, duration: Xs"
    - Exit code 0 if all clients connected successfully, 1 otherwise
  - Review and harden `server/signaling.py`:
    - Add try/except around entire handler, log errors
    - Ensure `broadcast_manager.remove_peer()` is always called in finally block
    - Add `pc.close()` in finally block
  - Review and harden `server/broadcast.py`:
    - Verify `put_nowait` with `QueueFull` catch is correct
    - Add logging for dropped frames (peer too slow)
  - Review `mobile/rhemacast/lib/webrtc_client.dart`:
    - Verify reconnect doesn't stack multiple timers
    - Confirm `_reconnectTimer?.cancel()` is at start of `connect()`
    - Verify `dispose()` is idempotent
  - **Tests**:
    - Update `server/tests/test_broadcast.py`: add test that `distribute` with a full queue logs a warning (patch `logging.warning` and assert it was called)
    - Update `server/tests/test_signaling.py`: add test that peer is cleaned up (removed from BroadcastManager) even if an exception occurs mid-handler
    - Run the full test suite: `cd server && python -m pytest tests/ -v` — all tests must pass
    - Run `cd mobile/rhemacast && flutter test` — all tests must pass

- [x] Task 15: App Store preparation
  - Update `mobile/rhemacast/pubspec.yaml`:
    - Set `version: 1.0.0+1`
    - Verify `description: "Real-time voice broadcasting for on-site translation"`
  - Android release prep:
    - Create `mobile/rhemacast/android/key.properties.template` (not actual keys): document what fields are needed
    - Update `mobile/rhemacast/android/app/build.gradle` for release signing config reference
    - Set `applicationId: "com.rhemacast.app"` in build.gradle
  - iOS release prep:
    - Ensure `ios/Runner/Info.plist` has all required privacy descriptions:
      - `NSMicrophoneUsageDescription` (already added in Task 7)
      - `NSBluetoothAlwaysUsageDescription`
      - `NSBluetoothPeripheralUsageDescription`
    - Add `UIBackgroundModes` with `audio` for background audio playback
    - Create `ios/Runner/PrivacyInfo.xcprivacy` for iOS 17+ Privacy Manifest:
      - Declare: `NSPrivacyAccessedAPITypes` (if using any required reason APIs)
      - Declare: `NSPrivacyCollectedDataTypes` — none (app does not collect data)
      - Declare: `NSPrivacyTrackingEnabled: false`
  - Create `mobile/rhemacast/assets/` directory placeholder (for future icon assets)
  - Document build commands in a `BUILD.md` file:
    - Android debug: `flutter build apk --debug`
    - Android release: `flutter build apk --release`
    - iOS debug: `flutter build ios --debug --no-codesign`
    - iOS release: `flutter build ipa`
  - **Tests**:
    - Write `server/tests/test_app_store_prep.py`:
      - Test `pubspec.yaml` version field is `1.0.0+1`
      - Test `pubspec.yaml` description contains "translation"
      - Test `Info.plist` contains `UIBackgroundModes` with `audio`
      - Test `Info.plist` contains `NSMicrophoneUsageDescription`
      - Test `PrivacyInfo.xcprivacy` exists
      - Test `key.properties.template` exists
    - Run the complete final test suite:
      - `cd server && python -m pytest tests/ -v` — all tests must pass
      - `cd mobile/rhemacast && flutter test` — all tests must pass
      - `cd mobile/rhemacast && flutter analyze` — zero errors required

---

## Loop Termination
The bash loop running this file checks for `- [ ]` patterns. When all tasks are `- [x]`, the loop exits automatically.

## Bash Loop Command (run from /home/stu/src/rhemacast)
```bash
while grep -qE '^\- \[ \]' PROMPT.md; do
  claude --dangerously-skip-permissions -p "$(cat PROMPT.md)"
  echo "--- Task complete. Starting next task ---"
done
echo "All tasks complete!"
```
