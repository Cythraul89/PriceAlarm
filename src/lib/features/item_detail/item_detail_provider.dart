import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/item.dart';
import '../../core/models/offer.dart';
import '../../core/models/price_check.dart';
import '../../core/providers.dart';

/// History page size (REQUIREMENTS / SCREENS §2).
const kHistoryPageSize = 50;

final itemProvider = StreamProvider.autoDispose.family<Item?, String>(
  (ref, id) => ref.watch(appDatabaseProvider).itemsDao.watchById(id),
);

final itemOffersProvider = StreamProvider.autoDispose
    .family<List<Offer>, String>(
      (ref, itemId) =>
          ref.watch(appDatabaseProvider).offersDao.watchByItem(itemId),
    );

final itemHistoryProvider = StreamProvider.autoDispose
    .family<List<PriceCheck>, ({String itemId, int limit})>(
      (ref, key) => ref
          .watch(appDatabaseProvider)
          .priceChecksDao
          .watchByItem(key.itemId, limit: key.limit),
    );
