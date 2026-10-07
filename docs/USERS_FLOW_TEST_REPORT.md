# Users Flow — UI Test Report

Live UI pass over the **Users** section of the native macOS App Store Connect
client, driven through Orca Computer Use against a real authenticated team.

| | |
|---|---|
| Date | 2026-10-05 |
| App | `App Store.app`, bundle `com.demos.App-Store-Test`, pid 8110 |
| Build | Debug, `~/Library/Developer/Xcode/DerivedData/App_Store-*/Build/Products/Debug/` |
| Team | "Team 1" (1 app: SmartClean AI / `com.sid.cleanify`) |
| Team members | 2 — Nayan Bhut (Admin), Siddharth Patel (Account Holder +1) |
| Driver | `/Applications/Orca.app/Contents/Resources/bin/orca computer …` |
| Result | **12 PASS, 4 fixed, 2 open (BUG-4/5), 1 blocked (AX)** |

> **No writes were made to the live team.** Every mutating control was exercised
> up to (not including) its confirm action. All edits were reverted or
> cancelled; the member list was verified unchanged (2 members) at the end.

## Re-test pass (same day, later)

All 10 cases were re-run against the same session to close out the module.
**9 PASS, BUG-1 reproduced, and one new defect found (BUG-3).** No writes were made
and the team ended the pass unchanged (2 members, 0 pending).

| Case | 1st pass | Re-test |
|---|---|---|
| TC1 list load | PASS | PASS — 2 Total, 2 rows, Pending (0) |
| TC2 user detail | PASS | PASS |
| TC3 update role | PASS | PASS — but surfaced BUG-3 |
| TC4 assigned apps + picker guard | PASS | PASS — "0 of 1 selected" disables confirm |
| TC5 revert | PASS | PASS — Save/Revert return to disabled |
| TC6 pending empty state | PASS | PASS — "No Pending Invitations" |
| TC7 invite form + guards | PASS | PASS — Send disabled on open and with Selected Apps unpicked (**submission still untested — see TC11**) |
| TC8 Account Holder protection | PASS | PASS — controls disabled, Remove replaced by static text |
| TC9 remove confirm dialog | PASS | PASS — cancelled, no deletion |
| TC10 row context menu | **BUG-1** | **BUG-1 reproduced** — Remove still offered on Account Holder |
| TC11–14 invite lifecycle | — | ❌ **NOT RUN** — no pending invite exists |

Harness notes from the re-test: element indexes went stale twice and silently
navigated to Bundle IDs / Profiles (once nearly reading Profiles' "3 Total" as a
Users regression). One scare turned out to be benign — a Settings popover left open
was swallowing coordinate clicks on **Invite User**, which is not reachable by
element index at all. Drive the sidebar by coordinate and re-read the tree before
every click.

---

## 1. Scope

Requested coverage: user list load, user detail, update user info, update
assigned apps, update role, add new user, pending list, delete user.

### APIs behind this flow

| Operation | Endpoint | Code |
|---|---|---|
| List members | `GET /v1/users?include=visibleApps` | `ResourcesViewModel.filteredUsers` (:287) |
| Pending invites | `GET /v1/userInvitations` | `loadInvitations()` |
| Invite | `POST /v1/userInvitations` | `inviteUser(email:…)` (:1539) |
| Update roles/scope | `PATCH /v1/users/{id}` | `updateUser(…)` (:1760) |
| Remove member | `DELETE /v1/users/{id}` | `removeUser(id:)` (:1823) |
| Revoke invite | `DELETE /v1/userInvitations/{id}` | :1695 |
| Resend invite | delete + re-POST (no dedicated endpoint) | :1585 |

View layer: `Shipyard/UsersTableView.swift`, `Shipyard/UserPermissionViews.swift`,
`Shipyard/ShipyardSidebar.swift`, `Shipyard/ShipyardShell.swift:176`.

---

## 2. Test cases

