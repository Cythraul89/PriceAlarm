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
  appVersionProvider           ▼              ▼                 ▼
                     priceCheckServiceProvider  backupServiceProvider
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
  settingsActionsProvider setThemeMode / requestNotificationPermission
```

## 2. Navigation tree

```
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

AlarmNotifier (interface) ◀── NotificationService

PriceCheckService            SchedulerService
  runItem(id)                  catchUpAndReschedule()
  runAllEnabled()              reschedule()
  runDue()                     dispose()
  testOffer(url, mode)

Top-level functions
  checkOffer({url, mode, resolvedMethod, http, webView}) → CheckOutcome
  runPriceChecks({db, items, http, webView, notifier, log, clock,
                  deferWebViewItems}) → List<ItemRunResult>
  callbackDispatcher()   (WorkManager entry point, Android)
```
