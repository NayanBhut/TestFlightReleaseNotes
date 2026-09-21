//
//  BuildProcessingMonitor.swift
//  App Store
//
//  Batch H (#8): menu bar + notifications. A lightweight poller watches
//  builds in PROCESSING state (GET /v1/builds?filter[processingState]=
//  PROCESSING — verified against Apple's List Builds docs, which list
//  filter[processingState] with values PROCESSING, FAILED, INVALID, VALID)
//  and posts a local notification on the PROCESSING → VALID transition
//  (FAILED / INVALID end the wait too, so they notify as well).
//

import AppKit
import Combine
import Foundation
import JSONAPI
import OSLog
import SwiftUI
import UserNotifications

private let buildMonitorLogger = Logger(subsystem: "com.appstore.release-notes", category: "BuildMonitor")

/// Minimal info the menu bar needs per processing build.
struct ProcessingBuildInfo: Identifiable, Equatable {
    let id: String
    /// Build number (BuildsModel.version, e.g. "42").
    let buildNumber: String
    /// Marketing version from the included pre-release version (e.g. "1.2").
    let marketingVersion: String?
    let uploadedDate: String?

    var displayName: String {
        if let marketingVersion, !marketingVersion.isEmpty {
            return "\(marketingVersion) (\(buildNumber))"
        }
        return buildNumber
    }
}

/// Posts local notifications. A protocol so the monitor's transition logic
/// stays testable without touching UNUserNotificationCenter.
protocol BuildNotificationPosting: AnyObject {
    func requestAuthorizationIfNeeded()
    func postTransitionNotification(build: BuildsModel)
}

final class SystemBuildNotifier: BuildNotificationPosting {
    func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error {
                    buildMonitorLogger.error("Notification authorization failed: \(error.localizedDescription)")
                } else {
                    buildMonitorLogger.debug("Notification authorization granted: \(granted)")
                }
            }
        }
    }

    func postTransitionNotification(build: BuildsModel) {
        guard let (title, body) = Self.content(for: build) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Identifier includes the terminal state so a VALID notice never
        // coalesces with an earlier one for the same build.
        let request = UNNotificationRequest(
            identifier: "build-\(build.id)-\(build.processingState ?? "unknown")",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                buildMonitorLogger.error("Failed to deliver build notification: \(error.localizedDescription)")
            }
        }
    }

    /// nil for non-terminal states — no notification.
    static func content(for build: BuildsModel) -> (title: String, body: String)? {
        let name = displayName(for: build)
        switch build.processingState {
        case "VALID":
            return ("Build ready for testing", "\(name) finished processing and is ready.")
        case "FAILED":
            return ("Build processing failed", "\(name) failed processing. Select the build to view errors.")
        case "INVALID":
            return ("Build invalid", "\(name) is invalid. Upload a new build.")
        default:
            return nil
        }
    }

    static func displayName(for build: BuildsModel) -> String {
        let number = build.version ?? ""
        if let marketing = build.preReleaseVersion?.version, !marketing.isEmpty {
            return "\(marketing) (\(number))"
        }
        return number.isEmpty ? "Build" : "Build \(number)"
    }
}

