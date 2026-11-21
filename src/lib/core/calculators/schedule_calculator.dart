import '../models/item.dart';

/// Daily schedule maths (REQUIREMENTS 5.1). Pure: `now` is always passed in.
///
/// `checkTime` is a local wall-clock time. Instants are built with the
/// local `DateTime` constructor, so on a daylight-saving transition a
/// non-existent or repeated wall time resolves the way the Dart runtime
/// resolves it for the platform time zone.
abstract final class ScheduleCalculator {
  /// The most recent due instant at or before [now].
  static DateTime latestDue(int checkTime, DateTime now) {
    final local = now.toLocal();
    final today = _at(local, checkTime, dayOffset: 0);
    return today.isAfter(local) ? _at(local, checkTime, dayOffset: -1) : today;
  }

  /// The first due instant strictly after [now].
  static DateTime nextDue(int checkTime, DateTime now) {
    final local = now.toLocal();
    final today = _at(local, checkTime, dayOffset: 0);
    return today.isAfter(local) ? today : _at(local, checkTime, dayOffset: 1);
  }

  /// An item is due when its latest due instant lies after its last run.
  /// A never-run item counts from its creation, so creating an item at
  /// 10:00 with check time 08:00 does not trigger an immediate catch-up.
  static bool isDue(Item item, DateTime now) {
    if (!item.enabled) return false;
    final reference = item.lastRunAt ?? item.createdAt;
    return latestDue(item.checkTime, now).isAfter(reference);
  }

  static List<Item> dueItems(Iterable<Item> items, DateTime now) =>
      items.where((item) => isDue(item, now)).toList();

  /// Earliest upcoming due instant over all enabled items; `null` if none.
  static DateTime? nextDueOverall(Iterable<Item> items, DateTime now) {
    DateTime? earliest;
    for (final item in items.where((i) => i.enabled)) {
      final next = nextDue(item.checkTime, now);
      if (earliest == null || next.isBefore(earliest)) earliest = next;
    }
    return earliest;
  }

  static DateTime _at(DateTime day, int checkTime, {required int dayOffset}) =>
      DateTime(
        day.year,
        day.month,
        day.day + dayOffset,
        checkTime ~/ 60,
        checkTime % 60,
      );
}
