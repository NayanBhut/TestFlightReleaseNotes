# Prompt — Devices CSV Export (Figma `131:146`)

## Goal

Implement the missing **Devices → Export CSV** flow in `SideBarView/Resources/DevicesView.swift`
so it matches the Figma Devices specification. Everything else in the Devices flow already
exists — this is a **single-feature addition**, not a rewrite.

## Scope

**In scope**

1. Row multi-selection (checkbox + selected-row set).
2. Export config sheet — scope picker + destination.
3. Export progress state.
4. Export complete state + Reveal in Finder.

**Out of scope (already implemented — do not touch)**

- CSV *import*: `DeviceCSVImportSheet` (line 1195), `DeviceCSVResultSheet` (line 1292).
- Device detail inspector: `DeviceDetailView` (line 540).
- Enable/disable confirmation sheets: `EnableDeviceSheet` (line 1076), `DisableDeviceSheet` (line 935).
  *(A previous audit wrongly reported enable-confirmation as missing — it is present.)*
- Dependent profiles table, loading/empty/error/no-filter states.

## Figma source

File `NKXESyrVfM54hZAJb95QZj`. Node `131:146` is the whole Devices spec section.

| Stage | Node | Heading |
|---|---|---|
| Config | `114:11262` | Export Devices as CSV |
| Progress | `114:11302` | Exporting selected devices… |
| Complete | `114:11330` | CSV export complete |

> Generated Figma code is React + Tailwind. Convert to SwiftUI; do **not** add Tailwind.
> Use `figmaNew_get_design_context` with `skillNames: "resource:figma-design-to-code"`,
> `clientLanguages: "swift"`, `clientFrameworks: "SwiftUI"`.

### Sheet chrome (all 3 stages)

| Token | Value |
|---|---|
| Sheet bg | `#F6F6F6`, border `#D2D2D7`, corner radius 12 |
| Context bar | `#EAEAEB`, height 40, padding `.horizontal 24`, 11px `#6D6D72` |
| Context text | `v1.2 · Monitoring & shared operations · Acme Mobile` (verbatim) |
| Workspace | `#FFFFFF`, padding 24, gap 20 |
| Heading | 18px semibold (590), `#1E1E1E` |
| Section label | 13px semibold (590), `#1E1E1E` |
| Helper text | 12px regular, `#6D6D72` |
| Field label | 12px regular, `#1E1E1E` |
| Read-only input | bg `#F0F0F2`, border `#D2D2D7`, radius 6, min-height 30, padding `.horizontal 10` / `.vertical 7`, 13px `#6D6D72` |
| Editable input | bg `#FFFFFF`, border `#D2D2D7`, radius 6, same metrics, 13px `#1E1E1E`, trailing `⌄` chevron 12px `#6D6D72` |
| Primary action | `#007AFF`, height 28, padding `.horizontal 12`, radius 6, 12px white |
| Secondary action | bg `#FFFFFF`, border `#D2D2D7`, height 28, padding `.horizontal 12`, radius 6, 12px `#1E1E1E` |
| Action row | trailing aligned, gap 8, `.top` padding 4 |
| Radio | 15×15, radius 8; selected `#007AFF` + white dot; unselected `#FFFFFF` + border `#D2D2D7`; row gap 8, `.vertical` padding 4; title 13px `#1E1E1E`, sub 11px `#6D6D72` |

Reuse `DeviceStatusBanner` (line 866) — its `.info` tint is already `#007AFF` / wash `#E5F1FF`
and `.success` is `#248A3D` / wash `#EAF7EE`, exactly matching the design. Do **not** add a new banner.

### Stage 1 — Config (`114:11262`)

- Heading: `Export Devices as CSV`
- Section: `Export scope`
- Helper: `Columns: name, udid, platform, status, registered_date. Export describes the visible / cached snapshot, not a fresh Apple audit report.`
- Radio options (title / subtitle):
  1. `Selected rows` / `3 selected devices` — default when ≥1 row selected
  2. `Current filtered list` / `8 devices · Status: Enabled`
  3. `All cached team devices` / `10 devices · includes disabled`
