import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  final _scroll = ScrollController();
  late String _content = ref.read(logServiceProvider).read();

  @override
  void initState() {
    super.initState();
    // Newest entries are at the bottom.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('App logs'),
      actions: [
        IconButton(
          tooltip: 'Share',
          icon: const Icon(Icons.share),
          onPressed: _content.isEmpty ? null : _share,
        ),
        IconButton(
          tooltip: 'Clear',
          icon: const Icon(Icons.delete_outline),
          onPressed: _content.isEmpty ? null : _clear,
        ),
      ],
    ),
    body: _content.isEmpty
        ? const Center(child: Text('The log is empty.'))
        : SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              _content,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
  );

  Future<void> _share() => SharePlus.instance.share(
    ShareParams(
      files: [XFile(ref.read(logServiceProvider).file.path)],
      subject: 'PriceAlarm log',
    ),
  );

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear the log?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    ref.read(logServiceProvider).clear();
    setState(() => _content = '');
  }
}
