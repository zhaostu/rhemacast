import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rhemacast/webrtc_client.dart';
import 'package:rhemacast/ui/status_widget.dart';

void main() {
  group('statusColor', () {
    test('connected returns green', () {
      expect(statusColor(ClientConnectionState.connected), equals(Colors.green));
    });

    test('error returns red', () {
      expect(statusColor(ClientConnectionState.error), equals(Colors.red));
    });

    test('idle returns grey', () {
      expect(statusColor(ClientConnectionState.idle), equals(Colors.grey));
    });

    test('connecting returns yellow', () {
      expect(statusColor(ClientConnectionState.connecting), equals(Colors.yellow));
    });

    test('reconnecting returns yellow', () {
      expect(statusColor(ClientConnectionState.reconnecting), equals(Colors.yellow));
    });
  });

  group('StatusWidget', () {
    testWidgets('renders green circle when connected', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusWidget(
              connectionState: ClientConnectionState.connected,
            ),
          ),
        ),
      );

      final circle = tester.widget<Container>(
        find.byKey(const Key('status_circle')),
      );
      final decoration = circle.decoration as BoxDecoration;
      expect(decoration.color, equals(Colors.green));
    });

    testWidgets('renders red circle when error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusWidget(
              connectionState: ClientConnectionState.error,
              errorMessage: 'Connection failed',
            ),
          ),
        ),
      );

      final circle = tester.widget<Container>(
        find.byKey(const Key('status_circle')),
      );
      final decoration = circle.decoration as BoxDecoration;
      expect(decoration.color, equals(Colors.red));
      expect(find.text('Connection failed'), findsOneWidget);
    });

    testWidgets('renders grey circle when idle', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusWidget(
              connectionState: ClientConnectionState.idle,
            ),
          ),
        ),
      );

      final circle = tester.widget<Container>(
        find.byKey(const Key('status_circle')),
      );
      final decoration = circle.decoration as BoxDecoration;
      expect(decoration.color, equals(Colors.grey));
    });

    testWidgets('shows state label text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusWidget(
              connectionState: ClientConnectionState.connected,
            ),
          ),
        ),
      );

      expect(find.text('Connected'), findsOneWidget);
    });

    testWidgets('does not show error message when null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusWidget(
              connectionState: ClientConnectionState.idle,
            ),
          ),
        ),
      );

      // No error text should be present
      expect(find.byType(Text), findsOneWidget); // only label, no error
    });
  });
}
