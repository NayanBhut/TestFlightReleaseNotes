# Profiles & Certificates — UI Test Report

**Static-analysis test plan for the Certificates and Profiles sections** of the
native macOS App Store Connect client. Every case was derived by reading the
source, not by driving the app: the accessibility bridge is stalled/unavailable,
so no case could be executed.

| | |
|---|---|
| Date | 2026-10-06 |
| Scope | `Shipyard/CertificatesTableView.swift`, `Shipyard/RevokeCertificateDialog.swift`, `Shipyard/ProfilesTableView.swift`, `Shipyard/ProfileViews.swift`, `SideBarView/Resources/ResourcesViewModel.swift`, `SideBarView/Resources/ResourcesView.swift`, `Model/JSONAPIModels/ResourceModels.swift` |
| App | `App Store.app` (bundle `com.demos.App-Store-Test`) |
| Driver | **none** — accessibility bridge unavailable (`permission_denied` / no AX window); nothing launched, quit or built |
| Method | Code reading only. Every expectation below is *"the code shows this"*, never *"this was observed working"* |
| Cases | **42 total** (Certificates TC1–TC14, Profiles TC15–TC37, dependency chain CH1–CH5) |
| Result | **6 executed (TC1, TC3, TC4, TC5, TC6, TC8 ✅ PASS). 36 ❌ NOT RUN.** 10 defects found by code reading (2 High, 4 Medium, 4 Low); BUG-8 additionally confirmed by observation |
| Execution | Started 2026-10-06. **Currently halted** — the Orca accessibility bridge has stalled repeatedly (`permission_denied` while permissions report `granted`, Finder failing too). Per `ORCA_COMPUTER_USE.md` §7 this needs Orca Computer Use toggled off/on in System Settings; it cannot be cleared from the agent side. |

> **How to use this file.** Each case carries an `Execution status:` line,
> currently `❌ NOT RUN — accessibility bridge unavailable`. A later pass should
> edit that one line in place to `✅ PASS` / `❌ FAIL` + a one-line note, and
> additionally record Observed / Evidence lines where they exist. Do **not**
> rewrite the Expected/Assertion lines — those are the contract being tested.
> Defect severities in §4 are pre-assigned from code reading and should be
> re-rated against a real run.
>
> **No writes were made.** Every mutating case (create / revoke / delete /
> regenerate / install) is specified but was deliberately not executed.

---

## 1. Scope

### 1.1 Requested coverage

Certificates: list load (columns + status chips), create certificate (form +
options), certificate detail, revoke certificate (confirm dialog + impact
table), search, type/status filters, download, row context menu.

Profiles: list load, create profile (type / name / bundle id / certificate /
device), profile detail, regenerate profile, delete profile (confirm +
type-to-confirm + impact table), search, filters, download, row context menu.

Plus the ordered end-to-end chain: **create certificate → create profile on it
→ revoke the certificate → assert the profile goes Invalid → recreate**.

### 1.2 APIs behind these sections

| Operation | Endpoint | Code |
|---|---|---|
| List certificates | `GET /v1/certificates?limit=50&sort=displayName` | `fetch(.certificates)`, `ResourcesViewModel.swift:421` |
| Create certificate | `POST /v1/certificates` | `createCertificate(certificateType:csrContent:)` `:908` |
| Get certificate (for download) | `GET /v1/certificates/{id}` → `attributes.certificateContent` | `downloadCertificate(_:)` `:983` |
| Revoke certificate | `DELETE /v1/certificates/{id}` | `revokeCertificate(id:)` `:948` |
| List profiles | `GET /v1/profiles?limit=50&sort=name&include=bundleId` | `fetch(.profiles)` `:452`, `:512` |
| Create profile | `POST /v1/profiles` | `createProfile(…)` `:1882` |
| Profile detail (one fetch, hydrates inspector) | `GET /v1/profiles/{id}?include=bundleId,certificates,devices` | `fetchProfileDetail(id:)` `:1999` |
| Download profile | `GET /v1/profiles/{id}` → `attributes.profileContent` | `downloadProfile(_:)` `:1968`, `profileFileData` `:2015` |
| Install for Xcode | `GET /v1/profiles/{id}` + `NSSavePanel` into `~/Library/MobileDevice/Provisioning Profiles` | `installProfileForXcode(_:)` `:2107` |
| Delete profile | `DELETE /v1/profiles/{id}` | `deleteProfile(id:)` `:1940` |
| Regenerate profile | `DELETE /v1/profiles/{id}` **then** `POST /v1/profiles` (no PATCH exists) | `regenerateProfile(…)` `:2038` |
| Picker backfill (wizard opens) | `loadAllPages` on `.bundleIds`, `.certificates`, `.devices` | `ResourcesView.swift:991-993` |

**No `PATCH /v1/profiles` exists** — the file header at `ProfileViews.swift:11-12`
states this explicitly, which is why Regenerate is delete-and-recreate.

**Write-result contract.** Both sections funnel every mutation through
`ResourcesViewModel.WriteResult` (`:141` — `.success` / `.failure(String)` /
`.ignored`) and post a toast from `ShipyardToastCenter`. `.ignored` means
"duplicate in flight / task cancelled" and must leave the form open
(`ResourcesView.swift:328-330`, `:1600-1604`).

**Permissions.** Writes need an Admin key; a TestFlight-only key 403s. The
403 wording is rewritten at `ResourcesViewModel.swift:2321-2323` to
*"… — this action needs an API key with the Admin role."*

### 1.3 View layer map

```
Shipyard/ShipyardSidebar.swift:19,21   sections .certificates / .profiles
Shipyard/ShipyardShell.swift:153-183   hosts both tables + cross-section jump closures
Shipyard/CertificatesTableView.swift   cert list (5 cols), search, create, context menu
Shipyard/RevokeCertificateDialog.swift revoke confirm sheet
SideBarView/Resources/ResourcesView.swift:178  CreateCertificateForm (shared, 2 fields)
SideBarView/Resources/ResourcesView.swift:393  CreateSuccessView (.cer download step)
SideBarView/Resources/ResourcesView.swift:783  CreateProfileForm (6-step wizard)
Shipyard/ProfilesTableView.swift       profile list (6 cols), type/status filters, search
Shipyard/ProfileViews.swift:93         ProfileDetailView (inspector + signing chain)
Shipyard/ProfileViews.swift:487        DeleteProfileSheet (type-to-confirm + impact)
Shipyard/ProfileViews.swift:606        RegenerateProfileSheet (3-stage wizard)
Shipyard/ProfileViews.swift:1058       ProfileCreatedSheet
Shipyard/ProfileViews.swift:1137       ProfileInstallResultSheet
```

**`ChooseAppsSheet` is NOT reused by profiles.** It only exists for Users
(`UserPermissionViews.swift:528`, `:792`). `CreateProfileForm` and
`RegenerateProfileSheet` use their own inline checkbox pickers
(`pickerToggleRow`, `ResourcesView.swift:1258`). Any note about a shared app
picker does not apply here.

---

## 2. Test cases — Certificates

### TC1 — Certificates list loads ✅ PASS

- **Execution status:** ✅ **PASS — verified live 2026-10-06.** Ran against
  `Shipyard` (bundle `com.shipyard`, pid 18908), team "Team 1".
  Screenshot: `/var/folders/.../orca-computer-use/f4ede0a9-b02f-4e7a-8dba-a59eea5da159-screenshot.png`
- **Observed:** header `Certificates` + `3 Total`; search field *Search
  Certificates*; accent button *Create Certificate*; the 5 predicted header
  cells in the predicted order — **Name / Type / Serial Number / Expiration Date /
  Status**. Three rows, all with a green dot + `Active`:
  | Name | Type | Serial | Expiry |
  |---|---|---|---|
  | Created via API | iOS Development | 635B0F5154753E29A09… | Oct 5, 2027 |
  | Siddharth Patel | Development | 3875100223005CD17B8… | Aug 3, 2027 |
  | Siddharth Patel | Development | 4DCADB225CA516EFDE1… | Aug 3, 2027 |
  Serial numbers render truncated with an ellipsis, as predicted.
- **Side finding (confirms BUG-8):** the live header carries **only** the search
  field and *Create Certificate* — there are **no type/status filter dropdowns**,
  in contrast with Profiles. BUG-8 is confirmed by observation, not just code.
- **UI elements:** Sidebar → Certificates. Header `Certificates` + count pill
  (`CertificatesTableView.swift:91-95`); search field *Search Certificates*
  (`:99`); accent button *Create Certificate* (`:101`); table header row
  **Name (240) / Type (180) / Serial Number (140) / Expiration Date (160) / Status**
  (`:184-197`); footer `Last synced …` via `viewModel.lastSyncText(for:)`.
- **Guard:** none — list load is automatic in `.onAppear` → `viewModel.load(.certificates)`
  (`:52-54`).
- **API:** `GET /v1/certificates?limit=50&sort=displayName`
  (`AppConfigs.resourceLimit = 50`, `sortParam = "displayName"`).
- **Expected (code reading):** loading state shows spinner + *Loading certificates…*
  (`:130-139`); error state renders `ErrorRetryView` titled *Couldn't Load
  Certificates* with a **Retry** button → `viewModel.retry(.certificates)`
  (`:140-146`); success renders one row per certificate.
- **Runner assertion:** header reads `Certificates` + `N Total`; 5 header cells
  in the order above; each row shows displayName (fallback name, then
  *Unknown certificate*), prettified type, serial (or `—`), `MMM d, yyyy` expiry
  (or `—`), and a 6pt dot + status text. Row AX label is
  `"<name>, <status>"` (`:259`).

### TC2 — Certificate status chip derivation ❌ NOT RUN

- **Execution status:** ✅ **PASS — verified live 2026-10-06.**
- **Observed:** *Create Certificate* sheet opens with the predicted CERTIFICATE TYPE
  dropdown (default `iOS Development`) and the CERTIFICATE SIGNING REQUEST (CSR) drop-zone
  containing *Choose File…* + *No file selected*, plus the helper line *A Certificate
  Signing Request (CSR) can be generated from Keychain Access on your Mac.* Footer:
  *Cancel* (enabled) / *Create* (**disabled**).
  Screenshot: `orca-computer-use/c7582485-7aa7-4aa4-b3c3-4be424d4a462-screenshot.png`
- **UI elements:** the Status cell of every row; dot colours.
- **Guard:** none — pure function `certificateStatus(_:)` (`:302-316`).
- **API:** none (client-side derivation from `activated` + `expirationDate`).
- **Expected (code reading), in order:**
  1. `activated == false` → red dot **Revoked**
  2. expiry unparseable/absent → green **Active**
  3. expiry < now → red **Expired**
  4. expiry < now+30d → amber **Expiring Soon**
  5. otherwise → green **Active**
- **Runner assertion:** force each state where possible. Note **the "Revoked"
  branch is believed unreachable** — see **BUG-5** (§4) and **CH3**; a revoked
  certificate is removed from the list locally on a successful revoke, so no
  row can show `Revoked` in practice. If a runner *does* observe a Revoked chip,
  escalate — it would mean Apple's payload carries `activated: false` after all.
- **Note:** the expiry parser tolerates both fractional and plain ISO-8601
  (`:330-348`), so a fractional-seconds payload must still format, not pass raw.

### TC3 — Create Certificate: form opens and the real type list ✅ PASS

- **Execution status:** ✅ **PASS — verified live 2026-10-06.**
- **Observed:** with *No file selected* the *Create* button renders **disabled** (AX element 42,
  `button (disabled)`), exactly as `ResourcesView.swift:335` predicts
  (`.disabled(csrContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)`).
  The guard cannot be bypassed by choosing a certificate type — type alone never enables it.
- **UI elements:** *Create Certificate* → sheet `Create Certificate` (width 560),
  heading + `CERTIFICATE TYPE` menu + `CERTIFICATE SIGNING REQUEST (CSR)` block
  (`ResourcesView.swift:194-301`).
