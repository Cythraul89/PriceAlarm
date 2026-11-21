import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/error_view.dart';
import 'items_provider.dart';
import 'widgets/item_card.dart';

const double _kMaxCardWidth = 420;

class ItemsScreen extends ConsumerStatefulWidget {
  const ItemsScreen({super.key});

  @override
  ConsumerState<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends ConsumerState<ItemsScreen> {
  bool _isRefreshing = false;

  @override
  Widget build(BuildContext context) {
    final overviews = ref.watch(itemOverviewsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('PriceAlarm'),
        actions: [
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              tooltip: 'Check all now',
              icon: const Icon(Icons.refresh),
              onPressed: _checkAll,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add item',
        onPressed: () => context.go('/items/new'),
        child: const Icon(Icons.add),
      ),
      body: overviews.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e),
        data: (list) => list.isEmpty
            ? const _EmptyState()
            // A Wrap instead of a fixed-extent grid: card height follows its
            // content, so larger system font sizes cannot overflow it.
            : LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 8.0;
                  final available = constraints.maxWidth - 32;
                  final columns = (available / _kMaxCardWidth).ceil().clamp(
                    1,
                    6,
                  );
                  final cardWidth =
                      (available - spacing * (columns - 1)) / columns;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                    child: Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        for (final overview in list)
                          SizedBox(
                            width: cardWidth,
                            child: ItemCard(
                              overview: overview,
                              onTap: () =>
                                  context.go('/items/${overview.item.id}'),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _checkAll() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      await ref.read(itemActionsProvider).checkAll();
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('No items yet — add a product to watch.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => context.go('/items/new'),
            icon: const Icon(Icons.add),
            label: const Text('Add item'),
          ),
        ],
      ),
    ),
  );
}
