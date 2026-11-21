import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/offer.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/status_icon.dart';

class OfferTile extends StatelessWidget {
  const OfferTile({super.key, required this.offer, required this.currency});

  final Offer offer;

  /// Item currency; offers in another currency are flagged.
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final price = offer.lastPrice;
    final foreign =
        offer.lastCurrency != null && offer.lastCurrency != currency;
    final current = offer.lastStatus == CheckStatus.ok;

    final details = <String>[
      checkStatusLabel(offer.lastStatus),
      if (offer.lastStatus != null && !current && offer.lastError != null)
        offer.lastError!,
      if (offer.resolvedMethod != null) offer.resolvedMethod!.name,
      if (current && offer.lastAvailability != null) offer.lastAvailability!,
      if (foreign) 'not compared (${offer.lastCurrency})',
    ];

    return ListTile(
      leading: CheckStatusIcon(status: offer.lastStatus, size: 24),
      title: Row(
        children: [
          Expanded(child: Text(offer.shopName)),
          Text(
            price == null
                ? '—'
                : formatMoney(price, offer.lastCurrency ?? currency),
            style: theme.textTheme.titleMedium?.copyWith(
              // A price from an earlier successful check is shown muted
              // so it is not mistaken for the current one.
              color: current ? null : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      subtitle: Text(
        '${details.join(' · ')}\n'
        '${offer.lastCheckedAt == null ? 'never checked' : formatDateTime(offer.lastCheckedAt!)}',
      ),
      isThreeLine: true,
      trailing: IconButton(
        tooltip: 'Open in browser',
        icon: const Icon(Icons.open_in_new),
        onPressed: () => launchUrl(
          Uri.parse(offer.url),
          mode: LaunchMode.externalApplication,
        ),
      ),
    );
  }
}
