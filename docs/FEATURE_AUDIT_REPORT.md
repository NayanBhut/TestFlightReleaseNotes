# Feature Audit Report

Date: 2026-10-07  
Scope: Native macOS SwiftUI App Store Connect client (`Shipyard` shell, team resources, app detail, app submission, provisioning resources).  
Status: Code-backed feature audit complete; live accessibility testing resumed after unlock. App Info first-open regression is fixed and live verified.

## Executive Summary

The app currently covers the main App Store Connect operational areas from one shell: team login/switching, app navigation, builds, TestFlight notes, App Info metadata, screenshots, app review/submission, customer reviews, processing-build monitoring, devices, certificates, merchant IDs, pass type IDs, bundle IDs, profiles, users, and invitations.

Recent high-priority fixes are present in code and already build/test verified: Apple Pay certificate creation now sends the required `merchantId` relationship, Pass Type ID certificate creation sends `passTypeId`, App Info first-entry activation was repaired, team switching resets stale detail/resource/review state, and success/failure toasts were added across the major write flows.

Live create/update/delete validation against the real Apple account is still incomplete. Do not treat write scenarios below as completed live evidence until the `Live UI Result` column is filled in.

## Verification Status

| Area | Result | Notes |
| --- | --- | --- |
| Build | Passed previously | `xcodebuild -project "App Store.xcodeproj" -scheme "App Store" -sdk macosx -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" build -skipMacroValidation` passed after the certificate, App Info, toast, and icon changes. |
| Project file | Passed previously | `plutil -lint "App Store.xcodeproj/project.pbxproj"` passed. |
| Focused tests | Passed previously | Certificate relationship bodies, identifier create bodies, API names, and certificate relationship decoding tests passed. |
| Live accessibility run | Partial | Verified App Store Versions navigation, first-release draft form, dirty-state submit gate, phone/demo/scheduled-date code gates, first-release What’s New UI, App Info first-open hydration, and team-switch stale-view reset. Mac locked during the earlier final Save click, so review-contact save result is still pending. |
| Real Apple writes | Partially attempted | User authorized create/update/delete. Review-contact save was prepared but not confirmed because accessibility lost Mac access at the Save action. Some operations are irreversible or quota-limited and still need safe throwaway data. |

## Product Surface Inventory

### Team And Shell

| Feature | Current Capability | Risk / Improvement |
| --- | --- | --- |
| Add team | Stores App Store Connect API credentials in Keychain and enters authenticated shell. | Add a post-save connectivity check so invalid keys fail before entering the shell. |
| Switch team | Sidebar team selector switches active credentials; shell resets detail/resources/reviews state. Live verified from App Info: switching Team 1 → Team 2 returned to the Team 2 Apps list, then Team 2 → Team 1 returned to the SmartClean AI team. | Add an automated UI/ViewModel regression test for stale-view prevention. |
| Delete team | Removes selected team credentials from Keychain with confirmation. | Show which local cached view state will be cleared after delete. |
| Navigation | Sidebar routes Apps, Processing Builds, Devices, Certificates, Identifiers, Bundle IDs, Profiles, Users, Reviews. | Builds row currently shares the Apps grid icon; use a distinct build/package icon. |
| Toasts | Shared toast overlay supports success/failure feedback across recent write paths. | Add an audit log/history panel for destructive actions, not only transient toasts. |

### Apps And Builds

| Feature | Current Capability | Risk / Improvement |
| --- | --- | --- |
| Apps list | Loads apps with pagination, local search/sort, and app detail navigation. | Add visible team badge in list header to reinforce current team after switches. |
| App detail | Per-app tabs: Builds, TestFlight, App Info, Reviews, App Store Versions. | Add breadcrumb from nested app detail back to sidebar resource areas. |
| Builds | Shows loaded builds and related metadata used by TestFlight/submission flows. | README mentions build table export, but current branch has no export manager; either implement CSV/Markdown export or remove stale README claims. |
| Processing builds | Menu/sidebar monitoring for processing builds. | Add last poll time and manual retry reason when processing count is stale. |
| Build selection | App submission flow can choose a build for a version. | Add stronger “processed only” visual gating and explain missing-build causes. |

### TestFlight

