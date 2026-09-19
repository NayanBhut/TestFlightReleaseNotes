//
//  ExportManager.swift
//  App Store
//
//  Created by Nayan Bhut on 18/09/25.
//

import Foundation
import AppKit

final class ExportManager: ObservableObject {
    @Published var exportProgress: Double = 0
    @Published var isExporting: Bool = false
    @Published var exportError: String?
    
    enum ExportFormat {
        case markdown
        case csv
    }
    
    func exportBuilds(builds: [BuildsModel], version: PreReleaseVersionsModel, appName: String, format: ExportFormat) -> URL? {
        let content = generateContent(builds: builds, version: version, appName: appName, format: format)
        
        guard let data = content.data(using: .utf8) else {
            exportError = "Failed to encode content"
            return nil
        }
        
        let fileName = "\(appName.replacingOccurrences(of: " ", with: "_"))_\(version.version ?? "unknown")_\(format == .markdown ? "md" : "csv")"
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            exportError = error.localizedDescription
            return nil
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
            let buildVersion = build.version ?? ""
            let date = build.uploadedDate ?? ""
            let notes = build.betaBuildLocalizations.first?.whatsNew ?? ""
            lines.append("| \(buildVersion) | \(date) | \(notes) |")
        }
        
        lines.append("")
        return lines.joined(separator: "\n")
    }
    
    private func generateCSV(builds: [BuildsModel]) -> String {
        var lines: [String] = []
        lines.append("\"Build\",\"Date\",\"Notes\"")
        
        for build in builds {
            let buildVersion = build.version ?? ""
            let date = build.uploadedDate ?? ""
            let notes = build.betaBuildLocalizations.first?.whatsNew ?? ""
            let escapedNotes = notes.replacingOccurrences(of: "\"", with: "\"\"")
            lines.append("\"\(buildVersion)\",\"\(date)\",\"\(escapedNotes)\"")
        }
        
        return lines.joined(separator: "\n")
    }
    
    func shareFile(url: URL) {
        let activity = NSSharingServicePicker(items: [url])
        if let window = NSApplication.shared.keyWindow,
           let view = window.contentView {
            activity.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
    }
    
    func openInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
