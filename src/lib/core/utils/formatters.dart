import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';

// The locale data for de_CH ships with package:intl (no async init needed
// for NumberFormat/DateFormat patterns used here).
final _money = NumberFormat('#,##0.00', 'de_CH');
final _dateTime = DateFormat('dd.MM. HH:mm');
final _time = DateFormat('HH:mm');

/// `CHF 2’209.00`. `toDouble()` only at this display boundary.
String formatMoney(Decimal value, String currency) =>
    '$currency ${_money.format(value.toDouble())}';

/// Local time-of-day from minutes since midnight: `08:00`.
String formatCheckTime(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

/// `21.11. 08:03` in local time.
String formatDateTime(DateTime value) => _dateTime.format(value.toLocal());

/// Relative day + time for an upcoming local instant: `today 08:00`.
String formatUpcoming(DateTime value, DateTime now) {
  final local = value.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = day.difference(today).inDays;
  final label = switch (diff) {
    0 => 'today',
    1 => 'tomorrow',
    _ => DateFormat('dd.MM.').format(local),
  };
  return '$label ${_time.format(local)}';
}
