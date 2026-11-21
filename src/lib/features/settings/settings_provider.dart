import 'package:flutter/material.dart' show ThemeMode;
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

// ── Write side ──────────────────────────────────────────────────────────────

class SettingsActions {
  SettingsActions(this._ref);

  final Ref _ref;

  Future<void> setThemeMode(ThemeMode mode) =>
      _ref.read(appDatabaseProvider).settingsDao.setThemeMode(mode);

  Future<void> requestNotificationPermission() async {
    await _ref.read(notificationServiceProvider).requestPermission();
    _ref.invalidate(notificationPermissionProvider);
  }
}

final settingsActionsProvider = Provider<SettingsActions>(SettingsActions.new);
