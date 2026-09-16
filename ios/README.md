# Rhemacast iOS — audio-only WebRTC listener

Audio-only `recvonly` listener for the translator broadcast via WHEP to `rhemacastd`:
`POST http://<ip>:8080/whep` with SDP offer, answer applied, `Location` saved for `DELETE` on disconnect.

Microphone is **NOT** needed (playback only) — do **not** add `NSMicrophoneUsageDescription`.

## Files

```
ios/Rhemacast/RhemacastApp.swift   # @main App entry
ios/Rhemacast/ContentView.swift    # single screen: IP field, Connect/Disconnect, mute, volume, status
ios/Rhemacast/WebRTCClient.swift   # RTCPeerConnection (audio recvonly) + WHEP + stats + cleanup
ios/Rhemacast/Info.plist           # merge these keys into your target's Info.plist
```

## 1. Create the Xcode project (no .xcodeproj in repo — generate locally)

1. `File > New > Project > iOS > App`, name `Rhemacast`, Interface `SwiftUI`, Language `Swift`.
2. Drag the 3 `.swift` files above into the `Rhemacast` group (Copy items if needed).
3. Merge `ios/Rhemacast/Info.plist` keys into the target's Info:
   - `UIBackgroundModes = audio` (Target > Signing & Capabilities > `+ Capability > Background Modes > Audio, AirPlay, and Picture in Picture`, or `TARGETS > Info > Custom iOS Target Properties`).
   - `NSLocalNetworkUsageDescription` = "Rhemacast connects to the translator server on your local network."
   - No microphone key needed.

## 2. Add WebRTC via SPM (preferred)

`File > Add Package Dependencies…`, enter:

```
https://github.com/stasel/WebRTC
```

- Use version rule "Up to Next Major" from the latest release (works with Xcode 15+).
- Add product `WebRTC` to the `Rhemacast` target.
- `import WebRTC` is already in `WebRTCClient.swift`.

Alternative (CocoaPods, not preferred): pod `GoogleWebRTC` — same API, but SPM above is recommended.

Package.swift snippet (if using SwiftPM directly instead of Xcode UI):

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Rhemacast",
    platforms: [.iOS(.v16)],
    dependencies: [
        .package(url: "https://github.com/stasel/WebRTC", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Rhemacast",
            dependencies: [.product(name: "WebRTC", package: "WebRTC")],
            path: "Rhemacast"
        ),
    ]
)
```

## 3. Run on device

1. iPhone and Pi on the **same LAN** (e.g. Pi hotspot `192.168.4.1`).
2. Select your Team in Signing & Capabilities, run on a **physical device** (Simulator audio/WebRTC is unreliable).
3. Enter the Pi IP (persisted via `@AppStorage`, default `192.168.4.1`), tap **Connect**.
4. Status shows `connecting…` → `live` (+ `RTT … / jitter …` polled every 2 s from `inbound-rtp` / `candidate-pair` stats). Offline/WHEP errors appear in the status label instead of crashing.
5. Volume slider = system volume (`MPVolumeView` — iOS has no per-track WebRTC gain). Mute toggles `RTCAudioTrack.isEnabled`.

## Notes

- Audio session: `.playback` + `.voiceChat` mode, no recording; background audio enabled so listening continues with screen locked.
- WHEP flow: offer (`OfferToReceiveAudio:true`) → `POST` SDP → answer → `setRemoteDescription`; `Location` header stored, `DELETE` sent on Disconnect.
