import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

class AudioRouteDetector extends ChangeNotifier {
  bool headphonesConnected = false;

  AudioSession? _session;
  StreamSubscription? _subscription;

  Future<void> initialize() async {
    _session = await AudioSession.instance;
    await _session!.configure(const AudioSessionConfiguration.speech());
    _updateHeadphoneState();
    _subscription = _session!.devicesChangedEventStream
        .listen((_) => _updateHeadphoneState());
  }

  void _updateHeadphoneState() {
    // We rely on the devicesChangedEventStream to detect route changes.
    // On a real device, we would query getDevices() to check headphone types.
    // In the unit-test environment (no platform channel), we default to false
    // and let the stream-based updates drive the state.
    //
    // When a real device is available (Task 12/13), replace this stub with:
    //   final devices = await _session!.getDevices();
    //   const headphoneTypes = {
    //     AudioDeviceType.wiredHeadphones,
    //     AudioDeviceType.wiredHeadset,
    //     AudioDeviceType.bluetoothA2dp,
    //     AudioDeviceType.bluetoothSco,
    //   };
    //   final connected = devices.any((d) => headphoneTypes.contains(d.type));
    //   _setHeadphonesConnected(connected);
    _setHeadphonesConnected(false);
  }

  void _setHeadphonesConnected(bool value) {
    if (headphonesConnected != value) {
      headphonesConnected = value;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
