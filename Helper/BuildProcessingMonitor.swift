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
//  The monitor is an app-lifetime @StateObject created in App_StoreApp and
//  never released — the poll loop intentionally retains it strongly.
//

import AppKit
import Combine
import Foundation
import JSONAPI
import OSLog
import SwiftUI
@preconcurrency import UserNotifications

private let buildMonitorLogger = Logger(subsystem: "com.appstore.release-notes", category: "BuildMonitor")

/// "1.2 (42)" / "AppName 1.2 (42)" — one implementation shared by the menu
/// rows and notification copies so the fallback ("Build") can never drift.
enum BuildDisplayName {
    static func make(appName: String?, marketingVersion: String?, buildNumber: String?) -> String {
        let versionPart: String
        if let marketing = marketingVersion, !marketing.isEmpty {
            let number = buildNumber ?? ""
            versionPart = number.isEmpty ? marketing : "\(marketing) (\(number))"
        } else {
            let number = buildNumber ?? ""
            versionPart = number.isEmpty ? "" : "Build \(number)"
        }
        guard !versionPart.isEmpty else { return appName ?? "Build" }
        guard let appName, !appName.isEmpty else { return versionPart }
        return "\(appName) \(versionPart)"
    }
}

/// Minimal info the menu bar needs per processing build.
struct ProcessingBuildInfo: Identifiable, Equatable {
    let id: String
    /// Owning app's name — multi-app accounts need to tell builds apart.
    let appName: String
    /// Build number (BuildsModel.version, e.g. "42").
    let buildNumber: String
    /// Marketing version from the included pre-release version (e.g. "1.2").
    let marketingVersion: String?
    let uploadedDate: String?

    var displayName: String {
        BuildDisplayName.make(
            appName: appName.isEmpty ? nil : appName,
            marketingVersion: marketingVersion,
            buildNumber: buildNumber
        )
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
    ///
    /// VALID copy must never imply TestFlight readiness or App Store /
    /// production eligibility (M12-H): beta readiness comes from
    /// BuildBetaDetail, which is checked separately.
    static func content(for build: BuildsModel) -> (title: String, body: String)? {
        let name = displayName(for: build)
        switch build.processingState {
        case "VALID":
            return ("Build processing completed", "\(name) processing is VALID. Check TestFlight readiness, production audience and compliance separately before distribution.")
        case "FAILED":
            // "Check App Store Connect", not "select the build": clicking the
            // notification doesn't navigate anywhere (no didReceive deep-link),
            // so the copy must not imply in-app interactivity.
            return ("Build processing failed", "\(name) failed processing. Check App Store Connect for errors.")
        case "INVALID":
            return ("Build invalid", "\(name) is invalid. Upload a new build.")
        default:
            return nil
        }
    }

    static func displayName(for build: BuildsModel) -> String {
        BuildDisplayName.make(
            appName: build.app?.name,
            marketingVersion: build.preReleaseVersion?.version,
            buildNumber: build.version
        )
    }
}

@MainActor
final class BuildProcessingMonitor: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var processingBuilds: [ProcessingBuildInfo] = []
    @Published private(set) var isPolling = false
    @Published private(set) var lastPollDate: Date?
    @Published private(set) var lastError: String?
    /// HTTP status of the last failed poll, when the failure carried one
    /// (used for the M12-L rate-limit branch; 429 enters scoped backoff).
    @Published private(set) var lastStatusCode: Int?
    /// True when the last failure was a connectivity loss (offline branch
    /// M12-O), as opposed to an HTTP/application error.
    @Published private(set) var lastErrorWasConnectivity = false
    /// Wall-clock time of the last poll attempt (success or failure).
    /// Drives the backoff "Retry locked until" date.
    @Published private(set) var lastAttemptDate: Date?

    /// Scoped connection state for the monitoring branches (M12-O/M12-L).
    /// A plain error (401/403/…) is neither offline nor rate-limited.
    enum ConnectionState: Equatable {
        case online
        case offline
        case rateLimited
    }

