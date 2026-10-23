import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class InfoScreen extends StatefulWidget {
  const InfoScreen({super.key});

  @override
  State<InfoScreen> createState() => _InfoScreenState();
}

class _InfoScreenState extends State<InfoScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _version = 'Version: ${packageInfo.version}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Информация')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Susanin 40°',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(_version),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Голосовой продвинутый навигатор.\n\n'
              'Назначение: вести по заданному маршруту или ранее кем-то записанному треку (загрузка из файла GPX) голосом, предупреждая о поворотах, отклонениях от маршрута и так далее.\n\n'
              'Использует офлайн векторные карты для сверки маршрута с уже известными путями для уверенного определения существующих поворотов/развилок. Векторные офлайн карты берутся из каталога, который нужно выбрать в настройках.',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}