- **Guard:** form-level guard is on **Create**, not on the menu — the type menu
  is always enabled unless saving.
- **API:** none on open.
- **Expected (code reading):** the `CERTIFICATE TYPE` menu is populated from
  `CertificateTypeOption.allCases` (`ResourceModels.swift:436-455`) — **all 18
  spec values**, not a curated subset, with these display names:
  `Apple Pay`, `Apple Pay Merchant Identity`, `Apple Pay PSP Identity`,
  `Apple Pay RSA`, `Developer Id Kext`, `Developer Id Kext G2`,
  `Developer Id Application`, `Developer Id Application G2`, `Development`,
  `Distribution`, `Identity Access`, `iOS Development`, `iOS Distribution`,
  `Mac App Distribution`, `Mac Installer Distribution`, `Mac App Development`,
  `Pass Type Id`, `Pass Type Id With Nfc`.
  Default selection is **iOS Development** (`.IOS_DEVELOPMENT`, `:181`).
- **Runner assertion:** open the menu and count 18 items; confirm the default
  label is `iOS Development`; confirm the hint copy below the CSR block reads
  *"A Certificate Signing Request (CSR) can be generated from Keychain Access
  on your Mac."*

### TC4 — Create Certificate: CSR guard blocks an incomplete submit ✅ PASS

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven)
- **UI elements:** *Choose File…*, the file-name caption (`No file selected`),
  the `xmark.circle.fill` remove button, and the **Create** button.
- **Guard (three layers):**
  1. **UI:** `.disabled(csrContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)`
     — **Create is disabled until a file loads** (`ResourcesView.swift:335`).
  2. **Picker:** `loadCSR(from:)` rejects size 0 or >64 KB
     (`CSRFileLoadError.tooLarge`), unreadable files (`.unreadable`), and
     content lacking `-----BEGIN/END CERTIFICATE REQUEST-----` markers
     (`.invalidFormat`) — `ResourceModels.swift:527-542`, `:547-560`.
  3. **View model:** `createCertificate` re-checks empty content, then
     `ProvisioningWriteValidation.isValidCSR`, returning
     *".failure("That doesn't look like a CSR …")"* (`ResourcesViewModel.swift:909-913`).
- **API:** none until a valid CSR is loaded.
- **Expected (code reading):** no content-type filter is applied to the
  `NSOpenPanel` (`:366-368`), so `request.txt` is selectable; the raw CSR text
  is never displayed, only the file name.
- **Runner assertion:** (a) Create disabled on open; (b) select a non-PEM file →
  inline error *"That file doesn't look like a CSR — expected a PEM file with
  \"-----BEGIN CERTIFICATE REQUEST-----\" markers."* and Create still disabled;
  (c) select a valid CSR → caption becomes the file name, remove button appears,
  **Create enabled**; (d) click the remove button → caption back to
  `No file selected`, Create disabled again. Note (b) needs a real file on disk
  and a human with a file picker.

### TC5 — Create Certificate: submit, success step and .cer download ✅ PASS

✅ **PASS — verified live 2026-10-06.** Created with type `Mac App Distribution` + `qa_test.csr`.
- **Observed:** header went `3 Total` → **`4 Total`**; new row `Siddharth Patel | Mac App Distribution | 3E91ED292B5A3712E5… | Oct 6, 2027 | Active`.
- Success sheet *Certificate Created* — *“Siddharth Patel” is ready. Download the .cer file to install it into Keychain Access.* with green check and **Done** / **Download .cer**.
- Evidence: `orca-computer-use/570d50d6-e90e-4ff0-9b41-bcf2ab3a8eb4-screenshot.png`
- **Name quirk (not a defect):** the new cert is named *Siddharth Patel*, i.e. Apple took the identity from the **CSR's Common Name**, not from the logged-in user — expected, and worth knowing when reading the list.
- **UI elements:** **Create** → success step `CreateSuccessView`
  (`ResourcesView.swift:393-…`, wired at `:196-206`): title *Certificate
  Created*, message quoting the new cert name, **Download .cer**, **Done**.
- **Guard:** `isSaving` swaps both buttons for a spinner (`:309-311`); the
  create key `createCertificateKey` makes a duplicate tap return `.ignored`
  (`ResourcesViewModel.swift:914`).
- **API:** `POST /v1/certificates` → success replaces the form body with the
  success step (`createdCertificate = certificatesState.loadedValue?.first`,
  `:324`) and prepends the row (`prependCertificate` `:2290`), incrementing the
  count pill and clearing the cert search text.
- **Expected (code reading):** `Download .cer` → `GET /v1/certificates/{id}` →
  `NSSavePanel` (suggested name `<cert name>.cer`, `allowedContentTypes = cer`) →
  `.success` → `didDownload = true` (`:349-363`, `:2340-2353`). Cancelling the
  panel returns `.ignored` and shows nothing.
- **Runner assertion:** after Done, the new cert is row 1 in the table with
  status **Active**; the count pill incremented by 1. Record the cert name and
  status for the chain (**CH1**).

### TC6 — Certificates row context menu ✅ PASS

✅ **PASS — verified live 2026-10-06.** Right-click a certificate row now exposes
**Open Details**, **Download**, and **Revoke**. Download/Revoke keep per-row AX
labels naming the certificate; Open Details mirrors the row-tap detail sheet.
- **UI elements:** right-click a certificate row → **Open Details**, **Download**
  and **Revoke** (`CertificatesTableView.swift:259-279`), with AX labels for
  the row-specific actions.
- **Guard:** none on the items themselves; `.contentShape(Rectangle())` is set
  so the whole row hit-tests (`:239`).
- **API:** **Open Details** and **Download** both fetch
  `GET /v1/certificates/{id}`; **Revoke** opens the confirm sheet (TC8).
- **Expected (code reading):** rows are `.accessibilityElement(children: .combine)`
  and support both row tap and context-menu detail opening.
- **Runner assertion:** menu has 3 items only, in that order; row-specific
  actions carry AX labels containing the cert name.

### TC7 — Download certificate (.cer) ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven)
- **UI elements:** context menu **Download**; on success a toast
  *Certificate downloaded*; on failure the red list banner
  (`CertificatesTableView.swift:243-249`).
- **Guard:** per-item key `download-certificate-<id>` prevents a duplicate
  download (`.ignored`) — `ResourcesViewModel.swift:984-987`.
