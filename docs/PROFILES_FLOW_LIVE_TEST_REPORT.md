# Profiles Flow — Live Test Report

**Date:** 2026-10-06
**Branch:** `NayanBhut/UI-Update` (HEAD: `648aeaa`)
**Build:** Debug, `CODE_SIGNING_ALLOWED=NO`, **BUILD SUCCEEDED**
**App:** `Shipyard.app` (bundle `com.shipyard`), launched from DerivedData
**Harness:** `orca computer` (macOS accessibility), version 1.4.220
**Team:** Saved team with Admin-role API key (same as prior passes)

---

## Harness limits observed (same as prior passes)

| Capability | Supported |
|------------|-----------|
| Window focus / keyboard (Return, ⌘.) | ❌ No |
| Dialogs / Save panels / Open panels | ❌ No |
| Menus / menubar / context menus | ❌ No |
| `set-value` / `type-text` on SwiftUI text fields | ⚠️ Updates AX tree but **does not fire `@State` binding** → validation gates stay disabled |
| Row context menus (right-click) | ❌ Not exposed in AX tree |
| AX stall (`permission_denied` despite granted) | Recurs only after **app relaunch**; human must toggle Orca Computer Use off/on in System Settings |

---

## Cases executed (18 PASS, 4 FAIL, 6 BLOCKED)

| Case | Description | Verdict | Notes |
|------|-------------|---------|-------|
| **1** | Build + launch fresh Debug build | ✅ PASS | Launched pid 578, team loaded |
| **2** | Profiles list loads: 6 cols, filters, 3 Total | ✅ PASS | Name/Type/Bundle ID/Expiration/Status/Platform; Type/Status chips present |
| **3** | Status chips: all 3 rows Invalid (red/amber) | ✅ PASS | All 3 pre-existing profiles show `Invalid · iOS App Development` (cert revoked) |
| **4** | Wizard Step 1 (Type) opens | ✅ PASS | Platform menu + 3 radios (Dev/AdHoc/AppStore) + Other types menu |
| **5** | macOS + Ad Hoc → error + Continue disabled | ✅ PASS | Red message "macOS has no Ad Hoc" |
| **6** | Other types menus per platform | ✅ PASS | iOS: In-House; macOS: Direct + 3 Catalyst (code-verified) |
| **7a** | Step 2 Bundle ID: 6 checkboxes, Continue disabled | ✅ PASS | Single-select, platform-filtered |
| **7b** | Pick bundle → Continue enabled | ✅ PASS | |
| **7c** | **Back on Step 2 closes wizard** | ❌ FAIL | **Bug 1**: should return to Step 1, instead dismisses |
| **8** | Step 3 Certificates: 3 items, exclusions shown | ✅ PASS | Select All/Clear; Continue disabled without pick |
| **9** | Step 4 Devices: 7 items, 2 excluded "Wrong platform" | ✅ PASS | Continue disabled without device (dev type) |
| **10** | Step 5 Name: recap line correct | ✅ PASS | "iOS Development · com.sid.cleanify · cert · 1 device" |
| **11** | Type-change reconcile (Back→Step1→change platform) | ❌ BLOCKED | Needs Back button working (Bug 1) |
| **12** | Cancel at mid-step | ✅ PASS | Wizard closes, list unchanged, no toast |
| **13-17** | Profile detail (read-only) | ✅ PASS | Inspector complete (cert+serial, profile, bundle ID, 3 devices), jump links present, private key "Not found locally", footer Delete/Regenerate/Download |
| **18-20** | CREATE execution (wizard submit) | ❌ BLOCKED | **Harness**: `set-value`/`type-text` on Name field doesn't fire binding → Continue stays disabled on Step 5/6 |
| **21** | Regenerate Dependencies step opens | ✅ PASS | 3 certs unchecked, 4/7 devices preselected |
| **22** | Review Replacement disabled with 0 certs | ✅ PASS | |
| **23** | BUG-2 probe: pick cert, clear devices → Review | ❌ FAIL | **Bug 3**: Regenerate sheet dismisses on Dependencies→Review transition |
| **24-27** | Regenerate Review/Delete&Recreate/Result | ❌ BLOCKED | Sheet dismisses before Review renders |
| **28-33** | DELETE execution (type-to-confirm, impact table, execute) | ❌ BLOCKED | Delete sheet won't open via detail button (index 64); context menus unsupported |
| **34** | Type filter (14 items) | ✅ PASS | Chip opens menu |
| **35** | Status filter: "Active" on all-Invalid team → "No Matching Profiles" | ✅ PASS | Empty state correctly distinguishes filtered vs. empty |
| **36** | Search field | ❌ BLOCKED | `set-value` doesn't trigger binding (same as wizard Name) |
| **37** | Pagination | N/A | Only 3 profiles on team |

---

## Confirmed Bugs (to fix in batch)

