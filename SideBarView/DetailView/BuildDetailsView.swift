//
//  BuildDetailsView.swift
//  App Store
//
//  Created by Nayan Bhut on 05/05/24.
//

import SwiftUI
import AppKit

struct BuildDetailsView: View {
    @ObservedObject var viewModel: DetailViewModel

    var getBuidsData: ((String) -> Void)?
    var setBuidsData: ((String, String, String) -> Void)?
    var refreshBuildList: (() -> Void)?
    var loadMoreBuild: (() -> Void)?

    /// Selected locale per build. The row edits one locale at a time;
    /// the committed text for it is read from the view model.
    @State private var selectedLocales: [String: String] = [:]
    @State private var toastMessage: String? = nil
    @State private var toastWorkItem: DispatchWorkItem? = nil
    @State private var showLocalePopover = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                switch viewModel.buildsState {
                case .idle:
                    // No version selected yet
                    if viewModel.selectedVersion == nil {
                        noVersionSelectedView
                    } else {
                        EmptyView()
                    }
                case .loading:
                    // Full screen loading when fetching builds.
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading builds...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .error(let message):
                    ErrorRetryView(
                        title: "Couldn't Load Builds",
                        message: message,
                        retryTitle: "Retry"
                    ) {
                        viewModel.retryBuilds()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty:
                    if viewModel.selectedVersion == nil {
                        noVersionSelectedView
                    } else {
                        buildsHeader()
                        Divider()
                        noBuildsView
                    }
                case .loaded:
                    if viewModel.selectedVersion == nil {
                        noVersionSelectedView
                    } else {
                        buildsHeader()
                        Divider()
                        // Builds list
                        getBuildsList()

                        // Load more button
                        if viewModel.nextPageCursor != nil {
                            VStack {
                                Divider()
                                Button("Load More Builds") {
                                    loadMoreBuild?()
                                }
                                .buttonStyle(.bordered)
                                .padding(.vertical, 12)
                            }
                        }
                    }
                }
            }

