import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:price_alarm/core/calculators/schedule_calculator.dart';
import 'package:price_alarm/core/models/item.dart';

Item _item({
  String id = 'i1',
  int checkTime = 480,
  bool enabled = true,
  DateTime? lastRunAt,
  DateTime? createdAt,
}) => Item(
  id: id,
  name: id,
  targetPrice: Decimal.fromInt(100),
  currency: 'CHF',
  checkTime: checkTime,
  enabled: enabled,
  alarmActive: false,
  lastRunAt: lastRunAt,
  createdAt: createdAt ?? DateTime(2026, 1, 1),
);

void main() {
  // Local times throughout: checkTime is a wall-clock value.
  final morning = DateTime(2026, 11, 21, 7, 59);
  final afterCheck = DateTime(2026, 11, 21, 8, 0);

  group('ScheduleCalculator.latestDue / nextDue', () {
    test('before the check time, the latest due instant was yesterday', () {
      expect(
        ScheduleCalculator.latestDue(480, morning),
        DateTime(2026, 11, 20, 8, 0),
      );
      expect(
        ScheduleCalculator.nextDue(480, morning),
        DateTime(2026, 11, 21, 8, 0),
      );
    });

    test('exactly at the check time, today is due and tomorrow is next', () {
      expect(ScheduleCalculator.latestDue(480, afterCheck), afterCheck);
      expect(
        ScheduleCalculator.nextDue(480, afterCheck),
        DateTime(2026, 11, 22, 8, 0),
      );
    });

    test('rolls over month and year boundaries', () {
      expect(
        ScheduleCalculator.nextDue(0, DateTime(2026, 12, 31, 23, 30)),
        DateTime(2027, 1, 1, 0, 0),
      );
    });
  });

  group('ScheduleCalculator.isDue', () {
    test('due when the last run was before the latest due instant', () {
      final item = _item(lastRunAt: DateTime(2026, 11, 20, 8, 1));
      expect(ScheduleCalculator.isDue(item, DateTime(2026, 11, 21, 9)), isTrue);
    });

    test('not due when it already ran after today\'s due instant', () {
      final item = _item(lastRunAt: DateTime(2026, 11, 21, 8, 2));
      expect(
        ScheduleCalculator.isDue(item, DateTime(2026, 11, 21, 23)),
        isFalse,
      );
    });

    test('several missed days still mean a single catch-up', () {
      final item = _item(lastRunAt: DateTime(2026, 11, 1, 8, 1));
      final now = DateTime(2026, 11, 21, 9);
      expect(ScheduleCalculator.isDue(item, now), isTrue);
      // After that one run the item is no longer due.
      final afterRun = _item(lastRunAt: now);
      expect(ScheduleCalculator.isDue(afterRun, now), isFalse);
    });

    test('a never-run item counts from its creation time', () {
      final created = _item(createdAt: DateTime(2026, 11, 21, 10));
      expect(
        ScheduleCalculator.isDue(created, DateTime(2026, 11, 21, 11)),
        isFalse,
      );
      expect(
        ScheduleCalculator.isDue(created, DateTime(2026, 11, 22, 8, 0)),
        isTrue,
      );
    });

    test('a disabled item is never due', () {
      final item = _item(enabled: false, lastRunAt: DateTime(2026, 1, 1));
      expect(ScheduleCalculator.isDue(item, afterCheck), isFalse);
    });
  });

  group('ScheduleCalculator.nextDueOverall', () {
    test('returns the earliest upcoming instant over enabled items', () {
      final items = [
        _item(id: 'a', checkTime: 600),
        _item(id: 'b', checkTime: 420), // 07:00 → tomorrow from 07:59
        _item(id: 'c', checkTime: 485, enabled: false),
      ];
      expect(
        ScheduleCalculator.nextDueOverall(items, morning),
        DateTime(2026, 11, 21, 10, 0),
      );
    });

    test('returns null when nothing is enabled', () {
      expect(
        ScheduleCalculator.nextDueOverall([_item(enabled: false)], morning),
        isNull,
      );
    });
  });
}
