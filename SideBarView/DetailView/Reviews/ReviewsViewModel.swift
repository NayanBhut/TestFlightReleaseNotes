//
//  ReviewsViewModel.swift
//  App Store
//
//  Batch C3: Customer reviews + review submissions (read-only).
//  Follows the BetaViewModel pattern: staleness via currentAppId, in-flight
//  task cancellation, cursor pagination with a retry on failure.
//  Reply (POST /customerReviewResponses) is implemented in replyToReview().
//

import SwiftUI
import JSONAPI
import OSLog

private let reviewsLogger = Logger(subsystem: "com.appstore.release-notes", category: "Reviews")
private let liveAppStoreVersionStates: Set<String> = [
    "READY_FOR_SALE",
    "READY_FOR_DISTRIBUTION",
    "PENDING_APPLE_RELEASE"
]
private let pendingAppStoreVersionStates: Set<String> = [
    "PREPARE_FOR_SUBMISSION",
    "READY_FOR_REVIEW",
    "WAITING_FOR_REVIEW",
    "IN_REVIEW",
    "PENDING_DEVELOPER_RELEASE",
    "REJECTED",
    "METADATA_REJECTED",
    "DEVELOPER_REJECTED",
    "INVALID_BINARY",
    "PENDING_CONTRACT",
    "PROCESSING_FOR_DISTRIBUTION"
]
private let ignoredAppStoreVersionStates: Set<String> = [
    "REPLACED_WITH_NEW_VERSION",
    "REMOVED_FROM_SALE"
]
private let editableAppStoreVersionStates: Set<String> = [
    "PREPARE_FOR_SUBMISSION",
    "REJECTED",
    "DEVELOPER_REJECTED",
    "METADATA_REJECTED",
    "INVALID_BINARY"
]

enum AppStoreVersionDisplayState: Equatable {
    case noVersion
    case liveOnly
    case both
    case pendingOnly
}

struct AppStoreVersionCaseState {
    let `case`: AppStoreVersionDisplayState
    let liveVersion: AppStoreVersionsModel?
    let pendingVersion: AppStoreVersionsModel?
}

private func appStoreVersionState(_ version: AppStoreVersionsModel) -> String? {
    version.appStoreState ?? version.appVersionState
}

let sharedFractionalISOFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

let sharedISOFormatter = ISO8601DateFormatter()

private func appStoreVersionCreatedDateValue(_ version: AppStoreVersionsModel) -> Date? {
    guard let value = version.createdDate else { return nil }
    if let date = sharedFractionalISOFormatter.date(from: value) {
        return date
    }
    return sharedISOFormatter.date(from: value)
}

private func mostRecentlyCreatedVersion(_ versions: [AppStoreVersionsModel]) -> AppStoreVersionsModel? {
    guard !versions.isEmpty else { return nil }
    var best = versions[0]
    var bestDate = appStoreVersionCreatedDateValue(best)
    for version in versions.dropFirst() {
        let date = appStoreVersionCreatedDateValue(version)
        switch (bestDate, date) {
        case let (.some(b), .some(d)) where d > b:
            best = version
            bestDate = date
        case (.none, .some):
            best = version
            bestDate = date
        case (.none, .none):
            if (version.versionString ?? "").localizedStandardCompare(best.versionString ?? "") == .orderedDescending {
                best = version
            }
        default:
            break
        }
    }
    return best
}

func getVersionCaseState(versions: [AppStoreVersionsModel]) -> AppStoreVersionCaseState {
    let relevantVersions = versions.filter { version in
        guard let state = appStoreVersionState(version) else { return false }
        return !ignoredAppStoreVersionStates.contains(state)
    }
    let liveVersion = mostRecentlyCreatedVersion(relevantVersions.filter { version in
        guard let state = appStoreVersionState(version) else { return false }
        return liveAppStoreVersionStates.contains(state)
    })
    let pendingCandidates = relevantVersions.filter { version in
        guard let state = appStoreVersionState(version) else { return false }
        return pendingAppStoreVersionStates.contains(state)
    }
    let pendingVersion = mostRecentlyCreatedVersion(pendingCandidates)
    let versionCase: AppStoreVersionDisplayState
    switch (liveVersion, pendingVersion) {
    case (.some, .some): versionCase = .both
    case (.some, .none): versionCase = .liveOnly
    case (.none, .some): versionCase = .pendingOnly
    case (.none, .none): versionCase = .noVersion
    }
    return AppStoreVersionCaseState(case: versionCase, liveVersion: liveVersion, pendingVersion: pendingVersion)
}

func getStatusLabel(appStoreState: String?) -> String {
    switch appStoreState {
    case "PREPARE_FOR_SUBMISSION": return "Draft"
    case "READY_FOR_REVIEW", "WAITING_FOR_REVIEW": return "Waiting for Review"
    case "IN_REVIEW": return "In Review"
    case "PENDING_DEVELOPER_RELEASE": return "Approved – Ready to Release"
    case "REJECTED", "DEVELOPER_REJECTED": return "Rejected"
    case "METADATA_REJECTED": return "Metadata Rejected"
    case "INVALID_BINARY": return "Invalid Binary – Needs New Build"
    case "PENDING_CONTRACT": return "Pending Contract"
    case "PROCESSING_FOR_DISTRIBUTION": return "Processing"
    case "READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "PENDING_APPLE_RELEASE": return "Live"
    default: return appStoreState?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Unknown"
    }
}

func isVersionEditable(appStoreState: String?) -> Bool {
    guard let appStoreState else { return false }
    return editableAppStoreVersionStates.contains(appStoreState)
}

@MainActor
final class ReviewsViewModel: ObservableObject {
    deinit {
        // A stuck network call must not keep the VM alive.
        reviewsFetchTask?.cancel()
        submissionsFetchTask?.cancel()
        appStoreVersionsFetchTask?.cancel()
        appStoreVersionsFetchLive = false
        eligibleBuildsFetchTask?.cancel()
        candidateBuildsFetchTask?.cancel()
        versionLocalizationsFetchTask?.cancel()
        reviewDetailsFetchTask?.cancel()
    }
    // MARK: - Customer reviews

    @Published var reviewsState: ViewState<[CustomerReviewModel]> = .idle
    @Published var reviewsMeta: Meta?
    @Published var reviewsNextCursor: String?
    @Published var reviewsPaginationFailed = false

    // MARK: - Review submissions

    @Published var submissionsState: ViewState<[ReviewSubmissionModel]> = .idle
    @Published var submissionsNextCursor: String?
    @Published var submissionsPaginationFailed = false

    @Published var appStoreVersionsState: ViewState<[AppStoreVersionsModel]> = .idle
    @Published var appStoreVersionsNextCursor: String?
    @Published var appStoreVersionsPaginationFailed = false
    @Published var appStoreVersionsError: String?
    @Published var appStoreVersionPlatforms: [String] = []
    @Published private(set) var selectedAppStoreVersionPlatform: String?
    @Published private(set) var selectedAppStoreVersionId: String?
    @Published private(set) var selectedBuildId: String?
    @Published private(set) var eligibleBuildsState: ViewState<[BuildsModel]> = .idle
    @Published private(set) var eligibleBuildsNextCursor: String?
    @Published private(set) var eligibleBuildsPaginationFailed = false
    @Published private(set) var eligibleBuildsError: String?
    /// All builds on the version's platform (newest first), backing the
    /// Choose Build dialog — processing and version-mismatched rows render
    /// as unavailable, unlike the eligible-only list above.
    @Published private(set) var candidateBuildsState: ViewState<[BuildsModel]> = .idle
    /// Version localizations for the release form, keyed by version id.
    /// The versions list fetch only includes `build`, so What's New needs
    /// this dedicated GET (…/appStoreVersions/{id}/appStoreVersionLocalizations).
    @Published private(set) var versionLocalizationsState: ViewState<[AppStoreVersionLocalizationsModel]> = .idle
    @Published private(set) var versionLocalizationsVersionId: String?
    /// Review contact/demo/notes for the release form, keyed by version
    /// id. Absent until loaded (or created on first save).
    @Published private(set) var reviewDetailsState: ViewState<AppStoreReviewDetailsModel> = .idle
    @Published private(set) var reviewDetailsVersionId: String?
    @Published private(set) var creatingVersion = false
    @Published private(set) var attachingBuild = false
    @Published private(set) var savingReleaseSettingsVersionId: String?
    @Published private(set) var releasingVersionId: String?
    @Published private(set) var deletingVersionId: String?
    @Published var releaseSettingsError: String?
    @Published var createVersionError: String?
    @Published var attachBuildError: String?
    @Published var workflowMessage: String?
    @Published private(set) var requestedBuildNumber: String?

    private var appStoreVersionsFetchTask: Task<Void, Never>?
    /// True while a versions fetch task is owned by the current
    /// generation. Unlike the in-flight app id (which can go stale when
    /// a task is cancelled), this is cleared in every fetch defer, so a
    /// dead task can never strand the list in loading with no retry.
    private var appStoreVersionsFetchLive = false
    private var eligibleBuildsFetchTask: Task<Void, Never>?
    private var candidateBuildsFetchTask: Task<Void, Never>?
    private var versionLocalizationsFetchTask: Task<Void, Never>?
    private var reviewDetailsFetchTask: Task<Void, Never>?
    private var appStoreVersionsInFlightAppId: String?
    private var eligibleBuildsInFlightVersionId: String?
    private var isPaginatingAppStoreVersions = false
    private var isPaginatingEligibleBuilds = false
    private var versionWorkflowGeneration = 0
    private var eligibleBuildsGeneration = 0
    private var candidateBuildsGeneration = 0
    private var versionLocalizationsGeneration = 0
    private var reviewDetailsGeneration = 0
    private var phasedReleaseGeneration = 0
    private var reviewsGeneration = 0
    private var submissionsGeneration = 0
    private var reviewSubmissionWorkflowGeneration = 0
    private var versionReleaseRequestGeneration = 0
    private var createVersionGeneration = 0
    private var attachBuildGeneration = 0
    private var releaseSettingsGeneration = 0
    private var deleteVersionGeneration = 0
    private var cancelSubmissionGeneration = 0
    private var selectedAppStoreVersionSnapshot: AppStoreVersionsModel?


    /// The app whose lists are in flight / last requested (loadMore target).
    private(set) var currentAppId: String?
    /// Per-list staleness ids, set only on SUCCESS — a failed load must
    /// auto-retry on the next appear instead of sticking on the error state
    /// (round-1 lesson applied per list here, mirroring DetailViewModel).
    private(set) var reviewsLoadedAppId: String?
    private(set) var submissionsLoadedAppId: String?
    /// Suppresses cancel+respawn churn while a fetch for the same app is
    /// already in flight (cleared in each fetch's defer).
    private var reviewsInFlightAppId: String?
    private var submissionsInFlightAppId: String?

    private var reviewsFetchTask: Task<Void, Never>?
    private var submissionsFetchTask: Task<Void, Never>?
    private var isPaginatingReviews = false
    private var isPaginatingSubmissions = false

    // MARK: - Writes (submit / cancel / phased release)

    /// Surfaced to the view as an alert. Fetch failures keep using the
    /// inline section errors; writes are user-initiated so they interrupt.
    @Published var writeError: String?
    /// Guards one in-flight write per action so double-taps can't issue
    /// duplicate submits/cancels.
    @Published private(set) var submittingReview = false
    @Published private(set) var cancellingSubmissionId: String?
    /// Version picked for phased-release management (an appStoreVersion id).
    @Published var phasedVersionId: String?
    /// Current phased-release state for phasedVersionId: nil = none started
    /// (the related link 404s), otherwise the server state string.
    @Published private(set) var phasedRelease: PhasedReleaseModel?
    @Published private(set) var phasedLoading = false
    @Published private(set) var phasedActionInFlight = false

    // MARK: - Filters

    /// Rating filter for customer reviews: 0 = All, 1–5 = specific rating.
    @Published var ratingFilter: Int = 0
    /// Local text search across title, body, and reviewer nickname.
    @Published var searchText: String = ""
    /// Module 11 local filters (C11-H: territory/date/reply-state stay
    /// local over correctly paginated requests).
    @Published var territoryFilter: String? = nil
    @Published var dateFilter: ReviewDateFilter = .all
    @Published var reviewSort: ReviewSortOption = .newest
    @Published var replyFilter: ReviewReplyFilter = .all
    /// Review selected from the cross-app inbox, consumed by ReviewsView
    /// to open the app detail's Reviews tab on that review.
    @Published var pendingInboxReviewId: String? = nil
    /// Last successful reviews sync (action-bar provenance, per app load).
    @Published private(set) var reviewsLastSync: Date? = nil
    /// Cached rows retained when a refresh fails (114:14026 error state):
    /// shown stale with editing disabled until refresh succeeds. Nil when
    /// no cache exists — then the error shows with Retry and no rows.
    @Published private(set) var staleReviewsCache: [CustomerReviewModel]? = nil
    /// A refresh is in flight while cached rows stay visible (114:13832).
    @Published private(set) var isRefreshingReviews = false
    /// Review ids with an in-flight POST (C11-S guard).
    @Published private(set) var sendingResponseIds: Set<String> = []
    /// Review ids with an in-flight DELETE.
    @Published private(set) var deletingResponseIds: Set<String> = []
    /// Review ids with an accepted DELETE awaiting refresh (114:10689).
    /// No DELETION_PENDING enum exists — this is local operation status.
    @Published private(set) var deleteAcceptedReviewIds: Set<String> = []
    /// Last local check time per review (refresh-status provenance).
    @Published private(set) var responseLastChecked: [String: Date] = [:]

