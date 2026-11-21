import 'dart:async';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/formatters.dart';
import 'log_service.dart';
import 'price_check_service.dart';

/// Permission state as far as the platform can report it.
enum NotificationPermission { granted, denied, unknown, notRequired }

class NotificationService implements AlarmNotifier {
  NotificationService({required this.log});

  final LogService log;
  final _plugin = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<String>.broadcast();

  /// Item ids of tapped notifications, for navigation.
  Stream<String> get tappedItemIds => _taps.stream;

  static const _channelId = 'price_alarms';

  // Fixed identity for Windows toast notifications; must never change, or
  // Windows treats it as a different app.
  static const _windowsGuid = '170e68ba-dec3-4369-a460-cb2c3d91aed0';

  /// Returns the item id if the app was launched by tapping a notification.
  Future<String?> initialize() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Permission is requested explicitly from Settings / first start,
        // not implicitly at plugin init.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
        linux: LinuxInitializationSettings(defaultActionName: 'Open'),
        windows: WindowsInitializationSettings(
          appName: 'PriceAlarm',
          appUserModelId: 'ch.pricealarm.PriceAlarm',
          guid: _windowsGuid,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) _taps.add(payload);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      return launch!.notificationResponse?.payload;
    }
    return null;
  }

  Future<NotificationPermission> permission() async {
    if (Platform.isAndroid) {
      final enabled = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled();
      return switch (enabled) {
        true => NotificationPermission.granted,
        false => NotificationPermission.denied,
        null => NotificationPermission.unknown,
      };
    }
    if (Platform.isIOS || Platform.isMacOS) return NotificationPermission.unknown;
    return NotificationPermission.notRequired;
  }

  /// `true` when granted, `false` when refused, `null` when not applicable.
  Future<bool?> requestPermission() async {
    try {
      if (Platform.isAndroid) {
        return await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      }
      if (Platform.isIOS) {
        return await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, sound: true);
      }
      if (Platform.isMacOS) {
        return await _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, sound: true);
      }
    } catch (e, st) {
      log.error('Notification permission request failed', e, st);
    }
    return null;
  }

  @override
  Future<void> showAlarm({
    required String itemId,
    required String itemName,
    required Decimal price,
    required Decimal targetPrice,
    required String currency,
    required String shopName,
  }) => _plugin.show(
    id: _notificationId(itemId),
    title: itemName,
    body:
        '${formatMoney(price, currency)} at $shopName '
        '(target ${formatMoney(targetPrice, currency)})',
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Price alarms',
        channelDescription: 'A watched price reached its target',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
    payload: itemId,
  );

  /// Stable across runs and isolates (unlike `String.hashCode`), so a new
  /// alarm for the same item replaces the old notification.
  static int _notificationId(String itemId) {
    var hash = 0;
    for (final unit in itemId.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash;
  }
}
