import 'dart:io';

import 'package:path/path.dart' as p;

/// Source assets are immutable. Deletion is deferred while a snapshot copies.
class SourceFilePins {
  static final _counts = <String, int>{};
  static final _deferred = <String>{};
  static void pin(String path) {
    final key = p.normalize(path);
    _counts[key] = (_counts[key] ?? 0) + 1;
  }

  static Future<void> release(String path) async {
    final key = p.normalize(path), count = _counts[p.normalize(path)] ?? 0;
    if (count > 1) {
      _counts[key] = count - 1;
      return;
    }
    _counts.remove(key);
    if (_deferred.remove(key)) await delete(File(key));
  }

  static Future<void> delete(File file) async {
    final key = p.normalize(file.path);
    if (_counts.containsKey(key)) {
      _deferred.add(key);
      return;
    }
    if (await file.exists()) await file.delete();
  }
}