- Field label `Destination`, value `~/Downloads/Shipyard/acme-devices.csv`, editable + chevron
- Actions: `Cancel` (secondary), `Export 3 Rows` (primary, count reflects chosen scope)

### Stage 2 — Progress (`114:11302`)

- Heading: `Exporting selected devices…`
- `DeviceStatusBanner(.info)`
  - title `Preparing CSV · 2 of 3 rows`
  - message `Illustrative local export progress. The selected scope and destination remain fixed.`
- Custom progress bar: track `#E5E5EA` height 6 radius 3; fill `#007AFF` height 6 radius 3.
  **Not** the stock `ProgressView` — the design is a flat 6px bar.
- Section `Export destination`
- Helper: `Cancel stops the unfinished export. Existing destination files require a Replace / Cancel confirmation before writing.`
- Field `File`, read-only input showing the destination
- Single action: `Cancel Export` (primary)

### Stage 3 — Complete (`114:11330`)

- Heading: `CSV export complete`
- `DeviceStatusBanner(.success)`
  - title `3 selected rows exported`
  - message `…acme-devices.csv · 1.2 KB · cached snapshot from <date>. No secrets included.`
- Section `Destination`, field `File`, read-only input
- Actions: `Reveal in Finder` (secondary), `Done` (primary)

## Code map (verified 2026-10-05)

| Concern | Location |
|---|---|
| `DevicesView` root, sheet modifiers | `DevicesView.swift:27`, `:126-204` |
| Toolbar (add Export button) | `:207-280` |
| Empty-state actions (`Import CSV…`) | `:387-393` |
| Row (add checkbox) | `:435-494` |
| Row context menu | `:474-489` |
| `DeviceStatusBanner` | `:866-929` |
| `DeviceCSVImportSheet` (mirror this chrome) | `:1195-1289` |
| Button styles `.launchPrimary` / `.launchSecondary` | `View/OnBoarding/LaunchAssistantSheet.swift:401-426` |
| `DeviceCSVRow` (import-only: name/udid/platform) | `Model/JSONAPIModels/ResourceModels.swift:302` |
| `importProgress: (done:total:)?` (pattern to copy) | `SideBarView/Resources/ResourcesViewModel.swift:878` |
| Theme tokens `AppTheme` / `ShipyardTheme` | `Helper/` |

Device row fields available for CSV (see row builder `:435-466`):
`device.name`, `device.udid`, `device.platform`, `device.status`, `device.addedDate`.

### Conventions to follow

- Sheets use `.sheet(isPresented:)` / `.sheet(item:)` with an `Identifiable` wrapper; follow
  `showCSVImporter` (`:46`) and the computed `disablePresented` / `enablePresented` bindings (`:131`, `:149`).
- Sheet body pattern: `VStack(alignment: .leading, spacing: 16)` → `.padding(24)` → `.frame(width: 560)`.
- Fonts: `.system(size:weight:)`, `ShipyardTheme.title` / `.body`. Monospaced UDIDs:
  `.font(.system(size: 11, design: .monospaced))`.
- Row is `.accessibilityElement(children: .combine)` + `.accessibilityAddTraits(.isButton)`.
  The new checkbox needs its **own** accessibility element/label — do not let it get swallowed by the combine.

## Implementation notes

- **Selection**: `@State private var selectedDeviceIds: Set<String>`.
  Keep click-to-open-detail working (`.onTapGesture` at `:471` sets `selectedDeviceId`) — do not
  hijack plain tap for selection. Selection via the row checkbox; add Cmd-click and a `Select All` /
  `Deselect All` control. Guard `.disabled` on export when the selected scope is empty.
- **Sandbox**: `ENABLE_APP_SANDBOX = YES` (pbxproj `:835`, `:869`). You cannot write to an arbitrary
  path. Use SwiftUI `.fileExporter(isPresented:document:contentType:defaultFilename:)`, which handles
  `NSSavePanel`, the security-scoped URL, **and** the Replace / Cancel confirmation the design calls for.
  Do not hand-roll `FileManager` writes to `~/Downloads`.
- **CSV**: RFC 4180 — quote any field containing `,`, `"`, `\n`; double embedded quotes. UTF-8,
  header row `name,udid,platform,status,registered_date`. Write incrementally so progress is real
  (matches `Preparing CSV · 2 of 3 rows`), or emit row-by-row into the document.
