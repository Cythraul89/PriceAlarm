import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

import 'enums.dart';

/// One history entry, joined with its offer's shop name for display.
class PriceCheck extends Equatable {
  const PriceCheck({
    required this.id,
    required this.offerId,
    required this.shopName,
    required this.checkedAt,
    required this.status,
    this.method,
    this.price,
    this.currency,
    this.availability,
    this.error,
  });

  final int id;
  final String offerId;
  final String shopName;

  /// UTC.
  final DateTime checkedAt;
  final CheckStatus status;
  final FetchMethod? method;
  final Decimal? price;
  final String? currency;
  final String? availability;
  final String? error;

  @override
  List<Object?> get props => [
    id,
    offerId,
    shopName,
    checkedAt,
    status,
    method,
    price,
    currency,
    availability,
    error,
  ];
}
