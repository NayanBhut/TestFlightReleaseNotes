# TestFlight Release Notes [![Swift](https://github.com/NayanBhut/TestFlightReleaseNotes/actions/workflows/Build.yml/badge.svg?branch=main)](https://github.com/NayanBhut/TestFlightReleaseNotes/actions/workflows/Build.yml)

A native macOS (SwiftUI) client for the App Store Connect API. Browse apps, pre-release versions, and TestFlight builds, and manage release notes (`whatsNew`), beta groups/testers, app info localizations, customer reviews, and team resources — without opening the App Store Connect web portal.

## Why Use This App? (Real-Time Use)

Releasing a TestFlight build normally means: upload from Xcode → wait for processing → open App Store Connect in a browser → click through Apps → TestFlight → build → fill in "What to Test" per locale → add groups/testers → check processing state by refreshing the page. This app collapses that loop into one native window:

- **Release-day TestFlight notes:** after Xcode finishes uploading, watch the build flip `PROCESSING` → `VALID` from the menu bar (with a local notification), then paste/type `whatsNew` once and push it to all 50 locales with **Save All** — including the locale-completeness check so no region ships an empty note.
- **No-refresh build tracking:** the menu-bar monitor polls every 120 s and notifies you on terminal states, instead of you refreshing the browser.
- **Beta ops in one place:** invite a tester by email, assign the new build to the external group, toggle auto-notify, and submit the external review — without switching between TestFlight tabs.
- **Store-listing fixes without the portal:** correct an app name, subtitle, keywords, or description inline (with Apple length validation up front) and export-compliance info, then reply to a 1-star customer review from the same window.
- **Team hygiene:** register a test device, revoke a leaked certificate, create a provisioning profile, or invite a new developer — tasks otherwise buried across Certificates/Identifiers/Profiles/Users pages.
- **Handoff-friendly:** export the builds table to Markdown/CSV for release notes, QA sign-off, or Slack updates.

**Who is it for:** iOS developers, release managers, QA leads, and indie makers who ship via TestFlight weekly/daily and live in Xcode rather than the browser.

## What You Need (Prerequisites)

**Apple side:**
- An Apple Developer Program membership with at least one app in App Store Connect.
- An App Store Connect user with **Admin** or **Account Holder** role to create API keys (a Developer-role user cannot create keys).
- One API key per team you want to manage (the app supports multiple teams; each is stored separately in Keychain).

**Mac side:**
- macOS 14.0 or later.
- The `.p8` private key file downloaded when the API key was created (Apple shows it **only once** — if lost, revoke and create a new key).
- The **Issuer ID** (team-scoped, shared across keys) and **Key ID** (per key).

**Key roles (pick at creation — decides what the app can do):**
| Key access | Unlocks in this app | Minimum role |
|---|---|---|
| TestFlight / limited | Browse apps, versions, builds; read/write release notes (`whatsNew`); read beta groups | Developer + TestFlight access |
| App Manager | Above + edit App Info / version localizations | App Manager |
| Admin | Above + manage beta groups/testers, devices, certificates, bundle IDs, profiles, users | Admin |

> If an action fails with a permission hint instead of data, your key's role is too narrow — create a broader key or ask an Admin.

## How to Create an API Key (Step by Step)

1. Sign in at https://appstoreconnect.apple.com/access/api with an **Admin/Account Holder** Apple ID.
2. Go to **Integrations → App Store Connect API** (older UI: **Users and Access → Integrations → Team Keys**).
3. Click **+ / Generate API Key** (or "Request Access" first if your team never enabled API access).
4. Enter a name you'll recognize (e.g. `release-notes-mac`), and choose the access/role:
   - Start with **Admin** if you want every feature in this app; otherwise match the table above.
5. Click **Generate**. Copy and store three things immediately:
   - **Issuer ID** — shown at the top of the page (same for all keys on the team).
   - **Key ID** — shown next to your new key.
   - **Private key** — click **Download** to get the `.p8` file. **This is the only chance** — Apple never shows it again.
