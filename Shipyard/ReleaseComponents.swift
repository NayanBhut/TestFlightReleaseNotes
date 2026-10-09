//
//  ReleaseComponents.swift
//  App Store
//
//  Shared chrome for the App Store Versions workspace: status badges,
//  summary cards, state alerts, the phased-rollout progress bar, toasts,
//  and the date/copy formatting the state screens share.
//

import SwiftUI

// MARK: - Top-pinned scroll container

/// ScrollView whose content stays pinned to the top even when it is
/// shorter than the viewport. SwiftUI's macOS ScrollView distributes the
/// leftover vertical space around short content, so state screens render
/// floating in the middle of the window; forcing the document to fill the
/// viewport height removes that slack. Long content still scrolls: the
/// minHeight is only a floor, never a ceiling.
struct TopPinnedScrollView<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, minHeight: max(geo.size.height, 1), alignment: .topLeading)
            }
        }
    }
}

// MARK: - Status badge

/// Dot + label pill used in headings and tables (Figma status badges).
struct ReleaseStatusBadge: View {
    var state: String?
    var dot: Color? = nil

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dot ?? ReleaseComponents.badgeDot(for: state))
                .frame(width: 6, height: 6)
            Text(getStatusLabel(appStoreState: state))
                .font(.system(size: 10))
                .foregroundColor(ShipyardTheme.title)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(ReleaseComponents.badgeFill(for: state))
        .cornerRadius(10)
        .accessibilityIdentifier("review.status.\(state ?? "UNKNOWN")")
    }
}

enum ReleaseComponents {
    static func badgeDot(for state: String?) -> Color {
        switch state {
        case "READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "PENDING_APPLE_RELEASE":
            return ShipyardTheme.success
        case "REJECTED", "DEVELOPER_REJECTED", "METADATA_REJECTED", "INVALID_BINARY":
            return ShipyardTheme.danger
        case "WAITING_FOR_REVIEW", "IN_REVIEW":
            return ShipyardTheme.warning
        default:
            return ShipyardTheme.body
        }
    }

    static func badgeFill(for state: String?) -> Color {
        switch state {
        case "WAITING_FOR_REVIEW", "IN_REVIEW":
            return Color.orange.opacity(0.15)
        default:
            return ShipyardTheme.tableHeader
        }
    }

    /// Apple's fixed phased-rollout ladder: day → percent of users.
    static func phasedPercent(day: Int) -> Int {
        switch day {
        case 1: return 1
        case 2: return 2
        case 3: return 5
        case 4: return 10
        case 5: return 20
        case 6: return 50
        default: return day >= 7 ? 100 : 1
        }
    }
}

// MARK: - Summary card

/// Bordered key/value card (Submitted summary, confirmation dialogs).
struct ReleaseSummaryCard: View {
    var rows: [(label: String, value: String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 12) {
                    Text(rows[index].label)
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                    Spacer(minLength: 16)
                    Text(rows[index].value)
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.title)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .background(ShipyardTheme.tableBackground)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(LaunchTheme.border, lineWidth: 1)
        )
    }
}

// MARK: - State alert

/// Full-width alert banner. Gray = neutral, blue = informational,
// amber = pending attention, green = success, red = rejection.
struct ReleaseAlert: View {
    enum Style {
        case neutral, info, warning, success, danger
    }

    var style: Style = .neutral
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
            Text(detail)
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(fill)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(border, lineWidth: 1)
        )
    }

    private var fill: Color {
        switch style {
        case .neutral: return ShipyardTheme.tableBackground
        case .info: return ShipyardTheme.accent.opacity(0.12)
        case .warning: return Color.orange.opacity(0.12)
        case .success: return ShipyardTheme.success.opacity(0.1)
        case .danger: return ShipyardTheme.danger.opacity(0.08)
        }
    }

    private var border: Color {
        switch style {
        case .neutral: return LaunchTheme.border
        case .info: return ShipyardTheme.accent
        case .warning: return Color.orange
        case .success: return ShipyardTheme.success
        case .danger: return ShipyardTheme.danger
        }
    }
}

// MARK: - Phased progress

/// Seven-segment rollout bar (1/2/5/10/20/50/100%) with the completed
/// days filled.
struct PhasedProgressBar: View {
    var day: Int

    private let ladder = [1, 2, 5, 10, 20, 50, 100]

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                HStack(spacing: 4) {
                    ForEach(ladder.indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(index < day ? ShipyardTheme.accent : ShipyardTheme.tableHeader)
                            .frame(width: (geometry.size.width - 24) / 7, height: 6)
                    }
                }
            }
            .frame(height: 6)
            HStack(spacing: 0) {
                ForEach(ladder.indices, id: \.self) { index in
                    Text("\(ladder[index])%")
                        .font(.system(size: 10))
                        .foregroundColor(ShipyardTheme.body)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Toast

/// Bottom-right confirmation toast ("Submitted for review",
/// "Submission cancelled") with auto-dismiss handled by the caller.
struct ReleaseToast: View {
    var title: String
    var detail: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ShipyardTheme.success)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
            }
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(ShipyardTheme.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(LaunchTheme.page)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(LaunchTheme.border, lineWidth: 1)
        )
    }
}

// MARK: - Formatting

/// "Sep 30, 2026 at 10:45 AM" for summary rows and history lines.
func releaseDateTimeDisplay(_ raw: String?) -> String {
    guard let date = releaseDateValue(raw) else { return "—" }
    let day = DateFormatter()
    day.dateFormat = "MMM d, yyyy"
    let time = DateFormatter()
    time.dateFormat = "h:mm a"
    return "\(day.string(from: date)) at \(time.string(from: date))"
}

/// "Sep 30, 2026" for table cells.
func releaseDayDisplay(_ raw: String?) -> String {
    guard let date = releaseDateValue(raw) else { return "—" }
    let day = DateFormatter()
    day.dateFormat = "MMM d, yyyy"
    return day.string(from: date)
}

private func releaseDateValue(_ raw: String?) -> Date? {
    guard let raw, !raw.isEmpty else { return nil }
    if let date = sharedISOFormatter.date(from: raw) { return date }
    return buildUploadDate(raw)
}

func humanizedReleaseType(_ raw: String?) -> String {
    switch raw {
    case AppStoreVersionReleaseType.manual.rawValue: return "Manually release"
    case AppStoreVersionReleaseType.afterApproval.rawValue: return "Automatically release after approval"
    case AppStoreVersionReleaseType.scheduled.rawValue: return "Automatically release on a specific date"
    default: return "—"
    }
}

func phasedReleaseDisplay(state: String?) -> String {
    switch (state ?? "").uppercased() {
    case "ACTIVE": return "Enabled · 7 days"
    case "PAUSED": return "Paused"
    case "INACTIVE": return "Not started"
    case "COMPLETE": return "Complete · all users"
    default: return "Disabled"
    }
}
