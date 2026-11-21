import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:price_alarm/app.dart';
import 'package:price_alarm/core/models/item.dart';
import 'package:price_alarm/core/providers.dart';
import 'package:price_alarm/features/items/items_provider.dart';
import 'package:price_alarm/features/settings/settings_provider.dart';
import 'package:price_alarm/shell/adaptive_shell.dart';

ItemOverview _overview() {
  final item = Item(
    id: 'i1',
    name: 'ASUS Radeon AI PRO R9700',
    targetPrice: Decimal.parse('2200'),
    currency: 'CHF',
    checkTime: 480,
    enabled: true,
    alarmActive: true,
    lastRunAt: null,
    createdAt: DateTime(2026, 11, 21),
  );
  return ItemOverview(
    item: item,
    offers: const [],
    bestPrice: Decimal.parse('2149'),
    bestShop: 'Galaxus',
    failingOffers: 0,
    nextDue: DateTime(2026, 11, 22, 8),
  );
}

Widget _app() => ProviderScope(
  overrides: [
    // Overriding the read models keeps Drift's stream store (and its
    // cleanup timers) out of the test's fake-async zone.
    itemOverviewsProvider.overrideWithValue(AsyncData([_overview()])),
    themeModeProvider.overrideWith((ref) => Stream.value(ThemeMode.light)),
    // Nothing in this test may touch a real service.
    appDatabaseProvider.overrideWith((ref) => throw UnimplementedError()),
    httpPageFetcherProvider.overrideWith((ref) => throw UnimplementedError()),
    webViewPageFetcherProvider.overrideWithValue(null),
  ],
  child: const PriceAlarmApp(),
);

void main() {
  testWidgets('mobile width shows the item list with bottom navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('ASUS Radeon AI PRO R9700'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('desktop width switches to the navigation rail', (tester) async {
    tester.view.physicalSize = const Size(kDesktopBreakpoint + 200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
