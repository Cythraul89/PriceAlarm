# PriceAlarm — Architecture

Status: v0.1 implemented · Last updated: 2026-11-21

## 1. Technology Stack

| Concern | Library | Note |
|---|---|---|
| UI | Flutter, Material 3 via `material_ui` | indigo seed, light + dark, `ThemeMode` from settings; `package:flutter/material.dart` is deprecated after Flutter 3.47 |
| State | `flutter_riverpod` 2 | manual providers, no codegen |
| Navigation | `go_router` | `StatefulShellRoute.indexedStack` |
| Persistence | `drift` (+ `sqlite3` 3.x) + `path_provider` | `sqlite3` 3.x bundles SQLite via build hooks; `sqlite3_flutter_libs` is obsolete and not used |
| Money | `decimal` | persisted as text via `DecimalConverter` |
| HTTP fetch | `dio` | shared instance, timeouts per REQUIREMENTS 4.2 |
| HTML parsing | `html` | only to locate `<script type="application/ld+json">` and `<meta>` tags |
| WebView fetch | `flutter_inappwebview` (`HeadlessInAppWebView`) | Android, iOS, macOS, Windows; no Linux implementation in 6.1.x |
| Notifications | `flutter_local_notifications` | Android: alarm channel, alarm audio usage, insistent, full-screen intent |
| Alarm sound | `audioplayers` | looping bundled WAV on iOS/desktop; Linux needs GStreamer |
| Background (Android) | `android_alarm_manager_plus` | exact alarm-clock alarm (`setAlarmClock`) per next due time; inexact Doze-capable fallback |
| Backup | `archive`, `file_picker`, `share_plus` | |
| About | `package_info_plus`, `url_launcher` | |
| Utilities | `uuid`, `intl`, `equatable` | |

Versions are pinned in `src/pubspec.yaml` / `pubspec.lock` (resolved by pub on
2026-11-21). Riverpod is held at 2.x per house style although 3.x exists.

## 2. Project Structure

```
src/lib/
├── main.dart                      bootstrap, provider overrides, alarm manager init
├── app.dart                       MaterialApp.router, theme, appRouter
├── core/
│   ├── providers.dart             singleton + composed service providers
│   ├── database/
│   │   ├── app_database.dart      @DriftDatabase, schemaVersion 2 (+ onUpgrade)
│   │   ├── decimal_converter.dart
│   │   ├── tables/                items, offers, price_checks, settings
│   │   └── daos/                  items_dao, offers_dao, price_checks_dao, settings_dao
│   ├── models/                    Item, Offer, PriceCheck, ItemDraft, CheckOutcome,
│   │                              enums (FetchMode, FetchMethod, CheckStatus)
│   ├── calculators/
│   │   ├── alarm_evaluator.dart   best price + once-per-cycle ring decision
│   │   └── schedule_calculator.dart  due items, next due time, catch-up
│   ├── services/
│   │   ├── price_extractor.dart   JSON-LD / meta → ExtractedPrice (pure, no I/O)
│   │   ├── page_fetcher.dart      sealed PageFetchResult + PageFetcher interface
│   │   ├── http_page_fetcher.dart
│   │   ├── webview_page_fetcher.dart
│   │   ├── price_check_service.dart  orchestrates one run (see 5.2)
│   │   ├── scheduler_service.dart    exact alarm (Android) / desktop timer / catch-up
│   │   ├── background_worker.dart    alarm callback + scheduleAndroidRun (Android)
│   │   ├── alarm_controller.dart     rings: notification + sound + alarm-screen event
│   │   ├── alarm_sound.dart          AlarmSound / AudioAlarmSound / SilentAlarmSound
│   │   ├── notification_service.dart
│   │   ├── backup_service.dart
│   │   └── log_service.dart
│   ├── utils/                     formatters (de_CH money), shop_name.dart, app_version.dart
│   └── widgets/                   error_view.dart, status_icon.dart
├── features/
│   ├── items/                     items_screen, items_provider, widgets/item_card
│   ├── item_detail/               item_detail_screen, item_detail_provider, widgets/
│   ├── item_edit/                 item_edit_screen, widgets/offer_editor (no own provider:
│   │                              reads DAOs once, writes via ItemActions)
│   ├── alarm/                     alarm_screen (full screen, outside the shell)
│   └── settings/                  settings_screen, about_screen, logs_screen,
│                                  backup_screen, settings_provider
└── shell/                         adaptive_shell, mobile_shell, desktop_shell
```

## 3. Data Model

The entities and fields are specified in REQUIREMENTS §3. Drift mapping:

