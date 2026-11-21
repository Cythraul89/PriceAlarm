import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/services/notification_service.dart';

// ── Read side ───────────────────────────────────────────────────────────────

final themeModeProvider = StreamProvider<ThemeMode>(
  (ref) => ref.watch(appDatabaseProvider).settingsDao.watchThemeMode(),
);

/// Re-read with `ref.invalidate` after a permission request.
final notificationPermissionProvider =
    FutureProvider.autoDispose<NotificationPermission>(
      (ref) => ref.watch(notificationServiceProvider).permission(),
    );

/// Android exact alarms ("Alarms & reminders"); always true elsewhere.
/// Re-read with `ref.invalidate` after returning from the system page.
final exactAlarmPermissionProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(notificationServiceProvider).canScheduleExactAlarms(),
);

// ── Write side ──────────────────────────────────────────────────────────────

class SettingsActions {
  SettingsActions(this._ref);

  final Ref _ref;

  Future<void> setThemeMode(ThemeMode mode) =>
      _ref.read(appDatabaseProvider).settingsDao.setThemeMode(mode);

  Future<void> testAlarm() => _ref.read(alarmControllerProvider).ringTest();

  Future<void> requestFullScreenAlarmPermission() => _ref
      .read(notificationServiceProvider)
      .requestFullScreenAlarmPermission();

  /// Opens the system page; the result is only known when the user comes
  /// back, so the scheduler re-plans on the next resume (catch-up) and the
  /// UI re-reads the state via [refreshExactAlarmPermission].
  Future<void> requestExactAlarmPermission() => _ref
      .read(notificationServiceProvider)
      .requestExactAlarmPermission();

  Future<void> refreshExactAlarmPermission() async {
    _ref.invalidate(exactAlarmPermissionProvider);
    await _ref.read(schedulerServiceProvider).reschedule();
  }

  Future<void> requestNotificationPermission() async {
    await _ref.read(notificationServiceProvider).requestPermission();
    _ref.invalidate(notificationPermissionProvider);
  }
}

final settingsActionsProvider = Provider<SettingsActions>(SettingsActions.new);
