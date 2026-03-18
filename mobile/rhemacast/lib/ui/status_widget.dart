import 'package:flutter/material.dart';
import '../webrtc_client.dart';

Color statusColor(ClientConnectionState state) {
  switch (state) {
    case ClientConnectionState.connected:
      return Colors.green;
    case ClientConnectionState.connecting:
    case ClientConnectionState.reconnecting:
      return Colors.yellow;
    case ClientConnectionState.error:
      return Colors.red;
    case ClientConnectionState.idle:
      return Colors.grey;
  }
}

String _statusLabel(ClientConnectionState state) {
  switch (state) {
    case ClientConnectionState.connected:
      return 'Connected';
    case ClientConnectionState.connecting:
      return 'Connecting...';
    case ClientConnectionState.reconnecting:
      return 'Reconnecting...';
    case ClientConnectionState.error:
      return 'Error';
    case ClientConnectionState.idle:
      return 'Idle';
  }
}

class StatusWidget extends StatelessWidget {
  final ClientConnectionState connectionState;
  final String? errorMessage;

  const StatusWidget({
    super.key,
    required this.connectionState,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    final color = statusColor(connectionState);
    final label = _statusLabel(connectionState);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: const Key('status_circle'),
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 16)),
        if (errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
