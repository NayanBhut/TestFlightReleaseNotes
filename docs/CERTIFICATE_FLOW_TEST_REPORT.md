# Certificate Flow Test Report

**Date:** 2026-10-06
**Branch / HEAD:** `648aeaa` - feat(bundle-ids): registration, dependent profiles, capability enable/disable
**Target:** macOS, Debug
**Environment:** live App Store Connect API, real API key from Keychain
**Driver:** Accessibility-driven live UI checks, source audit for blocked/unreachable cases

> One throwaway certificate was created and then revoked during the live pass:
> `Siddharth Patel` / `Mac App Distribution` / serial `3E91ED292B5A3712E5...`.
> The three pre-existing certificates were left intact.

---

## Build & verification

```sh
plutil -lint "App Store.xcodeproj/project.pbxproj"

xcodebuild -project "App Store.xcodeproj" -scheme "App Store" -sdk macosx \
  -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
  build -skipMacroValidation

xcodebuild test -project "App Store.xcodeproj" -scheme "App Store" \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

| Check | Result |
|---|---|
| `plutil -lint` | Pass |
| CI-style debug build | Pass |
| XCTest target | Fails with 4 pre-existing validation failures: 3 CSV parser tests and `testLoadCSRMissingFile` |
| Focused certificate regression tests | Pass - relationship encoding, Merchant/Pass Type decoding, certificate detail decoding, route raw values, Identifier create bodies |

---

## Summary

| Metric | Value |
|---|---|
| Certificate scenarios covered | 20 |
| Live-pass scenarios | 14 |
| Source-audit / absence scenarios | 6 |
| Mutating operations executed | Create certificate, revoke certificate |
| Bugs fixed in this pass | 7 |
| Remaining product gaps | 3 |

---

## Scenarios tested

| # | Scenario | Endpoint / path | Result |
|---|---|---|---|
| 1 | Certificates list load | `GET /v1/certificates?limit=50&sort=displayName` | Pass - live list showed 3 active certificates, 5 columns |
| 2 | Status chip derivation | client-side | Pass for Active rows; Revoked branch is unreachable after revoke because row disappears |
| 3 | Create Certificate sheet opens | UI only | Pass - type menu, CSR block, disabled Create button observed |
| 4 | CSR guard blocks incomplete submit | client-side | Pass - Create remains disabled with no CSR |
| 5 | Duplicate certificate error | `POST /v1/certificates` | Pass - Apple 409 surfaced inline |
| 6 | Change type after server error | UI only | Bug found and fixed - stale iOS Development error is now cleared on type change |
| 7 | Create certificate | `POST /v1/certificates` | Pass - Mac App Distribution certificate created, count 3 -> 4 |
| 8 | Success step | `GET /v1/certificates/{id}` for download | Partially verified - success UI observed; native save panel not automated |
| 9 | Row context menu | UI only | Pass - Open Details, Download, and Revoke |
| 10 | Revoke confirm sheet | UI only | Pass - irreversible warning observed |
| 11 | Revoke certificate | `DELETE /v1/certificates/{id}` | Pass - throwaway row removed, count 4 -> 3 |
| 12 | Search certificates | client-side | Source-audited; matches name, serial, type, platform |
| 13 | Filter certificates by type/status | UI absence | Not implemented - no filter controls exist |
| 14 | Certificate detail view | `GET /v1/certificates/{id}` | Pass - live row tap opened detail sheet, fetched content, and showed certificate id, serial, type, status, activation, and content availability |
| 15 | Revoke impact on profiles | `DELETE /v1/certificates/{id}` then profiles refetch | Bug fixed - revoke now invalidates/refetches profiles |
| 16 | Apple Pay certificate create | `POST /v1/certificates` | Bug reproduced live - missing Merchant ID relationship; fixed with required Merchant ID field |
| 17 | Pass Type certificate create | `POST /v1/certificates` | Source + AX verified - Pass Type ID field appears and gates Create |
| 18 | Merchant IDs list/create surface | `GET /v1/merchantIds`, `POST /v1/merchantIds` | Pass - new Identifiers page loaded Merchant IDs and opened Create Merchant ID sheet |
| 19 | Pass Type IDs list/create surface | `GET /v1/passTypeIds`, `POST /v1/passTypeIds` | Pass - Identifiers page switched to Pass Type IDs and exposed Create Pass Type ID |
| 20 | App Groups support check | UI + API contract | Public App Store Connect API gap - shown as unsupported guidance instead of a fake endpoint |

---

## Bugs found and fixed

| Bug | Severity | Fix | Location |
|---|---|---|---|
| Stale create error survived a certificate type change | Medium | Clear `errorMessage` when a new type is selected | `SideBarView/Resources/ResourcesView.swift` |
| Revoking a certificate left Profiles list stale | High | Remove the `.profiles` loaded latch and refetch profiles after successful revoke | `SideBarView/Resources/ResourcesViewModel.swift` |
| Regenerate result downloaded the first profile, not the replacement | Medium | Resolve the replacement by `lastRegeneratedProfileId` before download | `Shipyard/ProfileViews.swift` |
| Certificates empty state said "No Certificates" for search misses | Low | Show "No Matching Certificates" and hide Create when a search is active | `Shipyard/CertificatesTableView.swift` |
| Apple Pay certificates could not be created | High | Apple Pay types now require `relationships.merchantId`; the form loads Merchant IDs, keeps a paste fallback, and blocks Create until an id is filled | `Model/JSONAPIModels/ResourceModels.swift`, `Model/JSONAPIModels/APIManager.swift`, `SideBarView/Resources/ResourcesView.swift`, `SideBarView/Resources/ResourcesViewModel.swift` |
| Pass Type certificates had the same missing relationship shape | High | Pass Type types now require `relationships.passTypeId`; the form loads Pass Type IDs, keeps a paste fallback, and blocks Create until an id is filled | `Model/JSONAPIModels/ResourceModels.swift`, `Model/JSONAPIModels/APIManager.swift`, `SideBarView/Resources/ResourcesView.swift`, `SideBarView/Resources/ResourcesViewModel.swift` |
| Supporting IDs had no app surface | Medium | Added an Identifiers sidebar page for listing/searching/creating Merchant IDs and Pass Type IDs; App Groups displays an unsupported public-API message | `Shipyard/ShipyardSidebar.swift`, `Shipyard/ShipyardShell.swift`, `SideBarView/Resources/ResourcesView.swift`, `SideBarView/Resources/ResourcesViewModel.swift` |
| Certificates had no detail view | Low | Added row tap and context-menu Open Details sheet backed by `GET /v1/certificates/{id}`; sheet shows the latest detail payload and certificate-content availability | `Shipyard/CertificatesTableView.swift`, `SideBarView/Resources/ResourcesViewModel.swift` |

### Profile invalidation fix

The important dependency bug was in `revokeCertificate`. A successful certificate revoke only removed the certificate row locally; `profilesState` stayed loaded, and `load(.profiles)` returned early because `.profiles` was already in `loadedKinds`. This made the list continue showing dependent profiles as Active while profile detail could show Invalid after a fresh detail fetch.

The revoke path now:

1. removes the revoked certificate row;
2. updates certificate totals;
3. removes `.profiles` from `loadedKinds`;
4. cancels any in-flight profiles load;
5. starts a fresh profiles fetch.

This keeps the list aligned with Apple's server-side invalidation instead of trusting stale local state.

---

## Remaining gaps

| Gap | Impact |
|---|---|
| Revoke has no dependent-profile impact table or type-to-confirm gate | A destructive action can be confirmed with one click/Return and does not name affected profiles |
| Certificates have no type/status filters | Operators cannot isolate expiring certificates without scanning/searching |
| Revoked status chip is effectively dead code | Apple removes revoked certs from the list and the app removes them locally, so no row can display Revoked |

---

## Not fully automated

| Scenario | Blocker |
|---|---|
| `.cer` download save panel | Native save panel requires a user-selected path |
| Pagination | Team had fewer than 50 certificates |
| API failure paths | 401/rate-limit paths were not induced against the live account |

---

## State left behind

| Item | Value |
|---|---|
| Created certificate | `Siddharth Patel` / `Mac App Distribution` / serial `3E91ED292B5A3712E5...` |
| Final certificate state | Revoked; removed from the app list |
| Certificate count | Back to 3 after revoke |
| Existing certificates | Left untouched |

No durable certificate from this pass remains active.

---

## Certificate detail regression pass

**Date:** 2026-10-06

Live accessibility verification:

1. Relaunched the freshly built `Shipyard.app`.
2. Opened Team Resources -> Certificates.
3. Clicked the first certificate row (`Created via API`).
4. Verified a `Certificate Details` sheet opened.
5. Verified the sheet displayed `Name`, `Display Name`, `Type`, `Platform`, `Serial Number`, `Expiration Date`, `Status`, `Activated`, `Certificate ID`, and `Certificate Content`.
6. Verified the detail endpoint populated certificate content availability: `Available (1956 base64 characters)`.
7. Closed the sheet.

The detail sheet uses `GET /v1/certificates/{id}` so it can validate the per-certificate payload without invoking the save panel. The `Download .cer` button remains available from the detail sheet but was not clicked in this pass to avoid opening a native save dialog.

---

## Apple Pay regression pass

**Date:** 2026-10-06

Live accessibility reproduction:

1. Opened Shipyard -> Certificates -> Create Certificate.
2. Selected `Apple Pay`.
3. Chose a CSR file.
4. Clicked Create.
5. Apple returned: `You must provide a value for the attribute 'merchantId' with this request`.

Root cause: the app mirrored the full `CertificateType` enum, but the create body only sent `attributes.csrContent` and `attributes.certificateType`. Apple's create request also supports relationships, and Apple Pay certificates require `relationships.merchantId`. Wallet Pass Type certificates similarly require `relationships.passTypeId`.

Post-fix live accessibility verification:

1. Generated a new CSR with `openssl req -new -newkey rsa:2048 -nodes`.
2. Relaunched the freshly built `Shipyard.app`.
3. Opened Certificates -> Create Certificate and selected `Apple Pay`.
4. Verified the form queried Merchant IDs; this team returned none, so the fallback resource-id field remained visible.
5. Selected `shipyard-certificate-flow.csr` in the native `NSOpenPanel`.
6. Entered `1234567890` as a fake Merchant ID resource id.
7. Submitted the form; Apple returned `There is no identifier with ID '1234567890' on this team.`

That post-fix server response confirms the app no longer sends an empty Apple Pay relationship. The prior `merchantId`-missing error was replaced by Apple's invalid-related-resource error because the test id was intentionally fake.

| Type | Required field | CSR selected, id empty | CSR + id |
|---|---|---|---|
| `Apple Pay` | `MERCHANT ID` | Create disabled | Create enabled; submitted with fake id and server reached relationship validation |
| `Pass Type Id` | `PASS TYPE ID` | Create disabled | Create enabled after id entry; field clears when switching from Apple Pay |

No post-fix create was submitted with a real Merchant ID or Pass Type ID, so no new Apple Pay or Pass Type certificate was created during this verification.
