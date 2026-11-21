import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/item_draft.dart';
import '../../core/providers.dart';
import '../../core/utils/formatters.dart';
import '../items/items_provider.dart';
import 'widgets/offer_editor.dart';

/// Add (itemId == null) or edit an item with its offers.
class ItemEditScreen extends ConsumerStatefulWidget {
  const ItemEditScreen({super.key, this.itemId});

  final String? itemId;

  @override
  ConsumerState<ItemEditScreen> createState() => _ItemEditScreenState();
}

class _ItemEditScreenState extends ConsumerState<ItemEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _target = TextEditingController();
  final _offers = <OfferFormEntry>[];
  int _checkTime = 480;
  bool _enabled = true;
  bool _alarmActive = false;
  String _currency = 'CHF';
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;

  bool get _isNew => widget.itemId == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    for (final o in _offers) {
      o.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (_isNew) {
      _offers.add(OfferFormEntry());
      setState(() => _loading = false);
      return;
    }
    final db = ref.read(appDatabaseProvider);
    final item = await db.itemsDao.findById(widget.itemId!);
    final offers = await db.offersDao.getByItem(widget.itemId!);
    if (!mounted) return;
    if (item == null) {
      context.go('/items');
      return;
    }
    _name.text = item.name;
    _target.text = item.targetPrice.toStringAsFixed(2);
    _checkTime = item.checkTime;
    _enabled = item.enabled;
    _alarmActive = item.alarmActive;
    _currency = item.currency;
    _offers.addAll([
      for (final o in offers)
        OfferFormEntry(
          id: o.id,
          url: o.url,
          shopName: o.shopName,
          mode: o.fetchMode,
        ),
    ]);
    setState(() => _loading = false);
  }

  void _markDirty() => setState(() => _dirty = true);

  @override
  Widget build(BuildContext context) {
    final webViewAvailable = ref.watch(webViewPageFetcherProvider) != null;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          setState(() => _dirty = false);
          _leave();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () async {
              if (!_dirty || await _confirmDiscard()) _leave();
            },
          ),
          title: Text(_isNew ? 'New item' : 'Edit item'),
          actions: [
            TextButton(
              onPressed: _loading || _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        TextFormField(
                          controller: _name,
                          decoration: const InputDecoration(labelText: 'Name'),
                          maxLength: 120,
                          validator: (v) =>
                              (v ?? '').trim().isEmpty ? 'Required' : null,
                          onChanged: (_) => _markDirty(),
                        ),
                        TextFormField(
                          controller: _target,
                          decoration: InputDecoration(
                            labelText: 'Target price ($_currency)',
                            helperText: _alarmActive
                                ? 'Changing the target re-arms the alarm'
                                : null,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: _validateTarget,
                          onChanged: (_) => _markDirty(),
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Daily check time'),
                          trailing: Text(
                            formatCheckTime(_checkTime),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          onTap: _pickTime,
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Enabled'),
                          value: _enabled,
                          onChanged: (v) {
                            _enabled = v;
                            _markDirty();
                          },
                        ),
                        const Divider(),
                        Text(
                          'Offers',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        for (final entry in _offers)
                          OfferEditor(
                            key: ObjectKey(entry),
                            entry: entry,
                            currency: _currency,
                            webViewAvailable: webViewAvailable,
                            canRemove: _offers.length > 1,
                            onChanged: _markDirty,
                            onTest: () => _test(entry),
                            onRemove: () {
                              _offers.remove(entry);
                              entry.dispose();
                              _markDirty();
                            },
                            duplicateUrl: (url) => _offers.any(
                              (o) => o != entry && o.url.text.trim() == url,
                            ),
                          ),
                        TextButton.icon(
                          onPressed: () {
                            _offers.add(OfferFormEntry());
                            _markDirty();
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Add offer URL'),
                        ),
                        if (!_isNew) ...[
                          const Divider(),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.error,
                            ),
                            onPressed: _delete,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Delete item'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  String? _validateTarget(String? value) {
    final text = (value ?? '').trim().replaceAll(',', '.');
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text)) {
      return 'Enter an amount with at most 2 decimals';
    }
    if (Decimal.parse(text) <= Decimal.zero) return 'Must be greater than 0';
    return null;
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _checkTime ~/ 60, minute: _checkTime % 60),
    );
    if (picked == null || !mounted) return;
    _checkTime = picked.hour * 60 + picked.minute;
    _markDirty();
  }

  Future<void> _test(OfferFormEntry entry) async {
    final url = entry.url.text.trim();
    if (url.isEmpty) return;
    setState(() => entry.testing = true);
    final result = await ref
        .read(priceCheckServiceProvider)
        .testOffer(url, entry.mode);
    if (!mounted) return;
    setState(() {
      entry.testing = false;
      entry.testResult = result;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final draft = ItemDraft(
      id: widget.itemId,
      name: _name.text.trim(),
      targetPrice: Decimal.parse(_target.text.trim().replaceAll(',', '.')),
      checkTime: _checkTime,
      enabled: _enabled,
      offers: [
        for (final o in _offers)
          OfferDraft(
            id: o.id,
            url: o.url.text.trim(),
            shopName: o.shopName.text.trim(),
            fetchMode: o.mode,
          ),
      ],
    );
    try {
      final id = await ref.read(itemActionsProvider).save(draft);
      if (!mounted) return;
      _dirty = false;
      context.go('/items/$id');
    } catch (e, st) {
      ref.read(logServiceProvider).error('Saving item failed', e, st);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saving failed: $e')));
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete item?'),
        content: const Text('Its offers and price history are deleted too.'),
        actions: [
          TextButton(
            // The dialog's own context — the outer one would pop the screen.
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(itemActionsProvider).delete(widget.itemId!);
    if (!mounted) return;
    _dirty = false;
    context.go('/items');
  }

  Future<bool> _confirmDiscard() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard changes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _leave() =>
      context.go(_isNew ? '/items' : '/items/${widget.itemId}');
}
