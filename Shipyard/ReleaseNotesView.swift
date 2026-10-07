//
//  ReleaseNotesView.swift
//  App Store
//
//  TestFlight localizations browser from the testflight-notes-light Figma
//  frame: locale column (search + status rows) beside the per-locale editor
//  (character count, save state, snippet/revert/delete/save). All reads
//  and writes go through DetailViewModel's beta-build-localization APIs.
//  Locale status is text presence only (check vs. circle) — the API
//  exposes no per-locale error state. "Last saved" timestamps don't exist
//  either, so the header reports draft state instead of inventing times.
//

import SwiftUI

/// Apple's per-build whatsNew cap, enforced client-side like the old UI.
private let releaseNotesCharacterLimit = 4000

struct ReleaseNotesView: View {
    @ObservedObject var detailVM: DetailViewModel
    var buildId: String

    @State private var selectedLocale = BetaLocalizationLocales.defaultLocale
    @State private var searchQuery = ""
    /// Working copies keyed by locale; synced from the view model for
    /// locales without an entry yet, never overwritten while typing.
    @State private var drafts: [String: String] = [:]
    @State private var localeSignature = ""
    /// Locales staged by a row-tap (`""` draft, no server call) that the
    /// user never typed into. Viewing away must drop these so they don't
    /// persist as phantom locales (BUG_SWEEP #18); typing into one clears
    /// it from this set.
    @State private var tapStagedLocales: Set<String> = []

    private var locales: [String] {
        detailVM.getAllLocales(for: buildId)
    }