| Feature | Current Capability | Risk / Improvement |
| --- | --- | --- |
| Release notes | Create/update/delete build localizations for TestFlight notes. | Add diff preview before saving existing notes. |
| Beta groups | Beta group/tester views exist through shared `BetaViewModel`. | Include clearer status copy for invite-only tester states, because Apple exposes limited per-tester activity. |
| Tester invite sheet | Invites testers from the beta UI. | Add duplicate-invite detection before submit if API returns an identifiable conflict. |

### App Info Metadata

| Feature | Current Capability | Risk / Improvement |
| --- | --- | --- |
| First-load App Info | Fixed path activates the app before App Info/reviews version loading; live accessibility verified app name, subtitle, description, URLs, promo text, and screenshots populate on first open. | Add a regression test for opening App Info first from a fresh app detail. |
| App info localization | Save localized app name/subtitle/privacy/promo/URLs/categories where supported by current forms. | Show exact Apple role required beside disabled save states. |
| Version localization | Save version text such as What's New and localized metadata. | Add unsaved-change navigation guard when switching locale/version. |
| Locale management | Create/delete version localizations. | Show fallback locale and missing-required-locale warnings before submission. |
| Screenshots | Create screenshot sets, upload images, delete screenshots. | Add per-device-size checklist and image dimension validation before upload. |

### App Submission

| Feature | Current Capability | Risk / Improvement |
| --- | --- | --- |
| App Store Versions | Lists versions and state-specific screens for prepare, review, rejected, pending release, and live paths. | Highest-priority live test area; must verify every state transition with real data or a fake API harness. |
| Create version | New-version sheet exists from the versions tab. | Add preflight check for duplicate platform/version number before POST. |
| Choose build | Allows selecting a build for a version. | Add clear empty state for “no processed builds available.” |
| Release settings | Manual/automatic/scheduled release options are surfaced. | Scheduled date must be saved before submit; UI should say “Save release date to continue.” |
| Review details | Review contact/demo/sign-in details can be saved. | Fixed in code: phone is now part of the same submit-gating group as first name, last name, and email. Live UI verified dirty-state gate; server save still pending because Mac locked during Save. |
| Demo credentials | Sign-in demo fields are displayed when required. | Fixed in code: demo username/password now block submit when sign-in is enabled. Focused tests cover it; live toggle/save still pending. |
| Submit for review | Creates or reuses review submission items and PATCHes `submitted=true`. | Add a final preflight summary with exact missing server objects and a retry-safe state display. |
| Cancel submission | Cancels an active review submission. | Confirm copy should include current version/platform and resulting state. |
| Release version | Supports manual release path when version is approved/pending release. | Add explicit “this is production” confirmation copy. |
| Phased release | Supports phased-release state changes. | Add visible phased-release history and next rollout step. |

### Customer Reviews

| Feature | Current Capability | Risk / Improvement |
| --- | --- | --- |
| Reviews list | Loads customer reviews from sidebar or app detail. | Add filters for rating/territory/version if API support is verified. |
| Reply | Posts developer response to a review. | Add edit/delete response support if current API permissions and endpoints are available. |
| App-scoped navigation | Reviews can be reached globally and within app detail. | Keep app filter state visible so global vs app-scoped results are obvious. |

### Devices

| Feature | Current Capability | Risk / Improvement |
| --- | --- | --- |
| List devices | Loads devices with search, pagination, state display. | Add platform/status filter chips for large teams. |
| Register device | POST `/v1/devices` with name/platform/UDID validation. | Device registration counts against Apple annual limits and cannot be deleted; require a stronger quota warning before live tests. |
| Enable/disable device | PATCH status to `ENABLED`/`DISABLED`. | Show affected active provisioning profiles before disabling. |
| Rename device | PATCH device name. | Add duplicate-name warning if local list already has the name. |
| CSV import | Imports multiple devices from CSV and shows per-row results. | Add downloadable CSV template from the UI. |
| Dependent profiles | Device detail scans profiles and links to dependent profiles. | Add “refresh dependents” after enable/disable without leaving detail. |

### Certificates

