# PriceAlarm — Screens

Status: v0.1 implemented · Last updated: 2026-11-21

Mobile = width < 600 dp (bottom `NavigationBar`), desktop = ≥ 600 dp
(`NavigationRail`, extended above 1200 dp). Two top-level destinations:
**Items** and **Settings**.

---

## 1. Items list (`/items`)

Mobile:

```
┌────────────────────────────────┐
│ PriceAlarm                  ⟳  │
├────────────────────────────────┤
│ ┌────────────────────────────┐ │
│ │ 🔔 ASUS Radeon AI PRO R9700 │ │
│ │ CHF 2'189.00  ≤ 2'200.00   │ │
│ │ Brack · next 08:00 tomorrow│ │
│ └────────────────────────────┘ │
│ ┌────────────────────────────┐ │
│ │ ⚠ Some other item          │ │
│ │ CHF 349.00   target 299.00 │ │
│ │ 1 of 2 offers failing      │ │
│ └────────────────────────────┘ │
│                                │
│                          ( + ) │
├────────────────────────────────┤
│   [Items]        Settings      │
└────────────────────────────────┘
```

Desktop: same cards side by side in a wrap layout (cards up to 420 dp wide,
height follows content so large system fonts cannot overflow), rail on the
left.

Behaviour:
- Card tap → Item detail. FAB `+` → Add item.
- `⟳` runs all enabled items now (progress indicator in the app bar while
  running).
- Status icon: 🔔 alarm active (primary colour), ⚠ at least one offer not `ok`
  (`colorScheme.error`), none = all ok. Disabled items are greyed out with
  "paused".
- Price line: best price, then target. Best price shown in green when
  ≤ target.
- Empty state: "No items yet — add a product to watch" + button.
- Loading: centred progress indicator. Error: `ErrorView` with retry.

## 2. Item detail (`/items/:id`)

Mobile:

```
┌────────────────────────────────┐
│ ←  ASUS Radeon AI PRO R9700  ✎ │
├────────────────────────────────┤
│ Best  CHF 2'189.00 (Brack)     │
│ Target CHF 2'200.00   🔔 active │
│ Daily at 08:00 · last 08:03    │
│ [ Check now ]                  │
├────────────────────────────────┤
│ Offers                         │
│ ┌────────────────────────────┐ │
│ │ Brack          CHF 2'189.00│ │
│ │ ✓ ok · http · OutOfStock   │ │
│ │ today 08:03          ↗     │ │
│ └────────────────────────────┘ │
│ ┌────────────────────────────┐ │
│ │ Galaxus               —    │ │
│ │ ⚠ blocked (HTTP 403)       │ │
│ │ today 08:03          ↗     │ │
│ └────────────────────────────┘ │
├────────────────────────────────┤
│ History                        │
│ 21.11. 08:03 Brack   2'189.00  │
│ 21.11. 08:03 Galaxus blocked   │
│ 20.11. 08:01 Brack   2'209.00  │
│ …                              │
└────────────────────────────────┘
```

Desktop: two columns: summary + offers on the left, history on the right.

Behaviour:
- `✎` → Edit item. `↗` opens the offer URL in the system browser.
- "Check now" runs this item; button shows a spinner and is disabled while
  running.
- Platform hint under the schedule line where relevant, e.g. on iOS:
  "Checks run when you open the app."
- Offer status line: status, mode used, availability (informational).
  Foreign-currency offers show "not compared (EUR)".
- History: newest first, 50 entries, "Show more" loads the next 50.
- Item not found (deleted): pop back to the list.

## 3. Add / Edit item (`/items/new`, `/items/:id/edit`)

Mobile:

```
┌────────────────────────────────┐
│ ✕  New item               Save │
├────────────────────────────────┤
│ Name                           │
│ [ASUS Radeon AI PRO R9700    ] │
│ Target price (CHF)             │
│ [2200.00                     ] │
│ Daily check time               │
│ [08:00                    🕐 ] │
│ [✓] Enabled                    │
├────────────────────────────────┤
│ Offers                         │
│ ┌────────────────────────────┐ │
│ │ https://www.brack.ch/asus… │ │
│ │ Brack · auto      [Test] 🗑 │ │
│ │ ✓ CHF 2'209.00 · http      │ │
│ └────────────────────────────┘ │
│ ┌────────────────────────────┐ │
│ │ https://www.galaxus.ch/de… │ │
│ │ Galaxus · auto    [Test] 🗑 │ │
│ │ ⚠ blocked → trying webview…│ │
│ └────────────────────────────┘ │
│ [ + Add offer URL ]            │
├────────────────────────────────┤
│ (edit only)  [ Delete item ]   │
└────────────────────────────────┘
```

Desktop: same form, max width 640 dp, centred.

Behaviour:
- Validation: name required; target > 0 with ≤ 2 decimals; at least one offer;
  URL must be `https://`; duplicate URL in the same item rejected.
- Shop name auto-filled from the host on URL entry, editable.
- Fetch mode via a dropdown (auto / http / webview); on platforms without
  WebView, `webview` is disabled with a tooltip.
- `[Test]` runs one check without saving and shows the result inline
  (price, currency, availability, mode, or the failure reason).
- Changing the target price re-arms the alarm (REQUIREMENTS 5.2.4); the form
  says so under the field when the alarm is active.
- Delete item → confirmation dialog → back to the list.
- Unsaved changes + ✕ → "Discard changes?" dialog.

## 4. Settings (`/settings`)

```
┌────────────────────────────────┐
│ Settings                       │
├────────────────────────────────┤
│ Appearance                     │
│   Theme          System ▾      │
│ Notifications                  │
│   Permission     Granted ✓     │
│ Data                           │
│   Backup & restore         ›   │
│ About                          │
│   About PriceAlarm         ›   │
│   App logs                 ›   │
├────────────────────────────────┤
│   Items        [Settings]      │
└────────────────────────────────┘
```

Behaviour:
- Permission row shows "Request" button when not granted; on desktop
  platforms where no permission exists, the row reads "Not required".

## 5. Backup & restore (`/settings/backup`)

- "Export" writes `pricealarm_YYYYMMDD_HHmmss.zip` (save dialog on desktop,
  share sheet on mobile).
- "Import" picks a ZIP → confirmation "Replace all data?" → result snackbar
  ("Imported 3 items, 5 offers, 412 checks").

## 6. About (`/settings/about`) and Logs (`/settings/logs`)

- About: app name, version + build number, licence notice (GPL-3.0),
  privacy notice ("No data leaves the device except the page loads of the
  shops you add"), link to Logs, licences page.
- Logs: monospace scrollable view of the log file, newest at the bottom;
  actions Share and Clear (with confirmation).

## 7. Notification

```
PriceAlarm
ASUS Radeon AI PRO R9700 — CHF 2'189.00 at Brack
(target CHF 2'200.00)
```

Tap → opens `/items/:id`.

## 8. Screen Flow Summary

```
Items list ──tap card──▶ Item detail ──✎──▶ Edit item
   │                        ▲                  │
   └──+──▶ New item ─save───┘◀──save───────────┘
Notification ──tap──▶ Item detail
Settings ──▶ Backup & restore
         ──▶ About ──▶ Logs
         ──▶ Logs
```
