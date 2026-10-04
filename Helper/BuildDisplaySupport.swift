//
//  BuildDisplaySupport.swift
//  App Store
//
//  Shared build display helpers + toast variant + release-note snippets,
//  extracted from the legacy BuildDetailsView/BuildRowView files when the
//  legacy shells were removed. Still used by Shipyard views,
//  BuildProcessingMonitor, DetailViewModel, and unit tests.
//

import SwiftUI

/// Toast feedback variant: neutral (default, current look) or tinted
/// success/error/warning with a matching icon.
enum ToastVariant {
    case neutral
    case success
    case error
    case warning

    var systemImage: String? {
        switch self {
        case .neutral: return nil
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .neutral: return .secondary
        case .success: return .green
        case .error: return .red
        case .warning: return .orange
        }
    }

    /// Tinted background wash over the opaque neutral base; the neutral
    /// variant keeps the existing look. Tinted variants layer over the
    /// opaque base so scrolling content never bleeds through the toast.
    var background: some View {
        switch self {
        case .neutral:
            return AnyView(AppTheme.secondaryBackground)
        default:
            return AnyView(
                AppTheme.secondaryBackground
                    .overlay(tint.opacity(0.12))
            )
        }
    }
}

// MARK: - Shared build display helpers
//
// Single place for upload-date formatting (absolute + relative) and build
// status. Views use these instead of inline closures so formatting stays
// consistent and testable.

enum BuildDisplayHelper {
    // nonisolated(unsafe): formatters are not Sendable, but every caller
    // is a SwiftUI view body or @MainActor monitor — never concurrent.
    // This avoids per-render allocation while satisfying Swift 6.
    private nonisolated(unsafe) static let iso8601Formatter = ISO8601DateFormatter()

    private nonisolated(unsafe) static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()

    private nonisolated(unsafe) static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static func uploadedDate(from dateString: String?) -> Date? {
        guard let dateString = dateString, !dateString.isEmpty else { return nil }
        return iso8601Formatter.date(from: dateString)
    }

    /// Single absolute date format used across build rows.
    static func formattedUploadedDate(_ dateString: String?) -> String {
        guard let date = uploadedDate(from: dateString) else { return "" }
        return displayFormatter.string(from: date)
    }

    /// Relative time ("3 days ago") shown next to the absolute date.
    static func relativeUploadedTime(_ dateString: String?) -> String? {
        guard let date = uploadedDate(from: dateString) else { return nil }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func buildStatus(processingState: String, isExpired: Bool) -> (String, Color) {
        if isExpired {
            return ("EXPIRED", .red)
        }

        switch processingState {
        case "PROCESSING":
            return ("PROCESSING", .yellow)
        case "FAILED":
            return ("FAILED", .red)
        case "INVALID":
            return ("INVALID", .orange)
        case "VALID":
            return ("VALID", .green)
        default:
            return ("", .clear)
        }
    }
}

// MARK: - Build stats + list animation math
//
// Pure, UI-free helpers behind the builds header strip and the staggered
// row entrance. Kept separate from the views so unit tests can cover them
// without hosting SwiftUI.

/// Minimal build status projection for counting. Decouples `BuildStats`
/// from `BuildsModel` (whose macro-generated inits are awkward in tests).
struct BuildStatusInput {
    var processingState: String?
    var expired: Bool
}

/// Status-bucket counts for the builds header strip. Expired wins over
/// processingState, mirroring `BuildDisplayHelper.buildStatus` above.
struct BuildStats: Equatable {
    var valid = 0
    var processing = 0
    var failed = 0
    var expired = 0

    var total: Int { valid + processing + failed + expired }

    static func compute(_ inputs: [BuildStatusInput]) -> BuildStats {
        var stats = BuildStats()
        for input in inputs {
            if input.expired {
                stats.expired += 1
            } else {
                switch input.processingState {
                case "PROCESSING":
                    stats.processing += 1
                case "FAILED", "INVALID":
                    stats.failed += 1
                default:
                    // VALID, unknown, or missing states all read as shippable.
                    stats.valid += 1
                }
            }
        }
        return stats
    }
}

/// Entrance-animation timing for the builds list.
enum BuildListAnimation {
    /// Stagger delay for a row index. Capped so long lists don't cascade.
    static func staggerDelay(forRow index: Int, step: Double = 0.05, max maxDelay: Double = 0.5) -> Double {
        min(Double(max(index, 0)) * step, maxDelay)
    }
}

/// Canned release-note starting points — copied to clipboard
/// from a single menu so they can be pasted into any build's
/// release notes.
enum ReleaseNoteSnippets {
    static let all = [
        "Bug fixes and performance improvements",
        "New features:\n- Feature 1\n- Feature 2\n- Feature 3",
        "Bug fixes:\n- Fixed issue with login\n- Fixed crash on startup\n- Improved stability",
        "What's new in this version:\n- Enhanced UI\n- Better performance\n- Security updates",
        "Release notes:\n- Added dark mode support\n- Fixed memory leaks\n- Updated dependencies"
    ]

    /// One-line menu label; ellipsis only when actually truncated.
    static func menuLabel(_ snippet: String) -> String {
        let flattened = snippet.replacingOccurrences(of: "\n", with: " ")
        guard flattened.count > 40 else { return flattened }
        return String(flattened.prefix(40)) + "…"
    }
}

extension BuildsModel {
    var displayStatus: (String, Color) {
        BuildDisplayHelper.buildStatus(
            processingState: processingState ?? "",
            isExpired: expired ?? false
        )
    }

    var formattedUploadedDate: String {
        BuildDisplayHelper.formattedUploadedDate(uploadedDate)
    }

    var relativeUploadedTime: String? {
        BuildDisplayHelper.relativeUploadedTime(uploadedDate)
    }
}

/// One locale's added/removed lines vs its last-saved notes.
/// Produced by the view model across every dirty locale so bulk
/// Review changes never hides a second edited locale behind the
/// selected tab.
struct LocaleDiff: Equatable {
    let locale: String
    let added: [String]
    let removed: [String]
}
