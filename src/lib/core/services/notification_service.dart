import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/formatters.dart';
import 'log_service.dart';
import 'alarm_controller.dart' show kAlarmRingDuration;
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

  // Android channel settings (sound, audio usage) are immutable once the
  // channel exists on a device — change the id when changing them.
  static const _channelId = 'price_alarm_ring_v1';

  // Settings.System.DEFAULT_ALARM_ALERT_URI: the alarm-clock sound the user
  // picked in the system settings.
  static const _androidAlarmSound = UriAndroidNotificationSound(
    'content://settings/system/alarm_alert',
  );

  // Notification.FLAG_INSISTENT: repeat the sound until the notification is
  // cancelled or dismissed — what makes it ring like an alarm clock.
  static const _flagInsistent = 4;

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
        // "Stop" only silences (the action cancels the notification); it
        // must not open the app.
        if (response.actionId == _stopActionId) return;
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

  /// Whether exact alarms may be scheduled (Android 12+ "Alarms &
  /// reminders"; denied by default for new installs on Android 14+).
  /// `true` on other platforms, where the question does not arise.
  Future<bool> canScheduleExactAlarms() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.canScheduleExactNotifications() ??
          false;
    } catch (e, st) {
      log.error('Exact alarm permission check failed', e, st);
      return false;
    }
  }

  /// Opens the system "Alarms & reminders" page for this app.
  Future<void> requestExactAlarmPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestExactAlarmsPermission();
    } catch (e, st) {
      log.error('Exact alarm permission request failed', e, st);
    }
  }

  /// Android 14+ may revoke full-screen intents for apps that are not
  /// alarm clocks; this opens the system page where the user can allow it.
  Future<void> requestFullScreenAlarmPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestFullScreenIntentPermission();
    } catch (e, st) {
      log.error('Full-screen intent permission request failed', e, st);
    }
  }

  /// Rings like an alarm clock on Android (REQUIREMENTS 5.3): alarm stream
  /// and alarm-clock sound, repeating until cancelled, full-screen over the
  /// lock screen. On other platforms this is a plain notification; the loop
  /// sound comes from `AlarmSound` while the app runs.
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
    title: 'Price alarm: $itemName',
    body:
        '${formatMoney(price, currency)} at $shopName '
        '(target ${formatMoney(targetPrice, currency)})',
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Price alarm (rings)',
        channelDescription:
            'Rings like an alarm clock when a price reaches its target',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        sound: _androidAlarmSound,
        additionalFlags: Int32List.fromList([_flagInsistent]),
        vibrationPattern: Int64List.fromList([0, 800, 400, 800, 400, 800]),
        fullScreenIntent: true,
        visibility: NotificationVisibility.public,
        timeoutAfter: kAlarmRingDuration.inMilliseconds,
        autoCancel: true,
        actions: const [
          AndroidNotificationAction(
            _stopActionId,
            'Stop',
            cancelNotification: true,
          ),
        ],
      ),
    ),
    payload: itemId,
  );

  @override
  Future<void> cancelAlarm(String itemId) =>
      _plugin.cancel(id: _notificationId(itemId));

  static const _stopActionId = 'stop';

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
