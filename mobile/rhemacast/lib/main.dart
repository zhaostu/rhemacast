import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'webrtc_client.dart';
import 'audio_route.dart';
import 'ui/home_screen.dart';

void main() {
  runApp(const RhemacastApp());
}

class RhemacastApp extends StatelessWidget {
  const RhemacastApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WebRTCClient()),
        ChangeNotifierProvider(create: (_) => AudioRouteDetector()),
      ],
      child: MaterialApp(
        title: 'Rhemacast',
        theme: ThemeData.dark(),
        home: const HomeScreen(),
      ),
    );
  }
}
