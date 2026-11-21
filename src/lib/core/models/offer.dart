import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

import 'enums.dart';

class Offer extends Equatable {
  const Offer({
    required this.id,
    required this.itemId,
    required this.url,
    required this.shopName,
    required this.fetchMode,
    this.resolvedMethod,
    this.lastPrice,
    this.lastCurrency,
    this.lastAvailability,
    this.lastStatus,
    this.lastError,
    this.lastCheckedAt,
  });

  final String id;
  final String itemId;
  final String url;
  final String shopName;
  final FetchMode fetchMode;
  final FetchMethod? resolvedMethod;
  final Decimal? lastPrice;
  final String? lastCurrency;

  /// schema.org availability as read from the page, e.g. `InStock`.
  /// Informational only in v0.1.
  final String? lastAvailability;
  final CheckStatus? lastStatus;
  final String? lastError;

  /// UTC.
  final DateTime? lastCheckedAt;

  /// True when a check of this offer can only succeed with a WebView —
  /// used to defer such offers out of the Android background run.
  bool get needsWebView =>
      fetchMode == FetchMode.webview ||
      (fetchMode == FetchMode.auto && resolvedMethod == FetchMethod.webview);

  @override
  List<Object?> get props => [
    id,
    itemId,
    url,
    shopName,
    fetchMode,
    resolvedMethod,
    lastPrice,
    lastCurrency,
    lastAvailability,
    lastStatus,
    lastError,
    lastCheckedAt,
  ];
}