| Table | Row class | Key | Relations |
|---|---|---|---|
| `items` | `ItemRow` | `id` text (UUID) | — |
| `offers` | `OfferRow` | `id` text (UUID) | `item_id` → items, cascade; unique (`item_id`, `url`) |
| `price_checks` | `PriceCheckRow` | `id` int autoincrement | `offer_id` → offers, cascade; index (`offer_id`, `checked_at`) |
| `settings` | `SettingsRow` | `id` int = 1 | — |

Column conventions: `Decimal` as `TEXT` via `DecimalConverter`; enums as
`TEXT` via `textEnum<…>()` so reordering an enum never corrupts data; times as
UTC `DateTime`; `check_time` as minutes since local midnight (`INTEGER`).

Domain models (`core/models/`) are immutable, `Equatable`, with `copyWith`;
DAOs map rows to them.

## 4. Layered Architecture

```
UI         features/**  screens & widgets — layout and intent only
   │ watch / read
State      *_provider.dart — StreamProviders over DAO watch*(), *ActionsProvider
   │ call
Services   PriceCheckService ──▶ HttpPageFetcher ─┐
           SchedulerService     WebViewPageFetcher├─▶ PriceExtractor (pure)
           NotificationService  BackupService     │
           LogService                              │
   │ persist                                       ▼
Data       DAOs (Drift)                      AlarmEvaluator, ScheduleCalculator
   │                                         (core/calculators — pure)
Storage    SQLite (app documents dir), log file
```

Providers that must be overridden in `main.dart` (each throws
`UnimplementedError` otherwise):

| Provider | Value |
|---|---|
| `appDatabaseProvider` | `AppDatabase()` |
| `logServiceProvider` | `LogService` (file logger) |
| `notificationServiceProvider` | initialised `NotificationService` |
| `httpPageFetcherProvider` | `HttpPageFetcher(dio)` |
| `webViewPageFetcherProvider` | `WebViewPageFetcher` or `null` where unsupported |
| `appVersionProvider` | version string from `package_info_plus` |
| `alarmSoundProvider` | `AudioAlarmSound` (iOS, desktop) or `SilentAlarmSound` (Android) |

`alarmControllerProvider`, `priceCheckServiceProvider` and
`schedulerServiceProvider` are plain `Provider`s composed from the above. The
price check service notifies through the `AlarmController` (app running);
the Android worker notifies through `NotificationService` directly.

## 5. Price Check Pipeline

### 5.1 Fetch result contract

```dart
sealed class PageFetchResult {}
final class PageFetched extends PageFetchResult { final String html; }
final class PageBlocked extends PageFetchResult { final String reason; }   // 403/429/challenge
final class PageNetworkError extends PageFetchResult { final String reason; } // DNS, timeout, 5xx
final class PageUnsupported extends PageFetchResult { final String reason; }  // no WebView here
```

Both fetchers implement `abstract interface class PageFetcher { Future<PageFetchResult> fetch(Uri url); }`.
The WebView fetcher returns the **serialised DOM**
(`document.documentElement.outerHTML` via `evaluateJavascript`, after the load
event, then polled until it carries a price, at most 20 s), so `PriceExtractor` is the single parser for
both modes.

`PriceExtractor.extract(String html) → ExtractedPrice?` is pure: `null` means
"page loaded, no price found" (`noPrice`). A blocked or failed fetch never
reaches the extractor — this keeps "no price" and "could not load" apart.

### 5.2 One run of one item

```
PriceCheckService.runItem(itemId)
  for each offer (sequential — one page load at a time):
    methods = order(offer.fetchMode, offer.resolvedMethod)
    for mode in modes:                      # at most 2 (auto escalation)
      result = fetcher[mode].fetch(url)
      PageFetched  → extract → ok | noPrice
      PageBlocked / noPrice → try next mode if any
      PageNetworkError → stop (no escalation: the network is the problem)
    write PriceCheck row + targeted Offer update (last* columns, resolvedMethod)
  decision = AlarmEvaluator.evaluate(item, offersOfThisRun)
  in one transaction: update item.alarmActive, item.lastRunAt
  if decision.fire → NotificationService.showAlarm(...)
  PriceChecksDao.deleteOlderThan(now − 365 d)
```

`runItem` is backed by a top-level function
`runPriceChecks({required db, required fetchers, required notifier, required log, required now})`
so the Android background worker and the UI share exactly one code path and
the function is unit-testable with fakes.

### 5.3 Alarm evaluation (pure)

