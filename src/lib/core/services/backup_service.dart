import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../database/app_database.dart';

/// Local ZIP export/import (REQUIREMENTS 6.4.3). The archive holds one
/// `data.json` with a format version, so a future schema can migrate it.
class BackupService {
  BackupService({required this.db});

  final AppDatabase db;

  static const kFormatVersion = 1;
  static const _entryName = 'data.json';

  Future<Uint8List> export() async {
    final data = await db.exportAll();
    final json = jsonEncode({'formatVersion': kFormatVersion, ...data});
    final archive = Archive()..addFile(ArchiveFile.string(_entryName, json));
    return ZipEncoder().encodeBytes(archive);
  }

  /// Replaces all data. Throws [FormatException] for a file that is not a
  /// PriceAlarm backup — the caller shows the message.
  Future<({int items, int offers, int checks})> import(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('Not a ZIP file');
    }
    final entry = archive.findFile(_entryName);
    if (entry == null) {
      throw const FormatException('No data.json in the archive');
    }
    final data = jsonDecode(utf8.decode(entry.content));
    if (data is! Map<String, dynamic> ||
        data['formatVersion'] != kFormatVersion) {
      throw const FormatException('Unsupported backup format');
    }
    return db.importAll(data);
  }

  static String fileName(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'pricealarm_${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.zip';
  }
}