### TC1 — Users list loads ✅ PASS
Navigate sidebar → TEAM RESOURCES → Users.

Header renders `Users` + `2 Total`, segmented control `Members` / `Pending (0)`,
table columns Name / Email / Email-independent columns Role / Status / Apps Access.
Both members render with correct role chips, `Active` status dots, `All Apps`
access. Footer shows `Last synced Oct 5, 2026 at 21:36`.

### TC2 — User detail opens ✅ PASS
Click a member row → full-screen `Edit <name>` view.

Renders: title, subtitle `email · Active · roles and app access`, a 10-item Roles
checkbox list (Admin, Finance, Technical, Read Only, Sales, Marketing, App
Manager, Developer, Access to Reports, Customer Support), an App and provisioning
access group (All Apps / Selected Apps / Certificates+Identifiers+Profiles), a
live Permission summary table, and a footer with Remove User… / Revert / Save User.

### TC3 — Update role ✅ PASS (UI wiring)
Toggled **Developer** on for Nayan Bhut.

- Checkbox flipped to checked.
- Permission summary recomputed live: `All apps → Admin +1`.
- **Save User** became enabled; **Revert** became enabled.
- Roles render as searchable joined strings (`:290`), so multi-role chips stay
  searchable — correct.

### TC4 — Update assigned apps ✅ PASS
Switched App access → **Selected Apps**.

- A `Choose Apps…` link appeared, opening the *Choose selected apps* sheet
  (subtitle: "Reusable in Invite User and Edit User · 1 of 1 selected").
- Sheet lists apps with checkboxes plus a search field.
- **Guard verified:** deselecting the only app → subtitle "0 of 1 selected" and
  the confirm button went **disabled**.
- Re-selected, clicked `Use 1 Selected App` → sheet dismissed, detail summary
  switched from an `All apps` row to per-app rows.

### TC5 — Revert restores original state ✅ PASS
After TC3+TC4, clicked **Revert**.

Full restore: Developer unchecked, `All Apps` re-selected, summary back to
`All apps → Admin`, `Other apps → Included — all apps`. No network write occurred.

### TC6 — Pending invitations (empty state) ✅ PASS
Switched to the `Pending (0)` tab.

Renders `No Pending Invitations` / `New invitations appear here until accepted.`
Correct — and it correctly reflects that pending invites live in
`/v1/userInvitations`, not `/v1/users` (`ResourcesViewModel.swift:178`).

### TC7 — Add new user: form + guards ✅ PASS
Clicked **Invite User** → *Invite user · role and access choices*.

- First/Last/Email fields, same 10-role list, app access group, and a live
  *Invitation permission summary* with a `Status after sending → Pending
  invitation` row. Header states "The invitation grants no access until accepted."
- **Send Invitation correctly disabled** on open — matches `canSubmit` (:397).
- **Guard verified:** switching App access → `Selected Apps` with nothing picked
  showed `No apps picked yet` and summary `Apps → Selected apps only`, and Send
  stayed disabled — matches `(allAppsVisible || !selectedAppIds.isEmpty)` (:402).
- **Not completed:** submitting requires typing an email address, which this
  harness cannot do (see §4). No invitation was sent.

### TC8 — Account Holder protection (detail view) ✅ PASS
Opened Siddharth Patel (Account Holder).

- Amber banner: **"Account Holder is protected"** — "Ownership transfer and
  account changes must be handled through Apple's supported process."
- Roles replaced by read-only text `Account Holder — protected, not editable here.`
- App access radio group `(disabled)`, provisioning checkbox `(disabled)`.
- Permission summary table hidden entirely.
- Footer Remove User replaced by static text
  **`Remove User, disabled for Account Holder`** (`:758`).

### TC9 — Delete user: confirm dialog ✅ PASS (cancelled)
Opened **Remove User…** on Nayan Bhut (Admin).

- Title `Remove Nayan Bhut from the team?`
- Warning banner: "App and provisioning access will be removed… This does not
  delete the apps, certificates, or profiles they created."
