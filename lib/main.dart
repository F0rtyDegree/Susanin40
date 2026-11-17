import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'package:mapsforge_flutter_core/projection.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'services/map_service.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/settings_screen.dart';
import 'screens/info_screen.dart';
import 'screens/help_screen.dart';
import 'theme.dart';

void main() {
  runApp(const SusaninApp());
}

class SusaninApp extends StatefulWidget {
  const SusaninApp({super.key});

  @override
  State<SusaninApp> createState() => _SusaninAppState();
}

class _SusaninAppState extends State<SusaninApp> {
  AppTheme _theme = AppTheme.white;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeStr = prefs.getString('app_theme');
    if (themeStr != null) {
      setState(() {
        _theme = AppTheme.values.firstWhere((e) => e.name == themeStr, orElse: () => AppTheme.white);
      });
    }
  }

  Future<void> _setTheme(AppTheme theme) async {
    setState(() => _theme = theme);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_theme', theme.name);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Susanin 40°',
      theme: getThemeData(_theme),
      home: MainScreen(
        currentTheme: _theme,
        onThemeChanged: _setTheme,
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  final AppTheme currentTheme;
  final Function(AppTheme) onThemeChanged;

  const MainScreen({super.key, required this.currentTheme, required this.onThemeChanged});

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
  String? _mapCheckInfo;

  @override
  void initState() {
    super.initState();
    _initMap();
    _loadSavedGpx();
  }

  Future<void> _initMap() async {
    final prefs = await SharedPreferences.getInstance();
    final mapPath = prefs.getString('map_file_path');
    if (mapPath != null && await File(mapPath).exists()) {
      await MapService.instance.open(mapPath);
    }
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
      title: 'Выберите файл трека',
      context: context,
      rootDirectory: rootDirectory,
      fsType: FilesystemType.file,
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
      final List<_GpxPoint> parsedPoints = [];

      for (final pt in trkpts) {
        final latStr = pt.getAttribute('lat');
        final lonStr = pt.getAttribute('lon');
        if (latStr == null || lonStr == null) continue;

        final lat = double.tryParse(latStr);
        final lon = double.tryParse(lonStr);
        if (lat == null || lon == null) continue;

        parsedPoints.add(_GpxPoint(lat, lon));

        if (prevLat != null && prevLon != null) {
          total += _haversineDistance(prevLat, prevLon, lat, lon);
        }
        prevLat = lat;
        prevLon = lon;
      }

      _mapCheckInfo = 'Анализ карты...';
      if (MapService.instance.isLoaded && parsedPoints.isNotEmpty) {
        await _checkRouteAgainstMap(parsedPoints);
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

  Future<void> _checkRouteAgainstMap(List<_GpxPoint> points) async {
    try {
      final proj = MercatorProjection.fromZoomlevel(17);
      final Set<Tile> uniqueTiles = {};

      for (var pt in points) {
        final tx = proj.longitudeToTileX(pt.lon);
        final ty = proj.latitudeToTileY(pt.lat);
        uniqueTiles.add(Tile(tx, ty, 17, 0));
      }

      final Set<String> processedNodes = {};
      final List<String> gpxLines = [];
      final List<String> excludedLines = [];

      for (var tile in uniqueTiles) {
        final bundle = await MapService.instance.mapFile!.readMapDataSingle(tile);
        final validWays = bundle.ways.where((w) => w.tags.getTag('highway') != null).toList();
        if (validWays.isEmpty) continue;

        final Map<String, int> nodeCounts = {};
        final Map<String, Set<Way>> nodeToWays = {};
        for (var w in validWays) {
          for (var segment in w.latLongs) {
            for (var coord in segment) {
              final cKey = '${coord.latitude.toStringAsFixed(5)},${coord.longitude.toStringAsFixed(5)}';
              nodeCounts[cKey] = (nodeCounts[cKey] ?? 0) + 1;
              nodeToWays.putIfAbsent(cKey, () => {}).add(w);
            }
          }
        }

        for (var entry in nodeCounts.entries) {
          if (entry.value >= 2 && !processedNodes.contains(entry.key)) {

            final parts = entry.key.split(',');
            final lat = parts[0];
            final lon = parts[1];
            final ways = nodeToWays[entry.key]!;

            final List<String> allTags = [];
            for (var w in ways) {
              final tagList = w.tags.tags;
              final tagString = tagList.map((t) => '${t.key}=${t.value}').join(', ');
              if (tagString.isNotEmpty) {
                allTags.add('($tagString)');
              }
            }

            // Исключаем узлы, где ровно 2 примыкания и обе являются крайними точками (просто стык)
            if (entry.value == 2) {
              bool allEndpoints = true;
              for (var w in ways) {
                if (!_isEndpoint(w, double.parse(lat), double.parse(lon))) {
                  allEndpoints = false;
                  break;
                }
              }
              if (allEndpoints) {
                final exNameText = 'X${entry.value}: ${allTags.join(' | ')}';
                excludedLines.add('  <wpt lat="$lat" lon="$lon"><name>$exNameText</name></wpt>');
                continue;
              }
            }

            processedNodes.add(entry.key);

            final waysInfo = allTags;
            final nodeIndex = processedNodes.length;
            final nameText = '${nodeIndex}Y${entry.value}: ${waysInfo.join(' | ')}';

            gpxLines.add('  <wpt lat="$lat" lon="$lon"><name>$nameText</name></wpt>');
          }
        }
      }

      final trackName = _trackName ?? 'route';
      final safeName = trackName.replaceAll(RegExp(r'[^\w\s\-]'), '').trim().replaceAll(' ', '_');
      final filePath = '/storage/emulated/0/Download/${safeName}_v.gpx';
      final excludedFilePath = '/storage/emulated/0/Download/${safeName}_excluded.gpx';

      StringBuffer gpx = StringBuffer();
      gpx.writeln('<?xml version="1.0" encoding="UTF-8"?>');
      gpx.writeln('<gpx version="1.1" creator="Susanin40" xmlns="http://www.topografix.com/GPX/1/1">');
      for (var line in gpxLines) {
        gpx.writeln(line);
      }
      gpx.writeln('</gpx>');
      await File(filePath).writeAsString(gpx.toString());

      StringBuffer exGpx = StringBuffer();
      exGpx.writeln('<?xml version="1.0" encoding="UTF-8"?>');
      exGpx.writeln('<gpx version="1.1" creator="Susanin40" xmlns="http://www.topografix.com/GPX/1/1">');
      for (var line in excludedLines) {
        exGpx.writeln(line);
      }
      exGpx.writeln('</gpx>');
      await File(excludedFilePath).writeAsString(exGpx.toString());

      if (!mounted) return;
      setState(() {
        _mapCheckInfo = 'Найдено: ${gpxLines.length} | Исключено: ${excludedLines.length}\n$filePath\n$excludedFilePath';
      });
    } catch (e) {
      if (mounted) {
        setState(() => _mapCheckInfo = 'Ошибка анализа карты: $e');
      }
    }
  }
  bool _isEndpoint(Way w, double lat, double lon) {
    if (w.latLongs.isEmpty) return false;
    final targetLat = lat.toStringAsFixed(5);
    final targetLon = lon.toStringAsFixed(5);

    for (var segment in w.latLongs) {
      if (segment.isEmpty) continue;
      final firstPoint = segment.first;
      final lastPoint = segment.last;

      if (firstPoint.latitude.toStringAsFixed(5) == targetLat &&
          firstPoint.longitude.toStringAsFixed(5) == targetLon) {
        return true;
      }

      if (lastPoint.latitude.toStringAsFixed(5) == targetLat &&
          lastPoint.longitude.toStringAsFixed(5) == targetLon) {
        return true;
      }
    }
    return false;
  }
  double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    final rLat1 = _degreesToRadians(lat1);
    final rLat2 = _degreesToRadians(lat2);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
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
              MaterialPageRoute(builder: (_) => SettingsScreen(
                currentTheme: widget.currentTheme,
                onThemeChanged: widget.onThemeChanged,
              )),
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
              child: Text(
                _loading ? 'Чтение маршрута...' : 'Выбрать маршрут (.gpx)',
              ),
            ),
            const SizedBox(height: 16),
            if (_trackName != null)
              Text(_trackName!)
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
            if (_mapCheckInfo != null)
              Text(
                _mapCheckInfo!,
                style: const TextStyle(color: Colors.blue),
              ),
          ],
        ),
      ),
    );
  }
}

class _GpxPoint {
  final double lat;
  final double lon;
  _GpxPoint(this.lat, this.lon);
}

