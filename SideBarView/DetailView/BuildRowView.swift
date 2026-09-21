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
    let isUpdating: Bool
    let isExpireToggling: Bool

    /// Local editable draft, separate from the last committed (saved) text.
    @State private var whatsNewText: String = ""
    @State private var committedText: String = ""
    @State private var hasChanges: Bool = false
    @State private var showExpireConfirm = false
    @State private var showDiffView = false
    /// Locale awaiting removal confirmation (server-saved notes only —
    /// empty drafts are removed immediately, nothing is lost).
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
        .alert("Remove \(localePendingRemoval ?? "this locale") notes?", isPresented: Binding(
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
                            showDiffView = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .font(.caption)
                        .accessibilityLabel("Review release notes changes")
                        .accessibilityHint("Shows added and removed lines compared to the last saved version")
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
            DiffView(added: diffLines.added, removed: diffLines.removed)
        }
    }

    private var localeTabsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(locales, id: \.self) { locale in
                    Button(action: {
                        // Flush the old locale's pending edit before
                        // switching so keystrokes are never dropped.
                        flushPendingTextChange()
                        onLocaleChange(locale)
                    }) {
                        Text(locale)
                            .font(.caption)
                            .fontWeight(selectedLocale == locale ? .semibold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedLocale == locale ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                            )
                            .foregroundColor(selectedLocale == locale ? .white : .primary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(selectedLocale == locale ? Color.clear : Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        // Removing a mistakenly added locale. Always
                        // confirms — the row only knows the selected
                        // locale's text, so it can't tell an empty draft
                        // from saved notes for the other tabs.
                        Button("Remove \(locale)", role: .destructive) {
                            localePendingRemoval = locale
                        }
                    }
                }

                // Add-locale menu: lists supported locales not yet present.
                // Creates an empty draft; the existing save path POSTs it.
                Menu {
                    ForEach(newLocales, id: \.self) { locale in
                        Button(locale) {
                            // Flush the current locale's pending edit first,
                            // same as switching locale tabs.
                            flushPendingTextChange()
                            onAddLocale(locale)
                        }
                    }
                } label: {
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
                .menuStyle(.borderlessButton)
                .disabled(newLocales.isEmpty)
                .help("Add a locale")
                .accessibilityLabel("Add locale")
            }
            .padding(.horizontal, 4)
        }
    }

    /// Supported locales that don't exist on this build yet.
    private var newLocales: [String] {
        BetaLocalizationLocales.supported.filter { !locales.contains($0) }
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

    /// Line-level diff between the draft and last saved text.
    /// Returns (added, removed) line groups.
    private var diffLines: (added: [String], removed: [String]) {
        let draftLines = whatsNewText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let savedLines = committedText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var added: [String] = []
        var removed: [String] = []
        let savedSet = Set(savedLines)
        let draftSet = Set(draftLines)
        added = draftLines.filter { !savedSet.contains($0) }
        removed = savedLines.filter { !draftSet.contains($0) }
        return (added, removed)
    }
}

// MARK: - Diff view
//
// Shows added (green) and removed (red) lines comparing
// the current draft vs the last saved release notes.
struct DiffView: View {
    let added: [String]
    let removed: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
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
                .padding(8)
            }
            .navigationTitle("Diff")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

