# Batch I — Overnight work plan (single worktree)

Supersedes `docs/BATCH_C_PLAN.md` (deleted; its verified gotchas are carried
forward below so nothing is lost).

Branch: `feat/batch-i-writes-and-tests`
Target: one long session (~8–10h), **commit + build after every item** so
partial progress is still reviewable if the session ends early.

---

## Repo rules (keep — do not re-litigate)

- `SWIFT_STRICT_CONCURRENCY = complete`; VMs are `@MainActor`; `guard !Task.isCancelled`
  after every await. Keep the existing pattern.
- Cursor pagination: in-flight guard **before** cancel; staleness ids recorded
  **only on success**; `ViewState { idle/loading/loaded/empty/error }`.
- `Logger(subsystem:category:)`, never `print`.
- Full-screen states use `.frame(maxWidth: .infinity, maxHeight: .infinity)` —
  **never** `Spacer()` scaffolding (it collapses and pins content top-left).
- `ErrorRetryView` (`NavigationManager.swift`) and `InfoCard` (`AppInfoView.swift`)
  are the shared renderers; reuse, don't add another copy.
- New Swift files must be registered in all 4 pbxproj sections (PBXBuildFile,
  PBXFileReference, parent group, PBXSourcesBuildPhase); run
  `plutil -lint "App Store.xcodeproj/project.pbxproj"` after editing.
- Do **not** touch: the onboarding stash (`git stash list` → `onboarding-close-button-esc-fix`),
  `BATCH_C_PLAN.md` references, or unrelated tabs.
- API keys are often TestFlight-only: a 403 must surface the existing
  "needs broader permissions" hint, not a raw error.

## Verified API gotchas (from prior batches — don't re-derive)

- App-scoped routes are composed as `.get(name: .getAllApps, path: "\(appId)/x")`,
  e.g. `/apps/{id}/appInfos`, `/apps/{id}/customerReviews`. A raw
  `case x = "/appInfos"` builds an invalid `/v1/appInfos/{path}` — don't.
- There is **no** `/v1/apps/{id}/appEncryptionDeclarations`; export compliance is
  top-level `GET /v1/appEncryptionDeclarations?filter[app]=`.
- `CompoundDocument<T, Meta>` needs `meta` unless `Meta == Unit`
  (use the `NoMeta` alias for fixed-size collections).
- `reviewSubmissions` has **no sort param**; `customerReviews` sorts only by
  `rating` / `createdDate`.
- Invalid include paths or wrong `@ResourceWrapper(type:)` fail the **whole**
  document decode (400). Verify every include against the OpenAPI spec first.
- `@ResourceAttribute(key: "description")` is required for
  `appStoreVersionLocalizations.description` (bare `descriptionData` silently drops it).
- Apple metadata limits: name/subtitle 30, keywords 100, promotionalText 170,
  description/whatsNew 4000. URLs must be `http(s)`.

---

## Items (implement in this order, commit after each)

### I1 — Wire ExportManager into the Builds tab (~1h)
`Helper/ExportManager.swift` has `exportBuilds` / markdown / csv / `shareFile` /
`openInFinder` and **zero call sites**.
- `BuildDetailsView.swift` `buildsHeader()`: add an Export `Menu` beside Snippets
  → "Copy as Markdown", "Copy as CSV", "Save file…".
- Needs `viewModel.selectedVersion` + `viewModel.arrBuilds`; disable when either is empty.
- Copy paths → `NSPasteboard` (same pattern as the Snippets menu); file path → `ExportManager`.

### I2 — Bundle ID writes (~1h)
- `APIName`: reuse `getBundleIds = "/bundleIds"` with POST/PATCH/DELETE verbs.
- Models: `BundleIdCreateRequest` (name, identifier, platform, optional seedId),
  `BundleIdUpdateRequest` (name only).
- `ResourcesViewModel`: `createBundleId`, `renameBundleId`, `deleteBundleId`
  (+ destructive confirm), `WriteResult` pattern like devices/certificates.
- `ResourcesView`: New button + form, per-row Rename / Delete.

### I3 — User & invitation management (~2h)
- Endpoints: `GET/PATCH/DELETE /v1/users/{id}`, `GET/POST/DELETE /v1/userInvitations`.
  (Add `userInvitations = "/userInvitations"`; verify shapes against the spec.)
