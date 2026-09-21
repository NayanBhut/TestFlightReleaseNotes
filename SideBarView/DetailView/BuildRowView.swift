//
//  BuildRowView.swift
//  App Store
//
//  Created by Nayan Bhut on 09/12/25.
//

import SwiftUI
import OSLog

private let buildRowLogger = Logger(subsystem: "com.appstore.release-notes", category: "BuildRow")

struct BuildRowView: View {
    let buildId: String
    let version: String
    let uploadedDate: String
    let processingState: String
    let isExpired: Bool
    let selectedVersionString: String
    /// Committed (saved) notes for `selectedLocale`. Keystrokes stay local
    /// until Update; server/fresh values arrive here and are synced in.
    let whatsNew: String
    /// Last-saved notes for `selectedLocale` — the diff baseline. Unlike
    /// `whatsNew` (which carries the live draft once you type), this only
    /// moves on load and on successful save.
    let savedWhatsNew: String
    let selectedLocale: String
    let locales: [String]
    let onLocaleChange: (String) -> Void
    let onTextChange: (String, String) -> Void
    let onUpdate: (String) -> Void
    let onExpire: () -> Void
    let onCopyVersionBuildId: () -> Void
    let onAddLocale: (String) -> Void
    /// Removes a locale's notes (temp drafts locally, server ones via DELETE).
    let onRemoveLocale: (String) -> Void
    /// Number of locales with unsaved changes, computed from the view
    /// model so it covers the other tabs too — drives "Update all".
    let dirtyLocaleCount: Int
    /// Fresh per-locale diffs for every dirty locale, evaluated on tap
    /// (after flushing) so Review changes never shows a stale snapshot.
    let onFetchDiffs: () -> [LocaleDiff]
    /// Saves every dirty locale with savable text.
    let onUpdateAll: () -> Void
    let isUpdating: Bool
    let isExpireToggling: Bool

    /// Local editable draft, separate from the last committed (saved) text.
    @State private var whatsNewText: String = ""
    @State private var committedText: String = ""
    @State private var hasChanges: Bool = false
    @State private var showExpireConfirm = false
    @State private var showDiffView = false
    @State private var showAddLocale = false
    /// Diffs snapshot for the review sheet, computed on tap (post-flush).
    @State private var reviewDiffs: [LocaleDiff] = []
    /// Locale awaiting removal confirmation. Always confirms — the ×
    /// sits on the tab so the target is unambiguous, and the alert
    /// names the locale as a second check.
    @State private var localePendingRemoval: String?
    @State private var debounceTask: Task<Void, Never>?

    /// Debounce interval for propagating keystrokes to the view model.
    private static let debounceNanoseconds: UInt64 = 400_000_000

