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
    let selectedLocale: String
    let locales: [String]
    let onLocaleChange: (String) -> Void
    let onTextChange: (String, String) -> Void
    let onUpdate: (String) -> Void
    let onToggleExpire: () -> Void
    let onCopyVersionBuildId: () -> Void
    let isUpdating: Bool
    let isExpireToggling: Bool

    /// Local editable draft, separate from the last committed (saved) text.
    @State private var whatsNewText: String = ""
    @State private var committedText: String = ""
    @State private var hasChanges: Bool = false
    @State private var showExpireConfirm = false
    @State private var debounceTask: Task<Void, Never>?

    /// Debounce interval for propagating keystrokes to the view model.
    private static let debounceNanoseconds: UInt64 = 400_000_000

    /// App Store Connect caps beta release notes at 4000 characters.
    private let maxLength = 4000

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerView
            localeTabsView
            textEditorView
            characterCounterView
        }
        .padding(.vertical, 4)
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
                Button("Update") {
                    // Flush any pending debounced edit first so the view
                    // model (and therefore the save request) sees the
                    // latest text - not the last debounced value.
                    flushPendingTextChange()
                    committedText = whatsNewText
                    hasChanges = false
                    buildRowLogger.debug("Saving release notes for build \(buildId)")
                    onUpdate(selectedLocale)
                }
                .disabled(!hasChanges || whatsNewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }

            Button(action: onCopyVersionBuildId) {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Copy version and build ID")

            // There is no unexpire API (PATCH expired=false returns 409),
            // so expired builds offer no toggle.
            if !isExpired {
                Button(action: { showExpireConfirm = true }) {
                    Image(systemName: "circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isExpireToggling)
                .help("Expire build")
                .alert("Expire this build?", isPresented: $showExpireConfirm) {
                    Button("Cancel", role: .cancel) { }
                    Button("Expire", role: .destructive) {
                        onToggleExpire()
                    }
                } message: {
                    Text("Testers will no longer be able to install this build. This cannot be undone.")
                }
            }
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
                }
            }
            .padding(.horizontal, 4)
        }
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
                // Sync when the parent provides a genuinely new value
                // (different locale, fresh load, or server update).
                // Echoes of our own draft (newValue == whatsNewText)
                // are ignored so typing never clears hasChanges.
                guard newValue != whatsNewText else { return }
                buildRowLogger.debug("Syncing release notes draft for build \(buildId)")
                whatsNewText = newValue
                committedText = newValue
                hasChanges = false
            }
            .onChange(of: selectedLocale) { _, _ in
                // The parent re-renders with the new locale's committed
                // text right after onLocaleChange; the whatsNew sync above
                // picks it up. Reset here in case it arrives unchanged.
                hasChanges = whatsNewText != committedText
            }
            .onAppear {
                whatsNewText = whatsNew
                committedText = whatsNew
                hasChanges = false
            }
            .onDisappear {
                // Flush instead of just cancelling: a pending edit must
                // not be silently dropped when the row scrolls off-screen
                // or the version changes.
                flushPendingTextChange()
            }
    }

    private var characterCounterView: some View {
        HStack {
            Spacer()
            Text("\(whatsNewText.count)/\(maxLength)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
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
