import 'package:flutter/foundation.dart';

enum ClientConnectionState { idle, connecting, connected, reconnecting, error }

class WebRTCClient extends ChangeNotifier {
  ClientConnectionState state = ClientConnectionState.idle;
  String? errorMessage;
  int peerCount = 0;

  Future<void> connect() async {
    // TODO: implement in Task 8
  }

  @override
  Future<void> dispose() async {
    super.dispose();
  }
}