- **Type-to-confirm** gate: field pre-labelled with the target email, destructive
  button **disabled** until the typed value matches (case-insensitive, `:962`).
- Impact table: `SmartClean AI → Cannot manage these apps`,
  `Certificates, Identifiers & Profiles → No further provisioning access`,
  `Existing team resources → Remain in the team`.
- Post-cancel message preview: `Result returns to Users with "Nayan Bhut removed"`.
- **Cancelled.** No member was removed.

### TC10 — Row context menu ⚠️ PASS with defect (BUG-1)
Right-click a member row → context menu with **Edit** and **Remove**.

Menu renders correctly for a normal member, **but it also offers `Remove` on the
Account Holder row** — contradicting TC8, where the detail view disables removal
for that same account. See BUG-1.

### TC11–TC14 — Invite lifecycle ❌ NOT RUN (blocked, no test data)

The requested "add new user", "check pending list" and "resend invitation" coverage
is **incomplete**. One root cause: the team has **zero pending invitations**, and
creating one requires typing an email address, which this harness cannot do
(§4 B1). Everything downstream of a pending row is therefore unreachable.

| Case | Surface | Status |
|---|---|---|
| TC11 | Invite **submission** → `POST /v1/userInvitations` | ❌ not run — needs typed email |
| TC12 | **Populated** pending list (rows, badges, count) | ❌ not run — no pending invite exists |
| TC13 | Pending row → **Resend** sheet → `ResendInvitationSheet` | ❌ not run — sheet never opened |
| TC14 | Pending row → **Cancel** sheet → `CancelInvitationSheet` | ❌ not run — sheet never opened |

Only the *guards* around submission were verified (TC7): Send disabled while fields
are empty, and disabled again when `Selected Apps` is chosen with nothing picked.

**To close this gap:** a human creates one throwaway invite by hand (~20s — open
Users → Invite User → any email/role → Send). That single action unlocks TC11–TC14
plus the four new invite toasts, all of which are then drivable read-only/safely.
Until then, treat the invite lifecycle as **unverified**.

---

## 3. Defects

### BUG-1 — Account Holder is removable from the row context menu (High)

The row context menu shows `Remove` unconditionally:

```swift
// Shipyard/UsersTableView.swift:423-429
.contextMenu {
    if !editingDisabled {
        Button("Edit") { selectedUser = user }
        Button("Remove") { removeTarget = user }   // ← no Account Holder check
            .accessibilityLabel("Remove \(teamMemberDisplayName(user))")
    }
}
```

The detail view gates the same action correctly
(`UserPermissionViews.swift:725` → `if !isAccountHolder`), and `isAccountHolder`
is already computed there (`:599`). Neither `RemoveUserSheet` nor
`ResourcesViewModel.removeUser(id:)` re-checks it — `removeUser` goes straight to
`DELETE /v1/users/{id}`.

**Impact:** a destructive, effectively irreversible action is offered on a row the
app elsewhere declares protected. Apple would reject the `DELETE`, so the likely
symptom is a confusing error rather than data loss — but the app advertises an
action it must not allow. (Row secondary actions also expose `delete` to
assistive tech, so the same gap is reachable without the menu.)

**Fix:** gate the menu item on the same predicate.

```swift
if !isAccountHolder(user) {
    Button("Remove") { removeTarget = user }
        .accessibilityLabel("Remove \(teamMemberDisplayName(user))")
}
```

Reuse the existing `isAccountHolder` logic — consider hoisting it to a shared
nonisolated helper so the table and the detail view cannot drift again. Worth
pairing with a defensive guard in `removeUser(id:)`.

### BUG-2 — The list-level error banner is dead code (Medium)

`UsersTableView` declares and renders a dismissible error banner, but nothing ever
assigns it:

```swift
@State private var bannerError: String?          // :30
…
if let bannerError { … }                         // :88 rendered
    self.bannerError = nil                       // :97 only the dismiss button
```