    /// Customer reviews after applying active filters (all local).
    var filteredReviews: [CustomerReviewModel] {
        filterReviews(reviewRows)
    }

    /// Rows for the list: live state, or the retained stale cache when a
    /// refresh failed (114:14026). Never mixes the two.
    var reviewRows: [CustomerReviewModel] {
        if let loaded = reviewsState.loadedValue {
            return loaded
        }
        if case .error = reviewsState, let stale = staleReviewsCache {
            return stale
        }
        return []
    }

    /// True when the list currently shows the stale cache (editing and
    /// reply actions stay disabled until a refresh succeeds).
    var isShowingStaleReviews: Bool {
        reviewsState.loadedValue == nil && staleReviewsCache != nil
    }

    private func filterReviews(_ reviews: [CustomerReviewModel]) -> [CustomerReviewModel] {
        var result = reviews
        if ratingFilter > 0 {
            result = result.filter { ($0.rating ?? 0) == ratingFilter }
        }
        if let territory = territoryFilter {
            result = result.filter { $0.territory == territory }
        }
        if let days = dateFilter.days {
            let cutoff = Date().addingTimeInterval(TimeInterval(-days * 24 * 3600))
            result = result.filter {
                guard let raw = $0.createdDate,
                      let date = Self.reviewDate(raw) else { return false }
                return date >= cutoff
            }
        }
        switch replyFilter {
        case .unanswered:
            result = result.filter { $0.response == nil }
        case .pending:
            result = result.filter { $0.response?.state == "PENDING_PUBLISH" }
        case .published:
            result = result.filter { $0.response?.state == "PUBLISHED" }
        case .all:
            break
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                ($0.title ?? "").localizedCaseInsensitiveContains(query) ||
                ($0.body ?? "").localizedCaseInsensitiveContains(query) ||
                ($0.reviewerNickname ?? "").localizedCaseInsensitiveContains(query)
            }
        }
        // Local reorder over loaded pages (cursor was issued under the
        // server's -createdDate; see ReviewSortOption).
        switch reviewSort {
        case .newest:
            result.sort { ($0.createdDate ?? "") > ($1.createdDate ?? "") }
        case .oldest:
            result.sort { ($0.createdDate ?? "") < ($1.createdDate ?? "") }
        case .highestRated:
            result.sort { ($0.rating ?? 0) > ($1.rating ?? 0) }
        case .lowestRated:
            result.sort { ($0.rating ?? 0) < ($1.rating ?? 0) }
        }
        return result
    }

    nonisolated static func reviewDate(_ raw: String) -> Date? {
        ISO8601DateFormatter().date(from: raw)
    }

    // MARK: - Loading

    /// Loads both lists for the app. Safe to call from onAppear on every
    /// tab switch: only lists that are stale (not yet loaded successfully)
    /// for this app are (re)fetched, and in-flight fetches for the same app
    /// are not cancelled-and-restarted.
    func load(app: AppsData) {
        // App switch: the phased-release card belongs to the previous app —
        // without this reset it would show stale state and its buttons
        /// would PATCH the wrong app's release.
        if currentAppId != app.id {
            phasedVersionId = nil
            phasedRelease = nil
            writeError = nil
            versionWorkflowGeneration += 1
            phasedReleaseGeneration += 1
            reviewsGeneration += 1
            submissionsGeneration += 1
            reviewSubmissionWorkflowGeneration += 1
            versionReleaseRequestGeneration += 1
            createVersionGeneration += 1
            attachBuildGeneration += 1
            releaseSettingsGeneration += 1
            deleteVersionGeneration += 1
            cancelSubmissionGeneration += 1
            appStoreVersionsFetchTask?.cancel()
            appStoreVersionsFetchLive = false
            eligibleBuildsFetchTask?.cancel()
            eligibleBuildsGeneration += 1
            appStoreVersionsState = .idle
            appStoreVersionsNextCursor = nil
            appStoreVersionsPaginationFailed = false
            isPaginatingAppStoreVersions = false
            isPaginatingEligibleBuilds = false
            appStoreVersionsError = nil
            eligibleBuildsError = nil
            appStoreVersionPlatforms = []
            selectedAppStoreVersionPlatform = nil
            selectedAppStoreVersionId = nil
            selectedAppStoreVersionSnapshot = nil
            selectedBuildId = nil
            eligibleBuildsState = .idle
            eligibleBuildsNextCursor = nil
            eligibleBuildsPaginationFailed = false
            candidateBuildsState = .idle
            versionLocalizationsState = .idle
            versionLocalizationsVersionId = nil
            reviewDetailsState = .idle
            reviewDetailsVersionId = nil
            isPaginatingReviews = false
            isPaginatingSubmissions = false
            isRefreshingReviews = false
            staleReviewsCache = nil
            reviewsLastSync = nil
            createVersionError = nil
            attachBuildError = nil
            releaseSettingsError = nil
            savingReleaseSettingsVersionId = nil
            releasingVersionId = nil
            deletingVersionId = nil
            workflowMessage = nil
            requestedBuildNumber = nil
        }
        currentAppId = app.id
        if !appStoreVersionsFetchLive, appStoreVersionsInFlightAppId != app.id, appStoreVersionsState.loadedValue == nil {
            appStoreVersionsFetchTask?.cancel()
            appStoreVersionsInFlightAppId = app.id
            appStoreVersionsFetchLive = true
            let generation = versionWorkflowGeneration
            appStoreVersionsFetchTask = Task { await fetchAppStoreVersions(appId: app.id, generation: generation) }
        }
        if reviewsLoadedAppId != app.id, reviewsInFlightAppId != app.id {
            reviewsFetchTask?.cancel()
            reviewsInFlightAppId = app.id
            let generation = reviewsGeneration
            reviewsFetchTask = Task { await fetchReviews(appId: app.id, generation: generation) }
        }
        if submissionsLoadedAppId != app.id, submissionsInFlightAppId != app.id {
            submissionsFetchTask?.cancel()
            submissionsInFlightAppId = app.id
            let generation = submissionsGeneration
            submissionsFetchTask = Task { await fetchSubmissions(appId: app.id, generation: generation) }
        }
    }

    /// App deselection / team switch / logout: cancel in-flight fetches and
    /// drop everything (cursors included — they're only valid for the query
    /// epoch that issued them). Without this, a fetch from the previous
    /// team could still apply results, and a same-id app under the new team
    /// would hit the staleness guard and show stale cross-team data.
    func resetForTeamSwitch() {
        reviewsFetchTask?.cancel()
        submissionsFetchTask?.cancel()
        appStoreVersionsFetchTask?.cancel()
        appStoreVersionsFetchLive = false
        eligibleBuildsFetchTask?.cancel()
        currentAppId = nil
        reviewsLoadedAppId = nil
        submissionsLoadedAppId = nil
        reviewsInFlightAppId = nil
        submissionsInFlightAppId = nil
        appStoreVersionsInFlightAppId = nil
        eligibleBuildsInFlightVersionId = nil
        versionWorkflowGeneration += 1
        eligibleBuildsGeneration += 1
        phasedReleaseGeneration += 1
        reviewsGeneration += 1
        submissionsGeneration += 1
        reviewSubmissionWorkflowGeneration += 1
        versionReleaseRequestGeneration += 1
        createVersionGeneration += 1
        attachBuildGeneration += 1
        releaseSettingsGeneration += 1
        deleteVersionGeneration += 1
        cancelSubmissionGeneration += 1
        reviewsState = .idle
        submissionsState = .idle
        reviewsLastSync = nil
        staleReviewsCache = nil
        isRefreshingReviews = false
        sendingResponseIds = []
        deletingResponseIds = []
        deleteAcceptedReviewIds = []
        responseLastChecked = [:]
        pendingInboxReviewId = nil
        appStoreVersionsState = .idle
        eligibleBuildsState = .idle
        candidateBuildsState = .idle
        versionLocalizationsState = .idle
        versionLocalizationsVersionId = nil
        reviewDetailsState = .idle
        reviewDetailsVersionId = nil
        reviewsMeta = nil
        reviewsNextCursor = nil
        submissionsNextCursor = nil
        appStoreVersionsNextCursor = nil
        eligibleBuildsNextCursor = nil
        reviewsPaginationFailed = false
        submissionsPaginationFailed = false
        appStoreVersionsPaginationFailed = false
        eligibleBuildsPaginationFailed = false
        isPaginatingAppStoreVersions = false
        isPaginatingEligibleBuilds = false
        isPaginatingReviews = false
        isPaginatingSubmissions = false
        appStoreVersionsError = nil
        eligibleBuildsError = nil
        appStoreVersionPlatforms = []
        selectedAppStoreVersionPlatform = nil
        selectedAppStoreVersionId = nil
        selectedAppStoreVersionSnapshot = nil
        selectedBuildId = nil
        creatingVersion = false
        attachingBuild = false
        savingReleaseSettingsVersionId = nil
        releasingVersionId = nil
        deletingVersionId = nil
        releaseSettingsError = nil
        createVersionError = nil
        attachBuildError = nil
        workflowMessage = nil
        requestedBuildNumber = nil
        // Batch J write state clears with everything else.
        phasedVersionId = nil
        phasedRelease = nil
        phasedLoading = false
        phasedActionInFlight = false
        submittingReview = false
        cancellingSubmissionId = nil
        writeError = nil
    }

    func retryAll() {
        guard let appId = currentAppId else { return }
        reviewsFetchTask?.cancel()
        submissionsFetchTask?.cancel()
        reviewsGeneration += 1
        submissionsGeneration += 1
        isPaginatingReviews = false
        isPaginatingSubmissions = false
        reviewsInFlightAppId = appId
        submissionsInFlightAppId = appId
        let reviewsGeneration = reviewsGeneration
        let submissionsGeneration = submissionsGeneration
        reviewsFetchTask = Task { await fetchReviews(appId: appId, generation: reviewsGeneration) }
        submissionsFetchTask = Task { await fetchSubmissions(appId: appId, generation: submissionsGeneration) }
    }

    func retryReviews() {
        guard let appId = currentAppId else { return }
        reviewsFetchTask?.cancel()
        reviewsGeneration += 1
        isPaginatingReviews = false
        let generation = reviewsGeneration
        reviewsInFlightAppId = appId
        reviewsFetchTask = Task { await fetchReviews(appId: appId, generation: generation) }
    }

    func retrySubmissions() {
        guard let appId = currentAppId else { return }
        submissionsFetchTask?.cancel()
        submissionsGeneration += 1
        isPaginatingSubmissions = false
        let generation = submissionsGeneration
        submissionsInFlightAppId = appId
        submissionsFetchTask = Task { await fetchSubmissions(appId: appId, generation: generation) }
    }

    /// POST /v1/customerReviewResponses (create/overwrite).
    /// Optimistically updates the review's response relationship on
    /// success so the reply appears in the row without a refetch.
    /// Returns whether the reply posted — the row keeps the composer
    /// open on failure so typed input is never silently discarded.
    func replyToReview(reviewId: String, responseBody: String) async -> Bool {
        guard currentAppId != nil else { return false }
        let trimmed = responseBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let body = CustomerReviewResponseRequest(
            data: CustomerReviewResponseData(
                attributes: CustomerReviewResponseAttributes(responseBody: trimmed),
                relationships: CustomerReviewResponseRelationships(
                    review: ReviewLinkage(data: ReviewLinkageData(id: reviewId))
                )
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(body),
              let request = APIClient.shared.getRequest(
                api: .post(name: .customerReviewResponses, body: data),
                apiVersion: .v1) else {
            return false
        }

        do {
            let responseData = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return false }
            let model = try getDecoder().decode(CustomerReviewResponseModel.self,
                                                from: responseData)
            // Optimistic update: set the response on the review row. The
            // reply still posted when the list isn't .loaded (e.g. state
            // reset mid-flight) — success, just nothing to patch in place.
            guard case .loaded(var reviews) = reviewsState,
                  let index = reviews.firstIndex(where: { $0.id == reviewId }) else { return true }
            reviews[index].response = model
            reviewsState = .loaded(reviews)
            return true
        } catch {
            reviewsLogger.error("Failed to reply to review: \(error.localizedDescription)")
            guard !Task.isCancelled else { return false }
            writeError = writeMessage(for: error)
            return false
        }
    }

    // MARK: - App Store version workflow

    static func responseIsCurrent(generation: Int, current: Int) -> Bool {
        generation == current
    }

    private var platformFilteredAppStoreVersions: [AppStoreVersionsModel] {
        let versions = appStoreVersionsState.loadedValue ?? []
        guard let platform = selectedAppStoreVersionPlatform else { return versions }
        return versions.filter { $0.platform == platform }
    }

    private(set) var cachedVersionCaseState = AppStoreVersionCaseState(
        case: .noVersion, liveVersion: nil, pendingVersion: nil)

    private var versionCaseStateVersions: [AppStoreVersionsModel]?
    private var versionCaseStatePlatform: String?

    private var versionCaseState: AppStoreVersionCaseState {
        let versions = platformFilteredAppStoreVersions
        let platform = selectedAppStoreVersionPlatform
        if versionCaseStateVersions == versions, platform == versionCaseStatePlatform {
            return cachedVersionCaseState
        }
        versionCaseStateVersions = versions
        versionCaseStatePlatform = platform
        let result = getVersionCaseState(versions: versions)
        cachedVersionCaseState = result
        return result
    }

    var submissionVersion: AppStoreVersionsModel? {
        if let version = versionCaseState.pendingVersion {
            return version
        }
        if let snapshot = selectedAppStoreVersionSnapshot,
           snapshot.id == selectedAppStoreVersionId,
           Self.isPendingApprovalVersion(snapshot) {
            return snapshot
        }
        return nil
    }

    var displayedAppStoreVersion: AppStoreVersionsModel? {
        let state = versionCaseState
        if let version = state.pendingVersion ?? state.liveVersion {
            return version
        }
        if let snapshot = selectedAppStoreVersionSnapshot,
            snapshot.id == selectedAppStoreVersionId {
            return snapshot
        }
        return nil
    }

    var liveAppStoreVersion: AppStoreVersionsModel? {
        versionCaseState.liveVersion
    }

    var pendingAppStoreVersion: AppStoreVersionsModel? {
        versionCaseState.pendingVersion
    }

    var displayedAppStoreVersions: [AppStoreVersionsModel] {
        let state = versionCaseState
        switch state.case {
        case .both:
            return [state.liveVersion, state.pendingVersion].compactMap { $0 }
        case .liveOnly:
            return state.liveVersion.map { [$0] } ?? []
        case .pendingOnly:
            return state.pendingVersion.map { [$0] } ?? []
        case .noVersion:
            return []
        }
    }

    var appStoreVersionDisplayState: AppStoreVersionDisplayState {
        versionCaseState.case
    }

    var canCreateAppStoreVersion: Bool {
        appStoreVersionDisplayState == .liveOnly
    }

    var creatableAppStoreVersionPlatforms: [AppStoreVersionPlatform] {
        appStoreVersionPlatforms.compactMap { rawValue in
            guard let platform = AppStoreVersionPlatform(rawValue: rawValue) else { return nil }
            let versions = (appStoreVersionsState.loadedValue ?? [])
                .filter { $0.platform == rawValue }
            return getVersionCaseState(versions: versions).`case` == .liveOnly ? platform : nil
        }
    }

    var canSubmitForReview: Bool {
        guard let version = submissionVersion,
              isVersionEditable(appStoreState: version.appStoreState ?? version.appVersionState) else {
            return false
        }
        return version.build != nil
    }

    func selectAppStoreVersionPlatform(_ platform: String) {
        guard appStoreVersionPlatforms.contains(platform),
              platform != selectedAppStoreVersionPlatform else { return }
        selectedAppStoreVersionPlatform = platform
        let versions = appStoreVersionsState.loadedValue?.filter { $0.platform == platform } ?? []
        let caseState = getVersionCaseState(versions: versions)
        let displayedVersion = caseState.pendingVersion ?? caseState.liveVersion
        let selectionChanged = selectedAppStoreVersionId != displayedVersion?.id
        selectedAppStoreVersionId = displayedVersion?.id
        selectedAppStoreVersionSnapshot = displayedVersion
        requestedBuildNumber = nil
        eligibleBuildsNextCursor = nil
        eligibleBuildsPaginationFailed = false
        eligibleBuildsError = nil
        attachBuildError = nil
        releaseSettingsError = nil
        workflowMessage = nil
        if selectionChanged, let displayedVersion, Self.isPendingApprovalVersion(displayedVersion) {
            loadEligibleBuilds(for: displayedVersion)
        }
    }

    func selectAppStoreVersion(_ version: AppStoreVersionsModel) {
        guard Self.isPendingApprovalVersion(version) else { return }
        if selectedAppStoreVersionId != version.id {
            requestedBuildNumber = nil
            eligibleBuildsNextCursor = nil
            eligibleBuildsPaginationFailed = false
            eligibleBuildsError = nil
            candidateBuildsState = .idle
            versionLocalizationsState = .idle
            versionLocalizationsVersionId = nil
            reviewDetailsState = .idle
            reviewDetailsVersionId = nil
        }
        selectedAppStoreVersionId = version.id
        selectedAppStoreVersionSnapshot = version
        phasedReleaseGeneration += 1
        phasedVersionId = version.id
        phasedRelease = nil
        attachBuildError = nil
        releaseSettingsError = nil
        workflowMessage = nil
        loadEligibleBuilds(for: version)
    }

    /// Refetch versions and submissions after a write (submit, cancel,
    /// release, attach). load(appId:force:) only covers versions, so
    /// submissions are marked stale and refetched here too — summaries
    /// need the fresh submitted dates and cancel state.
    func refreshAfterWrite(appId: String) {
        guard currentAppId == appId else { return }
        load(appId: appId, force: true)
        submissionsLoadedAppId = nil
        submissionsGeneration += 1
        let generation = submissionsGeneration
        submissionsFetchTask?.cancel()
        submissionsFetchTask = Task { await fetchSubmissions(appId: appId, generation: generation) }
    }
    func load(appId: String, force: Bool = false) {
        guard currentAppId == appId else { return }
        if force || appStoreVersionsInFlightAppId != appId {
            appStoreVersionsFetchTask?.cancel()
            appStoreVersionsFetchLive = false
            versionWorkflowGeneration += 1
            isPaginatingAppStoreVersions = false
            appStoreVersionsInFlightAppId = appId
            appStoreVersionsFetchLive = true
            appStoreVersionsNextCursor = nil
            let generation = versionWorkflowGeneration
            appStoreVersionsFetchTask = Task { await fetchAppStoreVersions(appId: appId, generation: generation) }
        }
    }

    func retryAppStoreVersions() {
        guard let appId = currentAppId else { return }
        load(appId: appId, force: true)
    }

    func loadMoreAppStoreVersions(cursor: String) {
        guard let appId = currentAppId, !isPaginatingAppStoreVersions else { return }
        appStoreVersionsFetchTask?.cancel()
        appStoreVersionsFetchLive = false
        versionWorkflowGeneration += 1
        appStoreVersionsInFlightAppId = appId
        appStoreVersionsFetchLive = true
        let generation = versionWorkflowGeneration
        appStoreVersionsFetchTask = Task { await fetchAppStoreVersions(appId: appId, cursor: cursor, generation: generation) }
    }

    func fetchAppStoreVersions(appId: String, cursor: String? = nil, generation: Int) async {
        guard !Task.isCancelled,
              generation == versionWorkflowGeneration,
              currentAppId == appId else { return }
        let isPaginating = cursor != nil
        if isPaginating {
            isPaginatingAppStoreVersions = true
        } else if appStoreVersionsState.loadedValue == nil {
            appStoreVersionsState = .loading
        }
        appStoreVersionsPaginationFailed = false
        defer {
            if generation == versionWorkflowGeneration {
                if isPaginating { isPaginatingAppStoreVersions = false }
                appStoreVersionsInFlightAppId = nil
                appStoreVersionsFetchLive = false
            }
        }

        let existing = isPaginating ? (appStoreVersionsState.loadedValue ?? []) : []
        var fetchedVersions: [AppStoreVersionsModel] = []
        var nextCursor = cursor
        var visitedCursors = Set<String>()

        do {
            repeat {
                var queryParams = [
                    "include": "build",
                    "limit": "200"
                ]
                if let pageCursor = nextCursor {
                    guard visitedCursors.insert(pageCursor).inserted else { break }
                    queryParams["cursor"] = pageCursor
                }
                guard let request = APIClient.shared.getRequest(
                    api: .get(name: .getAllApps, queryParams: queryParams, path: "\(appId)/appStoreVersions"),
                    apiVersion: .v1) else {
                    if !isPaginating { appStoreVersionsState = .error("No team selected. Add a team to load App Store versions.") }
                    return
                }
                let data = try await APIClient.shared.callAPI(with: request)
                guard !Task.isCancelled,
                      Self.responseIsCurrent(generation: generation, current: versionWorkflowGeneration),
                      currentAppId == appId else { return }
                let model = try getDecoder().decode(AppStoreVersionsDocument.self, from: data)
                fetchedVersions.append(contentsOf: model.data)
                nextCursor = model.meta.paging.nextCursor
            } while nextCursor != nil

            let existingIDs = Set(existing.map(\.id))
            let merged = existing + fetchedVersions.filter { !existingIDs.contains($0.id) }
            appStoreVersionsError = nil
            let sorted = merged.sorted {
                ($0.versionString ?? "").localizedStandardCompare($1.versionString ?? "") == .orderedDescending
            }
            let platforms = Array(Set(sorted.compactMap(\.platform))).sorted()
            appStoreVersionPlatforms = platforms
            if !platforms.contains(selectedAppStoreVersionPlatform ?? "") {
                selectedAppStoreVersionPlatform = platforms.first
            }
            let platformVersions: [AppStoreVersionsModel]
            if let selectedAppStoreVersionPlatform {
                platformVersions = sorted.filter { $0.platform == selectedAppStoreVersionPlatform }
            } else {
                platformVersions = sorted
            }
            let pendingVersions = platformVersions.filter(Self.isPendingApprovalVersion)
            if pendingVersions.count > 1 {
                reviewsLogger.warning("App returned \(pendingVersions.count, privacy: .public) pending App Store versions for the selected platform; showing the most recently created")
            }
            appStoreVersionsState = sorted.isEmpty ? .empty : .loaded(sorted)
            appStoreVersionsNextCursor = nil
            let displayedVersion = Self.preferredAppStoreVersion(platformVersions)
            let selectionChanged = selectedAppStoreVersionId != displayedVersion?.id
            selectedAppStoreVersionId = displayedVersion?.id
            selectedAppStoreVersionSnapshot = displayedVersion
            if selectionChanged,
               let displayedVersion,
               Self.isPendingApprovalVersion(displayedVersion) {
                loadEligibleBuilds(for: displayedVersion)
            }
        } catch {
            guard !Task.isCancelled,
                  Self.responseIsCurrent(generation: generation, current: versionWorkflowGeneration),
                  currentAppId == appId else { return }
            reviewsLogger.error("Failed to load App Store versions: \(error.localizedDescription)")
            if isPaginating {
                appStoreVersionsPaginationFailed = true
            } else {
                recordAppStoreVersionsFailure(workflowMessage(for: error))
            }
        }
    }

    func createVersion(appId: String,
                       versionString: String,
                       platform: AppStoreVersionPlatform,
                       copyright: String,
                       releaseType: AppStoreVersionReleaseType,
                       buildNumber: String? = nil,
                       earliestReleaseDate: Date? = nil) async -> Bool {
        guard !creatingVersion, currentAppId == appId else { return false }
        let platformVersions = (appStoreVersionsState.loadedValue ?? [])
            .filter { $0.platform == platform.rawValue }
        guard getVersionCaseState(versions: platformVersions).`case` == .liveOnly else {
            createVersionError = "A new version requires an existing live version for \(platform.displayName) with no pending version."
            return false
        }
        let trimmedVersion = versionString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCopyright = copyright.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedVersion.isEmpty else {
            createVersionError = "Enter a version string."
            return false
        }
        guard releaseType != .scheduled || earliestReleaseDate != nil else {
            createVersionError = "Choose a release date for a scheduled release."
            return false
        }
        createVersionGeneration += 1
        let operationGeneration = createVersionGeneration
        creatingVersion = true
        createVersionError = nil
        workflowMessage = nil
        let trimmedBuildNumber = buildNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        requestedBuildNumber = trimmedBuildNumber.isEmpty ? nil : trimmedBuildNumber
        defer {
            if operationGeneration == createVersionGeneration { creatingVersion = false }
        }

        let formatter = sharedISOFormatter
        let body = AppStoreVersionCreateRequest(data: AppStoreVersionCreateData(
            attributes: AppStoreVersionCreateAttributes(
                platform: platform.rawValue,
                versionString: trimmedVersion,
                copyright: trimmedCopyright.isEmpty ? nil : trimmedCopyright,
                releaseType: releaseType.rawValue,
                earliestReleaseDate: earliestReleaseDate.map(formatter.string(from:))),
            relationships: AppStoreVersionCreateRelationships(
                app: AppStoreVersionAppLinkage(data: AppStoreVersionAppRef(id: appId)))))
        guard let data = try? JSONEncoder().encode(body),
              let request = APIClient.shared.getRequest(api: .post(name: .getAppStoreVersions, body: data), apiVersion: .v1) else {
            createVersionError = APIError.jsonConversionFailure.details
            return false
        }
        do {
            let response = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled,
                  operationGeneration == createVersionGeneration,
                  currentAppId == appId else { return false }
            let version = try getDecoder().decode(AppStoreVersionsModel.self, from: response)
            var versions = appStoreVersionsState.loadedValue ?? []
            versions.removeAll { $0.id == version.id }
            versions.append(version)
            versions.sort {
                ($0.versionString ?? "").localizedStandardCompare($1.versionString ?? "") == .orderedDescending
            }
            if let platform = version.platform {
                if !appStoreVersionPlatforms.contains(platform) {
                    appStoreVersionPlatforms.append(platform)
                    appStoreVersionPlatforms.sort()
                }
                selectedAppStoreVersionPlatform = platform
            }
            appStoreVersionsState = .loaded(versions)
            let platformVersions = selectedAppStoreVersionPlatform.map { platform in
                versions.filter { $0.platform == platform }
            } ?? versions
            let displayedVersion = Self.preferredAppStoreVersion(platformVersions)
            selectedAppStoreVersionId = displayedVersion?.id
            selectedAppStoreVersionSnapshot = displayedVersion
            workflowMessage = "Created version \(version.versionString ?? trimmedVersion)."
            load(appId: appId, force: true)
            if let displayedVersion,
               Self.isPendingApprovalVersion(displayedVersion) {
                loadEligibleBuilds(for: displayedVersion)
            }
            return true
        } catch {
            guard !Task.isCancelled,
                  operationGeneration == createVersionGeneration,
                  currentAppId == appId else { return false }
            reviewsLogger.error("Failed to create App Store version: \(error.localizedDescription)")
            requestedBuildNumber = nil
            createVersionError = workflowMessage(for: error)
            return false
        }
    }

    func deleteAppStoreVersion(versionId: String) async -> Bool {
        guard deletingVersionId == nil,
              let appId = currentAppId,
              let version = appStoreVersionsState.loadedValue?.first(where: { $0.id == versionId }),
              Self.isPendingApprovalVersion(version),
              isVersionEditable(appStoreState: version.appStoreState ?? version.appVersionState) else {
            return false
        }
        deleteVersionGeneration += 1
        let operationGeneration = deleteVersionGeneration
        deletingVersionId = versionId
        releaseSettingsError = nil
        workflowMessage = nil
        defer {
            if operationGeneration == deleteVersionGeneration {
                deletingVersionId = nil
            }
        }
        guard let request = APIClient.shared.getRequest(
            api: .delete(name: .getAppStoreVersions, path: versionId),
            apiVersion: .v1) else {
            releaseSettingsError = APIError.jsonConversionFailure.details
            return false
        }
        do {
            _ = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled,
                  operationGeneration == deleteVersionGeneration,
                  currentAppId == appId else { return false }
            var versions = appStoreVersionsState.loadedValue ?? []
            versions.removeAll { $0.id == versionId }
            appStoreVersionsState = versions.isEmpty ? .empty : .loaded(versions)
            let platformVersions = selectedAppStoreVersionPlatform.map { platform in
                versions.filter { $0.platform == platform }
            } ?? versions
            let displayedVersion = Self.preferredAppStoreVersion(platformVersions)
            selectedAppStoreVersionId = displayedVersion?.id
            selectedAppStoreVersionSnapshot = displayedVersion
            requestedBuildNumber = nil
            eligibleBuildsState = .idle
            eligibleBuildsNextCursor = nil
            eligibleBuildsError = nil
            selectedBuildId = nil
            workflowMessage = "Deleted version \(version.versionString ?? versionId)."
            if let appId = currentAppId {
                load(appId: appId, force: true)
            }
            return true
        } catch {
            guard !Task.isCancelled,
                  operationGeneration == deleteVersionGeneration,
                  currentAppId == appId else { return false }
            reviewsLogger.error("Failed to delete App Store version: \(error.localizedDescription)")
            releaseSettingsError = workflowMessage(for: error)
            return false
        }
    }

    func recordAppStoreVersionsFailure(_ message: String) {
        appStoreVersionsError = message
        if appStoreVersionsState.loadedValue == nil {
            appStoreVersionsState = .error(message)
        }
    }

    func recordEligibleBuildsFailure(_ message: String) {
        eligibleBuildsError = message
        if eligibleBuildsState.loadedValue == nil {
            eligibleBuildsState = .error(message)
        }
    }

    func selectBuild(_ build: BuildsModel) {
        guard let version = submissionVersion else { return }
        guard Self.isEligibleBuild(build, versionString: version.versionString ?? "", platform: version.platform ?? "") else { return }
        selectedBuildId = build.id
        attachBuildError = nil
    }

    static func isPendingApprovalVersion(_ version: AppStoreVersionsModel) -> Bool {
        let state = version.appStoreState ?? version.appVersionState
        return pendingAppStoreVersionStates.contains(state ?? "")
    }

    static func preferredAppStoreVersion(_ versions: [AppStoreVersionsModel]) -> AppStoreVersionsModel? {
        let state = getVersionCaseState(versions: versions)
        return state.pendingVersion ?? state.liveVersion
    }

    static func isEligibleBuild(_ build: BuildsModel, versionString: String, platform: String) -> Bool {
        guard build.processingState == "VALID", build.expired == false else { return false }
        let buildVersion = build.preReleaseVersion?.version
        guard buildVersion == versionString else { return false }
        return build.preReleaseVersion?.platform == platform
    }

    func loadEligibleBuilds(for version: AppStoreVersionsModel, cursor: String? = nil) {
        guard let appId = currentAppId, let versionString = version.versionString, let platform = version.platform else { return }
        if cursor != nil, isPaginatingEligibleBuilds { return }
        eligibleBuildsFetchTask?.cancel()
        eligibleBuildsGeneration += 1
        let generation = eligibleBuildsGeneration
        eligibleBuildsInFlightVersionId = version.id
        if cursor == nil {
            isPaginatingEligibleBuilds = false
            eligibleBuildsNextCursor = nil
            eligibleBuildsPaginationFailed = false
            eligibleBuildsError = nil
            eligibleBuildsState = .loading
            selectedBuildId = nil
        }
        eligibleBuildsFetchTask = Task {
            await fetchEligibleBuilds(appId: appId,
                                      version: version,
                                      versionString: versionString,
                                      platform: platform,
                                      cursor: cursor,
                                      generation: generation)
        }
    }

    func fetchEligibleBuilds(appId: String,
                             version: AppStoreVersionsModel,
                             versionString: String,
                             platform: String,
                              cursor: String? = nil,
                              generation: Int) async {
        guard !Task.isCancelled,
              generation == eligibleBuildsGeneration,
              currentAppId == appId,
              selectedAppStoreVersionId == version.id else { return }
        let isPaginating = cursor != nil
        if isPaginating { isPaginatingEligibleBuilds = true }
        eligibleBuildsPaginationFailed = false
        defer {
            if generation == eligibleBuildsGeneration {
                if isPaginating { isPaginatingEligibleBuilds = false }
                if eligibleBuildsInFlightVersionId == version.id { eligibleBuildsInFlightVersionId = nil }
            }
        }
        var queryParams = [
            "filter[app]": appId,
            "filter[processingState]": "VALID",
            "filter[expired]": "false",
            "filter[preReleaseVersion.version]": versionString,
            "filter[preReleaseVersion.platform]": platform,
            "sort": "-uploadedDate",
            "include": "preReleaseVersion",
            "limit": "200"
        ]
        if let cursor { queryParams["cursor"] = cursor }
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getVersionBuilds, queryParams: queryParams), apiVersion: .v1) else {
            if !isPaginating { eligibleBuildsState = .error("No team selected. Add a team to load builds.") }
            return
        }
        do {
            let data = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled,
                  Self.responseIsCurrent(generation: generation, current: eligibleBuildsGeneration),
                  currentAppId == appId,
                  selectedAppStoreVersionId == version.id else { return }
            let model = try getDecoder().decode(BuildsDocument.self, from: data)
            let eligible = model.data.filter { Self.isEligibleBuild($0, versionString: versionString, platform: platform) }
            let existing = isPaginating ? (eligibleBuildsState.loadedValue ?? []) : []
            let existingIDs = Set(existing.map(\.id))
            let merged = existing + eligible.filter { !existingIDs.contains($0.id) }
            eligibleBuildsError = nil
            eligibleBuildsState = merged.isEmpty ? .empty : .loaded(merged)
            eligibleBuildsNextCursor = model.meta.paging.nextCursor
            if let requestedBuildNumber {
                if let build = merged.first(where: { $0.version == requestedBuildNumber }) {
                    self.requestedBuildNumber = nil
                    selectBuild(build)
                    _ = await attachSelectedBuild()
                } else if model.meta.paging.nextCursor == nil {
                    self.requestedBuildNumber = nil
                    attachBuildError = "Build \(requestedBuildNumber) was not found for this version."
                }
            }
        } catch {
            guard !Task.isCancelled,
                  Self.responseIsCurrent(generation: generation, current: eligibleBuildsGeneration),
                  currentAppId == appId,
                  selectedAppStoreVersionId == version.id else { return }
            reviewsLogger.error("Failed to load eligible builds: \(error.localizedDescription)")
            if isPaginating {
                eligibleBuildsPaginationFailed = true
            } else {
                recordEligibleBuildsFailure(workflowMessage(for: error))
            }
        }
    }

    /// Version localizations for the release form (see the property
    /// comment for why the versions list can't supply them). Skips when
    /// the same version is already loading — showVersion and the
    /// shown-version observer fire back-to-back per tap, and the second
    /// call would only churn a duplicate request.
    func loadVersionLocalizations(versionId: String) {
        guard currentAppId != nil else { return }
        if versionLocalizationsVersionId == versionId,
           case .loading = versionLocalizationsState { return }
        versionLocalizationsFetchTask?.cancel()
        versionLocalizationsGeneration += 1
        let generation = versionLocalizationsGeneration
        versionLocalizationsVersionId = versionId
        versionLocalizationsState = .loading
        versionLocalizationsFetchTask = Task {
            guard let request = APIClient.shared.getRequest(
                api: .get(name: .getAppStoreVersions, path: "\(versionId)/appStoreVersionLocalizations"),
                apiVersion: .v1) else {
                guard !Task.isCancelled, generation == versionLocalizationsGeneration else { return }
                versionLocalizationsState = .error("No team selected. Add a team to load metadata.")
                return
            }
            do {
                let data = try await APIClient.shared.callAPI(with: request)
                guard !Task.isCancelled, generation == versionLocalizationsGeneration else { return }
                let model = try getDecoder().decode(AppStoreVersionLocalizationsDocument.self, from: data)
                versionLocalizationsState = model.data.isEmpty ? .empty : .loaded(model.data)
            } catch {
                guard !Task.isCancelled, generation == versionLocalizationsGeneration else { return }
                reviewsLogger.error("Failed to load version localizations: \(error.localizedDescription)")
                versionLocalizationsState = .error(FriendlyErrorMessage.message(for: error))
            }
        }
    }

    /// Builds for the App Store version's marketing version/platform in the Choose Build dialog.
    /// Same query shape as the eligible fetch minus the server-side
    /// VALID/not-expired filters, so processing rows can render as
    /// unavailable instead of vanishing.
    func loadCandidateBuilds(for version: AppStoreVersionsModel) {
        guard let appId = currentAppId,
              let versionString = version.versionString,
              let platform = version.platform else { return }
        let versionId = version.id
        candidateBuildsFetchTask?.cancel()
        candidateBuildsGeneration += 1
        let generation = candidateBuildsGeneration
        candidateBuildsState = .loading
        candidateBuildsFetchTask = Task {
            let queryParams = [
                "filter[app]": appId,
                "filter[preReleaseVersion.version]": versionString,
                "filter[preReleaseVersion.platform]": platform,
                "sort": "-uploadedDate",
                "include": "preReleaseVersion",
                "limit": "200"
            ]
            guard let request = APIClient.shared.getRequest(
                api: .get(name: .getVersionBuilds, queryParams: queryParams), apiVersion: .v1) else {
                guard !Task.isCancelled,
                      generation == candidateBuildsGeneration,
                      currentAppId == appId,
                      selectedAppStoreVersionId == versionId else { return }
                candidateBuildsState = .error("No team selected. Add a team to load builds.")
                return
            }
            do {
                let data = try await APIClient.shared.callAPI(with: request)
                guard !Task.isCancelled,
                      generation == candidateBuildsGeneration,
                      currentAppId == appId,
                      selectedAppStoreVersionId == versionId else { return }
                let model = try getDecoder().decode(BuildsDocument.self, from: data)
                candidateBuildsState = model.data.isEmpty ? .empty : .loaded(model.data)
            } catch {
                guard !Task.isCancelled,
                      generation == candidateBuildsGeneration,
                      currentAppId == appId,
                      selectedAppStoreVersionId == versionId else { return }
                reviewsLogger.error("Failed to load candidate builds: \(error.localizedDescription)")
                candidateBuildsState = .error(FriendlyErrorMessage.message(for: error))
            }
        }
    }

    /// PATCH /v1/appStoreVersionLocalizations/{id} for What's New only.
    /// Same unchanged/clear/set field contract as DetailViewModel's
    /// localization save; the updated localization is written back into
    /// the version inside appStoreVersionsState so the form resyncs.
    /// Saved What's New text, nil when the localization hasn't been
    /// loaded yet. Prefers the dedicated locale fetch; the versions list
    /// never includes localizations.
    private func savedVersionWhatsNew(versionId: String, localizationId: String) -> String? {
        if versionLocalizationsVersionId == versionId,
           case .loaded(let locs) = versionLocalizationsState,
           let loc = locs.first(where: { $0.id == localizationId }) {
            return loc.whatsNew ?? ""
        }
        if case .loaded(let versions) = appStoreVersionsState,
           let version = versions.first(where: { $0.id == versionId }),
           let loc = version.appStoreVersionLocalizations.first(where: { $0.id == localizationId }) {
            return loc.whatsNew ?? ""
        }
        return nil
    }

    /// GET /v1/appStoreVersions/{id} (attributes only — no includes) and
    /// merge it over the cached version, preserving the included build +
    /// localizations the instance response doesn't carry. Returns the
    /// server's version state, or nil when the read itself failed. Save
    /// calls this first so a stale list can't arm writes against a
    /// version Apple already moved on from (which surfaces as 409
    /// STATE_ERROR on the write).
    func refreshVersionForSave(versionId: String) async -> String? {
        guard currentAppId != nil, selectedAppStoreVersionId == versionId else { return nil }
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getAppStoreVersions, path: versionId),
            apiVersion: .v1) else { return nil }
        do {
            let data = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled,
                  currentAppId != nil,
                  selectedAppStoreVersionId == versionId else { return nil }
            let model = try getDecoder().decode(AppStoreVersionsModel.self, from: data)
            if case .loaded(var versions) = appStoreVersionsState,
               let index = versions.firstIndex(where: { $0.id == versionId }) {
                var merged = model
                merged.build = versions[index].build
                merged.appStoreVersionLocalizations = versions[index].appStoreVersionLocalizations
                versions[index] = merged
                appStoreVersionsState = .loaded(versions)
                if selectedAppStoreVersionSnapshot?.id == versionId {
                    selectedAppStoreVersionSnapshot = merged
                }
            }
            return model.appStoreState ?? model.appVersionState
        } catch {
            reviewsLogger.error("Failed to refetch version before save: \(error.localizedDescription)")
            return nil
        }
    }

    func saveVersionWhatsNew(versionId: String, localizationId: String, whatsNew: String) async -> Bool {
        guard currentAppId != nil,
              selectedAppStoreVersionId == versionId,
              let original = savedVersionWhatsNew(versionId: versionId, localizationId: localizationId) else { return false }
        let draft = whatsNew.trimmingCharacters(in: .whitespacesAndNewlines)
        let field: AppInfoLocalizationFieldValue
        if draft == original || (draft.isEmpty && original.isEmpty) {
            field = .unchanged
        } else if draft.isEmpty {
            field = .clear
        } else {
            field = .set(draft)
        }
        guard field != .unchanged else { return true }
        if case .set(let value) = field, value.count > VersionLocalizationLimits.descriptionMaxLength {
            releaseSettingsError = "What's New can't be longer than \(VersionLocalizationLimits.descriptionMaxLength) characters."
            return false
        }
        let body = VersionLocalizationUpdateRequest(
            data: VersionLocalizationUpdateData(
                id: localizationId,
                attributes: VersionLocalizationUpdateAttributes(
                    descriptionData: .unchanged,
                    keywords: .unchanged,
                    marketingUrl: .unchanged,
                    promotionalText: .unchanged,
                    supportUrl: .unchanged,
                    whatsNew: field)))
        guard let data = try? JSONEncoder().encode(body),
              let request = APIClient.shared.getRequest(
                api: .patch(name: .appStoreVersionLocalizations, body: data, path: localizationId),
                apiVersion: .v1) else {
            releaseSettingsError = APIError.jsonConversionFailure.details
            return false
        }
        do {
            let model = try await patchVersionWhatsNew(request: request)
            guard !Task.isCancelled,
                  currentAppId != nil,
                  selectedAppStoreVersionId == versionId else { return false }
            storeVersionLocalization(versionId: versionId, localizationId: localizationId, model: model)
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            if let apiError = error as? APIError, apiError.statusCode == 409 {
                // A back-to-back version write can leave the version briefly
                // locked: one bounded retry after a pause, then a
                // field-specific message instead of raw server JSON.
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled,
                      currentAppId != nil,
                      selectedAppStoreVersionId == versionId else { return false }
                do {
                    let model = try await patchVersionWhatsNew(request: request)
                    storeVersionLocalization(versionId: versionId, localizationId: localizationId, model: model)
                    return true
                } catch {
                    guard !Task.isCancelled else { return false }
                    reviewsLogger.error("Failed to update What's New after retry: \(error.localizedDescription)")
                    releaseSettingsError = stateLockedMessage(for: error, field: "What's New")
                    return false
                }
            }
            reviewsLogger.error("Failed to update What's New: \(error.localizedDescription)")
            releaseSettingsError = workflowMessage(for: error)
            return false
        }
    }

    private func patchVersionWhatsNew(request: URLRequest) async throws -> AppStoreVersionLocalizationsModel {
        let response = try await APIClient.shared.callAPI(with: request)
        return try getDecoder().decode(AppStoreVersionLocalizationsModel.self, from: response)
    }

    private func storeVersionLocalization(versionId: String, localizationId: String, model: AppStoreVersionLocalizationsModel) {
        if versionLocalizationsVersionId == versionId,
           case .loaded(var locs) = versionLocalizationsState,
           let locIndex = locs.firstIndex(where: { $0.id == localizationId }) {
            locs[locIndex] = model
            versionLocalizationsState = .loaded(locs)
        }
        if case .loaded(var updated) = appStoreVersionsState,
           let versionIndex = updated.firstIndex(where: { $0.id == versionId }),
           let nestedIndex = updated[versionIndex].appStoreVersionLocalizations.firstIndex(where: { $0.id == localizationId }) {
            updated[versionIndex].appStoreVersionLocalizations[nestedIndex] = model
            appStoreVersionsState = .loaded(updated)
            if selectedAppStoreVersionSnapshot?.id == versionId {
                selectedAppStoreVersionSnapshot = updated[versionIndex]
            }
        }
    }

    private func stateLockedMessage(for error: Error, field: String) -> String {
        if let apiError = error as? APIError, apiError.statusCode == 409 {
            return "\(field) can't be edited right now — the version may have changed state on App Store Connect. Reload and try again."
        }
        return workflowMessage(for: error)
    }

    // MARK: - Review details (contact/demo/notes)

    /// Active cancellable submission for this exact version. Do not fall
    /// back to platform-only matching: Apple permits a second items-only
    /// submission on the same platform, and cancelling that would withdraw
    /// unrelated review content.
    func cancellableSubmission(for version: AppStoreVersionsModel) -> ReviewSubmissionModel? {
        (submissionsState.loadedValue ?? []).first {
            Self.cancellableSubmissionStates.contains($0.state ?? "")
                && $0.appStoreVersionForReview?.id == version.id
        }
    }

    /// Latest submitted-state submission for the platform (any state past
    /// draft), used for the Submitted date in summaries.
    func latestSubmission(forPlatform platform: String?) -> ReviewSubmissionModel? {
        (submissionsState.loadedValue ?? []).first {
            ($0.state ?? "") != "READY_FOR_REVIEW"
                && (platform == nil || $0.platform == platform)
        }
    }

    /// Fire-and-forget read for the release form. Never creates: a
    /// missing record surfaces as .empty and is created lazily by the
    /// first save, so viewing a version has no server side effects.
    /// Skips when the same version is already loading (see
    /// loadVersionLocalizations).
    func loadReviewDetails(versionId: String) {
        guard currentAppId != nil else { return }
        if reviewDetailsVersionId == versionId,
           case .loading = reviewDetailsState { return }
        reviewDetailsFetchTask?.cancel()
        reviewDetailsGeneration += 1
        let generation = reviewDetailsGeneration
        reviewDetailsVersionId = versionId
        reviewDetailsState = .loading
        reviewDetailsFetchTask = Task {
            _ = await ensureReviewDetails(versionId: versionId, generation: generation, createIfMissing: false)
        }
    }

    /// GET-or-create for one version's review details. Apple creates the
    /// record for some versions and not others: a 404 (or a null-data
    /// payload) means "none yet", so the client creates an empty shell and
    /// returns it. Returns nil on any other failure.
    func ensureReviewDetails(versionId: String, generation: Int? = nil, createIfMissing: Bool = true) async -> AppStoreReviewDetailsModel? {
        let gen = generation ?? { reviewDetailsGeneration += 1; return reviewDetailsGeneration }()
        if reviewDetailsVersionId == versionId,
           case .loaded(let existing) = reviewDetailsState {
            return existing
        }
        reviewDetailsVersionId = versionId
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getAppStoreVersions, path: "\(versionId)/appStoreReviewDetail"),
            apiVersion: .v1) else {
            guard !Task.isCancelled, gen == reviewDetailsGeneration else { return nil }
            reviewDetailsState = .error("No team selected. Add a team to load review details.")
            return nil
        }
        do {
            let data = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled, gen == reviewDetailsGeneration else { return nil }
            if (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"] is NSNull {
                return await createReviewDetails(versionId: versionId, generation: gen, createIfMissing: createIfMissing, attributes: ReviewDetailsUpdateAttributes())
            }
            let details = try getDecoder().decode(AppStoreReviewDetailsModel.self, from: data)
            reviewDetailsState = .loaded(details)
            return details
        } catch {
            guard !Task.isCancelled, gen == reviewDetailsGeneration else { return nil }
            if let apiError = error as? APIError, apiError.statusCode == 404 {
                return await createReviewDetails(versionId: versionId, generation: gen, createIfMissing: createIfMissing, attributes: ReviewDetailsUpdateAttributes())
            }
            reviewsLogger.error("Failed to load review details: \(error.localizedDescription)")
            reviewDetailsState = .error(FriendlyErrorMessage.message(for: error))
            return nil
        }
    }

    private func createReviewDetails(versionId: String, generation: Int, createIfMissing: Bool, attributes: ReviewDetailsUpdateAttributes) async -> AppStoreReviewDetailsModel? {
        guard createIfMissing else {
            reviewDetailsState = .empty
            return nil
        }
        let body = ReviewDetailsCreateRequest(data: ReviewDetailsCreateData(
            attributes: attributes,
            relationships: ReviewDetailsCreateRelationships(
                appStoreVersion: ReviewDetailsVersionLinkage(
                    data: ReviewDetailsVersionRef(id: versionId)))))
        guard let data = try? JSONEncoder().encode(body),
              let request = APIClient.shared.getRequest(
                api: .post(name: .appStoreReviewDetails, body: data),
                apiVersion: .v1) else {
            guard !Task.isCancelled, generation == reviewDetailsGeneration else { return nil }
            reviewDetailsState = .error(APIError.jsonConversionFailure.details)
            return nil
        }
        do {
            let response = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled, generation == reviewDetailsGeneration else { return nil }
            let details = try getDecoder().decode(AppStoreReviewDetailsModel.self, from: response)
            reviewDetailsState = .loaded(details)
            return details
        } catch {
            guard !Task.isCancelled, generation == reviewDetailsGeneration else { return nil }
            reviewsLogger.error("Failed to create review details: \(error.localizedDescription)")
            reviewDetailsState = .error(FriendlyErrorMessage.message(for: error))
            return nil
        }
    }

    /// Saves the review-contact form. Creates the record (with the draft
    /// values) when none exists yet; otherwise PATCHes only changed
    /// fields. Returns false with releaseSettingsError set on failure.
    func saveReviewDetails(versionId: String,
                           firstName: String,
                           lastName: String,
                           phone: String,
                           email: String,
                           demoRequired: Bool,
                           demoUsername: String,
                           demoPassword: String,
                           notes: String) async -> Bool {
        guard currentAppId != nil, selectedAppStoreVersionId == versionId else { return false }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEmail.isEmpty, !trimmedEmail.contains("@") {
            releaseSettingsError = "Enter a valid contact email."
            return false
        }
        if notes.count > VersionLocalizationLimits.reviewNotesMaxLength {
            releaseSettingsError = "Review notes can't be longer than \(VersionLocalizationLimits.reviewNotesMaxLength) characters."
            return false
        }
        guard let existing = await ensureReviewDetails(versionId: versionId, createIfMissing: false) else {
            // No record yet — create it with the draft values in one POST.
            _ = await createWithDraft(versionId: versionId, firstName: firstName, lastName: lastName, phone: phone, email: email, demoRequired: demoRequired, demoUsername: demoUsername, demoPassword: demoPassword, notes: notes)
            return reviewDetailsVersionId == versionId && reviewDetailsState.loadedValue != nil
        }
        func changed(_ draft: String, _ saved: String?) -> String? {
            let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            let original = (saved ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == original { return nil }
            return trimmed
        }
        let demoChanged = demoRequired != (existing.demoAccountRequired ?? false)
        let attributes = ReviewDetailsUpdateAttributes(
            contactFirstName: changed(firstName, existing.contactFirstName),
            contactLastName: changed(lastName, existing.contactLastName),
            contactPhone: changed(phone, existing.contactPhone),
            contactEmail: changed(email, existing.contactEmail),
            demoAccountName: changed(demoUsername, existing.demoAccountName),
            demoAccountPassword: demoPassword.isEmpty ? nil : (demoPassword == (existing.demoAccountPassword ?? "") ? nil : demoPassword),
            demoAccountRequired: demoChanged ? demoRequired : nil,
            notes: changed(notes, existing.notes))
        guard !attributes.isEmpty else { return true }
        let body = ReviewDetailsUpdateRequest(data: ReviewDetailsUpdateData(id: existing.id, attributes: attributes))
        guard let data = try? JSONEncoder().encode(body),
              let request = APIClient.shared.getRequest(
                api: .patch(name: .appStoreReviewDetails, body: data, path: existing.id),
                apiVersion: .v1) else {
            releaseSettingsError = APIError.jsonConversionFailure.details
            return false
        }
        do {
            let response = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled,
                  currentAppId != nil,
                  selectedAppStoreVersionId == versionId else { return false }
            let model = try getDecoder().decode(AppStoreReviewDetailsModel.self, from: response)
            reviewDetailsVersionId = versionId
            reviewDetailsState = .loaded(model)
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            reviewsLogger.error("Failed to update review details: \(error.localizedDescription)")
            releaseSettingsError = workflowMessage(for: error)
            return false
        }
    }

    private func createWithDraft(versionId: String,
                                 firstName: String,
                                 lastName: String,
                                 phone: String,
                                 email: String,
                                 demoRequired: Bool,
                                 demoUsername: String,
                                 demoPassword: String,
                                 notes: String) async {
        reviewDetailsGeneration += 1
        let generation = reviewDetailsGeneration
        func value(_ draft: String) -> String? {
            let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let attributes = ReviewDetailsUpdateAttributes(
            contactFirstName: value(firstName),
            contactLastName: value(lastName),
            contactPhone: value(phone),
            contactEmail: value(email),
            demoAccountName: value(demoUsername),
            demoAccountPassword: value(demoPassword),
            demoAccountRequired: demoRequired,
            notes: value(notes))
        _ = await createReviewDetails(versionId: versionId, generation: generation, createIfMissing: true, attributes: attributes)
    }

    func attachSelectedBuild() async -> Bool {
        guard let appId = currentAppId, let version = submissionVersion, let buildId = selectedBuildId, !attachingBuild else { return false }
        let build = eligibleBuildsState.loadedValue?.first(where: { $0.id == buildId })
            ?? candidateBuildsState.loadedValue?.first(where: { $0.id == buildId })
        guard let build else {
            attachBuildError = "Choose an eligible build first."
            return false
        }
        guard Self.isEligibleBuild(build, versionString: version.versionString ?? "", platform: version.platform ?? "") else {
            attachBuildError = "That build is no longer eligible."
            return false
        }
        attachBuildGeneration += 1
        let operationGeneration = attachBuildGeneration
        attachingBuild = true
        attachBuildError = nil
        workflowMessage = nil
        defer {
            if operationGeneration == attachBuildGeneration { attachingBuild = false }
        }
        let body = AppStoreVersionBuildLinkageRequest(data: AppStoreVersionBuildRef(id: buildId))
        guard let data = try? JSONEncoder().encode(body),
              let request = APIClient.shared.getRequest(
                api: .patch(name: .getAppStoreVersions, body: data, path: "\(version.id)/relationships/build"),
                apiVersion: .v1) else {
            attachBuildError = APIError.jsonConversionFailure.details
            return false
        }
        do {
            _ = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled,
                  operationGeneration == attachBuildGeneration,
                  currentAppId == appId,
                  selectedAppStoreVersionId == version.id else { return false }
            if case .loaded(var versions) = appStoreVersionsState,
               let index = versions.firstIndex(where: { $0.id == version.id }) {
                versions[index].build = build
                appStoreVersionsState = .loaded(versions)
                if selectedAppStoreVersionSnapshot?.id == version.id {
                    selectedAppStoreVersionSnapshot = versions[index]
                }
            }
            workflowMessage = "Attached build \(build.version ?? buildId)."
            load(appId: appId, force: true)
            return true
        } catch {
            guard !Task.isCancelled,
                  operationGeneration == attachBuildGeneration,
                  currentAppId == appId,
                  selectedAppStoreVersionId == version.id else { return false }
            reviewsLogger.error("Failed to attach build: \(error.localizedDescription)")
            attachBuildError = workflowMessage(for: error)
            return false
        }
    }

    private func workflowMessage(for error: Error) -> String {
        if let apiError = error as? APIError {
            if apiError.statusCode == 403 {
                return "\(apiError.details) — this action requires an API key with the App Manager or Admin role."
            }
            return apiError.details
        }
        return error.localizedDescription
    }

    enum ReleaseSettingsSaveResult {
        case success
        case failure(String)
        case ignored
    }

    func saveReleaseSettings(versionId: String,
                             releaseType: AppStoreVersionReleaseType,
                             earliestReleaseDate: Date?,
                             copyright: String? = nil,
                             versionString: String? = nil) async -> ReleaseSettingsSaveResult {
        guard savingReleaseSettingsVersionId == nil,
              currentAppId != nil,
              selectedAppStoreVersionId == versionId else { return .ignored }
        guard releaseType != .scheduled || earliestReleaseDate != nil else {
            releaseSettingsError = "Choose a release date for a scheduled release."
            return .failure(releaseSettingsError ?? "Choose a release date.")
        }
        let trimmedVersion = versionString?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedVersion, trimmedVersion.isEmpty {
            releaseSettingsError = "Enter a version string."
            return .failure(releaseSettingsError ?? "Enter a version string.")
        }
        releaseSettingsGeneration += 1
        let operationGeneration = releaseSettingsGeneration
        savingReleaseSettingsVersionId = versionId
        releaseSettingsError = nil
        defer {
            if operationGeneration == releaseSettingsGeneration { savingReleaseSettingsVersionId = nil }
        }

        let formatter = sharedISOFormatter
        let trimmedCopyright = copyright?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = AppStoreVersionUpdateRequest(data: AppStoreVersionUpdateData(
            id: versionId,
            attributes: AppStoreVersionUpdateAttributes(
                releaseType: releaseType.rawValue,
                earliestReleaseDate: earliestReleaseDate.map(formatter.string(from:)),
                copyright: trimmedCopyright?.isEmpty == false ? trimmedCopyright : nil,
                versionString: trimmedVersion)))
        guard let data = try? JSONEncoder().encode(body),
              let request = APIClient.shared.getRequest(
                api: .patch(name: .getAppStoreVersions, body: data, path: versionId),
                apiVersion: .v1) else {
            releaseSettingsError = APIError.jsonConversionFailure.details
            return .failure(releaseSettingsError ?? APIError.jsonConversionFailure.details)
        }

        do {
            let response = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled,
                  operationGeneration == releaseSettingsGeneration,
                  currentAppId != nil,
                  selectedAppStoreVersionId == versionId else { return .ignored }
            let model = try getDecoder().decode(AppStoreVersionsModel.self, from: response)
            guard case .loaded(var versions) = appStoreVersionsState,
                  let index = versions.firstIndex(where: { $0.id == versionId }) else {
                return .ignored
            }
            // The PATCH response carries attributes only — no `included`
            // build or localizations. Merge the previous relationships
            // forward or a save would visibly "reset" the attached build
            // and wipe the form's locale data until the next full reload.
            var merged = model
            merged.build = versions[index].build
            merged.appStoreVersionLocalizations = versions[index].appStoreVersionLocalizations
            versions[index] = merged
            if selectedAppStoreVersionSnapshot?.id == versionId {
                selectedAppStoreVersionSnapshot = merged
            }
            return .success
        } catch {
            guard !Task.isCancelled,
                  operationGeneration == releaseSettingsGeneration,
                  selectedAppStoreVersionId == versionId else { return .ignored }
            releaseSettingsError = workflowMessage(for: error)
            return .failure(releaseSettingsError ?? error.localizedDescription)
        }
    }


    func releaseVersion(versionId: String) async -> Bool {
        guard releasingVersionId == nil,
              let appId = currentAppId,
              selectedAppStoreVersionId == versionId,
              let version = submissionVersion,
              version.id == versionId,
              version.releaseType == AppStoreVersionReleaseType.manual.rawValue,
              version.appVersionState == "PENDING_DEVELOPER_RELEASE" else { return false }
        let generation = versionReleaseRequestGeneration
        releasingVersionId = versionId
        releaseSettingsError = nil
        defer {
            if generation == versionReleaseRequestGeneration { releasingVersionId = nil }
        }

        let body = AppStoreVersionReleaseRequest(
            data: AppStoreVersionReleaseRequestData(
                relationships: AppStoreVersionReleaseRequestRelationships(
                    appStoreVersion: AppStoreVersionReleaseVersionLinkage(
                        data: AppStoreVersionCreateRef(id: versionId)))))
        guard let data = try? JSONEncoder().encode(body),
              let request = APIClient.shared.getRequest(
                api: .post(name: .appStoreVersionReleaseRequests, body: data),
                apiVersion: .v1) else {
            releaseSettingsError = APIError.jsonConversionFailure.details
            return false
        }

        do {
            _ = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled,
                  generation == versionReleaseRequestGeneration,
                  currentAppId == appId,
                  selectedAppStoreVersionId == versionId else { return false }
            workflowMessage = "Released version \(version.versionString ?? versionId)."
            load(appId: appId, force: true)
            return true
        } catch {
            guard !Task.isCancelled,
                  generation == versionReleaseRequestGeneration,
                  currentAppId == appId,
                  selectedAppStoreVersionId == versionId else { return false }
            reviewsLogger.error("Failed to release App Store version: \(error.localizedDescription)")
            releaseSettingsError = workflowMessage(for: error)
            return false
        }
    }

    /// Full submit pipeline (verified against spec v4.3.1 + the ASC
    /// submission workflow): POST /reviewSubmissions → POST
    /// /reviewSubmissionItems linking the appStoreVersion → PATCH the
    /// submission {submitted: true}. A POST alone only creates a draft.
    /// `versionId` is required — the UI disables submit without one.
    func submitForReview(appId: String, versionId: String) async -> Bool {
        guard !submittingReview,
              currentAppId == appId,
              let version = appStoreVersionsState.loadedValue?.first(where: { $0.id == versionId }),
              Self.isPendingApprovalVersion(version),
              isVersionEditable(appStoreState: version.appStoreState ?? version.appVersionState),
              version.build != nil else { return false }
        let generation = reviewSubmissionWorkflowGeneration
        submittingReview = true
        defer {
            if generation == reviewSubmissionWorkflowGeneration { submittingReview = false }
        }

        // Step 1: create the submission (platform omitted — the server
        // derives it from the linked version's app).
        let body = ReviewSubmissionCreateRequest(
            data: ReviewSubmissionCreateData(
                attributes: nil,
                relationships: ReviewSubmissionAppLinkage(
                    app: ReviewSubmissionAppRef(
                        data: ReviewSubmissionAppRefData(id: appId)))
            )
        )
        guard let data = try? JSONEncoder().encode(body),
              let request = APIClient.shared.getRequest(
                api: .post(name: .getReviewSubmissions, body: data),
                apiVersion: .v1) else {
            writeError = APIError.jsonConversionFailure.details
            return false
        }

        do {
            let responseData = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled,
                  generation == reviewSubmissionWorkflowGeneration,
                  currentAppId == appId else { return false }
            let submission = try getDecoder().decode(ReviewSubmissionModel.self, from: responseData)

            // Step 2: link the version as the item under review.
            let item = ReviewSubmissionItemCreateRequest(
                data: ReviewSubmissionItemCreateData(
                    relationships: ReviewSubmissionItemRelationships(
                        reviewSubmission: ReviewSubmissionItemRef(
                            data: ReviewSubmissionItemRefData(id: submission.id)),
                        appStoreVersion: ReviewSubmissionItemVersionRef(
                            data: ReviewSubmissionItemVersionRefData(id: versionId))
                    )
                )
            )
            guard let itemData = try? JSONEncoder().encode(item),
                  let itemRequest = APIClient.shared.getRequest(
                    api: .post(name: .reviewSubmissionItems, body: itemData),
                    apiVersion: .v1) else {
                writeError = APIError.jsonConversionFailure.details
                return false
            }
            _ = try await APIClient.shared.callAPI(with: itemRequest)
            guard !Task.isCancelled,
                  generation == reviewSubmissionWorkflowGeneration,
                  currentAppId == appId else { return false }

            // Step 3: flip submitted=true — this actually sends it.
            let update = ReviewSubmissionUpdateRequest(
                data: ReviewSubmissionUpdateData(
                    id: submission.id,
                    attributes: ReviewSubmissionUpdateAttributes(submitted: true, canceled: nil)
                )
            )
            guard let updateData = try? JSONEncoder().encode(update),
                  let updateRequest = APIClient.shared.getRequest(
                    api: .patch(name: .getReviewSubmissions, body: updateData, path: submission.id),
                    apiVersion: .v1) else {
                writeError = APIError.jsonConversionFailure.details
                return false
            }
            _ = try await APIClient.shared.callAPI(with: updateRequest)
            guard !Task.isCancelled,
                  generation == reviewSubmissionWorkflowGeneration,
                  currentAppId == appId else { return false }

            // Invalidate so the next load refetches with the new row.
            submissionsLoadedAppId = nil
            submissionsGeneration += 1
            let fetchGeneration = submissionsGeneration
            submissionsFetchTask = Task { await fetchSubmissions(appId: appId, generation: fetchGeneration) }
            return true
        } catch {
            guard !Task.isCancelled,
                  generation == reviewSubmissionWorkflowGeneration,
                  currentAppId == appId else { return false }
            reviewsLogger.error("Failed to submit for review: \(error.localizedDescription)")
            writeError = writeMessage(for: error)
            return false
        }
    }

    /// States in which Apple accepts a cancel. IN_REVIEW intentionally
    /// excluded — the server 422s cancels once review has started.
    static let cancellableSubmissionStates: Set<String> = ["READY_FOR_REVIEW", "WAITING_FOR_REVIEW"]

    /// PATCH /v1/reviewSubmissions/{id} {canceled: true}. Refetches the
    /// list on success so the row state updates; true = cancelled.
    func cancelSubmission(_ submission: ReviewSubmissionModel) async -> Bool {
        guard cancellingSubmissionId == nil else { return false }
        guard let appId = currentAppId else { return false }
        cancelSubmissionGeneration += 1
        let operationGeneration = cancelSubmissionGeneration
        cancellingSubmissionId = submission.id
        defer {
            if operationGeneration == cancelSubmissionGeneration { cancellingSubmissionId = nil }
        }

        let body = ReviewSubmissionUpdateRequest(
            data: ReviewSubmissionUpdateData(
                id: submission.id,
                attributes: ReviewSubmissionUpdateAttributes(submitted: nil, canceled: true)
            )
        )
        guard let data = try? JSONEncoder().encode(body),
              let request = APIClient.shared.getRequest(
                api: .patch(name: .getReviewSubmissions, body: data, path: submission.id),
                apiVersion: .v1) else {
            writeError = APIError.jsonConversionFailure.details
            return false
        }

        do {
            _ = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled,
                  operationGeneration == cancelSubmissionGeneration,
                  currentAppId == appId else { return false }
            submissionsLoadedAppId = nil
            submissionsGeneration += 1
            let generation = submissionsGeneration
            submissionsFetchTask = Task { await fetchSubmissions(appId: appId, generation: generation) }
            return true
        } catch {
            guard !Task.isCancelled,
                  operationGeneration == cancelSubmissionGeneration,
                  currentAppId == appId else { return false }
            reviewsLogger.error("Failed to cancel submission: \(error.localizedDescription)")
            writeError = writeMessage(for: error)
            return false
        }
    }

    // MARK: - Phased release

    /// GET /v1/appStoreVersions/{id}/appStoreVersionPhasedRelease.
    /// A 404 means no phased release was ever started — that is a valid
    /// empty state (phasedRelease = nil), not an error. Responses for a
    /// version the user has since navigated away from are dropped, so a
    /// slow earlier request can't overwrite (or arm buttons against)
    /// the currently selected version's release.
    func loadPhasedRelease(versionId: String) async {
        phasedVersionId = versionId
        phasedReleaseGeneration += 1
        let generation = phasedReleaseGeneration
        phasedLoading = true
        defer {
            if generation == phasedReleaseGeneration {
                phasedLoading = false
            }
        }
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getAppStoreVersions, path: "\(versionId)/appStoreVersionPhasedRelease"),
            apiVersion: .v1) else {
            writeError = APIError.jsonConversionFailure.details
            return
        }
        do {
            let data = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled,
                  generation == phasedReleaseGeneration,
                  phasedVersionId == versionId else { return }
            if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               payload["data"] is NSNull {
                phasedRelease = nil
                return
            }
            phasedRelease = try getDecoder().decode(PhasedReleaseModel.self, from: data)
        } catch {
            guard !Task.isCancelled,
                  generation == phasedReleaseGeneration,
                  phasedVersionId == versionId else { return }
            if let apiError = error as? APIError, apiError.statusCode == 404 {
                phasedRelease = nil
            } else {
                reviewsLogger.error("Failed to load phased release: \(error.localizedDescription)")
                if error is DecodingError {
                    writeError = "Couldn't read the phased release response. Try again."
                } else {
                    writeError = writeMessage(for: error)
                }
            }
        }
    }

    /// POST /v1/appStoreVersionPhasedReleases — starts phased release for
    /// a version that has none. Refetches state on success.
    func startPhasedRelease(versionId: String) async -> Bool {
        guard !phasedActionInFlight, phasedVersionId == versionId else { return false }
        let generation = phasedReleaseGeneration
        phasedActionInFlight = true
        defer {
            if generation == phasedReleaseGeneration { phasedActionInFlight = false }
        }

        let body = PhasedReleaseCreateRequest(
            data: PhasedReleaseCreateData(
                relationships: PhasedReleaseVersionLinkage(
                    appStoreVersion: PhasedReleaseVersionRef(
                        data: PhasedReleaseVersionRefData(id: versionId)))
            )
        )
        guard let data = try? JSONEncoder().encode(body),
              let request = APIClient.shared.getRequest(
                api: .post(name: .appStoreVersionPhasedReleases, body: data),
                apiVersion: .v1) else {
            writeError = APIError.jsonConversionFailure.details
            return false
        }

        do {
            let response = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled,
                  generation == phasedReleaseGeneration,
                  phasedVersionId == versionId else { return false }
            phasedRelease = try getDecoder().decode(PhasedReleaseModel.self, from: response)
            return true
        } catch {
            guard !Task.isCancelled,
                  generation == phasedReleaseGeneration,
                  phasedVersionId == versionId else { return false }
            reviewsLogger.error("Failed to start phased release: \(error.localizedDescription)")
            writeError = writeMessage(for: error)
            return false
        }
    }

    /// PATCH state transitions: ACTIVE (start/resume), PAUSED (pause),
    /// COMPLETE (finish). Updates local state on success, no refetch needed.
    func setPhasedReleaseState(_ state: String) async -> Bool {
        guard !phasedActionInFlight,
              let versionId = phasedVersionId,
              let release = phasedRelease else { return false }
        let generation = phasedReleaseGeneration
        phasedActionInFlight = true
        defer {
            if generation == phasedReleaseGeneration { phasedActionInFlight = false }
        }

        let body = PhasedReleaseUpdateRequest(
            data: PhasedReleaseUpdateData(
                id: release.id,
                attributes: PhasedReleaseUpdateAttributes(phasedReleaseState: state)
            )
        )
        guard let data = try? JSONEncoder().encode(body),
              let request = APIClient.shared.getRequest(
                api: .patch(name: .appStoreVersionPhasedReleases, body: data, path: release.id),
                apiVersion: .v1) else {
            writeError = APIError.jsonConversionFailure.details
            return false
        }

        do {
            let response = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled,
                  generation == phasedReleaseGeneration,
                  phasedVersionId == versionId else { return false }
            phasedRelease = try getDecoder().decode(PhasedReleaseModel.self, from: response)
            return true
        } catch {
            guard !Task.isCancelled,
                  generation == phasedReleaseGeneration,
                  phasedVersionId == versionId else { return false }
            reviewsLogger.error("Failed to update phased release: \(error.localizedDescription)")
            writeError = writeMessage(for: error)
            return false
        }
    }

    /// Writes need an App Manager key — a TestFlight-only key 403s.
    /// Surface the permissions hint, not a raw error.
    private func writeMessage(for error: Error) -> String {
        if let apiError = error as? APIError, apiError.statusCode == 403 {
            return "\(apiError.details) — submitting for review and phased releases need an API key with broader permissions (e.g. App Manager)."
        }
        if let apiError = error as? APIError {
            return apiError.details
        }
        return error.localizedDescription
    }

    func loadMoreReviews(cursor: String) {
        // In-flight check BEFORE cancelling: the successor task starts
        // before the cancelled predecessor runs its defer, so the internal
        // guard would no-op the tap while leaving the first request killed.
        guard let appId = currentAppId, !isPaginatingReviews else { return }
        reviewsFetchTask?.cancel()
        reviewsGeneration += 1
        let generation = reviewsGeneration
        reviewsInFlightAppId = appId
        reviewsFetchTask = Task { await fetchReviews(appId: appId, cursor: cursor, generation: generation) }
    }

    func loadMoreSubmissions(cursor: String) {
        guard let appId = currentAppId, !isPaginatingSubmissions else { return }
        submissionsFetchTask?.cancel()
        submissionsGeneration += 1
        let generation = submissionsGeneration
        submissionsInFlightAppId = appId
        submissionsFetchTask = Task { await fetchSubmissions(appId: appId, cursor: cursor, generation: generation) }
    }

    // MARK: - Fetches

    /// GET /v1/apps/{id}/customerReviews — composed with the /apps prefix
    /// (getAllApps) + `path`, mirroring the existing buildBetaDetail
    /// pattern. sort=-createdDate (newest first); include=response surfaces
    /// existing developer replies.
    func fetchReviews(appId: String, cursor: String? = nil, generation: Int) async {
        // A cancelled predecessor must not issue work (see ResourcesViewModel.fetch).
        guard !Task.isCancelled else { return }
        let isPaginating = cursor != nil
        // Ignore duplicate "Load more" taps while a page is in flight.
        if isPaginating, isPaginatingReviews { return }
        // Stash the rows before .loading replaces the state: a failed
        // refresh retains them as the marked-stale cache (114:14026).
        let previousRows = reviewsState.loadedValue
        if isPaginating {
            isPaginatingReviews = true
        } else if previousRows == nil {
            // First load: skeletons. A refresh with existing data keeps
            // cached rows visible instead of replacing them (114:13832).
            reviewsState = .loading
        } else {
            isRefreshingReviews = true
        }
        reviewsPaginationFailed = false
        defer {
            if generation == reviewsGeneration {
                if isPaginating { isPaginatingReviews = false }
                isRefreshingReviews = false
                reviewsInFlightAppId = nil
            }
        }

        var queryParams = [
            "sort": "-createdDate",
            "include": "response",
            "limit": String(AppConfigs.reviewLimit)
        ]
        if let cursor {
            queryParams["cursor"] = cursor
        }

        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getAllApps, queryParams: queryParams, path: "\(appId)/customerReviews"),
            apiVersion: .v1) else {
            if !isPaginating {
                reviewsState = .error("No team selected. Add a team to load reviews.")
            }
            return
        }

        do {
            let data = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled,
                  generation == reviewsGeneration,
                  currentAppId == appId else { return }
            let model = try getDecoder().decode(CustomerReviewsDocument.self, from: data)

            let merged: [CustomerReviewModel]
            if isPaginating, let existing = reviewsState.loadedValue {
                let existingIDs = Set(existing.map(\.id))
                merged = existing + model.data.filter { !existingIDs.contains($0.id) }
            } else {
                merged = model.data
            }
            reviewsMeta = model.meta
            reviewsNextCursor = model.meta.paging.nextCursor
            // Staleness id only on success (see load(app:)).
            reviewsLoadedAppId = appId
            reviewsLastSync = Date()
            staleReviewsCache = nil
            reviewsState = merged.isEmpty ? .empty : .loaded(merged)
        } catch {
            guard !Task.isCancelled,
                  generation == reviewsGeneration,
                  currentAppId == appId else { return }
            reviewsLogger.error("Failed to load customer reviews: \(error.localizedDescription)")
            if isPaginating {
                reviewsPaginationFailed = true
            } else {
                // Keep the previous rows as the stale cache when they
                // exist; the error state renders them marked stale.
                staleReviewsCache = previousRows
                reviewsState = .error(friendlyMessage(for: error))
            }
        }
    }

    /// GET /v1/apps/{id}/reviewSubmissions. The app-scoped endpoint exposes
    /// appStoreVersionForReview, which lets the UI bind cancellation to the
    /// exact App Store version instead of guessing from platform alone.
    func fetchSubmissions(appId: String, cursor: String? = nil, generation: Int) async {
        guard !Task.isCancelled else { return }
        let isPaginating = cursor != nil
        if isPaginating, isPaginatingSubmissions { return }
        if isPaginating {
            isPaginatingSubmissions = true
        } else {
            submissionsState = .loading
        }
        submissionsPaginationFailed = false
        defer {
            if generation == submissionsGeneration {
                if isPaginating { isPaginatingSubmissions = false }
                submissionsInFlightAppId = nil
            }
        }

        var queryParams = [
            "include": "appStoreVersionForReview,submittedByActor",
            "limit": String(AppConfigs.reviewLimit)
        ]
        if let cursor {
            queryParams["cursor"] = cursor
        }

        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getAllApps,
                      queryParams: queryParams,
                      path: "\(appId)/reviewSubmissions"),
            apiVersion: .v1) else {
            if !isPaginating {
                submissionsState = .error("No team selected. Add a team to load review submissions.")
            }
            return
        }

        do {
            let data = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled,
                  generation == submissionsGeneration,
                  currentAppId == appId else { return }
            let model = try getDecoder().decode(ReviewSubmissionsDocument.self, from: data)

            let merged: [ReviewSubmissionModel]
            if isPaginating, let existing = submissionsState.loadedValue {
                let existingIDs = Set(existing.map(\.id))
                merged = existing + model.data.filter { !existingIDs.contains($0.id) }
            } else {
                merged = model.data
            }
            // Staleness id only on success (see load(app:)); the paging
            // meta itself isn't rendered, only the cursor is consumed.
            submissionsLoadedAppId = appId
            submissionsNextCursor = model.meta.paging.nextCursor
            submissionsState = merged.isEmpty ? .empty : .loaded(merged)
        } catch {
            guard !Task.isCancelled,
                  generation == submissionsGeneration,
                  currentAppId == appId else { return }
            reviewsLogger.error("Failed to load review submissions: \(error.localizedDescription)")
            if isPaginating {
                submissionsPaginationFailed = true
            } else {
                submissionsState = .error(friendlyMessage(for: error))
            }
        }
    }

    // MARK: - Errors

    /// Reviews need broader roles than a TestFlight-only key provides
    /// (Customer Support / App Manager) — 403s get an actionable hint.
    private func friendlyMessage(for error: Error) -> String {
        if let apiError = error as? APIError {
            if apiError.statusCode == 403 {
                return "\(apiError.details) — this section may need an API key with broader permissions (e.g. App Manager or Customer Support)."
            }
            return FriendlyErrorMessage.message(for: error)
        }
        return FriendlyErrorMessage.message(for: error)
    }
}

