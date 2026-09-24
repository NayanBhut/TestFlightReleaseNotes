//
//  BuildDetailsView.swift
//  App Store
//
//  Created by Nayan Bhut on 05/05/24.
//

import SwiftUI
import OSLog

private let buildDetailsLogger = Logger(subsystem: "com.appstore.release-notes", category: "BuildDetails")

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
                    // Skeleton placeholders keep the layout stable while
                    // fetching, instead of a lone spinner.
                    BuildSkeletonList()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .transition(.opacity)
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
            // Name the failing locale: with Update all saving several
            // locales, the server detail alone ("The 'locale' value is
            // invalid.") doesn't say which one failed.
            Text("\(saveError.locale): \(saveError.message)")
        }
    }

    private var noVersionSelectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.box")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
                .emptyStateIconAppear()
            Text("No Version Selected")
                .font(.subheader)
                .fontWeight(.medium)
            Text("Select a version above to view its builds")
                .font(.appBody)
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
                .emptyStateIconAppear()
            Text("No Builds Available")
                .font(.subheader)
                .fontWeight(.medium)
            Text("This version doesn't have any builds yet")
                .font(.appBody)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func buildsHeader() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Builds")
                    .font(.sectionHeader)
                    .fontWeight(.semibold)

                Spacer()

                if let total = viewModel.meta?.paging.total {
                    Text("\(total) total")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                        .contentTransition(.numericText())
                }

                snippetsMenu

                openInASCMenu

                // Locales completeness popover: matrix of locale × build
                // (✓/empty) so missing locales are visible at a glance.
                Button(action: { showLocalePopover = true }) {
                    Label("Locales", systemImage: "globe")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showLocalePopover) {
                    LocaleCompletenessPopover(
                        completeness: viewModel.localeCompleteness(),
                        builds: viewModel.arrBuilds,
                        completeCount: viewModel.completeLocaleCount()
                    )
                    .frame(width: 500)
                    .padding()
                }

                Button(action: {
                    refreshBuildList?()
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.appCaption)
                        .rotationEffect(.degrees(viewModel.buildsState.isLoading ? 360 : 0))
                        .animation(
                            viewModel.buildsState.isLoading
                                ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                                : .default,
                            value: viewModel.buildsState.isLoading
                        )
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.buildsState.isLoading)
            }

            // Live status distribution for the loaded builds.
            buildStatsStrip
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(AppTheme.secondaryBackground)
    }

    /// Live counts by build status. Pure derivation from `arrBuilds` —
    /// no stored copies to keep in sync.
    private var buildStatsStrip: some View {
        let stats = BuildStats.compute(viewModel.arrBuilds.map {
            BuildStatusInput(processingState: $0.processingState, expired: $0.expired ?? false)
        })

        return HStack(spacing: 12) {
            if stats.valid > 0 {
                statPill(count: stats.valid, label: "valid", color: .green)
            }
            if stats.processing > 0 {
                statPill(count: stats.processing, label: "processing", color: .yellow)
            }
            if stats.failed > 0 {
                statPill(count: stats.failed, label: "failed", color: .red)
            }
            if stats.expired > 0 {
                statPill(count: stats.expired, label: "expired", color: .orange)
            }
            if stats.total == 0 {
                Text("No builds loaded")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: stats)
    }

    private func statPill(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(count) \(label)")
                .font(.appCaption)
                .foregroundColor(.secondary)
                .contentTransition(.numericText())
        }
        .transition(.scale.combined(with: .opacity))
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
                .font(.appCaption)
                .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .help("Copy a snippet to paste into release notes")
    }

    /// Batch F (#9): TestFlight feedback (crashes, screenshots) and
    /// in-app events have no public ASC API — open the app's page in the
    /// browser instead of leaving the user to hunt for it.
    private var openInASCMenu: some View {
        Menu {
            ForEach(ASCDeepLink.allCases) { link in
                Button {
                    guard let appId = viewModel.selectedApp?.id else { return }
                    guard let url = link.url(appId: appId) else {
                        // A nil URL means a malformed app id — never expected
                        // with numeric ASC ids, but a dead button shouldn't
                        // be a mystery (review finding).
                        buildDetailsLogger.error("Couldn't build \(link.title, privacy: .public) URL for app id \(appId, privacy: .public)")
                        return
                    }
                    if !NSWorkspace.shared.open(url) {
                        // No default browser / handler registered.
                        buildDetailsLogger.error("No application could open \(url.absoluteString, privacy: .public)")
                    }
                } label: {
                    Label(link.title, systemImage: link.systemImage)
                }
            }
        } label: {
            Label("Open in App Store Connect", systemImage: "safari")
                .font(.appCaption)
                .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        // The ASC SPA routes client-side per app id — without a selected
        // app there is nothing meaningful to open. Disabling the whole menu
        // communicates the state more clearly than three grayed items
        // behind an opening menu (review finding).
         .disabled(viewModel.selectedApp == nil)
         .help("Open this app in App Store Connect (browser)")
         .accessibilityLabel("Open in App Store Connect")
     }

     @ViewBuilder private func getBuildsList() -> some View {
         if viewModel.arrBuilds.isEmpty {
             noBuildsView
         } else {
             // Staggered entrance: index-based delay, no array copy.
             List(Array(zip(viewModel.arrBuilds.indices, viewModel.arrBuilds)), id: \.1.id) { index, build in
                 buildRow(for: build, entranceOffset: BuildListAnimation.staggerDelay(forRow: index))
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

    private func buildRow(for build: BuildsModel, entranceOffset: Double = 0) -> some View {
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
            dirtyLocaleCount: viewModel.dirtyLocales(for: build.id).count,
            onFetchDiffs: { viewModel.dirtyDiffs(for: build.id) },
            onUpdateAll: { viewModel.saveAllLocales(buildId: build.id) },
            isUpdating: viewModel.isBuildUpdating(build.id),
            isExpireToggling: viewModel.expireTogglingBuildId == build.id,
            entranceOffset: entranceOffset
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
            .font(.appCaption)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppTheme.secondaryBackground)
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

// MARK: - Build stats + list animation math
//
// Pure, UI-free helpers behind the builds header strip and the staggered
// row entrance. Kept separate from the views so unit tests can cover them
// without hosting SwiftUI.

/// Minimal build status projection for counting. Decouples `BuildStats`
/// from `BuildsModel` (whose macro-generated inits are awkward in tests).
struct BuildStatusInput {
    var processingState: String?
    var expired: Bool
}

/// Status-bucket counts for the builds header strip. Expired wins over
/// processingState, mirroring `BuildDisplayHelper.buildStatus` above.
struct BuildStats: Equatable {
    var valid = 0
    var processing = 0
    var failed = 0
    var expired = 0

    var total: Int { valid + processing + failed + expired }

    static func compute(_ inputs: [BuildStatusInput]) -> BuildStats {
        var stats = BuildStats()
        for input in inputs {
            if input.expired {
                stats.expired += 1
            } else {
                switch input.processingState {
                case "PROCESSING":
                    stats.processing += 1
                case "FAILED", "INVALID":
                    stats.failed += 1
                default:
                    // VALID, unknown, or missing states all read as shippable.
                    stats.valid += 1
                }
            }
        }
        return stats
    }
}

/// Entrance-animation timing for the builds list.
enum BuildListAnimation {
    /// Stagger delay for a row index. Capped so long lists don't cascade.
    static func staggerDelay(forRow index: Int, step: Double = 0.05, max maxDelay: Double = 0.5) -> Double {
        min(Double(max(index, 0)) * step, maxDelay)
    }
}

/// Batch F (#9): deep links into the App Store Connect web app for
/// sections the public API can't serve in-app. Routes are those of the
/// ASC web SPA; the testflight/crashes and testflight/screenshots paths
/// are the ones production TestFlight-feedback tooling links to.
enum ASCDeepLink: CaseIterable, Identifiable {
    case screenshots
    case crashes
    case inAppEvents

    var id: Self { self }

    var title: String {
        switch self {
        case .screenshots: return "Screenshots"
        case .crashes: return "Crashes"
        case .inAppEvents: return "In-App Events"
        }
    }

    var systemImage: String {
        switch self {
        case .screenshots: return "camera.viewfinder"
        case .crashes: return "exclamationmark.triangle"
        case .inAppEvents: return "calendar.badge.clock"
        }
    }

    /// TestFlight feedback lives under /testflight; in-app events use the
    /// camelCase resource route like other app-level ASC sections. Built
    /// via URLComponents so an unexpected app id gets percent-encoded
    /// (or rejected as nil) instead of interpolating into a malformed URL
    /// (review finding).
    func url(appId: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "appstoreconnect.apple.com"
        components.path = "/apps/\(appId)\(pathSuffix)"
        return components.url
    }

    private var pathSuffix: String {
        switch self {
        case .screenshots: return "/testflight/screenshots"
        case .crashes: return "/testflight/crashes"
        case .inAppEvents: return "/inAppEvents"
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
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Locales × Builds")
                        .font(.subheader)
                    Spacer()
                    Text("\(completeCount.complete)/\(completeCount.total) complete")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                }
                if builds.isEmpty {
                    Text("No builds selected")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(completeness, id: \.locale) { locale, buildStatus in
                        HStack(spacing: 4) {
                            Text(locale)
                                .font(.appCaption2)
                                .frame(width: 52, alignment: .leading)
                            Text(BetaLocalizationLocales.displayName(for: locale))
                                .font(.appCaption2)
                                .foregroundColor(.secondary)
                                .frame(width: 140, alignment: .leading)
                                .lineLimit(1)
                            ForEach(buildStatus, id: \.buildId) { _, hasNotes in
                                Image(systemName: hasNotes ? "checkmark.circle.fill" : "minus.circle.fill")
                                    .font(.appCaption)
                                    .foregroundColor(hasNotes ? .green : .gray)
                            }
                        }
                    }
                }
            }
            .padding(8)
        }
        .frame(width: 500, height: 300)
    }
}

#Preview {
    BuildDetailsView(viewModel: DetailViewModel(sidebarViewModel: SideBarViewModel()))
}

/// Shimmer skeleton shown while builds load. Purely presentational:
/// gray bars with a sweeping highlight, no data dependencies.
private struct BuildSkeletonList: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    BuildSkeletonRow()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollDisabled(true)
        .accessibilityLabel("Loading builds")
    }
}

private struct BuildSkeletonRow: View {
    @State private var sweep: CGFloat = -0.7

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(AppTheme.tertiaryBackground)
                .frame(width: 200, height: 18)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(AppTheme.tertiaryBackground)
                .frame(height: 60)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(AppTheme.tertiaryBackground)
                .frame(width: 140, height: 12)
                .opacity(0.7)
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
        .overlay {
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                LinearGradient(
                    gradient: Gradient(colors: [.clear, AppTheme.primaryText.opacity(0.08), .clear]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: width * 0.55)
                .offset(x: -width * 0.55 + sweep * width * 1.6)
            }
            .mask(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .onAppear {
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                sweep = 1
            }
        }
    }
}
