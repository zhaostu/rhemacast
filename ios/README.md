# Rhemacast iOS — audio-only WebRTC listener

Audio-only `recvonly` listener for the live broadcast via WHEP to `rhemacastd`:
`POST http://<ip>:8080/whep` with SDP offer, answer applied, `Location` saved for `DELETE` on disconnect.

Microphone is **NOT** needed (playback only) — do **not** add `NSMicrophoneUsageDescription`.

## Files

```
ios/Rhemacast.xcodeproj/
ios/Rhemacast/RhemacastApp.swift   # @main App entry
ios/Rhemacast/ContentView.swift    # single screen: big Listen/Stop toggle, output picker, volume, status, Settings
ios/Rhemacast/WebRTCClient.swift   # RTCPeerConnection (audio recvonly) + WHEP + stats + cleanup
ios/Rhemacast/AudioRouter.swift    # output routing (Auto = Headphones, loudspeaker opt-in)
ios/Info.plist                     # audio bg mode + local-network permission + ATS local exception
```

Project setup is checked in: `ios/Info.plist` holds the 3 custom keys
(`UIBackgroundModes=array(audio)`, `NSLocalNetworkUsageDescription`, `NSAppTransportSecurity` dict),
wired via `INFOPLIST_FILE = Info.plist` with `GENERATE_INFOPLIST_FILE = YES` (merge mode).
WebRTC (`stasel/WebRTC` 153.0.0) is wired via SPM in `project.pbxproj`. No microphone key.

## Run on device

1. iPhone and Pi on the **same LAN** (e.g. Pi hotspot `192.168.4.1`).
2. Select your Team in Signing & Capabilities, run on a **physical device** (Simulator audio/WebRTC is unreliable).
3. Enter the Pi IP (persisted via `@AppStorage`, default `192.168.4.1`), tap **Connect**.
4. Status shows `connecting…` → `live` (+ `RTT … / jitter …` polled every 2 s from `inbound-rtp` / `candidate-pair` stats). Offline/WHEP errors appear in the status label instead of crashing.
5. Volume slider = system volume (`MPVolumeView` — iOS has no per-track WebRTC gain). Mute toggles `RTCAudioTrack.isEnabled`.

## Notes

- Audio session: `.playback` + `.voiceChat` mode, no recording; background audio enabled so listening continues with screen locked.
- WHEP flow: offer (`OfferToReceiveAudio:true`) → `POST` SDP → answer → `setRemoteDescription`; `Location` header stored, `DELETE` sent on Disconnect.
