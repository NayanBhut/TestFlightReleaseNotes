## 📋 PR Description

Batch I — provisioning writes (bundle IDs, users/invitations, profiles, beta groups, version localizations) plus the `App Store Tests` unit-test target. I1 (Export wiring) and I7 (review reply edit/delete) skipped — out of scope for this batch.

### What changed?

**I2 — Bundle ID writes**
- `BundleIdCreateRequest` (name, identifier, platform, optional seedId) / `BundleIdUpdateRequest` (name only) — shapes verified against Apple's OpenAPI spec (`BundleIdPlatform`: `IOS`, `MAC_OS`)
- `ResourcesViewModel`: `createBundleId`, `renameBundleId`, `deleteBundleId` (`WriteResult` contract, Admin-role 403 hint)
- `ResourcesView`: New button + form, per-row Rename (inline) / Delete (confirm)

**I3 — User & invitation management**
- `UserRoleOption` (all 11 spec roles), `UserUpdateRequest`, `UserInvitationCreateRequest` (email/first/last/roles + `visibleApps` relationship for single-app invites)
- `ResourcesViewModel`: `inviteUser`, `updateUserRoles`, `removeUser` (confirm), `resendInvitation` (find by `filter[email]` → delete → re-create; no dedicated resend endpoint exists)
- `ResourcesView`: Invite form (roles dropdown, single/multi-app picker), row Edit roles / Remove (confirm); pending invitations render as rows above users with Resend/Revoke
- Users list auto-drains all pages on open so local search covers the whole team (progress footer while draining, Retry resumes)

**I4 — Provisioning profiles**
- `ProfileTypeOption` (all 14 spec types), `ProfileCreateRequest` (bundleId + certificates required, devices optional)
- `ResourcesViewModel`: `createProfile`, `deleteProfile`; form pickers reuse the already-loaded bundle/cert/device lists
- Cert/device pickers are compact dropdowns with Select All/Clear; cert rows show `name · Dev/Prod · expires <date>`

**I5 — Beta group CRUD + tester removal**
- `BetaGroupCreateRequest` (name + public-link options + app relationship), `BetaGroupUpdateRequest` (name)
- `BetaViewModel`: `createGroup`, `renameGroup`, `deleteGroup`, `deleteTester` (team delete, distinct from remove-from-group); 403 → Admin hint
- `BetaGroupView`: New Group sheet, inline rename, delete (confirm), per-tester remove-from-group vs delete-from-team actions
- Invite sheet: searchable team-member picker (tap fills email/names; manual entry still works for outsiders)

**I6 — Version localization editor**
- `VersionLocalizationUpdateRequest` (description, keywords, promotionalText, whatsNew, marketingUrl, supportUrl; reuses the Batch G unchanged/clear/set field encoding)
- `DetailViewModel.saveVersionLocalization` with Apple metadata limits (keywords 100, promo 170, description/whatsNew 4000, http(s) URLs) + per-id in-flight set + App Manager 403 hint
- App Info tab "Version Localizations" card: inline Edit/Save/Cancel per locale, stays open on failure

**I8 — Unit test target + core tests**
- New `App Store Tests` XCTest target (app-hosted, JSONAPI linked, Debug/Release configs), wired into the `App Store` scheme Test action
- 35 tests, all green: ViewState, BuildDisplayHelper, APIMethod path/query composition, JSON:API fixtures (incl. the `description`-key fix), validators/enums/field-encoding, invite-body relationships, DEBUG curl redaction
- `CredentialStorage` live selection untested by design (private init runs a real-keychain migration — needs a keychain seam)

**Follow-up fixes (user-reported, same branch)**
- Roles/app/cert/device pickers converted from inline lists to dropdowns so forms fit their sheets
- Profile picker lists sized to content (no mid-row clipping)
- Load-more footer hidden while the invite form is open
- Pending invitations on top of the users list
- `Resources` sidebar section: custom collapsible header with animated chevron
- DEBUG-only API logging: full bodies + copy-pasteable `[API][CURL]` lines, token and emails always redacted; `scripts/block-temp-logging.sh` installed as pre-commit/pre-push guard

### Test Scenarios Covered
<!-- Check all that apply -->
- [x] New feature added
- [ ] Bug fix
- [x] UI changes
- [x] Swift build passes
- [ ] Ollama Cloud PR Review passes

### Ollama Cloud Review
<!-- This PR automatically triggers an Ollama Cloud review with model kimi-k3:cloud.
     The review comment is updated in place on every push. Check the Checks tab
     on this PR for test results and the posted review. -->

### Checklist
- [x] Code compiles and builds successfully
- [x] No breaking changes
- [x] Self-reviewed my code

---

### 🤖 Automated Review Notice
> This PR triggers an automated Ollama Cloud review using **kimi-k3:cloud**.
> The review posts as a comment on this PR and is updated in place on every push.
> - Add **`[skip-review]`** to your PR title to skip the LLM review
> - Add **`[smoke-test]`** to your PR title for a quick connectivity check only