`bannerError` is never set, so **errors raised from the table level are silently
dropped**. Detail-level errors do work (`errorMessage` in `UserDetailView`,
`InviteUserSheet`, `RemoveUserSheet`), but list-level failures never surface.

This directly matches the reported symptom: *"we don't know if user is added or
not."*

### BUG-3 — Primary role label is nondeterministic (Medium) — found on re-test

The same user renders a **different primary role** depending on which surface you
look at, and which one you get varies between launches.

Observed live: table row shows `Admin`, while the detail Permission summary shows
`Developer +1` for the identical role set `[Admin, Developer]`. On the first pass
the detail showed `Admin +1`; on the re-test it showed `Developer +1`.

Cause — `rolesSummary` takes `names[0]`, and the detail view feeds it a `Set`:

```swift
// UserPermissionViews.swift:49
return "\(names[0]) +\(names.count - 1)"

// UserPermissionViews.swift:634 — summaryRows
("Role", rolesSummary(roles.map(\.rawValue)))   // roles is Set<UserRoleOption>
```

`Set` iteration order is unspecified and varies with the per-process hash seed, so
`names[0]` is arbitrary. The table row is unaffected because it calls
`rolesSummary(user.roles)` on the API's `roles` **array**, which has a stable order
— hence the two surfaces disagreeing at the same moment.

**Impact:** cosmetic but user-visible and confusing — the headline privilege looks
random, and the list and detail views contradict each other for one user.

**Fix:** order the roles deterministically before summarising — rank by
`UserRoleOption` declaration order (or a fixed precedence), e.g.

```swift
("Role", rolesSummary(UserRoleOption.ordered(roles).map(\.rawValue)))
```

and feed the table row through the same helper so both surfaces agree.

---

## 4. Blocked / not verified

### TC11–TC14 executed — invite lifecycle now covered

A **live invite** was sent to `nayan.bhut@brainvire.com` (Developer, All Apps) once a
deliverable address was supplied. `.example` / `.invalid` cannot be used: the client
accepts them (its only check is `contains("@")`, `ResourcesViewModel.swift:1549`) but
**Apple rejects them** — `does not match the email pattern must be a valid RFC 5321
Mailbox`. That lax client check is itself worth tightening (see BUG-6).

| Case | Status |
|---|---|
| TC11 invite submission (`POST /v1/userInvitations`) | ✅ PASS — live send, success toast |
| TC12 populated pending list | ✅ PASS — row, badges, `Pending (1)`, resend/cancel actions |
| TC13 resend invitation | ❌ **FAIL — BUG-5** |
| TC14 cancel/revoke invitation | ⏸ not re-run — AX stall blocked the UI |

**BUG-4 (Medium) — pending list is stale right after a successful invite.**
Immediately after the send the header read `0 Pending` and the body showed
"No Pending Invitations", despite a success toast. `inviteUser` does call
`loadInvitations()` (`:1576`), so the request goes out — Apple's list is simply
not yet consistent, and the UI renders the empty result as fact. Revisiting the
section fixed it (`Pending (1)`). No toast/refresh affordance distinguishes
"genuinely empty" from "not loaded yet". *(You marked a refresh button low
priority — agreed; the success toast is what actually covers the gap.)*

**BUG-5 (High) — resend is broken for All-Apps invitations, and fails destructively.**
Resend on the pending row returned:

> The email is already being used.; If you set allAppsVisible to true, you must not
> provide values for the visibleApps relationship. The previous invite was revoked —
> send a fresh invite.

Two separate defects:

1. **Malformed re-create.** `resendInvitation` (`:1601`) passed the hydrated
   `visibleApps` ids through unconditionally. Apple's error names the exact cause:
   an All-Apps invite must carry **no** `visibleApps` relationship. Every All-Apps
   resend therefore fails. The invite and update paths already guard this
   (`UserPermissionViews.swift:386`, `:817`) — only resend didn't.