    /// App Store Connect caps beta release notes at 4000 characters.
    private let maxLength = WhatsNewLimits.maxLength

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerView
            localeTabsView
            textEditorView
        }
        .padding(.vertical, 4)
        .alert("Remove \(localePendingRemoval.map { localeLabel($0) } ?? "this locale") notes?", isPresented: Binding(
            get: { localePendingRemoval != nil },
            set: { if !$0 { localePendingRemoval = nil } }
        )) {
            Button("Cancel", role: .cancel) { localePendingRemoval = nil }
            Button("Remove", role: .destructive) {
                if let locale = localePendingRemoval {
                    removeLocale(locale)
                }
                localePendingRemoval = nil
            }
        } message: {
            Text("The release notes for this locale will be deleted. This cannot be undone.")
        }
    }

    private var headerView: some View {
        HStack {
            Text("\(selectedVersionString)(\(version))")
                .font(.headline)

            Text(BuildDisplayHelper.formattedUploadedDate(uploadedDate))
                .font(.subheadline)
                .foregroundColor(.secondary)

            if let relative = BuildDisplayHelper.relativeUploadedTime(uploadedDate) {
                Text("· \(relative)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            let status = BuildDisplayHelper.buildStatus(
                processingState: processingState,
                isExpired: isExpired
            )
            if !status.0.isEmpty {
                Text(status.0)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(status.1.opacity(0.2))
                    .foregroundColor(status.1)
                    .cornerRadius(4)
            }

            Spacer()

            if isUpdating {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                HStack(spacing: 8) {
                    if hasChanges {
                        Button("Review changes") {
                            // Flush first so a just-typed line is in the
                            // view model before the diffs are computed.
                            flushPendingTextChange()
                            reviewDiffs = onFetchDiffs()
                            showDiffView = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .font(.caption)
                        .accessibilityLabel("Review release notes changes")
                        .accessibilityHint("Shows added and removed lines compared to the last saved version")
                    }
                    // Bulk save across locales. Hidden when the current tab
                    // is the only dirty locale (per-locale Update covers it).
                    if dirtyLocaleCount > 0 && (dirtyLocaleCount > 1 || !hasChanges) {
                        Button("Update all") {
                            flushPendingTextChange()
                            committedText = whatsNewText
                            hasChanges = false
                            showDiffView = false
                            buildRowLogger.debug("Saving all release notes for build \(buildId)")
                            onUpdateAll()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .font(.caption)
                        .accessibilityLabel("Update all locales with unsaved changes")
                    }
                    Button("Update") {
                        // Flush any pending debounced edit first so the view
                        // model (and therefore the save request) sees the
                        // latest text - not the last debounced value.
                        flushPendingTextChange()
                        committedText = whatsNewText
                        hasChanges = false
                        showDiffView = false
                        buildRowLogger.debug("Saving release notes for build \(buildId)")
                        onUpdate(selectedLocale)
                    }
                    .disabled(!hasChanges || whatsNewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    // Note: no keyboard shortcut here — one per list would resolve
                    // to the first row's button and save the wrong build.
                }
            }

            Button(action: onCopyVersionBuildId) {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Copy version and build ID")
            .accessibilityLabel("Copy version and build ID")

            // There is no unexpire API (PATCH expired=false returns 409),
            // so expired builds offer no toggle.
            if !isExpired {
                Button(action: { showExpireConfirm = true }) {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isExpireToggling)
                .help("Expire build")
                .accessibilityLabel("Expire build")
                .alert("Expire this build?", isPresented: $showExpireConfirm) {
                    Button("Cancel", role: .cancel) { }
                    Button("Expire", role: .destructive) {
                        onExpire()
                    }
                } message: {
                    Text("Testers will no longer be able to install this build. This cannot be undone.")
                }
            }
        }
        .sheet(isPresented: $showDiffView) {
            LocaleDiffsView(diffs: reviewDiffs)
        }
    }

    private var localeTabsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(locales, id: \.self) { locale in
                    // Select and remove are sibling buttons, never nested:
                    // the × sits inside its own tab so the removal target
                    // is visually unambiguous. Removal always confirms.
                    HStack(spacing: 0) {
                        Button(action: {
                            // Flush the old locale's pending edit before
                            // switching so keystrokes are never dropped.
                            flushPendingTextChange()
                            onLocaleChange(locale)
                        }) {
                            Text(locale)
                                .font(.caption)
                                .fontWeight(selectedLocale == locale ? .semibold : .regular)
                                .padding(.leading, 12)
                                .padding(.trailing, 4)
                                .padding(.vertical, 6)
                                .foregroundColor(selectedLocale == locale ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                        Button(action: {
                            localePendingRemoval = locale
                        }) {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(selectedLocale == locale ? .white.opacity(0.85) : .secondary)
                                .padding(6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Remove \(localeLabel(locale)) notes")
                        .accessibilityLabel("Remove \(localeLabel(locale)) notes")
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedLocale == locale ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(selectedLocale == locale ? Color.clear : Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }

                // Add-locale picker: searchable list with Apple's language
                // names (raw codes like "cs" aren't guessable). Creates an
                // empty draft; the existing save path POSTs it.
                Button(action: { showAddLocale = true }) {
                    Image(systemName: "plus")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(newLocales.isEmpty)
                .help("Add a locale")
                .accessibilityLabel("Add locale")
                .popover(isPresented: $showAddLocale) {
                    AddLocaleView(locales: newLocales) { locale in
                        // Flush the current locale's pending edit first,
                        // same as switching locale tabs.
                        flushPendingTextChange()
                        onAddLocale(locale)
                    }
                    .frame(width: 280, height: 340)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    /// Supported locales that don't exist on this build yet.
    private var newLocales: [String] {
        BetaLocalizationLocales.supported.filter { !locales.contains($0) }
    }

    /// "German (de-DE)" for display; the bare code when the name is unknown.
    private func localeLabel(_ locale: String) -> String {
        let name = BetaLocalizationLocales.displayName(for: locale)
        return name == locale ? locale : "\(name) (\(locale))"
    }

    private var textEditorView: some View {
        TextEditor(text: $whatsNewText)
            .font(.body)
            .frame(minHeight: 100, maxHeight: 150)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(hasChanges ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: hasChanges ? 2 : 1)
            )
            .scrollContentBackground(.hidden)
            .onChange(of: whatsNewText) { _, newValue in
                if newValue.count > maxLength {
                    whatsNewText = String(newValue.prefix(maxLength))
                    return
                }
                hasChanges = newValue != committedText
                scheduleDebouncedTextChange(newValue, locale: selectedLocale)
            }
            .onChange(of: whatsNew) { _, newValue in
                // Sync the draft when the parent provides a genuinely new
                // value (different locale, fresh load, or server update).
                // Echoes of our own draft (newValue == whatsNewText)
                // are ignored so typing never clears hasChanges.
                // NOTE: committedText is deliberately NOT touched here —
                // the baseline comes only from savedWhatsNew (load/save),
                // so a draft propagated to the view model can never
                // launder itself into "saved" when switching locales.
                guard newValue != whatsNewText else { return }
                buildRowLogger.debug("Syncing release notes draft for build \(buildId)")
                whatsNewText = newValue
                hasChanges = newValue != committedText
            }
            .onChange(of: savedWhatsNew) { _, newValue in
                // The saved baseline moves on load and on successful save.
                committedText = newValue
                hasChanges = whatsNewText != committedText
            }
            .onChange(of: selectedLocale) { _, _ in
                // The parent re-renders with the new locale's draft +
                // baseline right after onLocaleChange; the syncs above
                // pick them up. Recompute here in case they arrive unchanged.
                hasChanges = whatsNewText != committedText
            }
            .onAppear {
                whatsNewText = whatsNew
                committedText = savedWhatsNew
                hasChanges = whatsNewText != committedText
            }
            .onDisappear {
                // Flush instead of just cancelling: a pending edit must
                // not be silently dropped when the row scrolls off-screen
                // or the version changes.
                flushPendingTextChange()
            }
    }

    /// Immediately propagate any pending (debounced) text change to the
    /// view model, cancelling the debounce timer.
    private func flushPendingTextChange() {
        debounceTask?.cancel()
        debounceTask = nil
        if hasChanges, whatsNewText != committedText {
            onTextChange(whatsNewText, selectedLocale)
        }
    }

    /// Removes a locale tab. Flushes the current draft first so a pending
    /// edit on the selected locale isn't silently dropped, then routes to
    /// the view model (which drops temp drafts locally and DELETEs
    /// server-persisted localizations).
    private func removeLocale(_ locale: String) {
        flushPendingTextChange()
        showDiffView = false
        onRemoveLocale(locale)
    }

    private func scheduleDebouncedTextChange(_ newValue: String, locale: String) {
        debounceTask?.cancel()
        // @MainActor: BuildRowView is a plain struct, so the Task would
        // otherwise inherit no actor and could call onTextChange off the
        // main thread (mutating @Published state from a background thread).
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.debounceNanoseconds)
            guard !Task.isCancelled else { return }
            onTextChange(newValue, locale)
        }
    }

}

// MARK: - Diff views

/// One locale's added/removed lines vs its last-saved notes.
/// Produced by the view model across every dirty locale so bulk
/// Review changes never hides a second edited locale behind the
/// selected tab.
struct LocaleDiff: Equatable {
    let locale: String
    let added: [String]
    let removed: [String]
}

/// Added (green) / removed (red) line groups for one locale's diff.
struct DiffLinesView: View {
    let added: [String]
    let removed: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if added.isEmpty && removed.isEmpty {
                Label("No changes", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                if !removed.isEmpty {
                    Text("Removed")
                        .font(.headline)
                    ForEach(removed, id: \.self) { line in
                        Text("\u{2212} " + line)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal, 8)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                if !added.isEmpty {
                    Text("Added")
                        .font(.headline)
                    ForEach(added, id: \.self) { line in
                        Text("+ \(line)")
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
        }
    }
}

/// Bulk "Review changes" sheet: one section per dirty locale, so a
/// second edited locale's changes are never hidden behind the
/// selected tab.
struct LocaleDiffsView: View {
    let diffs: [LocaleDiff]
    @Environment(\.dismiss) private var dismiss

    /// "German (de-DE)"; bare code when the name is unknown.
    static func header(for locale: String) -> String {
        let name = BetaLocalizationLocales.displayName(for: locale)
        return name == locale ? locale : "\(name) (\(locale))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if diffs.isEmpty {
                        Label("No changes", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(diffs, id: \.locale) { diff in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(Self.header(for: diff.locale))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                DiffLinesView(added: diff.added, removed: diff.removed)
                            }
                            if diff.locale != diffs.last?.locale {
                                Divider()
                            }
                        }
                    }
                }
                .padding(8)
            }
            .navigationTitle("Review changes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Add-locale picker

/// Searchable list of locales not yet on this build. Shows Apple's
/// language names — raw codes like "cs" or "zh-Hans" aren't guessable —
/// and filters on both name and code as you type.
struct AddLocaleView: View {
    let locales: [String]
    let onSelect: (String) -> Void
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var filtered: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return locales }
        let q = query.lowercased()
        return locales.filter {
            $0.lowercased().contains(q)
            || BetaLocalizationLocales.displayName(for: $0).lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search languages\u{2026}", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .focused($searchFocused)
                .onAppear { searchFocused = true }
            if filtered.isEmpty {
                Text("No languages match \"\(searchText)\".")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filtered, id: \.self) { locale in
                            Button(action: {
                                onSelect(locale)
                                dismiss()
                            }) {
                                HStack {
                                    Text(BetaLocalizationLocales.displayName(for: locale))
                                        .font(.subheadline)
                                    Spacer()
                                    Text(locale)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(10)
    }
}