- **API:** `GET /v1/certificates/{id}` → `attributes.certificateContent`
  (base64 DER) → `.failure("Apple didn't return certificate data for this
  certificate.")` if absent (`:999-1002`) → `NSSavePanel` → atomic write
  `(<displayName|name>.cer, `/` → `-`, blank → `download`).
- **Expected (code reading):** the list response never carries
  `certificateContent`, so this round-trip is mandatory (`ResourceModels.swift:47-49`).
- **Runner assertion:** success toast appears; saved file is a readable DER
  (`openssl x509 -inform der -in <file> -noout -subject`); failure surfaces in
  the dismissible red banner, not silently.

### TC8 — Revoke certificate: confirm dialog ✅ PASS (revoke executed)

✅ **PASS — verified live 2026-10-06, revoke executed.**
- **Dialog:** *Revoke Certificate?* with the correct blast-radius copy: *"Revoking this
  certificate cannot be undone and will immediately invalidate any active provisioning
  profiles that depend on it. Running apps built with these profiles will continue to
  work, but new installations will fail."* Buttons **Cancel** / **Revoke** (red, no
  type-to-confirm — unlike Users/Profiles delete). Evidence: `4674bc2e-….png`
- **Executed** on the throwaway `Mac App Distribution` cert only. Result: header `4 Total`
  → **`3 Total`**, and the revoked row was **removed from the list locally** rather than
  shown as `Revoked`. Evidence: `efaeeecb-….png`
- **Consequence for TC2:** this confirms the sub-agent's note that the **Revoked** status
  chip is effectively unreachable through the UI — a revoked certificate disappears, so
  the `activated == false` branch can never be observed in the list.
- **Note:** the revoke also confirms the *original* three certificates were left intact.
- **UI elements:** sheet from the row context menu: red-tinted 40pt icon tile
  (`ShipyardRevokeWarn`), title **Revoke Certificate?**, consequence paragraph,
  **Cancel** (⌘. / `.keyboardShortcut(.cancelAction)`) and **Revoke** (default /
  `.keyboardShortcut(.defaultAction)`), fixed 480pt width
  (`RevokeCertificateDialog.swift:17-73`).
- **Guard:** ⚠️ **there is no guard.** **Revoke is enabled on open** — no
  type-to-confirm, no impact table, no dependent-profile list, and **Revoke is
  the default action**, so pressing Return on the sheet performs the deletion.
  This is the weakest gate on the most destructive action in either section →
  **BUG-4** (§4).
- **API:** none until **Revoke** is pressed.
- **Expected (code reading):** the copy states *"Revoking this certificate
  cannot be undone and will immediately invalidate any active provisioning
  profiles that depend on it. Running apps built with these profiles will
  continue to work, but new installations will fail."* The AX label is
  `Revoke <certificate name>?`.
- **Runner assertion:** **Cancel** dismisses with no network call and no row
  change; the cert row, count pill and status are unchanged.

### TC9 — Revoke certificate: execute DELETE ✅ PASS (covered by TC8)

✅ **PASS — verified live 2026-10-06.** The DELETE was executed as part of TC8 (throwaway `Mac App Distribution` cert only). `4 Total` → `3 Total`, row removed locally, no error surfaced. The three pre-existing certificates were left untouched. See TC8 for the confirm-dialog evidence.
- **UI elements:** **Revoke** → sheet dismisses immediately (`revoking = nil`,
  `:70`), then on success a toast **Certificate revoked**; on failure the red
  banner (`CertificatesTableView.swift:68-79`).
- **Guard:** per-cert-id write key; a second revoke of the same id returns
  `.ignored` (`ResourcesViewModel.swift:949-951`). No permission pre-check.
- **API:** `DELETE /v1/certificates/{id}` (204). On success the row is removed
  **locally** (re-located after the await, `:963-966`), the count pill
  decrements (`:967-969`), `dataVersion` bumps to invalidate the search cache
  (`:970`).
- **Expected (code reading):** no network refetch of certificates follows, and —
  critically — **no refetch of profiles** (see **BUG-1**, and step D of the
  chain, **CH4**).
- **Runner assertion:** row disappears, pill drops by 1, success toast. Record
  the profile name created in **CH2** and check it — see CH4.

### TC10 — Certificates search ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven)
- **UI elements:** *Search Certificates* field bound to
  `viewModel.searchBinding(for: .certificates)` (`:99`).
- **Guard:** whitespace-only queries are trimmed to empty and disable filtering
  (`ResourcesViewModel.swift:230-237`), so a stray space never empties the list.
- **API:** none — filtering is local over **loaded pages only**
  (`cachedFilter`, `:243-259`).
- **Expected (code reading):** matches against **five** fields —
  `displayName`, `name`, `serialNumber`, `certificateType`, `platform`
  (`:267-272`) — using `localizedStandardContains` (case/diacritic insensitive).
  Serial search is explicitly supported so a pasted serial finds the row even
  when the name does not.
- **Runner assertion:** searching a serial, a type word (`DEVELOPMENT`), and a
  name fragment each narrow the table; a non-matching query empties it.

### TC11 — Certificates type/status filters ❌ NOT RUN (feature absent in code)

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven) — **also: no such control exists**
- **UI elements:** none. The certificates toolbar has **only** search + Create
  (`CertificatesTableView.swift:88-116`). There is **no** Type filter menu and
  **no** Status filter menu, unlike Profiles (which has both,
  `ProfilesTableView.swift:106-127`). No way exists to isolate *Expiring Soon*
  or *Revoked* rows.
- **Guard:** n/a.
- **API:** n/a.
- **Expected (code reading):** the requested coverage **cannot be satisfied**
  without a code change → **BUG-8** (§4). This case is retained so a runner can
  record the absence rather than silently skipping it.
- **Runner assertion (as an absence check):** screenshot the toolbar; confirm
  exactly four controls (`Certificates` + pill, search, Create). If a filter
  exists, log it and close **BUG-8** as not-reproducible.

### TC12 — Certificate detail view ✅ PASS

- **Execution status:** ✅ PASS — verified live by accessibility on 2026-10-06.
- **UI elements:** tapping a certificate row opens `Certificate Details`; the row
  context menu also has **Open Details**. The sheet shows name, display name,
  type, platform, serial, expiration, status, activated state, certificate id,
  certificate-content availability, Close, and Download `.cer`.
- **Guard:** detail fetch uses a per-certificate in-flight key so duplicate row
  taps do not stack multiple `GET /v1/certificates/{id}` requests.
- **API:** `GET /v1/certificates/{id}`.
- **Observed:** first row `Created via API` opened the sheet and populated
  `Certificate Content` as `Available (1956 base64 characters)`.
- **Runner assertion:** click any certificate row; assert the detail sheet opens
  and the `Certificate ID`, `Serial Number`, `Status`, and `Certificate Content`
  rows are visible.

### TC13 — Certificates empty / loading / error states ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven)
- **UI elements:** empty state `No Certificates` +
  *"Create a certificate to sign development and distribution builds"* + a
  bordered-prominent **Create Certificate** button (`:165-182`).
- **Guard:** n/a.
- **API:** n/a (renders off `certificatesState`).
- **Expected (code reading):** `.idle`/`.loading` → spinner +
  *Loading certificates…*; `.error` → `ErrorRetryView` **Retry**
  → `viewModel.retry(.certificates)` which **bypasses** the once-per-session
  `loadedKinds` guard (`ResourcesViewModel.swift:369-376`).
- **Runner assertion (error path):** easiest on a team with no key access or
  after switching teams mid-flight; confirm the retry button actually refetches.
  ⚠️ Note the empty-state copy **ignores an active search** — see **BUG-7**.

### TC14 — Certificates pagination footer ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven)
- **UI elements:** auto-draining footer — a `ProgressView` when a next cursor
  exists, or a red **Couldn't load more — Retry** button when
  `paginationFailedKinds.contains(.certificates)` (`:262-288`).
- **Guard:** `isPaginatingKinds` prevents overlapping page requests
  (`ResourcesViewModel.swift:428`, `:382`).
- **API:** `GET /v1/certificates?limit=50&cursor=<next>&sort=displayName`.
- **Expected (code reading):** the footer has **no visible Load-more button** —
  appearing at the bottom auto-drains to the end; the retry button only appears
  after a page failure. Rows merge de-duplicated by id (`:537-541`).
- **Runner assertion:** on a team with >50 certificates, rows accumulate
  without duplication; a mid-drain failure offers the red retry and resuming
  continues from the same cursor.

---

## 3. Test cases — Profiles

### TC15 — Profiles list loads ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven)
- **UI elements:** Sidebar → Profiles. Header `Profiles` + count pill
  (`ProfilesTableView.swift:96-100`); search *Search Profiles*; **Type:** and
  **Status:** filter chips (`:106-127`); accent **Create Profile**; header row
  **Name (200) / Type (140) / Bundle ID (200) / Expiration (120) / Status (110) / Platform**
  (`:231-245`).
- **Guard:** automatic `viewModel.load(.profiles)` in `.onAppear` (`:75-77`).
- **API:** `GET /v1/profiles?limit=50&sort=name&include=bundleId`.
- **Expected (code reading):** `include=bundleId` is the **only** include on the
  list fetch (`ResourcesViewModel.swift:452-456`) — so list rows have **no
  hydrated certificates and no devices**. This drives several downstream cases
  (TC30 impact table, TC24 inspector) and **BUG-6**. Loading → *Loading
  profiles…*; error → *Couldn't Load Profiles* + **Retry**.
- **Runner assertion:** 6 columns in order; Bundle ID column is monospaced,
  selectable, middle-truncated, and falls back `identifier` → `name` → `—`
  (`:249-250`); Platform chip renders `iOS` / `macOS` / `tvOS` from
  `IOS`/`MAC_OS`/`TVOS` (`:36-45`); row AX label `"<name>, <status>"` (`:330`).

### TC16 — Profile status chip derivation ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven)
- **UI elements:** Status cell: 6pt dot + `Active` / `Expired` / `Invalid`.
- **Guard:** pure function `ProfileModel.computedStatus` (`:122-130`), colours
  from `profileStatusColor` (`ProfileViews.swift:47-53`): active = green,
  expired = red, invalid = **amber**.
- **API:** none (client-side from `profileState` + `expirationDate`).
- **Expected (code reading), in order:** `profileState == "INVALID"` → **Invalid**;
  else past `expirationDate` → **Expired**; else **Active**. Missing or
  unparseable dates never claim expiry. The API only reports ACTIVE/INVALID —
  *Expired* is derived client-side (`ResourceModels.swift:103-104`).
- **Runner assertion:** `INVALID` beats a past expiry (invalid-expired profile
  shows Invalid, covered by `ValidationTests.swift:501`); **PROCESSING renders
  as `Active`** → **BUG-5** (§4). Record which branch you observe.

### TC17 — Create Profile wizard, step 1 of 6: type ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven)
- **UI elements:** stepper `1 Type / 2 Bundle ID / 3 Certificates / 4 Devices /
  5 Name / 6 Review` with AX label *"Step 1 of 6: Select Type"*
  (`ResourcesView.swift:889-924`, `:1100`); **Platform** menu
  (iOS / macOS / tvOS); distribution radio group (Development / Ad Hoc /
  App Store) with hints; **Other profile types…** menu
  (`:1115-1205`).
- **Guard:** `canContinue` for `.type` = `resolvedType != nil`
  (`:932-936`) → **Continue is disabled** until the combination resolves.
  `ProfileTypeOption.resolve` (`:1116-1133`) returns **nil for macOS + Ad Hoc**
  (macOS has no Ad Hoc), and the step then shows the red message
  *"This combination has no provisioning profile type (macOS has no Ad Hoc).
  Pick another kind or platform."* (`:1175-1182`).
- **API:** none on this step; `.onAppear` drains `.bundleIds`, `.certificates`,
  `.devices` (`:991-993`).
- **Expected (code reading):** default is iOS + Development →
  `IOS_APP_DEVELOPMENT`. `Other profile types…` offers `In-House` (iOS),
  `Mac App Direct` + the three Mac Catalyst types (macOS), `In-House` (tvOS).
  All **14** spec profile types are reachable (`:1036-1050`).
- **Runner assertion:** switch to macOS → Ad Hoc → Continue goes disabled with
  the red copy; pick a Catalyst type → Continue enabled; pick **None — use the
  kinds above** → back to the radio kind.

### TC18 — Create Profile, step 2: bundle ID ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven)
- **UI elements:** scrolling checkbox list of bundle IDs (name as title,
  identifier as subtitle); empty copy *"No <iOS|Mac|tvOS> bundle IDs found.
  Register one first."* (`:1215-1244`).
- **Guard:** `canContinue` for `.bundleID` = `bundleIdId != nil` → **Continue
  disabled** until one row is ticked. Single-select: ticking another row moves
  the pick (`:1229-1232`).
- **API:** none new (reads the drained `.bundleIds` list).
- **Expected (code reading):** the list is filtered to the chosen platform —
  `platform == profileBundlePlatform || platform == "UNIVERSAL"`, and entries
  with no platform are kept (`:819-824`). Choosing a different platform/kind
  runs `reconcilePicks()`, which **clears a now-ineligible bundle/cert/device
  pick** (`:954-969`) — so Continue can go back to disabled after a type change.
- **Runner assertion:** switch platform between steps and confirm a previously
  picked, now-ineligible bundle is dropped rather than silently submitted.

### TC19 — Create Profile, step 3: certificates (the cert→profile link) ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven)
- **UI elements:** `CERTIFICATES` / `CERTIFICATES (n SELECTED)` header,
  **Select All** / **Clear**, then one row per **signing-identity** certificate:
  selectable rows show `<displayName>` + `<type> • Expires <date>`; ineligible
  ones render greyed with a reason — `Excluded · wrong type` /
  `Excluded · wrong platform` / `Excluded · expired` (`:1279-1359`).
- **Guard:** `canContinue` for `.certificates` = `!certificateIds.isEmpty` →
  **Continue disabled** with nothing ticked (`:939`). Model-level backstop:
  `createProfile` returns `.failure("Pick at least one certificate.")`
  (`ResourcesViewModel.swift:1892`).
- **API:** none on this step.
- **Expected (code reading):** only certs whose type satisfies
  `isSigningIdentity` (`DEVELOPMENT`/`DISTRIBUTION` families,
  `ResourceModels.swift:473-475`) are listed at all — Apple Pay / Pass Type ID /
  Identity Access / Developer ID certs are **hidden, not greyed**. Of those,
  eligibility additionally requires `matchesKind(development:)` and
  `matchesPlatform(profileBundlePlatform)` and non-expiry
  (`:841-852`). For an App Store / ad-hoc type the step adds the banner
  *"App Store and ad-hoc profiles use distribution certificates — development
  certificates are excluded below."* (`:1305-1311`). With no signing certs at
  all: *"No signing certificates found. Create a development or distribution
  certificate first."*
- **Runner assertion:** with only a **development** cert present, choosing
  **App Store** shows that cert greyed as `Excluded · wrong type` and Continue
  stays disabled; choosing **Development** makes it selectable. This is the
  case that proves the cert→profile type constraint.

### TC20 — Create Profile, step 4: devices ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven)
- **UI elements:** for device-allowing types: `DEVICES (n SELECTED)` +
  **Select All** / **Clear** + rows `<name>` / `<platform> • <udid>`, with
  greyed exclusions `Disabled · excluded` / `Wrong platform · excluded`. For
  App Store / In-House / Direct: an info banner **No device registration
  required** + a 4-row recap (`Devices → Not applicable · skipped`)
  (`:1361-1479`).
- **Guard:** `canContinue` for `.devices` =
  `resolvedType?.allowsDevices == false || !deviceIds.isEmpty` (`:940-943`) —
  a development/ad-hoc profile **cannot continue with zero devices** (Apple
  409s). `allowsDevices` is a suffix test on `_DEVELOPMENT` / `_ADHOC`
  (`ResourceModels.swift:1065-1067`).
- **API:** none on this step.
- **Expected (code reading):** eligibility = `status == "ENABLED"` **and**
  `devicePlatformMatches` (platform match or empty/`UNIVERSAL`,
  `ProfileViews.swift:1203-1208`). `createProfile` omits the `devices`
  relationship entirely unless `allowsDevices && !deviceIds.isEmpty`
  (`ResourcesViewModel.swift:1914-1916`) and the wizard additionally intersects
  the ids with the eligible set before calling (`ResourcesView.swift:1590-1596`).
- **Runner assertion:** App Store profile → device step shows the recap and no
  checkboxes; development profile with only DISABLED devices → Continue
  disabled. ⚠️ Registering a device counts against the team's yearly device
  limit — do not do this casually.

### TC21 — Create Profile, step 5: name ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven)
- **UI elements:** live recap line (e.g. *"iOS Development · com.acme.orbit ·
  John Appleseed 7168F2F9 · 2 devices selected"`, `:1513-1537`), `LaunchField`
  **Profile Name** (placeholder *Acme Development*), hint *"A descriptive,
  unique name."* (`:1497-1509`).
- **Guard:** `canContinue` for `.name` =
  `!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty` → **Continue
  disabled** for whitespace-only input. Model backstop:
  `.failure("Enter a name for the profile.")` (`ResourcesViewModel.swift:1888`).
- **API:** none on this step.
- **Expected (code reading):** the recap updates live and counts only
  *eligible* selected devices (`eligibleSelectedDeviceCount`, `:1453-1455`).
