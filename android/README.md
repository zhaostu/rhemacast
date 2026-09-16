# Rhemacast Android listener

Audio-only WebRTC listener (WHEP) for the broadcast. No microphone use.

## Prereqs

- Android Studio Hedgehog+ (AGP 8.5.2, JDK 17)
- Android device / emulator, API 26+, on the **same LAN** as `rhemacastd`
- `rhemacastd` serving WHEP at `http://<server-ip>:8080/whep`

## Run

1. Open **Android Studio** → Open → select the `android/` folder.
2. Let Gradle sync (Compose, `io.getstream:stream-webrtc-android:1.3.8`, OkHttp, coroutines
   are fetched from google()/mavenCentral()).
3. Run the `app` configuration on a physical device (same Wi-Fi as server).
4. Enter the server IP (default `192.168.4.1`) → **Connect**.
5. Audio plays via the music stream; adjust with the in-app volume slider.
   Playback continues in background via the foreground service; **Disconnect** stops it.

## Notes

- `minSdk 26`, `targetSdk/compileSdk 34`.
- Permissions: `INTERNET`, `ACCESS_NETWORK_STATE`, `FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_MEDIA_PLAYBACK` (+ runtime `POST_NOTIFICATIONS` on API 33+).
  `RECORD_AUDIO` is intentionally **not** requested (recvonly).
- Errors (unreachable host, bad IP, `rhemacastd` down) surface as status text;
  nothing crashes offline.
- No secrets in the app; the IP is user-entered at runtime.
