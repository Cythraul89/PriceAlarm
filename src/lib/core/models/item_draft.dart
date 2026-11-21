import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

import 'enums.dart';

/// User input of the add/edit form, saved atomically with its offers.
class ItemDraft extends Equatable {
  const ItemDraft({
    this.id,
    required this.name,
    required this.targetPrice,
    required this.checkTime,
    required this.enabled,
    required this.offers,
  });

  /// `null` for a new item.
  final String? id;
  final String name;
  final Decimal targetPrice;

  /// Minutes since local midnight.
  final int checkTime;
  final bool enabled;
  final List<OfferDraft> offers;

  @override
  List<Object?> get props => [id, name, targetPrice, checkTime, enabled, offers];
}

class OfferDraft extends Equatable {
  const OfferDraft({
    this.id,
    required this.url,
    required this.shopName,
    required this.fetchMode,
  });

  /// `null` for a new offer.
  final String? id;
  final String url;
  final String shopName;
  final FetchMode fetchMode;

  @override
  List<Object?> get props => [id, url, shopName, fetchMode];
}
