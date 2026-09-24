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

@MainActor
final class ReviewsViewModel: ObservableObject {
    deinit {
        // A stuck network call must not keep the VM alive.
        reviewsFetchTask?.cancel()
        submissionsFetchTask?.cancel()
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

    // MARK: - Staleness / in-flight bookkeeping

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
    /// State filter: all / replied / unreplied (based on developer reply presence).
    @Published var stateFilter: AppConfigs.ReviewStateFilter = .all
    /// Local text search across title, body, and reviewer nickname.
    @Published var searchText: String = ""

    /// Customer reviews after applying active filters (rating, state, search).
    var filteredReviews: [CustomerReviewModel] {
        filterReviews(reviewsState.loadedValue ?? [])
    }

    private func filterReviews(_ reviews: [CustomerReviewModel]) -> [CustomerReviewModel] {
        var result = reviews
        if ratingFilter > 0 {
            result = result.filter { ($0.rating ?? 0) == ratingFilter }
        }
        switch stateFilter {
        case .replied:
            result = result.filter { $0.response != nil }
        case .unreplied:
            result = result.filter { $0.response == nil }
        default:
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
        return result
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
        }
        currentAppId = app.id
        if reviewsLoadedAppId != app.id, reviewsInFlightAppId != app.id {
            reviewsFetchTask?.cancel()
            reviewsInFlightAppId = app.id
            reviewsFetchTask = Task { await fetchReviews(appId: app.id) }
        }
        if submissionsLoadedAppId != app.id, submissionsInFlightAppId != app.id {
            submissionsFetchTask?.cancel()
            submissionsInFlightAppId = app.id
            submissionsFetchTask = Task { await fetchSubmissions(appId: app.id) }
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
        currentAppId = nil
        reviewsLoadedAppId = nil
        submissionsLoadedAppId = nil
        reviewsInFlightAppId = nil
        submissionsInFlightAppId = nil
        reviewsState = .idle
        submissionsState = .idle
        reviewsMeta = nil
        reviewsNextCursor = nil
        submissionsNextCursor = nil
        reviewsPaginationFailed = false
        submissionsPaginationFailed = false
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
        reviewsInFlightAppId = appId
        submissionsInFlightAppId = appId
        reviewsFetchTask = Task { await fetchReviews(appId: appId) }
        submissionsFetchTask = Task { await fetchSubmissions(appId: appId) }
    }

    func retryReviews() {
        guard let appId = currentAppId else { return }
        reviewsFetchTask?.cancel()
        reviewsInFlightAppId = appId
        reviewsFetchTask = Task { await fetchReviews(appId: appId) }
    }

    func retrySubmissions() {
        guard let appId = currentAppId else { return }
        submissionsFetchTask?.cancel()
        submissionsInFlightAppId = appId
        submissionsFetchTask = Task { await fetchSubmissions(appId: appId) }
    }

    /// POST /v1/customerReviews/{id}/customerReviewResponses.
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
                api: .post(name: .postCustomerReviewResponse,
                           body: data,
                           path: "\(reviewId)/customerReviewResponses"),
                apiVersion: .v1) else {
            return false
        }

        do {
            let responseData = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return false }
            let model = try getDecoder().decode(CustomerReviewResponseModel.self,
                                                from: responseData)
            // Optimistic update: set the response on the review row.
            guard case .loaded(var reviews) = reviewsState,
                  let index = reviews.firstIndex(where: { $0.id == reviewId }) else { return false }
            reviews[index].response = model
            reviewsState = .loaded(reviews)
            return true
        } catch {
            reviewsLogger.error("Failed to reply to review: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Submit for review / cancel

    /// Full submit pipeline (verified against spec v4.3.1 + the ASC
    /// submission workflow): POST /reviewSubmissions → POST
    /// /reviewSubmissionItems linking the appStoreVersion → PATCH the
    /// submission {submitted: true}. A POST alone only creates a draft.
    /// `versionId` is required — the UI disables submit without one.
    func submitForReview(appId: String, versionId: String) async -> Bool {
        guard !submittingReview else { return false }
        submittingReview = true
        defer { submittingReview = false }

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
            guard !Task.isCancelled else { return false }
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
            guard !Task.isCancelled else { return false }

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
            guard !Task.isCancelled else { return false }

            // Invalidate so the next load refetches with the new row.
            submissionsLoadedAppId = nil
            submissionsFetchTask = Task { await fetchSubmissions(appId: appId) }
            return true
        } catch {
            guard !Task.isCancelled else { return false }
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
        cancellingSubmissionId = submission.id
        defer { cancellingSubmissionId = nil }

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
            guard !Task.isCancelled else { return false }
            submissionsLoadedAppId = nil
            submissionsFetchTask = Task { await fetchSubmissions(appId: appId) }
            return true
        } catch {
            guard !Task.isCancelled else { return false }
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
        phasedLoading = true
        defer { phasedLoading = false }
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getAppStoreVersions, path: "\(versionId)/appStoreVersionPhasedRelease"),
            apiVersion: .v1) else {
            writeError = APIError.jsonConversionFailure.details
            return
        }
        do {
            let data = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled, phasedVersionId == versionId else { return }
            phasedRelease = try getDecoder().decode(PhasedReleaseModel.self, from: data)
        } catch {
            guard !Task.isCancelled, phasedVersionId == versionId else { return }
            if let apiError = error as? APIError, apiError.statusCode == 404 {
                phasedRelease = nil
            } else {
                reviewsLogger.error("Failed to load phased release: \(error.localizedDescription)")
                writeError = writeMessage(for: error)
            }
        }
    }