            if let toast = toastMessage {
                VStack {
                    Spacer()
                    ToastView(message: toast)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(), value: toastMessage)
                        .padding(.bottom, 20)
                }
            }
        }
        .onChange(of: viewModel.toast) { _, newToast in
            // Toast events carry identity (UUID), so consecutive identical
            // messages still re-fire — the dismissal timer restarts each time.
            if let newToast {
                showToast(newToast.message)
            }
        }
        // Surface failed release-note saves instead of silently logging them.
        .alert(
            "Couldn't Update Release Notes",
            isPresented: Binding(
                get: { viewModel.saveError != nil },
                set: { if !$0 { viewModel.saveError = nil } }
            ),
            presenting: viewModel.saveError
        ) { saveError in
            Button("Retry") {
                // Retry repeats the failed operation: a failed DELETE
                // must not be retried as a save (or vice versa).
                switch saveError.kind {
                case .save:
                    viewModel.saveBuildLocalization(buildId: saveError.buildId, locale: saveError.locale)
                case .delete:
                    viewModel.removeLocale(buildId: saveError.buildId, locale: saveError.locale)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { saveError in
            Text(saveError.message)
        }
    }

    private var noVersionSelectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.box")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Version Selected")
                .font(.title3)
                .fontWeight(.medium)
            Text("Select a version above to view its builds")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noBuildsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Builds Available")
                .font(.title3)
                .fontWeight(.medium)
            Text("This version doesn't have any builds yet")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func buildsHeader() -> some View {
        HStack {
            Text("Builds")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            if let total = viewModel.meta?.paging.total {
                Text("\(total) total")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            snippetsMenu

            // Locales completeness popover: matrix of locale × build
            // (✓/empty) so missing locales are visible at a glance.
            Button(action: { showLocalePopover = true }) {
                Label("Locales", systemImage: "globe")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showLocalePopover) {
                LocaleCompletenessPopover(
                    completeness: viewModel.localeCompleteness(),
                    builds: viewModel.arrBuilds,
                    completeCount: viewModel.completeLocaleCount()
                )
                .frame(width: 520)
                .padding()
            }

            Button(action: {
                refreshBuildList?()
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.buildsState.isLoading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// Single snippets menu — copies selected text to clipboard
    /// so the user can paste it into any build's release notes.
    private var snippetsMenu: some View {
        Menu {
            ForEach(ReleaseNoteSnippets.all, id: \.self) { snippet in
                Button(ReleaseNoteSnippets.menuLabel(snippet)) {
                    NSPasteboard.general.clear()
                    NSPasteboard.general.setString(snippet, forType: .string)
                }
            }
        } label: {
            Label("Snippets", systemImage: "text.badge.plus")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .help("Copy a snippet to paste into release notes")
    }

    @ViewBuilder private func getBuildsList() -> some View {
        if viewModel.arrBuilds.isEmpty {
            noBuildsView
        } else {
            List(viewModel.arrBuilds, id: \.id) { build in
                buildRow(for: build)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            .listStyle(.plain)
        }
    }

    private func selectedLocale(for build: BuildsModel) -> String {
        let locales = viewModel.getAllLocales(for: build.id)
        if let saved = selectedLocales[build.id], locales.contains(saved) {
            return saved
        }
        return locales.first ?? BetaLocalizationLocales.defaultLocale
    }

    private func buildRow(for build: BuildsModel) -> some View {
        let locale = selectedLocale(for: build)

        return BuildRowView(
            buildId: build.id,
            version: build.version ?? "",
            uploadedDate: build.uploadedDate ?? "",
            processingState: build.processingState ?? "",
            isExpired: build.expired ?? false,
            selectedVersionString: viewModel.selectedVersion?.version ?? "",
            whatsNew: viewModel.getWhatsNew(for: build.id, locale: locale),
            savedWhatsNew: viewModel.savedWhatsNew(for: build.id, locale: locale),
            selectedLocale: locale,
            locales: viewModel.getAllLocales(for: build.id),
            onLocaleChange: { newLocale in
                selectedLocales[build.id] = newLocale
            },
            onTextChange: { newText, textLocale in
                viewModel.updateBuildWhatsNew(buildId: build.id, locale: textLocale, whatsNew: newText)
            },
            onUpdate: { updateLocale in
                viewModel.saveBuildLocalization(buildId: build.id, locale: updateLocale)
            },
            onExpire: {
                viewModel.expireBuild(buildId: build.id)
            },
            onCopyVersionBuildId: {
                viewModel.copyVersionAndBuildId(buildId: build.id)
            },
            onAddLocale: { newLocale in
                // Creates an empty draft localization; the row's existing
                // save path POSTs it once the user types and hits Update.
                viewModel.updateBuildWhatsNew(buildId: build.id, locale: newLocale, whatsNew: "")
                selectedLocales[build.id] = newLocale
            },
            onRemoveLocale: { removeLocale in
                viewModel.removeLocale(buildId: build.id, locale: removeLocale)
                // If the removed tab was selected, fall through to the
                // first remaining locale (selectedLocale(for:) falls back
                // automatically, but clear the stale selection eagerly).
                if selectedLocales[build.id] == removeLocale {
                    selectedLocales[build.id] = nil
                }
            },
            isUpdating: viewModel.isBuildUpdating(build.id),
            isExpireToggling: viewModel.expireTogglingBuildId == build.id
        )
        .padding(.vertical, 4)
    }

    private func showToast(_ message: String) {
        toastWorkItem?.cancel()
        toastMessage = message

        let workItem = DispatchWorkItem {
            withAnimation {
                toastMessage = nil
            }
        }
        toastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }
}

struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .shadow(radius: 4)
    }
}

// MARK: - Shared build display helpers
//
// Single place for upload-date formatting (absolute + relative) and build
// status. Views use these instead of inline closures so formatting stays
// consistent and testable.

enum BuildDisplayHelper {
    private static let iso8601Formatter = ISO8601DateFormatter()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static func uploadedDate(from dateString: String?) -> Date? {
        guard let dateString = dateString, !dateString.isEmpty else { return nil }
        return iso8601Formatter.date(from: dateString)
    }

    /// Single absolute date format used across build rows.
    static func formattedUploadedDate(_ dateString: String?) -> String {
        guard let date = uploadedDate(from: dateString) else { return "" }
        return displayFormatter.string(from: date)
    }

    /// Relative time ("3 days ago") shown next to the absolute date.
    static func relativeUploadedTime(_ dateString: String?) -> String? {
        guard let date = uploadedDate(from: dateString) else { return nil }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func buildStatus(processingState: String, isExpired: Bool) -> (String, Color) {
        if isExpired {
            return ("EXPIRED", .red)
        }

        switch processingState {
        case "PROCESSING":
            return ("PROCESSING", .yellow)
        case "FAILED":
            return ("FAILED", .red)
        case "INVALID":
            return ("INVALID", .orange)
        case "VALID":
            return ("VALID", .green)
        default:
            return ("", .clear)
        }
    }
}

/// Canned release-note starting points — copied to clipboard
/// from a single menu so they can be pasted into any build's
/// release notes.
enum ReleaseNoteSnippets {
    static let all = [
        "Bug fixes and performance improvements",
        "New features:\n- Feature 1\n- Feature 2\n- Feature 3",
        "Bug fixes:\n- Fixed issue with login\n- Fixed crash on startup\n- Improved stability",
        "What's new in this version:\n- Enhanced UI\n- Better performance\n- Security updates",
        "Release notes:\n- Added dark mode support\n- Fixed memory leaks\n- Updated dependencies"
    ]

    /// One-line menu label; ellipsis only when actually truncated.
    static func menuLabel(_ snippet: String) -> String {
        let flattened = snippet.replacingOccurrences(of: "\n", with: " ")
        guard flattened.count > 40 else { return flattened }
        return String(flattened.prefix(40)) + "…"
    }
}

extension BuildsModel {
    var displayStatus: (String, Color) {
        BuildDisplayHelper.buildStatus(
            processingState: processingState ?? "",
            isExpired: expired ?? false
        )
    }

    var formattedUploadedDate: String {
        BuildDisplayHelper.formattedUploadedDate(uploadedDate)
    }

    var relativeUploadedTime: String? {
        BuildDisplayHelper.relativeUploadedTime(uploadedDate)
    }
}

// MARK: - Locales completeness popover
//
// Matrix of locale × build (✓/empty) for the selected version.
// Lets you spot missing locales at a glance — "did I forget fr-FR?"
struct LocaleCompletenessPopover: View {
    let completeness: [(locale: String, builds: [(buildId: String, hasNotes: Bool)])]
    let builds: [BuildsModel]
    let completeCount: (complete: Int, total: Int)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Locales × Builds")
                        .font(.headline)
                    Spacer()
                    Text("\(completeCount.complete)/\(completeCount.total) complete")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if builds.isEmpty {
                    Text("No builds selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(completeness, id: \.locale) { locale, buildStatus in
                        HStack(spacing: 4) {
                            Text(locale)
                                .font(.caption2)
                                .frame(width: 48, alignment: .leading)
                            ForEach(buildStatus, id: \.buildId) { _, hasNotes in
                                Image(systemName: hasNotes ? "checkmark.circle.fill" : "minus.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(hasNotes ? .green : .gray)
                            }
                        }
                    }
                }
            }
            .padding(8)
        }
        .frame(width: 480, height: 300)
    }
}

#Preview {
    BuildDetailsView(viewModel: DetailViewModel(sidebarViewModel: SideBarViewModel()))
}
