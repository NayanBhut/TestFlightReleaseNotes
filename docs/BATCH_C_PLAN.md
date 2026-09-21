# Batch C — Handoff (DONE — build verified ✅)

Scope: read-only App Info tab (C1), Reviews tab (C3), Resources sidebar section (C2), one show/hide flag.
Status: all code implemented, all 7 new files registered in the pbxproj, `plutil -lint` OK,
`xcodebuild … BUILD SUCCEEDED`. All endpoint contracts in this doc are **verified against Apple's
OpenAPI spec** (`github.com/api-evangelist/ios`) — don't guess params.

---

## ✅ DONE (code already in the working tree)

| Area | File | Change |
|---|---|---|
| Flag | `NavigationManager.swift` | `UserDefaultsKeys.showExtendedInfo` key |
| Flag | `SideBarView.swift` | `@AppStorage` flag + eye toggle in "Apps" header + `ResourcesSectionView()` call under `appList()` (gated by flag) |
| Flag | `DetailView.swift` | `@AppStorage` flag, `visibleTabs` filter, tab-clamp `onChange`, cases `appInfo` / `reviews` wired to the new views |
| C1 | `Model/JSONAPIModels/APIModels.swift` | `AppsData.primaryLocale/contentRightsDeclaration/isOrEverWasMadeForKids`; fixed latent `descriptionData` decode bug (`@ResourceAttribute(key: "description")`); new models: `AppInfoModel`, `AgeRatingDeclarationModel`, `AppInfoLocalizationModel`, `AppCategoryModel`, `AppEncryptionDeclarationModel`; `Unit`-meta documents |
| C1 | `Model/JSONAPIModels/APIManager.swift` | APIName cases: `getAppStoreVersions`, `getReviewSubmissions`, `getDevices`, `getCertificates`, `getBundleIds`, `getProfiles`, `getUsers` (see "appInfos gotcha" below) |
| C1 | `SideBarView/DetailView/DetailViewModel.swift` | `appInfoState` / `versionLocalizationsState` / `exportComplianceState`, staleness ids, `loadAppInfo(force:)` / `retryAppInfo()`, 3 fetches, app-switch clearing, 403 hint |
| C1 | `SideBarView/DetailView/AppInfo/AppInfoView.swift` (new) | Read-only cards: General, App Store Info, App Info Localizations, Version Localizations, Export Compliance + reusable `Card` / `InfoRow` |
| C3 | `Model/JSONAPIModels/ReviewModels.swift` (new) | `CustomerReviewModel` (rel: `response`), `CustomerReviewResponseModel`, `ReviewSubmissionModel`, Meta documents |
| C3 | `SideBarView/DetailView/Reviews/ReviewsViewModel.swift` (new) | Both fetches, staleness `currentAppId`, cursor pagination + retry, 403 hint |
| C3 | `SideBarView/DetailView/Reviews/ReviewsView.swift` (new) | Submissions card + reviews card (stars/title/body/reply), Load-more, `StarRating`, `StateChip` |
| C2 | `Model/JSONAPIModels/ResourceModels.swift` (new) | `DeviceModel`, `CertificateModel`, `BundleIdModel`, `ProfileModel`, `UserModel`; all five documents use the paging `Meta` (verified: certificates response includes paging meta too) |
| C2 | `SideBarView/Resources/ResourcesViewModel.swift` (new) | `Kind` enum (apiName + verified sort param per kind), per-kind `ViewState`, staleness `loadedKinds`, dedup cursor merge, 403 hint |
| Config | `AppConfigs.swift` | `reviewLimit = 50`, `resourceLimit = 50` |

---

## ✅ DONE — everything below is implemented and building

### 1. `SideBarView/Resources/ResourcesView.swift` ✅

`ResourcesSectionView` (sidebar DisclosureGroup, opens per-kind sheet) + `ResourceListContentView`
(header, ViewState switch via `ViewStateListState` type-eraser switching on `listState.state`,
per-kind rows, Load-more footer) + `DeviceRow` / `CertificateRow` / `BundleIdRow` / `ProfileRow` /
`UserRow`. Reuses `StateChip` (ReviewsView.swift) and `ErrorRetryView` (NavigationManager.swift).

### 2. pbxproj registration ✅ (`plutil -lint` OK, build verified)

All 7 new files registered in all 4 places (PBXBuildFile, PBXFileReference, parent PBXGroup
children, PBXSourcesBuildPhase) with `B47A0010…B47A0020` IDs; new `AppInfo` + `Reviews` groups
under DetailView, new `Resources` group under SideBarView. ⚠️ Placement gotcha hit during
implementation: `PBXSourcesBuildPhase` entries must go *inside* the `files = ( … )` list (after
the last entry), NOT before the `/* End … */` marker — entries after the block's closing `};`
are outside the dict and break `plutil`.

