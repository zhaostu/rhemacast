import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../webrtc_client.dart';
import '../audio_route.dart';
import 'status_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WebRTCClient>().connect();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Rhemacast',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 32),
                Consumer<WebRTCClient>(
                  builder: (context, client, _) {
                    return Column(
                      children: [
                        StatusWidget(
                          connectionState: client.state,
                          errorMessage: client.errorMessage,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Peers: ${client.peerCount}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                Consumer<AudioRouteDetector>(
                  builder: (context, detector, _) {
                    if (detector.headphonesConnected) {
                      return const SizedBox.shrink();
                    }
                    return Card(
                      key: const Key('headphone_warning'),
                      color: Colors.yellow[800],
                      child: const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Icon(Icons.headset_off, color: Colors.white),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Please connect headphones to avoid disturbing others',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