@MainActor
final class BuildProcessingMonitor: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var processingBuilds: [ProcessingBuildInfo] = []
    @Published private(set) var isPolling = false
    @Published private(set) var lastPollDate: Date?
    @Published private(set) var lastError: String?

    var processingCount: Int { processingBuilds.count }

    private let pollInterval: TimeInterval
    private let pollLimit: Int
    private var pollTask: Task<Void, Never>?
    /// Build ids seen PROCESSING on the previous poll. A disappearance means
    /// the build left PROCESSING — the follow-up fetch learns the terminal state.
    private var knownProcessingIds: Set<String> = []
    private var notifiedBuildIds: Set<String> = []
    /// Consecutive failed follow-ups per disappeared id. A deleted build 404s
    /// forever, so misses are capped instead of retried indefinitely.
    private var followUpMisses: [String: Int] = [:]
    private static let maxFollowUpMisses = 5
    private var lastTeamKey: String?
    private let notifier: BuildNotificationPosting

    init(pollInterval: TimeInterval = AppConfigs.buildStatusPollInterval,
         pollLimit: Int = AppConfigs.buildStatusPollLimit,
         notifier: BuildNotificationPosting = SystemBuildNotifier()) {
        self.pollInterval = pollInterval
        self.pollLimit = pollLimit
        self.notifier = notifier
        super.init()
    }

    /// Idempotent: the App scene calls this from both the main window and
    /// the menu bar label — whichever appears first starts the loop.
    func start() {
        notifier.requestAuthorizationIfNeeded()
        // Banner even when frontmost (e.g. watching the builds list while an
        // upload processes). The monitor lives for the app's lifetime, so the
        // weak delegate reference stays valid.
        UNUserNotificationCenter.current().delegate = self
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.refresh()
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.pollInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func pollNow() async {
        await refresh()
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    // MARK: - Polling

    private func refresh() async {
        guard let team = CredentialStorage.shared.selectedTeam else {
            // Logged out: clear so the menu never shows another team's builds.
            processingBuilds = []
            knownProcessingIds = []
            notifiedBuildIds = []
            followUpMisses = [:]
            lastTeamKey = nil
            return
        }
        if lastTeamKey != team.key {
            // Team switch: old ids belong to the previous team — a
            // disappearance must not read as a transition.
            lastTeamKey = team.key
            knownProcessingIds = []
            notifiedBuildIds = []
            followUpMisses = [:]
        }
        guard !Task.isCancelled else { return }
        isPolling = true
        defer { isPolling = false }
        do {
            let builds = try await fetchProcessingBuilds()
            guard !Task.isCancelled else { return }
            let currentIds = Set(builds.map(\.id))
            let disappeared = knownProcessingIds.subtracting(currentIds)
            processingBuilds = builds.map {
                ProcessingBuildInfo(
                    id: $0.id,
                    buildNumber: $0.version ?? "",
                    marketingVersion: $0.preReleaseVersion?.version,
                    uploadedDate: $0.uploadedDate
                )
            }
            lastPollDate = Date()
            lastError = nil
            // Follow-ups resolve before committing: ids whose follow-up fails
            // (or that aren't terminal yet) stay known so the next poll
            // retries instead of dropping the transition on the floor.
            var stillKnown = currentIds
            for id in disappeared where !notifiedBuildIds.contains(id) {
                if let terminal = try? await fetchBuild(id: id),
                   SystemBuildNotifier.content(for: terminal) != nil {
                    notifier.postTransitionNotification(build: terminal)
                    notifiedBuildIds.insert(id)
                    followUpMisses.removeValue(forKey: id)
                } else {
                    let misses = (followUpMisses[id] ?? 0) + 1
                    if misses < Self.maxFollowUpMisses {
                        followUpMisses[id] = misses
                        stillKnown.insert(id)
                    } else {
                        // Gave up (deleted build, persistent 404): stop
                        // polling it rather than requesting it forever.
                        followUpMisses.removeValue(forKey: id)
                        buildMonitorLogger.debug("Dropping follow-up for vanished build \(id)")
                    }
                }
            }
            knownProcessingIds = stillKnown
        } catch {
            guard !Task.isCancelled else { return }
            buildMonitorLogger.error("Build status poll failed: \(error.localizedDescription)")
            lastError = (error as? APIError)?.details ?? error.localizedDescription
        }
    }

    func fetchProcessingBuilds() async throws -> [BuildsModel] {
        let queryParams = [
            "filter[processingState]": "PROCESSING",
            "sort": "-uploadedDate",
            "limit": String(pollLimit),
            "include": "preReleaseVersion",
            "fields[builds]": "processingState,version,uploadedDate,expired,preReleaseVersion"
        ]
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getVersionBuilds, queryParams: queryParams),
            apiVersion: .v1
        ) else {
            throw APIError.apiError(error: "No team selected.")
        }
        let data = try await APIClient.shared.callAPI(with: request)
        return try getDecoder().decode(BuildsDocument.self, from: data).data
    }

    func fetchBuild(id: String) async throws -> BuildsModel {
        let queryParams = [
            "include": "preReleaseVersion",
            "fields[builds]": "processingState,version,uploadedDate,expired,preReleaseVersion"
        ]
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getVersionBuilds, queryParams: queryParams, path: id),
            apiVersion: .v1
        ) else {
            throw APIError.apiError(error: "No team selected.")
        }
        let data = try await APIClient.shared.callAPI(with: request)
        return try getDecoder().decode(BuildsModel.self, from: data)
    }
}

// MARK: - Menu bar UI

/// Content of the MenuBarExtra scene: processing count, per-build rows,
/// last-checked state, manual refresh, and Quit (menu extras get no
/// automatic Quit item).
struct MenuBarBuildsView: View {
    @ObservedObject var monitor: BuildProcessingMonitor

    var body: some View {
        if monitor.processingBuilds.isEmpty {
            Text("No builds processing")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            ForEach(monitor.processingBuilds) { build in
                Text(menuLine(for: build))
            }
        }
        Divider()
        if let lastPoll = monitor.lastPollDate {
            Text("Last checked \(lastPoll, style: .time)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let error = monitor.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
        Button("Check now") {
            Task { await monitor.pollNow() }
        }
        .disabled(monitor.isPolling)
        Divider()
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func menuLine(for build: ProcessingBuildInfo) -> String {
        var line = build.displayName
        if let uploaded = build.uploadedDate,
           let relative = BuildDisplayHelper.relativeUploadedTime(uploaded) {
            line += " — uploaded \(relative)"
        }
        return line
    }
}
