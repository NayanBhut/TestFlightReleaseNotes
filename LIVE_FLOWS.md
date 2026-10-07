# Live Flow Pass — `orca computer` (2026-10-03)

Build: Debug, `CODE_SIGNING_ALLOWED=NO`, **BUILD SUCCEEDED**.
App launched from DerivedData (`com.demos.App-Store`). A real team was already
saved and loaded live API data — so this pass ran against the **production API
with real data, under strict read-only discipline**: no Save / Invite / Cancel /
Revoke / Delete / Submit / Register was invoked anywhere.

## Sections verified rendering with live data

| Section | Result |
|---|---|
| Apps list | 1 app, filter + status/sort menus + refresh render; row shows icon, name, bundle, state (`PREPARE_FOR_SUBMISSION`), platform |
| Devices | 7 rows (name/UDID/platform/status/date), search + platform filter + Register render |
| Certificates | Loads (`Loading certificates…` → 2 rows, Active) |
| Bundle IDs | Loads (`Loading bundle IDs…` → 6 rows), search + New button render |
| Profiles | 2 rows, Active |
| Users | 2 users with roles/statuses, search + Invite render |
| Reviews | App picker auto-selected the app; rating/state filters + search render; 3 review-submission rows (`READY_FOR_REVIEW`, Cancel buttons left untouched); Customer Reviews empty state correct |
| Processing Builds | Empty state (`No Processing Builds…`) + count badge `0`; **Check Now works** (re-polled, no error, still 0) |

Navigation: every sidebar section switches correctly via accessibility clicks;
loading → loaded transitions observed on Certificates/Bundle IDs/Profiles/Users.

## New live findings (not in BUG_SWEEP.md)

- **L1 — Bundle IDs search doesn't filter.** Typed `clean` into Search Bundle
  IDs (value confirmed in field + screenshot): all 6 rows still shown after
  8 s. Only 2 match. No error.
- **L2 — Apps search doesn't filter.** Typed `zzz` into Filter Apps: the
  non-matching row stays, Total stays `1`, after 4 s.
- Caveat on L1/L2: text entered via accessibility `set-value` (value confirmed
  visible in the field). If these filters are submit-on-Return, that path is
  untested — Return/typing needs window focus (see limits). Still, `.searchable`
  /
  `onChange` filters should react to binding changes; worth checking in code.

## Second pass (same day, pid-targeted) — NEW

- **App drill-down works, no code change needed.** App rows are native
  `Button`s with `accessibilityLabel` (`AppsTableView.swift:253`) — the row
  was tree element `29 button` all along. Clicking it opened app detail:
  breadcrumb, tabs (Builds/TestFlight/App Info/Reviews/App Store Versions),
  version picker, Filter Status.
- **Builds table:** 1 build (`VALID`, expires Nov 2026 — bug #5's expired
  display not observable here). Manage opened build detail.
- **Build detail:** Release Notes editor (en-US, `15 / 4,000`, `Saved`),
  snippet menu, Revert/Delete/Save buttons (untouched — real account);
  Groups tab empty state correct; Compliance tab empty state correct;
  BUILD METADATA panel correct. VALID pill shown for a non-expired build.
- **TestFlight tab:** version/build selectors + notes editor render. **App Info
  tab:** validation copy renders (`Name must be at least 2 characters`,
  counters, disabled-until-localization fields).
- **Team menu accident:** index 1 was the team switcher, not Back — menu opened
  showing a remove-team control; dismissed via toggle, nothing touched.
  Lesson: verify Back targets by tree position, never click near remove controls.
- **Unfinished when helper stalled:** app-detail Reviews tab, App Store
  Versions tab (both one click away, no code needed).
- **A11y edits made (additive, build passes):** `accessibilityHint` on app
  rows (`AppsTableView.swift:254`) and build rows (`BuildsTableView.swift:311`).
  No structural change required — the `Button`+label and
  `onTapGesture`+`isButton`+`accessibilityAction`+label patterns already work.

## Third pass (fresh build with hints, pid-targeted) — NEW

- App-detail **Reviews tab**: same data as sidebar Reviews (3 submissions,
  empty customer list, filters) — no per-tab desync.
- **App Store Versions tab**: sub-tabs (Overview/All Versions/Resolution
  Center/Builds), version table (1.0 · Draft · #1), detail card. **Version 1.0
  detail opens**: What's New editor, Build selector, release-type radios,
  phased release, contact fields, sign-in toggle, review notes, missing-item
  banner (`Add a locale in App Info, then write What's New`), footer
  `Missing: What's New`, Save + Submit (both untouched — real account).
- Settings popover opens/closes cleanly via its `cancel` AX action; checkboxes
  untouched. Team menu opened by mis-click, dismissed via toggle — nothing
  touched (remove-team control visible but never activated).
- L1/L2 not retested (filter code unchanged by the hint-only edit; prior
  evidence stands).
- Deliberately untested live: Add-Team (would disturb the real saved team),
  all write/submit/delete actions (real account).

## Environment limits (not app verdicts)

- **No window focus attainable** (`window_not_focused`, `activate` didn't help):
  coordinate `click`, `press-key`, `hotkey`, `type-text` all blocked. Only
  accessibility-index `click` / `set-value` worked.
- **`osascript` denied assistive access** (-25211): no synthetic mouse fallback.
- **Table rows aren't in the AX tree** (Apps/Builds tables expose headers only;
  resource tables expose row containers but App rows don't). Consequence: **app
  drill-down unreachable → builds, release notes, beta groups, app info,
  version/release flows untested live.**
- **Menu/dialog surfaces unsupported** by this provider build: sort/filter
  popups, team switcher menu, and all create wizards unopened; Cancel/Submit
  buttons deliberately untouched (real account).
- `AXShowMenu` on a device row failed (`AXUIElementPerformAction failed`)
  although `.contextMenu` (Enable/Disable + confirmation) is wired in
  `DevicesView.swift:314-339` — tooling limitation, not an app verdict.

## Follow-up for a focused session (real mouse + focus)

1. Re-test L1/L2 with physical keystrokes + Return.
2. Drill into the app row → builds → build detail → notes editor, beta, app info.
3. Open (don't submit) Register/Invite/New wizards; verify Cancel paths.
4. Device row right-click → Disable confirmation dialog (code-verified, live-untested).

Screenshots: `/var/folders/4_/tdy_x1fs7s3gc2r8_dcnj644jb9qsb/T/orca-computer-use/*.png`
(expire ~24 h). Skill doc: `docs/ORCA_COMPUTER_USE.md`.
