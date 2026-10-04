# AGENTS.md

Native macOS SwiftUI client for the App Store Connect API. Xcode project, no Swift package, no lint/test runner configs.

## Build / verify

```sh
plutil -lint "App Store.xcodeproj/project.pbxproj"
xcodebuild -project "App Store.xcodeproj" -scheme "App Store" -sdk macosx -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" build -skipMacroValidation
```

- Same build command CI (`.github/workflows/Build.yml`) runs on `macos-latest` / `latest-stable`. Match it exactly.
- Tests: `App Store Tests/` target (XCTest, `TEST_HOST` = app bundle). No CI test job; run focused suites from Xcode or `xcodebuild test -project ... -scheme "App Store" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`.
- No SwiftLint / formatter / typecheck beyond the compiler. `plutil -lint` is the pbxproj check — run it after any project-file edit.
- Deps resolve via Xcode SPM (`Datadog/swift-jsonapi` 0.1.5 pinned in pbxproj, `swift-syntax` transitive). Don't add Package.swift.

## Project-file gotcha

New `.swift` files must be added to `project.pbxproj` target membership or they silently don't compile. Hand-edits risk unbalanced parens — `plutil -lint` catches that before the build step.

## Architecture (active paths)

- Entry: `App_StoreApp.swift` (`@main`) → `ContentView/ContentView.swift` → `Shipyard/ShipyardShell.swift` (only shell). The legacy `SideBarView`/`DetailView`/reports/App-Info views were deleted; Shipyard reuses the shared VMs (`SideBarViewModel`, `DetailViewModel`, `BetaViewModel`, `ReviewsViewModel`, `ResourcesViewModel`), legacy `ReviewsView`, `DevicesView`, resource create-forms (`ResourcesView.swift`), and `ScreenshotsSheet.swift` (screenshots section is in `ShipyardAppInfoView`). Shared display helpers live in `Helper/BuildDisplaySupport.swift`.
- State: `SideBarViewModel` (apps/versions list) + `SideBarView/DetailView/DetailViewModel.swift` (builds, beta, app info, reviews, screenshots, reports VM was removed with the legacy shell) feed the UI. `NavigationManager.swift` holds login state / `ViewState<T>` / `ErrorRetryView`.
- Networking: `Model/JSONAPIModels/APIManager.swift` + `APIModels.swift` (`APIMethod`/`APIName` endpoint builder) + `BetaModels.swift`, `ReviewModels.swift`, `ResourceModels.swift`. JSON:API via `swift-jsonapi`; verify query params (`filter[]`, `include`, `sort`, cursor) against `APIManager`/`APIMethodTests`, not docs prose.
- Auth: hand-rolled ES256 in `JWT/`; token cached ~18 min, cleared on 401. Credentials in Keychain via `Helper/KeyChainHelper.swift` (`CredentialStorage`), never log them.
- Support: `Helper/` = `BuildProcessingMonitor` (MenuBarExtra poller), `AppTheme`/`AppAppearance`/`AppFont`, `FriendlyErrorMessage`, `StateView`. `AppConfigs.swift` = page limits + poll intervals (source of truth for numbers below).
- Docs drift: README advertises builds-table Markdown/CSV export — no such code exists on this branch (every `export` hit is export-compliance or Figma assets). Don't reference an `ExportManager`; treat export as missing, not broken.

## Conventions that differ from defaults

- Sorting is local over loaded pages, not server-side — the apps endpoint can't sort by state and mixing server sort with a cursor issued under another sort skips rows (`AppConfigs.swift`).
- Pagination is cursor + "Load More" everywhere: apps 50, versions 10, builds 5, reviews/resources 50, PROCESSING poll cap 50 (`AppConfigs`).
- Locale codes must be Apple's exact shortcodes (`de-DE`, `nl-NL`, default `en-US`); completeness matrix matters for Save All.
- Apple length caps validated client-side (name 2–30, subtitle ≤30, keywords ≤100, promo ≤170, description/whatsNew ≤4000, `http(s)` URLs only).
- Permission failures return "broader permissions" hints, not raw 403s — key role needed: TestFlight key = builds/notes, App Manager+ = app info writes, Admin = groups/testers/resources/users.
- Never commit the temp debug-logging marker in `APIManager.swift`: `scripts/block-temp-logging.sh` is a pre-commit/pre-push hook (install per clone: copy to `$(git rev-parse --git-dir)/hooks/`). It blocks pushes containing it; bypassing with `--no-verify` is not acceptable.

## Local-run keychain quirk

App is sandboxed (`ENABLE_APP_SANDBOX=YES` + `keychain-access-groups`): unsigned/ad-hoc builds get a fresh identity per build, so Keychain prompts on every launch and saved teams look "lost". Without a Developer account, set `ENABLE_APP_SANDBOX=NO` (Debug) or drop `keychain-access-groups` locally — but re-enable both before any App Store distribution. Either way you still need a real API key; without one the app shows "No Teams Yet".

## CI / PR notes

- PRs trigger an Ollama Cloud review (`kimi-k3:cloud`); `[skip-review]` in the title skips it, `[smoke-test]` runs connectivity only. `review-report` job posts the summary/troubleshooting.
- Test writes (devices, bundle IDs, groups) count against real limits — use throwaway IDs; device registration counts against the yearly limit.
