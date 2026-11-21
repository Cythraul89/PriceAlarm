import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Append-only file logger, trimmed to [kMaxLogLines] at startup.
///
/// Writes synchronously so a hard kill (or a background worker the OS stops)
/// still leaves its last lines on disk.
class LogService {
  LogService(this.file);

  final File file;

  static const kMaxLogLines = 2000;

  /// The app's log file in the application support directory — the same
  /// file from the UI and the background isolate.
  static Future<LogService> open() async {
    final dir = await getApplicationSupportDirectory();
    return LogService(File(p.join(dir.path, 'price_alarm.log')));
  }

  void info(String message) => _write('INFO ', message);

  void warn(String message, [Object? error]) =>
      _write('WARN ', error == null ? message : '$message: $error');

  void error(String message, Object error, [StackTrace? stackTrace]) =>
      _write('ERROR', '$message: $error${stackTrace == null ? '' : '\n$stackTrace'}');

  String read() => file.existsSync() ? file.readAsStringSync() : '';

  void clear() {
    if (file.existsSync()) file.writeAsStringSync('');
  }

  void trim() {
    if (!file.existsSync()) return;
    final lines = file.readAsLinesSync();
    if (lines.length <= kMaxLogLines) return;
    file.writeAsStringSync(
      '${lines.sublist(lines.length - kMaxLogLines).join('\n')}\n',
    );
  }

  void _write(String level, String message) {
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        '${DateTime.now().toIso8601String()} $level $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } on FileSystemException {
      // Logging must never take the app down; there is nowhere left to
      // report this to.
    }
  }
}