// MARK: - POST /customerReviewResponses request body

struct CustomerReviewResponseRequest: Codable {
    let data: CustomerReviewResponseData
}

struct CustomerReviewResponseData: Codable {
    var type: String = "customerReviewResponses"
    let attributes: CustomerReviewResponseAttributes
    let relationships: CustomerReviewResponseRelationships
}

struct CustomerReviewResponseAttributes: Codable {
    let responseBody: String
}

struct CustomerReviewResponseRelationships: Codable {
    let review: ReviewLinkage
}

struct ReviewLinkage: Codable {
    let data: ReviewLinkageData
}

struct ReviewLinkageData: Codable {
    var type: String = "customerReviews"
    let id: String
}

// MARK: - Module 11 · Customer Reviews (C11-H contract)

/// Local date-window filter. Server offers no date parameter — this is
/// applied locally over correctly paginated requests (C11-H).
enum ReviewDateFilter: String, CaseIterable {
    case all = "All dates"
    case last30 = "Last 30 days"
    case last90 = "Last 90 days"

    var displayName: String {
        switch self {
        case .all: return "Date: All"
        case .last30: return "Date: Last 30 days"
        case .last90: return "Date: Last 90 days"
        }
    }

    var days: Int? {
        switch self {
        case .all: return nil
        case .last30: return 30
        case .last90: return 90
        }
    }
}