    var connectionState: ConnectionState {
        if lastStatusCode == 429 { return .rateLimited }
        if lastError != nil, lastErrorWasConnectivity { return .offline }
        return .online
    }

    /// Earliest date at which a retry is policy-eligible after a failed
    /// poll. Nil when no backoff applies.
    var backoffAvailableDate: Date? {
        guard lastError != nil, let attempt = lastAttemptDate else { return nil }
        return attempt.addingTimeInterval(errorPollInterval)
    }

    /// True while the local backoff policy forbids another request.
    var isRetryLocked: Bool {
        guard let available = backoffAvailableDate else { return false }
        return available > Date()
    }

    var processingCount: Int { processingBuilds.count }

    private let pollInterval: TimeInterval
    private let pollLimit: Int
    /// Backoff after a failed poll: an erroring key (expired/revoked) would
    /// otherwise hammer the API with 401s at full cadence.
    private let errorPollInterval: TimeInterval
    private var pollTask: Task<Void, Never>?
    /// Build ids seen PROCESSING on the previous poll. A disappearance means
    /// the build left PROCESSING — the follow-up fetch learns the terminal state.
    private var knownProcessingIds: Set<String> = []
    /// One-shot per build id: build ids are unique per upload and a terminal
    /// build never re-enters PROCESSING, so eviction only risks a re-notify
    /// for an ancient build re-uploaded under the same id — not possible.
    /// Ordered (oldest-first) so the cap evicts the stalest ids instead of
    /// dropping the whole window at once. Linear contains is fine at this
    /// scale (a few hundred ids, checked once per poll).
    private var notifiedBuildIds: [String] = []
    private static let notifiedBuildIdsCap = 500
    /// Consecutive failed follow-ups per disappeared id. A deleted build 404s
    /// forever, so misses are capped instead of retried indefinitely.
    private var followUpMisses: [String: Int] = [:]
    private static let maxFollowUpMisses = 5
    private var lastTeamKey: String?
    private let notifier: BuildNotificationPosting
    private var teamsCancellable: AnyCancellable?
    /// App-owned polling + notification preferences (Module 12). The loop
    /// interval, the enabled gate and per-outcome notification toggles all
    /// read from here.
    private let prefs = MonitoringPreferences.shared

    init(pollInterval: TimeInterval = AppConfigs.buildStatusPollInterval,
         pollLimit: Int = AppConfigs.buildStatusPollLimit,
         notifier: BuildNotificationPosting = SystemBuildNotifier()) {
        self.pollInterval = pollInterval
        self.pollLimit = pollLimit
        self.errorPollInterval = AppConfigs.buildStatusPollErrorInterval
        self.notifier = notifier
        super.init()
        // Login must not wait up to a whole poll interval to show data.
        // (Logout is handled inside refresh() itself.)
        teamsCancellable = CredentialStorage.shared.$teams
            .receive(on: DispatchQueue.main)
            .sink { [weak self] teams in
                guard let self, !teams.isEmpty else { return }
                Task { await self.pollNow() }
            }
    }

