import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

import 'enums.dart';

/// Result of checking one offer once (possibly after an auto escalation).
class CheckOutcome extends Equatable {
  const CheckOutcome({
    required this.status,
    this.method,
    this.price,
    this.currency,
    this.availability,
    this.error,
  });

  final CheckStatus status;

  /// The transport that produced this outcome; `null` when nothing could be
  /// attempted (e.g. `unsupported`).
  final FetchMethod? method;
  final Decimal? price;
  final String? currency;
  final String? availability;

  /// Short human-readable reason when [status] is not `ok`.
  final String? error;

  @override
  List<Object?> get props => [
    status,
    method,
    price,
    currency,
    availability,
    error,
  ];
}