/// Local sort over loaded pages. The server cursor was issued under
/// sort=-createdDate, so (like the apps list) this reorders loaded pages
/// rather than re-querying — never mixed into a cursor request.
enum ReviewSortOption: String, CaseIterable {
    case newest = "Newest"
    case oldest = "Oldest"
    case highestRated = "Highest rated"
    case lowestRated = "Lowest rated"

    var displayName: String {
        switch self {
        case .newest: return "Sort: Newest ↓"
        case .oldest: return "Sort: Oldest ↑"
        case .highestRated: return "Sort: Highest ★"
        case .lowestRated: return "Sort: Lowest ★"
        }
    }
}

/// Local reply-state filter. Verified absence of a response → unanswered;
/// PENDING_PUBLISH stays separate from PUBLISHED; an unknown or failed
/// fetch is never unanswered (C11-H).
enum ReviewReplyFilter: String, CaseIterable {
    case all = "All"
    case unanswered = "Unanswered"
    case pending = "Pending"
    case published = "Published"

    var displayName: String {
        switch self {
        case .all: return "Reply: All"
        case .unanswered: return "Reply: Unanswered"
        case .pending: return "Reply: Pending"
        case .published: return "Reply: Published"
        }
    }
}

/// Written-review sample statistics. These describe the loaded sample
/// only — never official App Store all-ratings distributions (C11-H).
struct ReviewSampleSummary: Equatable {
    /// Total loaded written reviews in the sample.
    let total: Int
    /// Mean rating over the sample (nil when empty).
    let average: Double?
    /// Counts per star 1...5.
    let perStar: [Int: Int]
}

