//
//  ReviewsView.swift
//  App Store
//
//  Module 11 (Customer Reviews): written-review summary (average +
//  histogram over the loaded sample), filter chips, the Review / Rating /
//  Date / Response table, the reply editor with its lifecycle branches,
//  and the independent list states (loading / empty / error / no filter
//  results). The review-submissions card below is preserved unchanged —
//  App Store review submission is outside Module 11 scope.
//
//  API contract notes (C11-H, Apple OpenAPI 4.5):
//  - Reads: GET /v1/apps/{id}/customerReviews (sort=-createdDate,
//    include=response). Rating/territory server filters exist, but text
//    search, date windows, reply-state filters, cross-app aggregation and
//    averages stay local over correctly paginated requests.
//  - Histograms describe the loaded written-review sample only — never
//    official App Store all-ratings distributions. Partial coverage and
//    per-request provenance stay visible.
//  - Verified absence of a response → Unanswered. PENDING_PUBLISH stays
//    separate from PUBLISHED. Unknown/failed fetches are never unanswered.
//

import SwiftUI

struct ReviewsView: View {
    @ObservedObject var reviewsViewModel: ReviewsViewModel
    var selectedApp: AppsData?
    @EnvironmentObject private var toastCenter: ShipyardToastCenter
    @State private var confirmingSubmit = false
    @State private var submissionToCancel: ReviewSubmissionModel?
    /// Master-detail navigation inside the tab (Figma editor screens).
    @State private var selectedReviewId: String? = nil
    @State private var highlightedReviewId: String? = nil
    @State private var showSyncDetails = false

