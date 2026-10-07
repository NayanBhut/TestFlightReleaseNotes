# Module 10 — App Store Submission & Release Figma Support Audit

Audit date: 2026-10-07

Source: user-provided Module 10 Figma contract in `/Users/nayan.bhut/.codex/attachments/9c275600-dd08-4508-8a1a-296f0d8274fb/Pasted text.txt`.

Figma access note: the file opens in Brave and the selected `START HERE — Release flow & navigation key` frame is visible. Browser accessibility exposes layer/frame metadata and the visible contract text, but not full inspectable design JSON for every descendant frame. This audit verifies implementation support from the listed screen contract and the visible navigation/API contract against the current SwiftUI release-flow code and App Store Connect public API constraints.

## Summary

Overall support: **partial**.

The app has a real App Store Versions workspace with the primary submission path, create-version flow, choose-build modal, save/submit/cancel/release API operations, loading/empty/error states, status-specific read-only screens, and phased-release controls. The largest gaps are the recovery/alternative states from the Figma contract: explicit sending/outcome-unconfirmed screens, permission-specific submission screen, unresolved-review-items screen, expedited-review prep screens, availability outcome tracking, and a few blocked/new-version variants.

## Implemented Foundations

- **Navigation shell:** `ReleaseTabView` provides `Overview`, `All Versions`, and `Builds` feature tabs with version chips and a bottom action bar. The Resolution Center tab is intentionally hidden because App Review messages/replies are not available in the public API.
- **Version list states:** N1 list, N2 empty, N3 loading, N4 error are implemented.
- **Prepare path:** `ReleasePrepareView` covers version string, What’s New, build selection, release type, phased release toggle, review contact, demo credentials, App Review notes, missing-items gating, save, and submit gating.
- **Write operations:** real App Store Connect API paths exist for create version, attach/save metadata/review details, submit review, cancel submission, release version, and phased-release start/pause/resume/end.
- **Status screens:** waiting, in review, pending developer release, live/removed-from-sale, rejected, metadata rejected, and generic locked states are implemented.
- **Manual Apple handoffs:** Resolution Center, expedited review/message review, and remove-from-sale all hand off to App Store Connect rather than pretending unsupported API surfaces exist.

## Brave/Figma Contract Check

The visible Figma navigation key lists these implementation rules. Current support:

