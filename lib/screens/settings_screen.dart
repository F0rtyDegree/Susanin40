import 'package:flutter/material.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mapsforge_flutter_mapfile/mapfile.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _pathKey = 'map_file_path';

  Mapfile? _mapFile;
  String? _path;
  bool _isPickingFile = false;
  bool _loading = false;
  bool _isLoaded = false;
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
      if (await File(saved).exists()) {
        setState(() => _path = saved);
        await _openMap(saved);
      } else {
        await prefs.remove(_pathKey);
      }
    }
  }

  Future<void> _pickFile() async {
    setState(() {
      _isPickingFile = true;
      _error = null;
      _subFileCount = null;
      _isLoaded = false;
    });

    final status = await Permission.manageExternalStorage.request();

    if (!mounted) return;

    if (!status.isGranted) {
      setState(() {
        _isPickingFile = false;
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
      setState(() {
        _isPickingFile = false;
        _error = 'Не удалось получить доступ к хранилищу';
      });
      return;
    }

    if (!mounted) return;

    final String? pickedPath = await FilesystemPicker.open(
      title: 'Выберите файл карты (.map)',
      context: context,
      rootDirectory: rootDirectory,
      fsType: FilesystemType.file,
      allowedExtensions: ['.map'],
      fileTileSelectMode: FileTileSelectMode.wholeTile,
    );

    if (!mounted) return;

    if (pickedPath == null) {
      setState(() => _isPickingFile = false);
      return;
    }

    setState(() {
      _isPickingFile = false;
    });

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
      _isLoaded = false;
    });

    try {
      final mapFile = await Mapfile.createFromFile(filename: path);
      await mapFile.getBoundingBox();
      final info = mapFile.getMapHeaderInfo();
      final count = info.numberOfSubFiles;

      if (!mounted) {
        mapFile.dispose();
        return;
      }

      _mapFile?.dispose();
      _mapFile = mapFile;
      setState(() {
        _subFileCount = count;
        _isLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
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
              onPressed: (_isPickingFile || _loading) ? null : _pickFile,
              child: Text(
                _isPickingFile
                    ? 'Открытие...'
                    : _loading
                        ? 'Карта загружается...'
                        : _isLoaded
                            ? 'Карта загружена'
                            : 'Выбрать карту',
              ),
            ),
            const SizedBox(height: 16),
            if (_path != null) Text('Файл: $_path'),
            const SizedBox(height: 16),
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