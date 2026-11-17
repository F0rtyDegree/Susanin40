import 'package:flutter/material.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import '../services/map_service.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  final AppTheme currentTheme;
  final Function(AppTheme) onThemeChanged;

  const SettingsScreen({super.key, required this.currentTheme, required this.onThemeChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _pathKey = 'map_file_path';

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

    final success = await MapService.instance.open(path);
    if (!mounted) return;

    if (success) {
      final info = MapService.instance.mapFile!.getMapHeaderInfo();
      final count = info.numberOfSubFiles;
      setState(() {
        _subFileCount = count;
        _isLoaded = true;
      });
    } else {
      setState(() => _error = 'Ошибка открытия карты');
    }

    if (mounted) {
      setState(() => _loading = false);
    }
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
            const SizedBox(height: 32),
            const Text('Оформление', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButton<AppTheme>(
              value: widget.currentTheme,
              isExpanded: true,
              items: AppTheme.values.map((theme) {
                String name;
                switch (theme) {
                  case AppTheme.white: name = 'Белый'; break;
                  case AppTheme.black: name = 'Чёрный'; break;
                  case AppTheme.grey: name = 'Серый'; break;
                }
                return DropdownMenuItem(value: theme, child: Text(name));
              }).toList(),
              onChanged: (v) {
                if (v != null) widget.onThemeChanged(v);
              },
            ),
          ],
        ),
      ),
    );
  }
}