- **Runner assertion:** spaces-only name keeps Continue disabled; the recap
  changes as picks change; multi-cert shows `N certificates` rather than a
  serial.

### TC22 — Create Profile, step 6: review + submit ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven) — **mutating, not executed**
- **UI elements:** review rows **Type / Bundle ID / Certificates / Devices /
  Name** (`:1539-1552`) with the footer note *"Test on a throwaway profile
  first. Needs an API key with the Admin role."*; footer **Cancel / Back /
  Create** (the Continue button becomes **Create** on the review step).
- **Guard:** `canContinue` for `.review` is always `true` (`:946-947`) — the
  gate is upstream. `create()` re-validates `resolvedType` before calling
  (`:1584-1587`). Write key `createProfileKey` blocks a double tap
  (`ResourcesViewModel.swift:1893`).
- **API:** `POST /v1/profiles` with `attributes.name` + `attributes.profileType`
  and relationships `bundleId` (single), `certificates` (array, always sent,
  sorted), `devices` (array, omitted when not applicable)
  (`ResourcesViewModel.swift:1899-1923`).
- **Expected (code reading):** `.success` prepends the row and swaps the wizard
  for `ProfileCreatedSheet` (`createdProfile = profilesState.loadedValue?.first`,
  `:1597-1598`). `.failure` keeps the wizard open and shows the message
  inline; `.ignored` also keeps it open (`:1600-1604`). A TestFlight-only key
  403s and renders the "needs Admin" wording.
- **Runner assertion:** the review recap matches every prior pick; after Create
  the wizard shows **Provisioning profile created** with
  `<type> · <platform> · expires <date>`. Record the profile name + expiry +
  status for **CH2**.

### TC23 — ProfileCreatedSheet: download + Install for Xcode ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven) — **writes to disk, not executed**
- **UI elements:** success sheet **Provisioning profile created**, green banner
  quoting name/type/platform/expiry, buttons **Download .mobileprovision** /
  **Install for Xcode** / **Done** (`ProfileViews.swift:1058-1109`). After a
  successful install the sheet swaps to `ProfileInstallResultSheet`:
  **Profile installed for Xcode**, green *Installation complete*, **File** and
  **Install location** fields, **Reveal File** / **Open Profile** / **Done**
  (`:1137-1176`).
- **Guard:** `isWorking` swaps both action buttons for a spinner and disables
  **Done** (`:1089-1103`).
- **API:** **Download** → `GET /v1/profiles/{id}` + `NSSavePanel` →
  `<name>.mobileprovision`. **Install for Xcode** → same fetch, then an
  `NSSavePanel` **rooted at `~/Library/MobileDevice/Provisioning Profiles/`**
  with the panel message *"Save into Provisioning Profiles so Xcode picks it up
  automatically."* (`ResourcesViewModel.swift:2118-2131`).
- **Expected (code reading):** the save panel is deliberate — it carries user
  consent so the write works under the app sandbox (`:2104-2106`); cancelling
  returns `.ignored` and shows no error. `Reveal File` uses
  `NSWorkspace.activateFileViewerSelecting`.
- **Runner assertion:** after Install, **Install location** shows the
  Provisioning Profiles directory and Reveal File opens Finder on a real
  `.mobileprovision`; cancelling the panel leaves the sheet on the success
  step with no error text.

### TC24 — Profile detail opens and hydrates its dependencies ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven)
- **UI elements:** click a profile row → full-screen detail: back chevron
  *Profiles*, profile name, subtitle
  *"<status> · <type> · expires <date>"*, a **Dependency inspector** table
  (columns Dependency / Value / Status / Jump), **Profile details**
  (Type-platform, Expiration, Name), a `SIGNING CHAIN` note
  (*"Certificate → Profile → Bundle ID → Device…"*), **Private key**, and a
  footer with `Last synced …`, **Delete…**, **Regenerate…**,
  **Download .mobileprovision** (`ProfileViews.swift:93-481`).
- **Guard:** a full-screen **Loading profile details…** overlay covers the view
  until the fetch resolves (`:180-211`); a fetch failure shows a warning banner
  *"Couldn't load profile details"* and falls back to list data
  (`:132-137`).
- **API:** `GET /v1/profiles/{id}?include=bundleId,certificates,devices`
  (`fetchProfileDetail`, `ResourcesViewModel.swift:1999-2010`). Plus a local,
  non-network keychain check for the private key
  (`hasLocalIdentity`, `:2144-2162`; status text *"found locally"* /
  *"Not found locally"* / *"Checking keychain…"*, `ProfileViews.swift:418-425`).
- **Expected (code reading), inspector rows:** one **Certificate** row per
  hydrated cert (`<displayName> · <serial>`, status `Active` or
  `Expired · <date>`), then **Profile** (`Copy Profile ID →` → pasteboard),
  then **Bundle ID** (`Explicit / <platform>`, `Open Bundle ID →`), then one
  **Device** row per hydrated device (`Enabled` / `<status>`, `Open Device →`).
  Missing collections degrade explicitly: no certs → `Certificate · — ·
  Unavailable` in destructive red with **no** jump link; no bundle → same; no
  devices → `None selected` (or `Not applicable` when the type embeds none) with
  status `—` / `Skipped` (`:302-372`).
- **Runner assertion:** a healthy dev profile shows Certificate(Active) →
  Profile(Active) → Bundle ID(Explicit / iOS) → N Device(Enabled) rows; the
  **Private key** field says `found locally` when the CSR's private key is in
  the login keychain, else `Not found locally`. On a freshly created CSR in
  this app it should read **found locally** if the key was imported.

### TC25 — Profile detail banners for Invalid / Expired ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven)
- **UI elements:** error banner `Signing certificate revoked` — *"This profile
  cannot be used for new signing. Select a compatible certificate and recreate
  the profile."*; or `Expired <date>` — *"Create a compatible replacement;
  expiry cannot be extended by downloading the same file."*
  (`ProfileViews.swift:121-131`).
- **Guard:** banner is driven by `shown.computedStatus` — note it reads the
  **freshly fetched** `detail`, not the list row.
- **API:** same single detail fetch as TC24.
- **Expected (code reading):** **Invalid** and **Expired** are mutually
  exclusive (`INVALID` wins, TC16). This is the surface where step D of the
  chain *does* show correct data, because it refetches — the **list** does not
  (BUG-1).
- **Runner assertion (the workaround for BUG-1):** after a revoke, open the
  profile and confirm the banner appears even though the list still reads
  *Active*. That divergence is the bug's observable signature.

### TC26 — Profile detail dependency jump links ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven)
- **UI elements:** **Open Certificate →**, **Open Bundle ID →**,
  **Open Device →**, **Copy Profile ID →** (`:270`, `:334`).
- **Guard:** jump labels are empty (no button) for absent dependencies
  (`:316`, `:350`).
- **API:** none — pure navigation. Each jump sets the target section's search
  text and switches section (`ShipyardShell.swift:169-183`).
- **Expected (code reading):** jumping to Certificates sets
  `searchTexts[.certificates] = <displayName ?? name ?? "">`. Two consequences:
  (a) after a revoke, the cert is gone from the local list, so the jump lands
  on an **empty** filtered list whose copy still says *No Certificates*
  (**BUG-7**); (b) if both `displayName` and `name` are nil the search is set to
  `""`, which `query(for:)` trims to *no filter* — the user lands on the whole
  list instead of one row.
- **Runner assertion:** each jump lands on the right section already filtered
  to that dependency; **Copy Profile ID** puts the raw profile id on the
  pasteboard.

### TC27 — Regenerate profile, step 1 (Dependencies) ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven)
- **UI elements:** `Regenerate <name>` header, stepper
  Dependencies / Review / Result, read-only **Profile type** + **Bundle ID**
  fields, `CERTIFICATES (n SELECTED)` with **Select All** / **Clear**, and (for
  device-allowing types) a `DEVICES (n SELECTED)` scroll list
  (`ProfileViews.swift:769-882`).
- **Guard:** **Review Replacement** is `.disabled(isSaving || certificateIds.isEmpty)`
  (`:701-703`) → cannot advance with no certificate. Devices are preselected
  from the profile's current set, intersected with eligibility (`:736-739`).
  **Select All** is disabled when the eligible list is empty; **Clear** when
  nothing is selected.
- **API:** `.onAppear` drains `.certificates` and `.devices` and fetches the
  profile detail (`:729-745`); the detail fetch failure renders an inline error.
- **Expected (code reading):** only **active, non-expired** certs of the
  matching kind are offered, with the copy *"Only active development
  certificates appear as selectable replacements."* or the distribution
  equivalent (`:774-776`); empty state *"No active compatible certificates —
  create one first."* ⚠️ Eligibility here checks **kind + expiry only — not
  platform** (`:652-660`), unlike the create wizard → **BUG-3**.
- **Runner assertion:** for a development profile only development certs appear;
  after revoking the cert in **CH3**, the revoked cert is absent from this list
  (it was removed locally) — which is why regeneration is possible at all.

### TC28 — Regenerate profile, step 2 (Review) + Delete & Recreate ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven) — **destructive: DELETE lands first, not executed**
- **UI elements:** warning banner *"Regeneration replaces the profile record"*
  — *"The old <statusWord> <name> profile is deleted, then a new profile is
  created with a new identifier. If creation fails after deletion, no
  replacement exists yet."*; a **Required follow-up** paragraph; the
  old-vs-replacement table (columns Property / Old / Replacement):
  **Signing certificate** `<serial> · replaced` → `<serial> · active`;
  **Device set** `N iOS device(s)` → `N enabled device(s)`;
  **Profile identity** `Old profile ID` → `New ID / new file`
  (`:884-960`); buttons **Back** / **Delete & Recreate** (red).
- **Guard:** ⚠️ **only `isSaving`**. **Delete & Recreate** is *not* disabled
  when `deviceIds.isEmpty` — unlike the create wizard, which requires ≥1 device
  for development/ad-hoc types (`:943`) — and **not** type-to-confirmed →
  **BUG-2** (§4). Devices are the body field Apple rejects last.
- **API:** `DELETE /v1/profiles/{id}` **first**, then `POST /v1/profiles`
  (`regenerateProfile`, `ResourcesViewModel.swift:2038-2078`). Order matters:
  the local row is dropped immediately after the DELETE (`:2060`).
- **Expected (code reading) failure wording:** if the POST then fails, the
  message is *"<reason> The old profile was already deleted — no replacement
  exists yet."* (`:2069`); an `.ignored` POST yields *"The old profile was
  deleted, but the replacement was not created — run the wizard again."*
  (`:2071`). The UI stays on the review step with that message inline.
- **Runner assertion:** **Back** returns to Dependencies with the picks intact;
  **Delete & Recreate** ends on the result step; on failure assert the old
  profile is genuinely gone from the list (this is the destructive failure mode
  worth testing deliberately on a throwaway profile).

### TC29 — Regenerate profile, result stage ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven)
- **UI elements:** **Profile recreated**, green banner
  *"<name> · Active"* + *"New profile ID and file created. The previous profile
  record was removed."*, the follow-up line *"Update Xcode and CI references
  before the next signing operation."*, buttons **Download Replacement** /
  **Open Profile** (`ProfileViews.swift:976-998`).
- **Guard:** n/a.
- **API:** **Download Replacement** → `downloadProfile(viewModel.profilesState.loadedValue?.first)`
  — i.e. it downloads *whatever is first in the list*, not the profile it just
  created (`:1045-1050`) → **BUG-4** (§4).
- **Expected (code reading):** the banner name is likewise
  `profilesState.loadedValue?.first?.name` (`:1036`), i.e. inferred from list
  position rather than carried from the create response.
- **Runner assertion:** with only one profile being regenerated the two are the
  same row — the risk only appears when the list order differs. Note for the
  runner: this stage's success toast is **not** posted (regenerate is not wired
  into `ShipyardToastCenter`, consistent with the earlier toast sweep).

