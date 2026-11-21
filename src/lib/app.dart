import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/item_detail/item_detail_screen.dart';
import 'features/item_edit/item_edit_screen.dart';
import 'features/items/items_screen.dart';
import 'features/settings/about_screen.dart';
import 'features/settings/backup_screen.dart';
import 'features/settings/logs_screen.dart';
import 'features/settings/settings_provider.dart';
import 'features/settings/settings_screen.dart';
import 'shell/adaptive_shell.dart';

const _seedColor = Colors.indigo;

/// Public (not `_router`) because main.dart navigates on notification taps.
final appRouter = GoRouter(
  initialLocation: '/items',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AdaptiveShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/items',
              builder: (context, state) => const ItemsScreen(),
              routes: [
                // Before ':id' so "new" is not taken for an id.
                GoRoute(
                  path: 'new',
                  builder: (context, state) => const ItemEditScreen(),
                ),
                GoRoute(
                  path: ':id',
                  builder: (context, state) =>
                      ItemDetailScreen(itemId: state.pathParameters['id']!),
                  routes: [
                    GoRoute(
                      path: 'edit',
                      builder: (context, state) => ItemEditScreen(
                        itemId: state.pathParameters['id']!,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
              routes: [
                GoRoute(
                  path: 'backup',
                  builder: (context, state) => const BackupScreen(),
                ),
                GoRoute(
                  path: 'about',
                  builder: (context, state) => const AboutScreen(),
                ),
                GoRoute(
                  path: 'logs',
                  builder: (context, state) => const LogsScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

class PriceAlarmApp extends ConsumerWidget {
  const PriceAlarmApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider).valueOrNull;
    return MaterialApp.router(
      title: 'PriceAlarm',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: themeMode ?? ThemeMode.system,
      routerConfig: appRouter,
    );
  }
}