| Feature | Current Capability | Risk / Improvement |
| --- | --- | --- |
| List certificates | Loads certificates with search, pagination, type/status/expiration display. | Add expiration filter and “expires soon” grouping. |
| Create certificate | POST `/v1/certificates` from CSR content. | Add in-app CSR/key generation option or a guided `openssl` copy command; user asked that CSR creation should be possible. |
| Apple Pay certificate | Sends `relationships.merchantId` for Apple Pay certificate types. | Live test pending after Mac unlock; ensure picker reloads after creating a new Merchant ID. |
| Pass Type certificate | Sends `relationships.passTypeId` for Pass Type certificate types. | Live test pending after Mac unlock; ensure picker reloads after creating a new Pass Type ID. |
| Download certificate | Fetches detail to read `certificateContent`, then saves `.cer`. | Add default save location memory and copy fingerprint after download. |
| Detail inspector | Fetches certificate detail and shows full payload fields. | Add linked owner display for Merchant/Pass certificates when relationships are available. |
| Revoke certificate | DELETE certificate with confirmation; profiles cache invalidates afterward. | Add a pre-revoke dependency preview listing profiles signed by the certificate. |

### Identifiers

| Feature | Current Capability | Risk / Improvement |
| --- | --- | --- |
| Merchant IDs | List/create Merchant IDs for Apple Pay. | No delete/cleanup path in current UI; add if Apple API supports it or document that cleanup is Apple portal only. |
| Pass Type IDs | List/create Pass Type IDs for Wallet passes. | No delete/cleanup path in current UI; add if Apple API supports it or document that cleanup is Apple portal only. |
| App Groups | Sidebar copy can explain App Groups, but App Groups are not implemented as a full API-backed resource. | Add a real App Groups section if API coverage exists; otherwise add manual Apple Developer Portal deep-link/help. |
| Bundle IDs | Separate full resource section supports app identifiers. | Consider nesting Merchant/Pass/App Groups under a dedicated “Identifiers” hub instead of separate sidebar rows plus hub. |

### Bundle IDs

| Feature | Current Capability | Risk / Improvement |
| --- | --- | --- |
| List Bundle IDs | Loads Bundle IDs with search, pagination, platform/name/identifier display. | Add filters for platform and explicit/wildcard type. |
| Create Bundle ID | POST `/v1/bundleIds` with name, identifier, platform, optional seed ID. | Add reverse-DNS validation and “test identifier” naming helper. |
| Rename Bundle ID | PATCH name. | Add unsaved-change guard in detail if rename sheet is open. |
| Delete Bundle ID | Pre-checks dependent apps and profiles, then DELETE if unused. | If dependencies changed between pre-check and delete, show a targeted “dependency changed” retry message. |
| Capabilities | Lists, enables, and disables Bundle ID capabilities. | Add capability-specific setup guidance for advanced/manual capabilities. |
| Dependency detail | Shows dependent profiles/apps and jump links. | Add direct app jump by ID if API can return app IDs reliably for dependencies. |

### Profiles

| Feature | Current Capability | Risk / Improvement |
| --- | --- | --- |
| List profiles | Loads provisioning profiles with relationships and local search. | Add profile-state/type filters and expired/invalid grouping. |
| Create profile | POST `/v1/profiles` with bundle ID, certificates, and devices when needed. | Add preflight “profile type requires devices” checklist and clearer App Store vs Ad Hoc explanations. |
| Delete profile | DELETE profile with confirmation. | Show affected local downloaded file/install status if known. |
| Download profile | Fetches `profileContent` and saves `.mobileprovision`. | Add “Reveal in Finder” after save. |
| Install for Xcode | Uses profile file data for local installation. | Add success toast with installed UUID/name. |
| Detail inspector | Fetches bundle ID, certificates, devices relationships. | Add missing relationship recovery hints when Apple omits included resources. |
| Regenerate profile | Delete + create replacement profile. | High-risk partial failure path; add a dry-run review and “old profile will be deleted first” emphasis. |

### Users And Invitations

