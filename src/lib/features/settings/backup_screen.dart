import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/services/backup_service.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Backup & restore')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Export writes all items, offers and price history to a ZIP file. '
          'Import replaces all current data with the content of such a file.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _export,
          icon: const Icon(Icons.upload_file),
          label: const Text('Export'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _import,
          icon: const Icon(Icons.download),
          label: const Text('Import'),
        ),
        if (_busy) ...[
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator()),
        ],
      ],
    ),
  );

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final bytes = await ref.read(backupServiceProvider).export();
      final saved = await FilePicker.saveFile(
        fileName: BackupService.fileName(DateTime.now()),
        bytes: bytes,
        mimeType: 'application/zip',
        dialogTitle: 'Save backup',
      );
      _show(saved == null ? 'Export cancelled' : 'Backup saved');
    } catch (e, st) {
      ref.read(logServiceProvider).error('Export failed', e, st);
      _show('Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Select backup',
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (files.isEmpty || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Replace all data?'),
        content: const Text(
          'All current items, offers and history are deleted and replaced '
          'by the backup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final bytes = await files.first.readAsBytes();
      final counts = await ref.read(backupServiceProvider).import(bytes);
      await ref.read(schedulerServiceProvider).reschedule();
      _show(
        'Imported ${counts.items} items, ${counts.offers} offers, '
        '${counts.checks} checks',
      );
    } on FormatException catch (e) {
      _show('Import failed: ${e.message}');
    } catch (e, st) {
      ref.read(logServiceProvider).error('Import failed', e, st);
      _show('Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
