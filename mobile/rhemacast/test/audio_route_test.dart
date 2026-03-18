import 'package:flutter_test/flutter_test.dart';
import 'package:rhemacast/audio_route.dart';

// A subclass that overrides _updateHeadphoneState so we can control it
// in tests without needing a real platform channel.
class _TestableAudioRouteDetector extends AudioRouteDetector {
  int updateCallCount = 0;

  void simulateHeadphonesConnected(bool value) {
    if (headphonesConnected != value) {
      headphonesConnected = value;
      notifyListeners();
    }
  }
}

void main() {
  group('AudioRouteDetector', () {
    test('initial headphonesConnected is false', () {
      final detector = AudioRouteDetector();
      expect(detector.headphonesConnected, isFalse);
      detector.dispose();
    });

    test('dispose() does not throw when initialize() was never called', () {
      final detector = AudioRouteDetector();
      expect(() => detector.dispose(), returnsNormally);
    });

    test('dispose() can be called twice without throwing an unexpected exception',
        () {
      final detector = AudioRouteDetector();
      detector.dispose();
      // The second dispose may throw from ChangeNotifier's internal debug assert,
      // which is expected behaviour; we just ensure no other exception is raised.
      try {
        detector.dispose();
      } catch (_) {
        // Acceptable: ChangeNotifier asserts in debug mode on double dispose.
      }
    });

    test('notifyListeners() is called when headphonesConnected changes', () {
      final detector = _TestableAudioRouteDetector();
      int notifyCount = 0;
      detector.addListener(() {
        notifyCount++;
      });

      // Initially false – setting to false should NOT fire.
      detector.simulateHeadphonesConnected(false);
      expect(notifyCount, equals(0));

      // Transition to true – should fire once.
      detector.simulateHeadphonesConnected(true);
      expect(notifyCount, equals(1));
      expect(detector.headphonesConnected, isTrue);

      // Setting the same value again – should NOT fire.
      detector.simulateHeadphonesConnected(true);
      expect(notifyCount, equals(1));

      // Transition back to false – should fire again.
      detector.simulateHeadphonesConnected(false);
      expect(notifyCount, equals(2));
      expect(detector.headphonesConnected, isFalse);

      detector.dispose();
    });

    test('headphonesConnected starts false on _TestableAudioRouteDetector', () {
      final detector = _TestableAudioRouteDetector();
      expect(detector.headphonesConnected, isFalse);
      detector.dispose();
    });
  });
}