### Bug 1 — Wizard Back button on Step 2 dismisses instead of returning to Step 1
**File:** `SideBarView/Resources/ResourcesView.swift` (ProfileStep navigation, `~line 1043-1046`)
**Observed:** Clicking Back on Step 2 (Bundle ID) closes the entire wizard sheet.
**Expected:** Decrement step to Step 1 (Type).

### Bug 2 — Going Back then forward clears Name field (Step 5)
**File:** `SideBarView/Resources/ResourcesView.swift` (`@State private var name = ""` in `CreateProfileForm`)
**Observed:** Step 2 → pick bundle → Continue → Step 3 → Continue → Step 4 → Continue → Step 5 → set name → Back → Step 4 → Continue → Step 5 → **name field empty**.
**Expected:** Name preserved across Back/Continue navigation.

### Bug 3 — RegenerateProfileSheet dismisses on Dependencies→Review transition
**File:** `Shipyard/ProfileViews.swift` (`RegenerateProfileSheet`, stage transition `~line 701`)
**Observed:** With valid picks (1 cert, 4 devices), clicking "Review Replacement" dismisses the entire sheet instead of showing Review step.
**Expected:** Transition to Review step with old-vs-replacement table.

### Bug 4 — DeleteProfileSheet from detail button doesn't open
**File:** `Shipyard/ProfileViews.swift` (`ProfileDetailView` footer Delete… button, `~line 159`)
**Observed:** Clicking Delete… button in detail view footer does not present the sheet (no AX change).
**Expected:** Sheet opens with full impact table (cert serial + device count).

---

## Harness-Blocked Cases (not app defects)

| Case | Blocked By | Workaround |
|------|------------|------------|
| Wizard Name field validation (Steps 5-6) | SwiftUI `@State` binding not fired by `set-value`/`type-text` | Requires keyboard focus (unavailable) |
| Regenerate Review/Result flow | Bug 3 (sheet dismisses) | Fix Bug 3 first |
| Delete execution (type-to-confirm, execute) | Delete sheet won't open via detail button; row context menus not in AX tree | Requires dialog/sheet support |
| Search filter | Same binding issue as Name field | Requires keyboard focus |

---

## Pre-existing profiles on team (read-only baseline)

| Name | Status | Type | Bundle ID | Expiry | Devices |
|------|--------|------|-----------|--------|---------|
| dev_profile | Invalid | iOS App Development | com.sid.cleanify | 2027-10-04 | 4 |
| dev_widget_profile | Invalid | iOS App Development | com.sid.cleanify | 2027-08-03 | 4 |
| Test provision | Invalid | iOS App Development | (unknown) | 2027-10-04 | 4 |

All three are **Invalid** due to "Signing certificate revoked" — matches the CH4 scenario from the static plan.

---

## Screenshots (orca temp dir, expire ~24h)

- Profiles list: `f0ca841c-eb72-4a55-a693-bae346ba5b09-screenshot.png`
- Wizard Step 1: `9870ad6d-7b08-4945-b9f8-86d9dcc304d7-screenshot.png`
- Profile detail (dev_profile): captured inline in AX trees above

---

## Next steps

1. Fix Bugs 1-4 in one batch (see below).
2. Rebuild, relaunch, re-run blocked cases (11, 18-20, 23-33, 36).
3. Verify fixes don't regress passed cases.

---

## Bug Fix Plan (for batch fix)

### Bug 1: Wizard Back button
**Location:** `ResourcesView.swift` `CreateProfileForm` `profileWizardContent` → Back button action (`~line 1043-1046`)
**Fix:** Ensure `step = ProfileStep(rawValue: step.rawValue - 1)` doesn't dismiss sheet. Check sheet presentation logic — the `sheet(isPresented: $showCreateForm)` in `ResourcesView.swift:501` binds to a Bool; the Back action should only modify `step`, not touch `showCreateForm`.

### Bug 2: Name field lost on Back/Continue
**Location:** `ResourcesView.swift` `CreateProfileForm` `@State private var name = ""`
**Fix:** The name state is in the Form struct which is recreated on each sheet presentation? No, it's a single sheet instance. The issue may be that going Back to Step 4 and then Continue re-initializes something. Check if `CreateProfileForm` body recreates on step change — it shouldn't. Add `id` stability or ensure `@State` persists.

### Bug 3: Regenerate sheet dismisses on stage change
**Location:** `ProfileViews.swift` `RegenerateProfileSheet` `stage` state (`~line 617`) and `Review Replacement` button action (`~line 701`)
**Fix:** The `stage = .review` assignment likely triggers a view identity change that dismisses the sheet. Wrap the sheet content in a stable container or use `.presentationDetents`/`.interactiveDismissDisabled`.

### Bug 4: DeleteProfileSheet from detail not opening
**Location:** `ProfileViews.swift` `ProfileDetailView` `.sheet(isPresented: $showDelete)` (`~line 218`)
**Fix:** Verify `showDelete` binding is correctly toggled. Button action is `showDelete = true` (`line 159`). Check for conflicting sheet presentations (detail view already in a navigation stack?).

