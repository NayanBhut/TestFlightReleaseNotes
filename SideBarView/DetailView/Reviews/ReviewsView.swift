//
//  ReviewsView.swift
//  App Store
//
//  Batch C3: Reviews tab — customer reviews (rating/title/body) and
//  review submissions (state). Reply via POST /customerReviewResponses
//  is implemented in replyToReview().
//

import SwiftUI

struct ReviewsView: View {
    @ObservedObject var reviewsViewModel: ReviewsViewModel
    var selectedApp: AppsData?
    @State private var confirmingSubmit = false
    @State private var submissionToCancel: ReviewSubmissionModel?
    @State private var confirmingCompletePhased = false

    var body: some View {
        Group {
            if let app = selectedApp {
                VStack(spacing: 0) {
                    header(app: app)
                    filterBar(app: app)
                    Divider()
                    // Side-by-side columns, each with its own scroll: a tall
                    // submissions list can no longer push reviews off-screen.
                    // Horizontal padding lives here, not inside the
                    // ScrollViews, so the inter-column gap is exactly the
                    // HStack spacing (16pt) instead of padding+spacing+padding.
                    HStack(alignment: .top, spacing: 16) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                submissionsSection(app: app)
                                phasedReleaseSection(app: app)
                            }
                            .padding(.vertical, 20)
                        }
                        ScrollView {
                            reviewsSection
                                .padding(.vertical, 20)
                        }
                    }
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .onAppear {
                    reviewsViewModel.load(app: app)
                    selectDefaultPhasedVersion(app: app)
                }
                .onChange(of: app.id) { _, _ in
                    reviewsViewModel.load(app: app)
                    selectDefaultPhasedVersion(app: app)
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
            } else {
                EmptyStateView(icon: "star.bubble", title: "No App Selected",
                               subtitle: "Select an app from the sidebar to view its reviews")
            }
        }
    }

    /// Defaults the phased-release version picker to the first App Store
    /// version and loads its phased-release state.
    private func selectDefaultPhasedVersion(app: AppsData) {
        guard reviewsViewModel.phasedVersionId == nil,
              let first = app.appStoreVersions.first else { return }
        reviewsViewModel.phasedVersionId = first.id
        Task { await reviewsViewModel.loadPhasedRelease(versionId: first.id) }
    }

    // MARK: - Header

    private func header(app: AppsData) -> some View {
        HStack {
            Text("Reviews")
                .font(.sectionHeader)
                .fontWeight(.semibold)
            Spacer()
            Text(app.name ?? "")
                .font(.appCaption)
                .foregroundColor(.secondary)
                .lineLimit(1)
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

    // MARK: - Filter bar

    private func filterBar(app: AppsData) -> some View {
        HStack(spacing: 12) {
            Picker("Rating", selection: $reviewsViewModel.ratingFilter) {
                ForEach(AppConfigs.ratingOptions, id: \.self) { value in
                    Text(value == 0 ? "All ratings" : "\(value) ★").tag(value)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 110)

            Picker("State", selection: $reviewsViewModel.stateFilter) {
                ForEach(AppConfigs.ReviewStateFilter.allCases, id: \.self) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 110)

            TextField("Search title / body / author", text: $reviewsViewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .font(.appCaption)
                .frame(maxWidth: 200)

            Spacer()

            if reviewsViewModel.ratingFilter > 0 || reviewsViewModel.stateFilter != .all || !reviewsViewModel.searchText.isEmpty {
                Button("Clear") {
                    reviewsViewModel.ratingFilter = 0
                    reviewsViewModel.stateFilter = .all
                    reviewsViewModel.searchText = ""
                }
                .font(.appCaption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }

    // MARK: - Review submissions

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
                                if let version = submission.appStoreVersion?.versionString, !version.isEmpty {
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
                                    .foregroundColor(.red)
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
        let submittableVersionId = app.appStoreVersions.first?.id
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
                .disabled(hasOpenSubmission || submittableVersionId == nil)
                .help(submittableVersionId == nil
                      ? "The app has no App Store version to submit"
                      : (hasOpenSubmission ? "An open review submission already exists" : ""))
                .confirmationDialog(
                    "Submit for App Review?",
                    isPresented: $confirmingSubmit,
                    titleVisibility: .visible
                ) {
                    Button("Submit") {
                        guard let versionId = submittableVersionId else { return }
                        Task {
                            await reviewsViewModel.submitForReview(appId: app.id, versionId: versionId)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This submits \(app.name ?? "the app") \(app.appStoreVersions.first?.versionString ?? "") to App Store review.")
                }
            }
        }
    }

    // MARK: - Phased release

    /// Gradual rollout controls for one App Store version. State is read
    /// from GET /v1/appStoreVersions/{id}/appStoreVersionPhasedRelease
    /// (404 = none started); writes go through the top-level
    /// /v1/appStoreVersionPhasedReleases collection.
    @ViewBuilder private func phasedReleaseSection(app: AppsData) -> some View {
        InfoCard(title: "Phased Release", systemImage: "tortoise") {
            if app.appStoreVersions.isEmpty {
                Text("No App Store versions for this app")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
            } else {
                HStack {
                    Menu {
                        ForEach(app.appStoreVersions, id: \.id) { version in
                            Button(version.versionString ?? version.id) {
                                reviewsViewModel.phasedVersionId = version.id
                                Task {
                                    await reviewsViewModel.loadPhasedRelease(versionId: version.id)
                                }
                            }
                        }
                    } label: {
                        Label(
                            app.appStoreVersions.first(where: { $0.id == reviewsViewModel.phasedVersionId })?.versionString ?? "Select version",
                            systemImage: "chevron.down"
                        )
                        .font(.appCaption)
                    }
                    .menuStyle(.borderlessButton)

                    Spacer()

                    phasedStateContent
                }
            }
        }
    }

    @ViewBuilder private var phasedStateContent: some View {
        if reviewsViewModel.phasedLoading {
            ProgressView()
                .controlSize(.small)
        } else if reviewsViewModel.phasedActionInFlight {
            ProgressView()
                .controlSize(.small)
        } else if let release = reviewsViewModel.phasedRelease {
            let state = release.phasedReleaseState ?? "UNKNOWN"
            StateChip(text: state)
            switch state.uppercased() {
            case "ACTIVE":
                Button("Pause") {
                    Task { await reviewsViewModel.setPhasedReleaseState("PAUSED") }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case "PAUSED", "INACTIVE":
                Button("Resume") {
                    Task { await reviewsViewModel.setPhasedReleaseState("ACTIVE") }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("Complete") {
                    confirmingCompletePhased = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .confirmationDialog(
                    "Complete Phased Release?",
                    isPresented: $confirmingCompletePhased,
                    titleVisibility: .visible
                ) {
                    Button("Complete Release", role: .destructive) {
                        Task { await reviewsViewModel.setPhasedReleaseState("COMPLETE") }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The version releases to all remaining users immediately. This cannot be undone.")
                }
            default:
                EmptyView()
            }
        } else if let versionId = reviewsViewModel.phasedVersionId {
            Text("Not started")
                .font(.appCaption)
                .foregroundColor(.secondary)
            Button("Start") {
                Task { await reviewsViewModel.startPhasedRelease(versionId: versionId) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    // MARK: - Customer reviews

    @ViewBuilder private var reviewsSection: some View {
        InfoCard(title: "Customer Reviews", systemImage: "star.bubble") {
            switch reviewsViewModel.reviewsState {
            case .idle, .loading:
                LoadingStateView(text: "Loading...")
            case .empty:
                Text("No customer reviews")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
            case .error(let message):
                sectionError(message: message) {
                    reviewsViewModel.retryReviews()
                }
            case .loaded:
                VStack(alignment: .leading, spacing: 12) {
                    let filtered = reviewsViewModel.filteredReviews
                    if filtered.isEmpty {
                        Text(reviewsViewModel.ratingFilter > 0 || reviewsViewModel.stateFilter != .all || !reviewsViewModel.searchText.isEmpty
                              ? "No reviews match your filters" : "No customer reviews")
                            .font(.appCaption)
                            .foregroundColor(.secondary)
                    } else {
                        if let total = reviewsViewModel.reviewsMeta?.paging.total {
                            Text("\(filtered.count) of \(total) total")
                                .font(.appCaption2)
                                .foregroundColor(.secondary)
                                .contentTransition(.numericText())
                        }
                        ForEach(filtered, id: \.id) { review in
                            if review.id != filtered.first?.id { Divider() }
                            reviewRow(review)
                        }
                        paginationControls(
                            nextCursor: reviewsViewModel.reviewsNextCursor,
                            paginationFailed: reviewsViewModel.reviewsPaginationFailed,
                            onLoadMore: { cursor in reviewsViewModel.loadMoreReviews(cursor: cursor) }
                        )
                    }
                }
            }
        }
    }

    private func reviewRow(_ review: CustomerReviewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                StarRating(rating: review.rating ?? 0)
                Text(review.title ?? "")
                    .font(.appBody)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer()
                Text(review.territory ?? "")
                    .font(.appCaption2)
                    .foregroundColor(.secondary)
            }
            Text(review.reviewerNickname ?? "")
                .font(.appCaption2)
                .foregroundColor(.secondary)
            Text(review.body ?? "")
                .font(.appBody)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text(review.createdDate ?? "")
                .font(.appCaption2)
                .foregroundColor(.secondary)
            if let response = review.response {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.appCaption2)
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Developer reply (\(response.state ?? "PUBLISHED"))")
                            .font(.appCaption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text(response.responseBody ?? "")
                            .font(.appCaption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .padding(8)
                .background(AppTheme.windowBackground)
                .cornerRadius(6)
            }
            if review.response == nil {
                ReplySection(reviewId: review.id,
                              reviewsViewModel: reviewsViewModel)
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

// MARK: - Reply controls

struct ReplySection: View {
    let reviewId: String
    @ObservedObject var reviewsViewModel: ReviewsViewModel
    @State private var isReplying = false
    @State private var replyText: String = ""

    var body: some View {
        if isReplying {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Write a reply...", text: $replyText)
                    .textFieldStyle(.roundedBorder)
                    .font(.appCaption)
                HStack {
                    Button("Cancel") {
                        isReplying = false
                        replyText = ""
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.secondary)
                    Spacer()
                    Button("Send") {
                        Task { @MainActor in
                            let posted = await reviewsViewModel.replyToReview(
                                reviewId: reviewId,
                                responseBody: replyText
                            )
                            // Keep the composer open on failure so the
                            // typed reply is never silently discarded.
                            if posted {
                                isReplying = false
                                replyText = ""
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(8)
            .background(AppTheme.windowBackground)
            .cornerRadius(6)
        } else {
            Button("Reply") {
                isReplying = true
            }
            .font(.appCaption)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
        }
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

#Preview {
    ReviewsView(reviewsViewModel: ReviewsViewModel(), selectedApp: nil)
}
