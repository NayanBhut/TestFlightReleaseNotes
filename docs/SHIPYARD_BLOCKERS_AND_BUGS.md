# Shipyard Blockers and Open Bugs

Last reconciled against source: 2026-10-07

This file contains only unresolved product defects, unsupported API areas, high-risk designs, and incomplete verification. Fixed historical defects belong in `docs/SHIPYARD_REFERENCE.md` as regression knowledge.

## Priority Summary

| Priority | Area | Issue |
| --- | --- | --- |
| P0 | App submission | Full live state-transition regression is incomplete |
| P0 | Profiles | Regenerate is delete-first and can permanently remove the old profile when replacement validation/create fails |
| P1 | Profiles | Regenerate does not require devices for development/ad-hoc types and certificate eligibility ignores platform |
| P1 | Submission | Ambiguous/permission/recovery outcomes do not have explicit state screens |
| P1 | Tests | Four validation tests currently fail |
| P1 | Users | Resend invitation remains a destructive revoke-then-create workflow |
| P2 | Devices | CSV export/multi-selection flow is not implemented |
| P2 | Certificates | No in-app CSR/key generation and no type/status filters |
| P2 | Identifiers | No App Groups API-backed flow or Merchant/Pass identifier cleanup UI |
| P2 | Users | Email validation is too weak; list-level error banner is unwired |
| P2 | Profiles | `PROCESSING` profiles render as Active |
| P3 | UX/verification | Several native-panel, pagination, and destructive flows remain unverified |

## App Submission

### P0 — Production submission regression is incomplete

Submission is the highest-risk workflow and must not regress. Current evidence covers loading, version navigation, build filtering/selection, dirty-state gating, first-release What's New behavior, App Info hydration, and much of the prepare form. It does not fully prove every server transition with a controlled test app.

Still required:

- Create version through a safe app and verify duplicate/ineligible errors.
- Attach and replace a build, then confirm the server relationship after refetch.
- Save review contact, demo credentials, scheduled release, localized What's New, and phased-release settings.
- Submit and observe Waiting for Review.
- Cancel and observe the server-returned post-cancel state.
- Exercise rejection, metadata rejection, invalid binary, in review, pending developer release, processing, and live states.
- Confirm retry behavior after 401, 403, 409, rate limit, timeout, and unknown write outcome.

Use a throwaway app/version. Do not exercise release or cancellation on a production submission without explicit approval.

### P1 — Missing recovery-state UX

The Figma contract calls for distinct states that are only partially represented:

- Submission validation failed with preserved saved work.
- Submission outcome unknown after timeout; refresh before retry.
- Submission not permitted with a clear role/connection action.
- Cancellation in progress and cancellation outcome confirmation.
- Processing for Distribution as a named state.
- Manual availability handoff with outcome still unconfirmed.
- Unresolved review items with a local checklist plus App Store Connect handoff.

Current dialogs/toasts prevent many duplicate actions, but ambiguous writes can still look like ordinary failures. Add explicit recovery models before retrying multi-step writes.

### Intentional public-API boundaries

These are not bugs and must remain honest handoffs unless an official endpoint is verified:

- Uploading app binaries.
- Resolution Center messages, replies, and attachments.
- Expedited review request form.
- Remove-from-sale/availability changes not exposed by the implemented API contract.

## Profiles

### P0 — Regenerate deletes before replacement creation

`regenerateProfile` deletes the old profile, then creates the replacement. Any create failure leaves no profile. The UI reports partial failure but cannot restore the deleted profile.

Required improvement:

- Validate every prerequisite before DELETE.
- Add type-to-confirm or equivalent destructive acknowledgement.
- Keep an immutable review snapshot of profile type, Bundle ID, certificates, and devices.
- If Apple cannot support transactional replacement, make the irreversible ordering visually explicit.

### P1 — Missing device guard during regenerate

The regenerate UI disables Review only when no certificate is selected. `ResourcesViewModel.regenerateProfile` also validates certificates but does not reject an empty device set for profile types that require devices. A development/ad-hoc replacement can therefore delete the old profile and fail the POST.

