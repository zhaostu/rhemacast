import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../admin_client.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  @override
  void initState() {
    super.initState();
    context.read<AdminClient>().startListening();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin'),
        backgroundColor: Colors.grey[850],
      ),
      backgroundColor: Colors.grey[900],
      body: Consumer<AdminClient>(
        builder: (context, admin, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SwitchListTile(
                title: const Text('Mute', style: TextStyle(color: Colors.white)),
                value: admin.muted,
                onChanged: (val) => admin.setMuted(val),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Volume: ${(admin.volume * 100).round()}%',
                      style: const TextStyle(color: Colors.white),
                    ),
                    Slider(
                      value: admin.volume,
                      min: 0.0,
                      max: 1.0,
                      divisions: 20,
                      onChanged: (val) => admin.setVolume(val),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white24),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Connected Clients',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              ...admin.clients.map((c) {
                final peerId = c['peer_id'] as String? ?? '';
                final ip = c['ip_address'] as String? ?? '';
                final shortId = peerId.length > 8 ? peerId.substring(0, 8) : peerId;
                return ListTile(
                  title: Text(ip, style: const TextStyle(color: Colors.white)),
                  subtitle: Text(shortId, style: const TextStyle(color: Colors.white54)),
                  trailing: TextButton(
                    onPressed: () => admin.kickPeer(peerId),
                    child: const Text('Kick', style: TextStyle(color: Colors.redAccent)),
                  ),
                );
              }),
              if (admin.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    admin.errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