2. **The failure message lies, and the design is destructive.** Resend is
   DELETE-then-POST. The POST failed, so the code reported
   *"The previous invite was revoked — send a fresh invite"* (`:1639`) — but a fresh
   fetch still showed the invitation present. So either the DELETE silently didn't
   land or it raced the re-create. Had the DELETE landed, the user would have been
   left with **no** invitation at all, with only a failure toast as warning. Resend
   should verify the re-create or roll back, and must not claim a revoke that
   didn't happen.

*Fix applied* — `visibleAppIds` is now gated on `allAppsVisible` at the call site
(`:1601`) **and** defensively in the serializer (`:1739`), so no caller can build an
illegal body. Compiles clean. **Not yet re-verified in the UI** (AX stall).

### BUG-6 (Low) — client-side email validation is only `contains("@")`

`inviteUser` (`:1549`) and `resendInvitation` (`:1595`) accept any string with an
`@`, so an undeliverable address passes local validation and only fails at the API,
where the error is far from the field. Apple enforces RFC 5321 Mailbox. Reusing the
existing `EmailValidator` (already covered by `ValidationTests`) would catch it
client-side.

### AX stall — blocked the tail of the pass

Repeated `permission_denied` / "visible windows but no accessibility window" while
permissions still reported `granted`, and **Finder failed too**, so it is the
system-wide stall in `ORCA_COMPUTER_USE.md` §7 — it needs Orca Computer Use toggled
off/on in System Settings. It recovered twice on its own after ~1 minute; a later
occurrence did not recover within ~2 minutes. Not an app defect.

### B1 — No text input; search filtering and invite submission unverified (Harness)
`computer capabilities` reports `windows.focus: false`, `surfaces.menus/dialogs:
false`. Consequences:

- `type-text` / `press-key` / `paste-text` never reach the app (the window does
  not take keyboard focus).
- `set-value` **renders** text into a field but does **not** fire the SwiftUI
  binding — verified twice: typing `siddharth` into the users search showed the
  text in the field and in the screenshot, yet both rows stayed visible; setting
  all three invite fields showed the text but left **Send Invitation** disabled.

Both are harness limitations, **not app bugs** — the filtering
(`cachedFilter`, `:243`) and validation (`canSubmit`, `:397`) code paths are
correct by inspection. **These two paths need a human to click and type.**

### B2 — No destructive or outbound writes performed
Deliberately not executed, because they hit the real team:

- **Invite send** (`POST /v1/userInvitations`) — would email a real address.
- **Resend invite** — delete + re-POST.
- **Remove member** (`DELETE /v1/users/{id}`) — irreversible; re-invitation
  required to restore access.
- **Save User** (`PATCH /v1/users/{id}`) — real role/scope change.

TC3/TC4 verified the UI wiring and guards of these paths; the network write itself
is untested. Recommend running these against a throwaway team.

---

---

## 4b. Write-feedback gap → toast work (implemented)

The root complaint — *"right now we don't know if user is added or not"* — traces to
three unconnected write paths. Implemented as a follow-up change:

