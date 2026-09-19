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
    let whatsNew: String
    let localizationId: String?
    let selectedVersionString: String
    let onTextChange: (String) -> Void
    let onUpdate: () -> Void
    let isUpdating: Bool

    /// Local editable draft, separate from the last committed (saved) text.
    @State private var whatsNewText: String = ""
    @State private var committedText: String = ""
    @State private var hasChanges: Bool = false
    @State private var debounceTask: Task<Void, Never>?

    /// Debounce interval for propagating keystrokes to the view model.
    private static let debounceNanoseconds: UInt64 = 400_000_000

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                        .scaleEffect(0.8)
                } else {
                    Button("Update") {
                        // Flush any pending debounced edit first so the view
                        // model (and therefore the save request) sees the
                        // latest text - not the last debounced value.
                        flushPendingTextChange()
                        committedText = whatsNewText
                        hasChanges = false
                        buildRowLogger.debug("Saving release notes for build \(buildId)")
                        onUpdate()
                    }
                    .disabled(!hasChanges || whatsNewText.isEmpty)
                }
            }

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
                    hasChanges = newValue != committedText
                    scheduleDebouncedTextChange(newValue)
                }
                .onChange(of: whatsNew) { _, newValue in
                    // Sync when the parent provides a genuinely new value
                    // (different build, fresh load, or server update).
                    // Echoes of our own draft (newValue == whatsNewText)
                    // are ignored so typing never clears hasChanges.
                    guard newValue != whatsNewText else { return }
                    buildRowLogger.debug("Syncing release notes draft for build \(buildId)")
                    whatsNewText = newValue
                    committedText = newValue
                    hasChanges = false
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
        .padding(.vertical, 4)
    }

    /// Immediately propagate any pending (debounced) text change to the
    /// view model, cancelling the debounce timer.
    private func flushPendingTextChange() {
        debounceTask?.cancel()
        debounceTask = nil
        if hasChanges, whatsNewText != committedText {
            onTextChange(whatsNewText)
        }
    }

    private func scheduleDebouncedTextChange(_ newValue: String) {
        debounceTask?.cancel()
        // @MainActor: BuildRowView is a plain struct, so the Task would
        // otherwise inherit no actor and could call onTextChange off the
        // main thread (mutating @Published state from a background thread).
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.debounceNanoseconds)
            guard !Task.isCancelled else { return }
            onTextChange(newValue)
        }
    }
}