Fix both layers:

- Disable Review and Delete & Recreate when `profileType.allowsDevices && deviceIds.isEmpty`.
- Add the same guard before issuing DELETE in the ViewModel.

### P1 — Regenerate certificate eligibility ignores platform

The create wizard checks certificate kind, expiry, and platform. `RegenerateProfileSheet.eligibleCertificates` checks only kind and expiry. A macOS certificate can be offered for an iOS profile, and the destructive delete can occur before Apple rejects the replacement.

Use one shared compatibility helper for create and regenerate.

### P2 — `PROCESSING` profiles render as Active

`ProfileComputedStatus` handles only Active, Expired, and Invalid. Any server `PROCESSING` value falls through to Active and cannot be filtered separately.

Add a Processing case, neutral status styling, filter support, and disable destructive operations until processing completes.

### P3 — Canceling profile deletion navigates away

`ProfileDetailView` passes the same completion closure to `DeleteProfileSheet` for cancel and success; the closure clears the sheet and calls `onBack()`. Cancel therefore returns to the profiles list instead of staying in detail.

Separate `onCancel` from `onDeleted`.

### P3 — Row-menu delete impact can be incomplete

Profile list rows may not hydrate certificates/devices, while the delete impact sheet derives its detail from those relationships. Ensure the sheet fetches profile detail before presenting its impact table.

## Users and Invitations

### P1 — Resend remains destructive

All-Apps request encoding was fixed to omit `visibleApps`, but resend still performs DELETE then POST because Apple has no dedicated resend endpoint. If POST fails, the invitation may be lost.

Before re-testing:

- Confirm the current invitation snapshot is complete.
- Make the destructive ordering explicit.
- Refetch after DELETE and after POST.
- Never claim the previous invite was revoked unless the server confirms it.
- Consider replacing “Resend” with “Revoke and recreate” to match reality.

The fixed All-Apps body has not received a complete live regression after the accessibility stall.

### P2 — Email validation is too weak

`inviteUser` and `resendInvitation` currently accept any non-empty value containing `@`. Apple validates a real RFC mailbox and rejects values the client accepts.

Reuse the existing `EmailValidator` and attach errors to the email field before making a request.

### P2 — Users list error banner is unwired

`UsersTableView.bannerError` is rendered and dismissible but has no assignment other than clearing itself. Table-level failures therefore cannot populate the banner.

Either wire list actions into it or remove the dead state and rely consistently on toasts/state errors.

### P2 — Pending list can look stale after invite

Apple's invitation list can be eventually consistent. Immediately after a successful POST, a reload may still return zero pending invitations. The success toast helps, but the empty state looks authoritative.

Show a short `Refreshing invitation…` state, poll with a bounded retry, or expose last-sync/manual refresh information.

## Certificates and Identifiers

### P2 — No in-app CSR generation

The user must generate or supply a CSR externally. Add a guided CSR/private-key creation flow that stores the private key securely and exports only when requested. Preserve the current file/paste path for advanced users.

Never discard the generated private key: a downloaded certificate is unusable for signing without it.

### P2 — Certificate type/status filters are absent

Search exists, but operators cannot isolate Expiring Soon, Expired, platform, or certificate type. Add filter chips consistent with Profiles.

### P3 — Revoked certificate state is misleading

The UI contains a Revoked branch based on `activated == false`, but Apple's list generally removes revoked certificates and the local revoke path removes the row. The branch is effectively unreachable.

Remove unsupported copy/state or verify a real API payload that can produce it.

### P2 — Identifier gaps

- App Groups are not API-backed and currently show guidance only.
- Merchant ID and Pass Type ID list/create are implemented, but cleanup/delete is absent.
- Verify official API delete support before adding controls; otherwise link to the Apple Developer portal and document manual cleanup.

## Devices

### P2 — CSV export is missing

The Figma-defined Devices export flow is not implemented. Required behavior:

