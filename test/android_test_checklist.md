# Android Integration Test Checklist

## Prerequisites

- Android device (API 21+) connected to the same WiFi network as the server
- Server machine accessible at `192.168.4.1`
- Wired headphones or Bluetooth headphones for audio testing
- ADB installed and device connected via USB (for `flutter install`)
- Flutter SDK installed on development machine

---

## Steps

### 1. Start the Server

```bash
cd server
python server.py
```

Expected: Server prints `Rhemacast server starting on http://0.0.0.0:8080`

---

### 2. Verify Debug UI

Open `http://192.168.4.1:8080/` in a browser.

- [ ] Page loads with title "Rhemacast Debug"
- [ ] "Streaming: YES" is shown (microphone is active)
- [ ] VU meter responds to audio input
- [ ] "Connected peers: 0" initially

---

### 3. Browser Client Sanity Check

Open `test/browser_client.html` in Chrome on the laptop (must be on same network).

- [ ] "Ready to connect" message shown
- [ ] Click "Connect" — status transitions to "connected"
- [ ] Audio plays through laptop speakers/headphones
- [ ] Debug UI shows "Connected peers: 1"
- [ ] Click "Disconnect" — peers count returns to 0

---

### 4. Build Flutter App

```bash
cd mobile/rhemacast
flutter build apk --debug
```

- [ ] Build exits with code 0
- [ ] APK generated at `build/app/outputs/flutter-apk/app-debug.apk`

---

### 5. Install and Run on Device

```bash
flutter install
# or
flutter run
```

- [ ] App installs successfully
- [ ] App launches without crash
- [ ] App auto-starts connection on launch
- [ ] Status widget shows yellow "Connecting" briefly

---

### 6. Auto-Connect: Confirm Green Status

With headphones connected to the Android device:

- [ ] Status widget turns green "Connected" within 5 seconds
- [ ] Debug UI shows "Connected peers: 1"
- [ ] No headphone warning banner visible

---

### 7. Audio Test

Speak into the server microphone:

- [ ] Audio is audible through headphones on the Android device
- [ ] No significant delay (< 500ms expected on local WiFi)
- [ ] VU meter on debug UI reflects voice input

---

### 8. Reconnect Test

While connected:

1. Kill the server (`Ctrl+C` or kill the process)
2. Observe the app

- [ ] Status widget changes to yellow "Reconnecting"
- [ ] App does NOT crash

Restart the server:

```bash
python server.py
```

- [ ] App reconnects automatically within 30 seconds
- [ ] Status widget returns to green "Connected"
- [ ] Audio resumes

---

### 9. Headphone Warning Test

With the app connected, unplug the headphones from the device:

- [ ] Yellow warning card appears: "Please connect headphones to avoid disturbing others"
- [ ] Warning text matches exactly

Re-plug the headphones:

- [ ] Warning card disappears

---

### 10. Multi-Client Test

Connect 2 or more Android devices simultaneously (repeat steps 4–7 on each):

- [ ] All devices show green "Connected"
- [ ] Debug UI shows "Connected peers: N" (matching device count)
- [ ] All devices receive audio simultaneously
- [ ] No noticeable degradation in audio quality with multiple clients

---

## Known Issues

*(Fill in during testing)*

| Issue | Date | Status |
|-------|------|--------|
| | | |

---

## Fix Log

*(Record fixes applied during testing)*

| Date | Issue | Fix Applied |
|------|-------|-------------|
| | | |
