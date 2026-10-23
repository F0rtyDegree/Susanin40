import 'package:flutter/material.dart';
import 'screens/settings_screen.dart';
import 'screens/info_screen.dart';
import 'screens/help_screen.dart';

void main() {
  runApp(const SusaninApp());
}

class SusaninApp extends StatelessWidget {
  const SusaninApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Susanin 40°',
      theme: ThemeData(useMaterial3: true),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Susanin 40°'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HelpScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const InfoScreen()),
            ),
          ),
        ],
      ),
      body: const SizedBox.shrink(),
    );
  }
}
