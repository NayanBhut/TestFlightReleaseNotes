//
//  ReviewsView.swift
//  App Store
//
//  Batch C3: read-only Reviews tab — customer reviews (rating/title/body)
//  and review submissions (state). Replying via POST /customerReviewResponses
//  is a follow-up.
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
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            submissionsSection
                            reviewsSection
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .onAppear {
                    reviewsViewModel.load(app: app)
                }
                .onChange(of: app.id) { _, _ in
                    reviewsViewModel.load(app: app)
                }
            } else {
                emptyState(icon: "star.bubble", title: "No App Selected",
                           subtitle: "Select an app from the sidebar to view its reviews")
            }
        }
    }

    // MARK: - Header

    private func header(app: AppsData) -> some View {
        HStack {
            Text("Reviews")
                .font(.title2)
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
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Review submissions

    @ViewBuilder private var submissionsSection: some View {
        InfoCard(title: "Review Submissions", systemImage: "doc.badge.gearshape") {
            switch reviewsViewModel.submissionsState {
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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
                                    .font(.subheadline)
                                    .fontWeight(.medium)
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
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case .empty:
                Text("No customer reviews")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .error(let message):
                sectionError(message: message) {
                    reviewsViewModel.retryReviews()
                }
            case .loaded(let reviews):
                VStack(alignment: .leading, spacing: 12) {
                    if let total = reviewsViewModel.reviewsMeta?.paging.total {
                        Text("\(total) total")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    ForEach(reviews, id: \.id) { review in
                        if review.id != reviews.first?.id { Divider() }
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

    private func reviewRow(_ review: CustomerReviewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                StarRating(rating: review.rating ?? 0)
                Text(review.title ?? "")
                    .font(.subheadline)
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
                .font(.subheadline)
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
                .background(Color(nsColor: .windowBackgroundColor))
                .cornerRadius(6)
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

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(title)
                .font(.title3)
                .fontWeight(.medium)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
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
