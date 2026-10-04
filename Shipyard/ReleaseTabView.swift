//
//  ReleaseTabView.swift
//  App Store
//
//  App Store Versions workspace shell: N1 All Versions list, N2/N3/N4
//  empty/loading/error states, and per-version detail screens routed by
//  Apple version state (01/03/C2 prepare form, 05 waiting, 06 in review,
//  07 pending release, 09 live, R1/R2 resolution, locked states).
//  Drafts live here so the action bar can save them; the prepare form,
//  status screens, and dialogs are separate views.
//

import SwiftUI

// MARK: - Section toolbar state (shared with AppDetailView)

enum ReleaseStatusFilter: String, CaseIterable {
    case all = "All"
    case draft = "Draft"
    case waiting = "Waiting"
    case inReview = "In Review"
    case approved = "Approved"
    case live = "Live"
    case rejected = "Rejected"

    func matches(_ state: String?) -> Bool {
        switch self {
        case .all: return true
        case .draft: return state == "PREPARE_FOR_SUBMISSION"
        case .waiting: return state == "WAITING_FOR_REVIEW" || state == "READY_FOR_REVIEW"
        case .inReview: return state == "IN_REVIEW"
        case .approved: return state == "PENDING_DEVELOPER_RELEASE" || state == "PENDING_APPLE_RELEASE"
        case .live:
            return ["READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "REMOVED_FROM_SALE",
                    "DEVELOPER_REMOVED_FROM_SALE", "REPLACED_WITH_NEW_VERSION"].contains(state ?? "")
        case .rejected:
            return ["REJECTED", "METADATA_REJECTED", "DEVELOPER_REJECTED", "INVALID_BINARY"].contains(state ?? "")
        }
    }
}

@MainActor
final class ReleaseSectionState: ObservableObject {
    @Published var searchText = ""
    @Published var statusFilter: ReleaseStatusFilter = .all
    @Published var newVersionRequested = false
}

// MARK: - Shell

struct ReleaseTabView: View {
    var app: AppsData
    @ObservedObject var reviewsVM: ReviewsViewModel
    @ObservedObject var section: ReleaseSectionState
    var onOpenAppInfo: () -> Void
    var onOpenBuilds: () -> Void

    @Environment(\.openURL) private var openURL

    enum FeatureTab: Hashable {
        case overview, allVersions, resolution, builds
    }

    @State private var featureTab: FeatureTab = .allVersions
    @State private var shownVersionId: String?
    @State private var n1SelectedId: String?
    @State private var draftVersionString = ""
    @State private var draftWhatsNew = ""
    @State private var draftLocaleId: String?
    @State private var draftReleaseType = AppStoreVersionReleaseType.manual
    @State private var draftReleaseDate = Date()
    @State private var draftFirstName = ""
    @State private var draftLastName = ""
    @State private var draftPhone = ""
    @State private var draftEmail = ""
    @State private var draftDemoRequired = false
    @State private var draftDemoUser = ""
    @State private var draftDemoPass = ""
    @State private var draftNotes = ""
    @State private var syncedVersionId: String?
    @State private var lastLocaleDefault: String?
    @State private var lastReviewDefault = ReleaseTabView.emptyReviewJoin
    @State private var saving = false
    @State private var saveError: String?
    @State private var showChooseBuild = false
    @State private var showSubmitDialog = false
    @State private var showCancelDialog = false
    @State private var showReleaseDialog = false
    @State private var showNewVersionSheet = false
    @State private var showRemoveConfirm = false
    @State private var showLoadErrorDetails = false
    @State private var toastTitle: String?
    @State private var toastDetail: String?
    @State private var toastGeneration = 0
    @State private var initialLandingDone = false
    @State private var showStuckRetry = false

    private static let emptyReviewJoin = Array(repeating: "", count: 7).joined(separator: "\u{1F}")

    // MARK: - Version selection

    private var allVersions: [AppStoreVersionsModel] {
        // NOTE: must not read shownVersion here — shownVersion reads
        // allVersions, so that would recurse until the stack blows up.
        let loaded = reviewsVM.appStoreVersionsState.loadedValue ?? []
        let sorted = loaded.sorted {
            ($0.versionString ?? "").localizedStandardCompare($1.versionString ?? "") == .orderedDescending
        }
        let platform = reviewsVM.displayedAppStoreVersion?.platform
            ?? reviewsVM.selectedAppStoreVersionPlatform
        let scoped = platform.map { p in sorted.filter { $0.platform == p } } ?? sorted
        let filtered = (scoped.isEmpty ? sorted : scoped).filter { version in
            let state = version.appStoreState ?? version.appVersionState
            guard section.statusFilter.matches(state) else { return false }
            let query = section.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return (version.versionString ?? "").localizedCaseInsensitiveContains(query)
                || (version.build?.version ?? "").localizedCaseInsensitiveContains(query)
        }
        return filtered
    }

    private var shownVersion: AppStoreVersionsModel? {
        // Resolved from the unfiltered list on purpose: an active
        // search/filter must never yank the open form out from under
        // the user (which would also discard unsaved drafts on resync).
        if let id = shownVersionId,
           let found = reviewsVM.appStoreVersionsState.loadedValue?.first(where: { $0.id == id }) {
            return found
        }
        return reviewsVM.displayedAppStoreVersion
    }

    private var shownState: String? {
        guard let version = shownVersion else { return nil }
        return version.appStoreState ?? version.appVersionState
    }

    /// Editable only when the shown version is the VM-selected pending
    /// version — every write guards on selectedAppStoreVersionId.
    private var canEditShown: Bool {
        guard let version = shownVersion,
              isVersionEditable(appStoreState: shownState),
              reviewsVM.displayedAppStoreVersion?.id == version.id,
              reviewsVM.selectedAppStoreVersionId == version.id else { return false }
        return true
    }

    private var localizations: [AppStoreVersionLocalizationsModel] {
        // The versions list never includes localizations — prefer the
        // dedicated locale fetch once it arrives for the shown version.
        if let id = shownVersion?.id,
           reviewsVM.versionLocalizationsVersionId == id,
           let loaded = reviewsVM.versionLocalizationsState.loadedValue {
            return loaded
        }
        return shownVersion?.appStoreVersionLocalizations ?? []
    }