    private var visibleLocales: [String] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return locales }
        // Search the full supported list (not just this build's locales) so
        // a missing language can be found and staged from the same box.
        let matches = { (code: String) in
            code.localizedCaseInsensitiveContains(query)
                || BetaLocalizationLocales.displayName(for: code).localizedCaseInsensitiveContains(query)
        }
        let existing = locales.filter(matches)
        let missing = BetaLocalizationLocales.supported.filter { !locales.contains($0) && matches($0) }
        return existing + missing
    }

    /// Locales staged on this build (have a localization row).
    private func isStaged(_ locale: String) -> Bool {
        locales.contains(locale)
    }

    private func savedText(_ locale: String) -> String {
        detailVM.savedWhatsNew(for: buildId, locale: locale)
    }

    private func isDirty(_ locale: String) -> Bool {
        (drafts[locale] ?? savedText(locale)) != savedText(locale)
    }

    private var dirtyLocales: [String] {
        locales.filter { isDirty($0) }
    }

    var body: some View {
        HStack(spacing: 0) {
            localeColumn
                .frame(width: 280)

            ShipyardTheme.rowDivider
                .frame(width: 1)

            editor
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShipyardTheme.tableBackground)
        .onAppear(perform: syncDrafts)
        .onChange(of: buildId) { _, _ in
            selectedLocale = BetaLocalizationLocales.defaultLocale
            drafts = [:]
            localeSignature = ""
            tapStagedLocales.removeAll()
            syncDrafts()
        }
        .onChange(of: locales) { _, _ in syncDrafts() }
        .onDisappear { dropUntouchedTapStages() }
    }

    /// Drops tap-staged locales the user never typed into. Those are
    /// navigation residue, not intent (BUG_SWEEP #18) — a staged locale
    /// must survive the locale-list change its own staging triggers, so
    /// this runs on navigation (leave / build switch), never from
    /// `syncDrafts()`. Anything the user typed into already left the set
    /// via `draftText.set`.
    private func dropUntouchedTapStages() {
        guard !tapStagedLocales.isEmpty else { return }
        let stages = tapStagedLocales
        tapStagedLocales.removeAll()
        for locale in stages where (drafts[locale] ?? "").isEmpty {
            drafts.removeValue(forKey: locale)
            detailVM.removeLocale(buildId: buildId, locale: locale)
        }
    }

    /// Seeds drafts for locales without one and keeps the selection valid.
    /// Existing keys are never touched, so in-flight typing survives
    /// server refreshes.
    private func syncDrafts() {
        let signature = "\(buildId)|\(locales.joined(separator: ","))"
        guard signature != localeSignature else { return }
        localeSignature = signature
        for locale in locales where drafts[locale] == nil {
            drafts[locale] = detailVM.getWhatsNew(for: buildId, locale: locale)
        }
        if !locales.contains(selectedLocale), let first = locales.first {
            selectedLocale = first
        } else if locales.isEmpty {
            selectedLocale = BetaLocalizationLocales.defaultLocale
        }
    }

    // MARK: - Locale column

    private var localeColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ShipyardIcon(name: "ShipyardSearch", size: 11)
                TextField("Search languages", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(ShipyardTheme.body)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(LaunchTheme.field)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(LaunchTheme.border, lineWidth: 1)
            )
            .padding(10)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visibleLocales, id: \.self) { locale in
                        localeRow(locale)
                    }
                }
                .padding(.horizontal, 8)
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(ShipyardTheme.sidebarBackground)
    }

    private func localeRow(_ locale: String) -> some View {
        let isSelected = locale == selectedLocale
        let staged = isStaged(locale)
        let hasText = !(drafts[locale] ?? savedText(locale)).isEmpty
        return Button {
            if !staged {
                // Stage an empty localization so it joins the build's
                // list; Save persists it to the server. Typed into or
                // saved, it graduates out of the auto-drop set.
                detailVM.updateBuildWhatsNew(buildId: buildId, locale: locale, whatsNew: "")
                drafts[locale] = ""
                tapStagedLocales.insert(locale)
                localeSignature = ""
                syncDrafts()
            }
            selectedLocale = locale
        } label: {
            HStack(spacing: 8) {
                if staged {
                    ShipyardIcon(name: hasText ? "ShipyardCheckSm" : "ShipyardCircleSm", size: 12)
                } else {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.accent)
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                }
                Text(BetaLocalizationLocales.displayName(for: locale))
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
                    .lineLimit(1)
                Spacer()
                Text(locale)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(ShipyardTheme.body)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? ShipyardTheme.selectedRow : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(BetaLocalizationLocales.displayName(for: locale)), \(staged ? (hasText ? "complete" : "empty") : "tap to add")")
    }

    // MARK: - Editor

    private var draftText: Binding<String> {
        Binding(
            get: { drafts[selectedLocale] ?? savedText(selectedLocale) },
            // Clamped so over-limit text can never sit in the draft —
            // matches the legacy BuildRowView prefix(maxLength) behavior
            // and keeps Save reachable (BUG_SWEEP #4). Typing into a
            // tap-staged locale takes it out of the auto-drop set (the
            // user committed real intent — BUG_SWEEP #18).
            set: {
                tapStagedLocales.remove(selectedLocale)
                drafts[selectedLocale] = String($0.prefix(releaseNotesCharacterLimit))
            }
        )
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            editorHeader
                .padding(24)
                .padding(.bottom, 0)

            TextEditor(text: draftText)
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
                .environment(\.layoutDirection, selectedLocaleTextDirection)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LaunchTheme.field)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(LaunchTheme.border, lineWidth: 1)
                )
                .scrollContentBackground(.hidden)
                .padding(24)
                .padding(.top, 12)
                .padding(.bottom, 12)

            editorFooter
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }

    private var editorHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(BetaLocalizationLocales.displayName(for: selectedLocale)) — \(selectedLocale)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                Text("What to Test description for TestFlight beta releases.")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                if !dirtyLocales.isEmpty {
                    Button("Save All (\(dirtyLocales.count))") {
                        saveAll()
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ShipyardTheme.accent)
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(draftText.wrappedValue.count) / \(releaseNotesCharacterLimit) characters")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(ShipyardTheme.body)
                Text(saveStateText)
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
            }
        }
    }

    private var saveStateText: String {
        // Only claim the limit when there's actually something to save —
        // a saved note that happens to be exactly at the cap is "Saved".
        if draftText.wrappedValue.count >= releaseNotesCharacterLimit,
           isDirty(selectedLocale) {
            return "Character limit reached."
        }
        if isDirty(selectedLocale) { return "Unsaved changes" }
        return savedText(selectedLocale).isEmpty ? "No notes yet" : "Saved"
    }

    private var selectedLocaleTextDirection: LayoutDirection {
        BetaLocalizationLocales.isRightToLeft(selectedLocale) ? .rightToLeft : .leftToRight
    }

    private var editorFooter: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(ReleaseNoteSnippets.all, id: \.self) { snippet in
                    Button(snippet.split(separator: "\n").first.map(String.init) ?? "Snippet") {
                        let current = draftText.wrappedValue
                        draftText.wrappedValue = current.isEmpty ? snippet : current + "\n" + snippet
                    }
                }
            } label: {
                footerButtonLabel("Insert Snippet", color: ShipyardTheme.title)
            }
            .menuStyle(.borderlessButton)

            Button("Revert Changes") {
                drafts[selectedLocale] = savedText(selectedLocale)
            }
            .buttonStyle(.plain)
            .foregroundColor(ShipyardTheme.title)
            .font(.system(size: 11))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(LaunchTheme.field)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(LaunchTheme.border, lineWidth: 1)
            )
            .disabled(!isDirty(selectedLocale))

            Button("Delete Localization") {
                detailVM.removeLocale(buildId: buildId, locale: selectedLocale)
                drafts.removeValue(forKey: selectedLocale)
                localeSignature = ""
                syncDrafts()
            }
            .buttonStyle(.plain)
            .foregroundColor(ShipyardTheme.danger)
            .font(.system(size: 11))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(LaunchTheme.field)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(LaunchTheme.border, lineWidth: 1)
            )

            Spacer()

            if detailVM.isBuildUpdating(buildId) {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Button("Save \(BetaLocalizationLocales.displayName(for: selectedLocale))") {
                    save(selectedLocale)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(isDirty(selectedLocale) ? ShipyardTheme.accent : ShipyardTheme.accent.opacity(0.4))
                .cornerRadius(6)
                .buttonStyle(.plain)
                .disabled(!isDirty(selectedLocale))
                .keyboardShortcut(.defaultAction)
            }

            if let error = detailVM.saveError, error.buildId == buildId {
                Text(error.message)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.negative)
                    .lineLimit(2)
            }
        }
    }

    private func footerButtonLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(LaunchTheme.field)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(LaunchTheme.border, lineWidth: 1)
            )
    }

    // MARK: - Writes

    private func save(_ locale: String) {
        let text = drafts[locale] ?? savedText(locale)
        guard text.count <= releaseNotesCharacterLimit else { return }
        detailVM.updateBuildWhatsNew(buildId: buildId, locale: locale, whatsNew: text)
        detailVM.saveBuildLocalization(buildId: buildId, locale: locale)
    }

    private func saveAll() {
        for locale in dirtyLocales {
            save(locale)
        }
    }
}
