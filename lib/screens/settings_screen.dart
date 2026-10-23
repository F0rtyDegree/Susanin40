import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mapsforge_flutter_mapfile/mapfile.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _pathKey = 'map_file_path';

  Mapfile? _mapFile;
  String? _path;
  bool _loading = false;
  int? _subFileCount;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedPath();
  }

  Future<void> _loadSavedPath() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_pathKey);
    if (saved != null && saved.isNotEmpty) {
      setState(() => _path = saved);
      await _openMap(saved);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['map'],
    );
    final pickedPath = result?.files.single.path;
    if (pickedPath == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pathKey, pickedPath);
    setState(() => _path = pickedPath);
    await _openMap(pickedPath);
  }

  Future<void> _openMap(String path) async {
    setState(() {
      _loading = true;
      _error = null;
      _subFileCount = null;
    });

    try {
      final mapFile = await Mapfile.createFromFile(filename: path);
      final info = mapFile.getMapHeaderInfo();
      final count = info.numberOfSubFiles;
      _mapFile?.dispose();
      _mapFile = mapFile;
      setState(() => _subFileCount = count);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _mapFile?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: _pickFile,
              child: const Text('Выбрать карту'),
            ),
            const SizedBox(height: 16),
            if (_path != null) Text('Файл: $_path'),
            const SizedBox(height: 16),
            if (_loading) const CircularProgressIndicator(),
            if (!_loading && _subFileCount != null)
              Text('Загружено объектов: $_subFileCount'),
            if (!_loading && _error != null)
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