| Feature | Current Capability | Risk / Improvement |
| --- | --- | --- |
| List users | Loads team users with visible apps and role/provisioning state. | Add role/status filters and export of current access matrix. |
| Invite user | POST `/v1/userInvitations`, supports all-apps or app-scoped invitations. | Live tests need a safe throwaway email; never test against a real teammate accidentally. |
| Pending invitations | Loads pending invites separately and merges into user search experience. | Add age/sent-date if API exposes it. |
| Resend invitation | Deletes old invite then re-creates identical invite. | High-risk partial failure path; copy already warns, but add a preflight review before deletion. |
| Revoke invitation | DELETE pending invitation. | Add undo guidance: revoked invite must be re-created. |
| Edit user | PATCH roles, all-apps/app-scoped access, provisioning access while preserving unknown roles. | Add role templates/presets for common teams. |
| Remove user | DELETE user with Account Holder guard. | Add a two-step confirmation with username and roles for non-test accounts. |

## Bugs And Gaps Found

| Priority | Item | Area | Evidence / Impact | Suggested Fix |
| --- | --- | --- | --- | --- |
| P0 | App submission needs full live regression | App Submission | App submission is the highest-risk production workflow and includes several server-state transitions. Current verification is code/build/docs-backed only. | Execute the live app submission matrix or add a fake API harness that simulates all version states. |
| Fixed / Live Pending | Phone required marker mismatch | App Submission | Code now blocks submit when phone is blank in known review details; focused test covers it. | Validate through live UI once Mac is unlocked. |
| Fixed / Live Pending | Demo credentials not submit-gated | App Submission | Code now blocks submit when sign-in is enabled and demo username/password are blank; focused test covers it. | Validate through live UI once Mac is unlocked. |
| Fixed / Live Verified | Scheduled release date / unsaved edits need clearer save dependency | App Submission | Code now blocks submit while saving or while release/review/metadata drafts are dirty; action bar says to save first. Focused tests cover the submit gate. | Live UI verified: after filling required fields, action bar showed “Save changes to continue” and Submit stayed unavailable. |
| Fixed / Save Pending | First-release What’s New wrongly required and patched | App Submission | Live test found version 1.0 first release tried to PATCH What’s New and failed with a state/conflict message. Code now detects first releases, removes the `*`, disables the field with explanatory copy, and excludes it from save/missing-items. | Server-save verification for review contact is pending because the Mac locked during Save. |
| P1 | Real write operations need safer test mode | Resources | User authorized writes, but devices/certs/users can be irreversible or quota-impacting. | Add a visible “Audit/Test write” naming convention helper and destructive quota warnings. |
| P1 | No cleanup path for Merchant IDs / Pass Type IDs | Identifiers | Create/list exists, but current UI does not expose delete. | Verify API delete support; add delete if supported or document Apple portal cleanup. |
| P2 | App Groups are not API-backed in UI | Identifiers | User asked for App Groups/IDs; current app has a hub but no full App Groups CRUD. | Add App Groups API support if possible or a clear manual-only page. |
| Fixed / Live Verified | App Info first-open stayed blank | App Info | Live repro showed blank App Info on first navigation because empty draft state masked server values after async localization loads. | Fixed: drafts no longer seed from empty loading values, the app activates before loading, selected-version localizations load on first entry, and the rebuilt app populated SmartClean AI metadata on first open. |
| P2 | App Info/team-switch fixes lack dedicated tests | App Info / Shell | Fixes are present and build/live verified, but future refactors can regress them. | Add ViewModel/UI tests for first-open App Info and team-switch state reset. |
| P2 | Certificate create path lacks a full ViewModel request-body unit test | Certificates | Model body tests passed, but `createCertificate` itself is not isolated with a mock API client. | Introduce injectable API client or request recorder for write ViewModel tests. |
| P2 | No in-app CSR generation | Certificates | User explicitly said the app should be able to create CSR itself. | Add CSR/key generation flow using Security/OpenSSL-compatible export guidance. |
| P2 | Build export appears missing | Builds | Repo instructions note README advertises Markdown/CSV build export but code does not include it. | Implement export or correct documentation. |
| P3 | Sidebar icon duplication | Navigation | Apps and Builds both use `ShipyardGrid`. | Use a dedicated Builds icon for recognition. |
| P3 | Existing Swift concurrency warnings | Build hygiene | Build has warnings around date formatter concurrency and `nonisolated(unsafe)` usage from previous verification. | Clean warnings after functional priorities are stable. |

## Live Scenario Matrix To Run After Unlock

