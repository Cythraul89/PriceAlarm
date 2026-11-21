# PriceAlarm — Requirements

Status: v0.1 implemented · Last updated: 2026-11-21

## 1. Purpose

PriceAlarm watches the price of a product at one or more online shops once a
day, at a time of day the user chooses, and raises a local notification when
the price reaches a user-defined target. It is a personal, offline-first app
with no account and no server.

Seed data for v0.1 (the first item the user will create):

| Item | Shop | URL |
|---|---|---|
| ASUS Radeon AI PRO R9700 32 GB | Galaxus | `https://www.galaxus.ch/de/s1/product/asus-radeon-ai-pro-r9700-32-gb-gddr6-grafikkarte-60913447` |
| ASUS Radeon AI PRO R9700 32 GB | Brack | `https://www.brack.ch/asus-grafikkarte-turbo-radeon-ai-pro-r9700-1961443` |

## 2. Terms

| Term | Meaning |
|---|---|
| **Item** | The thing the user wants to buy (e.g. "ASUS Radeon AI PRO R9700"). Owns a target price and a daily check time. |
| **Offer** | One shop page (URL) that sells an item. An item has 1..n offers. |
| **Check** | One attempt to read the current price of one offer. |
| **Run** | All checks of one item, executed together at its check time. |
| **Alarm** | Notification raised when the item's trigger condition becomes true. |

## 3. Data Model

### 3.1 Item

| Field | Type | Notes |
|---|---|---|
| id | UUID (text) | primary key |
| name | text | required, 1–120 chars |
| targetPrice | Decimal | required, > 0, max 2 fraction digits |
| currency | text | ISO 4217, default `CHF` |
| checkTime | int | minutes since local midnight, 0–1439, default 480 (08:00) |
| enabled | bool | default `true`; disabled items are never checked |
| alarmActive | bool | `true` while the trigger condition holds (see 5.2) |
| lastRunAt | DateTime? | UTC, end of the last run that left no offer due |
| lastAlarmAt | DateTime? | UTC, last ring; at most one ring per daily cycle (schema 2) |
| createdAt | DateTime | UTC |

### 3.2 Offer

| Field | Type | Notes |
|---|---|---|
| id | UUID (text) | primary key |
| itemId | UUID | FK → Item, `ON DELETE CASCADE` |
| url | text | required, `https://` only, unique per item |
| shopName | text | derived from host (`galaxus.ch` → "Galaxus"), editable |
| fetchMode | enum | `auto` (default), `http`, `webview` — see 4.2 |
| resolvedMethod | enum? | `http` or `webview` — the method that last succeeded under `auto` |
| lastPrice | Decimal? | last successfully read price |
| lastCurrency | text? | currency reported by the page |
| lastAvailability | text? | schema.org value as read (e.g. `InStock`, `OutOfStock`), informational only |
| lastStatus | enum? | `ok`, `blocked`, `noPrice`, `networkError`, `unsupported` |
| lastError | text? | short human-readable reason for the last non-`ok` status |
| lastCheckedAt | DateTime? | UTC |

### 3.3 PriceCheck (history)

| Field | Type | Notes |
|---|---|---|
| id | int | autoincrement |
| offerId | UUID | FK → Offer, `ON DELETE CASCADE` |
| checkedAt | DateTime | UTC |
| status | enum | as `Offer.lastStatus` |
| method | enum? | `http` or `webview` — the method actually used; empty for `unsupported` |
| price | Decimal? | only when `status = ok` |
| currency | text? | |
| availability | text? | |
| error | text? | reason when `status` is not `ok` |

Retention: entries older than 365 days are deleted at the end of each run.

### 3.4 Settings (single row, id = 1)

| Field | Type | Notes |
|---|---|---|
| themeMode | enum | `system` (default), `light`, `dark` |

## 4. Price Retrieval

### 4.1 Extraction

1. The price is read from schema.org structured data: every
   `<script type="application/ld+json">` block is parsed, and the first
   `Product` (also inside `@graph` or arrays) with an `offers` entry of type
   `Offer` or `AggregateOffer` provides `price` (or `lowPrice`),
   `priceCurrency` and `availability`.
2. If no JSON-LD price exists, the meta tags `product:price:amount` /
   `product:price:currency` (Open Graph product) are used.
3. If neither yields a price, the check status is `noPrice`. The app never
   guesses a price from arbitrary page text.
4. Prices are parsed into `Decimal`; both `"2209.00"` and `2209` (JSON number)
   are accepted. A price ≤ 0 is treated as `noPrice`.
5. A currency that differs from the item currency is stored and shown, but
   that offer is excluded from the trigger evaluation (no FX conversion in
   v0.1) and shown with a warning.