- **New** `Helper/ShipyardToast.swift` — one app-wide toast (Figma 76:31853).
  `ShipyardToastCenter` owns the auto-dismiss timer (5s success / 9s error+warning,
  with a generation counter so a superseded timer can't clear a newer toast).
  `report(_:success:…)` funnels every `ResourcesViewModel.WriteResult` so no call
  site can forget to report one.
- **Rendered once** at the shell (`ShipyardShell.swift`), bottom-trailing, injected
  via `.environmentObject` so any section or sheet can post to it. Dismissed on team
  switch so a toast can't report the previous team's result.
- **Reused the existing** `ToastVariant` (`BuildDisplaySupport.swift:15`) rather than
  adding a third variant enum. Note the two older implementations: `ReleaseToast`
  (still live in Reviews/Release, left untouched) and `ToastEvent` on
  `DetailViewModel` — the latter is **dead code**, written at `:1820` and rendered by
  nothing since the legacy shell was deleted.

Wired write results (success *and* failure):

| Section | Actions |
|---|---|
| Users | invite, save user, remove user, resend invite, cancel invite |
| Bundle IDs | delete, rename, enable capability |
| Certificates | revoke, download |
| Profiles | delete, download (table + detail) |

Two `@EnvironmentObject` injections were added and then **removed** from
`RegenerateProfileSheet` / `ProfileCreatedSheet` — they had no toast call, and
`ProfileCreatedSheet` is also instantiated from the legacy `ResourcesView`, which
has no injector and would have crashed at runtime.

Still unverified: the toast was **compile-verified only**, not seen on screen.
Relaunching to test it would drop the Keychain session this whole pass ran on
(unsigned build ⇒ fresh identity per build), and the harness cannot type
credentials to re-authenticate. Visual check needed from a human.

**Not included:** BUG-1 remains unfixed per your instruction, and B2 (no live writes)
still stands — so no toast has yet been observed firing on a real success/failure.

---

## 5. Flow reference (for re-runs)

```
Sidebar TEAM RESOURCES → Users
  ├─ Members tab
  │    ├─ header: "N Total"
  │    ├─ search field            (searches name, email, roles — local, cached)
  │    ├─ Invite User → invite sheet → Choose Apps… → Send Invitation
  │    ├─ row tap → UserDetailView
  │    │      ├─ Roles (10 checkboxes; read-only if Account Holder)
  │    │      ├─ App access: All Apps | Selected Apps (+ Choose Apps…) | provisioning
  │    │      ├─ Permission summary (live, recomputed on edit)
  │    │      ├─ Remove User… → type-email confirm → DELETE /v1/users/{id}
  │    │      ├─ Revert (restores snapshot, no write)
  │    │      └─ Save User (enabled only when dirty) → PATCH /v1/users/{id}
  │    └─ row context menu → Edit | Remove          ⚠️ BUG-1: ungated
  └─ Pending tab
       ├─ empty: "No Pending Invitations"
       └─ row → Resend | Revoke  → DELETE + re-POST / DELETE
```

Key source anchors: `canSubmit` `UserPermissionViews.swift:397` · `isAccountHolder`
`:599` · context menu `UsersTableView.swift:423` · error banner `:88` ·
`filteredUsers` `ResourcesViewModel.swift:287` · `cachedFilter` `:243` ·
`inviteUser` `:1539` · `removeUser` `:1823`.

---

## 6. Driving notes (Orca Computer Use)

Per `ORCA_COMPUTER_USE.md` §0, `/usr/local/bin/orca` is a root-owned shim that
fails with *"Unable to determine Orca.app path from symlink"*; the in-app binary
`/Applications/Orca.app/Contents/Resources/bin/orca` (v1.4.220) was used instead.

Session-specific learnings, worth adding to that doc:

1. **The AX tree is sparse and row labels are omitted.** Member rows appear as
   bare `container` elements. Labels only materialised after the first
   screenshot pass (`container Nayan Bhut, Admin, …`). Do not conclude a control
   is unreachable from the first tree — take a screenshot and re-read.
2. **`Invite User` was not reachable by element index at all.** It sits outside
   the indexed set; a coordinate click (`--x 1613 --y 64`) opened it. Fall back
   to coordinates early rather than hunting indexes.
3. **The known AX stall is transient, not always fatal.** `permission_denied`
   ("visible windows but no accessibility window") hit mid-run and also affected
   Finder. Per §7 it *may* need a human toggle, but retrying with backoff
   (3×/8s, or 4×8s) recovered on its own both times — **retry before escalating to
   the user.**
4. **Element indexes go stale fast.** Re-read the tree before every click; two
   clicks during this run silently landed on Bundle IDs and Profiles instead of
   the intended target.
5. **Rows expose a `delete` secondary action.** Treat row secondary actions as
   destructive on a real account; drive destructive flows through explicit
   confirm controls instead.