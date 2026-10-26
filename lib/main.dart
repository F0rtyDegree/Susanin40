import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const _gpxPathKey = 'gpx_file_path';

  String? _gpxPath;
  String? _trackName;
  int? _pointCount;
  double? _distanceKm;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadSavedGpx();
  }

  Future<void> _loadSavedGpx() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_gpxPathKey);
    if (saved != null && saved.isNotEmpty) {
      if (await File(saved).exists()) {
        setState(() => _gpxPath = saved);
        await _parseGpx(saved);
      } else {
        await prefs.remove(_gpxPathKey);
      }
    }
  }

  Future<void> _pickGpx() async {
    setState(() {
      _error = null;
      _trackName = null;
      _pointCount = null;
      _distanceKm = null;
    });

    final status = await Permission.manageExternalStorage.request();
    if (!mounted) return;

    if (!status.isGranted) {
      setState(() {
        _error = status.isPermanentlyDenied
            ? 'Разрешение отклонено навсегда. Включите его в настройках приложения.'
            : 'Нет разрешения на доступ к файлам.';
      });
      if (status.isPermanentlyDenied) {
        await openAppSettings();
      }
      return;
    }

    final rootDirectory = Directory('/storage/emulated/0');
    if (!await rootDirectory.exists()) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось получить доступ к хранилищу');
      return;
    }

    if (!mounted) return;

    final String? pickedPath = await FilesystemPicker.open(
      title: 'Выберите файл трека (.gpx)',
      context: context,
      rootDirectory: rootDirectory,
      fsType: FilesystemType.file,
      allowedExtensions: ['.gpx'],
      fileTileSelectMode: FileTileSelectMode.wholeTile,
    );

    if (!mounted) return;
    if (pickedPath == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_gpxPathKey, pickedPath);
    setState(() => _gpxPath = pickedPath);
    await _parseGpx(pickedPath);
  }

  Future<void> _parseGpx(String path) async {
    setState(() {
      _loading = true;
      _error = null;
      _trackName = null;
      _pointCount = null;
      _distanceKm = null;
    });

    try {
      final content = await File(path).readAsString();
      final document = XmlDocument.parse(content);

      String? trackName;
      final trkElements = document.findAllElements('trk');
      if (trkElements.isNotEmpty) {
        final nameNode = trkElements.first.findElements('name').firstOrNull;
        if (nameNode != null) {
          trackName = nameNode.innerText.trim();
        }
      }

      final trkpts = document.findAllElements('trkpt').toList();

      if (trkpts.isEmpty) {
        setState(() => _error = 'Файл не содержит точек маршрута');
        return;
      }

      double total = 0.0;
      double? prevLat;
      double? prevLon;

      for (final pt in trkpts) {
        final latStr = pt.getAttribute('lat');
        final lonStr = pt.getAttribute('lon');
        if (latStr == null || lonStr == null) continue;

        final lat = double.tryParse(latStr);
        final lon = double.tryParse(lonStr);
        if (lat == null || lon == null) continue;

        if (prevLat != null && prevLon != null) {
          total += _haversineDistance(prevLat, prevLon, lat, lon);
        }
        prevLat = lat;
        prevLon = lon;
      }

      setState(() {
        _trackName = trackName;
        _pointCount = trkpts.length;
        _distanceKm = total;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Ошибка чтения файла: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusKm = 6371.0;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    final rLat1 = _degreesToRadians(lat1);
    final rLat2 = _degreesToRadians(lat2);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        sin(dLon / 2) * sin(dLon / 2) * cos(rLat1) * cos(rLat2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180.0;
  }

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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: _loading ? null : _pickGpx,
              child: Text(_loading ? 'Чтение маршрута...' : 'Выбрать маршрут (.gpx)'),
            ),
            const SizedBox(height: 16),
            if (_trackName != null)
              Text('Трек: $_trackName')
            else if (_gpxPath != null)
              Text('Файл: $_gpxPath'),            if (_trackName != null)
              Text('Маршрут: $_trackName')
            else if (_gpxPath != null)
              Text('Файл: $_gpxPath'),
            const SizedBox(height: 8),
            if (_pointCount != null) Text('Точек маршрута: $_pointCount'),
            if (_distanceKm != null)
              Text('Длина: ${_distanceKm!.toStringAsFixed(1)} км'),
            if (_error != null)
              Text(
                'Ошибка: $_error',
                style: const TextStyle(color: Colors.red),
              ),
          ],
        ),
      ),
    );
  }
}