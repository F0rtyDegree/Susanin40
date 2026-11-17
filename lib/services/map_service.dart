import 'package:mapsforge_flutter_mapfile/mapfile.dart';

class MapService {
  static final MapService instance = MapService._internal();
  MapService._internal();

  Mapfile? _mapFile;

  Mapfile? get mapFile => _mapFile;
  bool get isLoaded => _mapFile != null;

  Future<bool> open(String path) async {
    close();
    try {
      final file = await Mapfile.createFromFile(filename: path);
      await file.getBoundingBox();
      _mapFile = file;
      return true;
    } catch (e) {
      return false;
    }
  }

  void close() {
    _mapFile?.dispose();
    _mapFile = null;
  }
}