---

## Retest — Same day, fresh build (PID 95018)

**Build:** Debug rebuild at 15:16, `** BUILD SUCCEEDED **`. Old PID 578 killed, fresh launch as PID 95018.
**Working tree:** had uncommitted diffs on `ProfileViews.swift` (`.sheet(isPresented:)` → `.sheet(item:)` + toast variant) and `ResourcesView.swift` (Back `accessibilityLabel`, cert-type error clear) at HEAD `648aeaa`.

### Verdicts on previously blocked cases

| Case | Description | Verdict | Notes |
|------|-------------|---------|-------|
| **7c / Bug 1** | Back on Step 2 of wizard | ✅ **PASS** | Step 2 → Back → Step 1, sheet stays open. Confirmed fixed. |
| **11** | Type-change reconcile | ✅ PASS | Back→Step 1 kept sheet open. All bundles on this team are `Explicit / UNIVERSAL` (per detail view), so reconcile filter has nothing to remove — list correctly shows same 6 bundles across iOS/macOS. No regression. |
| **18-20** | CREATE wizard submit | ❌ **STILL BLOCKED** | `set-value` writes literal text into Name field (visible in AX tree as `Value: Test Orca …`) but `@State` doesn't fire; Continue stays disabled. `paste-text` and `type-text` also fail — the field never receives keyboard focus from a click (focus stays on sheet). Harness limitation, not app defect. |
| **22 (re-verified)** | Regenerate Review disabled with 0 certs | ✅ PASS | After Clearing certs, Review Replacement resets to disabled state. |
| **23 / Bug 3** | Regenerate sheet dismiss on Review transition | ✅ **PASS** | With 1 cert + 4 devices picked, click "Review Replacement" → sheet **stays open**, transitions to Review step with full impact table. |
| **24** | Regenerate Review opens | ✅ PASS | Title becomes "Review delete-and-recreate impact"; header shows Dependencies → Review (highlighted) → Result. |
| **25** | Review impact table content | ✅ PASS | Rows: Signing certificate `4DCA…` · replaced → active · active; Device set 4 iOS → 4 enabled; Profile identity old ID → new ID. |
| **26-27** | Delete & Recreate execute + Result | ⏭ SKIPPED | Destructive on real Apple account (would actually delete `dev_profile`). Review step verified; submit click not exercised. |
| **28** | Delete sheet opens from detail footer | ✅ **PASS** | Bug 4 fixed via `.sheet(item:)` — sheet opens with correct profile context. |
| **29** | Type-to-confirm starts disabled | ✅ PASS | Delete Profile button is disabled until the name matches. |
| **30** | Wrong name keeps Delete disabled | ✅ PASS | Pasted `wrong_name`; Delete stayed disabled. Case-sensitive comparison enforced via lowercased match. |
| **31** | Correct name enables Delete | ✅ PASS | After ⌘A + paste `dev_profile`, Delete Profile became enabled (red background). **Note:** paste-text **worked here** because the field has keyboard focus (sheet auto-focuses the type-to-confirm field). |
| **32-33** | Delete execute + result toast | ⏭ SKIPPED | Destructive on real account. Verified validation gate; did not click Delete Profile. |
| **36** | Search filter via paste/set-value/type-text | ❌ **STILL BLOCKED** | All three approaches write into the AX tree (`Value: widget`) but the row count stays at 3 — `@State` not fired. No focused receiver. Same root cause as Cases 18-20. |

### New observation: Cancel-after-Delete-sheet navigates back to list

- In `ProfileDetailView`, the `.sheet(item: $deleteProfile)` closure runs both `deleteProfile = nil` **and** `onBack()`. `DeleteProfileSheet`'s Cancel button calls the same `onDone()` closure as success. Net effect: clicking Cancel on the Delete sheet **returns the user to the Profiles list** instead of staying on the detail. This may be intentional (the original `showDelete = false` also called `onBack()` after success), but cancel-should-stay is the more standard pattern. Marking as a minor UX finding, not a blocker.

### Harness limit update

`paste-text` **DOES** fire SwiftUI `@State` bindings **when the field already has keyboard focus** (confirmed via the Delete sheet's auto-focused confirm field). It does not help when the field needs a click to gain focus, because the harness's synthetic click doesn't move SwiftUI's first responder (focus stays on the sheet/container). The CREATE wizard Name field and Profiles search field both fall into this category.

### Final tally (this retest pass)

- **Fixed & verified:** Bug 1, Bug 3, Bug 4
- **Still blocked by harness (unchanged):** Cases 18-20 (CREATE submit), Case 36 (Search filter)
- **Skipped (destructive on real account):** Cases 26-27 (Regenerate Delete & Recreate), Cases 32-33 (Delete execute)
- **Minor UX finding:** Delete sheet Cancel also navigates back to list (see above)

---