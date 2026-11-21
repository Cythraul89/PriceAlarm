import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/calculators/alarm_evaluator.dart';
import '../../core/models/enums.dart';
import '../../core/models/item.dart';
import '../../core/models/offer.dart';
import '../../core/models/price_check.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/error_view.dart';
import '../../core/widgets/status_icon.dart';
import '../items/items_provider.dart';
import 'item_detail_provider.dart';
import 'widgets/offer_tile.dart';

class ItemDetailScreen extends ConsumerStatefulWidget {
  const ItemDetailScreen({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends ConsumerState<ItemDetailScreen> {
  bool _checking = false;
  int _historyLimit = kHistoryPageSize;

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(itemProvider(widget.itemId));
    return item.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(appBar: AppBar(), body: ErrorView(error: e)),
      data: (item) {
        if (item == null) {
          // Deleted (e.g. from the edit screen): leave once the frame is done.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) context.go('/items');
          });
          return const Scaffold();
        }
        return _buildItem(context, item);
      },
    );
  }

  Widget _buildItem(BuildContext context, Item item) {
    final offers = ref.watch(itemOffersProvider(item.id));
    final history = ref.watch(
      itemHistoryProvider((itemId: item.id, limit: _historyLimit)),
    );
    final summary = _Summary(
      item: item,
      offers: offers.valueOrNull ?? const [],
      checking: _checking,
      onCheckNow: () => _checkNow(item.id),
    );
    final offerList = offers.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e),
      data: (list) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final offer in list)
            OfferTile(offer: offer, currency: item.currency),
        ],
      ),
    );
    final historyList = history.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e),
      data: (list) => _HistoryList(
        checks: list,
        currency: item.currency,
        canLoadMore: list.length >= _historyLimit,
        onLoadMore: () =>
            setState(() => _historyLimit += kHistoryPageSize),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit),
            onPressed: () => context.go('/items/${item.id}/edit'),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 900) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                summary,
                const SizedBox(height: 16),
                const _SectionTitle('Offers'),
                offerList,
                const SizedBox(height: 16),
                const _SectionTitle('History'),
                historyList,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    summary,
                    const SizedBox(height: 16),
                    const _SectionTitle('Offers'),
                    offerList,
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [const _SectionTitle('History'), historyList],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _checkNow(String id) async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await ref.read(itemActionsProvider).checkNow(id);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.item,
    required this.offers,
    required this.checking,
    required this.onCheckNow,
  });

  final Item item;
  final List<Offer> offers;
  final bool checking;
  final VoidCallback onCheckNow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final best = AlarmEvaluator.bestKnown(item.currency, [
      for (final o in offers)
        if (o.lastStatus == CheckStatus.ok)
          (shopName: o.shopName, price: o.lastPrice, currency: o.lastCurrency),
    ]);
    final belowTarget = best != null && best.price <= item.targetPrice;
    final hint = _platformHint();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              best == null
                  ? 'Best  —'
                  : 'Best  ${formatMoney(best.price, item.currency)} '
                        '(${best.shop})',
              style: theme.textTheme.titleLarge?.copyWith(
                color: belowTarget ? Colors.green : null,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'Target ${formatMoney(item.targetPrice, item.currency)}',
                ),
                if (item.alarmActive) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.notifications_active,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  Text(
                    ' active',
                    style: TextStyle(color: theme.colorScheme.primary),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              item.enabled
                  ? 'Daily at ${formatCheckTime(item.checkTime)}'
                        '${item.lastRunAt == null ? '' : ' · last ${formatDateTime(item.lastRunAt!)}'}'
                  : 'Paused',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(hint, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: checking ? null : onCheckNow,
              icon: checking
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: const Text('Check now'),
            ),
          ],
        ),
      ),
    );
  }

  /// States the platform's timing limit instead of implying exact runs
  /// (REQUIREMENTS 5.1.4).
  static String? _platformHint() {
    if (Platform.isIOS) return 'On iOS, checks run when you open the app.';
    if (Platform.isAndroid) {
      return 'Runs on time with "Exact check time" allowed in Settings; '
          'otherwise Android may run it several minutes late.';
    }
    return 'Checks run while the app is open, or at the next start.';
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.checks,
    required this.currency,
    required this.canLoadMore,
    required this.onLoadMore,
  });

  final List<PriceCheck> checks;
  final String currency;
  final bool canLoadMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (checks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No checks yet.'),
      );
    }
    return Column(
      children: [
        for (final check in checks)
          ListTile(
            dense: true,
            leading: CheckStatusIcon(status: check.status),
            title: Text('${formatDateTime(check.checkedAt)}  ${check.shopName}'),
            trailing: Text(
              check.price == null
                  ? checkStatusLabel(check.status)
                  : formatMoney(check.price!, check.currency ?? currency),
            ),
          ),
        if (canLoadMore)
          TextButton(onPressed: onLoadMore, child: const Text('Show more')),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}