### TC30 — Delete profile: sheet + type-to-confirm gate ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven) — **destructive, not executed**
- **UI elements:** sheet *Delete \<name\>?*, warning banner **Profile record
  removal is irreversible**, a `Confirm profile` block with the caption *"This
  does not remove current App Store versions or delete the app record."*, a
  **Type profile name** `TextField` **pre-labelled with the profile's own name**,
  and **Cancel / Delete Profile** (`:487-598`).
- **Guard (real, and correctly implemented):**
  ```swift
  // ProfileViews.swift:498-502
  let confirmed = !name.isEmpty
      && confirmation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        == name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  ```
  → the button background is `ShipyardTheme.danger` only when confirmed,
  otherwise a muted grey, and `.disabled(!confirmed)` (`:588-590`).
  `isSaving` disables the field, Cancel, and swaps the button for a spinner
  (`:544`, `:562-566`). Model backstop: none needed — the id is already known.
- **API:** none until **Delete Profile** is pressed.
- **Expected (code reading):** comparison is case-insensitive and
  whitespace-trimmed, matching the Users pattern (`UserPermissionViews.swift:962`).
- **Runner assertion:** the destructive button is greyed/disabled on open;
  typing the wrong name, a prefix, or the name with different case leaves it
  disabled (case-insensitive match *should* enable it); typing the exact name
  turns it red and enables it.

### TC31 — Delete profile: impact table ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven)
- **UI elements:** `PermissionSummaryTable` with headers
  **Dependency / Effect** (`:547-550`), three rows from `effectRows`
  (`:504-517`).
- **Guard:** n/a (display only).
- **API:** n/a.
- **Expected (code reading), row contents:**
  | Row key | Value |
  |---|---|
  | `Certificate <serial, comma-joined>` — or just `Certificate` when none are hydrated | `Not revoked` |
  | `<bundle identifier>` — or `Bundle ID` | `Not deleted` |
  | `N registered device(s)` — or `Devices` when 0 | `Not disabled` |
- **Runner assertion — the important one:** opened from the **detail** view the
  table names the certificate **serial** and the device **count**; opened from
  the **row context menu** it degrades to bare `Certificate` / `Devices`
  because the list payload carries no `certificates`/`devices` relationships
  (`include=bundleId` only, `ResourcesViewModel.swift:452-456`) → **BUG-6**.
  Same deletion, materially different confirmation quality.

### TC32 — Delete profile: execute DELETE ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven) — **mutating/irreversible, not executed**
- **UI elements:** **Delete Profile** → spinner → sheet dismisses via `onDone()`
  (which for the detail path also returns to the list,
  `ProfileViews.swift:218-223`); success toast **Profile deleted**; failure →
  error toast **Couldn't delete profile** + inline message, sheet stays open
  (`:567-582`).
- **Guard:** per-profile-id write key (`.ignored` on a duplicate tap,
  `ResourcesViewModel.swift:1941-1943`).
- **API:** `DELETE /v1/profiles/{id}` (204). On success the row is dropped
  locally via `dropProfileLocally` — re-located after the await — and the count
  pill decrements and the search cache invalidates (`:1955`, `:2082-2091`).
- **Expected (code reading):** no refetch — the local drop is the source of
  truth; if the row was not found in local state the result degrades to
  `.ignored` (`:1956`), which would dismiss nothing and show no message.
- **Runner assertion:** row gone, pill decremented, toast shown; the other
  profiles' statuses and the certificates list are **unchanged** (the impact
  table's promise).

### TC33 — Profiles search ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven)
- **UI elements:** *Search Profiles* field (`ProfilesTableView.swift:104`).
- **Guard:** whitespace-only queries are ignored (`:230-237`).
- **API:** none — local filter over loaded pages.
- **Expected (code reading):** matches **seven** fields — `name`, `uuid`,
  `profileType`, `profileState`, `platform`, `bundleId.identifier`,
  `bundleId.name` (`ResourcesViewModel.swift:280-285`), so typing
  `INVALID` or `IOS_APP_STORE` filters by state/type as a side effect.
- **Runner assertion:** searching a bundle identifier, a type string, and
  `INVALID` each narrow the table; `hasActiveSearch` flips the empty state to
  **No Matching Profiles** (`:214`).

### TC34 — Profiles type filter ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven)
- **UI elements:** `Type: All ▾` chip (AX label *"Filter by profile type"*),
  menu = **All** + one item per `ProfileTypeOption.allCases` → **all 14**
  display names (`iOS App Development`, `iOS App Store`, `iOS App Adhoc`,
  `iOS App Inhouse`, `Mac App Development`, `Mac App Store`, `Mac App Direct`,
  `TvOS App Development`, …, `Mac Catalyst App Direct`)
  (`ProfilesTableView.swift:106-116`, `ResourceModels.swift:1036-1060`).
- **Guard:** filtering is applied **on top of** the search
  (`filteredProfiles.filter { … }`, `:29-35`) — both must match. ⚠️ The chip
  label shows the *option's* display name but stores the **raw** `rawValue`
  (`:109`, `:112`), and the row filter compares against
  `profile.profileType` (`:31`) — consistent for all 14 known values.
- **API:** none.
- **Expected (code reading):** the filter never counts toward the header pill —
  the pill shows the team's **total** (or loaded count), not the filtered count
  (`:164-169`), so the header can read `12 Total` over 2 visible rows.
- **Runner assertion:** selecting `iOS App Store` leaves only store profiles;
  combined with a search the intersection is shown; the empty state reads
  *No Matching Profiles*.

### TC35 — Profiles status filter ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven)
- **UI elements:** `Status: All ▾` chip (AX label *"Filter by profile status"*),
  menu = **All / Active / Expired / Invalid** (`ProfilesTableView.swift:118-127`).
- **Guard:** same intersection semantics as TC34.
- **API:** none.
- **Expected (code reading):** exactly three statuses exist client-side
  (`ProfileComputedStatus`, `ResourceModels.swift:105-117`), so a profile the
  API reports as **PROCESSING** falls through to *Active* and cannot be filtered
  → **BUG-5** (§4).
- **Runner assertion (this is the chain's key filter):** after **CH4**, select
  `Status: Invalid` — **expect the profile to be listed there, but by code
  reading it will not be**, because the list was never refetched (BUG-1). Record
  exactly what you see.

### TC36 — Profiles row context menu ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven)
- **UI elements:** right-click a profile row → **Open**, **Download**
  (replaced by static text **Downloading…** while in flight), **Delete**
  (`role: .destructive`), each with a per-row AX label
  (`ProfilesTableView.swift:304-328`).
- **Guard:** the in-flight swap is per-row via `downloadingId` (`:306-308`), so
  a second row's Download stays enabled.
- **API:** Open → local navigation; Download → `GET /v1/profiles/{id}` +
  save panel; Delete → `DeleteProfileSheet` (TC30).
- **Expected (code reading):** success toasts *Profile downloaded*; failures go
  to the list-level red banner. Unlike `UsersTableView`'s menu (BUG-1 in the
  Users report), there is no protected-row case here — every profile is
  deletable, which is correct.
- **Runner assertion:** exactly 3 items; Download shows `Downloading…` while the
  save panel is up; Open enters the detail view.

### TC37 — Profiles pagination footer ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven)
- **UI elements:** identical to TC14 but for `.profiles`
  (`ProfilesTableView.swift:333-359`).
- **Guard:** `isPaginatingKinds` per-kind (`:351`).
- **API:** `GET /v1/profiles?limit=50&cursor=…&sort=name&include=bundleId`.
- **Expected (code reading):** cursor is issued under `sort=name`; any local
  change of *sort* would invalidate it — the type/status filters are client-side
  precisely for that reason (`AppConfigs` convention).
- **Runner assertion:** rows accumulate de-duplicated; failure offers the red
  retry.

---

## 4. The certificate → profile dependency chain (ordered end-to-end)

The user's headline scenario. **This is the most important sequence in the
document**, because it is the one place where a stale-cache bug is *designed*
into the current code. Run it in this order on a throwaway app/bundle id; steps
C, D, CH5 are destructive.

| Step | Case | Action | Guard that should block it if incomplete | API |
|---|---|---|---|---|
| **A** | **CH1** | Create a certificate. Record **name** and **status**. | **Create** disabled until a valid PEM CSR is loaded (`ResourcesView.swift:335`, `:909-913`) | `POST /v1/certificates` |
| **B** | **CH2** | Create a profile that uses that certificate. Record **name**, **expiration**, **status**. | Continue disabled at each of the 6 steps; `!certificateIds.isEmpty` at step 3; `!deviceIds.isEmpty` for dev/ad-hoc at step 4 | `POST /v1/profiles` |
| **C** | **CH3** | Revoke the certificate. | ⚠️ **no gate at all** — `Revoke` is enabled on open and is the default keyboard action (`RevokeCertificateDialog.swift:57-66`) | `DELETE /v1/certificates/{id}` |
| **D** | **CH4** | **Assert the profile transitions to `Invalid`.** | — | **none is issued** — see below |
| **E** | **CH5** | Recreate the profile (regenerate, or new cert + new profile) and confirm it returns to Active. | **Review Replacement** disabled with no certificate (`ProfileViews.swift:703`); `.failure` if bundle id unknown (`:1023`) | `DELETE` + `POST /v1/profiles` |

### CH1 — Create the certificate ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven) — **mutating, not executed**
- **Execution status (record):** `______`
- **Steps / UI elements:** Sidebar → Certificates → *Create Certificate* →
  `CERTIFICATE TYPE` = the kind the chain needs (use **iOS Development** for an
  iOS development profile, **iOS Distribution** for App Store/ad-hoc) →
  *Choose File…* → pick a real `.csr` → **Create**.
- **Guard:** CSR PEM markers + 64 KB cap; Create disabled without content.
- **API:** `POST /v1/certificates` → success step **Certificate Created** →
  **Download .cer** (`GET /v1/certificates/{id}`).
- **Expected (code reading):** the new row is prepended, the pill increments,
  the search box clears (`prependCertificate`, `:2290-2317`), and the status
  chip reads **Active**. **Record: name = ______, status = Active.**
- **Chain note:** the certificate is only usable in a profile if its *type*
  matches the profile's distribution kind (`matchesKind`, TC19) and it is not
  expired. A revoked certificate is **removed from the local list**, so it also
  disappears from the wizard's picker — which is what makes CH5 possible.

### CH2 — Create the profile on that certificate ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven) — **mutating, not executed**
- **Execution status (record):** `______`
- **Steps / UI elements:** Sidebar → Profiles → *Create Profile* → 6 steps:
  1. Type: platform + distribution kind matching the CH1 certificate kind
  2. Bundle ID: tick the throwaway bundle id
  3. Certificates: tick **the certificate from CH1** (it must appear as a
     selectable row, not a greyed `Excluded · wrong type`)
  4. Devices: for development/ad-hoc, tick ≥1 enabled iOS device
  5. Name: e.g. `ACME chain test dev`
  6. Review → **Create** → **Provisioning profile created**
- **Guard:** `canContinue` per step (`:932-949`); model backstops
  `ResourcesViewModel.swift:1888-1892`.
- **API:** `POST /v1/profiles` (`bundleId`, `certificates`, `devices`
  relationships).
- **Expected (code reading):** the created sheet shows
  `<type> · <platform> · expires <date>`; the new row is prepended with status
  **Active**. **Record: name = ______, expiration = ______, status = Active.**
- **Chain note:** the profile list row carries **no certificates** (list fetch
  includes only `bundleId`), so the *only* place the link is visible before the
  revoke is the **profile detail's** Dependency inspector (TC24) — check it
  here, or you lose the evidence for CH4.

### CH3 — Revoke the certificate ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven) — **destructive, not executed**
- **Execution status (record):** `______`
- **Steps / UI elements:** Sidebar → Certificates → right-click the CH1 row →
  **Revoke** → read the consequence copy → **Revoke** (red).
