import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../webrtc_client.dart';
import '../audio_route.dart';
import '../admin_client.dart';
import 'status_widget.dart';
import 'admin_screen.dart';

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

  Future<String?> _showPinDialog(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => const _PinDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('Rhemacast'),
        backgroundColor: Colors.grey[850],
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Admin',
            onPressed: () async {
              final pin = await _showPinDialog(context);
              if (pin == null || !context.mounted) return;
              context.read<AdminClient>().setPin(pin);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
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

class _PinDialog extends StatefulWidget {
  const _PinDialog();

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  String _pin = '';

  void _onDigit(String digit) {
    if (_pin.length >= 4) return;
    final next = _pin + digit;
    setState(() => _pin = next);
    if (next.length == 4) {
      Navigator.of(context).pop(next);
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final dots = List.generate(
      4,
      (i) => Icon(
        i < _pin.length ? Icons.circle : Icons.circle_outlined,
        size: 16,
        color: Colors.white,
      ),
    );

    return AlertDialog(
      backgroundColor: Colors.grey[850],
      title: const Text('Enter PIN', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: dots.map((d) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: d,
            )).toList(),
          ),
          const SizedBox(height: 24),
          _buildKeypad(),
        ],
      ),
    );
  }

  Widget _buildKeypad() {
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];
    return Column(
      children: [
        ...rows.map((row) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: row.map((d) => _DigitButton(digit: d, onTap: _onDigit)).toList(),
        )),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 72),
            _DigitButton(digit: '0', onTap: _onDigit),
            SizedBox(
              width: 72,
              height: 72,
              child: IconButton(
                icon: const Icon(Icons.backspace, color: Colors.white70),
                onPressed: _onBackspace,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DigitButton extends StatelessWidget {
  const _DigitButton({required this.digit, required this.onTap});
  final String digit;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: TextButton(
        onPressed: () => onTap(digit),
        child: Text(
          digit,
          style: const TextStyle(fontSize: 24, color: Colors.white),
        ),
      ),
    );
  }
}
