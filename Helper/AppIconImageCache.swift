//
//  AppIconImageCache.swift
//  App Store
//
//  Created by Nayan Bhut on 20/09/26.
//

import SwiftUI
import CryptoKit
import OSLog

private let iconLogger = Logger(subsystem: "com.appstore.release-notes", category: "Icons")

/// Memory + disk cache for App Store Connect icon artwork.
///
/// Actor-isolated so Swift 6 treats all bookkeeping as race-free.
/// Disk + network I/O stays in nonisolated helpers / detached tasks so
/// a slow download never blocks other cache lookups.
actor AppIconImageCache {
    static let shared = AppIconImageCache()

    /// Icons change only when the app's artwork changes (new upload);
    /// a week comfortably covers that while keeping launches offline-fast.
    private static let diskTTL: TimeInterval = 7 * 24 * 60 * 60
    /// A failing URL (404, decode failure, offline) is skipped for this long
    /// so a permanently-broken icon doesn't re-hit the network on every
    /// row appearance — negative caching.
    private static let failureTTL: TimeInterval = 10 * 60

    private let memory = NSCache<NSURL, NSImage>()
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]
    private var lastFailure: [URL: Date] = [:]
    private let diskDirectory: URL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("AppIcons", isDirectory: true)
        ?? FileManager.default.temporaryDirectory.appendingPathComponent("AppIcons", isDirectory: true)

    func image(for url: URL) async -> NSImage? {
        if let cached = memory.object(forKey: url as NSURL) {
            return cached
        }
        // Negative cache: skip refetching a recently-failing URL.
        if let failedAt = lastFailure[url],
           Date().timeIntervalSince(failedAt) < Self.failureTTL {
            return nil
        }
        // Coalesce concurrent requests for the same URL (e.g. the row
        // re-rendering mid-download) into a single network fetch.
        // Actor isolation makes the check-and-insert atomic without a lock,
        // and nothing here suspends while bookkeeping is half-done.
        if let existing = inFlight[url] {
            return await existing.value
        }
        let task = Task { await Self.load(url: url, diskDirectory: diskDirectory) }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            memory.setObject(image, forKey: url as NSURL)
            lastFailure[url] = nil
        } else {
            lastFailure[url] = Date()
        }
        return image
    }

    /// Nonisolated so disk + network I/O never blocks cache bookkeeping.
    private nonisolated static func load(url: URL, diskDirectory: URL) async -> NSImage? {
        let fileURL = diskDirectory.appendingPathComponent(Self.fileName(for: url))
        if let fresh = Self.freshDiskImage(at: fileURL) { return fresh }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = NSImage(data: data) else { return nil }
            try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
            // Written atomically; a half-downloaded file must never be served.
            try? data.write(to: fileURL, options: .atomic)
            return image
        } catch {
            iconLogger.error("Icon download failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Disk hit only when the file exists and is younger than the TTL.
    private nonisolated static func freshDiskImage(at fileURL: URL) -> NSImage? {
        guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
              let modified = values.contentModificationDate,
              Date().timeIntervalSince(modified) < diskTTL,
              let data = try? Data(contentsOf: fileURL),
              let image = NSImage(data: data) else { return nil }
        return image
    }

    /// SHA-256 hex: fixed-length, filesystem-safe, collision-proof keys
    /// regardless of query strings or template parameters in the URL.
    private nonisolated static func fileName(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".png"
    }
}

/// Drop-in replacement for the AsyncImage used in app rows, backed by
/// AppIconImageCache so icons survive scrolling and relaunches.
struct CachedAppIcon: View {
    let url: URL
    let size: CGFloat

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .cornerRadius(6)
            } else if failed {
                Image(systemName: "app.fill")
                    .font(.system(size: size - 4, weight: .medium))
                    .foregroundColor(.gray)
                    .frame(width: size, height: size)
            } else {
                ProgressView()
                    .frame(width: size, height: size)
            }
        }
        // Keyed by URL: Row reuse with a different URL cancels the stale
        // load instead of flashing the previous row's icon.
        .task(id: url) {
            image = nil
            failed = false
            if let loaded = await AppIconImageCache.shared.image(for: url) {
                image = loaded
            } else {
                failed = true
            }
        }
    }
}