6. In this app: **Add Team** (or `+`) → enter a unique Team Name (any label, e.g. `Acme iOS`) + Issuer ID + Key ID + private key:
   - Either click **Select File** and pick the `.p8` (header/footer stripped automatically), or
   - Open the `.p8` in a text editor, copy the contents, and paste **without** the `-----BEGIN PRIVATE KEY-----` / `-----END PRIVATE KEY-----` lines and without extra spaces/line breaks.
7. Click **Continue**. The app signs a test JWT locally, fetches your app list to validate, and only then saves the credential to Keychain. Errors you may see:
   - `Invalid JWT credentials` → wrong Key ID / Issuer ID / `.p8` mismatch.
   - `Authentication failed. Please check your credentials.` → key revoked/expired, or network issue.
   - `No apps found for this team` → key is valid but has no app access, or the team truly has no apps.
   - `Couldn't save the team to the Keychain` → macOS Keychain denied access; retry and approve the prompt.

To manage another team/vendor, repeat steps 3–7 with a new Team Name — the sidebar team switcher flips between them.

## What This App Supports

| Area | Read | Write | Notes |
|---|---|---|---|
| Apps / versions / builds | ✅ list, search, filter, sort, paginate | — (expire build only) | 10 apps / 10 versions / 5 builds per page, Load More |
| Release notes (`whatsNew`, 50 locales) | ✅ per-build, completeness matrix | ✅ create / update / delete, Save All, snippets | Exact Apple locale codes (`de-DE`, `nl-NL`); default `en-US` |
| Beta groups & testers | ✅ groups, testers, review status | ✅ invite/add/remove, assign build, auto-notify, submit review, CRUD groups | External review submit supported; status check included |
| App Info & version localizations | ✅ general, age rating, categories, export compliance | ✅ inline edit name/subtitle/keywords/description/URLs | Apple length caps validated client-side; needs App Manager+ |
| Customer reviews & replies | ✅ list, filter (rating/replied/text), sort | ✅ create / edit / delete replies | 50 per page; needs appropriate role |
| Devices | ✅ list | ✅ register / enable / disable (disable = revoke) | No API delete; registrations count against yearly limit |
| Certificates | ✅ list | ✅ create (CSR) / revoke | Keep CSR safe; revoking can break provisioning |
| Bundle IDs | ✅ list | ✅ create / rename / delete | Use throwaway IDs for tests |
| Provisioning profiles | ✅ list | ✅ create (pick certs/devices/bundle) / delete | — |
| Users & invitations | ✅ list | ✅ invite / edit roles / remove, resend invite | Admin key required |
| Export | ✅ Markdown / CSV, copy / save / share / reveal | — | CSV formula-injection guarded; temp files purged after 24 h |
| Build monitoring | ✅ menu-bar `PROCESSING` poll + notifications | — (Check now / Open App / Quit) | 120 s poll, 300 s backoff on error, 50-build cap |

