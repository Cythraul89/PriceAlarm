import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../items_provider.dart';

class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.overview, required this.onTap});

  final ItemOverview overview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = overview.item;
    final best = overview.bestPrice;
    final belowTarget = best != null && best <= item.targetPrice;
    final muted = !item.enabled;

    final (statusIcon, statusColor) = item.alarmActive
        ? (Icons.notifications_active, theme.colorScheme.primary)
        : overview.failingOffers > 0
        ? (Icons.warning_amber, theme.colorScheme.error)
        : (null, null);

    final subtitle = !item.enabled
        ? 'paused'
        : overview.failingOffers > 0
        ? '${overview.failingOffers} of ${overview.offers.length} offers '
              'failing · next ${formatUpcoming(overview.nextDue, DateTime.now())}'
        : '${overview.bestShop ?? 'no price yet'} · next '
              '${formatUpcoming(overview.nextDue, DateTime.now())}';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: muted ? 0.5 : 1,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (statusIcon != null) ...[
                      Icon(statusIcon, color: statusColor, size: 20),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        item.name,
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: best == null
                            ? '—'
                            : formatMoney(best, item.currency),
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: belowTarget ? Colors.green : null,
                        ),
                      ),
                      TextSpan(
                        text:
                            '   target '
                            '${formatMoney(item.targetPrice, item.currency)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