- Row multi-selection with individually accessible checkboxes.
- Export scope: selected rows, filtered cached list, or all cached team devices.
- RFC 4180 CSV columns: `name,udid,platform,status,registered_date`.
- Sandboxed `.fileExporter` destination and Replace/Cancel handling.
- Real progress, cancellation without partial files, completion summary, and Reveal in Finder.

CSV import exists but is effectively hidden when devices already exist; expose import from the normal toolbar rather than only an empty state.

### P3 — Device UX gaps

- Header total remains unfiltered while the list is filtered; label it as total or show visible count.
- Pagination is unverified on teams with more than 50 devices.
- API failure and rate-limit recovery are unverified.

## Builds and TestFlight

### P2 — Build export documentation/code mismatch

Repository guidance says README has advertised Markdown/CSV build export, but the active branch has no export implementation. Either implement export or remove the stale product claim.

### P3 — Monitoring and build-state improvements

- Show last successful processing-build poll and why a retry is needed.
- Add clearer explanations for no matching processed build.
- Verify large build/version pagination and stale-cursor protection against live data.

## App Info and Screenshots

### P2 — Missing automated regressions

Add coverage for:

- First-open App Info hydration.
- Switching teams while App Info is visible.
- Switching app/version/locale while requests are in flight.
- RTL locale text direction.
- Read-only text selection/copy.
- Screenshot counts after upload/delete.

### P3 — Screenshot processing ambiguity

Uploaded screenshots have appeared as `PENDING`. Verify whether this is normal Apple processing or an incomplete status mapping. Add dimension/device-size validation before upload and a visible processing explanation.

## Tests and Build Hygiene

### P1 — Four XCTest failures

The latest full test run failed:

- `ValidationTests.testCSVParsesCommaRowsWithHeader`
- `ValidationTests.testCSVPlatformAliases`
- `ValidationTests.testCSVSkipsCommentsBlanksAndRejectsBadRows`
- `ValidationTests.testLoadCSRMissingFile`

The project compiles and the remaining suites pass. Fix the fixtures/parser expectations and missing-file behavior before treating the suite as green.

### P3 — Existing warnings

Builds have reported concurrency warnings around shared `ISO8601DateFormatter` instances and some `nonisolated(unsafe)` declarations. They are not current build failures under Swift 5 mode but will become stricter under Swift 6.

## Verification Blockers

### Accessibility harness

These are test-environment limitations, not product defects:

- `set-value` may not fire SwiftUI bindings.
- Synthetic click may not give a text field keyboard focus.
- Native open/save panels and context menus may not be exposed.
- Accessibility can stall system-wide even while permissions report granted.
- Element indexes change after every render.

Use a human-driven pass for text entry, file panels, right-click menus, and final destructive confirmations when automation cannot prove them.

### Account and data limits

The following need controlled data or a throwaway team:

- More than 50 rows to verify resource pagination.
- Real Merchant ID and Pass Type ID for service-certificate creation.
- Disposable certificate/profile chain for revoke-invalidation timing.
- Safe app/version for submit, cancel, release, and phased release.
- Deliverable throwaway email for invitation lifecycle.
- Native save destinations for `.cer`, `.mobileprovision`, screenshots, and exports.

### Destructive operations requiring explicit care

| Operation | Risk |
| --- | --- |
| Register device | Consumes annual membership slot; cannot delete |
| Revoke certificate | Irreversible; invalidates profiles |
| Delete/regenerate profile | Irreversible; regenerate can fail after delete |
| Remove user | Requires a new invitation to restore access |
| Resend invitation | Current design revokes before recreating |
| Submit/cancel/release version | Changes production App Store state |
| Complete phased release | Changes rollout for production users |

## Recommended Work Order

1. Protect profile regeneration with device/platform validation before DELETE.
2. Fix the four failing tests.
3. Complete the controlled App Submission state-transition regression.
4. Replace invitation resend UX with an honest revoke-and-recreate flow.
5. Add robust email validation and wire/remove the Users banner.
6. Add explicit submission recovery/unknown-outcome states.
7. Add CSR generation and certificate filters.
8. Implement Devices CSV export.
9. Add automated App Info/team-switch regressions.
10. Address lower-priority status, pagination, and build-warning cleanup.