| Figma contract item | Current support | Evidence / gap |
| --- | --- | --- |
| 01 Missing version fields → 02 Choose eligible build | **Supported** | Missing-items gating and `ChooseBuildSheet` are implemented. |
| 03 Version fields entered → shared checks pending | **Supported** | Dirty state blocks submit until saved. |
| 04 Blocked: resolve metadata/media/payment checks | **Partial** | Local metadata/build/review checks exist; payment/compliance/app privacy are surfaced only indirectly through API errors or Apple handoff. |
| S1 Ready for Review = added, not sent to Apple | **Supported** | `SubmitReviewDialog` confirms before sending. |
| S2 Sending = local operation, prevent duplicate writes | **Partial** | Submit progress guards duplicate writes; no dedicated S2 full-screen state. |
| S3 Validation error: keep saved steps, fix actual error | **Partial** | Errors persist in dialog/action bar; no dedicated validation recovery screen. |
| S4 Outcome unknown: refresh before retrying send | **Missing** | Unknown/timeout outcome is not represented as a distinct screen. |
| P0 No submit access: preserve draft, switch connection | **Partial** | Permission hints exist in error messages; no P0 view or switch-connection action. |
| R1/R2 explanation, replies and appeals are external | **Supported** | Rejection views explain binary/metadata cases and hand off to App Store Connect. |
| R3 Unresolved issues: resolve/remove rejected items | **Missing/Partial** | App has no `reviewSubmissionItems` resolution UI; external handoff only. |
| No new items while unresolved; removed items stay out | **Missing** | No local unresolved-item state machine beyond submission cancel. |
| C1 cancels all items in the review submission | **Supported** | Cancel patches the review submission as canceled. |
| C0 canceling → C2 developer rejected after refresh | **Partial** | Cancel dialog has progress and refresh, but no dedicated C0/C2 confirmation screens. |
| Do not invent a CANCELED submission state | **Supported** | Code patches `canceled` and refetches server state rather than inventing local state. |
| 07 Pending Developer Release → 08 request confirmation | **Supported** | Pending release screen and release confirmation dialog exist. |
| Accepted request → live, L1 Processing for Distribution | **Partial** | Release request and refetch exist; no named L1 screen. |
| 09 only after fetched READY_FOR_DISTRIBUTION | **Supported** | Live UI is state-driven from server version state. |
| Phasing 1/2/5/10/20/50/100%; no forced install | **Supported/Partial** | Phased progress uses Apple’s fixed ladder and supports pause/resume/end; exact visual matching needs per-frame visual review. |
| 30 cumulative pause days; API cannot undo release request | **Partial** | Paused state is represented; cumulative pause-day limit is not visibly enforced. |
| Save version: PATCH `/v1/appStoreVersions/{id}` | **Supported** | `saveReleaseSettings` patches release settings. |
| Build: PATCH `/v1/appStoreVersions/{id}/relationships/build` | **Supported** | Build attachment uses relationships/build. |
| Notes: appStoreVersionLocalizations.whatsNew | **Supported** | Release notes/localizations are editable and saved. |
| Review: appStoreReviewDetails first/last name separate | **Supported** | Review details save path exists. |
| Add container: POST `/v1/reviewSubmissions` | **Supported** | Submit workflow creates the review submission. |
| Add version item: POST `/v1/reviewSubmissionItems` | **Supported** | Submit workflow links app store version item. |
| Send: PATCH `/v1/reviewSubmissions/{id}`, `submitted: true` | **Supported** | Submit workflow flips `submitted`. |
| Cancel: PATCH `/v1/reviewSubmissions/{id}`, `canceled: true` | **Supported** | Cancel workflow patches `canceled`. |
| Handle item: PATCH `/v1/reviewSubmissionItems/{id}` | **Missing** | No item-level resolve/remove UI exists. |
| Release: POST `/v1/appStoreVersionReleaseRequests` | **Supported** | Manual release request is implemented. |
| Phase: PATCH `/v1/appStoreVersionPhasedReleases/{id}` active/paused/complete | **Supported** | Phased start/update paths exist. |
| Guards: submit/release roles, configured key role, matching platform/version, valid build, incomplete compliance, saved notes | **Partial** | Role/permission errors are surfaced; local checks cover matching platform/version, valid build, saved notes. Compliance/payment/privacy remain Apple/API-handoff gaps. |

## Screen Support Matrix

