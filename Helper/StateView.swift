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
                .font(.subheader)
                .fontWeight(.medium)
            Text(subtitle)
                .font(.appBody)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

/// One-time appear-bounce for large empty-state icons: fades and scales
/// in once (0.3 s, never looping) with hierarchical symbol rendering for
/// depth. Shared so every empty state feels identical.
private struct EmptyStateIconModifier: ViewModifier {
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .symbolRenderingMode(.hierarchical)
            .scaleEffect(appeared ? 1 : 0.9)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) {
                    appeared = true
                }
            }
    }
}

extension View {
    /// `symbolRenderingMode(.hierarchical)` plus a one-time scale+fade-in
    /// for empty-state icons (use at size-48 icon sites).
    func emptyStateIconAppear() -> some View {
        modifier(EmptyStateIconModifier())
    }
}

/// Reusable loading-state renderer — replaces the inline
/// ProgressView + "Loading..." blocks in BetaGroupView,
/// AppInfoView (section method), ReviewsView (submissions & reviews).
struct LoadingStateView: View {
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView().scaleEffect(1.1)
            Text(text)
                .font(.appBody)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
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
                .font(.appCaption)
                .foregroundColor(.secondary)
            Button("Retry", action: onRetry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

/// Tap feedback for row-style targets (app rows, version chips): a small
/// scale-down plus dim while pressed, springing back on release. Defined
/// once here and reused at every site so the feel stays identical.
struct PressableScaleButtonStyle: ButtonStyle {
    /// How far the target shrinks while pressed.
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableScaleButtonStyle {
    /// `.buttonStyle(.pressableScale)` — defined once in StateView.swift.
    static var pressableScale: PressableScaleButtonStyle { .init() }
}

#Preview {
    VStack(spacing: 32) {
        EmptyStateView(icon: "info.circle", title: "No App Selected", subtitle: "Select an app from the sidebar")
        LoadingStateView(text: "Loading...")
    }
}
