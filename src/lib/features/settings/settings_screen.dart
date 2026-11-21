import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/notification_service.dart';
import 'settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider).valueOrNull;
    final permission = ref.watch(notificationPermissionProvider);
    final exactAlarms = ref.watch(exactAlarmPermissionProvider);

    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          section('Appearance'),
          ListTile(
            title: const Text('Theme'),
            trailing: DropdownButton<ThemeMode>(
              value: themeMode ?? ThemeMode.system,
              onChanged: (mode) {
                if (mode != null) {
                  ref.read(settingsActionsProvider).setThemeMode(mode);
                }
              },
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
              ],
            ),
          ),
          section('Notifications'),
          ListTile(
            title: const Text('Permission'),
            trailing: permission.when(
              loading: () => const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (e, _) => const Text('unknown'),
              data: (state) => switch (state) {
                NotificationPermission.granted => const Text('Granted ✓'),
                NotificationPermission.notRequired => const Text(
                  'Not required',
                ),
                NotificationPermission.denied ||
                NotificationPermission.unknown => FilledButton.tonal(
                  onPressed: () => ref
                      .read(settingsActionsProvider)
                      .requestNotificationPermission(),
                  child: const Text('Request'),
                ),
              },
            ),
          ),
          if (Platform.isAndroid)
            ListTile(
              title: const Text('Exact check time'),
              subtitle: const Text(
                'Lets the daily check run on time while the phone is idle, '
                'like an alarm clock ("Alarms & reminders")',
              ),
              trailing: exactAlarms.when(
                loading: () => const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (e, _) => const Text('unknown'),
                data: (allowed) => allowed
                    ? const Text('Allowed ✓')
                    : FilledButton.tonal(
                        onPressed: () => ref
                            .read(settingsActionsProvider)
                            .requestExactAlarmPermission(),
                        child: const Text('Allow'),
                      ),
              ),
            ),
          if (Platform.isAndroid)
            ListTile(
              title: const Text('Allow alarm over lock screen'),
              subtitle: const Text(
                'Lets the alarm open full-screen like an alarm clock '
                '(Android 14+ may require this)',
              ),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => ref
                  .read(settingsActionsProvider)
                  .requestFullScreenAlarmPermission(),
            ),
          ListTile(
            title: const Text('Test alarm'),
            subtitle: Text(
              Platform.isAndroid
                  ? 'Rings with your alarm-clock sound at alarm volume'
                  : 'Rings while the app is open; volume follows the system '
                        'volume',
            ),
            trailing: const Icon(Icons.alarm),
            onTap: () => ref.read(settingsActionsProvider).testAlarm(),
          ),
          section('Data'),
          ListTile(
            title: const Text('Backup & restore'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/backup'),
          ),
          section('About'),
          ListTile(
            title: const Text('About PriceAlarm'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/about'),
          ),
          ListTile(
            title: const Text('App logs'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/logs'),
          ),
        ],
      ),
    );
  }
}