    private var reviewDetailsValue: AppStoreReviewDetailsModel? {
        guard let id = shownVersion?.id,
              reviewsVM.reviewDetailsVersionId == id else { return nil }
        return reviewsVM.reviewDetailsState.loadedValue
    }

    private var reviewDetailsKnown: Bool {
        guard let id = shownVersion?.id,
              reviewsVM.reviewDetailsVersionId == id else { return false }
        switch reviewsVM.reviewDetailsState {
        case .loading: return false
        default: return true
        }
    }

    /// Changes whenever the shown version or its locale set does.
    private var localeSyncKey: String {
        "\(shownVersion?.id ?? "none")#\(localizations.map(\.id).joined(separator: ","))"
    }

    private var reviewSyncKey: String {
        "\(shownVersion?.id ?? "none")#\(reviewsVM.reviewDetailsVersionId ?? "none")#\(reviewDetailsValue?.id ?? "none")"
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                switch reviewsVM.appStoreVersionsState {
                case .loading, .idle:
                    loadingView
                case .error(let message):
                    loadErrorView(message)
                case .loaded:
                    let versions = allVersions
                    if versions.isEmpty && section.searchText.isEmpty && section.statusFilter == .all {
                        emptyState
                    } else if featureTab == .allVersions {
                        n1List(versions: versions)
                    } else if shownVersion != nil {
                        detailMode
                    } else {
                        n1List(versions: versions)
                    }
                case .empty:
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ShipyardTheme.tableBackground)
            if let title = toastTitle {
                ReleaseToast(title: title, detail: toastDetail ?? "") {
                    toastTitle = nil
                    toastDetail = nil
                }
                .padding(.trailing, 24)
                .padding(.bottom, 72)
            }
        }
        .onAppear {
            reviewsVM.load(app: app)
            if shownVersionId == nil {
                shownVersionId = reviewsVM.displayedAppStoreVersion?.id
            }
            syncDrafts()
            loadPhased()
            loadVersionData()
            if !initialLandingDone {
                initialLandingDone = true
                featureTab = .allVersions
            }
        }
        // App switch while mounted (tap another app, same tab): the view
        // does NOT remount, so without this the old app's versions, drafts
        // and selection stick around and writes could hit the wrong app.
        // A plain struct `app` is correct here (@ObservedObject needs a
        // class) — reactivity comes from reloading on the id change.
        .onChange(of: app.id) { _, _ in
            resetAppScopedState()
            reviewsVM.load(app: app)
            syncDrafts()
            loadPhased()
            loadVersionData()
        }
        .onChange(of: shownVersion?.id) {
            syncDrafts()
            loadPhased()
            loadVersionData()
        }
        .onChange(of: localeSyncKey) {
            adoptLoadedLocales()
        }
        .onChange(of: reviewSyncKey) {
            adoptLoadedReviewDetails()
        }
        .onChange(of: section.newVersionRequested) { _, requested in
            if requested {
                section.newVersionRequested = false
                showNewVersionSheet = true
            }
        }
        .sheet(isPresented: $showChooseBuild) {
            if let version = shownVersion {
                ChooseBuildSheet(version: version, appName: app.name, reviewsVM: reviewsVM) {
                    syncedVersionId = nil
                    syncDrafts()
                }
            }
        }
        .sheet(isPresented: $showSubmitDialog) {
            if let version = shownVersion {
                SubmitReviewDialog(
                    appId: app.id,
                    appName: app.name ?? "this app",
                    version: version,
                    phasedState: reviewsVM.phasedRelease?.phasedReleaseState,
                    reviewsVM: reviewsVM
                ) {
                    reviewsVM.refreshAfterWrite(appId: app.id)
                    showToast(title: "Submitted for review",
                              detail: "\(app.name ?? "App") \(version.versionString ?? "") · Build #\(version.build?.version ?? "—")")
                }
            }
        }
        .sheet(isPresented: $showCancelDialog) {
            if let version = shownVersion {
                CancelSubmissionDialog(
                    appName: app.name ?? "this app",
                    version: version,
                    phasedState: reviewsVM.phasedRelease?.phasedReleaseState,
                    submission: reviewsVM.cancellableSubmission(forPlatform: version.platform),
                    reviewsVM: reviewsVM
                ) {
                    // Never assume the post-cancel state — refetch and
                    // route by whatever Apple returns (usually Prepare).
                    reviewsVM.refreshAfterWrite(appId: app.id)
                    featureTab = .overview
                    showToast(title: "Submission cancelled",
                              detail: "\(app.name ?? "App") \(version.versionString ?? "") · Build #\(version.build?.version ?? "—")")
                }
            }
        }
        .sheet(isPresented: $showReleaseDialog) {
            if let version = shownVersion {
                ReleaseVersionDialog(
                    appName: app.name ?? "this app",
                    version: version,
                    phasedState: reviewsVM.phasedRelease?.phasedReleaseState,
                    reviewsVM: reviewsVM
                ) {
                    reviewsVM.refreshAfterWrite(appId: app.id)
                }
            }
        }
        .sheet(isPresented: $showNewVersionSheet) {
            NewVersionSheet(appId: app.id, reviewsVM: reviewsVM) {
                if let id = reviewsVM.selectedAppStoreVersionId,
                   let created = reviewsVM.appStoreVersionsState.loadedValue?.first(where: { $0.id == id }) {
                    showVersion(created)
                }
            }
        }
        .confirmationDialog(
            "Remove from sale isn’t available through the API. Open this app in App Store Connect to change availability?",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Open in App Store Connect") {
                openASC()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Detail mode

    private var detailMode: some View {
        VStack(spacing: 0) {
            versionHeading
            featureTabs(chips: true)
                .padding(.horizontal, 24)
            Divider()
            if let error = reviewsVM.writeError {
                errorBanner(error) {
                    reviewsVM.writeError = nil
                }
            }
            HStack(alignment: .top, spacing: 0) {
                featureContent
                inspector
            }
            Divider()
            detailActionBar
        }
    }

    private var versionHeading: some View {
        HStack(spacing: 12) {
            Text("Version \(shownVersion?.versionString ?? "—")")
                .font(.system(size: 18))
                .foregroundColor(ShipyardTheme.title)
            ReleaseStatusBadge(state: shownState)
            Spacer(minLength: 0)
            Button("‹ All Versions") {
                featureTab = .allVersions
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(ShipyardTheme.body)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func featureTabs(chips: Bool) -> some View {
        HStack(spacing: 16) {
            featureTabButton(.overview, label: "Overview")
            featureTabButton(.allVersions, label: "All Versions")
            featureTabButton(.resolution, label: "Resolution Center")
            featureTabButton(.builds, label: "Builds")
            if chips {
                Text("│")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.tertiary)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(allVersions, id: \.id) { version in
                            let selected = version.id == shownVersion?.id
                            Button(version.versionString ?? "—") {
                                showVersion(version, tab: featureTab)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: selected ? .semibold : .regular))
                            .foregroundColor(selected ? ShipyardTheme.accent : ShipyardTheme.body)
                        }
                    }
                }
                .frame(height: 20)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
    }

    private func featureTabButton(_ tab: FeatureTab, label: String) -> some View {
        Button(label) {
            if shownVersion == nil, let first = allVersions.first {
                showVersion(first, tab: tab)
            } else {
                featureTab = tab
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: featureTab == tab ? .semibold : .regular))
        .foregroundColor(featureTab == tab ? ShipyardTheme.accent : ShipyardTheme.body)
        .accessibilityLabel(label)
    }

    private func showVersion(_ version: AppStoreVersionsModel, tab: FeatureTab? = nil) {
        if ReviewsViewModel.isPendingApprovalVersion(version) {
            reviewsVM.selectAppStoreVersion(version)
        }
        shownVersionId = version.id
        n1SelectedId = version.id
        featureTab = tab ?? .overview
        syncDrafts()
        loadPhased()
        loadVersionData()
    }

    @ViewBuilder
    private var featureContent: some View {
        switch featureTab {
        case .overview:
            overviewContent
        case .allVersions:
            n1List(versions: allVersions)
        case .resolution:
            resolutionContent
        case .builds:
            versionBuilds
        }
    }

    @ViewBuilder
    private var overviewContent: some View {
        if let version = shownVersion {
            switch shownState {
            case "WAITING_FOR_REVIEW", "READY_FOR_REVIEW":
                TopPinnedScrollView {
                    WaitingVersionView(
                        version: version,
                        localizations: localizations,
                        primaryLocale: app.primaryLocale,
                        reviewsVM: reviewsVM)
                        .padding(24)
                }
            case "IN_REVIEW":
                TopPinnedScrollView {
                    InReviewVersionView(
                        version: version,
                        localizations: localizations,
                        primaryLocale: app.primaryLocale,
                        reviewsVM: reviewsVM)
                        .padding(24)
                }
            case "PENDING_DEVELOPER_RELEASE":
                TopPinnedScrollView {
                    PendingReleaseVersionView(
                        version: version,
                        localizations: localizations,
                        primaryLocale: app.primaryLocale,
                        reviewsVM: reviewsVM)
                        .padding(24)
                }
            case "READY_FOR_SALE", "READY_FOR_DISTRIBUTION",
                 "REMOVED_FROM_SALE", "DEVELOPER_REMOVED_FROM_SALE":
                TopPinnedScrollView {
                    LiveVersionView(
                        version: version,
                        localizations: localizations,
                        primaryLocale: app.primaryLocale,
                        reviewsVM: reviewsVM,
                        removedFromSale: (shownState == "REMOVED_FROM_SALE"
                            || shownState == "DEVELOPER_REMOVED_FROM_SALE"))
                        .padding(24)
                }
            case "REJECTED", "DEVELOPER_REJECTED", "INVALID_BINARY",
                 "METADATA_REJECTED", "PREPARE_FOR_SUBMISSION":
                prepareForm(version)
            default:
                TopPinnedScrollView {
                    LockedVersionView(
                        version: version,
                        localizations: localizations,
                        primaryLocale: app.primaryLocale,
                        reviewsVM: reviewsVM)
                        .padding(24)
                }
            }
        }
    }

    private func prepareForm(_ version: AppStoreVersionsModel) -> some View {
        ReleasePrepareView(
            app: app,
            version: version,
            reviewsVM: reviewsVM,
            localizations: localizations,
            reviewDetails: reviewDetailsValue,
            missingItems: missingItems,
            missingDetail: missingDetail,
            canEdit: canEditShown,
            draftVersionString: $draftVersionString,
            draftWhatsNew: $draftWhatsNew,
            draftLocaleId: $draftLocaleId,
            draftReleaseType: $draftReleaseType,
            draftReleaseDate: $draftReleaseDate,
            draftFirstName: $draftFirstName,
            draftLastName: $draftLastName,
            draftPhone: $draftPhone,
            draftEmail: $draftEmail,
            draftDemoRequired: $draftDemoRequired,
            draftDemoUser: $draftDemoUser,
            draftDemoPass: $draftDemoPass,
            draftNotes: $draftNotes,
            showChooseBuild: $showChooseBuild,
            onOpenAppInfo: onOpenAppInfo)
    }

    @ViewBuilder
    private var resolutionContent: some View {
        if let version = shownVersion,
           shownState == "REJECTED" || shownState == "DEVELOPER_REJECTED"
            || shownState == "INVALID_BINARY" {
            TopPinnedScrollView {
                RejectedThreadView(version: version, kind: .binary, appId: app.id)
                    .padding(24)
            }
        } else if let version = shownVersion, shownState == "METADATA_REJECTED" {
            TopPinnedScrollView {
                RejectedThreadView(version: version, kind: .metadata, appId: app.id)
                    .padding(24)
            }
        } else {
            TopPinnedScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No conversations")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    Text("Rejection messages from App Review appear here. Conversations live in App Store Connect.")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                    Button("Open in App Store Connect") {
                        openASC()
                    }
                    .buttonStyle(.launchSecondary)
                    .padding(.top, 4)
                }
                .padding(24)
            }
        }
    }

    private var versionBuilds: some View {
        TopPinnedScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Builds for version \(shownVersion?.versionString ?? "—")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                if let build = shownVersion?.build {
                    HStack(spacing: 8) {
                        Text("#\(build.version ?? "")")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(ShipyardTheme.title)
                        buildStateBadge(build)
                        Spacer(minLength: 0)
                        Text("Attached")
                            .font(.system(size: 11))
                            .foregroundColor(ShipyardTheme.body)
                    }
                    .padding(10)
                    .background(ShipyardTheme.tableBackground)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(LaunchTheme.border, lineWidth: 1)
                    )
                }
                if canEditShown {
                    Button("Choose a different build") {
                        showChooseBuild = true
                    }
                    .buttonStyle(.launchSecondary)
                    .controlSize(.small)
                }
                Button("Open Builds tab") {
                    onOpenBuilds()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(ShipyardTheme.accent)
            }
            .padding(24)
        }
    }

    private func buildStateBadge(_ build: BuildsModel) -> some View {
        let state = build.processingState ?? ""
        return HStack(spacing: 5) {
            Circle()
                .fill(state == "VALID" ? ShipyardTheme.success : ShipyardTheme.accent)
                .frame(width: 6, height: 6)
            Text(buildStateDisplayName(state))
                .font(.system(size: 10))
                .foregroundColor(ShipyardTheme.title)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(ShipyardTheme.tableHeader)
        .cornerRadius(10)
    }

    // MARK: - Inspector

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("GENERAL INFORMATION")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
            inspectorRow(label: "APP NAME", value: app.name ?? "—")
            inspectorRow(label: "APPLE ID", value: app.id)
            inspectorRow(label: "SKU", value: app.sku ?? "—")
            inspectorRow(label: "PRIMARY LOCALE", value: ReleasePrepareView.localeDisplay(app.primaryLocale))
            ShipyardTheme.rowDivider.frame(height: 1)
            Text("VERSION HISTORY")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
            Text(historyLine)
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.title)
            Text("Prepare → Waiting → In Review → Pending → Ready")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
            Button("View \(app.name ?? "App") Builds ›") {
                onOpenBuilds()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(ShipyardTheme.accent)
            Button("Edit App Info ›") {
                onOpenAppInfo()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(ShipyardTheme.accent)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 224)
        .background(ShipyardTheme.sidebarBackground)
        .overlay(
            ShipyardTheme.rowDivider.frame(width: 1),
            alignment: .leading
        )
    }

    private func inspectorRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(ShipyardTheme.tertiary)
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.title)
        }
    }

    private var historyLine: String {
        guard let version = shownVersion else { return "—" }
        let submitted = releaseDayDisplay(
            reviewsVM.latestSubmission(forPlatform: version.platform)?.submittedDate)
        switch shownState {
        case "PREPARE_FOR_SUBMISSION":
            return "Draft · Created \(releaseDayDisplay(version.createdDate))"
        case "WAITING_FOR_REVIEW", "READY_FOR_REVIEW":
            return "Submitted \(submitted)"
        case "IN_REVIEW":
            return "In Review · submitted \(submitted)"
        case "PENDING_DEVELOPER_RELEASE":
            return "Approved · pending release"
        case "PENDING_APPLE_RELEASE":
            return "Approved · releasing automatically"
        case "READY_FOR_SALE", "READY_FOR_DISTRIBUTION":
            return "Live · \(phasedHistorySuffix)"
        case "REJECTED", "DEVELOPER_REJECTED", "INVALID_BINARY":
            return "Rejected · fix and resubmit"
        case "METADATA_REJECTED":
            return "Metadata rejected · fix and resubmit"
        default:
            return "\(getStatusLabel(appStoreState: shownState)) · Created \(releaseDayDisplay(version.createdDate))"
        }
    }

    private var phasedHistorySuffix: String {
        if let release = reviewsVM.phasedRelease,
           reviewsVM.phasedVersionId == shownVersion?.id {
            return "phased \((release.phasedReleaseState ?? "").lowercased())"
        }
        return "released to all users"
    }

    // MARK: - Action bars

    @ViewBuilder
    private var detailActionBar: some View {
        switch featureTab {
        case .overview:
            overviewActionBar
        case .allVersions:
            n1ActionBar
        case .resolution:
            resolutionActionBar
        case .builds:
            buildsActionBar
        }
    }

    @ViewBuilder
    private var overviewActionBar: some View {
        switch shownState {
        case "WAITING_FOR_REVIEW", "READY_FOR_REVIEW":
            waitingActionBar
        case "IN_REVIEW":
            inReviewActionBar
        case "PENDING_DEVELOPER_RELEASE":
            pendingReleaseActionBar
        case "READY_FOR_SALE", "READY_FOR_DISTRIBUTION",
             "REMOVED_FROM_SALE", "DEVELOPER_REMOVED_FROM_SALE",
             "REPLACED_WITH_NEW_VERSION":
            liveActionBar
        default:
            if canEditShown {
                prepareActionBar
            } else {
                lockedActionBar
            }
        }
    }

    private var prepareActionBar: some View {
        HStack(spacing: 8) {
            Text(actionBarText)
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let error = saveError ?? reviewsVM.releaseSettingsError, canEditShown {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.danger)
            }
            if saving {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Button("Save") {
                    save()
                }
                .buttonStyle(.launchSecondary)
                .disabled(!canEditShown || !isDirty)
            }
            if reviewsVM.submittingReview {
                ProgressView()
                    .scaleEffect(0.7)
            } else if canSubmit {
                Button("Submit for Review") {
                    showSubmitDialog = true
                }
                .buttonStyle(.launchPrimary)
            } else {
                Button("Submit for Review") {
                    showSubmitDialog = true
                }
                .buttonStyle(.launchSecondary)
                .disabled(true)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(ShipyardTheme.tableBackground)
    }

    private var waitingActionBar: some View {
        HStack(spacing: 8) {
            Text("Cancel Submission → Prepare for Submission · Your saved information is retained.")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Edit Info") {
                onOpenAppInfo()
            }
            .buttonStyle(.launchSecondary)
            if let version = shownVersion,
               reviewsVM.cancellableSubmission(forPlatform: version.platform) != nil {
                Button("Cancel Submission") {
                    showCancelDialog = true
                }
                .buttonStyle(.launchDestructive)
            }
            Button("Request Expedited Review") {
                openASC()
            }
            .buttonStyle(.launchSecondary)
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(ShipyardTheme.tableBackground)
    }

    private var inReviewActionBar: some View {
        HStack(spacing: 8) {
            Text("App Review will notify you when the review is complete.")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Message App Review") {
                openASC()
            }
            .buttonStyle(.launchPrimary)
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(ShipyardTheme.tableBackground)
    }

    private var pendingReleaseActionBar: some View {
        HStack(spacing: 8) {
            Text("Release This Version → Ready for Distribution · Phased release will begin.")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            if reviewsVM.releasingVersionId != nil {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Button("Release This Version") {
                    showReleaseDialog = true
                }
                .buttonStyle(.launchPrimary)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(ShipyardTheme.tableBackground)
    }

    private var liveActionBar: some View {
        HStack(spacing: 8) {
            Text("This version is available for distribution.")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            if reviewsVM.canCreateAppStoreVersion {
                Button("Create New Version") {
                    showNewVersionSheet = true
                }
                .buttonStyle(.launchSecondary)
            }
            Button("Remove from Sale") {
                showRemoveConfirm = true
            }
            .buttonStyle(.launchDestructive)
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(ShipyardTheme.tableBackground)
    }

    private var lockedActionBar: some View {
        HStack(spacing: 8) {
            Text("Version is \(getStatusLabel(appStoreState: shownState).lowercased()) — metadata is locked while Apple has it.")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let version = shownVersion,
               reviewsVM.cancellableSubmission(forPlatform: version.platform) != nil {
                Button("Cancel Submission") {
                    showCancelDialog = true
                }
                .buttonStyle(.launchDestructive)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(ShipyardTheme.tableBackground)
    }

    private var resolutionActionBar: some View {
        HStack(spacing: 8) {
            if shownState == "REJECTED" || shownState == "DEVELOPER_REJECTED"
                || shownState == "INVALID_BINARY" {
                Text("Resubmit → Waiting for Review · A new processed build is required.")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Upload New Build and Resubmit") {
                    showChooseBuild = true
                }
                .buttonStyle(.launchPrimary)
            } else if shownState == "METADATA_REJECTED" {
                Text("Edit in App Info, then resubmit → Waiting for Review · No new build needed.")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Edit Metadata and Resubmit") {
                    featureTab = .overview
                }
                .buttonStyle(.launchPrimary)
            } else {
                Text("Rejection messages from App Review appear here.")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Open in App Store Connect") {
                    openASC()
                }
                .buttonStyle(.launchSecondary)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(ShipyardTheme.tableBackground)
    }

    private var buildsActionBar: some View {
        HStack(spacing: 8) {
            Text("Builds for version \(shownVersion?.versionString ?? "—"). Uploads come from Xcode — processed builds can be attached here.")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open Builds tab") {
                onOpenBuilds()
            }
            .buttonStyle(.launchSecondary)
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(ShipyardTheme.tableBackground)
    }

    private var n1ActionBar: some View {
        HStack(spacing: 8) {
            Text("Apps › \(app.name ?? "App") › App Store Versions · Select a version to view its release details.")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("View \(app.name ?? "App") Builds") {
                onOpenBuilds()
            }
            .buttonStyle(.launchSecondary)
            Button("App Info") {
                onOpenAppInfo()
            }
            .buttonStyle(.launchSecondary)
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(ShipyardTheme.tableBackground)
    }

    private var actionBarText: String {
        guard shownVersion != nil else { return "" }
        if !canEditShown {
            return "Version is \(getStatusLabel(appStoreState: shownState).lowercased()) — metadata is locked while Apple has it."
        }
        let missing = missingItems
        if missing.isEmpty {
            return "All required fields complete · Submit → Waiting for Review"
        }
        return "Missing: \(missing.joined(separator: ", "))."
    }

    private var canSubmit: Bool {
        guard canEditShown, missingItems.isEmpty else { return false }
        return reviewsVM.canSubmitForReview
            && reviewsVM.submissionVersion?.id == shownVersion?.id
    }

    // MARK: - N1 All Versions

    private func n1Selected(in versions: [AppStoreVersionsModel]) -> AppStoreVersionsModel? {
        if let id = n1SelectedId, let found = versions.first(where: { $0.id == id }) {
            return found
        }
        return shownVersion ?? versions.first
    }

    private func n1List(versions: [AppStoreVersionsModel]) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("App Store Versions")
                        .font(.system(size: 18))
                        .foregroundColor(ShipyardTheme.title)
                    featureTabs(chips: false)
                }
                Spacer(minLength: 0)
                Text("\(shipyardPlatformDisplay(appStorePlatformLabel)) · \(app.name ?? "App")")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            Divider()
                .padding(.top, 8)
            TopPinnedScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Text(app.name?.prefix(1).uppercased() ?? "A")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(shipyardTileColor(for: app.id))
                            .cornerRadius(6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name ?? "App")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(ShipyardTheme.title)
                            Text("\(app.bundleId ?? "") · \(shipyardPlatformDisplay(appStorePlatformLabel)) · \(ReleasePrepareView.localeDisplay(app.primaryLocale))")
                                .font(.system(size: 11))
                                .foregroundColor(ShipyardTheme.body)
                        }
                        Spacer(minLength: 0)
                        Text("\(versions.count) version\(versions.count == 1 ? "" : "s")")
                            .font(.system(size: 11))
                            .foregroundColor(ShipyardTheme.body)
                    }
                    n1Table(versions: versions)
                    if versions.isEmpty {
                        // Filtered-empty (search/filter), not truly-empty:
                        // offer clearing instead of a bare table.
                        VStack(spacing: 8) {
                            Text("No matching versions")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(ShipyardTheme.title)
                            Text("No versions match the current search or status filter.")
                                .font(.system(size: 12))
                                .foregroundColor(ShipyardTheme.body)
                            Button("Clear search and filters") {
                                section.searchText = ""
                                section.statusFilter = .all
                            }
                            .buttonStyle(.launchSecondary)
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    }
                    if let selected = n1Selected(in: versions) {
                        n1DetailCard(selected)
                    }
                }
                .padding(24)
            }
            Divider()
            n1ActionBar
        }
    }

    private var appStorePlatformLabel: String {
        shownVersion?.platform
            ?? reviewsVM.displayedAppStoreVersion?.platform
            ?? reviewsVM.selectedAppStoreVersionPlatform
            ?? ""
    }

    private func n1Table(versions: [AppStoreVersionsModel]) -> some View {
        let selectedId = n1Selected(in: versions)?.id
        let submissionId = reviewsVM.submissionVersion?.id
        let submissionDate = reviewsVM.submissionVersion?.platform.flatMap { platform in
            reviewsVM.latestSubmission(forPlatform: platform)?.submittedDate
        }
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Version ↓")
                    .frame(width: 90, alignment: .leading)
                Text("Status")
                    .frame(width: 190, alignment: .leading)
                Text("Build")
                    .frame(width: 90, alignment: .leading)
                Text("Submitted")
                    .frame(width: 130, alignment: .leading)
                Text("Released")
                    .frame(width: 130, alignment: .leading)
                Spacer(minLength: 0)
            }
            .font(.system(size: 11))
            .foregroundColor(ShipyardTheme.body)
            .padding(.horizontal, 16)
            .frame(height: 28)
            .background(ShipyardTheme.tableHeader)
            ForEach(versions, id: \.id) { version in
                let state = version.appStoreState ?? version.appVersionState
                let selected = version.id == selectedId
                let submittedText: String = version.id == submissionId ? releaseDayDisplay(submissionDate) : "—"
                Button {
                    n1SelectedId = version.id
                } label: {
                    HStack(spacing: 12) {
                        Text(version.versionString ?? "—")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(ShipyardTheme.title)
                            .frame(width: 90, alignment: .leading)
                        ReleaseStatusBadge(state: state)
                            .frame(width: 190, alignment: .leading)
                        Text(version.build.map { "#\($0.version ?? "")" } ?? "—")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(ShipyardTheme.title)
                            .frame(width: 90, alignment: .leading)
                        Text(submittedText)
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                            .frame(width: 130, alignment: .leading)
                        Text("—")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                            .frame(width: 130, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(selected ? ShipyardTheme.selectedRow : ShipyardTheme.tableBackground)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
                    .background(ShipyardTheme.rowDivider)
            }
        }
        .background(ShipyardTheme.tableBackground)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(LaunchTheme.border, lineWidth: 1)
        )
    }

    private func n1DetailCard(_ version: AppStoreVersionsModel) -> some View {
        let state = version.appStoreState ?? version.appVersionState
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Version \(version.versionString ?? "—")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                Spacer(minLength: 0)
                Button("Open Version ›") {
                    showVersion(version)
                }
                .buttonStyle(.launchPrimary)
                .controlSize(.small)
            }
            Text(n1DetailSubtitle(state))
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
            if let build = version.build {
                Text("Build #\(build.version ?? "—") · \(buildStateDisplayName(build.processingState ?? "")) · Uploaded \(releaseDateTimeDisplay(build.uploadedDate))")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ShipyardTheme.tableBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(LaunchTheme.border, lineWidth: 1)
        )
    }

    private func n1DetailSubtitle(_ state: String?) -> String {
        switch state {
        case "PREPARE_FOR_SUBMISSION":
            return "Continue preparing release notes, App Review information, and release options."
        case "WAITING_FOR_REVIEW", "READY_FOR_REVIEW":
            return "Submitted — waiting for App Review."
        case "IN_REVIEW":
            return "Apple is reviewing this version."
        case "PENDING_DEVELOPER_RELEASE":
            return "Approved — ready for you to release."
        case "REJECTED", "DEVELOPER_REJECTED", "INVALID_BINARY":
            return "Rejected — fix the build and resubmit."
        case "METADATA_REJECTED":
            return "Metadata rejected — fix the metadata and resubmit."
        default:
            return getStatusLabel(appStoreState: state)
        }
    }

    // MARK: - N2/N3/N4

    private var emptyState: some View {
        VStack(spacing: 0) {
            n1HeadingOnly
            Divider()
            VStack(spacing: 12) {
                Spacer()
                VStack(spacing: 8) {
                    Text("No App Store Versions Yet")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    Text("Create an App Store version for \(app.name ?? "this app"), then choose a build and prepare your submission. Your existing TestFlight builds stay in Builds.")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                    HStack(spacing: 12) {
                        Button("New Version") {
                            showNewVersionSheet = true
                        }
                        .buttonStyle(.launchPrimary)
                        Button("View \(app.name ?? "App") Builds") {
                            onOpenBuilds()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ShipyardTheme.accent)
                    }
                    .padding(.top, 4)
                }
                .padding(32)
                .frame(maxWidth: 520)
                .background(ShipyardTheme.tableBackground)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(LaunchTheme.border, lineWidth: 1)
                )
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            n1ActionBar
        }
    }

    private var n1HeadingOnly: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("App Store Versions")
                    .font(.system(size: 18))
                    .foregroundColor(ShipyardTheme.title)
                featureTabs(chips: false)
            }
            Spacer(minLength: 0)
            Text("\(shipyardPlatformDisplay(appStorePlatformLabel)) · \(app.name ?? "App")")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private var loadingView: some View {
        VStack(spacing: 0) {
            n1HeadingOnly
            Divider()
            VStack(spacing: 12) {
                Spacer()
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading versions…")
                            .font(.system(size: 13))
                            .foregroundColor(ShipyardTheme.title)
                    }
                    Text("Syncing \(app.name ?? "the app") with App Store Connect.")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                    if showStuckRetry {
                        Text("This is taking longer than usual.")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                        Button("Retry Connection") {
                            showStuckRetry = false
                            reviewsVM.retryAppStoreVersions()
                        }
                        .buttonStyle(.launchSecondary)
                        .padding(.top, 4)
                    }
                    VStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 6)
                                .fill(ShipyardTheme.tableHeader)
                                .frame(height: 12)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(32)
                .frame(maxWidth: 520)
                .background(ShipyardTheme.tableBackground)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(LaunchTheme.border, lineWidth: 1)
                )
                .task {
                    // Backstop: if a fetch is dropped without settling
                    // (cancelled with no successor), the screen would sit
                    // on the spinner forever with no recourse. Surface a
                    // retry instead of stranding the user. A successful
                    // load after this arms must clear the flag again —
                    // otherwise the next .loading session inherits the old
                    // banner (BUG_SWEEP #27).
                    try? await Task.sleep(nanoseconds: 20_000_000_000)
                    if reviewsVM.appStoreVersionsState.loadedValue == nil {
                        switch reviewsVM.appStoreVersionsState {
                        case .loading, .idle:
                            showStuckRetry = true
                        default:
                            break
                        }
                    }
                }
                .onChange(of: reviewsVM.appStoreVersionsState.loadedValue == nil) { _, stillLoading in
                    if !stillLoading { showStuckRetry = false }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            n1ActionBar
        }
    }

    private func loadErrorView(_ message: String) -> some View {
        VStack(spacing: 0) {
            n1HeadingOnly
            Divider()
            VStack(spacing: 12) {
                Spacer()
                VStack(spacing: 8) {
                    Text("Unable to Load Versions")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    Text("Check your network connection and try again. Your saved drafts have not been changed.")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                    if showLoadErrorDetails {
                        Text(message.isEmpty ? "Unknown error." : message)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(ShipyardTheme.body)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 440)
                    }
                    HStack(spacing: 12) {
                        Button("Retry Connection") {
                            reviewsVM.retryAppStoreVersions()
                        }
                        .buttonStyle(.launchPrimary)
                        Button(showLoadErrorDetails ? "Hide Details" : "Show Details") {
                            showLoadErrorDetails.toggle()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ShipyardTheme.accent)
                    }
                    .padding(.top, 4)
                }
                .padding(32)
                .frame(maxWidth: 520)
                .background(ShipyardTheme.tableBackground)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(LaunchTheme.border, lineWidth: 1)
                )
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            n1ActionBar
        }
    }

    // MARK: - Drafts + save

    /// Server-side scheduled date, parsed once.
    private var serverReleaseDate: Date? {
        guard let raw = shownVersion?.earliestReleaseDate else { return nil }
        return sharedISOFormatter.date(from: raw)
    }

    private var isDirty: Bool {
        guard let version = shownVersion else { return false }
        if draftVersionString != (version.versionString ?? "") { return true }
        let serverReleaseType = AppStoreVersionReleaseType(rawValue: version.releaseType ?? "") ?? .manual
        if draftReleaseType != serverReleaseType { return true }
        // Scheduled was previously always-dirty: every scheduled version
        // re-PATCHed on every Save, never greying out. Compare the date
        // against the server's parsed earliestReleaseDate instead; the
        // one-minute granularity mirrors the DatePicker.
        if draftReleaseType == .scheduled,
           serverReleaseDate == nil || abs(draftReleaseDate.timeIntervalSince(serverReleaseDate!)) > 61 { return true }
        if let loc = draftLocale, draftWhatsNew != (loc.whatsNew ?? "") { return true }
        if let details = reviewDetailsValue, reviewDraftDirty(details) { return true }
        if reviewDetailsValue == nil,
           !(draftFirstName.isEmpty && draftLastName.isEmpty && draftPhone.isEmpty
                && draftEmail.isEmpty && draftDemoUser.isEmpty && draftDemoPass.isEmpty
                && draftNotes.isEmpty && !draftDemoRequired) { return true }
        return false
    }

    private var draftLocale: AppStoreVersionLocalizationsModel? {
        if let id = draftLocaleId {
            return localizations.first { $0.id == id }
        }
        return localizations.first
    }

    private func reviewDraftDirty(_ details: AppStoreReviewDetailsModel) -> Bool {
        if draftFirstName != (details.contactFirstName ?? "") { return true }
        if draftLastName != (details.contactLastName ?? "") { return true }
        if draftPhone != (details.contactPhone ?? "") { return true }
        if draftEmail != (details.contactEmail ?? "") { return true }
        if draftDemoRequired != (details.demoAccountRequired ?? false) { return true }
        if draftDemoUser != (details.demoAccountName ?? "") { return true }
        if !draftDemoPass.isEmpty { return true }
        if draftNotes != (details.notes ?? "") { return true }
        return false
    }

    private var missingItems: [String] {
        guard let version = shownVersion, canEditShown else { return [] }
        var items: [String] = []
        // The draft counts for the selected locale — flagging the model's
        // blank value while the user is typing would never clear.
        let locs = localizations
        if locs.isEmpty {
            items.append("What’s New")
        } else {
            let anyBlank = locs.contains { loc in
                let text = loc.id == draftLocaleId ? draftWhatsNew : (loc.whatsNew ?? "")
                return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if anyBlank {
                items.append("What’s New")
            }
        }
        if version.build == nil {
            items.append("build")
        }
        if draftReleaseType == .scheduled && serverReleaseDate == nil {
            items.append("release date")
        }
        if reviewDetailsKnown {
            if draftFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || draftLastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || draftEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.append("review contact")
            }
        }
        return items
    }

    private var missingDetail: String {
        if localizations.isEmpty {
            return "Add a locale in App Info, then write What’s New."
        }
        return "Add \(missingItems.joined(separator: ", "))."
    }

    /// Clears everything scoped to one app (selection, drafts, toasts,
    /// errors) so an app switch never shows or saves another app's data.
    /// The VM's own reset happens inside reviewsVM.load(app:) when the id
    /// changes; this covers the view's @State the VM can't see.
    private func resetAppScopedState() {
        shownVersionId = nil
        n1SelectedId = nil
        featureTab = .allVersions
        draftVersionString = ""
        draftWhatsNew = ""
        draftLocaleId = nil
        draftReleaseType = AppStoreVersionReleaseType.manual
        draftReleaseDate = Date()
        draftFirstName = ""
        draftLastName = ""
        draftPhone = ""
        draftEmail = ""
        draftDemoRequired = false
        draftDemoUser = ""
        draftDemoPass = ""
        draftNotes = ""
        syncedVersionId = nil
        lastLocaleDefault = nil
        lastReviewDefault = ReleaseTabView.emptyReviewJoin
        saveError = nil
        toastTitle = nil
        toastDetail = nil
    }

    private func syncDrafts() {        guard let version = shownVersion, syncedVersionId != version.id else { return }
        syncedVersionId = version.id
        saveError = nil
        draftVersionString = version.versionString ?? ""
        let preferred = localizations.first { $0.locale == app.primaryLocale } ?? localizations.first
        draftLocaleId = preferred?.id
        draftWhatsNew = preferred?.whatsNew ?? ""
        lastLocaleDefault = draftWhatsNew
        draftReleaseType = AppStoreVersionReleaseType(rawValue: version.releaseType ?? "") ?? .manual
        if let raw = version.earliestReleaseDate,
           let date = sharedISOFormatter.date(from: raw) {
            draftReleaseDate = date
        } else {
            draftReleaseDate = Date()
        }
        syncReviewDrafts()
    }

    private func syncReviewDrafts() {
        let details = reviewDetailsValue
        draftFirstName = details?.contactFirstName ?? ""
        draftLastName = details?.contactLastName ?? ""
        draftPhone = details?.contactPhone ?? ""
        draftEmail = details?.contactEmail ?? ""
        draftDemoRequired = details?.demoAccountRequired ?? false
        draftDemoUser = details?.demoAccountName ?? ""
        draftDemoPass = details?.demoAccountPassword ?? ""
        draftNotes = details?.notes ?? ""
        lastReviewDefault = reviewDraftJoin()
    }

    private func reviewDraftJoin() -> String {
        [draftFirstName, draftLastName, draftPhone, draftEmail,
         draftDemoRequired ? "1" : "0", draftDemoUser, draftNotes]
            .joined(separator: "\u{1F}")
    }

    private func adoptLoadedLocales() {
        let locs = localizations
        if localizations.first(where: { $0.id == draftLocaleId }) == nil {
            let preferred = locs.first { $0.locale == app.primaryLocale } ?? locs.first
            draftLocaleId = preferred?.id
        }
        let currentDefault = draftLocale?.whatsNew ?? ""
        if draftWhatsNew == (lastLocaleDefault ?? "") {
            draftWhatsNew = currentDefault
            lastLocaleDefault = currentDefault
        }
    }

    private func adoptLoadedReviewDetails() {
        guard let details = reviewDetailsValue else { return }
        if reviewDraftJoin() == lastReviewDefault {
            syncReviewDrafts()
        }
    }

    private func loadPhased() {
        guard let version = shownVersion else { return }
        Task {
            await reviewsVM.loadPhasedRelease(versionId: version.id)
        }
    }

    private func loadVersionData() {
        guard let version = shownVersion else { return }
        reviewsVM.loadVersionLocalizations(versionId: version.id)
        reviewsVM.loadReviewDetails(versionId: version.id)
    }

    private func save() {
        guard let version = shownVersion, canEditShown else { return }
        saving = true
        saveError = nil
        Task {
            var ok = true
            // The list can go stale (another client — or the web — moved
            // the version on). A write against a locked version comes
            // back 409, so check the server state first and bail out
            // with the fresh status instead of failing each write.
            if let serverState = await reviewsVM.refreshVersionForSave(versionId: version.id),
               !isVersionEditable(appStoreState: serverState) {
                saveError = "Version is now \(getStatusLabel(appStoreState: serverState).lowercased()) — reloaded the latest status. Your edits are kept below."
                saving = false
                reviewsVM.load(appId: app.id, force: true)
                return
            }
            let versionDirty = draftVersionString != (version.versionString ?? "")
            // Same comparison as isDirty: a scheduled version whose draft
            // date equals the server's is not dirty (BUG_SWEEP #13).
            let serverReleaseType = AppStoreVersionReleaseType(rawValue: version.releaseType ?? "") ?? .manual
            let releaseDirty = draftReleaseType != serverReleaseType
                || (draftReleaseType == .scheduled
                    && (serverReleaseDate == nil
                        || abs(draftReleaseDate.timeIntervalSince(serverReleaseDate!)) > 61))
            if versionDirty || releaseDirty {
                let result = await reviewsVM.saveReleaseSettings(
                    versionId: version.id,
                    releaseType: draftReleaseType,
                    earliestReleaseDate: draftReleaseType == .scheduled ? draftReleaseDate : nil,
                    versionString: versionDirty ? draftVersionString : nil)
                if case .failure(let message) = result {
                    saveError = message
                    ok = false
                }
            }
            if ok, let locId = draftLocaleId ?? draftLocale?.id,
               let loc = localizations.first(where: { $0.id == locId }),
               draftWhatsNew != (loc.whatsNew ?? "") {
                if await reviewsVM.saveVersionWhatsNew(
                    versionId: version.id,
                    localizationId: locId,
                    whatsNew: draftWhatsNew) == false {
                    saveError = reviewsVM.releaseSettingsError ?? "Couldn't save What's New."
                    ok = false
                }
            }
            if ok, reviewDetailsKnown || reviewDetailsValue != nil,
               reviewFormDirty {
                if await reviewsVM.saveReviewDetails(
                    versionId: version.id,
                    firstName: draftFirstName,
                    lastName: draftLastName,
                    phone: draftPhone,
                    email: draftEmail,
                    demoRequired: draftDemoRequired,
                    demoUsername: draftDemoUser,
                    demoPassword: draftDemoPass,
                    notes: draftNotes) == false {
                    saveError = reviewsVM.releaseSettingsError ?? "Couldn't save review information."
                    ok = false
                }
            }
            saving = false
            if ok {
                syncedVersionId = nil
                syncDrafts()
            }
        }
    }

    /// Whether the review-contact form differs from the loaded record
    /// (or has any input when no record exists yet).
    private var reviewFormDirty: Bool {
        if let details = reviewDetailsValue {
            return reviewDraftDirty(details)
        }
        return !(draftFirstName.isEmpty && draftLastName.isEmpty && draftPhone.isEmpty
            && draftEmail.isEmpty && draftDemoUser.isEmpty && draftDemoPass.isEmpty
            && draftNotes.isEmpty && !draftDemoRequired)
    }

    // MARK: - Shared bits

    private func showToast(title: String, detail: String) {
        toastTitle = title
        toastDetail = detail
        toastGeneration += 1
        let generation = toastGeneration
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if generation == toastGeneration {
                toastTitle = nil
                toastDetail = nil
            }
        }
    }

    private func openASC() {
        if let url = URL(string: "https://appstoreconnect.apple.com/apps/\(app.id)") {
            openURL(url)
        }
    }

    private func errorBanner(_ message: String, onDismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppTheme.negative)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.negative)
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(ShipyardTheme.tableBackground)
    }
}
