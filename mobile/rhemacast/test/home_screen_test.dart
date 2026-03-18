import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rhemacast/webrtc_client.dart';
import 'package:rhemacast/audio_route.dart';
import 'package:rhemacast/ui/home_screen.dart';

/// Mock WebRTCClient that overrides connect() to be a no-op.
class MockWebRTCClient extends WebRTCClient {
  @override
  Future<void> connect() async {
    // No-op: avoids native flutter_webrtc calls in tests
  }
}

/// Mock AudioRouteDetector with configurable headphone state.
class MockAudioRouteDetector extends AudioRouteDetector {
  MockAudioRouteDetector({bool headphones = false}) {
    headphonesConnected = headphones;
  }
}

Widget _buildHomeScreen({
  MockWebRTCClient? client,
  MockAudioRouteDetector? detector,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<WebRTCClient>.value(
        value: client ?? MockWebRTCClient(),
      ),
      ChangeNotifierProvider<AudioRouteDetector>.value(
        value: detector ?? MockAudioRouteDetector(),
      ),
    ],
    child: const MaterialApp(
      home: HomeScreen(),
    ),
  );
}

void main() {
  group('HomeScreen', () {
    testWidgets('shows Rhemacast title', (tester) async {
      await tester.pumpWidget(_buildHomeScreen());
      await tester.pump(); // process post-frame callbacks
      expect(find.text('Rhemacast'), findsOneWidget);
    });

    testWidgets('shows headphone warning when headphones not connected',
        (tester) async {
      final detector = MockAudioRouteDetector(headphones: false);
      await tester.pumpWidget(_buildHomeScreen(detector: detector));
      await tester.pump();
      expect(find.byKey(const Key('headphone_warning')), findsOneWidget);
      expect(
        find.text('Please connect headphones to avoid disturbing others'),
        findsOneWidget,
      );
    });

    testWidgets('hides headphone warning when headphones connected',
        (tester) async {
      final detector = MockAudioRouteDetector(headphones: true);
      await tester.pumpWidget(_buildHomeScreen(detector: detector));
      await tester.pump();
      expect(find.byKey(const Key('headphone_warning')), findsNothing);
    });

    testWidgets('shows status widget', (tester) async {
      await tester.pumpWidget(_buildHomeScreen());
      await tester.pump();
      // StatusWidget renders with a status_circle key
      expect(find.byKey(const Key('status_circle')), findsOneWidget);
    });

    testWidgets('shows peer count', (tester) async {
      await tester.pumpWidget(_buildHomeScreen());
      await tester.pump();
      expect(find.textContaining('Peers:'), findsOneWidget);
    });

    testWidgets('calls connect() on init without throwing', (tester) async {
      final client = MockWebRTCClient();
      await tester.pumpWidget(_buildHomeScreen(client: client));
      await tester.pump(); // triggers post-frame callback
      // If connect() threw, the test would fail; since it completes, we're good.
      expect(tester.takeException(), isNull);
    });
  });
}