Use timestamped throwaway names: `Shipyard Audit YYYYMMDD-HHMMSS`. Capture screenshots, toast text, API error copy, and cleanup outcome for every write.

### Safe Read / Navigation Scenarios

| ID | Scenario | Expected Result | Live UI Result |
| --- | --- | --- | --- |
| NAV-01 | Launch app with an existing team. | Sidebar shows active team and resources; no stale old-team data. | Pending |
| NAV-02 | Switch team from any nested screen. | Current detail/resource view resets or reloads for the new team. | Passed live from App Info: old SmartClean AI detail cleared when switching to Team 2, and Team 1 restored to its Apps list afterward. |
| NAV-03 | Open app detail, then App Info as first tab interaction. | App Info localizations/version data load on first entry. | Passed live after rebuild: SmartClean AI App Info showed App Name `SmartClean AI`, Subtitle `Cleaner`, description, promo text, URLs, and screenshot section without staying blank. |
| NAV-04 | Open Certificates, Profiles, Users, Bundle IDs, then switch team. | Each list clears/reloads with no old-team rows. | Pending |
| NAV-05 | Trigger a known failed read with insufficient-role key. | Friendly permission hint appears and failure toast shows. | Pending |

### App Submission Scenarios

| ID | Scenario | Expected Result | Live UI Result |
| --- | --- | --- | --- |
| SUB-01 | Open App Store Versions for an app with editable version. | Prepare UI shows version state, build slot, metadata requirements. | Passed live: SmartClean AI version 1.0 draft opened from App Store Versions. |
| SUB-02 | Create a new version with duplicate version string. | Server/client error is clear and form remains open. | Pending |
| SUB-03 | Create a valid new version, then select a processed build. | Build relationship saves and visible state updates. | Pending |
| SUB-04 | Enable sign-in required without demo credentials. | Submit must stay blocked after P1 fix. | Pending live; focused test passed. |
| SUB-05 | Leave phone empty while UI marks it required. | Submit gating should match label. | Fixed in code; focused test passed. |
| SUB-06 | Set scheduled release date but do not save. | Submit blocked with explicit save-required copy. | Pending |
| SUB-07 | Save review details and release settings. | Success toast appears; reload preserves saved values. | Partial: dirty-state gate verified; Mac locked during Save click, so success/failure is pending. |
| SUB-08 | Submit for review on a throwaway/non-production app version. | Review submission item is created/reused and state changes to waiting. | Pending |
| SUB-09 | Cancel submission. | State returns to editable path; toast confirms cancellation. | Pending |
| SUB-10 | Release approved version / phased release actions if available. | Production-risk confirmation appears before action. | Pending |

### Certificate And Identifier Scenarios

| ID | Scenario | Expected Result | Live UI Result |
| --- | --- | --- | --- |
| CERT-01 | Create Merchant ID `merchant.com.shipyard.audit.<ts>`. | Merchant ID row appears; success toast appears. | Pending |
| CERT-02 | Create Apple Pay certificate using generated CSR and new Merchant ID. | Request succeeds; no `merchantid` missing error; row appears. | Pending |
| CERT-03 | Open Apple Pay certificate detail. | Detail loads and shows certificate content availability. | Pending |
| CERT-04 | Download Apple Pay certificate. | Save panel appears and `.cer` saves. | Pending |
| CERT-05 | Revoke test certificate. | Confirmation appears; row is removed; profiles reload. | Pending |
| CERT-06 | Create Pass Type ID `pass.com.shipyard.audit.<ts>`. | Pass Type ID row appears; success toast appears. | Pending |
| CERT-07 | Create Pass Type certificate using generated CSR and new Pass Type ID. | Request succeeds; row appears. | Pending |
| CERT-08 | Try Apple Pay certificate without selecting Merchant ID. | Inline validation blocks request with missing Merchant ID message. | Pending |

### Bundle ID / Capability Scenarios