| Figma screen | Current support | Notes |
| --- | --- | --- |
| START HERE — Release flow & navigation key | **Partial** | Shell and routes exist; Resolution Center is intentionally hidden because the public API cannot provide rejection messages/replies. |
| N1 — All Versions · Entry / return | **Supported** | List, selection, filters/search, detail preview, open-version action are present. |
| New version — blocked by existing iOS draft | **Partial** | API guard blocks creation and surfaces an error, but there is no dedicated blocked design before opening/creating. |
| Future version 2.4.1 — local notes preparation | **Partial** | New version and local draft preparation exist; exact “future version” local-prep state is not explicit. |
| 01 — Prepare for Submission · Missing items | **Supported** | Missing requirements are computed and shown in the action bar/form. |
| 02 — Choose Build · Modal | **Supported** | Dedicated `ChooseBuildSheet` exists. |
| 03 — Version fields entered · shared checks pending | **Supported** | Dirty state blocks submit until saved; shared checks/missing items gate action bar. |
| 04 — Submission prerequisites · blocked | **Supported** | Submit button disabled until saved, build/localization/review requirements pass. |
| S1 — Ready for Review | **Supported** | Submit confirmation dialog summarizes app/version/build/release. |
| S2 — Sending submission | **Partial** | Progress indicator appears in dialog/action bar; no dedicated full sending screen. |
| S3 — Submission validation failed | **Partial** | Errors/toasts show failure; no dedicated recovery screen with validation issue checklist. |
| S4 — Submission outcome unconfirmed | **Missing** | No explicit ambiguous-result screen after timeout/unknown write result. |
| P0 — Submission not permitted | **Partial** | Broader-permission hints surface through errors; no dedicated not-permitted screen. |
| 05 — Waiting for Review | **Supported** | Waiting status screen and cancel/expedited handoff actions exist. |
| 06 — In Review | **Supported** | In-review status screen and App Review handoff exist. |
| 07 — Pending Developer Release · Approved | **Supported** | Pending release screen and release action exist. |
| 08 — Release This Version · Confirmation | **Supported** | Dedicated release confirmation dialog exists. |
| L1 — Processing for Distribution | **Partial** | Generic locked status can display unknown/Apple-held states; no specific L1 design. |
| 09 — Ready for Distribution · Live | **Supported** | Live screen exists; removed-from-sale is also represented. |
| 03A — Prepare · Scheduled release option | **Partial** | Release type and scheduled date support exist in API/model; current New Version sheet does not expose scheduled date, and prepare save coverage needs UI verification. |
| 09A — Ready for Distribution · Paused | **Supported** | Live screen shows phased rollout paused and offers resume/end controls. |
| Version supplements — Release to all users now? | **Supported** | Phased release end confirmation exists. |
| Version supplements — Phased rollout ended | **Partial** | End operation exists; explicit ended-state screen depends on returned phased state and is not a named route. |
| R1 — Rejected · External explanation | **Supported** | Binary rejection explanation and App Store Connect handoff exist. |
| R2 — Metadata Rejected · External explanation | **Supported** | Metadata rejection explanation and no-new-build guidance exist. |
| R3 — Unresolved review items | **Partial** | Resolution Center handoff exists; no distinct unresolved-items state/thread list. |
| C1 — Cancel Submission · Confirmation | **Supported** | Dedicated cancel confirmation dialog exists. |
| C0 — Cancellation in progress | **Partial** | Dialog progress exists; no dedicated full cancellation-in-progress screen. |
| C2 — Developer Rejected · withdrawal confirmed | **Partial** | State routes to prepare/locked handling; no explicit withdrawal-confirmed design state. |
| Expedited review — Local preparation & Apple form | **Partial** | Button opens App Store Connect; no local prep form/checklist. |
| Expedited review — Complete request on Apple website | **Supported as handoff** | Uses external App Store Connect link, not embedded form. |
| Availability — manual Apple handoff | **Supported as handoff** | Remove-from-sale confirmation opens App Store Connect. |
| Availability — manual handoff, outcome unconfirmed | **Missing** | No local pending/unconfirmed outcome tracking after returning from Apple site. |
| N2 — Empty · No versions | **Supported** | Empty state with New Version and Builds actions exists. |
| N3 — Loading versions | **Supported** | Loading state with long-running retry exists. |
| N4 — Error · Unable to load | **Supported** | Error state with retry/details exists. |
| New version — invalid or ineligible candidate | **Partial** | Create errors show, but no tailored invalid/ineligible candidate screen. |

## Highest-Priority Gaps

1. **Add recovery-state screens.** Implement S3, S4, P0, C0, and availability-outcome-unconfirmed as explicit views so failed/ambiguous writes are understandable.
2. **Finish scheduled release UI.** Surface scheduled date in New Version / Prepare in the same place the design expects, and verify it saves before submission.
3. **Add unresolved-review-items state.** Since App Review conversation contents are not reliably available through public API, show known status, external handoff, and a checklist of local fix actions.
4. **Improve new-version blocked/ineligible handling.** Disable or explain unavailable platforms before submission instead of relying on the create request to fail.

## Public API Constraints To Preserve

- App Review Resolution Center messages/replies/attachments should remain an App Store Connect handoff unless the official API contract is verified for the exact endpoints in use.
- Remove-from-sale / availability changes remain a manual App Store Connect handoff.
- Build upload remains outside this app; the app can attach processed builds, not upload binaries.
- Expedited review remains a manual Apple form handoff unless an official API is verified.