/// Outcome of POST /v1/customerReviewResponses (create/overwrite).
enum ReplySendOutcome: Equatable {
    /// 201 with the returned resource. State is PENDING_PUBLISH or
    /// PUBLISHED — never automatic storefront success.
    case sent(state: String?, lastModifiedDate: String?)
    /// Explicit Apple validation rejection (e.g. empty responseBody).
    /// Correct the field before resubmitting (C11-E).
    case validationError(String)
    /// 403: reads stay permitted; writes disabled; Save Local Draft
    /// remains useful (C11-R).
    case forbidden(String)
    /// Timeout / connection loss: Apple may have accepted the write.
    /// Reconcile review/response before any retry (114:10569).
    case connectionLost
    /// Defensive no-op (a send is already in flight for this review).
    case ignored
}

/// Outcome of refreshing one review's response (GET detail).
enum ResponseRefreshOutcome: Equatable {
    case updated(state: String?)
    /// Verified absence on a successful fetch → unanswered.
    case unanswered
    /// Failed fetch: unknown, never unanswered.
    case unknown
}

/// Outcome of DELETE /v1/customerReviewResponses/{id} (204, no body).
/// Deletes the developer reply only — never the review or rating.
enum ReplyDeleteOutcome: Equatable {
    case deleted
    case explicitError(String)
    case forbidden(String)
    case connectionLost
    case ignored
}