- **Progress**: add a separate `@Published var exportProgress: (done: Int, total: Int)?` in
  `ResourcesViewModel`; do not reuse `importProgress`.
- **Cancel Export**: cancel the running `Task`; the sheet must not leave a half-written file
  (write to a temp file then move, or delete the partial on cancellation).
- **Reveal in Finder**: `NSWorkspace.shared.activateFileViewerSelecting([url])`.
- **Copy is not literal**: `acme-devices.csv`, `3`, `8 devices · Status: Enabled`, `1.2 KB`, and the
  snapshot timestamp are all illustrative. Compute real values.

## Known pre-existing divergences (fix while in this file)

1. Sheet `spacing: 16` (`:1204`) vs Figma `gap 20`.
2. Sheet heading uses `weight: .bold` (`:1206`) vs Figma semibold 590.
3. `DeviceStatusBanner` icon is a filled SF Symbol (`info.circle`), the design shows a bare `ⓘ` glyph.

## Constraints

- Production API data. Export is **local-only** and read-only — it must issue no network calls and
  mutate nothing. Never test register/disable/enable against the real team without explicit approval.
- Verify with:
  ```sh
  plutil -lint "App Store.xcodeproj/project.pbxproj"
  xcodebuild -project "App Store.xcodeproj" -scheme "App Store" -sdk macosx -configuration Debug \
    CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" build -skipMacroValidation
  ```
- Only this file needs editing; no new files, so no `project.pbxproj` target-membership work.
- `scripts/block-temp-logging.sh` is a pre-commit hook; never leave temp debug logging in `APIManager.swift`.
- Baseline: 67 tests pass; `ValidationTests.testLoadCSRMissingFile` fails pre-existing on a clean tree.

## Live verification

Bundle ID `com.demos.App-Store`. Built app:
`~/Library/Developer/Xcode/DerivedData/App_Store-*/Build/Products/Debug/App Store.app`

```sh
open -a "$HOME/Library/Developer/Xcode/DerivedData/App_Store-hjjhrpenpofrqbeouumdemmiqmbe/Build/Products/Debug/App Store.app"
```

Prefer `orca computer`; fall back to the `macos-ui-automation` MCP tools.

```sh
/Applications/Orca.app/Contents/Resources/bin/orca computer get-app-state \
  --app com.demos.App-Store --restore-window --json     # read result.snapshot.treeText
/Applications/Orca.app/Contents/Resources/bin/orca computer click \
  --app com.demos.App-Store --element-index <n> --json
```

MCP: `macos-ui-automation_find_elements_in_app`, `macos-ui-automation_click_at_position`,
`macos-ui-automation_click_element_by_selector`, `macos-ui-automation_get_element_details`.

Caveats:

- Element indexes are short-lived — re-read state after every action; never infer them from counts.
- `/usr/local/bin/orca` is a broken symlink; always use the `/Applications/Orca.app/...` path.
- The AX window is often **not focused**; use `--restore-window`, and re-check if you get
  `window_not_focused`.
- Screenshots are unusable for some agent models. Drive verification off `treeText` and the Figma
  code context, not pixels.

## Acceptance checklist

- [ ] Checkbox selects/deselects; `Select All` reflects the filtered set; selection survives paging.
- [ ] Config sheet shows correct live counts per scope; `Export N Rows` tracks the chosen scope.
- [ ] Default scope = `Selected rows` when selection is non-empty, else `Current filtered list`.
- [ ] Empty scope disables export; `Cancel` closes with nothing written.
- [ ] Progress bar is the flat 6px bar and counts real rows.
- [ ] `Cancel Export` stops the run and leaves no partial file.
- [ ] Completing writes a valid RFC 4180 CSV with the 5 specified columns.
- [ ] Replacing an existing file shows the Replace / Cancel confirmation.
- [ ] `Reveal in Finder` selects the written file.
- [ ] Enable/disable/import/detail flows still work unchanged.
- [ ] Accessibility: checkbox is individually addressable; rows keep `.isButton` + hint.
- [ ] `plutil -lint` and `xcodebuild` both pass.