- Roles enum from the spec (`ADMIN`, `FINANCE`, `ACCOUNT_HOLDER`, `SALES`,
  `MARKETING`, `APP_MANAGER`, `DEVELOPER`, `ACCESS_TO_REPORTS`, `CUSTOMER_SUPPORT`).
- `ResourcesViewModel` (users kind): `inviteUser`, `updateUserRoles`,
  `removeUser` (with confirm), `resendInvitation`.
- `ResourcesView` `UserRow`: role chips + Invite / Edit roles / Remove.
- Deletes on `/users` may 403 for non-Admin — surface the permissions hint.

### I4 — Provisioning profiles (~1.5h)
- `POST /v1/profiles` (name, profileType, bundleId + certificates + devices
  relationships), `DELETE /v1/profiles/{id}`.
- `ProfileType` full enum from the spec; reuse the existing certificate/device
  fetch for relationship pickers.
- `ResourcesViewModel`: `createProfile`, `deleteProfile`; `ResourcesView`:
  New + Delete with confirm.

### I5 — Beta group CRUD + tester removal (~1.5h)
- `POST /v1/betaGroups` (name, optional publicLinkEnabled/publicLinkLimit),
  `PATCH /v1/betaGroups/{id}`, `DELETE /v1/betaGroups/{id}`.
- `DELETE /v1/betaTesters/{id}` (delete tester from team).
- `BetaViewModel`: `createGroup`, `renameGroup`, `deleteGroup`, `deleteTester`.
- `BetaGroupView`: New group / rename / delete (confirm), tester row delete.

### I6 — App Store version localization editor (~2h)
- `PATCH /v1/appStoreVersionLocalizations/{id}` with `description`, `keywords`,
  `promotionalText`, `whatsNew`, `marketingUrl`, `supportUrl`.
- New inline editor in the **App Info** tab's "Version Localizations" card
  (mirror `AppInfoLocalizationRow`'s Edit/Save/Cancel pattern; stays open on failure).
- Client validation with the limits above + `http(s)` URL check; per-id in-flight set;
  403 → App Manager hint.
- This is the biggest-value item: it makes store metadata editable, not just readable.

### I7 — Review reply edit / delete (~1h)
- `PATCH /v1/customerReviewResponses/{id}` (responseBody),
  `DELETE /v1/customerReviewResponses/{id}`.
- `ReviewsViewModel`: `editReply`, `deleteReply`; `ReplySection` gains Edit/Delete
  when a response already exists; optimistic in-row update on success.

### I8 — Unit test target + core tests (~2h) — no API needed
- Add a `App Store Tests` XCTest target to the pbxproj, `@testable import App_Store`.
- Cover the pure logic that bugs have actually come from:
  - JSON decoding of the JSON:API models (incl. the `description` key fix).
  - `APIClient.getURL` / `APIMethod` query-item + path composition (nil vs empty params).
  - `ViewState` transitions and `loadedValue` / `errorMessage` accessors.
  - Build status mapping + date formatting (`BuildDisplayHelper`).
  - `CredentialStorage` selection logic (mock keychain if feasible).
- Run with `xcodebuild test -project ... -scheme "App Store" -destination "platform=macOS"`.
- ⚠️ pbxproj target creation is the riskiest change here: do it **last**, in its
  own commit, and if it destabilises the build, revert just that commit and note it.

---

## Commit / verification strategy

After each item:
1. `plutil -lint "App Store.xcodeproj/project.pbxproj"`
2. `xcodebuild -project "App Store.xcodeproj" -scheme "App Store" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build | grep -E "error:|BUILD"`
3. Commit with `feat(batch-i): <item> — <what>`.

## Manual smoke (end of session, list in the PR)

- Builds → Export menu copies Markdown/CSV and saves a file.
- Resources → Bundle IDs: create, rename, delete.
- Resources → Users: invite, edit roles, remove.
- Resources → Profiles: create (with bundle/cert/device), delete.
- Beta Groups: create, rename, delete; remove a tester.
- App Info → Version Localizations: edit description/keywords/whatsNew, save, reopen.
- Reviews: reply → edit reply → delete reply.
- `xcodebuild test` green (if I8 landed).

## Out of scope (still follow-ups)

Sales/finance reports • screenshot/asset upload • review submission create/cancel &
phased release • in-app events • webhooks • App Store Connect web-only actions.

## Live-write caveat

I2–I7 are writes. Test on a throwaway bundle ID / device / dummy group first, and
expect 403 on a TestFlight-only key — the correct behaviour is the permissions hint,
not a crash or a silent no-op.
