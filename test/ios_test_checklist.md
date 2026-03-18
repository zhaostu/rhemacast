# iOS Integration Test Checklist

## Prerequisites

- iOS device (iPhone or iPad, iOS 12.0+) connected to the same WiFi network as the server
- Server machine accessible at `192.168.4.1`
- Wired headphones or Bluetooth headphones (e.g., AirPods) for audio testing
- Xcode installed on macOS development machine
- Apple Developer account configured in Xcode (free account is sufficient for on-device testing)
- iOS device trusted and unlocked, connected via USB
- Flutter SDK installed on development machine
- Note: `flutter_webrtc` on iOS requires `IPHONEOS_DEPLOYMENT_TARGET = 12.0` minimum in `ios/Podfile`

---

## Steps

### 1. Build the iOS App

```bash
cd mobile/rhemacast
flutter build ios --debug
```

- [ ] Build exits with code 0
- [ ] Xcode project compiles without errors
- [ ] `IPHONEOS_DEPLOYMENT_TARGET` is set to `12.0` or higher in `ios/Podfile`

---

### 2. Run on Device

With an iOS device connected via USB:

```bash
flutter run
```

- [ ] App installs on device successfully (Xcode code signing completes)
- [ ] App launches without crash
- [ ] App auto-starts connection on launch
- [ ] Status widget shows yellow "Connecting" briefly

---

### 3. Microphone Permission Dialog (iOS-specific)

On first launch, iOS will prompt for microphone access due to `NSMicrophoneUsageDescription` in `Info.plist`.

- [ ] Microphone permission dialog appears with description "Rhemacast uses the microphone for audio translation"
- [ ] Tap "Allow" — app proceeds normally
- [ ] If "Don't Allow" is tapped, app does not crash (degrades gracefully)

---

### 4. iOS Audio Session — Headphone Playback

With headphones connected to the iOS device:

- [ ] Status widget turns green "Connected" within 5 seconds
- [ ] Audio plays through headphones (AVAudioSession is configured correctly)
- [ ] No audio plays through the device speaker (correct route selected)
- [ ] Debug UI at `http://192.168.4.1:8080/` shows "Connected peers: 1"

---

### 5. Background Audio Test

With audio playing, press the Home button (or swipe up) to background the app:

- [ ] Audio continues playing through headphones after backgrounding
- [ ] `UIBackgroundModes` includes `audio` in `ios/Runner/Info.plist`
- [ ] iOS Control Center shows the app as the active audio source
- [ ] Bring app back to foreground — status is still "Connected"

---

### 6. Reconnect Test

While connected:

1. Kill the server (`Ctrl+C` or kill the process)
2. Observe the app

- [ ] Status widget changes to yellow "Reconnecting"
- [ ] App does NOT crash

Restart the server:

```bash
cd server
python server.py
```

- [ ] App reconnects automatically within 30 seconds
- [ ] Status widget returns to green "Connected"
- [ ] Audio resumes

---

### 7. Headphone Warning — AirPods and Wired Headphones

**AirPods (Bluetooth):**

- [ ] Connect AirPods before launching the app — no headphone warning appears
- [ ] AirPods count as Bluetooth headphones (`AudioDeviceType.bluetoothA2dp` / `bluetoothHfp`), so no false warning is shown

**Wired headphones (Lightning or USB-C adapter):**

- [ ] Connect wired headphones — no warning banner visible
- [ ] Unplug headphones — yellow warning card appears: "Please connect headphones to avoid disturbing others"
- [ ] Re-connect headphones — warning card disappears

**No headphones:**

- [ ] With no headphones connected at launch, warning card is shown immediately

---

## Known Issues

*(Fill in during testing)*

| Issue | Date | Status |
|-------|------|--------|
| | | |

---

## Notes

- `flutter_webrtc` on iOS requires `IPHONEOS_DEPLOYMENT_TARGET = 12.0` minimum in `ios/Podfile`. Ensure the Podfile contains `platform :ios, '12.0'` or higher.
- The app uses `AVAudioSession` (via the `audio_session` Flutter package) to manage audio routing. The session is configured with `AudioSessionConfiguration.speech()` which sets the iOS category to `.playAndRecord` with appropriate options for headphone routing.
- `UIBackgroundModes` with value `audio` must be present in `ios/Runner/Info.plist` for background audio playback to work. This is already added in the Info.plist.
- On iOS 14+, Bluetooth permission is requested via `NSBluetoothAlwaysUsageDescription`. This is already present in `Info.plist`.
- If the app is rejected for App Store review due to microphone usage without user-visible audio recording feature, add clarification to `NSMicrophoneUsageDescription` that the mic is used for translation (not recording stored audio).
