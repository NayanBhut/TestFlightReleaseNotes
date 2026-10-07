//
//  ShipyardToast.swift
//  App Store
//
//  One app-wide write-feedback channel. Every mutating action in the Shipyard
//  sections posts its `WriteResult` here so the user always learns whether the
//  write landed — the failure mode this replaces was silent success (a saved
//  role change looked identical to a no-op) and a dead error banner in
//  UsersTableView that was rendered but never assigned.
//
//  Figma 76:31853 — bottom-trailing toast, status dot, semibold title,
//  muted detail line, trailing dismiss button.
//
//

import SwiftUI

// MARK: - Message

/// A single toast. Carries an identity so two consecutive identical messages
/// still re-fire the view's `onChange` (which only triggers on a value
/// change), matching `ToastEvent`'s existing trick.
struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var detail: String?
    var variant: ToastVariant

    init(_ title: String, detail: String? = nil, variant: ToastVariant = .neutral) {
        self.title = title
        self.detail = detail
        self.variant = variant
    }

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool { lhs.id == rhs.id }
}

// MARK: - Center

/// Observable holder so the toast renders once, at the shell, while any
/// descendant view (or view model) can post to it. Owns the auto-dismiss
/// timer — the generation counter stops a superseded timer from clearing a
/// newer toast that is already on screen.
@MainActor
final class ShipyardToastCenter: ObservableObject {
    /// Seconds a toast stays up. Errors linger longer than successes: they
    /// carry text the user has to actually read, and they are the ones that
    /// were previously being dropped entirely.
    static let successDuration: TimeInterval = 5
    static let errorDuration: TimeInterval = 9

    @Published private(set) var current: ToastMessage?

    private var generation = 0

    func show(_ message: ToastMessage, duration: TimeInterval? = nil) {
        generation += 1
        let generation = self.generation
        current = message

        let duration = duration
            ?? (message.variant == .error || message.variant == .warning
                ? Self.errorDuration
                : Self.successDuration)

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard let self, self.generation == generation else { return }
            self.current = nil
        }
    }

    func show(_ title: String, detail: String? = nil, variant: ToastVariant = .neutral) {
        show(ToastMessage(title, detail: detail, variant: variant))
    }

    func dismiss() {
        generation += 1
        current = nil
    }
}

// MARK: - Write-result bridging

extension ShipyardToastCenter {
    /// Single funnel for every write outcome, so no call site can forget to
    /// report one. `.success` posts the supplied confirmation; `.failure`
    /// posts the view model's already-human message (permission hints and all);
    /// `.ignored` stays silent because it means "superseded", not "failed".
    func report(
        _ result: ResourcesViewModel.WriteResult,
        success title: String,
        successDetail: String? = nil,
        errorTitle: String = "Couldn't save changes"
    ) {
        switch result {
        case .success:
            show(title, detail: successDetail, variant: .success)
        case .failure(let message):
            show(errorTitle, detail: message, variant: .error)
        case .ignored:
            break
        }
    }

    func report(
        _ result: DetailViewModel.AppInfoSaveResult,
        success title: String,
        successDetail: String? = nil,
        errorTitle: String = "Couldn't save App Info"
    ) {
        switch result {
        case .success:
            show(title, detail: successDetail, variant: .success)
        case .failure(let message):
            show(errorTitle, detail: message, variant: .error)
        case .ignored:
            break
        }
    }

    func report(
        _ result: DetailViewModel.VersionLocalizationSaveResult,
        success title: String,
        successDetail: String? = nil,
        errorTitle: String = "Couldn't save App Info"
    ) {
        switch result {
        case .success:
            show(title, detail: successDetail, variant: .success)
        case .failure(let message):
            show(errorTitle, detail: message, variant: .error)
        case .ignored:
            break
        }
    }

    func report(
        _ result: DetailViewModel.ScreenshotUploadResult,
        success title: String,
        successDetail: String? = nil,
        errorTitle: String = "Couldn't update screenshots"
    ) {
        switch result {
        case .success:
            show(title, detail: successDetail, variant: .success)
        case .failure(let message):
            show(errorTitle, detail: message, variant: .error)
        case .ignored:
            break
        }
    }
}

// MARK: - View

/// Bottom-trailing toast. Success/warning/error tint the leading dot so the
/// state reads at a glance; neutral keeps the plain dot.
struct ShipyardToastView: View {
    var title: String
    var detail: String?
    var variant: ToastVariant
    var onDismiss: () -> Void

    /// Caps how wide the text column grows so a long failure message wraps
    /// onto multiple lines instead of stretching into one very long line
    /// across the window. Sized to keep the Figma 348pt toast intact for
    /// short copy while giving ~3–4 wrapped lines for verbose API errors.
    private let maxTextWidth: CGFloat = 360

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(variant.dotColor)
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Bound the text column so it wraps; `fixedSize(vertical:)` above
            // then lets the toast grow downward as lines are added.
            .frame(maxWidth: maxTextWidth, alignment: .leading)

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(ShipyardTheme.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss notification")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(variant.toastBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ShipyardTheme.rowDivider, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        // Width follows the content up to the cap; height always fits the
        // content, so no message is ever clipped vertically.
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

private extension ToastVariant {
    /// Figma draws a plain green dot; the tinted variants reuse the same dot
    /// shape so the silhouette never changes between states.
    var dotColor: Color { self == .neutral ? ShipyardTheme.success : tint }

    var toastBackground: some View { background }
}

// MARK: - Overlay

extension View {
    /// Bottom-trailing toast overlay. `bottomInset` clears the section footer
    /// (56pt action bar + 16pt padding) so the toast never covers Save/Remove.
    ///
    /// Dismissal is routed through `center` so the pending auto-dismiss timer
    /// is cancelled — a stale timer must never clear a newer toast.
    func shipyardToast(
        _ toast: ToastMessage?,
        center: ShipyardToastCenter,
        bottomInset: CGFloat = 72
    ) -> some View {
        overlay(alignment: .bottomTrailing) {
            if let toast {
                ShipyardToastView(
                    title: toast.title,
                    detail: toast.detail,
                    variant: toast.variant
                ) {
                    center.dismiss()
                }
                .padding(.trailing, 24)
                .padding(.bottom, bottomInset)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toast)
    }
}