Verified on 2026-11-21: the Brack page above delivers a JSON-LD `Product`
with `offers.price = "2209.00"`, `priceCurrency = "CHF"`,
`availability = "OutOfStock"`. Galaxus could not be inspected (see 4.2) —
**whether Galaxus exposes JSON-LD is unverified.**

### 4.2 Fetch modes

| Mode | How | Platforms |
|---|---|---|
| `http` | Plain HTTPS GET of the page | all five |
| `webview` | Page loaded in an invisible (headless) WebView; the structured data is read from the rendered DOM | Android (foreground only, see 5.1), iOS, macOS, Windows. **Not Linux** (R2) |
| `auto` | `http` first; on `blocked` or `noPrice`, retry once with `webview` where available. The successful method is stored in `resolvedMethod` and tried first next time | — |

Rules:

1. An HTTP 403/429 response or a recognised bot-challenge page is recorded as
   `blocked`, never as `noPrice` and never as "price unchanged".
2. Verified on 2026-11-21: Galaxus answers a plain HTTP request with
   `403 Access Denied` (Akamai). The `webview` mode exists for this case.
   **Whether a WebView passes Galaxus' protection is unverified** (risk R1).
3. The app makes no attempt to disguise itself beyond using a normal browser
   engine: no fingerprint spoofing, no CAPTCHA solving, no proxy rotation.
   If a shop still blocks, the offer stays `blocked` and the user is told.
4. One page load per offer per run; no retries beyond the single `auto`
   escalation. Timeouts: HTTP connect 15 s, receive 30 s; WebView page load
   45 s.
5. On a platform without WebView support, a `webview` offer gets status
   `unsupported` with that reason.

Note: automated reading of shop pages may conflict with a shop's terms of
use. At one request per offer per day this is low-volume, but the user is
responsible for checking the terms of the shops they add.

## 5. Scheduling and Alarm

### 5.1 Daily schedule

1. Each enabled item is due once per local calendar day at its `checkTime`.
2. **Catch-up:** whenever the app starts or returns to the foreground, every
   enabled item whose most recent due time lies after its `lastRunAt` is run
   immediately — only its due offers, i.e. those not checked since that due
   time (at most one catch-up per item, not one per missed day).
3. "Check now" on an item runs it immediately and does not change the
   schedule.
4. Platform behaviour (stated in the UI and README — not hidden):

| Platform | When the scheduled run happens |
|---|---|
| Android | Exact alarm-clock alarm (`AlarmManager.setAlarmClock`) at the due time, also with the app closed and in Doze; needs "Alarms & reminders" (exact alarms), which Android 14+ denies by default — the app shows a banner and a Settings entry. Without it, an inexact alarm that also fires in Doze but may be several minutes late. The background run checks the HTTP offers; offers that need the WebView are checked at the next app start/resume (R3). |
| iOS | iOS gives no way to run at a fixed time. Runs happen on app open/foreground (catch-up). Background refresh is planned, not in v0.1. |
| macOS, Windows, Linux | While the app is running: in-app timer at the due time. Otherwise on next start (catch-up). |

### 5.2 Trigger: price at or below target

1. After a run, the item's **best price** is the lowest `lastPrice` among its
   offers whose last check in this run is `ok` and whose currency equals the
   item currency.
2. The condition is `bestPrice <= targetPrice`.
3. **Rings every day while reached:** the alarm rings in every daily cycle in
   which a check finds the condition true — at most **once per cycle**,
   whichever check of the cycle (scheduled, catch-up on app open, Check now)
   finds it first. A cycle starts at the item's daily check time.
4. Editing the target price clears the ring state, so the new target may ring
   in the current cycle. `alarmActive` (the bell on the item) shows whether
   the last check found the condition true.
5. A run in which no offer is `ok` leaves `alarmActive` unchanged and does
   not ring. A run that checked only some offers (Android background, a
   WebView offer deferred) may ring, but cannot clear `alarmActive`. The failure is visible on the item (see 6.1); no notification in
   v0.1.
6. When the alarm fires, it **rings like an alarm clock** (5.3). Content:
   item name, best price with currency, shop name, target price.

### 5.3 Alarm ringing

1. The alarm plays a looping alarm sound until the user presses **Stop**, or
   automatically stops after **10 minutes** (`kAlarmRingDuration`). No snooze.
2. While it rings, a full-screen **alarm screen** shows item, best price,
   shop and target, with the buttons **Stop** and **Show item**.
3. Tapping the notification, or a full-screen launch over the lock screen,
   opens the alarm screen.
4. Per platform:

| Platform | Sound and volume | When it can ring |
|---|---|---|
| Android | The device's **default alarm-clock sound** on the **alarm audio stream** — the same volume as the alarm clock; plays in silent/vibrate mode; passes Do Not Disturb as long as "Alarms" are allowed there (Android default). Notification category `alarm`, sound repeats until dismissed (`FLAG_INSISTENT`), vibration, full-screen intent over the lock screen. | Also with the app closed (background run). |
| iOS | Bundled alarm sound in a loop, audio session `playback` (ignores the silent switch while the app is open). Volume = device media volume. | Only while the app is open — iOS gives v0.1 no background run, and a sound that breaks through silent mode with the app closed needs Apple's Critical Alerts entitlement or AlarmKit (planned, see §10). |
| macOS, Windows, Linux | Bundled alarm sound in a loop at full player volume, bounded by the system volume. System notification in addition. | While the app is running (checks only run then). |

5. The app never changes the system volume.
6. **Settings → Test alarm** rings exactly like a real alarm, so the user can
   check sound and volume.
7. Android 14+ may restrict full-screen alarms; Settings offers
   **Allow alarm over lock screen**, which opens the system permission page.
   Without it the alarm still rings as a heads-up notification.

## 6. Functional Requirements

### 6.1 Items

1. The user can create, edit, enable/disable and delete items.
2. Deleting an item deletes its offers and their history (after confirmation).
3. The items list shows per item: name, best current price (or "—"), target
   price, next check time, and a status indicator: alarm active / ok /
   at least one offer failing.
4. The list is sorted by name; items with an active alarm are listed first.

### 6.2 Offers

1. An item has at least one offer; the user can add, edit and remove offers.
2. When an offer URL is added, the user can run a **test fetch** that shows
   the extracted price, currency, availability and the mode used, before
   saving.
3. Each offer shows its last price, status, last check time and, when not
   `ok`, the reason. "Open in browser" opens the URL externally.

### 6.3 History

1. The item detail screen shows the price history per offer as a list
   (newest first). A chart is a planned feature.

### 6.4 Settings

1. Theme: system / light / dark.
2. Notifications: shows the permission state and a button to request it;
   on Android also "Allow alarm over lock screen" (5.3.7).
3. Test alarm (5.3.6).
4. Backup: export all data to a ZIP file and import it (replace all data).
5. About: version, licence (GPL-3.0), privacy notice, link to logs.
6. Logs: view, share and clear the app log file.

## 7. Platforms

Android, iOS, Linux, macOS, Windows — each with a debug and a release build.
Platform-specific limitations are those in 4.2 and 5.1; they are documented
in the README.

## 8. Non-functional Requirements

1. **Offline first:** all data is local (SQLite). Without network the app is
   fully usable; checks record `networkError`.
2. **No accounts, no telemetry.** The only network traffic is the shop page
   loads the user configured.
3. **Money as Decimal**, never `double`.
4. **No silent failures:** every check outcome is stored and visible; every
   caught error is written to the app log.
5. A run of one item with two offers completes within 2 minutes, including a
   WebView fallback (bounded by the timeouts in 4.2).
6. UI language English in v0.1; prices formatted with the `de_CH` locale
   (`CHF 2'209.00`).

## 9. Open Risks (to be resolved before or during v0.1)

| # | Risk | How it is resolved |
|---|---|---|
| R1 | Galaxus may block the WebView as well, or may not expose JSON-LD. | **Resolved 2026-11-21 (device test):** with the WebView, Galaxus delivers structured data (CHF 2'276.00, InStock); plain HTTP stays blocked (403). |
| R2 | `flutter_inappwebview` Linux support. | **Resolved 2026-11-21:** the stable 6.1.5 line has no Linux implementation. Linux reports `webview` offers as `unsupported` (or keeps `blocked` with the reason under `auto`); stated in the README. |
| R3 | A headless WebView inside the Android background isolate is not proven (upstream issue #1348 reported a broken platform channel). | **Tried with fallback:** the background run also loads WebView offers in a headless WebView (the plugin uses the application context without an Activity). A WebView offer that fails there is not recorded and stays due for the next foreground catch-up; HTTP offers are checked either way and may ring. Device verification pending. |
| R4 | Shops change their markup. | Extraction relies on schema.org data, not on CSS selectors; a failure shows up as `noPrice`, never as a wrong price. |

## 10. Planned Features

- Price drop by X % since last check (trigger)
- Back-in-stock trigger (availability is already stored)
- Notification when all offers of an item fail
- Price history chart
- iOS background refresh (`BGAppRefreshTask`)
- iOS alarm with the app closed: needs a background check first (above);
  then AlarmKit (iOS 26+, breaks through silent mode and Focus) could ring
  the result, or the Critical Alerts entitlement (requires Apple approval)
- Bring the desktop window to the front when the alarm rings
- Desktop tray / autostart so desktop checks run without the window open
- Currency conversion for foreign-currency offers
- Optional WebDAV/Nextcloud backup