    /// POST /v1/appStoreVersionPhasedReleases — starts phased release for
    /// a version that has none. Refetches state on success.
    func startPhasedRelease(versionId: String) async -> Bool {
        guard !phasedActionInFlight else { return false }
        phasedActionInFlight = true
        defer { phasedActionInFlight = false }

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
            guard !Task.isCancelled else { return false }
            phasedRelease = try getDecoder().decode(PhasedReleaseModel.self, from: response)
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            reviewsLogger.error("Failed to start phased release: \(error.localizedDescription)")
            writeError = writeMessage(for: error)
            return false
        }
    }

    /// PATCH state transitions: ACTIVE (start/resume), PAUSED (pause),
    /// COMPLETE (finish). Updates local state on success, no refetch needed.
    func setPhasedReleaseState(_ state: String) async -> Bool {
        guard !phasedActionInFlight, let release = phasedRelease else { return false }
        phasedActionInFlight = true
        defer { phasedActionInFlight = false }

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
            guard !Task.isCancelled else { return false }
            phasedRelease = try getDecoder().decode(PhasedReleaseModel.self, from: response)
            return true
        } catch {
            guard !Task.isCancelled else { return false }
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
        reviewsInFlightAppId = appId
        reviewsFetchTask = Task { await fetchReviews(appId: appId, cursor: cursor) }
    }

    func loadMoreSubmissions(cursor: String) {
        guard let appId = currentAppId, !isPaginatingSubmissions else { return }
        submissionsFetchTask?.cancel()
        submissionsInFlightAppId = appId
        submissionsFetchTask = Task { await fetchSubmissions(appId: appId, cursor: cursor) }
    }

    // MARK: - Fetches

    /// GET /v1/apps/{id}/customerReviews — composed with the /apps prefix
    /// (getAllApps) + `path`, mirroring the existing buildBetaDetail
    /// pattern. sort=-createdDate (newest first); include=response surfaces
    /// existing developer replies.
    func fetchReviews(appId: String, cursor: String? = nil) async {
        // A cancelled predecessor must not issue work (see ResourcesViewModel.fetch).
        guard !Task.isCancelled else { return }
        let isPaginating = cursor != nil
        // Ignore duplicate "Load more" taps while a page is in flight.
        if isPaginating, isPaginatingReviews { return }
        if isPaginating {
            isPaginatingReviews = true
        } else {
            reviewsState = .loading
        }
        reviewsPaginationFailed = false
        defer {
            if isPaginating { isPaginatingReviews = false }
            reviewsInFlightAppId = nil
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
            guard !Task.isCancelled else { return }
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
            reviewsState = merged.isEmpty ? .empty : .loaded(merged)
        } catch {
            guard !Task.isCancelled else { return }
            reviewsLogger.error("Failed to load customer reviews: \(error.localizedDescription)")
            if isPaginating {
                reviewsPaginationFailed = true
            } else {
                reviewsState = .error(friendlyMessage(for: error))
            }
        }
    }

    /// GET /v1/reviewSubmissions?filter[app]={id}&include=submittedByActor.
    /// The collection has no sort parameter (verified against the OpenAPI
    /// spec), so order is the server's default. NOTE: the list endpoint's
    /// include enum is narrower than the detail endpoint's — it rejects
    /// appStoreVersion ("not a valid relationship name", verified at
    /// runtime), so the version relationship + row UI stay nil on list
    /// rows until a valid path for them is found.
    func fetchSubmissions(appId: String, cursor: String? = nil) async {
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
            if isPaginating { isPaginatingSubmissions = false }
            submissionsInFlightAppId = nil
        }

        var queryParams = [
            "filter[app]": appId,
            "include": "submittedByActor",
            "limit": String(AppConfigs.reviewLimit)
        ]
        if let cursor {
            queryParams["cursor"] = cursor
        }

        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getReviewSubmissions, queryParams: queryParams),
            apiVersion: .v1) else {
            if !isPaginating {
                submissionsState = .error("No team selected. Add a team to load review submissions.")
            }
            return
        }

        do {
            let data = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return }
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
            guard !Task.isCancelled else { return }
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
            return apiError.details
        }
        return error.localizedDescription
    }
}

// MARK: - POST /customerReviewResponses request body

struct CustomerReviewResponseRequest: Codable {
    let data: CustomerReviewResponseData
}

struct CustomerReviewResponseData: Codable {
    let type: String = "customerReviewResponses"
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
    let type: String = "customerReviews"
    let id: String
}

