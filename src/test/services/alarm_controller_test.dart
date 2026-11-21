import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:price_alarm/core/services/alarm_controller.dart';
import 'package:price_alarm/core/services/alarm_sound.dart';
import 'package:price_alarm/core/services/log_service.dart';
import 'package:price_alarm/core/services/price_check_service.dart';

class _FakeNotifications implements AlarmNotifier {
  final shown = <String>[];
  final cancelled = <String>[];
  bool fail = false;

  @override
  Future<void> showAlarm({
    required String itemId,
    required String itemName,
    required Decimal price,
    required Decimal targetPrice,
    required String currency,
    required String shopName,
  }) async {
    if (fail) throw StateError('permission denied');
    shown.add(itemId);
  }

  @override
  Future<void> cancelAlarm(String itemId) async => cancelled.add(itemId);
}

class _FakeSound implements AlarmSound {
  int starts = 0;
  int stops = 0;
  bool get playing => starts > stops;

  @override
  Future<void> start() async => starts++;

  @override
  Future<void> stop() async => stops++;
}

void main() {
  late Directory tmp;
  late _FakeNotifications notifications;
  late _FakeSound sound;
  late AlarmController controller;

  AlarmController create({Duration ring = kAlarmRingDuration}) =>
      AlarmController(
        notifications: notifications,
        sound: sound,
        log: LogService(File('${tmp.path}/test.log')),
        ringDuration: ring,
      );

  Future<void> ring(String itemId) => controller.showAlarm(
    itemId: itemId,
    itemName: 'R9700',
    price: Decimal.parse('1999'),
    targetPrice: Decimal.parse('2000'),
    currency: 'CHF',
    shopName: 'Brack',
  );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('price_alarm_test');
    notifications = _FakeNotifications();
    sound = _FakeSound();
    controller = create();
  });

  tearDown(() async {
    controller.dispose();
    await tmp.delete(recursive: true);
  });

  group('AlarmController', () {
    test('ringing shows the notification, starts the sound and emits', () async {
      final emitted = expectLater(
        controller.rings.map((a) => a.itemId),
        emits('i1'),
      );
      await ring('i1');
      await emitted;
      expect(notifications.shown, ['i1']);
      expect(sound.playing, isTrue);
      expect(controller.current?.itemId, 'i1');
    });

    test('stop silences the sound and cancels the notification', () async {
      await ring('i1');
      await controller.stop();
      expect(sound.playing, isFalse);
      expect(notifications.cancelled, ['i1']);
      expect(controller.current, isNull);
    });

    test('stop with an item id cancels a notification rung by the '
        'background worker', () async {
      await controller.stop(itemId: 'from-background');
      expect(notifications.cancelled, ['from-background']);
    });

    test('a second alarm replaces the first — one sound at a time', () async {
      await ring('i1');
      await ring('i2');
      expect(notifications.cancelled, ['i1']);
      expect(sound.starts - sound.stops, 1);
      expect(controller.current?.itemId, 'i2');
    });

    test('stops by itself after the ring duration', () async {
      controller.dispose();
      controller = create(ring: const Duration(milliseconds: 20));
      await ring('i1');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(sound.playing, isFalse);
      expect(notifications.cancelled, ['i1']);
      expect(controller.current, isNull);
    });

    test('still rings in-app when the notification fails', () async {
      notifications.fail = true;
      await ring('i1');
      expect(sound.playing, isTrue);
      expect(controller.current?.itemId, 'i1');
    });

    test('the test alarm uses its reserved id', () async {
      await controller.ringTest();
      expect(notifications.shown, [kTestAlarmItemId]);
      expect(sound.playing, isTrue);
    });
  });
}
