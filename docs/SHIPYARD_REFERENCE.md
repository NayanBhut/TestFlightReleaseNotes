# Shipyard Engineering and Test Reference

Last consolidated: 2026-10-07

This is the canonical reference for maintaining and testing Shipyard. It replaces the historical batch plans, feature audits, flow reports, Figma notes, and live-test journals that previously lived across `docs/` and `LIVE_FLOWS.md`.

For unresolved defects, unsupported features, and incomplete verification, use `docs/SHIPYARD_BLOCKERS_AND_BUGS.md`.

## Product Scope

Shipyard is a native macOS SwiftUI client for the App Store Connect API. The active UI is the Shipyard shell; deleted legacy views must not be restored.

The current product surface includes:

- Multiple App Store Connect teams stored in Keychain.
- Apps, versions, builds, TestFlight notes, beta groups, and testers.
- App Info and version-localized metadata.
- Screenshot-set creation, upload, listing, and deletion.
- App Store version preparation, build attachment, review submission, cancellation, release, and phased release.
- Customer reviews and developer responses.
- Processing-build monitoring.
- Devices, certificates, Merchant IDs, Pass Type IDs, Bundle IDs, capabilities, profiles, users, and invitations.
- Shared success, warning, and failure toasts for write operations.

## Build and Verification

Run the same build used by CI:

```sh
plutil -lint "App Store.xcodeproj/project.pbxproj"

xcodebuild -project "App Store.xcodeproj" -scheme "App Store" -sdk macosx \
  -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
  build -skipMacroValidation
```

Run tests with:

