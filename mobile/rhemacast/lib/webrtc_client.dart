import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'constants.dart';

enum ClientConnectionState { idle, connecting, connected, reconnecting, error }

class WebRTCClient extends ChangeNotifier {
  static const String _serverWsUrl = AppConfig.wsUrl;

  RTCPeerConnection? _pc;
  WebSocketChannel? _ws;
  ClientConnectionState state = ClientConnectionState.idle;
  String? errorMessage;
  int peerCount = 0;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  static const List<int> _backoffSeconds = [1, 2, 4, 8, 16, 30];

  List<int> get backoffSeconds => _backoffSeconds;

  Future<void> connect() async {
    _reconnectTimer?.cancel();

    state = ClientConnectionState.connecting;
    notifyListeners();

    _pc = await createPeerConnection(
      {'iceServers': []},
      {
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': false,
        }
      },
    );

    _pc!.onConnectionState = (rtcState) {
      if (rtcState == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          rtcState ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _scheduleReconnect();
      }
    };

    _pc!.onTrack = (event) {
      _setState(ClientConnectionState.connected);
    };

    final offer = await _pc!.createOffer({'offerToReceiveAudio': 1});
    await _pc!.setLocalDescription(offer);

    _ws = WebSocketChannel.connect(Uri.parse(_serverWsUrl));
    _ws!.sink.add(jsonEncode({'type': 'offer', 'sdp': offer.sdp}));

    final raw = await _ws!.stream.first;
    final data = jsonDecode(raw as String) as Map<String, dynamic>;
    final answer =
        RTCSessionDescription(data['sdp'] as String, 'answer');
    await _pc!.setRemoteDescription(answer);

    state = ClientConnectionState.connected;
    _reconnectAttempts = 0;
    notifyListeners();
  }

  void _scheduleReconnect() {
    final delay = _backoffSeconds[
        _reconnectAttempts.clamp(0, _backoffSeconds.length - 1)];
    if (_reconnectAttempts < _backoffSeconds.length - 1) {
      _reconnectAttempts++;
    }
    state = ClientConnectionState.reconnecting;
    notifyListeners();
    _reconnectTimer = Timer(Duration(seconds: delay), connect);
  }

  void _setState(ClientConnectionState s) {
    state = s;
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    _reconnectTimer?.cancel();
    _ws?.sink.close();
    await _pc?.close();
    super.dispose();
  }
}
