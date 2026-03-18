import 'package:flutter/material.dart';

void main() {
  runApp(const RhemacastApp());
}

class RhemacastApp extends StatelessWidget {
  const RhemacastApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rhemacast',
      home: Scaffold(
        body: Center(child: Text('Rhemacast')),
      ),
    );
  }
}
