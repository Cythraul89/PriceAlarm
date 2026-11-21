import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

class Item extends Equatable {
  const Item({
    required this.id,
    required this.name,
    required this.targetPrice,
    required this.currency,
    required this.checkTime,
    required this.enabled,
    required this.alarmActive,
    required this.lastRunAt,
    required this.createdAt,
    this.lastAlarmAt,
  });

  final String id;
  final String name;
  final Decimal targetPrice;
  final String currency;

  /// Minutes since local midnight (0–1439).
  final int checkTime;
  final bool enabled;
  final bool alarmActive;

  /// UTC.
  final DateTime? lastRunAt;

  /// UTC.
  final DateTime createdAt;

  /// When the alarm last rang (UTC); at most one ring per daily cycle.
  final DateTime? lastAlarmAt;

  @override
  List<Object?> get props => [
    id,
    name,
    targetPrice,
    currency,
    checkTime,
    enabled,
    alarmActive,
    lastRunAt,
    createdAt,
    lastAlarmAt,
  ];
}
