## 📋 PR Description

### What changed?

**#3 — Per-locale completeness view**
- `DetailViewModel.localeCompleteness()`: matrix of all supported locales × builds, each cell showing whether notes exist (✓) or are empty (—)
- `DetailViewModel.completeLocaleCount()`: returns e.g. (6, 8) — locales complete / total
- `BuildDetailsView` header: new **Locales** popover showing the matrix, with completeness count

**#4 — Diff before save**
- `BuildRowView`: **Review changes** button (appears when notes have unsaved changes) opens a `DiffView` showing added (green) and removed (red) lines vs the last saved version
- On save, `committedText` updates → diff clears on reopen

**#5 — Unified empty/loading/error renderers**
- New `Helper/StateView.swift` with `EmptyStateView`, `LoadingStateView`, `StateErrorView`
- Replaces 3 duplicated `emptyState(icon:title:subtitle:)` functions (BetaGroupView, AppInfoView, ReviewsView)
- Replaces 5 inline loading blocks (AppInfoView.section, ReviewsView ×2, BetaGroupView.loadingState)
- All 3 views now use shared components; deleted local duplicates

### Test Scenarios Covered
- [x] New feature added
- [x] UI changes
- [x] Swift build passes

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

---

### Follow-up fixes (pushed after initial review)
- **Remove localization**: right-click a locale tab → confirm → temp drafts drop locally, server notes go through `DELETE /v1/betaBuildLocalizations/{id}` (spec-verified: `betaBuildLocalizations_deleteInstance`, id-only path param, no body, 204). Delete failures surface with kind-routed Retry.
- **Diff/Update across locales**: `DetailViewModel.savedNotes` snapshot (captured on load skipping temp drafts, refreshed on save success) feeds the row baseline via a new `savedWhatsNew` prop — switching locales can no longer launder a draft into "saved", so Review changes + Update now work per locale.
- **Beta Groups loader**: `LoadingStateView` is a centered VStack again.

---

### Follow-up fixes, round 2 (user-reported)
- **Remove showed the wrong locale**: the right-click menu could present a neighboring tab's entry — replaced with an explicit **× inside each locale tab** (select and remove are sibling buttons, never nested), so the target is visually unambiguous; the confirm alert still names the locale.
- **Bulk Review + Update all**: Review changes now opens one added/removed section **per dirty locale** (computed post-flush from the saved snapshot), and a new **Update all** button saves every dirty locale (each on its own save key; hidden when the current tab is the only dirty one). Empty text stays Remove-only, mirroring row Update.

---

### Follow-up fixes, round 3 (invalid locale)
- **Wrong locale codes**: `BetaLocalizationLocales.supported` used `de`/`nl`, but Apple only accepts `de-DE`/`nl-NL` (spec leaves `locale` a free string; verified against fastlane's `Deliver::Languages::ALL_LANGUAGES`, which also adds missing `fr-CA`). This was the `'locale' value is invalid` failure on Update All.
- Save-error alert now prefixes the failing locale, so bulk failures name which locale failed.

---

### Language names + search (round 4)
- Apple's official 50-language table (the linked locale-shortcodes doc) confirmed `de-DE`/`nl-NL`/`fr-CA` and added 11 more valid codes (`bn-BD gu-IN kn-IN ml-IN mr-IN or-IN pa-IN sl-SI ta-IN te-IN ur-PK`) — list now matches Apple 1:1.
- `BetaLocalizationLocales.displayName`: every code maps to Apple's language name.
- The + menu is now a searchable picker (auto-focused search over name + code, rows show `German / de-DE`).
- Names surface on tab remove tooltips/alerts, Review-changes headers, and the Locales matrix.
