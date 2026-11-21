import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:price_alarm/core/providers.dart';
import 'package:price_alarm/core/services/alarm_controller.dart';
import 'package:price_alarm/core/services/alarm_sound.dart';
import 'package:price_alarm/core/services/log_service.dart';
import 'package:price_alarm/core/services/price_check_service.dart';
import 'package:price_alarm/features/alarm/alarm_screen.dart';

class _FakeNotifications implements AlarmNotifier {
  final cancelled = <String>[];

  @override
  Future<void> showAlarm({
    required String itemId,
    required String itemName,
    required Decimal price,
    required Decimal targetPrice,
    required String currency,
    required String shopName,
  }) async {}

  @override
  Future<void> cancelAlarm(String itemId) async => cancelled.add(itemId);
}

class _FakeSound implements AlarmSound {
  bool playing = false;

  @override
  Future<void> start() async => playing = true;

  @override
  Future<void> stop() async => playing = false;
}

void main() {
  testWidgets('Stop silences the ringing alarm and leaves the screen', (
    tester,
  ) async {
    final notifications = _FakeNotifications();
    final sound = _FakeSound();
    late AlarmController controller;
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('price_alarm_test');
      addTearDown(() => tmp.delete(recursive: true));
      controller = AlarmController(
        notifications: notifications,
        sound: sound,
        log: LogService(File('${tmp.path}/test.log')),
      );
      await controller.showAlarm(
        itemId: 'i1',
        itemName: 'ASUS Radeon AI PRO R9700',
        price: Decimal.parse('2149'),
        targetPrice: Decimal.parse('2200'),
        currency: 'CHF',
        shopName: 'Galaxus',
      );
    });
    addTearDown(controller.dispose);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/alarm/:itemId',
          builder: (context, state) =>
              AlarmScreen(itemId: state.pathParameters['itemId']!),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [alarmControllerProvider.overrideWithValue(controller)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.push('/alarm/i1');
    await tester.pumpAndSettle();

    expect(find.text('ASUS Radeon AI PRO R9700'), findsOneWidget);
    expect(find.textContaining('at Galaxus'), findsOneWidget);
    expect(sound.playing, isTrue);

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();

    expect(sound.playing, isFalse);
    expect(notifications.cancelled, ['i1']);
    expect(find.text('home'), findsOneWidget);
  });
}
