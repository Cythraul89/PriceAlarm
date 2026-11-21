import 'package:material_ui/material_ui.dart';

import '../../../core/models/check_outcome.dart';
import '../../../core/models/enums.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/shop_name.dart';
import '../../../core/widgets/status_icon.dart';

/// Mutable form state of one offer row; owned by the edit screen.
class OfferFormEntry {
  OfferFormEntry({this.id, String url = '', String shopName = '', this.mode = FetchMode.auto})
    : url = TextEditingController(text: url),
      shopName = TextEditingController(text: shopName);

  final String? id;
  final TextEditingController url;
  final TextEditingController shopName;
  FetchMode mode;
  CheckOutcome? testResult;
  bool testing = false;

  void dispose() {
    url.dispose();
    shopName.dispose();
  }
}

class OfferEditor extends StatelessWidget {
  const OfferEditor({
    super.key,
    required this.entry,
    required this.currency,
    required this.webViewAvailable,
    required this.canRemove,
    required this.onChanged,
    required this.onTest,
    required this.onRemove,
    required this.duplicateUrl,
  });

  final OfferFormEntry entry;
  final String currency;
  final bool webViewAvailable;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onTest;
  final VoidCallback onRemove;

  /// Returns true when the URL is used by another offer of this item.
  final bool Function(String url) duplicateUrl;

  @override
  Widget build(BuildContext context) {
    final result = entry.testResult;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: entry.url,
              decoration: const InputDecoration(labelText: 'Offer URL'),
              keyboardType: TextInputType.url,
              validator: (value) {
                final error = validateOfferUrl(value ?? '');
                if (error != null) return error;
                if (duplicateUrl(value!.trim())) return 'Duplicate URL';
                return null;
              },
              onChanged: (value) {
                // Auto-fill the shop name until the user edits it.
                final derived = shopNameFromUrl(value);
                if (derived.isNotEmpty) entry.shopName.text = derived;
                entry.testResult = null;
                onChanged();
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: entry.shopName,
                    decoration: const InputDecoration(labelText: 'Shop'),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Required' : null,
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<FetchMode>(
                  value: entry.mode,
                  onChanged: (mode) {
                    if (mode == null) return;
                    entry.mode = mode;
                    entry.testResult = null;
                    onChanged();
                  },
                  items: [
                    for (final mode in FetchMode.values)
                      DropdownMenuItem(
                        value: mode,
                        enabled: mode != FetchMode.webview || webViewAvailable,
                        child: Text(
                          mode == FetchMode.webview && !webViewAvailable
                              ? 'webview (n/a)'
                              : mode.name,
                        ),
                      ),
                  ],
                ),
                IconButton(
                  tooltip: 'Test fetch',
                  icon: entry.testing
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  onPressed: entry.testing ? null : onTest,
                ),
                IconButton(
                  tooltip: 'Remove offer',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: canRemove ? onRemove : null,
                ),
              ],
            ),
            if (result != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  CheckStatusIcon(status: result.status),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_describe(result))),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _describe(CheckOutcome r) {
    final method = r.method == null ? '' : ' · ${r.method!.name}';
    if (r.status == CheckStatus.ok) {
      return '${formatMoney(r.price!, r.currency ?? currency)}'
          '${r.availability == null ? '' : ' · ${r.availability}'}$method';
    }
    return '${checkStatusLabel(r.status)}: ${r.error ?? ''}$method';
  }
}