/// App-owned reply drafts, keyed by account + app + review (C11-H: drafts
/// survive credential and app-context switches; closing never cancels an
/// accepted write).
enum ReviewDraftStore {
    private static let storageKey = "reviews.replyDrafts"
    private struct Draft: Codable {
        let text: String
        let saved: Date
    }

    static func key(account: String?, appId: String, reviewId: String) -> String {
        "\(account ?? "no-account")/\(appId)/\(reviewId)"
    }

    private static func all() -> [String: Draft] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: Draft].self, from: data) else {
            return [:]
        }
        return decoded
    }

    static func load(account: String?, appId: String, reviewId: String) -> (text: String, saved: Date)? {
        guard let draft = all()[key(account: account, appId: appId, reviewId: reviewId)] else {
            return nil
        }
        return (draft.text, draft.saved)
    }

    static func save(_ text: String, account: String?, appId: String, reviewId: String) {
        var drafts = all()
        drafts[key(account: account, appId: appId, reviewId: reviewId)] = Draft(text: text, saved: Date())
        if let data = try? JSONEncoder().encode(drafts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func clear(account: String?, appId: String, reviewId: String) {
        var drafts = all()
        drafts.removeValue(forKey: key(account: account, appId: appId, reviewId: reviewId))
        if let data = try? JSONEncoder().encode(drafts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

extension ReviewsViewModel {
    // MARK: Module 11 filters (all local over paginated loads)

    /// Territories present in the loaded sample (sorted), for the local
    /// territory filter. The server filter[territory] values (USA/CAN/GBR/
    /// DEU/JPN) are a subset of what may appear here.
    var availableTerritories: [String] {
        Array(Set((reviewsState.loadedValue ?? []).compactMap(\.territory))).sorted()
    }

    /// Sample statistics over the loaded written reviews.
    var reviewSampleSummary: ReviewSampleSummary {
        let reviews = reviewsState.loadedValue ?? []
        var perStar: [Int: Int] = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0]
        var sum = 0
        var counted = 0
        for review in reviews {
            guard let rating = review.rating, (1...5).contains(rating) else { continue }
            perStar[rating, default: 0] += 1
            sum += rating
            counted += 1
        }
        return ReviewSampleSummary(
            total: reviews.count,
            average: counted > 0 ? Double(sum) / Double(counted) : nil,
            perStar: perStar
        )
    }

    // MARK: Module 11 loading controls

    /// Cancels an in-flight first load (Cancel Load, 114:13832). Cached
    /// rows stay visible; with no data the state becomes a retryable
    /// error instead of a permanent spinner.
    func cancelReviewsLoad() {
        reviewsFetchTask?.cancel()
        reviewsGeneration += 1
        isPaginatingReviews = false
        reviewsInFlightAppId = nil
        if reviewsState.loadedValue == nil {
            reviewsState = .error("Load cancelled. Retry to fetch reviews.")
        }
    }

    // MARK: Module 11 write paths

    /// True while a POST is in flight for this review (C11-S: duplicate
    /// POST and Delete stay disabled until it resolves).
    func isSendingResponse(reviewId: String) -> Bool {
        sendingResponseIds.contains(reviewId)
    }

    /// POST /v1/customerReviewResponses — create or overwrite the developer
    /// response. Uses the 201-returned record and state; no PATCH and no
    /// delete-first (C11-H).
    func sendResponse(reviewId: String, responseBody: String) async -> ReplySendOutcome {
        let trimmed = responseBody.trimmingCharacters(in: .whitespacesAndNewlines)
        // Client-side field error mirrors C11-E: an empty responseBody is
        // rejected by Apple validation, so it never reaches the API.
        guard !trimmed.isEmpty else {
            return .validationError("Enter a response before submitting. Field: attributes.responseBody.")
        }
        guard !sendingResponseIds.contains(reviewId) else { return .ignored }
        sendingResponseIds.insert(reviewId)
        defer { sendingResponseIds.remove(reviewId) }

        let body = CustomerReviewResponseRequest(
            data: CustomerReviewResponseData(
                attributes: CustomerReviewResponseAttributes(responseBody: trimmed),
                relationships: CustomerReviewResponseRelationships(
                    review: ReviewLinkage(data: ReviewLinkageData(id: reviewId))
                )
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(body),
              let request = APIClient.shared.getRequest(
                api: .post(name: .customerReviewResponses, body: data),
                apiVersion: .v1) else {
            return .validationError("Couldn't build the submit request.")
        }
        do {
            let responseData = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .ignored }
            let model = try getDecoder().decode(CustomerReviewResponseModel.self, from: responseData)
            guard !Task.isCancelled else { return .ignored }
            if case .loaded(var reviews) = reviewsState,
               let index = reviews.firstIndex(where: { $0.id == reviewId }) {
                reviews[index].response = model
                reviewsState = .loaded(reviews)
            }
            responseLastChecked[reviewId] = Date()
            return .sent(state: model.state, lastModifiedDate: model.lastModifiedDate)
        } catch {
            reviewsLogger.error("Failed to send reply: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return Self.classifyReviewWriteError(error)
        }
    }

    /// Classifies write failures into the Figma branches: connection loss
    /// (unconfirmed → reconcile first), 403 (read-only), everything else
    /// (explicit error → fix the cause before resubmitting).
    static func classifyReviewWriteError(_ error: Error) -> ReplySendOutcome {
        if let apiError = error as? APIError, apiError.statusCode == 403 {
            return .forbidden(apiError.details)
        }
        if isReviewConnectivityError(error) {
            return .connectionLost
        }
        if let apiError = error as? APIError {
            return .validationError(apiError.details)
        }
        return .validationError(error.localizedDescription)
    }

    private static func isReviewConnectivityError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return isReviewConnectivityCode(urlError.code)
        }
        let nsError = error as NSError
        if nsError.domain == (NSURLErrorDomain as String) {
            return isReviewConnectivityCode(URLError.Code(rawValue: nsError.code))
        }
        return false
    }

    private static func isReviewConnectivityCode(_ code: URLError.Code) -> Bool {
        switch code {
        case .notConnectedToInternet, .networkConnectionLost,
             .dnsLookupFailed, .cannotFindHost, .cannotConnectToHost,
             .timedOut, .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    /// GET /v1/customerReviews/{id}?include=response — refreshes one
    /// review's response. A successful fetch with no response is verified
    /// absence (unanswered); a failed fetch is unknown, never unanswered.
    func refreshResponse(reviewId: String) async -> ResponseRefreshOutcome {
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .postCustomerReviewResponse,
                      queryParams: ["include": "response"],
                      path: reviewId),
            apiVersion: .v1) else {
            return .unknown
        }
        do {
            let data = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .unknown }
            // Single-resource documents decode like the list path (same
            // pattern as the build follow-up fetch in BuildProcessingMonitor).
            let review = try getDecoder().decode(CustomerReviewModel.self, from: data)
            guard !Task.isCancelled else { return .unknown }
            if case .loaded(var reviews) = reviewsState,
               let index = reviews.firstIndex(where: { $0.id == reviewId }) {
                reviews[index].response = review.response
                reviewsState = .loaded(reviews)
            }
            responseLastChecked[reviewId] = Date()
            if review.response == nil {
                deleteAcceptedReviewIds.remove(reviewId)
            }
            return review.response == nil ? .unanswered : .updated(state: review.response?.state)
        } catch {
            reviewsLogger.error("Failed to refresh response: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .unknown }
            return .unknown
        }
    }

    /// DELETE /v1/customerReviewResponses/{id} — removes the developer
    /// reply only (never the review/rating). 204 carries no body; the row
    /// keeps its reply until Refresh verifies absence (storefront lag).
    func deleteResponse(reviewId: String, responseId: String) async -> ReplyDeleteOutcome {
        guard !deletingResponseIds.contains(reviewId) else { return .ignored }
        deletingResponseIds.insert(reviewId)
        defer { deletingResponseIds.remove(reviewId) }
        guard let request = APIClient.shared.getRequest(
            api: .delete(name: .customerReviewResponses, path: responseId),
            apiVersion: .v1) else {
            return .explicitError("Couldn't build the delete request.")
        }
        do {
            _ = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .ignored }
            // Accepted, refresh pending: do NOT clear the row — verified
            // absence only comes from a follow-up refresh (114:10689).
            deleteAcceptedReviewIds.insert(reviewId)
            return .deleted
        } catch {
            reviewsLogger.error("Failed to delete reply: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            if let apiError = error as? APIError, apiError.statusCode == 403 {
                return .forbidden(apiError.details)
            }
            if Self.isReviewConnectivityError(error) {
                return .connectionLost
            }
            if let apiError = error as? APIError {
                return .explicitError(apiError.details)
            }
            return .explicitError(error.localizedDescription)
        }
    }

    // MARK: Module 11 cross-app page fetch

    /// One page of reviews for any app (cross-app inbox). Same query as
    /// the per-app fetch (sort=-createdDate, include=response, limit 50):
    /// cursors stay scoped to the app+query that issued them.
    struct ReviewListPage {
        let reviews: [CustomerReviewModel]
        let nextCursor: String?
        let total: Int?
    }

    static func fetchReviewListPage(appId: String, cursor: String? = nil) async throws -> ReviewListPage {
        var queryParams = [
            "sort": "-createdDate",
            "include": "response",
            "limit": String(AppConfigs.reviewLimit)
        ]
        if let cursor {
            queryParams["cursor"] = cursor
        }
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getAllApps, queryParams: queryParams, path: "\(appId)/customerReviews"),
            apiVersion: .v1) else {
            throw APIError.apiError(error: "No team selected.")
        }
        let data = try await APIClient.shared.callAPI(with: request)
        let model = try getDecoder().decode(CustomerReviewsDocument.self, from: data)
        return ReviewListPage(reviews: model.data, nextCursor: model.meta.paging.nextCursor, total: model.meta.paging.total)
    }
}