| ID | Scenario | Expected Result | Live UI Result |
| --- | --- | --- | --- |
| BID-01 | Create Bundle ID `com.shipyard.audit.<ts>`. | Bundle ID appears with correct platform/type. | Pending |
| BID-02 | Rename created Bundle ID. | Row updates and toast confirms. | Pending |
| BID-03 | Enable a low-risk capability on created Bundle ID. | Capability appears after refetch; toast confirms. | Pending |
| BID-04 | Disable that capability. | Capability disappears after refetch; toast confirms. | Pending |
| BID-05 | Delete unused Bundle ID. | Dependency pre-check passes and row is removed. | Pending |
| BID-06 | Attempt delete on a used Bundle ID. | Dependency sheet blocks destructive delete and links to dependencies. | Pending |

### Profile Scenarios

| ID | Scenario | Expected Result | Live UI Result |
| --- | --- | --- | --- |
| PROF-01 | Create development profile from throwaway Bundle ID, certificate, and safe existing device. | Profile row appears; success toast. | Pending |
| PROF-02 | Open profile detail. | Bundle ID/certificates/devices hydrate correctly. | Pending |
| PROF-03 | Download profile. | `.mobileprovision` saves successfully. | Pending |
| PROF-04 | Install profile for Xcode. | Profile installs and success toast appears. | Pending |
| PROF-05 | Regenerate profile. | Old profile deletion and replacement creation are clearly explained and successful. | Pending |
| PROF-06 | Delete test profile. | Row removed and related Bundle ID caches invalidate. | Pending |

### Device Scenarios

| ID | Scenario | Expected Result | Live UI Result |
| --- | --- | --- | --- |
| DEV-01 | Search/filter existing devices. | Results filter locally and do not leak into other resources. | Pending |
| DEV-02 | Rename existing safe test device. | Name updates and toast confirms. | Pending |
| DEV-03 | Disable existing safe test device. | Dependent profiles warning appears; status updates after confirm. | Pending |
| DEV-04 | Re-enable same test device. | Status updates after confirm. | Pending |
| DEV-05 | Register new device. | Only run if user accepts annual-device-limit impact. | Pending |
| DEV-06 | Import CSV with one valid and one invalid row. | Valid rows register; invalid rows show row-level errors. | Pending |

### Users / Invitations Scenarios

| ID | Scenario | Expected Result | Live UI Result |
| --- | --- | --- | --- |
| USER-01 | Invite throwaway email with limited role and one app scope. | Pending invitation appears; success toast. | Pending |
| USER-02 | Resend that invitation. | Old invite is revoked and recreated; partial failure copy is correct if recreate fails. | Pending |
| USER-03 | Revoke that invitation. | Pending invitation row disappears. | Pending |
| USER-04 | Edit a safe existing non-owner user. | Roles/scope/provisioning update; unknown roles are preserved. | Pending |
| USER-05 | Try to remove Account Holder. | App blocks removal before API call. | Pending |
| USER-06 | Remove only an explicitly approved test user. | User row disappears after confirmation. | Pending |

## Recommended Priority Plan

1. P0: Unlock Mac and run live accessibility matrix for App Submission first.
2. P1: Run live validation for fixed App Submission gating: phone, demo credentials, and unsaved/scheduled release changes.
3. P1: Run Apple Pay / Pass Type certificate live tests with generated CSR and throwaway Merchant/Pass Type IDs.
4. P1: Add safe-write guardrails for quota/destructive resources before broad live mutation testing.
5. P2: Add automated regression tests for App Info first-load, team-switch reset, and certificate create request bodies through the ViewModel layer.
6. P2: Implement in-app CSR/key generation or a guided local CSR generator.
7. P2: Decide App Groups strategy: API-backed CRUD if available, otherwise manual help/deep-link page.
8. P3: Clean navigation polish, build export documentation drift, and non-critical build warnings.

## Data Safety Notes

- Device registration can consume annual Apple device slots and cannot be deleted from this API; do not run `DEV-05` without a real test device and explicit acceptance of quota impact.
- Certificate revoke is irreversible and can invalidate profiles; only revoke certificates created during this audit.
- Profile regeneration deletes first and creates second; a create failure after delete leaves no replacement.
- Invitation resend deletes first and recreates second; a create failure after delete leaves no pending invite.
- User removal should never target the Account Holder or a real teammate during testing.
- Merchant IDs and Pass Type IDs may not have a cleanup path in this UI; use timestamped names and expect possible manual cleanup in Apple Developer Portal.
