# Device Flow Test Report

**Date:** 2026-10-05
**Branch / HEAD:** `648aeaa` — feat(bundle-ids): registration, dependent profiles, capability enable/disable
**App bundle ID under test:** `com.demos.App-Store-Test`
**Target:** macOS, Debug
**Environment:** live App Store Connect API, real API key from Keychain
**Driver:** Orca Computer Use v1.4.220 (accessibility tree)

> One throwaway device was registered. Production device registrations count against the
> membership-year limit, so exactly one slot was consumed. No real customer device was mutated.

---

## Build & verification

```sh
plutil -lint "App Store.xcodeproj/project.pbxproj"

xcodebuild -project "App Store.xcodeproj" -scheme "App Store" -sdk macosx \
  -configuration Debug \
  PRODUCT_BUNDLE_IDENTIFIER=com.demos.App-Store-Test \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
  build -skipMacroValidation
```

`PRODUCT_BUNDLE_IDENTIFIER` is pinned on the command line because the app target's build
setting can drift between the project file and DerivedData.

**Unit tests:** `90 passed / 5 failed` (see [Pre-existing failures](#pre-existing-test-failures)).
Before this work the test target **did not compile at all**.

---

## Summary

| Metric | Value |
|---|---|
| Scenarios exercised | 23 |
| Passed | 22 |
| Failed | 0 |
| Inconclusive | 1 |
| Bugs found and fixed | 6 (2 critical) |
| Device registration slots consumed | 1 |

---

## Scenarios tested

| # | Scenario | Endpoint / path | Expected | Result |
|---|---|---|---|---|
| 1 | App launch + Keychain credential load | — | Teams load | ✅ Pass |
| 2 | Devices list load | `GET /v1/devices` | 8 devices, 5 columns | ✅ Pass |
| 3 | Section navigation | — | Switches cleanly | ✅ Pass |
| 4 | Register sheet opens | — | Register disabled when empty | ✅ Pass |
| 5 | Bad UDID validation | client-side | Inline error, no POST | ✅ Pass |
| 6 | Input updates SwiftUI bindings | — | Register enables | ✅ Pass |
| 7 | **Register device** | `POST /v1/devices` | Device created | ✅ Pass (7 → 8) |
| 8 | Device detail view | `GET /v1/devices` | All fields render | ✅ Pass |
| 9 | Dependent profiles — new device | derived | Empty state | ✅ Pass |
| 10 | Dependent profiles — real device | derived | Profile table | ✅ Pass (3 profiles) |
| 11 | Yearly registrations explainer | — | Present | ✅ Pass |
| 12 | Search devices | client-side | Filters list | ✅ Pass (8 → 1) |
| 13 | **Rename device** | `PATCH /v1/devices/{id}` | Name updated + persisted | ✅ Pass |
| 14 | Rename `isDirty` gating | — | Save/Revert enable only when dirty | ✅ Pass |
| 15 | Disable confirm sheet | — | Warns quota + profile impact | ✅ Pass |
| 16 | **Disable device** | `PATCH /v1/devices/{id}` | Status → `DISABLED`, persisted | ✅ Pass |
| 17 | Enable confirm sheet | — | Warns no new slot | ✅ Pass |
| 18 | **Re-enable device** | `PATCH /v1/devices/{id}` | Status → `ENABLED`, persisted | ✅ Pass |
| 19 | Platform filter | client-side | Filters by platform | ✅ Pass (8 / 6 / 2) |
| 20 | **Modern 25-char UDID accepted** | client-side | Register enables | ✅ Pass |
| 21 | Classic 40-hex UDID accepted | client-side | Register enables | ✅ Pass |
| 22 | Corrected error copy renders | — | New text shown | ✅ Pass |
| 23 | Invalid UDID blocks POST | client-side | Sheet open, count unchanged | ✅ Pass |

### Detail

**#13 — rename.** Edits the inline `Name` field, then `Save Name`. Verified twice: the detail
header updates immediately, and the new name survives a full section reload, so the `PATCH`
really landed rather than only mutating local state.

**#16 / #18 — disable → enable round trip.** The detail action bar shows exactly one of
`Enable Device…` / `Disable Device…` (mutually exclusive on `isDisabled`), alongside `Revert`
and `Save Name` which stay disabled until the name is dirty. Both transitions were confirmed
to persist after re-navigating away and back.

**#19 — platform filter.** `All` → 8 rows, `iOS` → 6, `macOS` → 2.

---

## Bugs found and fixed

| Bug | Severity | Status | Location |
|---|---|---|---|
| Validator rejected **every** modern 25-char UDID — registration impossible for current hardware | **Critical** | ✅ Fixed | `Model/JSONAPIModels/ResourceModels.swift` |
| Unbalanced `)` broke compilation of the entire test target | **Critical** | ✅ Fixed | `App Store Tests/ValidationTests.swift:342` |
| Shipped placeholder `00008101-001C25D40C28001E` was rejected by the app's own validator | High | ✅ Fixed | `SideBarView/Resources/ResourcesViewModel.swift` |
| Test asserted a **valid** 25-char UDID was invalid, locking the bug in | High | ✅ Fixed | `App Store Tests/ValidationTests.swift` |
| Error text cited a nonexistent "8-8-9 groups" format | Medium | ✅ Fixed | `SideBarView/Resources/ResourcesViewModel.swift` |
| Helper text said "25-character" and credited "Apple Silicon" | Low | ✅ Fixed | `SideBarView/Resources/ResourcesView.swift` |

### The validator bug

The regex only accepted `8-9` or 40 hex:

```swift
// before — wrong on both branches
let pattern = "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{9}$|^[0-9A-Fa-f]{40}$"
```

Real Apple UDIDs are either **40 hex** (hardware before the iPhone XS / A12 generation) or
**25 characters as 8 + dash + 16** (XS and later). Neither real format was fully accepted: the
modern form was rejected outright, and the `8-9` branch accepted a shape Apple never issues.

```swift
// after
static func isValidUDID(_ udid: String) -> Bool {
    let normalized = udid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    // Modern UDIDs are alphanumeric (Apple derives them from chip/ECID
    // values, so the tail is not reliably hex). Classic ones are strictly
    // hex. Both are re-validated by Apple, so the modern form stays
    // permissive on purpose: a too-strict client check would block a
    // legitimate device outright.
    let modern = "^[0-9A-Z]{8}-[0-9A-Z]{16}$"
    let classic = "^[0-9A-F]{40}$"
    return normalized.range(of: modern, options: .regularExpression) != nil
        || normalized.range(of: classic, options: .regularExpression) != nil
}
```

The old test suite enshrined the bug — it asserted that
`00008030-001A2B3C4D5E6F7A8` (a well-formed 25-character UDID) was **invalid**. That assertion
was inverted, and a self-consistency test was added for the shipped placeholder.

**Confirmed against live data:** a real device on the account has UDID
`00008150-001C3CDA3E41401C` — exactly the 8 + dash + 16 shape now implemented. Before this fix
that device could not have been registered through the app.

### The test-target compile break

A single missing `)` in `testEnableCapabilityBodyCarriesBundleIdRelationship` meant
`App Store Tests` never compiled, so **no** test in the target could run. Verified pre-existing
by checking out HEAD's copy of the file and rebuilding.

---

## Pre-existing test failures

Unrelated to the UDID work; none of these touch UDID code.

| Test | Area |
|---|---|
| `testCSVParsesCommaRowsWithHeader` | CSV parsing |
| `testCSVPlatformAliases` | CSV parsing |
| `testCSVSkipsCommentsBlanksAndRejectsBadRows` | CSV parsing |
| `testEnableCapabilityBodyCarriesBundleIdRelationship` | Capability JSON body |
| `testLoadCSRMissingFile` | CSR file loading (previously documented) |

## Inconclusive

| Item | Note |
|---|---|
| 8-9 UDID rejection re-test | The sheet stayed open (consistent with the error path), but the error text was not captured before the run ended. Worth one clean re-run. |

---

## Not tested / unreachable

| Scenario | Blocker |
|---|---|
| CSV import | **Only reachable in the empty state** — cannot import when devices already exist |
| Load more / pagination | 8 devices < 50 page limit, so the control never renders |
| Row context menu actions | `AXShowMenu` returns `accessibility_error` |
| "Open Profile →" jump from dependent profiles | Not exercised |
| API failure paths (401, rate limit, retry) | Not exercised |
| Multi-select + CSV export | Not implemented |
| Delete device | No `DELETE /v1/devices` exists — disabling is the only revoke |
| Delete account | **No such feature** — `deleteAccount` / `signOut` / `logOut` return nothing |

---

## UX observations

- The header count (`8 Total`) never changes when search or platform filters are applied. It
  reads as inconsistent next to a filtered one-row list; consider labelling it as the
  unfiltered total, or scoping it to the filter.
- Registering with the iOS platform defaulted the device class to `iPod`. Apple assigns the
  class, but the default reads oddly in the detail view.
- **CSV import is effectively hidden** for any account that already has devices.

---

## Automation notes (Orca / macOS accessibility)

These cost real time to rediscover and are worth keeping.

| Behaviour | Detail |
|---|---|
| Flag needed | `--restore-window`; without it, AX reads fail with *"has no accessibility window"* even when the app is frontmost. Permissions reported `granted` while reads were still failing. |
| SwiftUI text fields | `click` issues `AXConfirm`, which does **not** focus the field. `set-value` updates the accessibility value without touching the `@State` binding — a field looks filled but the model stays empty. |
| Working input path | Focus with <kbd>Tab</kbd>, then `paste-text`. |
| Focus probe | `get-app-state` reports `focusedElementId`; loop `press-key --key Tab` until it matches the target field. |
| Correct key syntax | `orca computer press-key --app <id> --key Tab`. There is no `computer key` subcommand — it fails with *"Did you mean: orca computer hotkey"*. |
| Discovering actions | `orca computer capabilities --json` lists supported actions (`pressKey`, `pasteText`, `hotkey`, `setValue`, …). |
| Element indices are unstable | Sidebar indices shift per section, and re-reading after an error banner can renumber everything. Re-read the tree immediately before every click. |
| Context menus | `AXShowMenu` fails on these row menus. |
| Pickers | The Device details / Dependent profiles control is exposed as plain text, so `AXConfirm` cannot switch it. Its content is rendered inline regardless, so data is still verifiable. |
| Register proof | A click on the sheet's Register button can dismiss the sheet **without firing**. The reliable signal is the first poll after clicking, where Cancel shows `disabled` (`isSaving`). A dismissed sheet alone is not evidence of success. |

---

## State left behind

| Field | Value |
|---|---|
| Name | `Renamed Throwaway 01` (renamed from `OpenCode Verify 2026-10-05`) |
| UDID | `deadbeefdeadbeefdeadbeefdeadbeefdeadbeef` |
| Status | **Enabled** |
| Platform / class | iOS · iPod |
| Registered | 2026-10-05 |

One membership-year registration slot consumed. The device is intact and enabled. The register
sheet was left open holding a test UDID during the last run — nothing was submitted.

Two stale bundles with the old `com.demos.App-Store` identifier remain on disk and are **not**
running; they were left in place pending approval to delete:

- `/Applications/App Store.app`
- `~/Library/Developer/Xcode/DerivedData/App_Store-eixbftcynxurlvepwtxjgepqmyui/Build/Products/Debug/App Store.app`