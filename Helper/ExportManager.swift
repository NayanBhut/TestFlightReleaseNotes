//
//  ExportManager.swift
//  App Store
//
//  Created by Nayan Bhut on 18/09/25.
//

import Foundation
import AppKit

enum ExportFormat {
    case markdown
    case csv

    var fileExtension: String {
        self == .markdown ? "md" : "csv"
    }
}

@MainActor
final class ExportManager: ObservableObject {
    @Published var exportError: String?

    /// Directory for exported files; stale files are purged in the background.
    private static let exportsDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("BuildExports", isDirectory: true)
    /// Exports older than this are purged so the temp directory can't grow unbounded.
    private static let staleExportInterval: TimeInterval = 24 * 60 * 60
    /// Longest sanitized file-name component, in UTF-8 **bytes**, so app name
    /// + version can't exceed the 255-byte filename limit alongside the
    /// extension even with 4-byte characters (emoji, CJK).
    private static let maxFileNameComponentBytes = 100

    init() {
        purgeStaleExportsInBackground()
    }

    func exportBuilds(builds: [BuildsModel], version: PreReleaseVersionsModel, appName: String, format: ExportFormat) -> URL? {
        exportError = nil

        let content = generateContent(builds: builds, version: version, appName: appName, format: format)
        let data = Data(content.utf8)

        let fileName = "\(sanitizedFileNameComponent(appName))_\(sanitizedFileNameComponent(version.version ?? "unknown")).\(format.fileExtension)"

        do {
            try FileManager.default.createDirectory(at: Self.exportsDirectory, withIntermediateDirectories: true)
            let fileURL = Self.exportsDirectory.appendingPathComponent(fileName)
            try data.write(to: fileURL, options: .atomic)
            purgeStaleExportsInBackground()
            return fileURL
        } catch {
            exportError = error.localizedDescription
            return nil
        }
    }

    /// Replaces characters that are invalid or unsafe in file names and caps
    /// the length (UTF-8 bytes) so long app names + versions can't exceed the
    /// 255-byte filename limit.
    private func sanitizedFileNameComponent(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
            .union(.illegalCharacters)
        let sanitized = value
            .replacingOccurrences(of: " ", with: "_")
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")

        // Truncate on a safe UTF-8 scalar boundary once the byte budget is spent.
        var result = String.UnicodeScalarView()
        var bytes = 0
        for scalar in sanitized.unicodeScalars {
            let width = UTF8.width(scalar)
            if bytes + width > Self.maxFileNameComponentBytes { break }
            bytes += width
            result.append(scalar)
        }
        return String(result)
    }

    /// Removes exported files left over from previous sessions, off the main thread.
    private func purgeStaleExportsInBackground() {
        Task.detached(priority: .utility) {
            Self.purgeStaleExports()
        }
    }

    private nonisolated static func purgeStaleExports() {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: exportsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-staleExportInterval)
        for fileURL in files {
            if let modifiedDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               modifiedDate < cutoff {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    private func generateContent(builds: [BuildsModel], version: PreReleaseVersionsModel, appName: String, format: ExportFormat) -> String {
        let header = format == .markdown ? "# \(appName) - \(version.version ?? "Unknown")\n\n" : ""

        switch format {
        case .markdown:
            return header + generateMarkdown(builds: builds)
        case .csv:
            return generateCSV(builds: builds)
        }
    }

    private func generateMarkdown(builds: [BuildsModel]) -> String {
        // No blank line between the separator and the first data row —
        // GFM (and most renderers) require contiguous table rows.
        var lines = ["| Build | Date | Notes |", "|-------|------|-------|"]

        for build in builds {
            let buildVersion = escapeMarkdownCell(build.version ?? "")
            let date = escapeMarkdownCell(build.uploadedDate ?? "")
            let notes = escapeMarkdownCell(build.betaBuildLocalizations.first?.whatsNew ?? "")
            lines.append("| \(buildVersion) | \(date) | \(notes) |")
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Escapes pipe characters and line breaks so release notes can't break the table layout.
    private func escapeMarkdownCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r\n", with: "<br>")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    private func generateCSV(builds: [BuildsModel]) -> String {
        var lines: [String] = []
        lines.append("\"Build\",\"Date\",\"Notes\"")

        for build in builds {
            let buildVersion = escapeCSVCell(build.version ?? "")
            let date = escapeCSVCell(build.uploadedDate ?? "")
            let notes = escapeCSVCell(build.betaBuildLocalizations.first?.whatsNew ?? "")
            lines.append("\(buildVersion),\(date),\(notes)")
        }

        return lines.joined(separator: "\n")
    }

    /// Quote-escapes a cell and neutralizes spreadsheet formula injection
    /// (per OWASP, a value whose first *non-whitespace* character is `=`, `+`,
    /// `-`, or `@` is prefixed with `'`). The prefix is added inside the
    /// quotes so the cell stays a single well-formed CSV field.
    private func escapeCSVCell(_ value: String) -> String {
        var escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        let firstNonWhitespace = escaped.drop(while: { $0 == " " || $0 == "\t" || $0 == "\r" || $0 == "\n" }).first
        if let first = firstNonWhitespace, ["=", "+", "-", "@"].contains(first) {
            escaped = "'" + escaped
        }
        return "\"\(escaped)\""
    }

    func shareFile(url: URL, from sourceView: NSView? = nil) {
        let activity = NSSharingServicePicker(items: [url])
        // Anchor to the triggering control when provided; otherwise fall back
        // to the key window, or any open window right after activation.
        if let sourceView {
            activity.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .minY)
            return
        }
        let window = NSApplication.shared.keyWindow ?? NSApp.windows.first
        guard let view = window?.contentView else { return }
        activity.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func openInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