    /// Idempotent: the App scene calls this from both the main window and
    /// the menu bar label — whichever appears first starts the loop. The
    /// monitor lives for the app's lifetime (@StateObject), so the loop
    /// captures self strongly on purpose.
    func start() {
        notifier.requestAuthorizationIfNeeded()
        // Banner even when frontmost (e.g. watching the builds list while an
        // upload processes). The monitor lives for the app's lifetime, so the
        // weak delegate reference stays valid.
        UNUserNotificationCenter.current().delegate = self
        guard pollTask == nil else { return }
        pollTask = Task { [self] in
            while !Task.isCancelled {
                // App-owned policy (M12-H): polling runs only while enabled.
                // Disabled polling skips the refresh but keeps the loop so
                // re-enabling resumes without a restart.
                if prefs.pollingEnabled {
                    await refresh()
                }
                // Sleep AFTER the refresh: fresh login / upload fires the
                // pollNow path, while a failed poll backs off instead of
                // hammering at full cadence.
                let interval = lastError == nil ? prefs.activeBuildCadence : errorPollInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
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

    /// Serialized by isPolling: a manual "Check now" landing while the timer
    /// poll is in flight must not double-fire follow-ups and notifications.
    private func refresh() async {
        guard !isPolling else { return }

        guard let team = CredentialStorage.shared.selectedTeam else {
            // Logged out: clear so the menu never shows another team's
            // builds — including any stale error/last-checked from the
            // previous session.
            processingBuilds = []
            knownProcessingIds = []
            notifiedBuildIds = []
            followUpMisses = [:]
            lastTeamKey = nil
            lastError = nil
            lastStatusCode = nil
            lastErrorWasConnectivity = false
            lastPollDate = nil
            lastAttemptDate = nil
            return
        }

        if lastTeamKey != team.key {
            // Team switch: old ids belong to the previous team — a
            // disappearance must not read as a transition.
            lastTeamKey = team.key
            knownProcessingIds = []
            notifiedBuildIds = []
            followUpMisses = [:]
            lastError = nil
            lastStatusCode = nil
            lastErrorWasConnectivity = false
        }

        guard !Task.isCancelled else { return }
        isPolling = true
        defer { isPolling = false }
        lastAttemptDate = Date()
        do {
            let builds = try await fetchProcessingBuilds()
            guard !Task.isCancelled else { return }
            let currentIds = Set(builds.map(\.id))
            let disappeared = knownProcessingIds.subtracting(currentIds)
            processingBuilds = builds.map {
                ProcessingBuildInfo(
                    id: $0.id,
                    appName: $0.app?.name ?? "",
                    buildNumber: $0.version ?? "",
                    marketingVersion: $0.preReleaseVersion?.version,
                    uploadedDate: $0.uploadedDate
                )
            }
            lastPollDate = Date()
            lastError = nil
            lastStatusCode = nil
            lastErrorWasConnectivity = false
            // Follow-ups resolve before committing: ids whose follow-up fails
            // (or that aren't terminal yet) stay known so the next poll
            // retries instead of dropping the transition on the floor.
            var stillKnown = currentIds
            for id in disappeared where !notifiedBuildIds.contains(id) {
                guard !Task.isCancelled else { return }
                do {
                    let terminal = try await fetchBuild(id: id)
                    if SystemBuildNotifier.content(for: terminal) == nil {
                        // Not terminal yet (rare: build briefly vanished) —
                        // keep tracking so the next poll retries.
                        followUpMisses[id] = (followUpMisses[id] ?? 0) + 1
                        stillKnown.insert(id)
                        continue
                    }
                    // Per-outcome desktop toggle (Monitoring preferences):
                    // in-app alert-center rows are unaffected.
                    if prefs.allowsNotification(for: terminal.processingState) {
                        notifier.postTransitionNotification(build: terminal)
                    }
                    if !notifiedBuildIds.contains(id) {
                        notifiedBuildIds.append(id)
                    }
                    if notifiedBuildIds.count > Self.notifiedBuildIdsCap {
                        // Evict oldest-first: bursty accounts keep recent
                        // history instead of losing the whole dedup window.
                        notifiedBuildIds.removeFirst(notifiedBuildIds.count - Self.notifiedBuildIdsCap)
                    }
                    followUpMisses.removeValue(forKey: id)
                } catch {
                    // Logged instead of try?-swallowed: a decoding or network
                    // bug here would otherwise look exactly like a deleted build.
                    guard !Task.isCancelled else { return }
                    buildMonitorLogger.debug("Follow-up fetch failed for build \(id): \(error.localizedDescription)")
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
            lastStatusCode = (error as? APIError)?.statusCode
            lastErrorWasConnectivity = Self.isConnectivityError(error)
        }
    }

    /// Offline (M12-O) means the request never reached Apple: DNS / host /
    /// connection-loss URLErrors, including their NSError bridges. HTTP
    /// failures (401/403/429/5xx) and timeouts are not offline — they keep
    /// their own branches and guards.
    private static func isConnectivityError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return isConnectivityCode(urlError.code)
        }
        let nsError = error as NSError
        if nsError.domain == (NSURLErrorDomain as String) {
            return isConnectivityCode(URLError.Code(rawValue: nsError.code))
        }
        return false
    }

    private static func isConnectivityCode(_ code: URLError.Code) -> Bool {
        switch code {
        case .notConnectedToInternet, .networkConnectionLost,
             .dnsLookupFailed, .cannotFindHost, .cannotConnectToHost,
             .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    /// Relationship names must be listed in fields[builds]: sparse fieldsets
    /// filter relationships too, so omitting "preReleaseVersion,app" would
    /// drop their linkage and the include= hydration would yield nil.
    private static let buildFields = "processingState,version,uploadedDate,expired,preReleaseVersion,app"

    func fetchProcessingBuilds() async throws -> [BuildsModel] {
        let queryParams = [
            "filter[processingState]": "PROCESSING",
            "sort": "-uploadedDate",
            "limit": String(pollLimit),
            "include": "preReleaseVersion,app",
            "fields[builds]": Self.buildFields,
            // Just the name — a full app payload per build per poll
            // duplicates for nothing.
            "fields[apps]": "name"
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
            "include": "preReleaseVersion,app",
            "fields[builds]": Self.buildFields,
            "fields[apps]": "name"
        ]
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getVersionBuilds, queryParams: queryParams, path: id),
            apiVersion: .v1
        ) else {
            throw APIError.apiError(error: "No team selected.")
        }
        let data = try await APIClient.shared.callAPI(with: request)
        // JSONAPIDecoder.decode<R> wraps the response in a CompoundDocument
        // internally (JSONAPIDecoder.swift:81) — single-resource documents
        // decode exactly like the list path. Same pattern as expireBuild.
        return try getDecoder().decode(BuildsModel.self, from: data)
    }
}

// MARK: - Menu bar UI

/// Content of the MenuBarExtra scene (Figma 3-4502 menu-bar-monitor):
/// fetched-snapshot badge, per-build rows with relative upload age, local
/// check time, manual refresh and Quit (menu extras get no automatic Quit
/// item). Dark mode comes from system colors.
struct MenuBarBuildsView: View {
    @ObservedObject var monitor: BuildProcessingMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack {
            Text("PROCESSING BUILDS")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
            Spacer()
            // "Fetched snapshots": only claimed when a poll actually
            // succeeded — a stale cache never presents as fresh data.
            if monitor.lastPollDate != nil {
                Text("Fetched snapshots")
                    .font(.system(size: 10))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(6)
            }
        }
        Divider()
        if monitor.processingBuilds.isEmpty {
            Text("No builds processing")
                .font(.appBody)
                .foregroundStyle(.secondary)
        } else {
            ForEach(monitor.processingBuilds) { build in
                VStack(alignment: .leading, spacing: 2) {
                    Text(menuTitle(for: build))
                    Text(menuSubtitle(for: build))
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        Divider()
        HStack {
            Button("Check Now") {
                Task { await monitor.pollNow() }
            }
            .disabled(monitor.isPolling)
            if let lastPoll = monitor.lastPollDate {
                Text("Local check: \(lastPoll, style: .time)")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Shipyard") {
                // MenuBarExtras can be clicked with only the menu extra
                // visible — bring up the main window so the notification
                // context has a home.
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
        }
        if let error = monitor.lastError {
            Text(error)
                .font(.appCaption)
                .foregroundStyle(.red)
        }
        Divider()
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func menuTitle(for build: ProcessingBuildInfo) -> String {
        let app = build.appName.isEmpty ? "Unknown App" : build.appName
        let version = build.marketingVersion.map { "\($0) " } ?? ""
        return "\(app) — \(version)(\(build.buildNumber))"
    }

    private func menuSubtitle(for build: ProcessingBuildInfo) -> String {
        if let uploaded = build.uploadedDate,
           let relative = BuildDisplayHelper.relativeUploadedTime(uploaded) {
            return "Processing… Uploaded \(relative)"
        }
        return "Processing…"
    }

    private func menuLine(for build: ProcessingBuildInfo) -> String {
        "\(menuTitle(for: build)) — \(menuSubtitle(for: build))"
    }
}
