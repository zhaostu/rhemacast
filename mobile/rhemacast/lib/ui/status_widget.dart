import 'package:flutter/material.dart';
import '../webrtc_client.dart';

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
    return Text(connectionState.name);
  }
}
