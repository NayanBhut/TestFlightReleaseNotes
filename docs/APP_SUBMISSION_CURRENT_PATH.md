# App Submission UI — Current Path To Submit A Build

**Date:** 2026-10-06  
**Scope:** Current SwiftUI code path for App Store version / build submission.

This document explains what the app shows today, when each submission view appears, and what can be removed or simplified to make the path easier to discover.

---

## Entry Points

### Main path

1. Open `Apps`.
2. Select an app row.
3. In the app detail sub-navigation, open `App Store Versions`.
4. Select an existing version, or click `New Version`.
5. Use the `Overview` prepare form to choose a build, fill release metadata, save, then submit.

Code path:

- `Shipyard/ShipyardShell.swift` opens app detail from `AppsTableView`.
- `Shipyard/AppDetailView.swift` owns the app-level tabs and exposes `App Store Versions`.
- `Shipyard/ReleaseTabView.swift` owns the version list, version-state routing, save action bar, submit dialog, cancel dialog, release dialog, and new-version sheet.
- `Shipyard/ReleasePrepareView.swift` renders the editable prepare/submission form.
- `Shipyard/ReleaseDialogs.swift` renders the final `Submit for Review` confirmation.
- `SideBarView/DetailView/Reviews/ReviewsViewModel.swift` performs the App Store Connect writes.

### Secondary shortcuts

- From `App Store Versions`, the bottom action bar can jump to `App Info`.
- The prepare form has `Manage shared metadata in App Info ›`.
- The prepare form has `Choose Build`, which opens the build picker sheet.
- When there are no App Store versions, the empty state shows `New Version` and `View <App> Builds`.

---

## What The UI Shows By Version State

`ReleaseTabView` routes the selected version by `appStoreState ?? appVersionState`.

| State | UI shown | Primary action |
|---|---|---|
| No versions | Empty state: `No App Store Versions Yet` | `New Version` |
| `PREPARE_FOR_SUBMISSION` | Editable prepare form | `Save`, then `Submit for Review` |
| `REJECTED`, `DEVELOPER_REJECTED`, `INVALID_BINARY` | Prepare/resolution flow | Choose/upload new build, then resubmit |
| `METADATA_REJECTED` | Prepare/resolution flow | Edit metadata, then resubmit |
| `WAITING_FOR_REVIEW`, `READY_FOR_REVIEW` | Waiting status screen | `Cancel Submission`, `Request Expedited Review` |
| `IN_REVIEW` | In-review status screen | `Message App Review` |
| `PENDING_DEVELOPER_RELEASE` | Approved/pending release screen | `Release This Version` |
| `READY_FOR_SALE`, `READY_FOR_DISTRIBUTION`, removed/replaced states | Live/locked screen | `Create New Version`, sometimes `Remove from Sale` handoff |
| Other Apple-held states | Locked status screen | Usually read-only; may allow cancellation if a cancellable submission exists |

---

## Prepare Form Contents

The editable prepare form is split into two columns.

### Version and release column

- `Version *`
- `What’s New *` per locale
- `Build *`
- `Choose Build`
- Release type:
  - `Manually release`
  - `Automatically release after approval`
  - `Automatically release on a specific date`
- Optional release date picker for scheduled release
- `Phased release` toggle

### App Review information column

- `First name *`
- `Last name *`
- `Phone *`
- `Email *`
- `Sign-in required`
- Demo username/password when sign-in is enabled
- Notes for App Review
- Missing/ready alert
- Link to `Manage shared metadata in App Info ›`

---

## Submit Button Conditions

The bottom action bar enables `Submit for Review` only when all of these are true:

1. The shown version is editable.
2. It is the selected pending App Store version.
3. `missingItems` is empty.
4. No release/review/metadata draft is dirty.
5. A save is not currently in flight.
6. `reviewsVM.canSubmitForReview` is true.
7. The shown version matches `reviewsVM.submissionVersion`.

Current `missingItems` rules:

- For update versions only, at least one localization must exist.
- For update versions only, every loaded localization must have non-empty `What’s New`.
- For first App Store releases, `What’s New` is not required, is disabled in the prepare form, and is not PATCHed on save.
- A build must be attached.
- A scheduled release requires the saved server release date.
- When review details are known, first name, last name, phone, and email must be non-empty.
- When sign-in is required, demo username and demo password must be non-empty.

---

## Actual Submit Pipeline

The final confirmation dialog is `SubmitReviewDialog`.

When the user confirms, `ReviewsViewModel.submitForReview(appId:versionId:)` runs:

1. `POST /v1/reviewSubmissions`
   - Creates a review submission draft linked to the app.
2. `POST /v1/reviewSubmissionItems`
   - Links the selected `appStoreVersion` to that submission.
3. `PATCH /v1/reviewSubmissions/{id}`
   - Sends `{ submitted: true }`.

After success:

- The app refetches versions and review submissions.
- A toast says `Submitted for review`.
- The expected server-side result is `Waiting for Review`.

---

## Current Navigation Complexity

The submission path is functional, but users must understand several layers:

1. `Apps` table.
2. App detail page.
3. App detail sub-tab: `App Store Versions`.
4. Internal release tabs: `Overview`, `All Versions`, `Resolution`, `Builds`.
5. Prepare form.
6. Build picker sheet.
7. Save action bar.
8. Submit confirmation dialog.