- **Guard:** ⚠️ **none** (BUG-4). Only `writeInFlight` prevents a duplicate tap.
- **API:** `DELETE /v1/certificates/{id}` → 204.
- **Expected (code reading):** the sheet dismisses immediately, the row
  disappears from the table, the count pill drops by 1, and a
  **Certificate revoked** success toast fires (`CertificatesTableView.swift:68-79`,
  `ResourcesViewModel.swift:963-971`). **No profile refresh is issued.**
- **Runner assertion:** also note what the app *tells* you — the dialog says the
  revoke *"will immediately invalidate any active provisioning profiles that
  depend on it"* but **never names them**. The affected-profile list is exactly
  the information the operator needs at this moment and the app has it (the
  profile→certificate relationship) but does not surface it.

### CH4 — Assert the profile transitions to **Invalid** ❌ NOT RUN — **BUG-1 PREDICTED**

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven)
- **Execution status (record):** `______`
- **What the code does — read this before running:**
  - `revokeCertificate` (`ResourcesViewModel.swift:948-977`) mutates **only**
    `certificatesState`, `totals[.certificates]` and `dataVersion`. It issues
    **no** `GET /v1/profiles` and does **not** invalidate `profilesState`.
  - Re-visiting the Profiles section calls `viewModel.load(.profiles)`
    (`ProfilesTableView.swift:76`), and `load(_:)` returns immediately when the
    kind is already loaded this session (`ResourcesViewModel.swift:359-360`).
    So **navigating away and back does not refetch either**.
  - The only paths that clear it are a manual `retry(.profiles)` (from the
    error state only), a **team switch** (`resetForTeamSwitch`, `:548-581`) or
    an app relaunch.
  - **Consequence:** the Profiles list keeps showing the profile as **Active**
    with a green dot after the revoke — an actively misleading state, and it
    persists for the rest of the session.
  - **Partial escape hatch:** the **profile detail view** *does* refetch
    (`fetchProfileDetail`, `ProfileViews.swift:212-217`, `:446-456`), so opening
    the profile after the revoke will show the correct **Invalid** status and
    the *"Signing certificate revoked"* banner. So the same object reports two
    different statuses depending on which surface you look at.
- **Expected (code reading):**
  - Profiles **list** row: **still Active** ❌ (bug)
  - `Status: Invalid` filter (TC35): **does not contain the profile** ❌ (bug)
  - Profiles **detail** banner: **Signing certificate revoked** ✅
  - Detail inspector's Certificate row: Apple stops returning the revoked cert
    under `include=certificates`, so the row should degrade to
    `Certificate · — · Unavailable` in destructive red (`ProfileViews.swift:312-316`,
    `profileCertificateStatus` `:78-85`).
- **Runner assertion (this is the discriminating observation):** capture the list
  row status and the detail banner for the same profile at the same moment. If
  the list says Active while the detail says Invalid → **BUG-1 confirmed**; if
  the list already says Invalid → BUG-1 does not reproduce (Apple-side
  behaviour changed, or something outside this code path refetches) and the
  defect should be downgraded. Also confirm the inspector's Certificate row
  reads `Unavailable` rather than `Active` — if it still reads `Active`, the
  revoked certificate is still being returned by the API and `Invalid` may take
  time to propagate (see §6).
- **Fix (proposed):** invalidate the dependent collection on revoke.
  ```swift
  // ResourcesViewModel.swift — revokeCertificate, after the local removal
  profilesState = .idle          // or profilesState = nil-ed refresh
  loadedKinds.remove(.profiles)
  Task { await fetch(.profiles) }
  ```
  Cheaper and equally correct: mark profiles stale and let `load(.profiles)`'s
  guard pass — i.e. `loadedKinds.remove(.profiles)` plus
  `lastSyncDates[.profiles] = nil` — so the next visit refetches. A targeted
  alternative is to mutate the affected rows' `profileState` to `"INVALID"`
  locally from the revoke response, but a refetch is the only way to be
  truthful (Apple decides when the transition happens). Ideally the revoke
  dialog should also list the profiles that will go invalid.

### CH5 — Recreate the profile and confirm it returns to valid/active ❌ NOT RUN

- **Execution status:** ❌ NOT RUN — accessibility bridge unavailable (app not driven) — **destructive (DELETE lands first), not executed**
- **Execution status (record):** `______`
- **Two routes — record which was used:**
  - **Route 1 (preferred, exercises the wizard):** create a **new
    certificate** (same kind, new CSR) → open the invalid profile →
    **Regenerate…** → Dependencies (tick the new cert; devices are preselected)
    → **Review Replacement** → **Delete & Recreate** → result stage
    *Profile recreated* → **Download Replacement**. Then re-check
    **Status: All** and confirm the profile reads **Active**.
  - **Route 2 (manual):** delete the invalid profile (TC30) and run the 6-step
    wizard again with the new certificate.
- **Guard:** **Review Replacement** `.disabled(isSaving || certificateIds.isEmpty)`
  (`ProfileViews.swift:703`); `runRegenerate` refuses when the bundle id
  cannot be resolved (`:1023-1026`) and the view model refuses an empty
  certificate set (`:2046`) and an empty name (`:2045`).
- **API:** `DELETE /v1/profiles/{id}` then `POST /v1/profiles`.
- **Expected (code reading):** success → result stage; the review table's
  *Replacement* column shows `<new serial> · active`. The replacement gets a
  **new profile id and a new expiry**. ⚠️ If the POST fails after the DELETE,
  the profile is **gone with no replacement** and the app says so explicitly —
  the one failure this flow must be tested against.
- **Runner assertion:** the regenerated profile is **Active** (green dot, no
  *Signing certificate revoked* banner in the detail), its detail inspector's
  Certificate row reads `Active` with the **new** serial, and **Download
  Replacement** yields a usable `.mobileprovision`. Record the new name +
  expiry.

---

## 5. Defects

All defects below were **found by reading the code** (static analysis only) —
none was observed at runtime. Severity is my pre-rating; re-rate after a real
run.

### BUG-10 — A stale server error survives a change of certificate type (Medium) — found live

Reproduced 2026-10-06 while running TC5.

1. Type `iOS Development` + CSR → *Create* → Apple rejects with a **409**,
   surfaced inline as: *"You already have a current iOS Development certificate or a
   pending certificate request."*
2. Changed the type to `Mac App Distribution`. **The error text stayed on screen,
   still naming "iOS Development"** while the dropdown read `Mac App Distribution`.

So the submission error is only cleared by re-opening the sheet, not by changing the
inputs that caused it. A user who fixes the problem sees a message describing the
thing they just changed away from, and may reasonably think the fix did not register
(`ResourcesView.swift` clears `errorMessage` only in some paths — the type
`onChange` does not clear it).

**Fix:** clear `errorMessage` whenever any input changes (type, CSR selection), or
key the message to the request that produced it.

**Note (good behaviour):** the 409 itself is handled correctly — Apple's conflict is
surfaced verbatim instead of being swallowed, and *Create* stays enabled so the user
can retry with a different type. This is exactly the class of message that used to be
dropped by the dead `bannerError` (BUG-2 in the Users report) — worth confirming the
same regression isn't present here.

### FIXES APPLIED 2026-10-06 (compile-clean, `xcodebuild` green; unit tests show no new failures)

| Defect | Fix | File |
|---|---|---|
| **BUG-10** stale error after changing type | `errorMessage = nil` in the certificate-type `Menu` action, so the previous submit error can't outlive the input that caused it | `SideBarView/Resources/ResourcesView.swift:227` |
| **BUG-1 (High)** revoke never invalidates the profiles list | After a successful `DELETE /v1/certificates/{id}`, drop the `.profiles` latch and refetch. Previously `profilesState` was untouched and `load(.profiles)` early-returns on `loadedKinds`, so navigating away and back did **not** re-read — the list kept showing `Active` for a profile Apple had just invalidated, contradicting the detail screen | `ResourcesViewModel.revokeCertificate` |
| **BUG-4 (Medium)** regenerate result names the wrong profile | New `lastRegeneratedProfileId`, set by diffing profile ids across the delete+create, and read by the result stage. It previously used `profilesState.loadedValue?.first?.name`, which labelled the replacement with whatever profile sorted first. Cleared on failure so a stale id can't render | `ResourcesViewModel` + `ProfileViews.runRegenerate` |

**Still open / not fixed:** BUG-2 (regenerate is DELETE-first and does not carry device
selection forward), BUG-3 (regenerate certificate eligibility ignores platform), BUG-5
(`PROCESSING` renders as Active; `activated`/Revoked chip unreachable), BUG-6/7/8/9.
BUG-2 needs a product decision — whether a regenerated profile should inherit the
original's devices — so it was left alone rather than guessed at.

### BLOCKER-1 — The CSR file picker is not drivable, so certificate creation cannot be completed (Harness)

**TC5 and CH1 are blocked on this.** A CSR *can* be produced without the app —
`openssl req -new -newkey rsa:2048 -nodes -keyout qa_test.key -out qa_test.csr -subj "…"`
— and one was generated for this pass. The app, however, **only accepts a CSR
through the native `NSOpenPanel`** (`ResourcesView.swift:257` → `selectCSRFile()`);
it has no built-in generator.

That panel cannot be driven from the agent side:

- It opens as a **second window** (560×315, empty title, `list-windows` index 1)
  that carries **no accessibility content** — the app's AX tree keeps returning the
  main window even when explicitly targeted with `--window-index 1` / `--window-id`.
- `orca computer capabilities` reports `surfaces.dialogs: false`, so there is no
  dialog surface to drive.
- The usual escape hatch fails too: with the panel open, `System Events`
  **Cmd+Shift+G** ("Go to Folder") followed by typing the absolute path does not
  reach it — the keystrokes land on the main window and the panel dismisses with
  *No file selected*. (System Events typing *does* work inside the app's own text
  fields, so this is the panel specifically, not the input method.)

**Unblocks in ~15 seconds by hand:** open Certificates → *Create Certificate* →
*Choose File…* → select
`/var/folders/4_/tdy_x1fs7s3gc2r8_dcnj644jb9qsb/T/opencode/csr/qa_test.csr`
→ *Create*. The generated key is at `…/csr/qa_test.key`.

Everything downstream that needs a *new* certificate (CH1, CH2, CH5) inherits this
blocker. Cases that only need an **existing** certificate — revoke, download,
search, filters, the profile create form's certificate picker, delete/regenerate —
are unaffected and can still be executed.

### BUG-1 — Revoking a certificate never invalidates the profiles list (High)

Found by code reading. **This is the step-D failure the user asked about.**

```swift
// SideBarView/Resources/ResourcesViewModel.swift:948-977
func revokeCertificate(id: String) async -> WriteResult {
    ...
    certificates.remove(at: index)               // certificates only
    certificatesState = certificates.isEmpty ? .empty : .loaded(certificates)
    if let total = totals[.certificates] { totals[.certificates] = max(0, total - 1) }
    dataVersion += 1
    return .success                               // ← no profilesState touch, no refetch
}
```

and the guard that makes "just navigate away and come back" not help:

```swift
// ResourcesViewModel.swift:359-360
func load(_ kind: Kind) {
    if loadedKinds.contains(kind) { return }     // ← ProfilesTableView.swift:76 calls this
```