Not supported (Apple has no public API or it's web-only): sales/finance reports, screenshot/asset upload, review-submission create/cancel, phased releases, in-app events (deep-linked to the portal instead), webhooks.

## Features

### Apps, Versions & Builds
- App list sidebar with search (local + debounced server-side `filter[name]`), app-state filter, name/state sorting, cursor pagination, and cached app icons.
- Pre-release versions per app (`filter[app]`, newest first) with pagination.
- Builds per version with processing state (`PROCESSING` / `VALID` / `FAILED` / `INVALID` / `EXPIRED`), upload dates, version/build IDs, and deep links to App Store Connect.

### Release Notes (TestFlight `whatsNew`)
- Per-build editor covering 50 Apple locales (`en-US` default; exact codes such as `de-DE` / `nl-NL` required).
- Create (`POST`), update (`PATCH`), and delete (`DELETE`) beta build localizations.
- Bulk **Save All**, dirty-diff review, locale-completeness matrix, snippet menu, and expire-build action.

### Beta Groups & Testers
- List internal/external groups (incl. public links), view testers, invite by email or from team users.
- Add/remove testers, assign builds to groups, toggle auto-notify, submit external review and check its status.
- Create/rename/delete groups.

### App Info
- General info (Apple ID, bundle ID, SKU, primary locale), app info state, age rating, categories, and export compliance.
- Inline editors for app info and live-version localizations with client-side validation (name 2–30 chars, subtitle ≤ 30, keywords ≤ 100, promo ≤ 170, description/whatsNew ≤ 4000, `http(s)` URLs only).

### Reviews
- Beta review submissions plus customer reviews (rating/date sort, 50 per page).
- Filter by rating, replied/unreplied state, and text; create/edit/delete developer replies.

### Team Resources
- Devices (register/enable/disable — disable revokes, there is no delete), certificates (create/revoke + CSR), bundle IDs, provisioning profiles, users and invitations.
- Invite/edit-roles/remove users, resend invitations.

### Export & Monitoring
- Export builds to Markdown or CSV (formula-injection guarded), copy to clipboard, save/share file, or reveal in Finder.
- Menu-bar build monitor polls `filter[processingState]=PROCESSING` every 120 s (300 s backoff on error) with count badge, per-build rows, and local notifications on `PROCESSING` → terminal-state transitions.

### Auth & Security
- Multi-team support; credentials (Issuer ID, Key ID, `.p8` private key) stored in Keychain and never logged.
- ES256 JWT signing (20-min expiry, cached ~18 min, cleared on 401); DEBUG-only redacted logging.

## Setup

1. Go to https://appstoreconnect.apple.com/access/api and create an API key. Note the **Issuer ID**, **Key ID**, and download the `.p8` private key (one-time download).
2. Run the app and choose **Add Team** (or `+`).
3. Enter a unique team name plus the Issuer ID, Key ID, and private key (paste the key with or without the `-----BEGIN/END PRIVATE KEY-----` header/footer, or use **Select File**).
4. Choose **Continue** — the app signs a JWT, test-fetches your apps to validate, then saves the credential to Keychain.

> **Key roles matter:** a TestFlight-only key covers builds/notes; App Info writes need **App Manager+**; Resources / beta-group writes and user management need **Admin**. Permission errors surface a "broader permissions" hint instead of a raw 403.

## Requirements

- macOS 14.0+
- Xcode with the macOS 14 SDK (CI builds with `latest-stable` on `macos-latest`)
- Swift 5, SwiftUI (`NavigationSplitView`, `MenuBarExtra`)
- Dependencies (SPM): `Datadog/swift-jsonapi` 0.1.5, `swift-syntax` 510.0.3 (transitive)

Build from source:

```sh
xcodebuild -scheme "App Store" -sdk macosx CODE_SIGNING_ALLOWED=NO build
```

## Project Structure

```
App_StoreApp.swift        @main entry: main window + MenuBarExtra monitor
ContentView/              NavigationSplitView shell + Add-Team overlay
NavigationManager.swift   login state, ViewState<T>, ErrorRetryView
AppConfigs.swift          page limits, poll intervals, sort/filter enums
SideBarView/              apps + versions list, detail tabs (builds, beta, app info, reviews), team resources
Model/JSONAPIModels/      APIClient, endpoints (APIMethod/APIName), JSON:API models
Helper/                   Keychain storage, ExportManager, BuildProcessingMonitor, image cache, extensions
JWT/                      ES256 signing (EC key, ASN.1, JWT encode/decode)
View/OnBoarding/          Add-Team flow + view model
App Store Tests/          XCTest: API methods, JSON decoding, view state, display helpers, validation
docs/BATCH_I_PLAN.md      write-features plan, API gotchas and limits
scripts/                  pre-commit / pre-push guards (e.g. block temp logging)
```

## Testing

Xcode unit tests live in `App Store Tests/` (API method construction, JSON:API decoding, view-state transitions, build display helpers, input validation). CI (`.github/workflows/Build.yml`) lints the project file and builds the `App Store` scheme with signing disabled.

## Limitations

- Page sizes: 10 apps, 10 versions, 5 builds per page (cursor-paginated with Load More); 50 reviews and 50 resources per page; build-status poll capped at 50 `PROCESSING` builds.
- Apple metadata caps are enforced client-side (see App Info above); locale codes must match Apple's exact shortcodes.
- Key-role gated writes return permission hints (see Setup).
- Out of scope: sales/finance reports, screenshot/asset upload, review-submission create/cancel, phased releases, in-app events (deep-linked only), webhooks, and web-only App Store Connect actions.
- Test writes on throwaway bundle IDs/devices/groups — device registrations count against your yearly limit.
