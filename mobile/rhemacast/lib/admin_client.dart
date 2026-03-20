import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'constants.dart';

class AdminClient extends ChangeNotifier {
  String? _pin;

  List<Map<String, dynamic>> clients = [];
  bool muted = false;
  double volume = 1.0;
  int peerCount = 0;
  double vuDb = -96.0;
  bool streaming = false;
  String? errorMessage;

  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _sub;
  bool _disposed = false;

  void setPin(String pin) {
    _pin = pin;
    errorMessage = null;
    notifyListeners();
  }

  void startListening() {
    _connect();
  }

  void _connect() {
    if (_disposed) return;
    final uri = Uri.parse(AppConfig.wsUiUrl);
    _ws = WebSocketChannel.connect(uri);
    _sub = _ws!.stream.listen(
      _onMessage,
      onError: (_) => _scheduleReconnect(),
      onDone: _scheduleReconnect,
    );
  }

  void _onMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      peerCount = (data['peer_count'] as num?)?.toInt() ?? peerCount;
      streaming = (data['streaming'] as bool?) ?? streaming;
      vuDb = (data['vu_db'] as num?)?.toDouble() ?? vuDb;
      muted = (data['muted'] as bool?) ?? muted;
      volume = (data['volume'] as num?)?.toDouble() ?? volume;
      final rawClients = data['clients'];
      if (rawClients is List) {
        clients = rawClients.cast<Map<String, dynamic>>();
      }
      notifyListeners();
    } catch (_) {}
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _sub?.cancel();
    _ws = null;
    Future.delayed(const Duration(seconds: 3), _connect);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_pin != null) 'X-Admin-PIN': _pin!,
      };

  Future<void> kickPeer(String peerId) async {
    final resp = await http.post(
      Uri.parse('${AppConfig.baseUrl}/admin/kick/$peerId'),
      headers: _headers,
    );
    if (resp.statusCode == 401) {
      errorMessage = 'Wrong PIN';
      notifyListeners();
    } else if (resp.statusCode == 200) {
      clients.removeWhere((c) => c['peer_id'] == peerId);
      notifyListeners();
    }
  }

  Future<void> setVolume(double level) async {
    final prev = volume;
    volume = level;
    notifyListeners();
    final resp = await http.post(
      Uri.parse('${AppConfig.baseUrl}/admin/volume'),
      headers: _headers,
      body: jsonEncode({'level': level}),
    );
    if (resp.statusCode == 401) {
      volume = prev;
      errorMessage = 'Wrong PIN';
      notifyListeners();
    }
  }

  Future<void> setMuted(bool value) async {
    final prev = muted;
    muted = value;
    notifyListeners();
    final resp = await http.post(
      Uri.parse('${AppConfig.baseUrl}/admin/mute'),
      headers: _headers,
      body: jsonEncode({'muted': value}),
    );
    if (resp.statusCode == 401) {
      muted = prev;
      errorMessage = 'Wrong PIN';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _ws?.sink.close();
    super.dispose();
  }
}