```sh
xcodebuild test -project "App Store.xcodeproj" -scheme "App Store" \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Before committing, run `scripts/block-temp-logging.sh`. Never commit temporary API logging or credentials.

New Swift files must be added to the Xcode target in `project.pbxproj`; always run `plutil -lint` after a project-file edit.

## Architecture and Ownership

| Area | Primary code |
| --- | --- |
| App entry and authentication routing | `App_StoreApp.swift`, `ContentView/ContentView.swift` |
| Main shell and team lifecycle | `Shipyard/ShipyardShell.swift`, `Shipyard/ShipyardSidebar.swift` |
| Apps and app-level tabs | `Shipyard/AppDetailView.swift` |
| Builds and TestFlight notes | `Shipyard/BuildsTableView.swift`, `Shipyard/ReleaseNotesView.swift`, `BetaViewModel` |
| App Info and screenshots | `Shipyard/ShipyardAppInfoView.swift`, `SideBarView/DetailView/DetailViewModel.swift`, `SideBarView/DetailView/AppInfo/ScreenshotsSheet.swift` |
| App Store versions and submission | `Shipyard/ReleaseTabView.swift`, `ReleasePrepareView.swift`, `ReleaseStatusViews.swift`, `ReleaseDialogs.swift`, `ChooseBuildSheet.swift` |
| Reviews and submission state | `SideBarView/DetailView/Reviews/ReviewsViewModel.swift`, `ReviewsView.swift` |
| Devices and signing resources | `SideBarView/Resources/ResourcesView.swift`, `ResourcesViewModel.swift`, `ResourceModels.swift` |
| Resource-specific tables and inspectors | `Shipyard/Devices*`, `CertificatesTableView.swift`, `BundleIDsTableView.swift`, `ProfilesTableView.swift`, `ProfileViews.swift`, `UsersTableView.swift`, `UserPermissionViews.swift` |
| Networking and endpoints | `Model/JSONAPIModels/APIManager.swift`, `APIModels.swift`, `ReviewModels.swift`, `ResourceModels.swift` |
| Shared visual/status helpers | `Helper/AppTheme.swift`, `BuildDisplaySupport.swift`, `ShipyardToast.swift`, `StateView.swift` |

Shared view models are app/team scoped. A team switch must cancel in-flight work, increment request generations, clear pagination cursors, clear selected app/version/build state, dismiss stale detail screens, and reload with the new credentials.

## Navigation Contract

### Sidebar

The sidebar contains:

- Apps
- Processing Builds
- Devices
- Certificates
- Identifiers
- Bundle IDs
- Profiles
- Users

Reviews are intentionally not duplicated in the sidebar. Customer reviews remain inside App Detail because reviews require an explicit app context.

### App Detail

App Detail contains:

- Builds
- App Info
- Reviews
- App Store Versions

Builds includes TestFlight release-note editing. App Store Versions owns version selection and submission state. A nested version detail must always provide a back route to the versions list.

## App Store Submission Flow

### User path

1. Open Apps and select an app.
2. Open App Store Versions.
3. Select the editable version or create a new version when permitted.
4. Choose a valid build matching the marketing version and platform.
5. Complete localized What's New, review contact, demo credentials when required, and release settings.
6. Save all dirty fields.
7. Submit for review.
8. Follow the state-specific screen for Waiting, In Review, Rejected, Pending Release, Processing, or Live.

Binary upload itself remains outside Shipyard. Upload with Xcode Organizer or Apple tooling, then wait for the build to become `VALID` before attaching it.

### Editable states

The editable App Store version states are:

- `PREPARE_FOR_SUBMISSION`
- `REJECTED`
- `DEVELOPER_REJECTED`
- `METADATA_REJECTED`
- `INVALID_BINARY`

Waiting, in-review, approved, processing, live, removed, and replaced versions are read-only except for state-specific operations Apple permits.

### Submit gate

Submission is enabled only when:

- The shown version is the selected editable pending version.
- A matching valid, unexpired build is attached.
- Required version localizations are loaded and complete.
- Update versions have non-empty What's New; first releases do not send What's New.
- Review first name, last name, phone, and email are present once review details are known.
- Demo username and password are present when sign-in is required.
- Scheduled release data has been saved.
- No draft is dirty and no save is in flight.

### Review submission pipeline

The submission sequence is:

1. `POST /v1/reviewSubmissions`
2. `POST /v1/reviewSubmissionItems`
3. `PATCH /v1/reviewSubmissions/{id}` with `submitted: true`
4. Refetch versions and submissions; never invent a local terminal state.

Cancellation patches the review submission with `canceled: true`, then refetches server state. Manual release uses `POST /v1/appStoreVersionReleaseRequests`.

### Build picker

Candidate builds must be filtered by app, marketing version, and platform. Only `VALID`, unexpired builds are selectable. The sheet shows loading while candidates load and a blocking `Updating build…` state while the build relationship is patched. After success, update the local version relationship before dismissing, then reconcile with a background refetch.

### Version-state labels

| API state | Display meaning |
| --- | --- |
| `PREPARE_FOR_SUBMISSION` | Draft |
| `WAITING_FOR_REVIEW`, `READY_FOR_REVIEW` | Waiting for Review |
| `IN_REVIEW` | In Review |
| `PENDING_DEVELOPER_RELEASE` | Approved, ready for manual release |
| `REJECTED`, `DEVELOPER_REJECTED` | Rejected |
| `METADATA_REJECTED` | Metadata Rejected |
| `INVALID_BINARY` | Invalid Binary |
| `PENDING_CONTRACT` | Pending Contract |
| `PROCESSING_FOR_DISTRIBUTION` | Processing |
| `READY_FOR_SALE`, `READY_FOR_DISTRIBUTION` | Live |

## App Info, Locales, and Screenshots

App Info must activate the selected app before requesting metadata. Draft fields must not initialize from an empty loading state; untouched fields continue following server values as asynchronous App Info and localization responses arrive.

Use Apple's exact locale shortcodes, for example `en-US`, `en-GB`, `de-DE`, `fr-FR`, `es-ES`, and RTL `ar-SA`. Text controls should respect locale direction while retaining copy/select behavior in read-only version screens.

Client-side limits:

| Field | Limit |
| --- | --- |
| Name | 2–30 characters |
| Subtitle | 30 characters |
| Keywords | 100 characters |
| Promotional text | 170 characters |
| Description | 4,000 characters |
| What's New | 4,000 characters |
| URLs | `http` or `https` only |

Screenshot upload uses Apple's reserve, upload-operations `PUT`, and commit pipeline:

- `GET /v1/appStoreVersionLocalizations/{id}/appScreenshotSets`
- `POST /v1/appScreenshotSets`
- `GET /v1/appScreenshotSets/{id}/appScreenshots`
- `POST /v1/appScreenshotSets/{id}/appScreenshots`
- Upload every reserved operation exactly as returned.
- Commit only after all operations succeed.
- `DELETE /v1/appScreenshots/{id}` removes a screenshot.

Read-only versions still show sets and thumbnails; create, upload, and delete controls stay hidden.

## TestFlight and Builds

- Build release notes are `betaBuildLocalizations`, not App Store version localizations.
- Keep notes compact inside build rows, with expand/collapse, locale chips, and a locale picker.
- Locale-specific notes support create, save, revert, and delete.
- A build row should remain usable while release notes are collapsed.
- Processing builds should expose last refresh, loading/error state, and manual retry.
- Server cursors must not be reused after changing query parameters; local filtering/sorting is preferred where Apple does not support the desired server sort.

## Resource Flows

### Devices

- List, search, platform filter, inspect, register, rename, enable, and disable are implemented.
- Modern UDIDs are `8` alphanumeric characters, a dash, then `16` alphanumeric characters. Classic UDIDs are `40` hexadecimal characters.
- Registration consumes a membership-year slot and devices cannot be deleted through the API.
- Disabling can invalidate dependent profiles; confirmation must describe that impact.
- CSV import must validate every row before or during the sequential write and report partial results honestly.

One historical live test registered `deadbeefdeadbeefdeadbeefdeadbeefdeadbeef`, later renamed to `Renamed Throwaway 01`, and left it enabled. It consumed one yearly registration slot.

### Certificates and Identifiers

- Certificate creation requires CSR content.
- Apple Pay certificate types require a `merchantId` relationship.
- Pass Type certificate types require a `passTypeId` relationship.
- The create UI must block submission until the required relationship resource ID is selected or entered.
- Revoke is irreversible and invalidates dependent provisioning profiles; invalidate and refetch the profiles cache after a successful revoke.
- Download fetches certificate detail because `certificateContent` is not guaranteed in list responses.
- Merchant IDs and Pass Type IDs are listed and created from the Identifiers screen.
- App Groups must not call an invented endpoint; show an explicit unsupported/manual guidance state unless an official API contract is verified.

Live regression evidence confirmed the original Apple Pay failure, `You must provide a value for the attribute merchantId`, changed after the fix to an invalid-related-resource error when a fake Merchant ID was deliberately supplied. This proves the relationship is now encoded.

### Bundle IDs

- Support list, search, create, rename, dependency inspection, delete-if-unused, and capability enable/disable.
- Create uses name, identifier, platform, and optional seed ID.
- Delete must re-check dependent apps/profiles and explain dependency changes rather than retrying blindly.
- Capability writes must use the official capability type and relationship shapes.

### Profiles

- Create profiles with a Bundle ID, compatible certificate set, and devices when required by profile type.
- Detail fetches Bundle ID, certificates, devices, profile content, and local private-key availability.
- Download and Install for Xcode are local file operations after authenticated detail fetch.
- Delete requires explicit confirmation.
- Regenerate is delete-and-recreate because Apple exposes no profile update endpoint; treat partial failure as destructive and report it explicitly.
- Revoke-related profile state must be refetched rather than inferred indefinitely.

### Users and Invitations

- Members and pending invitations are separate resources: `/v1/users` and `/v1/userInvitations`.
- Account Holder controls are read-only. The shared `isAccountHolderUser` predicate must gate row menus, detail actions, accessibility actions, and the ViewModel delete path.
- Role summaries must use deterministic role precedence, never `Set` iteration order.
- Selected-app access requires at least one app; All Apps invitations must omit `visibleApps` relationships.
- Resend has no dedicated endpoint and currently uses revoke plus re-create; partial failure must state whether the old invitation is gone.
- Invite, update, remove, resend, and revoke actions report through the shared toast system.

### Customer Reviews

- Reviews remain app-scoped inside App Detail.
- Customer review and App Review submission are different workflows; do not mix customer reply actions with version submission.
- Verify every `include`, filter, and sort against Apple's OpenAPI contract before adding it. Invalid include paths fail the entire JSON:API request or decode.

## API and State-Management Rules

- View models are `@MainActor`.
- Every asynchronous state machine needs cancellation, generation/epoch validation, app/team/version identity checks, loading, error, and retry states.
- Check `Task.isCancelled` after each `await` before mutating published state.
- Cursor pagination uses Load More. Default page sizes: apps 50, versions 10, builds 5, reviews/resources 50, processing poll cap 50.
- Never combine a cursor issued under one sort/filter query with a changed query.
- App-scoped routes use the app endpoint plus a path, for example `/apps/{id}/appInfos`.
- Export compliance is top-level: `GET /v1/appEncryptionDeclarations?filter[app]=...`.
- `reviewSubmissions` does not support arbitrary sort parameters.
- `customerReviews` sorting is limited to API-supported keys such as rating or created date.
- Use `NoMeta` for JSON:API collections that do not return `meta`.
- `appStoreVersionLocalizations.description` requires `@ResourceAttribute(key: "description")`.
- A 403 should explain the required App Store Connect role instead of showing only a raw status.

Typical role requirements:

| Operation | Minimum practical role |
| --- | --- |
| Read builds and TestFlight notes | TestFlight-capable key |
| App Info, versions, screenshots, review submission | App Manager or Admin |
| Devices, certificates, profiles, users | Admin for the broadest coverage |
| Sales/finance reports | Matching Finance/Sales access |

## Live-Test Safety

- Work against a throwaway app, identifier, profile, certificate, device, or invitation whenever possible.
- Device registration consumes a yearly slot and cannot be deleted.
- Certificate revoke is irreversible and invalidates profiles.
- Profile regenerate deletes first; a failed create can leave no profile.
- User removal is irreversible without re-invitation.
- Invitation sends email to a real mailbox.
- Build attachment, metadata save, submission, cancellation, release, and phased-release operations affect production App Store Connect state.
- Record created resource IDs, cleanup outcome, server error text, and final state in the test run.

## Accessibility-Driven Testing

Preferred loop: snapshot, act, snapshot, verify. Re-read the accessibility tree after every navigation or render because element indexes are short-lived.

Important macOS/Orca lessons:

- Two apps with the same bundle ID must be targeted by full app path or process ID.
- `/usr/local/bin/orca` may fail with `Unable to determine Orca.app path from symlink`; use the configured computer-use tool or the Orca app binary only when the current skill guide permits it.
- `set-value` can change the accessibility value without firing a SwiftUI binding.
- `paste-text` works when a field already has keyboard focus; a synthetic click may not make it first responder.
- Native open/save panels, context menus, and menu popovers may be unavailable to the automation provider.
- A dismissed sheet is not proof of a successful write. Verify the loading state, toast, list mutation, and server refetch.
- If Finder also reports no accessibility window while permissions are granted, the accessibility bridge is stalled; retry with backoff, then have a human toggle Orca Computer Use permission if needed.
- Never activate row secondary actions until confirming whether they are destructive.

## Regression Checklist

After changes to shared state or navigation, verify:

1. App Info populates on first open without visiting another tab first.
2. Switching teams from an app/resource detail clears old-team state.
3. Reviews load only for the selected app.
4. App Store Versions shows the intended current/live versions and version detail data.
5. Choose Build lists only matching version/platform builds, scrolls, selects, and shows loading while fetching/attaching.
6. Unsaved submission edits keep Submit disabled.
7. First-release What's New remains disabled and is not sent.
8. Locale switching preserves correct text direction and selectable read-only text.
9. Screenshot set/image counts reload after upload or delete.
10. Certificate type changes clear stale server errors.
11. Certificate revoke invalidates/refetches Profiles.
12. Account Holder cannot be removed from any surface.
13. Role summaries are stable between list and detail.
14. Every write shows success or failure feedback.
15. Team switching cancels stale responses and returns to Apps.

## Historical Fixes Worth Protecting

These defects are fixed and should remain regression cases:

- App Info was blank on first open because empty drafts masked asynchronously loaded server values.
- Team switching left old app/resource detail visible.
- Apple Pay and Pass Type certificate requests omitted required relationships.
- Certificate revoke left the profiles list stale.
- Certificate search empty state incorrectly claimed the team had no certificates.
- Profile wizard Back dismissed the sheet; regenerate Review and delete-sheet presentation also dismissed or failed to open.
- Regenerate result selected the first profile instead of the actual replacement.
- Modern 25-character UDIDs were rejected by the client validator.
- Account Holder removal appeared in the row context menu.
- User role summary used nondeterministic `Set` order.
- All-Apps invitation resend incorrectly included `visibleApps`.
- Submission gating omitted phone, demo credentials, dirty drafts, saved scheduled date, and first-release What's New behavior.
