# PriceAlarm — Class Diagram

Status: v0.1 · Last updated: 2026-11-21

## 1. Provider graph

```
main.dart overrides
  appDatabaseProvider ─────────┬──────────────┬─────────────────┐
  logServiceProvider ──────────┤              │                 │
  notificationServiceProvider ─┤              │                 │
  httpPageFetcherProvider ─────┤              │                 │
  webViewPageFetcherProvider ──┤              │                 │
  alarmSoundProvider ──────────┤              │                 │
  appVersionProvider           ▼              ▼                 ▼
                     alarmControllerProvider    backupServiceProvider
                               │
                               ▼
                     priceCheckServiceProvider
                               │
                               ▼
                     schedulerServiceProvider

Read models (watch appDatabaseProvider):
  itemsStreamProvider ──┐
  allOffersStreamProvider ┴─▶ itemOverviewsProvider ─▶ ItemsScreen
  itemProvider(id), itemOffersProvider(id),
  itemHistoryProvider((id, limit)) ─────────────────▶ ItemDetailScreen
  themeModeProvider ────────────────────────────────▶ PriceAlarmApp, SettingsScreen
  notificationPermissionProvider ───────────────────▶ SettingsScreen

Write side (ref.read):
  itemActionsProvider     save / delete / setEnabled / checkNow / checkAll
                          → DAOs, priceCheckService, scheduler.reschedule()
  settingsActionsProvider setThemeMode / requestNotificationPermission /
                          requestFullScreenAlarmPermission / testAlarm
```

## 2. Navigation tree

```
/alarm/:itemId            AlarmScreen(itemId)      (outside the shell)
StatefulShellRoute.indexedStack (AdaptiveShell)
├── /items                ItemsScreen
│   ├── /items/new        ItemEditScreen()
│   └── /items/:id        ItemDetailScreen(itemId)
│       └── edit          ItemEditScreen(itemId)
└── /settings             SettingsScreen
    ├── backup            BackupScreen
    ├── about             AboutScreen
    └── logs              LogsScreen
```

## 3. Central types

```
Item                         Offer                          PriceCheck
  id, name                     id, itemId, url, shopName      id, offerId, shopName
  targetPrice: Decimal         fetchMode: FetchMode           checkedAt (UTC)
  currency                     resolvedMethod: FetchMethod?   status: CheckStatus
  checkTime: int (min)         lastPrice: Decimal?            method: FetchMethod?
  enabled, alarmActive         lastCurrency, lastAvailability price: Decimal?
  lastRunAt, createdAt         lastStatus, lastError          currency, availability, error
                               lastCheckedAt
                               needsWebView (getter)

ItemDraft / OfferDraft         CheckOutcome                   AlarmDecision
  form input, saved by           status, method, price,         active, fire,
  ItemsDao.saveDraft()           currency, availability, error  bestPrice, bestShop

sealed PageFetchResult
  ├── PageFetched(html)
  ├── PageBlocked(reason)
  ├── PageNetworkError(reason)
  └── PageUnsupported(reason)

PageFetcher (interface) ◀── HttpPageFetcher(dio, log)
                        ◀── WebViewPageFetcher(log)

AlarmNotifier (interface: showAlarm, cancelAlarm)
  ◀── NotificationService           (rings itself on Android)
  ◀── AlarmController(notifications, sound)
        rings: Stream<ActiveAlarm>, current, stop({itemId}), ringTest()

AlarmSound (interface: start, stop)
  ◀── AudioAlarmSound (audioplayers, assets/sounds/alarm.wav, loop)
  ◀── SilentAlarmSound (Android)

PriceCheckService            SchedulerService
  runItem(id)                  catchUpAndReschedule()
  runAllEnabled()              reschedule()
  runDue()                     dispose()
  testOffer(url, mode)

Top-level functions
  checkOffer({url, mode, resolvedMethod, http, webView}) → CheckOutcome
  runPriceChecks({db, items, http, webView, notifier, log, clock,
                  scope: RunScope, deferWebViewOffers}) → List<ItemRunResult>
  priceRunCallback()     (android_alarm_manager_plus entry point, Android)
  scheduleAndroidRun(next, {exactAllowed, log})
```