### 3. Verify ✅

```bash
plutil -lint "App Store.xcodeproj/project.pbxproj"        # OK
xcodebuild -project "App Store.xcodeproj" -scheme "App Store" \
  -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build 2>&1 \
  | grep -E "error:|BUILD"                                 # BUILD SUCCEEDED
```

Implementation fixes worth knowing (already applied, don't revert):
- `NoMeta = JSONAPI.Unit` alias (APIModels.swift) — bare `Unit` is ambiguous
  (`Foundation.Unit` vs `JSONAPI.Unit`); used by all four `Unit`-meta documents.
- C1 stored props (`appInfoFetchTask`, staleness ids) live in the `DetailViewModel` class
  body — extensions must not contain stored properties.
- `ResourcesViewModel.merge` takes `id: KeyPath<T, String>` — the `@ResourceWrapper`
  models don't conform to `Identifiable`.
- `ResourcesViewModel.fetch` uses local `paginating` vs the `isPaginating` guard property
  (a `let` shadowed the property and failed to compile).

---

## Key gotchas (verified — don't re-litigate)

- **No `case getAppInfos = "/appInfos"`**: rawValue is a URL prefix → it would build `/v1/appInfos/{path}`, an invalid route. App-scoped routes (`/apps/{id}/appInfos`, `/apps/{id}/customerReviews`) are composed as `.get(name: .getAllApps, path: "\(appId)/appInfos")` — same precedent as `buildBetaDetail`. This is intentional, not a bug. ⚠️ Exception (Branch D correction): there is NO `/v1/apps/{id}/appEncryptionDeclarations` subpath — the relationship doesn't exist on apps (server 400s it). Export compliance is a top-level collection: `GET /v1/appEncryptionDeclarations?filter[app]={id}` via `case getAppEncryptionDeclarations = "/appEncryptionDeclarations"`.
- **`CompoundDocument<T, Meta>` requires `meta` in the response** unless `Meta == Unit` (library special-case). Small/fixed lists (appInfos, version localizations) use the `NoMeta` alias; all cursor-paginated collections — including certificates AND appEncryptionDeclarations (Branch D: `AppEncryptionDeclarationsDocument` moved `NoMeta` → paging `Meta`) — use the paging `Meta`.
- **Invalid include paths or wrong `@ResourceWrapper(type:)` fail/400 the whole document decode.** All include paths used are verified valid.
- `reviewSubmissions` collection has **no sort param**; `customerReviews` sorts only by `rating`/`createdDate` (we use `-createdDate`).
- 403 on narrow TestFlight-only keys is expected; VMs already append a permissions hint.
- `SWIFT_STRICT_CONCURRENCY = complete`: VMs are `@MainActor`, `guard !Task.isCancelled` after every await (existing pattern — keep it).

## Follow-ups (explicitly NOT this batch)
PATCH appInfo • create/revoke devices/certificates/profiles • review filters.
(POST /customerReviewResponses review replies moved INTO Branch D — see below.)

## Batch G (#10) — App Info + provisioning writes (this branch)

Implements two of the follow-ups above; endpoint contracts verified against
Apple's OpenAPI spec mirror (v4.4.1).

| Area | File | Change |
|---|---|---|
| API | `Model/JSONAPIModels/APIManager.swift` | New case `appInfoLocalizations = "/appInfoLocalizations"` (top-level route — unlike appInfos, no `/apps` prefix composition). Devices/certs reuse `getDevices`/`getCertificates` with the verb from `APIMethod` |
| API | `Model/JSONAPIModels/APIModels.swift` | `AppInfoLocalizationUpdateRequest` (+30-char limits enum); `locale` absent — immutable on update |
| API | `Model/JSONAPIModels/ResourceModels.swift` | `DeviceCreate/UpdateRequest`, `DevicePlatform` (IOS/MAC_OS/UNIVERSAL), full-enum `CertificateTypeOption`, `CertificateCreateRequest` |
| G1 | `SideBarView/DetailView/DetailViewModel.swift` | `saveAppInfoLocalization()` PATCH + in-row model update, per-id in-flight set, client validation (name 2–30, subtitle ≤30, http(s) URLs), 403 → App Manager hint |
| G1 | `SideBarView/DetailView/AppInfo/AppInfoView.swift` | `AppInfoLocalizationRow` inline editor (Edit/Save/Cancel, stays open on failure, blank = unchanged) |
| G2 | `SideBarView/Resources/ResourcesViewModel.swift` | `registerDevice` (POST), `setDeviceEnabled` (PATCH ENABLED/DISABLED — no DELETE exists on devices; website-only removal), `createCertificate` (POST), `revokeCertificate` (DELETE 204), `writeInFlight` set, 403 → Admin hint |
| G2 | `SideBarView/Resources/ResourcesView.swift` | Register/New header buttons + forms, per-row Enable/Disable, Revoke with destructive confirm alert |

Out of scope (still follow-ups): PATCH appInfo (categories), profiles create/delete,
review filters, certificate CSR generation in-app (paste-only for now).

Verify: `xcodebuild … BUILD SUCCEEDED`, no new warnings in touched files.
Live-write verification needs an App Manager/Admin key (TestFlight-only 403s):
exercise device registration with a throwaway device UDID first (yearly limit),
then App Info edits in an editable state, then cert create/revoke.

## Round 1 review (kimi-k3:cloud) — triage outcome

- FIXED: staleness ids recorded only on success (stuck-error auto-retry) • certificates paginate with real totals (was silently truncated >50) • `ReviewsViewModel.resetForTeamSwitch()` on deselection (cross-team staleness/cursor races) • App Info Refresh `||` • tab clamp independent of the picker • parallel App Info fetches (`async let`) • `ForEach` identity by `id` not offset • per-kind pagination-failure/in-flight flags • `StateChip` green for ENABLED/ACTIVE/VALID • `StarRating` collapsed VoiceOver element • `deinit` task cancellation in all 3 VMs • dead `force` params removed • CI comment decoupled from this doc • misnamed `emailFallback` extension inlined.
- DEFERRED: unify `emptyState`/ViewState renderers across views (pure refactor) • eye-toggle placement (design choice; flag semantics intentional).
- Not adopted: deleting this doc — kept deliberately as the batch record; CI no longer references it.

## Branch D — review replies + endpoint corrections (this PR)

| Area | File | Change |
|---|---|---|
| Fix | `Model/JSONAPIModels/APIManager.swift` | New cases: `getAppEncryptionDeclarations` (`/appEncryptionDeclarations`, top-level + `filter[app]`) and `postCustomerReviewResponse` (`/customerReviews`, POST `\(reviewId)/customerReviewResponses`) |
| Fix | `Model/JSONAPIModels/APIModels.swift` | `AppEncryptionDeclarationsDocument`: `NoMeta` → paging `Meta` |
| Fix | `SideBarView/DetailView/DetailViewModel.swift` | `fetchExportCompliance` now `GET /v1/appEncryptionDeclarations?filter[app]={id}&limit=200` |
| C3 | `Model/JSONAPIModels/ReviewModels.swift` | `ReviewSubmissionModel` gains `appStoreVersion` + `submittedByActor` relationships; new `ActorModel` (type `actors`, `displayName` with email fallback) |
| C3 | `SideBarView/DetailView/Reviews/ReviewsViewModel.swift` | `fetchSubmissions` requests `include=submittedByActor`; new `replyToReview(reviewId:responseBody:)` POST with in-row response update on success (composer stays open on failure). NOTE: list endpoint rejects `appStoreVersion` include, so that relationship stays nil on list rows |
| C3 | `SideBarView/DetailView/Reviews/ReviewsView.swift` | Submission rows show version (when present) + submitter; review rows gain `ReplySection` composer (Reply → TextField → Cancel/Send, Send disabled while empty) |
| CI | `.github/workflows/md-comment.yml` | **Removed** — PR body now comes from `.github/PULL_REQUEST_TEMPLATE.md`; Build + Ollama review workflows unchanged |

Verify: `plutil -lint` OK, `xcodebuild … BUILD SUCCEEDED`.

## Round 2 review (kimi-k3:cloud) — triage outcome

- FIXED: per-list success-only staleness in ReviewsViewModel (`reviewsLoadedAppId`/`submissionsLoadedAppId` — failed loads auto-retry on next appear) • in-flight guard moved BEFORE the cancel in all `loadMore*` (double-tap no longer kills the running page request and no-ops) • Reviews reset hoisted to DetailView level (installed on every tab, not just Reviews) • age rating explicit mapping (`FOUR_PLUS` → "4+") • per-section App Info fetch tasks + per-section Retry buttons (a failing section no longer drags the other two) • fractional-seconds date fallback for expiry parsing • `Card` renamed to scoped `InfoCard` • `StateChip` pending states use `.orange` (yellow-on-yellow contrast) • dead `submissionsMeta` removed • `@AppStorage` properties made `private`.
- MOVED: this doc from repo root to `docs/` (process record, out of the way of project docs).
- DEFERRED (unchanged): unify the empty/loading/error renderers across views — pure refactor, tracked follow-up.