    var body: some View {
        Group {
            if let app = selectedApp {
                VStack(spacing: 0) {
                    header(app: app)
                    Divider()
                    if let reviewId = selectedReviewId {
                        ReviewReplyEditorView(
                            reviewId: reviewId,
                            app: app,
                            reviewsVM: reviewsViewModel,
                            isStale: reviewsViewModel.isShowingStaleReviews,
                            onReturnToInbox: nil,
                            onBack: { selectedReviewId = nil }
                        )
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                customerReviewsSection(app: app)
                                submissionsSection(app: app)
                            }
                            .padding(20)
                        }
                    }
                }
                .onAppear {
                    reviewsViewModel.load(app: app)
                    consumePendingInboxReview()
                }
                .onChange(of: app.id) { _, _ in
                    selectedReviewId = nil
                    reviewsViewModel.load(app: app)
                    consumePendingInboxReview()
                }
                .onChange(of: reviewsViewModel.pendingInboxReviewId) { _, _ in
                    consumePendingInboxReview()
                }
                .onChange(of: reviewsViewModel.writeError) { _, message in
                    if let message {
                        toastCenter.show("Review action failed", detail: message, variant: .error)
                    }
                }
                .alert("Action Failed",
                       isPresented: Binding(
                        get: { reviewsViewModel.writeError != nil },
                        set: { if !$0 { reviewsViewModel.writeError = nil } }
                       ),
                       presenting: reviewsViewModel.writeError
                ) { _ in
                    Button("OK", role: .cancel) {}
                } message: { message in
                    Text(message)
                }
                .sheet(isPresented: $showSyncDetails) {
                    syncDetailsSheet(app: app)
                }
            } else {
                EmptyStateView(icon: "star.bubble", title: "No App Selected",
                               subtitle: "Select an app from the sidebar to view its reviews")
            }
        }
    }

    /// Review opened from the cross-app inbox: jump the tab onto it.
    private func consumePendingInboxReview() {
        guard let reviewId = reviewsViewModel.pendingInboxReviewId else { return }
        reviewsViewModel.pendingInboxReviewId = nil
        highlightedReviewId = reviewId
        selectedReviewId = reviewId
    }

    // MARK: - Header

    private func header(app: AppsData) -> some View {
        HStack {
            Text(selectedReviewId == nil ? "Reviews" : "Review Detail")
                .font(.sectionHeader)
                .fontWeight(.semibold)
            Spacer()
            Text(app.name ?? "")
                .font(.appCaption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            if reviewsViewModel.isRefreshingReviews {
                ProgressView()
                    .controlSize(.small)
                    .help("Refreshing reviews… cached rows stay visible")
            }
            Button(action: { reviewsViewModel.retryAll() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.appCaption)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(AppTheme.secondaryBackground)
    }

    // MARK: - Written-review summary (114:10098)

    @ViewBuilder
    private func customerReviewsSection(app: AppsData) -> some View {
        InfoCard(title: "Customer Reviews", systemImage: "star.bubble") {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(app.name ?? "App") · written customer reviews")
                    .font(.appBody)
                    .fontWeight(.semibold)
                filterChips
                provenanceBanner
                switch reviewsViewModel.reviewsState {
                case .idle, .loading:
                    if reviewsViewModel.reviewRows.isEmpty {
                        loadingState(app)
                    } else {
                        reviewsTable(app: app)
                    }
                case .empty:
                    emptyState(app: app)
                case .error(let message):
                    errorState(app: app, message: message)
                case .loaded:
                    if reviewsViewModel.filteredReviews.isEmpty {
                        if reviewsViewModel.reviewRows.isEmpty {
                            emptyState(app: app)
                        } else {
                            noFilterResultsState(app)
                        }
                    } else {
                        summaryBlock
                        reviewsTable(app: app)
                    }
                }
            }
        }
    }

    // MARK: Filters (all local)

    private var hasActiveFilters: Bool {
        reviewsViewModel.ratingFilter > 0
            || reviewsViewModel.territoryFilter != nil
            || reviewsViewModel.dateFilter != .all
            || reviewsViewModel.reviewSort != .newest
            || reviewsViewModel.replyFilter != .all
            || !reviewsViewModel.searchText.isEmpty
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            Menu {
                Button("All ratings") { reviewsViewModel.ratingFilter = 0 }
                ForEach(AppConfigs.ratingOptions.filter { $0 > 0 }, id: \.self) { value in
                    Button("\(value) ★") { reviewsViewModel.ratingFilter = value }
                }
            } label: {
                Text(reviewsViewModel.ratingFilter == 0 ? "Rating: All" : "Rating: \(reviewsViewModel.ratingFilter) ★")
                    .font(.appCaption)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.bordered)
            .controlSize(.small)

            Menu {
                Button("All territories") { reviewsViewModel.territoryFilter = nil }
                ForEach(reviewsViewModel.availableTerritories, id: \.self) { territory in
                    Button(territory) { reviewsViewModel.territoryFilter = territory }
                }
            } label: {
                Text("Territory: \(reviewsViewModel.territoryFilter ?? "All")")
                    .font(.appCaption)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.bordered)
            .controlSize(.small)

            Menu {
                ForEach(ReviewDateFilter.allCases, id: \.self) { option in
                    Button(option.rawValue) { reviewsViewModel.dateFilter = option }
                }
            } label: {
                Text(reviewsViewModel.dateFilter.displayName)
                    .font(.appCaption)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.bordered)
            .controlSize(.small)

            Menu {
                ForEach(ReviewSortOption.allCases, id: \.self) { option in
                    Button(option.rawValue) { reviewsViewModel.reviewSort = option }
                }
            } label: {
                Text(reviewsViewModel.reviewSort.displayName)
                    .font(.appCaption)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.bordered)
            .controlSize(.small)

            Menu {
                ForEach(ReviewReplyFilter.allCases, id: \.self) { option in
                    Button(option.rawValue) { reviewsViewModel.replyFilter = option }
                }
            } label: {
                Text(reviewsViewModel.replyFilter.displayName)
                    .font(.appCaption)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.bordered)
            .controlSize(.small)

            TextField("Search title / body / author", text: $reviewsViewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .font(.appCaption)
                .frame(maxWidth: 200)

            if hasActiveFilters {
                Button("Clear") { clearFilters() }
                    .font(.appCaption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func clearFilters() {
        reviewsViewModel.ratingFilter = 0
        reviewsViewModel.territoryFilter = nil
        reviewsViewModel.dateFilter = .all
        reviewsViewModel.reviewSort = .newest
        reviewsViewModel.replyFilter = .all
        reviewsViewModel.searchText = ""
    }

    private var provenanceBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Scope: loaded written reviews only — not official App Store rating totals. API: rating/territory filters and createdDate sorting.")
                .font(.appCaption2)
                .foregroundColor(.secondary)
            Text("Text, date-window and reply-state filters are local over paginated results; partial coverage remains visible.")
                .font(.appCaption2)
                .foregroundColor(.secondary)
            Text("No response → Unanswered. PENDING_PUBLISH and PUBLISHED are separate; no published response can still have a pending reply.")
                .font(.appCaption2)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.06))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.blue.opacity(0.25), lineWidth: 0.5))
    }

    // MARK: Summary (sample statistics)

    private var summaryBlock: some View {
        let summary = reviewsViewModel.reviewSampleSummary
        return HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                if let average = summary.average {
                    Text(String(format: "%.1f", average))
                        .font(.system(size: 36, weight: .semibold))
                    StarRating(rating: Int(round(average)))
                    Text("\(summary.total) loaded written reviews")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                } else {
                    Text("—")
                        .font(.system(size: 36, weight: .semibold))
                    Text("\(summary.total) loaded written reviews")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 180, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                ForEach((1...5).reversed(), id: \.self) { stars in
                    let count = summary.perStar[stars, default: 0]
                    let share = summary.total > 0 ? Double(count) / Double(summary.total) : 0
                    HStack(spacing: 12) {
                        Text("\(stars) ★")
                            .font(.appCaption)
                            .foregroundColor(.secondary)
                            .frame(width: 36, alignment: .leading)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 8)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.blue)
                                    .frame(width: proxy.size.width * share, height: 8)
                            }
                        }
                        .frame(height: 8)
                        Text("\(count)")
                            .font(.appCaption)
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .leading)
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.windowBackground)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))
    }

    // MARK: Reviews table

    private func reviewsTable(app: AppsData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if reviewsViewModel.isRefreshingReviews {
                Text("Refreshing reviews… cached rows stay visible.")
                    .font(.appCaption2)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
            }
            if reviewsViewModel.isShowingStaleReviews {
                Text("Cached snapshot · stale · editing disabled until refresh succeeds.")
                    .font(.appCaption2)
                    .foregroundColor(.orange)
                    .padding(.bottom, 8)
            }
            tableHeader(columns: ["Review", "Rating", "Date", "Response"])
            ForEach(reviewsViewModel.filteredReviews, id: \.id) { review in
                Button {
                    highlightedReviewId = review.id
                    selectedReviewId = review.id
                } label: {
                    HStack(spacing: 12) {
                        Text(review.title?.isEmpty == false ? review.title! : String((review.body ?? "").prefix(60)))
                            .font(.appBody)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(reviewStarsText(review.rating))
                            .font(.appCaption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(review.createdDate.map(reviewDisplayDate) ?? "—")
                            .font(.appCaption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(responseCellText(review))
                            .font(.appCaption)
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(highlightedReviewId == review.id ? Color.blue.opacity(0.08) : Color.clear)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                Divider()
            }
            tableFooter(app)
        }
    }

    private func responseCellText(_ review: CustomerReviewModel) -> String {
        switch review.response?.state {
        case "PUBLISHED":
            return "PUBLISHED · edit reply →"
        case "PENDING_PUBLISH":
            return "PENDING_PUBLISH · open detail →"
        default:
            return "No response · open detail →"
        }
    }

    private func tableHeader(columns: [String]) -> some View {
        HStack(spacing: 12) {
            ForEach(columns, id: \.self) { column in
                Text(column)
                    .font(.appCaption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(AppTheme.secondaryBackground)
    }

    private func tableFooter(_ app: AppsData) -> some View {
        HStack(spacing: 12) {
            Text(syncStatusLine(app))
                .font(.appCaption2)
                .foregroundColor(.secondary)
            Spacer()
            if let cursor = reviewsViewModel.reviewsNextCursor {
                if reviewsViewModel.reviewsPaginationFailed {
                    Button("Couldn't load more — Retry") {
                        reviewsViewModel.loadMoreReviews(cursor: cursor)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button("Load more") {
                        reviewsViewModel.loadMoreReviews(cursor: cursor)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            Button("Open Selected Review") {
                let target = highlightedReviewId
                    ?? reviewsViewModel.filteredReviews.first?.id
                if let target {
                    highlightedReviewId = target
                    selectedReviewId = target
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(reviewsViewModel.filteredReviews.isEmpty)
        }
        .padding(.top, 12)
    }

    private func syncStatusLine(_ app: AppsData) -> String {
        var parts: [String] = []
        if let sync = reviewsViewModel.reviewsLastSync {
            parts.append("Last synced \(reviewDateTime(sync))")
        } else {
            parts.append("Not yet synced")
        }
        parts.append(CredentialStorage.shared.selectedTeam?.key ?? "Team")
        if reviewsViewModel.reviewsNextCursor != nil || (reviewsViewModel.reviewsMeta?.paging.total ?? 0) > reviewsViewModel.reviewRows.count {
            parts.append("paginated sample · partial coverage")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - List states (11S, independent alternatives)

    /// First load: info banner + skeleton rows + Cancel Load. A refresh
    /// with existing data never replaces rows with skeletons (114:13832).
    private func loadingState(_ app: AppsData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Loading reviews…")
                        .font(.appBody)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                    Text("First load · controls that require loaded resources are unavailable. A refresh with existing data keeps cached rows visible instead of replacing them with skeletons.")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color.blue.opacity(0.06))
            .cornerRadius(8)
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { _ in
                    HStack(spacing: 24) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.2)).frame(width: 180, height: 10)
                        RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.2)).frame(width: 240, height: 10)
                        RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.2)).frame(width: 140, height: 10)
                        RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.2)).frame(width: 100, height: 10)
                    }
                    .padding(12)
                    .frame(height: 38)
                }
            }
            HStack {
                Spacer()
                Button("Cancel Load") {
                    reviewsViewModel.cancelReviewsLoad()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    /// Empty team: reviews appear after customers post them — Shipyard
    /// cannot create customer reviews (114:13942).
    private func emptyState(app: AppsData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("No reviews yet")
                        .font(.appBody)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                    Text("Customer reviews will appear after customers post them. Reviews cannot be created by Shipyard.")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color.blue.opacity(0.06))
            .cornerRadius(8)
            Text("Get started")
                .font(.appBody)
                .fontWeight(.medium)
            Text("Open App Store Listing opens the public listing in your browser. Shipyard cannot create customer reviews.")
                .font(.appCaption)
                .foregroundColor(.secondary)
            HStack {
                Spacer()
                Button("Open App Store Listing") {
                    openStoreListing(app: app)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private func openStoreListing(app: AppsData) {
        let query = app.bundleId ?? app.name ?? ""
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://apps.apple.com/us/search?term=\(encoded)") {
            ASCLink.open(url)
        }
    }

    /// Failed refresh: retained cache shows marked stale with editing
    /// disabled; with no cache the error shows with Retry and no rows.
    private func errorState(app: AppsData, message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unable to refresh reviews")
                        .font(.appBody)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                    if reviewsViewModel.staleReviewsCache != nil {
                        Text("Network connection failed. Cached data is retained below and marked stale. If no cache exists, show this error with Retry and no resource rows.")
                            .font(.appCaption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(message)
                            .font(.appCaption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color.red.opacity(0.06))
            .cornerRadius(8)
            if reviewsViewModel.staleReviewsCache != nil {
                reviewsTable(app: app)
            }
            HStack {
                Text(staleFooterText)
                    .font(.appCaption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Show Sync Details") { showSyncDetails = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Retry Refresh") {
                    reviewsViewModel.retryReviews()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private var staleFooterText: String {
        "Cached snapshot · stale · editing disabled until refresh succeeds"
    }

    /// Filters match nothing: reviews still exist — clear search & filters.
    /// Distinct from an empty team (114:14123).
    private func noFilterResultsState(_ app: AppsData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("No matching reviews")
                        .font(.appBody)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                    Text("No rows match “\(reviewsViewModel.searchText)”. Your reviews still exist; clear the search and filters to see them. This is not an empty team.")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color.blue.opacity(0.06))
            .cornerRadius(8)
            HStack {
                Spacer()
                Button("Clear Search & Filters") { clearFilters() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    private func syncDetailsSheet(app: AppsData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sync Details")
                .font(.system(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text("App: \(app.name ?? app.id)")
                Text("Scope: \(CredentialStorage.shared.selectedTeam?.key ?? "Team")")
                Text("Last sync: \(reviewsViewModel.reviewsLastSync.map(reviewDateTime) ?? "never")")
                Text("Loaded rows: \(reviewsViewModel.reviewRows.count)")
                if let total = reviewsViewModel.reviewsMeta?.paging.total {
                    Text("Server total: \(total) (paginated sample · partial coverage)")
                }
                Text("Filters: rating \(reviewsViewModel.ratingFilter == 0 ? "all" : "\(reviewsViewModel.ratingFilter)"), territory \(reviewsViewModel.territoryFilter ?? "all"), reply \(reviewsViewModel.replyFilter.rawValue)")
            }
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            HStack {
                Spacer()
                Button("Close") { showSyncDetails = false }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    // MARK: - Review submissions (preserved; outside Module 11 scope)

    @ViewBuilder private func submissionsSection(app: AppsData) -> some View {
        InfoCard(title: "Review Submissions", systemImage: "doc.badge.gearshape") {
            submitRow(app: app)
            Divider()
            switch reviewsViewModel.submissionsState {
            case .idle, .loading:
                LoadingStateView(text: "Loading...")
            case .empty:
                Text("No review submissions")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
            case .error(let message):
                sectionError(message: message) {
                    reviewsViewModel.retrySubmissions()
                }
            case .loaded(let submissions):
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(submissions, id: \.id) { submission in
                        if submission.id != submissions.first?.id { Divider() }
                        HStack(alignment: .top, spacing: 10) {
                            StateChip(text: submission.state ?? "UNKNOWN")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(submission.platform ?? "")
                                    .font(.appBody)
                                    .fontWeight(.medium)
                                if let version = submission.appStoreVersionForReview?.versionString, !version.isEmpty {
                                    Text("Version \(version)")
                                        .font(.appCaption)
                                        .foregroundColor(.secondary)
                                }
                                if let submitter = submission.submittedByActor {
                                    Text("Submitted by \(submitter.displayName)")
                                        .font(.appCaption)
                                        .foregroundColor(.secondary)
                                }
                                Text(submission.submittedDate ?? "")
                                    .font(.appCaption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if ReviewsViewModel.cancellableSubmissionStates
                                .contains(submission.state ?? "") {
                                if reviewsViewModel.cancellingSubmissionId == submission.id {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Button("Cancel") {
                                        submissionToCancel = submission
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .foregroundColor(AppTheme.negative)
                                }
                            }
                        }
                    }
                    .confirmationDialog(
                        "Cancel Review Submission?",
                        isPresented: Binding(
                            get: { submissionToCancel != nil },
                            set: { if !$0 { submissionToCancel = nil } }
                        ),
                        titleVisibility: .visible,
                        presenting: submissionToCancel
                    ) { submission in
                        Button("Cancel Submission", role: .destructive) {
                            Task {
                                await reviewsViewModel.cancelSubmission(submission)
                            }
                        }
                    } message: { _ in
                        Text("The submission will be withdrawn from review.")
                    }
                    paginationControls(
                        nextCursor: reviewsViewModel.submissionsNextCursor,
                        paginationFailed: reviewsViewModel.submissionsPaginationFailed,
                        onLoadMore: { cursor in reviewsViewModel.loadMoreSubmissions(cursor: cursor) }
                    )
                }
            }
        }
    }

    /// Submit-for-review action row. Submitting is a server-side state
    /// change, so it asks for confirmation first. Disabled while an open
    /// submission exists (the server 409s duplicates) or when the app has
    /// no App Store version to submit (the pipeline requires one).
    @ViewBuilder private func submitRow(app: AppsData) -> some View {
        let hasOpenSubmission = reviewsViewModel.submissionsState.loadedValue?.contains {
            !["COMPLETE", "CANCELING"].contains($0.state ?? "")
        } ?? false
        let submittableVersion = reviewsViewModel.submissionVersion
        let submittableVersionId = submittableVersion?.id
        let hasAttachedBuild = submittableVersion?.build != nil
        HStack {
            Text("Send the app for App Store review")
                .font(.appCaption)
                .foregroundColor(.secondary)
            Spacer()
            if reviewsViewModel.submittingReview {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(hasOpenSubmission ? "Submission in progress" : "Submit for Review") {
                    confirmingSubmit = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(hasOpenSubmission || !reviewsViewModel.canSubmitForReview)
                .help(!hasAttachedBuild
                      ? "Attach an eligible build before submitting"
                      : (hasOpenSubmission ? "An open review submission already exists" : ""))
                .confirmationDialog(
                    "Submit for App Review?",
                    isPresented: $confirmingSubmit,
                    titleVisibility: .visible
                ) {
                    Button("Submit") {
                        guard let versionId = submittableVersionId else { return }
                        guard hasAttachedBuild else { return }
                        Task {
                            await reviewsViewModel.submitForReview(appId: app.id, versionId: versionId)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This submits \(app.name ?? "the app") \(submittableVersion?.versionString ?? "") to App Store review.")
                }
            }
        }
    }

    // MARK: - Shared

    @ViewBuilder
    private func paginationControls(nextCursor: String?,
                                    paginationFailed: Bool,
                                    onLoadMore: @escaping (String) -> Void) -> some View {
        if let nextCursor {
            HStack {
                if paginationFailed {
                    Button("Couldn't load more — Retry") {
                        onLoadMore(nextCursor)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button("Load more") {
                        onLoadMore(nextCursor)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func sectionError(message: String, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.appCaption)
                .foregroundColor(.secondary)
            Button("Retry", action: retry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

struct NewVersionView: View {
    @ObservedObject var reviewsViewModel: ReviewsViewModel
    let app: AppsData?
    @Environment(\.dismiss) private var dismiss
    @State private var versionString = ""
    @State private var platform: AppStoreVersionPlatform = .iOS
    @State private var copyright = ""
    @State private var buildNumber = ""
    @State private var releaseType: AppStoreVersionReleaseType = .afterApproval
    @State private var earliestReleaseDate = Date()

    init(reviewsViewModel: ReviewsViewModel, app: AppsData?) {
        self.reviewsViewModel = reviewsViewModel
        self.app = app
        let creatable = reviewsViewModel.creatableAppStoreVersionPlatforms
        let selected = reviewsViewModel.selectedAppStoreVersionPlatform
            .flatMap(AppStoreVersionPlatform.init(rawValue:))
        _platform = State(initialValue: selected.flatMap { value in
            creatable.contains(value) ? value : creatable.first
        } ?? .iOS)
    }

    private var creatablePlatforms: [AppStoreVersionPlatform] {
        reviewsViewModel.creatableAppStoreVersionPlatforms
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("New App Store Version")
                    .font(.sectionHeader)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Divider()
            Form {
                TextField("Version string", text: $versionString)
                Picker("Platform", selection: $platform) {
                    ForEach(creatablePlatforms) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                TextField("Copyright", text: $copyright)
                TextField("Build number (optional)", text: $buildNumber)
                Picker("Release type", selection: $releaseType) {
                    ForEach(AppStoreVersionReleaseType.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                if releaseType == .scheduled {
                    DatePicker("Release no earlier than", selection: $earliestReleaseDate)
                        .datePickerStyle(.compact)
                }
            }
            .formStyle(.grouped)
            if let error = reviewsViewModel.createVersionError {
                Text(error)
                    .font(.appCaption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button {
                    guard let app else { return }
                    Task {
                        let created = await reviewsViewModel.createVersion(
                            appId: app.id,
                            versionString: versionString,
                            platform: platform,
                            copyright: copyright,
                            releaseType: releaseType,
                            buildNumber: buildNumber,
                            earliestReleaseDate: releaseType == .scheduled ? earliestReleaseDate : nil)
                        if created { dismiss() }
                    }
                } label: {
                    if reviewsViewModel.creatingVersion {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Create Version")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(reviewsViewModel.creatingVersion || versionString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - Star rating

/// Filled/empty stars for a 1–5 rating.
struct StarRating: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.appCaption2)
                    .foregroundColor(star <= rating ? .yellow : .secondary)
            }
        }
        // Collapse the five star images into one VoiceOver element so
        // each image isn't announced separately.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rating) of 5 stars")
    }
}

// MARK: - State chip

/// Small colored pill for review/app states (mirrors the sidebar's
/// version-state chips).
struct StateChip: View {
    let text: String

    private var color: Color { text.stateColor }

    var body: some View {
        Text(text)
            .font(.appCaption2)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .cornerRadius(4)
    }
}

// MARK: - Reusable card

/// A bordered, read-only grouping used across the Reviews tabs (moved here
/// from the removed legacy App Info view, its other consumer).
/// Scoped name (`InfoCard`, not `Card`) so it can't collide with
/// other generic card views in the module.
struct InfoCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheader)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.secondaryBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}

#Preview {
    ReviewsView(reviewsViewModel: ReviewsViewModel(), selectedApp: nil)
}
