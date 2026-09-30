//
//  BuildDisplayHelper.swift
//  App Store
//
//  Shared upload-date formatting and build status labels for build rows,
//  App Info version cards, and the menu-bar monitor.
//

import SwiftUI

enum BuildDisplayHelper {
    // nonisolated(unsafe): formatters are not Sendable, but every caller
    // is a SwiftUI view body or @MainActor monitor — never concurrent.
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
