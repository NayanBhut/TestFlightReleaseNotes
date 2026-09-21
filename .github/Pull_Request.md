## 📋 PR Description

Batch E — release-notes quality (#3 + #4 + #5) plus user-reported follow-up fixes.

### What changed?

**#3 — Per-locale completeness view**
- `DetailViewModel.localeCompleteness()`: matrix of all supported locales × builds, each cell showing whether notes exist (✓) or are empty (—)
- `DetailViewModel.completeLocaleCount()`: returns e.g. (6, 8) — locales complete / total
- `BuildDetailsView` header: new **Locales** popover showing the matrix, with completeness count

**#4 — Diff before save**
- `BuildRowView`: **Review changes** button (appears when notes have unsaved changes) opens a diff sheet showing added (green) and removed (red) lines vs the last saved version
- Bulk view: one section **per dirty locale** (computed post-flush from the saved snapshot), so a second edited locale is never hidden behind the selected tab
- On save, `committedText` updates → diff clears on reopen

**#5 — Unified empty/loading/error renderers**
- New `Helper/StateView.swift` with `EmptyStateView`, `LoadingStateView`, `StateErrorView`
- Replaces 3 duplicated `emptyState(icon:title:subtitle:)` functions (BetaGroupView, AppInfoView, ReviewsView)
- Replaces 5 inline loading blocks (AppInfoView.section, ReviewsView ×2, BetaGroupView.loadingState)
- All 3 views now use shared components; deleted local duplicates

**Follow-up fixes (user-reported)**
- **Remove localization**: explicit **× inside each locale tab** (select and remove are sibling buttons, never nested — the earlier right-click menu could present a neighboring tab's entry); confirm alert names the locale; temp drafts drop locally, server notes go through `DELETE /v1/betaBuildLocalizations/{id}` (spec-verified: id-only path param, no body, 204); delete failures surface with kind-routed Retry
- **Per-locale diff baseline**: `DetailViewModel.savedNotes` snapshot (captured on load skipping temp drafts, refreshed on save success) feeds the row baseline via a new `savedWhatsNew` prop — switching locales can no longer launder a draft into "saved"; Review changes + Update now work per locale
- **Update all**: saves every dirty locale with savable text, each on its own save key (hidden when the current tab is the only dirty one); empty text stays Remove-only, mirroring row Update
- **Beta Groups loader**: `LoadingStateView` is a centered VStack again

**Locale correctness (user-reported)**
- `BetaLocalizationLocales.supported` now matches Apple's official 50-language table 1:1 (locale-shortcodes doc): fixes `de`→`de-DE`, `nl`→`nl-NL`, adds `fr-CA` + 11 more (`bn-BD gu-IN kn-IN ml-IN mr-IN or-IN pa-IN sl-SI ta-IN te-IN ur-PK`); this was the `'locale' value is invalid` failure on Update All
- `BetaLocalizationLocales.displayName`: every code maps to Apple's language name (e.g. `de-DE` → German)
- The + menu is now a **searchable picker** (auto-focused search over name + code, rows show `German / de-DE`); names also surface on tab remove tooltips/alerts, Review-changes headers, and the Locales matrix
- Save-error alert prefixes the failing locale, so bulk failures name which locale failed

### Test Scenarios Covered
<!-- Check all that apply -->
- [x] New feature added
- [x] Bug fix
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