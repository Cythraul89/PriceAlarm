import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

import 'alarm_sound.dart';
import 'log_service.dart';
import 'price_check_service.dart';

/// An alarm rings at most this long without user action (REQUIREMENTS 5.3.1).
const kAlarmRingDuration = Duration(minutes: 10);

/// Item id used by Settings → Test alarm.
const kTestAlarmItemId = 'test-alarm';

class ActiveAlarm extends Equatable {
  const ActiveAlarm({
    required this.itemId,
    required this.itemName,
    required this.price,
    required this.targetPrice,
    required this.currency,
    required this.shopName,
  });

  final String itemId;
  final String itemName;
  final Decimal price;
  final Decimal targetPrice;
  final String currency;
  final String shopName;

  @override
  List<Object?> get props => [
    itemId,
    itemName,
    price,
    targetPrice,
    currency,
    shopName,
  ];
}

/// Rings an alarm like an alarm clock while the app runs: notification
/// (which itself rings on Android) + looping in-app sound + an event the UI
/// turns into the full-screen alarm screen. Stops on [stop] or after
/// [ringDuration].
///
/// The Android background worker does not use this class — it calls the
/// notification service directly, whose notification rings on its own.
class AlarmController implements AlarmNotifier {
  AlarmController({
    required this.notifications,
    required this.sound,
    required this.log,
    this.ringDuration = kAlarmRingDuration,
  });

  final AlarmNotifier notifications;
  final AlarmSound sound;
  final LogService log;
  final Duration ringDuration;

  final _rings = StreamController<ActiveAlarm>.broadcast();
  ActiveAlarm? _current;
  Timer? _autoStop;

  /// Emits each alarm that starts ringing; the app navigates to the alarm
  /// screen on it.
  Stream<ActiveAlarm> get rings => _rings.stream;

  /// The alarm ringing right now, if any.
  ActiveAlarm? get current => _current;

  @override
  Future<void> showAlarm({
    required String itemId,
    required String itemName,
    required Decimal price,
    required Decimal targetPrice,
    required String currency,
    required String shopName,
  }) async {
    // A second alarm replaces the first: one ringing sound, one screen.
    if (_current != null) await stop();
    final alarm = ActiveAlarm(
      itemId: itemId,
      itemName: itemName,
      price: price,
      targetPrice: targetPrice,
      currency: currency,
      shopName: shopName,
    );
    _current = alarm;
    log.info('Alarm ringing: $itemName ${price.toString()} at $shopName');
    try {
      await notifications.showAlarm(
        itemId: itemId,
        itemName: itemName,
        price: price,
        targetPrice: targetPrice,
        currency: currency,
        shopName: shopName,
      );
    } catch (e, st) {
      // The in-app sound and screen must still ring if the notification
      // could not be shown (e.g. permission denied).
      log.error('Alarm notification failed', e, st);
    }
    await sound.start();
    _autoStop = Timer(ringDuration, () {
      log.info('Alarm stopped automatically after $ringDuration');
      unawaited(stop());
    });
    _rings.add(alarm);
  }

  /// Silences the ringing alarm. With [itemId], also cancels that item's
  /// notification when no alarm is tracked in memory — the case after the
  /// app was launched from a ringing Android notification.
  Future<void> stop({String? itemId}) async {
    _autoStop?.cancel();
    _autoStop = null;
    final id = _current?.itemId ?? itemId;
    _current = null;
    await sound.stop();
    if (id != null) await cancelAlarm(id);
  }

  @override
  Future<void> cancelAlarm(String itemId) async {
    try {
      await notifications.cancelAlarm(itemId);
    } catch (e, st) {
      log.error('Cancelling the alarm notification failed', e, st);
    }
  }

  /// Settings → Test alarm: rings exactly like a real alarm.
  Future<void> ringTest() => showAlarm(
    itemId: kTestAlarmItemId,
    itemName: 'Test alarm',
    price: Decimal.parse('1999.00'),
    targetPrice: Decimal.parse('2000.00'),
    currency: 'CHF',
    shopName: 'PriceAlarm',
  );

  void dispose() {
    _autoStop?.cancel();
    unawaited(_rings.close());
  }
}
