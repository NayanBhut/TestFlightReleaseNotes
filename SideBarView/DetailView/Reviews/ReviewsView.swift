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
                            submissionsSection
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
                }
                .onChange(of: app.id) { _, _ in
                    reviewsViewModel.load(app: app)
                }
            } else {
                EmptyStateView(icon: "star.bubble", title: "No App Selected",
                               subtitle: "Select an app from the sidebar to view its reviews")
            }
        }
    }

    // MARK: - Header

    private func header(app: AppsData) -> some View {
        HStack {
            Text("Reviews")
                .font(.sectionHeader)
                .fontWeight(.semibold)
            Spacer()
            Text(app.name ?? "")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Button(action: { reviewsViewModel.retryAll() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
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
                .font(.caption)
                .frame(maxWidth: 200)

            Spacer()

            if reviewsViewModel.ratingFilter > 0 || reviewsViewModel.stateFilter != .all || !reviewsViewModel.searchText.isEmpty {
                Button("Clear") {
                    reviewsViewModel.ratingFilter = 0
                    reviewsViewModel.stateFilter = .all
                    reviewsViewModel.searchText = ""
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }

    // MARK: - Review submissions

    @ViewBuilder private var submissionsSection: some View {
        InfoCard(title: "Review Submissions", systemImage: "doc.badge.gearshape") {
            switch reviewsViewModel.submissionsState {
            case .idle, .loading:
                LoadingStateView(text: "Loading...")
            case .empty:
                Text("No review submissions")
                    .font(.caption)
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
                                    .font(.body)
                                    .fontWeight(.medium)
                                if let version = submission.appStoreVersion?.versionString, !version.isEmpty {
                                    Text("Version \(version)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                if let submitter = submission.submittedByActor {
                                    Text("Submitted by \(submitter.displayName)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(submission.submittedDate ?? "")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
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

    // MARK: - Customer reviews

    @ViewBuilder private var reviewsSection: some View {
        InfoCard(title: "Customer Reviews", systemImage: "star.bubble") {
            switch reviewsViewModel.reviewsState {
            case .idle, .loading:
                LoadingStateView(text: "Loading...")
            case .empty:
                Text("No customer reviews")
                    .font(.caption)
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
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        if let total = reviewsViewModel.reviewsMeta?.paging.total {
                            Text("\(filtered.count) of \(total) total")
                                .font(.caption2)
                                .foregroundColor(.secondary)
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
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer()
                Text(review.territory ?? "")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(review.reviewerNickname ?? "")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(review.body ?? "")
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text(review.createdDate ?? "")
                .font(.caption2)
                .foregroundColor(.secondary)
            if let response = review.response {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Developer reply (\(response.state ?? "PUBLISHED"))")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text(response.responseBody ?? "")
                            .font(.caption)
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
                .font(.caption)
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
                    .font(.caption)
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
            .font(.caption)
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
                    .font(.caption2)
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

    private var color: Color {
        switch text.uppercased() {
        case "COMPLETE", "APPROVED", "ACCEPTED", "ENABLED", "ACTIVE", "VALID":
            return .green
        case "WAITING_FOR_REVIEW", "READY_FOR_REVIEW":
            // Orange, not yellow: yellow on yellow.opacity(0.15) fails
            // contrast against light-mode surfaces.
            return .orange
        case "IN_REVIEW":
            return .blue
        case "UNRESOLVED_ISSUES", "REJECTED", "INVALID":
            return .red
        case "CANCELING", "COMPLETING":
            return .orange
        default:
            return .secondary
        }
    }

    var body: some View {
        Text(text)
            .font(.caption2)
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