**Impact:** after `DELETE /v1/certificates/{id}` succeeds, the Profiles list
keeps rendering the dependent profile as **Active** with a green dot for the
rest of the session. The `Status: Invalid` filter will not show it. Only the
profile **detail** refetches (`ProfileViews.swift:446`) and therefore shows the
truth, so the app contradicts itself between two surfaces for the same object —
the exact class of bug the Users report logged as BUG-4 ("stale list right after
a successful write"). It also means the detail view's own
*"Signing certificate revoked"* remediation banner is undiscoverable from the
list, which is where an operator would look first.

**Fix:** invalidate the dependent collection on revoke — see the sketch in
CH4. Recommended: `loadedKinds.remove(.profiles)` +
`lastSyncDates[.profiles] = nil` and a background `fetch(.profiles)`, so the
next visit refetches without a spinner on the current screen; or have
`CertificatesTableView` optimistically set `profileState = "INVALID"` on rows
whose `certificates` contain the revoked id. The first is honest about Apple's
timing; the second is instant but can over-report.

### BUG-2 — Regenerate is destructive-first with no device guard (High)

Found by code reading.

```swift
// Shipyard/ProfileViews.swift:711 — "Delete & Recreate"
Button("Delete & Recreate") { … }
    .disabled(isSaving)                 // ← only isSaving; no certificateIds/deviceIds check
```

Compare the create wizard, which does gate devices:

```swift
// SideBarView/Resources/ResourcesView.swift:940-943
case .devices:
    // Development/ad-hoc profiles embed devices server-side —
    // an empty pick passes the old gate and 409s on create.
    return resolvedType?.allowsDevices == false || !deviceIds.isEmpty
```

**Impact:** for a development or ad-hoc profile, `regenerateProfile` issues
`DELETE /v1/profiles/{id}` **first** (`ResourcesViewModel.swift:2053-2060`) and
only then `POST`s. If no device is ticked, Apple rejects the POST (devices are
required for those types), so the user ends up with **no profile at all** and a
red button that required no confirmation beyond the review sheet's prose. The
failure is handled *honestly* (`:2069-2071` says the old profile is already
deleted) but the app let the user walk into it. Clearing the device list on the
Dependencies step is one click (`Clear`, `:847`).

**Fix:** disable **Delete & Recreate** when the profile type allows devices and
`deviceIds.isEmpty`, mirroring `canContinue`, and surface the reason inline.
Cheaper belt-and-braces: validate the device set in
`regenerateProfile` *before* the DELETE (the create-side guards at `:2044-2046`
are the right place), and only delete once the replacement parameters are known
valid. Also add type-to-confirm here — the dialog for delete uses it
(`ProfileViews.swift:498-502`) but this equally irreversible flow does not.

### BUG-3 — Regenerate's certificate eligibility ignores platform (Medium)

Found by code reading. Two eligibility functions disagree:

```swift
// Shipyard/ProfileViews.swift:652-660 — regenerate
private var eligibleCertificates: [CertificateModel] {
    certificates.filter { cert in
        guard let option = cert.certificateType.flatMap(CertificateTypeOption.init(rawValue:)) else { return false }
        guard option.matchesKind(development: developmentKind) else { return false }
        if let raw = cert.expirationDate, … date < Date() { return false }
        return true                          // ← no matchesPlatform(_:)
    }
}
```

```swift
// SideBarView/Resources/ResourcesView.swift:841-852 — create wizard
return signingCertificates.filter { cert in
    guard let option = …,
          option.matchesKind(development: development),
          option.matchesPlatform(profileBundlePlatform) else { return false }   // ← present
    …
}
```

**Impact:** `matchesKind` only tests `rawValue.contains("DISTRIBUTION")`, so a
`MAC_APP_DISTRIBUTION` certificate is offered as a selectable replacement for an
**iOS App Store** profile. Apple rejects that combination (409), and because the
DELETE already landed (BUG-2's ordering), the user loses the profile *and* gets
an unusable replacement attempt. The wizard at least shows the cert greyed with
`Excluded · wrong platform`; regenerate shows it as a normal checkbox.

**Fix:** hoist one shared eligibility helper (platform + kind + expiry) and use
it in both places; render the excluded rows in regenerate the way the wizard
does, or at minimum filter by
`option.matchesPlatform(profileType?.bundlePlatformCode ?? "IOS")`.

### BUG-4 — Regenerate's result stage names and downloads "whatever is first" (Medium)

Found by code reading.

```swift
// Shipyard/ProfileViews.swift:1036
newProfileName = viewModel.profilesState.loadedValue?.first?.name
// Shipyard/ProfileViews.swift:1046
guard let replacement = viewModel.profilesState.loadedValue?.first else { return }
if case .failure(let message) = await viewModel.downloadProfile(replacement) { … }
```

**Impact:** both infer the created profile from list *position*. It happens to
work because `prependProfile` inserts at index 0 (`:2231-2251`), but the
identity is positional, not the server-confirmed model returned by the POST.
With a concurrent import, a background drain, or a list whose first row changed
while the sheet was open, the result banner can name the **wrong profile** and
**Download Replacement** can write the wrong `.mobileprovision` to disk — with
no error, because the download itself succeeds. `.guard … else { return }` also
fails silently if the list is momentarily empty.

**Fix:** carry the created model out of the write —
`regenerateProfile` should return the new `ProfileModel`
(the codebase already has the payload-carrying pattern:
`WriteValueResult<T>` at `ResourcesViewModel.swift:158-162`, used by bundle-ID
registration) and the result stage should bind to that value.

### BUG-5 — Two status enums have unhandled cases (Medium)

Found by code reading, two related instances.

1. **`PROCESSING` renders as `Active`.** The model documents the value
   (`ResourceModels.swift:77` and `:190`, *"INVALID, ACTIVE, PROCESSING"*) but
   the derivation ignores it:

   ```swift
   // ResourceModels.swift:122-130
   var computedStatus: ProfileComputedStatus {
       if profileState == "INVALID" { return .invalid }
       if let raw = expirationDate, …, date < Date() { return .expired }
       return .active                       // ← PROCESSING lands here
   }
   ```

   The Status filter offers only All/Active/Expired/Invalid
   (`ProfilesTableView.swift:118-127`), so a profile still being generated by
   Apple is presented as fully **Active** and cannot be filtered out.

2. **The certificate `Revoked` chip is unreachable.** The status helper reads an
   attribute Apple does not send:

   ```swift
   // Shipyard/CertificatesTableView.swift:298-305
   /// Active (usable), Expiring Soon (<30 days), Expired, or Revoked
   /// (deactivated). The API carries no revoked flag — a deactivated,
   /// unexpired certificate reads as revoked.
   private func certificateStatus(_ certificate: CertificateModel) -> CertificateStatus {
       if certificate.activated == false { return CertificateStatus(…, text: "Revoked") }
   ```

   with `@ResourceAttribute var activated: Bool?` (`ResourceModels.swift:46`)
   declared against a resource whose spec has no `activated` attribute — the
   doc comment itself says the API carries no such flag, so the branch can never
   be true. It is doubly unreachable in practice because a successful revoke
   **removes** the row locally (`:963-966`). So **no certificate in this app can
   ever display `Revoked`**, even though the copy, the red dot and the
   `Revoked` label all exist.

**Impact:** cosmetic-to-moderate status misreporting; a revoked certificate
leaving no trace in the UI is arguably *fine* (it is gone), but the code and
the Figma-derived design both promise a Revoked state, and the
`activated == false` check implies a false sense of coverage. Same class of
issue as the Users report's BUG-3 (nondeterministic label).

**Fix:** (a) add a `.processing` case to `ProfileComputedStatus` (grey dot,
*"Processing"*), include **Processing** in the status filter, and exclude
processing profiles from *any* destructive action; (b) either delete the
`activated` field and the `Revoked` branch, or replace them with the honest
model — Apple simply drops revoked certificates from the list, so the table has
no revoked rows to show and the copy should not promise one.

### BUG-6 — The delete impact table is materially weaker from the row menu (Medium)

Found by code reading. `DeleteProfileSheet` builds its effect rows from the
profile's **relationships**:

```swift
// Shipyard/ProfileViews.swift:504-517
let serials = profile.certificates.compactMap(\.serialNumber).filter { !$0.isEmpty }
rows.append((serials.isEmpty ? "Certificate" : "Certificate \(serials.joined(separator: ", "))", "Not revoked"))
…
let deviceCount = profile.devices.count
rows.append((deviceCount == 0 ? "Devices" : "\(deviceCount) registered device\(…)", "Not disabled"))
```

But the Profiles **list** fetch includes only `bundleId`:

```swift
// SideBarView/Resources/ResourcesViewModel.swift:452-456
if kind == .profiles {
    // Hydrate bundle names for the Bundle ID column (Figma 3-5273)
    // and the profile detail inspector. spec: include=bundleId.
    queryParams["include"] = "bundleId"
}
```

`ProfilesTableView` presents `DeleteProfileSheet(viewModel:profile:)` with the
**row** model (`:83-87`), whose `certificates` and `devices` are empty arrays
(the wrappers document this: `ResourceModels.swift:85-100`).

**Impact:** the same destructive action shows a confident impact table from the
detail view (`Certificate 7168F2F9… → Not revoked`, `3 registered devices →
Not disabled`) and a vague one from the row menu (bare `Certificate`,
`Devices`). The user is asked to type the profile name to confirm destruction
with less information precisely in the faster path.

**Fix:** hydrate the row before showing the sheet (one
`fetchProfileDetail` call in `DeleteProfileSheet.onAppear`, with a spinner while
it runs), or add `include=certificates,devices` to the list fetch. The former is
cheaper and keeps the list payload small.

### BUG-7 — Certificates empty state ignores an active search or a broken jump (Low)

Found by code reading.

```swift
// Shipyard/CertificatesTableView.swift:165-169  (no hasActiveSearch check)
Text("No Certificates")
```

versus Profiles, which distinguishes the two cases:

```swift
// Shipyard/ProfilesTableView.swift:214-215
Text(viewModel.hasActiveSearch(for: .profiles) || typeFilter != nil || statusFilter != nil
     ? "No Matching Profiles" : "No Profiles")
```

**Impact:** the certificates empty state always claims *"No Certificates"* with
the subtitle *"Create a certificate to sign development and distribution
builds"* — even when the list is merely filtered to nothing. This is reachable
by the app's own navigation: the profile detail's **Open Certificate →** jump
(`ShipyardShell.swift:172-175`) sets a certificate search and switches section,
so a revoked/missing certificate lands the user on *"No Certificates"*, telling
them the team has no certificates when it has several. The same path with both
`displayName` and `name` nil sets the search to `""`, which disables filtering
entirely and drops the user on the unfiltered list (`ProfileViews.swift:326`,
`ResourcesViewModel.swift:230`).

**Fix:** mirror the Profiles copy — `"No Matching Certificates"` when
`viewModel.hasActiveSearch(for: .certificates)` — and make the jump fall back to
the certificate **id** (or leave the search empty) when both name fields are nil.

### BUG-8 — Certificates have no type/status filters, unlike Profiles (Low)

Found by code reading. Profiles ships both filter menus
(`ProfilesTableView.swift:106-127`); Certificates ships neither
(`CertificatesTableView.swift:88-116`). The Status column already computes four
meaningful values (TC2), so *Expiring Soon* — the one state an operator acts on
proactively — is unreachable by any means other than reading every row or
searching for a date. This is also why TC11 is an absence case.

**Fix:** port the two `Menu`-based chips; they are ~20 lines and can share the
`filterChipLabel` helper already in `ProfilesTableView.swift:146-162`.

**Resolved 2026-10-06.** Tapping a certificate row now opens a detail sheet, and
the row context menu has **Open Details** alongside Download and Revoke.

### BUG-9 — Certificates had no detail view and no row tap (Low, fixed)

Resolved by adding a row tap and `Open Details` context-menu item backed by
`GET /v1/certificates/{id}`. The detail sheet mirrors the table fields and adds
the certificate id, activated state, and certificate-content availability so the
detail endpoint can be verified without opening the native save panel.

---

## 6. Blocked / not verified

### 6.1 The whole pass — accessibility bridge unavailable

The Orca Computer Use accessibility bridge is stalled (`permission_denied` /
"visible windows but no accessibility window"), the same failure mode recorded
in `docs/USERS_FLOW_TEST_REPORT.md` §4 and `ORCA_COMPUTER_USE.md` §7. Per the
brief, **nothing was launched, quit or built**, so:

- **0 of 42 cases executed.** Every case is `❌ NOT RUN`.
- Nothing in this document is an observation of the running app. Every
  "Expected" line is a statement about the source, and each one that could be
  wrong is written so a runner can falsify it (e.g. CH4's
  "if the list already says Invalid → BUG-1 does not reproduce").
- Rendering, layout, truncation and column-width behaviour are **entirely
  unverified**. The fixed widths in the header rows (`:184-197`,
  `:231-245`) predict truncation at small window sizes; that is inference, not
  observation.
- Keyboard shortcuts (`⌘.` cancel, `Return` = default action) are code-declared
  only.

### 6.2 Could not be determined from the code alone

| # | Question | Why the code can't answer it |
|---|---|---|
| 1 | Does Apple flip `profileState` to `INVALID` **synchronously** with the `DELETE /v1/certificates/{id}` response, or after a delay? | Apple-side behaviour; the app never observes it (BUG-1). If delayed, CH4's expected timeline changes and a refetch-based fix needs a second poll. |
| 2 | Does `DELETE /v1/certificates/{id}` **remove** the certificate from `GET /v1/certificates`, or return it in some deactivated form? | The code assumes removal (`ResourcesViewModel.swift:963-966`) and *also* reads an `activated` flag (BUG-5) — the two assumptions are mutually exclusive, and the code comment admits the API "carries no revoked flag". Only a live call settles it. |
| 3 | Under what permission does `DELETE /v1/certificates/{id}` fail on this team — and does Apple 403 or 409 a cert that is in use by a profile? | `writeErrorMessage` handles 403 only (`:2321-2323`); a 409 has no dedicated wording. Both would surface as a raw API message in the banner. |
| 4 | Do `MAC_CATALYST_*` profiles accept iOS-platform bundle IDs? | `bundlePlatformCode` maps `MAC_` → `MAC_OS` (`:1088-1092`) while the wizard sets `profileBundlePlatform = platformCode` (`ResourcesView.swift:814`) — for a Catalyst pick made through **Other profile types…** the platform code stays whatever the Platform menu had, which may or may not be right. Needs a live create. |
| 5 | Is the 64 KB CSR cap ever hit by a legitimate request? | Only derivable by trying; the code's rationale (a real CSR is ~1 KB) is a comment, not evidence. |
| 6 | Does `downloadCertificate` succeed for a certificate whose `.cer` Apple no longer serves? | The failure message exists (`:1001`) but its triggering condition is Apple-side. |
| 7 | Which of `Install for Xcode`'s outcomes occur on a sandboxed, unsigned local build? | `NSSavePanel` + write into `~/Library/MobileDevice/Provisioning Profiles`; the local-run keychain/sandbox quirks in `AGENTS.md` may change the result. |
| 8 | Actual pagination behaviour on a >50-row team | The cursor/sort interaction is safe by construction (client-side filters only), but real cursor epochs are untested. |

### 6.3 Destructive operations — deliberately not executed

None of these were run, and each should be run on a **throwaway team / bundle
id** rather than a live one:

| Case | Operation | Blast radius |
|---|---|---|
| CH1 / TC5 | `POST /v1/certificates` | Consumes one of the team's certificate slots (Apple caps distribution certs); the CSR's private key must be kept or the `.cer` is useless. |
| CH2 / TC22 | `POST /v1/profiles` | Creates a real profile record. |
| TC9 / CH3 | `DELETE /v1/certificates/{id}` | **Irreversible.** Invalidates every dependent profile; cannot be undone even by re-creating a same-name certificate. |
| TC32 | `DELETE /v1/profiles/{id}` | Irreversible record removal (downloaded copies survive). |
| TC28 / CH5 | `DELETE` + `POST` (regenerate) | Irreversible, and **ordered so the delete lands first** — a failed create leaves nothing (BUG-2). |
| TC23 | Install for Xcode | Writes into `~/Library/MobileDevice/Provisioning Profiles` — affects Xcode's view of the machine. |
| TC7 / TC36 | Downloads | `NSSavePanel` writes a `.cer` / `.mobileprovision` to a user-chosen path. |
| TC20 | (implicit) device registration | Device registration counts against Apple's **yearly** limit. Not needed for these cases — reuse an existing enabled device. |

### 6.4 Recommended execution order for the next pass

1. **CH1 → CH2 → CH4 read-only portion first**: load both lists, capture the
   certificate row and the profile row, then open the profile detail to record
   the baseline inspector (certificate serial + `found locally`).
2. **CH3 (revoke)** — the destructive step. Immediately do **CH4**: compare the
   list row status against the detail banner and record the difference. This is
   the single most informative observation in the whole plan.
3. **TC8 / TC11 / TC12 / TC13** (cancel path, absence checks, retry) — read-only
   and cheap.
4. **TC30 / TC31** on a **throwaway** profile, comparing the impact table from
   the row menu vs the detail view (BUG-6).
5. **CH5 Route 1** (regenerate) last, once the invalid profile exists and its
   state is recorded.
6. Filter/search cases (TC10, TC33-35) require **real keyboard input**; the
   harness used in the Users pass could not deliver it (`set-value` renders text
   without firing the SwiftUI binding). Those need a human.

---

## 7. Flow reference (for re-runs)

```
Sidebar TEAM RESOURCES → Certificates                    [CertificatesTableView]
  ├─ header "Certificates · N Total"  ·  Search Certificates  ·  Create Certificate
  ├─ onAppear → load(.certificates)   GET /v1/certificates?limit=50&sort=displayName
  │     └─ loadedKinds guard: revisiting does NOT refetch (ResourcesViewModel:359)
  ├─ row: Name | Type | Serial Number | Expiration Date | Status(dot+text)
  │     ├─ status: Revoked(dead code) / Expired / Expiring Soon(<30d) / Active   :302
  │     ├─ row tap → CertificateDetailSheet → GET /v1/certificates/{id}
  │     └─ context menu:
  │          ├─ Open Details → CertificateDetailSheet
  │          ├─ Download     → GET /v1/certificates/{id} → NSSavePanel(<name>.cer) → toast
  │          └─ Revoke       → RevokeCertificateDialog   ⚠️ no gate, no impact table (BUG-4)
  │                          └─ Revoke → DELETE /v1/certificates/{id}
  │                                 ├─ row removed locally, pill −1
  │                                 └─ toast "Certificate revoked"
  │                                 └─ ⚠️⚠️ NO profile refresh  →  BUG-1 (step D fails)
  ├─ Create Certificate sheet (CreateCertificateForm)
  │     ├─ CERTIFICATE TYPE menu (18 options, default iOS Development)
  │     ├─ CSR file picker (PEM markers + 64 KB cap)
  │     ├─ Create  ⛔ disabled until a valid CSR loads
  │     └─ success: "Certificate Created" → Download .cer → Done
  └─ footer: auto-drain pages · red "Couldn't load more — Retry" on failure
  ⚠️ NO Type filter, NO Status filter (BUG-8) · empty state ignores search (BUG-7)

Sidebar TEAM RESOURCES → Profiles                         [ProfilesTableView]
  ├─ header "Profiles · N Total" · Search · Type: ▾ · Status: ▾ · Create Profile
  ├─ onAppear → load(.profiles)  GET /v1/profiles?limit=50&sort=name&include=bundleId
  │     └─ ⚠️ only bundleId hydrated → no certs/devices on rows (BUG-6)
  ├─ row: Name | Type | Bundle ID | Expiration | Status | Platform(ios/macOS/tvOS)
  │     ├─ status: Invalid(INVALID wins) / Expired(past date) / Active
  │     │          ⚠️ PROCESSING → Active  (BUG-5)
  │     ├─ row tap → ProfileDetailView
  │     └─ context menu: Open | Download (→ "Downloading…") | Delete(role: .destructive)
  ├─ Create Profile wizard (6 steps, canContinue gate per step)
  │     1 Type        platform(iOS/macOS/tvOS) × kind(Dev/AdHoc/AppStore) + Other types(14 total)
  │                   ⛔ Continue disabled when resolve()==nil (macOS+AdHoc)
  │     2 Bundle ID   platform/UNIVERSAL filtered · single-select
  │     3 Certificates  signing-identity certs only; greyed "Excluded · wrong type/platform/expired"
  │                   ⛔ Continue disabled with 0 certs
  │     4 Devices     ⛔ Continue disabled with 0 devices for _DEVELOPMENT/_ADHOC
  │                   AppStore/InHouse/Direct → "No device registration required" recap
  │     5 Name        ⛔ Continue disabled for whitespace-only
  │     6 Review → Create → POST /v1/profiles → ProfileCreatedSheet
  │                   (Download .mobileprovision | Install for Xcode | Done)
  │                   Install → ProfileInstallResultSheet (File / Install location / Reveal)
  ├─ ProfileDetailView   GET /v1/profiles/{id}?include=bundleId,certificates,devices
  │     ├─ banners: "Signing certificate revoked" (invalid) | "Expired <date>"
  │     ├─ Dependency inspector: Certificate(s) → Profile → Bundle ID → Device(s)
  │     │     missing cert  → "Unavailable" (destructive red, no jump)
  │     │     missing bundle → "Unavailable"
  │     ├─ SIGNING CHAIN + Private key (keychain check → "found locally")
  │     ├─ jumps: Open Certificate/Bundle ID/Device → other section, pre-filtered
  │     └─ Delete… / Regenerate… / Download .mobileprovision
  ├─ Regenerate wizard (delete-and-recreate; NO PATCH on /v1/profiles)
  │     1 Dependencies  ⛔ Review disabled with 0 certs   ⚠️ 0 devices allowed (BUG-2)
  │                     cert eligibility: kind + expiry only  ⚠️ no platform (BUG-3)
  │     2 Review       Property/Old/Replacement table + "no replacement exists yet" warning
  │       Delete & Recreate → DELETE /v1/profiles/{id} → POST /v1/profiles
  │                     ⚠️ delete-first: a failed create leaves nothing
  │     3 Result       "Profile recreated" → Download Replacement ⚠️ uses list[0] (BUG-4)
  └─ DeleteProfileSheet
        ⛔ Delete Profile disabled until the typed name matches (case-insensitive)
        impact table: Certificate <serial> → Not revoked | <bundle> → Not deleted | N devices → Not disabled
        ⚠️ degraded to bare "Certificate"/"Devices" when opened from the row menu (BUG-6)

── The chain ──────────────────────────────────────────────────────────────
  CH1 POST /v1/certificates          → cert Active
  CH2 POST /v1/profiles (uses cert)  → profile Active      [+ inspector proves the link]
  CH3 DELETE /v1/certificates/{id}   → cert row gone, NO profile refresh  →  BUG-1
  CH4 expect Invalid  → list: still Active ❌   detail: "Signing certificate revoked" ✅
  CH5 DELETE+POST /v1/profiles       → Active again (regenerate w/ new cert)
```

### Key source anchors

`createCertificate` `ResourcesViewModel.swift:908` · `revokeCertificate` `:948`
· `downloadCertificate` `:983` · `createProfile` `:1882` · `deleteProfile`
`:1940` · `downloadProfile` `:1968` · `fetchProfileDetail` `:1999` ·
`regenerateProfile` `:2038` · `installProfileForXcode` `:2107` ·
`load(_:)` guard `:359` · `profiles` list include `:452` · `dropProfileLocally`
`:2082` · `WriteResult` `:141` · `filteredCertificates` `:267` ·
`filteredProfiles` `:280` · `prependCertificate` `:2290` · `prependProfile`
`:2231` · `certificateStatus` `CertificatesTableView.swift:302` · revoke dialog
`RevokeCertificateDialog.swift:12` · profile status filter
`ProfilesTableView.swift:118` · `computedStatus` `ResourceModels.swift:122` ·
`allowsDevices` `:1065` · `matchesKind` `:480` · `isValidCSR` `:513` ·
`canContinue` `ResourcesView.swift:932` · wizard certificate eligibility `:841`
· `reconcilePicks` `:954` · delete gate `ProfileViews.swift:498` ·
`effectRows` `:504` · regenerate eligibility `:652` · regenerate result
`:1036`.