This makes the path hard to discover because `Submit for Review` is not visible until the user enters an app, opens `App Store Versions`, selects a pending/editable version, and satisfies missing requirements.

---

## Suggested Simplification

The current UI is hard to understand because the submission path is named `App Store Versions`, then splits again into `Overview`, `All Versions`, `Resolution`, and `Builds`. A user trying to submit a build should see a single submission checklist instead of needing to infer which tab owns each requirement.

### Required product changes

1. Rename the app-detail tab from `App Store Versions` to `Submission`.
2. Make `Submission` the primary release workspace with one selected version at a time.
3. Replace the internal `Overview`/`All Versions`/`Resolution`/`Builds` tab strip with a single checklist page.
4. Keep version selection visible as a compact dropdown or left rail instead of a separate `All Versions` tab.
5. Keep build selection inline in the checklist and remove the duplicate internal `Builds` tab.
6. Show one sticky bottom action bar with exactly one next action: `Create Version`, `Save Changes`, `Submit for Review`, `Cancel Submission`, or `Release This Version`.
7. Add loading rows/skeletons anywhere App Info, version localizations, review details, release settings, or build candidates are still loading.
8. Keep `App Info` as the shared metadata editor, but expose missing App Info items inside the `Submission` checklist with direct jump links.

### Keep

- `Apps` list.
- App detail page.
- A single `Submission` or `App Store Submission` tab.
- `New Version`.
- `Choose Build`.
- `Save`.
- `Submit for Review`.
- Post-submit status screens for Waiting, In Review, Pending Release, Live, and Rejected.

### Remove or merge

- Merge `App Store Versions` and internal `Overview` into one visible submission page.
- Remove the internal `All Versions` tab and show the versions list as a left rail or compact dropdown.
- Remove the internal `Builds` tab because app detail already has a top-level `Builds` tab.
- Merge `Resolution` into the same submission page as a rejection banner plus action.
- Avoid a separate `Reviews` sidebar entry for submission; keep customer reviews separate from App Review submission.

### Easier target flow

Recommended user flow:

1. `Apps`.
2. Select app.
3. Open `Submission`.
4. If no draft exists, show one primary CTA: `Create App Store Version`.
5. In the same page, show a checklist:
   - Version
   - Build
   - What’s New
   - App Review contact
   - Release option
6. Each checklist row expands inline or jumps to the exact field.
7. Keep `Submit for Review` sticky at the bottom with clear disabled reasons.

---

## Recommended UI Copy

Use one status card at the top of the submission page:

- Missing state: `3 items left before submission`
- Ready state: `Ready to submit`
- Waiting state: `Submitted — waiting for App Review`
- In review state: `Apple is reviewing this version`
- Rejected state: `Rejected — update the required item and resubmit`
- Approved state: `Approved — ready to release`

Use one sticky action bar:

- Draft with missing fields: disabled `Submit for Review`, text `Add build, What’s New, and review contact.`
- Draft ready: primary `Submit for Review`
- Unsaved edits: primary `Save`, secondary/disabled submit until save finishes
- Waiting: destructive `Cancel Submission`
- In review: `Message App Review`
- Approved manual release: `Release This Version`

---

## Current Bugs / Cleanup Candidates

| Issue | Why it matters | Suggested fix |
|---|---|---|
| App Info could render blank/disabled on first app-detail entry | The submission path depends on App Info metadata, but empty drafts could mask server metadata after async localization loads | Fixed and live verified: App Info activates its app synchronously, loads the selected version localization on first entry, and keeps untouched fields following server values |
| Team add/switch could leave the old app/resource screen visible | Submission, certificates, profiles, and other resources could show stale data for the previous team | Fixed: the shell now observes active credential changes and resets app detail, resources, reviews, and App Info state |
| `Phone *` is not actually required by submit gating | UI says required but submit could enable without it | Fixed: phone now belongs to the review-contact requirement |
| Demo credentials are not submit-gated when sign-in is enabled | UI says required but submit could enable without them | Fixed: sign-in enabled now requires demo username and password |
| Scheduled release date / other unsaved edits must be saved before submit | User may edit release/review data and accidentally submit using last-saved server data | Fixed: submit now stays disabled while saving or while drafts are dirty |
| First-release `What’s New` is required and PATCHed | First App Store release version 1.0 does not accept update release notes, causing a live save failure | Fixed: first-release versions skip `What’s New`; update versions still require it |
| App Store Versions is a long label and internal tabs add another navigation layer | Users may miss the actual submission form | Rename tab to `Submission` and flatten internal tabs |
| `Builds` appears both as app tab and release internal tab | Duplicated navigation | Keep top-level Builds; use `Choose Build` inside Submission |
| `Resolution` is separate from the prepare page | Rejected versions require extra navigation | Show rejection banner inline on Submission |

---

## Quick Code Map

| Need | File |
|---|---|
| App detail tabs | `Shipyard/AppDetailView.swift` |
| Release workspace shell and state routing | `Shipyard/ReleaseTabView.swift` |
| Editable prepare form | `Shipyard/ReleasePrepareView.swift` |
| Submit/cancel/release/new-version dialogs | `Shipyard/ReleaseDialogs.swift` |
| Build picker sheet | `Shipyard/ChooseBuildSheet.swift` |
| App Store Connect submit pipeline | `SideBarView/DetailView/Reviews/ReviewsViewModel.swift` |
| JSON:API request bodies | `Model/JSONAPIModels/ReviewModels.swift` |
