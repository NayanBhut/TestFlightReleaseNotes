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

    /// Directory for exported files; stale files are purged on each export.
    private static let exportsDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("BuildExports", isDirectory: true)
    /// Exports older than this are purged so the temp directory can't grow unbounded.
    private static let staleExportInterval: TimeInterval = 24 * 60 * 60

    init() {
        purgeStaleExports()
    }

    func exportBuilds(builds: [BuildsModel], version: PreReleaseVersionsModel, appName: String, format: ExportFormat) -> URL? {
        let content = generateContent(builds: builds, version: version, appName: appName, format: format)

        guard let data = content.data(using: .utf8) else {
            exportError = "Failed to encode content"
            return nil
        }

        let fileName = "\(sanitizedFileNameComponent(appName))_\(sanitizedFileNameComponent(version.version ?? "unknown")).\(format.fileExtension)"

        do {
            try FileManager.default.createDirectory(at: Self.exportsDirectory, withIntermediateDirectories: true)
            purgeStaleExports()
            let fileURL = Self.exportsDirectory.appendingPathComponent(fileName)
            try data.write(to: fileURL)
            return fileURL
        } catch {
            exportError = error.localizedDescription
            return nil
        }
    }

    /// Replaces characters that are invalid or unsafe in file names.
    private func sanitizedFileNameComponent(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
            .union(.illegalCharacters)
        return value
            .replacingOccurrences(of: " ", with: "_")
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
    }

    /// Removes exported files left over from previous sessions.
    private func purgeStaleExports() {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: Self.exportsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-Self.staleExportInterval)
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
        var lines = ["| Build | Date | Notes |", "|-------|------|-------|", ""]

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
    /// (values starting with `=`, `+`, `-`, or `@` are prefixed with `'`).
    private func escapeCSVCell(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if let first = escaped.first, ["=", "+", "-", "@"].contains(first) {
            return "'\(escaped)"
        }
        return "\"\(escaped)\""
    }

    func shareFile(url: URL) {
        let activity = NSSharingServicePicker(items: [url])
        // Fall back to any open window if the key window isn't set
        // (e.g. right after app activation).
        let window = NSApplication.shared.keyWindow ?? NSApp.windows.first
        guard let view = window?.contentView else { return }
        activity.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func openInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
