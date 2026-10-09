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

enum ReleaseSubmissionRequirements {
    static let priorReleaseStates: Set<String> = [
        "READY_FOR_SALE",
        "READY_FOR_DISTRIBUTION",
        "REMOVED_FROM_SALE",
        "DEVELOPER_REMOVED_FROM_SALE",
        "REPLACED_WITH_NEW_VERSION"
    ]

    static func requiresWhatsNew(for version: AppStoreVersionsModel?,
                                 allVersions: [AppStoreVersionsModel]) -> Bool {
        guard let version else { return true }
        let platform = version.platform
        return allVersions.contains { candidate in
            guard candidate.id != version.id else { return false }
            if let platform, candidate.platform != platform { return false }
            let state = candidate.appStoreState ?? candidate.appVersionState ?? ""
            return priorReleaseStates.contains(state)
        }
    }

    static func missingItems(canEdit: Bool,
                             hasLocalizations: Bool,
                             hasBlankWhatsNew: Bool,
                             requiresWhatsNew: Bool,
                             hasBuild: Bool,
                             isScheduledRelease: Bool,
                             hasSavedScheduledReleaseDate: Bool,
                             reviewDetailsKnown: Bool,
                             firstName: String,
                             lastName: String,
                             phone: String,
                             email: String,
                             demoRequired: Bool,
                             demoUsername: String,
                             demoPassword: String) -> [String] {
        guard canEdit else { return [] }
        var items: [String] = []
        if requiresWhatsNew && (!hasLocalizations || hasBlankWhatsNew) {
            items.append("What’s New")
        }
        if !hasBuild {
            items.append("build")
        }
        if isScheduledRelease && !hasSavedScheduledReleaseDate {
            items.append("saved release date")
        }
        if reviewDetailsKnown {
            let contactFields = [firstName, lastName, phone, email]
            if contactFields.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                items.append("review contact")
            }
            if demoRequired {
                let demoFields = [demoUsername, demoPassword]
                if demoFields.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    items.append("demo credentials")
                }
            }
        }
        return items
    }

    static func canSubmit(canEdit: Bool,
                          missingItems: [String],
                          isDirty: Bool,
                          isSaving: Bool,
                          canSubmitForReview: Bool,
                          submissionMatchesShownVersion: Bool) -> Bool {
        canEdit
            && missingItems.isEmpty
            && !isDirty
            && !isSaving
            && canSubmitForReview
            && submissionMatchesShownVersion
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
    @ObservedObject var detailVM: DetailViewModel
    @ObservedObject var reviewsVM: ReviewsViewModel
    @ObservedObject var section: ReleaseSectionState
    var onOpenAppInfo: () -> Void
    var onOpenBuilds: () -> Void

    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var toastCenter: ShipyardToastCenter

    enum FeatureTab: Hashable {
        case overview, allVersions, resolution
    }

    @State private var featureTab: FeatureTab = .overview
    @State private var shownVersionId: String?
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

    private var reviewStatusSyncing: Bool {
        reviewsVM.reviewStatusSyncState.isSyncing
            && reviewsVM.reviewStatusSyncState.belongs(to: shownVersion?.id)
    }

    private var reviewStatusDelayed: Bool {
        reviewsVM.reviewStatusSyncState.isDelayed
            && reviewsVM.reviewStatusSyncState.belongs(to: shownVersion?.id)
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

    private var requiresWhatsNew: Bool {
        ReleaseSubmissionRequirements.requiresWhatsNew(
            for: shownVersion,
            allVersions: reviewsVM.appStoreVersionsState.loadedValue ?? [])
    }

    private var versionSwitcherVersions: [AppStoreVersionsModel] {
        if featureTab == .overview {
            return overviewSwitcherVersions
        }
        return allVersions
    }

    private var overviewSwitcherVersions: [AppStoreVersionsModel] {
        let appStoreVisibleVersions = Array(reviewsVM.displayedAppStoreVersions.prefix(2))
        if let shownVersion,
           appStoreVisibleVersions.contains(where: { $0.id == shownVersion.id }) == false {
            return [shownVersion]
        }
        return appStoreVisibleVersions
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
                featureTab = .overview
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
                    submission: reviewsVM.cancellableSubmission(for: version),
                    reviewsVM: reviewsVM
                ) {
                    // cancelSubmission refreshes the version and routes the
                    // UI by whatever Apple returns (usually Prepare).
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
            versionSwitcher()
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
            Button {
                featureTab = .allVersions
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Versions")
                        .font(.system(size: 12))
                }
                .foregroundColor(ShipyardTheme.body)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to App Store Versions list")

            ShipyardTheme.rowDivider
                .frame(width: 1, height: 20)

            Text("Version \(shownVersion?.versionString ?? "—")")
                .font(.system(size: 18))
                .foregroundColor(ShipyardTheme.title)
            ReleaseStatusBadge(state: shownState)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func versionSwitcher() -> some View {
        HStack(spacing: 16) {
            let switcherVersions = versionSwitcherVersions
            if !switcherVersions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(switcherVersions, id: \.id) { version in
                            let selected = version.id == shownVersion?.id
                            Button(version.versionString ?? "—") {
                                showVersion(version, tab: featureTab)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("review.version.\(version.id)")
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

    private func showVersion(_ version: AppStoreVersionsModel, tab: FeatureTab? = nil) {
        if ReviewsViewModel.isPendingApprovalVersion(version) {
            reviewsVM.selectAppStoreVersion(version)
        }
        shownVersionId = version.id
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
                        detailVM: detailVM,
                        localizations: localizations,
                        primaryLocale: app.primaryLocale,
                        reviewsVM: reviewsVM)
                        .padding(24)
                }
            case "IN_REVIEW":
                TopPinnedScrollView {
                    InReviewVersionView(
                        version: version,
                        detailVM: detailVM,
                        localizations: localizations,
                        primaryLocale: app.primaryLocale,
                        reviewsVM: reviewsVM)
                        .padding(24)
                }
            case "PENDING_DEVELOPER_RELEASE":
                TopPinnedScrollView {
                    PendingReleaseVersionView(
                        version: version,
                        detailVM: detailVM,
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
                        detailVM: detailVM,
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
                        detailVM: detailVM,
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
            requiresWhatsNew: requiresWhatsNew,
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
            reviewsVM.latestSubmission(for: version)?.submittedDate)
        switch shownState {
        case "PREPARE_FOR_SUBMISSION":
            return "Draft · Created \(releaseDayDisplay(version.createdDate))"
        case "READY_FOR_REVIEW":
            return "Added to draft submission"
        case "WAITING_FOR_REVIEW":
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
        }
    }

    @ViewBuilder
    private var overviewActionBar: some View {
        if reviewStatusSyncing || reviewStatusDelayed {
            prepareActionBar
        } else {
            switch shownState {
            case "WAITING_FOR_REVIEW", "READY_FOR_REVIEW":
                waitingActionBar
            case "IN_REVIEW":
                inReviewActionBar
            case "PENDING_DEVELOPER_RELEASE":
                pendingReleaseActionBar
            case "PENDING_APPLE_RELEASE":
                scheduledReleaseActionBar
            case "READY_FOR_SALE", "READY_FOR_DISTRIBUTION":
                liveActionBar
            case "REMOVED_FROM_SALE", "DEVELOPER_REMOVED_FROM_SALE":
                removedFromSaleActionBar
            default:
                if canEditShown {
                    prepareActionBar
                } else {
                    lockedActionBar
                }
            }
        }
    }

    private var prepareActionBar: some View {
        HStack(spacing: 8) {
            Text(actionBarText)
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let error = saveError ?? reviewsVM.releaseSettingsError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.danger)
            }
            if reviewStatusSyncing {
                ProgressView()
                    .scaleEffect(0.7)
                    .accessibilityIdentifier("review.sync.progress")
                Text("Updating status…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ShipyardTheme.body)
            } else if reviewStatusDelayed {
                Button("Check Again") {
                    guard let versionId = shownVersion?.id else { return }
                    reviewsVM.retryReviewStatusSync(appId: app.id, versionId: versionId)
                }
                .buttonStyle(.launchPrimary)
                .accessibilityIdentifier("review.sync.retry")
                Button("Dismiss") {
                    guard let versionId = shownVersion?.id else { return }
                    reviewsVM.dismissReviewStatusSync(versionId: versionId)
                }
                .buttonStyle(.launchSecondary)
                .accessibilityIdentifier("review.sync.dismiss")
            } else {
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
                    .accessibilityIdentifier("review.submit")
                } else {
                    Button("Submit for Review") {
                        showSubmitDialog = true
                    }
                    .buttonStyle(.launchSecondary)
                    .disabled(true)
                    .accessibilityIdentifier("review.submit")
                }
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
               reviewsVM.cancellableSubmission(for: version) != nil {
                Button("Remove from Review") {
                    showCancelDialog = true
                }
                .buttonStyle(.launchDestructive)
                .accessibilityIdentifier("review.cancel")
            }
            Button("Request Expedited Review") {
                openExpeditedReview()
            }
            .buttonStyle(.launchSecondary)
            .accessibilityIdentifier("review.expedite")
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
            .accessibilityIdentifier("review.message-app-review")
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
                .accessibilityIdentifier("review.release")
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(ShipyardTheme.tableBackground)
    }

    private var scheduledReleaseActionBar: some View {
        HStack(spacing: 8) {
            Text("This approved version is scheduled for automatic release.")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Manage Release Schedule") {
                openASC()
            }
            .buttonStyle(.launchSecondary)
            .accessibilityIdentifier("review.manage-schedule")
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
                .accessibilityIdentifier("review.create-version")
            }
            Button("Remove from Sale") {
                showRemoveConfirm = true
            }
            .buttonStyle(.launchDestructive)
            .accessibilityIdentifier("review.remove-from-sale")
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(ShipyardTheme.tableBackground)
    }

    private var removedFromSaleActionBar: some View {
        HStack(spacing: 8) {
            Text("This version is not available for distribution.")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Manage Availability") {
                openASC()
            }
            .buttonStyle(.launchSecondary)
            .accessibilityIdentifier("review.manage-availability")
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
               reviewsVM.cancellableSubmission(for: version) != nil {
                Button("Remove from Review") {
                    showCancelDialog = true
                }
                .buttonStyle(.launchDestructive)
                .accessibilityIdentifier("review.cancel")
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
        if reviewStatusSyncing {
            return "Submission accepted · Waiting for App Store Connect to update the review status."
        }
        if reviewStatusDelayed {
            return "Submission accepted · The review status is taking longer than expected to update."
        }
        if !canEditShown {
            return "Version is \(getStatusLabel(appStoreState: shownState).lowercased()) — metadata is locked while Apple has it."
        }
        let missing = missingItems
        if missing.isEmpty {
            if saving {
                return "Saving changes… Submit will unlock after App Store Connect confirms them."
            }
            if isDirty {
                return "Save changes to continue · Submit uses the last saved App Store Connect data."
            }
            return "All required fields complete · Submit → Waiting for Review"
        }
        return "Missing: \(missing.joined(separator: ", "))."
    }

    private var canSubmit: Bool {
        return ReleaseSubmissionRequirements.canSubmit(
            canEdit: canEditShown,
            missingItems: missingItems,
            isDirty: isDirty,
            isSaving: saving,
            canSubmitForReview: reviewsVM.canSubmitForReview,
            submissionMatchesShownVersion: reviewsVM.submissionVersion?.id == shownVersion?.id)
    }

    // MARK: - N1 All Versions

    private func n1List(versions: [AppStoreVersionsModel]) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("App Store Versions")
                        .font(.system(size: 18))
                        .foregroundColor(ShipyardTheme.title)
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
        let selectedId = shownVersion?.id
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
                let submittedText = releaseDayDisplay(
                    reviewsVM.latestSubmission(for: version)?.submittedDate)
                Button {
                    showVersion(version)
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
        if requiresWhatsNew, let loc = draftLocale, draftWhatsNew != (loc.whatsNew ?? "") { return true }
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
        if draftDemoPass != (details.demoAccountPassword ?? "") { return true }
        if draftNotes != (details.notes ?? "") { return true }
        return false
    }

    private var missingItems: [String] {
        let locs = localizations
        // The draft counts for the selected locale — flagging the model's
        // blank value while the user is typing would never clear.
        let hasBlankWhatsNew = locs.contains { loc in
            let text = loc.id == draftLocaleId ? draftWhatsNew : (loc.whatsNew ?? "")
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return ReleaseSubmissionRequirements.missingItems(
            canEdit: canEditShown,
            hasLocalizations: !locs.isEmpty,
            hasBlankWhatsNew: hasBlankWhatsNew,
            requiresWhatsNew: requiresWhatsNew,
            hasBuild: shownVersion?.build != nil,
            isScheduledRelease: draftReleaseType == .scheduled,
            hasSavedScheduledReleaseDate: serverReleaseDate != nil,
            reviewDetailsKnown: reviewDetailsKnown,
            firstName: draftFirstName,
            lastName: draftLastName,
            phone: draftPhone,
            email: draftEmail,
            demoRequired: draftDemoRequired,
            demoUsername: draftDemoUser,
            demoPassword: draftDemoPass)
    }

    private var missingDetail: String {
        if requiresWhatsNew && localizations.isEmpty {
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
        featureTab = .overview
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
        guard reviewDetailsValue != nil else { return }
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
        detailVM.loadAppInfo()
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
                let message = "Version is now \(getStatusLabel(appStoreState: serverState).lowercased()) — reloaded the latest status. Your edits are kept below."
                saveError = message
                toastCenter.show("Couldn't save submission", detail: message, variant: .warning)
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
                    toastCenter.show("Couldn't save release settings", detail: message, variant: .error)
                    ok = false
                }
            }
            if ok, requiresWhatsNew,
               let locId = draftLocaleId ?? draftLocale?.id,
               let loc = localizations.first(where: { $0.id == locId }),
               draftWhatsNew != (loc.whatsNew ?? "") {
                if await reviewsVM.saveVersionWhatsNew(
                    versionId: version.id,
                    localizationId: locId,
                    whatsNew: draftWhatsNew) == false {
                    let message = reviewsVM.releaseSettingsError ?? "Couldn't save What's New."
                    saveError = message
                    toastCenter.show("Couldn't save What's New", detail: message, variant: .error)
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
                    let message = reviewsVM.releaseSettingsError ?? "Couldn't save review information."
                    saveError = message
                    toastCenter.show("Couldn't save review information", detail: message, variant: .error)
                    ok = false
                }
            }
            saving = false
            if ok {
                syncedVersionId = nil
                syncDrafts()
                toastCenter.show("Submission info saved", detail: "\(app.name ?? "App") \(version.versionString ?? "")", variant: .success)
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
        toastCenter.show(title, detail: detail, variant: .success)
    }

    private func openASC() {
        if let url = URL(string: "https://appstoreconnect.apple.com/apps/\(app.id)") {
            openURL(url)
        }
    }

    private func openExpeditedReview() {
        if let url = URL(string: "https://developer.apple.com/contact/app-store/?topic=expedite") {
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
