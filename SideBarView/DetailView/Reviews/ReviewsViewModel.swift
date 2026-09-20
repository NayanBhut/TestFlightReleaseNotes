//
//  ReviewsViewModel.swift
//  App Store
//
//  Batch C3: Customer reviews + review submissions (read-only).
//  Follows the BetaViewModel pattern: staleness via currentAppId, in-flight
//  task cancellation, cursor pagination with a retry on failure.
//  Replying (POST /customerReviewResponses) is a follow-up.
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

    // MARK: - Loading

    /// Loads both lists for the app. Safe to call from onAppear on every
    /// tab switch: only lists that are stale (not yet loaded successfully)
    /// for this app are (re)fetched, and in-flight fetches for the same app
    /// are not cancelled-and-restarted.
    func load(app: AppsData) {
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

    /// GET /v1/reviewSubmissions?filter[app]={id}. The collection has no
    /// sort parameter (verified against the OpenAPI spec), so order is the
    /// server's default.
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
