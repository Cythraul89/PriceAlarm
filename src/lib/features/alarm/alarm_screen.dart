import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/calculators/alarm_evaluator.dart';
import '../../core/models/enums.dart';
import '../../core/providers.dart';
import '../../core/services/alarm_controller.dart';
import '../../core/utils/formatters.dart';
import '../item_detail/item_detail_provider.dart';

/// Full-screen alarm (REQUIREMENTS 5.3.2). Shown while an alarm rings, and
/// after a launch from a ringing Android notification.
class AlarmScreen extends ConsumerStatefulWidget {
  const AlarmScreen({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends ConsumerState<AlarmScreen> {
  bool _stopped = false;

  String get itemId => widget.itemId;

  /// Idempotent: the buttons stop explicitly, and the following pop must
  /// not stop (and cancel the notification) a second time.
  Future<void> _stop() async {
    if (_stopped) return;
    _stopped = true;
    await ref.read(alarmControllerProvider).stop(itemId: itemId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final controller = ref.watch(alarmControllerProvider);
    final details = _details(controller.current);

    return PopScope(
      // Leaving the screen by back gesture must also silence the alarm.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _stop();
      },
      child: Scaffold(
        backgroundColor: scheme.errorContainer,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.alarm,
                      size: 96,
                      color: scheme.onErrorContainer,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Price alarm',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      details.title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                    ),
                    if (details.priceLine != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        details.priceLine!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: scheme.onErrorContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    if (details.targetLine != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        details.targetLine!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: scheme.onErrorContainer,
                        ),
                      ),
                    ],
                    const SizedBox(height: 48),
                    SizedBox(
                      height: 72,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.error,
                          foregroundColor: scheme.onError,
                          textStyle: theme.textTheme.headlineSmall,
                        ),
                        onPressed: () async {
                          await _stop();
                          if (context.mounted) _leave(context);
                        },
                        icon: const Icon(Icons.alarm_off, size: 32),
                        label: const Text('Stop'),
                      ),
                    ),
                    if (itemId != kTestAlarmItemId) ...[
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () async {
                          await _stop();
                          if (context.mounted) context.go('/items/$itemId');
                        },
                        child: const Text('Stop and show item'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Prefers the in-memory alarm; after a launch from a notification only
  /// the database is available.
  _AlarmDetails _details(ActiveAlarm? current) {
    if (current != null && current.itemId == itemId) {
      return _AlarmDetails(
        title: current.itemName,
        priceLine:
            '${formatMoney(current.price, current.currency)} '
            'at ${current.shopName}',
        targetLine:
            'Target ${formatMoney(current.targetPrice, current.currency)}',
      );
    }
    final item = ref.watch(itemProvider(itemId)).valueOrNull;
    if (item == null) return const _AlarmDetails(title: 'Price alarm');
    final offers = ref.watch(itemOffersProvider(itemId)).valueOrNull ?? [];
    final best = AlarmEvaluator.bestKnown(item.currency, [
      for (final o in offers)
        if (o.lastStatus == CheckStatus.ok)
          (shopName: o.shopName, price: o.lastPrice, currency: o.lastCurrency),
    ]);
    return _AlarmDetails(
      title: item.name,
      priceLine: best == null
          ? null
          : '${formatMoney(best.price, item.currency)} at ${best.shop}',
      targetLine: 'Target ${formatMoney(item.targetPrice, item.currency)}',
    );
  }

  void _leave(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/items');
    }
  }
}

class _AlarmDetails {
  const _AlarmDetails({required this.title, this.priceLine, this.targetLine});

  final String title;
  final String? priceLine;
  final String? targetLine;
}
