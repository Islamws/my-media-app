import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ResumeStore {
  static Map<String, int> _data = {};
  static bool _loaded = false;
  static File? _file;

  static Future<void> load() async {
    if (_loaded) return;
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/video_positions.json');
    try {
      if (await _file!.exists()) {
        final m = jsonDecode(await _file!.readAsString()) as Map;
        _data = m.map((k, v) => MapEntry(k as String, v as int));
      }
    } catch (_) {}
    _loaded = true;
  }

  static int? get(String path) => _data[path];

  static Future<void> put(String path, Duration pos, Duration dur) async {
    final ms = pos.inMilliseconds;
    final total = dur.inMilliseconds;
    if (total <= 0) return;
    if (ms < 5000 || ms > total - 10000) {
      _data.remove(path);
    } else {
      _data[path] = ms;
    }
    try {
      await _file?.writeAsString(jsonEncode(_data));
    } catch (_) {}
  }
}