`AlarmEvaluator.evaluate(targetPrice, currency, wasActive, offerResults)`
returns `AlarmDecision { Decimal? bestPrice; String? bestShop; bool active; bool fire; }`
implementing REQUIREMENTS 5.2 exactly. Table-driven unit tests cover:
no ok offer, mixed currencies, equality at target, once per cycle, new cycle,
partial runs.

## 6. Scheduling

`ScheduleCalculator` (pure) answers two questions for a given `now` and the
local time zone:

- `dueItems(items, now)` — enabled items whose latest due instant is after
  `lastRunAt` (catch-up, REQUIREMENTS 5.1.2).
- `nextDue(items, now)` — the earliest future due instant over all items.

Daylight-saving transitions: `checkTime` is a local wall-clock time, built
with the local `DateTime` constructor; a non-existent or repeated wall time on
a transition day resolves however the Dart runtime resolves it for the
platform time zone. Not covered by tests (the result depends on the test
machine's time zone).

`SchedulerService` uses the calculator per platform:

| Platform | Mechanism |
|---|---|
| Android | One alarm (id 4711) via `android_alarm_manager_plus.oneShotAt` at `nextDue`: `alarmClock` + `exact` when exact alarms are allowed (fires on time in Doze; the system leaves Doze shortly before, so the network works), otherwise `allowWhileIdle` (Doze-capable, may be late); `wakeup`, `rescheduleOnReboot`. Scheduling with the same id replaces the pending alarm. The callback runs the due offers (HTTP only) and always schedules the next alarm, also after a failure. |
| iOS | No background run in v0.1. Catch-up on app start and on `AppLifecycleState.resumed`. |
| Desktop | A single `Timer` to `nextDue`, re-armed after each run and on item changes. Catch-up on start/resume. |

Background isolate (Android): the worker opens its own `AppDatabase` via
`AppDatabase.openForIsolate()` and constructs its own fetchers and
notification plugin; nothing from the UI isolate is shared.

## 7. Key Design Decisions

### 7.1 Schema.org structured data instead of per-shop scrapers
**What:** one extractor reading JSON-LD `Product/Offer` (fallback: Open Graph
product meta tags) for every shop.
**Why:** shops publish this for search engines, so it is stable across
redesigns; adding a shop needs no code. Verified for Brack.
**Rejected:** CSS-selector scrapers per shop — break on every redesign and
need code per shop. May be added later as a fallback *only* for a shop
without structured data, behind the same `ExtractedPrice` contract.

### 7.2 Two fetch modes with `auto` escalation
**What:** plain HTTP first, headless WebView as fallback, remembered per offer.
**Why:** HTTP is fast and works in every isolate and on every platform; the
WebView is needed for shops like Galaxus that reject non-browser clients
(verified 403). Remembering `resolvedMode` avoids a doomed HTTP request every
day.
**Rejected:** WebView for everything — slower, heavier, unavailable on Linux
(stable) and unproven in the Android background isolate (R3). Fingerprint
spoofing / proxies — deliberately out of scope (REQUIREMENTS 4.2.3).

### 7.3 Item with several offers, trigger on the best price
**What:** the target price belongs to the item; the alarm compares the lowest
comparable offer price.
**Why:** the user's goal is "buy this product below X anywhere", not "this
shop below X". One check time per item keeps all shops of a product compared
on the same snapshot.

### 7.4 Ring once per daily cycle, every day while reached
**What:** ring in every cycle in which a check finds the best price at or
below the target, at most once per cycle; `lastAlarmAt` (schema 2) records the
ring, a target edit clears it.
**Why:** the user wants a daily alarm while the price is low (decided
2026-11-21, replacing the earlier "once per price drop" rule, which looked
like a broken alarm in testing). One ring per cycle keeps catch-ups and
"Check now" from ringing repeatedly.
**Rejected:** ringing on every check — catch-ups would ring several times a day.

### 7.5 Exact alarm-clock alarm instead of WorkManager (Android)
**What:** schedule the next due instant with `setAlarmClock`
(android_alarm_manager_plus); the callback re-schedules itself.
**Why:** WorkManager postpones work in Doze — a device log showed runs 1, 3,
10 and 14 minutes late, and OEM battery savers can hold it until the app is
opened. Alarm-clock alarms are the mechanism Android provides for "at this
time" and also show the next alarm like a clock app.
**Cost:** the exact-alarm permission ("Alarms & reminders"), denied by default
on Android 14+; the app asks via a banner/Settings and falls back to an
inexact Doze-capable alarm.
**Replaced:** the earlier decision for a chained WorkManager task (v0.1).

### 7.6 Catch-up instead of guaranteed timing on iOS and desktop
**What:** missed runs are executed on start/resume; at most one per item.
**Why:** iOS offers no fixed-time background execution, desktop apps are
not always running. Catch-up gives the user a fresh price whenever they look,
and the UI states the platform limitation instead of implying exact timing.

### 7.7 Android background runs defer failed WebView offers, not items
**What:** the background run checks all due offers, WebView offers in a
headless WebView. A WebView offer whose check fails there is not recorded and
stays due (`RunScope.dueOffers` + `deferWebViewOffers`); `lastRunAt` is only
set once no offer was skipped, so the foreground catch-up checks the rest.
**Why:** a headless WebView in the background isolate is unproven (R3) — it
may fail on some devices; recording that failure would end the offer's cycle.
Skipping whole items (v0.1) meant an item with a Galaxus offer was never
checked in the background — the device log showed `deferred (needs WebView)`
at every scheduled run, so the alarm only rang on app open.
**Consequence:** a partial run may ring but never clears `alarmActive`.

### 7.8 New items are checked immediately
**What:** saving a new item starts one run without waiting for it.
**Why:** the user sees a price (or the failure) right away, and `auto` offers
learn their `resolvedMethod` in the foreground, which the Android background
run depends on (7.7).

### 7.9 Alarm rings like an alarm clock
**What:** on Android the notification itself is the alarm: alarm audio usage
(alarm-clock volume), the system alarm-clock sound
(`content://settings/system/alarm_alert`), `FLAG_INSISTENT` so it repeats until
dismissed, category `alarm`, full-screen intent, 10-minute timeout. While the
app runs, `AlarmController` adds the full-screen alarm screen and — on iOS and
desktop only — a looping bundled sound (`audioplayers`).
**Why:** only the notification can ring with the app closed, and the alarm
stream is exactly the alarm-clock volume the user asked for. Playing the
in-app sound on Android as well would double the sound.
**Rejected:** a foreground service playing audio on Android — more
permissions and Play policy questions for no gain over an insistent alarm
notification. Changing the system volume — never done (REQUIREMENTS 5.3.5).
**Constraint:** Android channel sound and usage are fixed once the channel
exists; the channel id carries a version (`price_alarm_ring_v1`) to change
them.

## 8. Navigation Map

```
/alarm/:itemId                           AlarmScreen (full screen, outside the shell)
StatefulShellRoute.indexedStack
├── branch 0: /items                     ItemsScreen
│   ├── /items/new                       ItemEditScreen (create)
│   └── /items/:id                       ItemDetailScreen
│       └── /items/:id/edit              ItemEditScreen (edit)
└── branch 1: /settings                  SettingsScreen
    ├── /settings/backup                 BackupScreen
    ├── /settings/about                  AboutScreen
    └── /settings/logs                   LogsScreen
```

Notification payload = item id; a tap or full-screen launch pushes
`/alarm/:itemId`. A ringing in-app alarm pushes the same route, so "Stop"
pops back to the previous screen.

## 9. Testing

| Area | Test | How |
|---|---|---|
| `PriceExtractor` | unit | HTML fixtures: the Brack page JSON-LD (saved 2026-11-21), `@graph` variant, `AggregateOffer`, numeric price, meta-tag fallback, no price, malformed JSON |
| `AlarmEvaluator` | unit | table-driven, see 5.3 |
| `ScheduleCalculator` | unit | due/next-due, catch-up, creation time, month/year rollover |
| `HttpPageFetcher` | integration | loopback `HttpServer`: 200, 403, 429, timeout, 500 |
| DAOs | unit | in-memory Drift, cascade deletes, retention delete |
| `runPriceChecks` | unit | fake fetchers + in-memory DB: escalation order, no escalation on network error, once-per-cycle ring, Android background partial run, foreground completion of deferred offers, history rows |
| Migration | unit | real schema-1 database (fixture written by the previous version) upgraded to 2 |
| `BackupService` | unit | export → import through real ZIP/JSON bytes |
| Shell | widget | renders with overridden providers; bottom nav < 600 dp, rail ≥ 600 dp |
| Utils | unit | shop name, URL validation, formatters, backup file name |
| `AlarmController` | unit | ring/stop, auto-stop, replace, notification failure, test alarm |
| `AlarmScreen` | widget | Stop silences, cancels the notification once, pops back |

What is not tested automatically: `WebViewPageFetcher` (needs a real platform
WebView), `SchedulerService` and the Android alarm callback, notification
delivery and taps, the actual loudness/looping of the Android alarm channel
and of `AudioAlarmSound` (device test — use Settings → Test alarm), DST behaviour, the screens beyond the
shell smoke test, and the live shop pages (fixtures only; CI never contacts
Galaxus or Brack).
