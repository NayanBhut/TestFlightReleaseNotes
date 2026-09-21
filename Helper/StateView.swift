//
//  StateView.swift
//  App Store

import SwiftUI

/// Reusable empty-state renderer — replaces the duplicated
/// emptyState(icon:title:subtitle:) in BetaGroupView, AppInfoView,
/// and ReviewsView. Same visual structure everywhere: centered
/// icon, title, subtitle.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 44))
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
        .frame(maxWidth: .infinity)
    }
}

/// Reusable loading-state renderer — replaces the inline
/// ProgressView + "Loading..." blocks in BetaGroupView,
/// AppInfoView (section method), ReviewsView (submissions & reviews).
struct LoadingStateView: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

/// Reusable inline error renderer — replaces the inline
/// error message + Retry button pattern in ReviewsView's
/// submissionsSection and reviewsSection.
struct StateErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Retry", action: onRetry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

#Preview {
    VStack(spacing: 32) {
        EmptyStateView(icon: "info.circle", title: "No App Selected", subtitle: "Select an app from the sidebar")
        LoadingStateView(text: "Loading...")
    }
}
