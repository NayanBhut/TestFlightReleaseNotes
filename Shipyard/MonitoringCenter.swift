//
//  MonitoringCenter.swift
//  App Store
//
//  Module 12 (Monitoring & Shared Actions): app-owned desktop polling
//  preferences, the local observed alert center, the offline-paused (M12-O)
//  and rate-limit backoff (M12-L) states, and the macOS notification
//  permission preprompt.
//
//  API contract notes (M12-H implementation contract, Apple docs 4.5):
//  - Polling is a client policy (active builds 30s, general resources 5min),
//    not an SLA. It runs only while enabled, running, online and authorized,
//    and pauses/backs off on offline, 401, 403 or 429.
//  - processingState is PROCESSING / FAILED / INVALID / VALID. VALID means
//    processing finished — it is NOT TestFlight-ready nor eligible for
//    distribution; beta readiness comes from BuildBetaDetail separately.
//  - Observation time is the local successful poll time, never Apple event
//    history. Freshness is tracked per resource + scope.
//  - Native macOS notification permission is independent of ASC: denied
//    notifications never disable the in-app alert center.
//  - No webhooks, no server push, no user audit-log API and no
//    processing-stage stream exist on this client.
//

import AppKit
import Combine
import SwiftUI
@preconcurrency import UserNotifications

// MARK: - Monitoring preferences (Figma 3-6386, 114-10778)

/// App-owned desktop polling + notification preferences. Persisted in
/// UserDefaults (app-owned, per the contract) and read by
/// BuildProcessingMonitor before every poll and every notification.
@MainActor
final class MonitoringPreferences: ObservableObject {
    static let shared = MonitoringPreferences()

    /// Master switch — "Enable desktop polling". When off, the monitor's
    /// loop sleeps instead of polling.
    @Published var pollingEnabled: Bool {
        didSet { UserDefaults.standard.set(pollingEnabled, forKey: Self.pollingEnabledKey) }
    }
    /// Active-build cadence in seconds. Figma default: 30.
    @Published var activeBuildCadence: TimeInterval {
        didSet { UserDefaults.standard.set(activeBuildCadence, forKey: Self.activeCadenceKey) }
    }
    /// General team-resource cadence in seconds. Figma default: 300 (5 min).
    @Published var generalResourceCadence: TimeInterval {
        didSet { UserDefaults.standard.set(generalResourceCadence, forKey: Self.generalCadenceKey) }
    }
    /// Alert-center checkboxes (Figma 114-10778 "Monitor preferences").
    @Published var monitorBuildStatusChanges: Bool {
        didSet { UserDefaults.standard.set(monitorBuildStatusChanges, forKey: Self.monitorBuildsKey) }
    }
    @Published var monitorReviewAndExpiry: Bool {
        didSet { UserDefaults.standard.set(monitorReviewAndExpiry, forKey: Self.monitorReviewKey) }
    }
    /// Per-outcome desktop notification toggles (Figma 3-6386).
    /// VALID does not imply TestFlight readiness — see the notifier copy.
    @Published var notifyBuildValid: Bool {
        didSet { UserDefaults.standard.set(notifyBuildValid, forKey: Self.notifyValidKey) }
    }
    @Published var notifyBetaReadiness: Bool {
        didSet { UserDefaults.standard.set(notifyBetaReadiness, forKey: Self.notifyBetaKey) }
    }
    @Published var notifyVersionStatus: Bool {
        didSet { UserDefaults.standard.set(notifyVersionStatus, forKey: Self.notifyVersionKey) }
    }
    @Published var notifyBuildFailed: Bool {
        didSet { UserDefaults.standard.set(notifyBuildFailed, forKey: Self.notifyFailedKey) }
    }
    @Published var notifyExpiryReminders: Bool {
        didSet { UserDefaults.standard.set(notifyExpiryReminders, forKey: Self.notifyExpiryKey) }
    }

    static let pollingEnabledKey = "monitoring.pollingEnabled"
    static let activeCadenceKey = "monitoring.activeBuildCadence"
    static let generalCadenceKey = "monitoring.generalResourceCadence"
    static let monitorBuildsKey = "monitoring.monitorBuildStatus"
    static let monitorReviewKey = "monitoring.monitorReviewExpiry"
    static let notifyValidKey = "monitoring.notifyBuildValid"
    static let notifyBetaKey = "monitoring.notifyBetaReadiness"
    static let notifyVersionKey = "monitoring.notifyVersionStatus"
    static let notifyFailedKey = "monitoring.notifyBuildFailed"
    static let notifyExpiryKey = "monitoring.notifyExpiryReminders"

    /// Figma cadence options for the "Active build polling cadence" picker.
    static let activeCadenceOptions: [TimeInterval] = [30, 60, 120, 300]

    static func cadenceLabel(_ interval: TimeInterval) -> String {
        if interval < 60 { return "Every \(Int(interval)) seconds" }
        let minutes = Int(interval / 60)
        return minutes == 1 ? "Every minute" : "Every \(minutes) minutes"
    }

    private init() {
        let defaults = UserDefaults.standard
        self.pollingEnabled = defaults.object(forKey: Self.pollingEnabledKey) as? Bool ?? true
        // Defaults follow AppConfigs (source of truth for poll intervals).
        self.activeBuildCadence = defaults.object(forKey: Self.activeCadenceKey) as? TimeInterval ?? AppConfigs.buildStatusPollInterval
        self.generalResourceCadence = defaults.object(forKey: Self.generalCadenceKey) as? TimeInterval ?? 300
        self.monitorBuildStatusChanges = defaults.object(forKey: Self.monitorBuildsKey) as? Bool ?? true
        self.monitorReviewAndExpiry = defaults.object(forKey: Self.monitorReviewKey) as? Bool ?? true
        self.notifyBuildValid = defaults.object(forKey: Self.notifyValidKey) as? Bool ?? true
        self.notifyBetaReadiness = defaults.object(forKey: Self.notifyBetaKey) as? Bool ?? true
        // Figma shows "App Store version status changes" off by default.
        self.notifyVersionStatus = defaults.object(forKey: Self.notifyVersionKey) as? Bool ?? false
        self.notifyBuildFailed = defaults.object(forKey: Self.notifyFailedKey) as? Bool ?? true
        self.notifyExpiryReminders = defaults.object(forKey: Self.notifyExpiryKey) as? Bool ?? true
    }

    /// Whether a terminal processingState may post a desktop notification.
    func allowsNotification(for processingState: String?) -> Bool {
        switch processingState {
        case "VALID": return notifyBuildValid
        case "FAILED", "INVALID": return notifyBuildFailed
        default: return false
        }
    }
}

// MARK: - Monitoring preferences view (Figma 3-6386)

/// "Monitoring Preferences" — app-owned desktop polling section, polling
/// behavior note, notification preferences and the last-snapshot footer.
/// Uses system colors so the light/dark Figma variants (3-6386) come free.
struct MonitoringPreferencesView: View {
    @ObservedObject var prefs: MonitoringPreferences
    var lastSnapshot: Date?
    var processingCount: Int
    var lastPollSucceeded: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                pollingSection
                notificationSection
                snapshotFooter
            }
            .padding(24)
        }
        .background(ShipyardTheme.tableBackground)
    }

    private var pollingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("APP-OWNED DESKTOP POLLING")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(ShipyardTheme.body)
            ShipyardCard {
                Toggle("Enable desktop polling", isOn: $prefs.pollingEnabled)
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.title)
                    .toggleStyle(.switch)
                Text("Polls App Store Connect when this app is running, online, and authorized. Does not rely on Apple push notifications.")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
            }
            ShipyardCard {
                HStack {
                    Text("Active build polling cadence")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                    Spacer()
                    Menu {
                        ForEach(MonitoringPreferences.activeCadenceOptions, id: \.self) { option in
                            Button(MonitoringPreferences.cadenceLabel(option)) {
                                prefs.activeBuildCadence = option
                            }
                        }
                    } label: {
                        ShipyardMenuLabel(text: MonitoringPreferences.cadenceLabel(prefs.activeBuildCadence))
                    }
                    .menuStyle(.borderlessButton)
                    .accessibilityLabel("Active build polling cadence")
                }
                Text("Applies to active builds only. Team-resource sync is configured separately and defaults to 5 minutes.")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
            }
            ShipyardCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Polling behavior")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    Text("Polling runs only when the app is enabled, running, online, and authorized. It pauses or backs off on offline, 401, 403, or 429 responses.")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                    Text("Last successful snapshot is kept, but stale. Inaccessible resources are skipped; the app does not assume the whole team is blocked.")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                }
            }
        }
    }

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NOTIFICATION PREFERENCES")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(ShipyardTheme.body)
            VStack(spacing: 0) {
                notificationRow(
                    title: "Build processed VALID",
                    subtitle: "Build processing completed successfully, but does not confirm TestFlight readiness or App Store eligibility.",
                    isOn: $prefs.notifyBuildValid
                )
                notificationRow(
                    title: "TestFlight readiness via BuildBetaDetail",
                    subtitle: "Separate signal for when a build is ready for internal or external testing.",
                    isOn: $prefs.notifyBetaReadiness
                )
                notificationRow(
                    title: "App Store version status changes",
                    subtitle: "Separate from build processing state; AppVersionState.INVALID_BINARY belongs to the version, not the build.",
                    isOn: $prefs.notifyVersionStatus
                )
                notificationRow(
                    title: "Build failed or invalid",
                    subtitle: "Build.processingState FAILED or INVALID; display returned upload diagnostics only when available.",
                    isOn: $prefs.notifyBuildFailed
                )
                notificationRow(
                    title: "Expiry reminders",
                    subtitle: "Local reminders from build, certificate and profile expirationDate.",
                    isOn: $prefs.notifyExpiryReminders
                )
            }
            .background(LaunchTheme.card)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(LaunchTheme.border, lineWidth: 1))
            ShipyardCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Desktop notification controls")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    Text("Native macOS permission controls apply to desktop notifications. In-app alerts remain available even if desktop notifications are denied.")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                }
            }
        }
    }

    private func notificationRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.title)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(12)
    }

    private var snapshotFooter: some View {
        HStack {
            Text(snapshotLine)
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(lastPollSucceeded ? ShipyardTheme.success : ShipyardTheme.warning)
                    .frame(width: 6, height: 6)
                Text(lastPollSucceeded ? "Last poll succeeded" : "Last poll did not succeed")
                    .font(.system(size: 11))
                    .foregroundColor(lastPollSucceeded ? ShipyardTheme.success : ShipyardTheme.warning)
            }
        }
        .padding(12)
        .background(LaunchTheme.card)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(LaunchTheme.border, lineWidth: 1))
    }

    private var snapshotLine: String {
        let when: String
        if let lastSnapshot {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            when = formatter.string(from: lastSnapshot)
        } else {
            when = "never"
        }
        return "Local last successful check: \(when) · \(processingCount) builds processing in this snapshot"
    }
}

/// Card container shared by the monitoring screens (Figma rounded-8 rows).
struct ShipyardCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LaunchTheme.card)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(LaunchTheme.border, lineWidth: 1))
    }
}

// MARK: - Local observed alert center (Figma 114-10778)

/// One row of the cross-app alert center. Alerts are local observations
/// (poll diffs, expiry reminders), never complete Apple history.
struct MonitorAlert: Identifiable, Equatable {
    enum Kind: Equatable {
        case buildProcessing
        case buildTransition
        case versionTransition
        case certificateExpiry
        case profileExpiry
        case buildExpiry
    }

    let id: String
    let resource: String
    let transition: String
    let observed: String
    /// Jump destination label, e.g. "Open Build →".
    let jumpLabel: String
    let kind: Kind
    let isRead: Bool
    /// Search query preset for the destination section (cert/profile name).
    /// Nil when the destination needs no filter.
    var jumpQuery: String?
}

/// Cross-app alert center: monitor-preference checkboxes, filter chips,
/// the observed-alerts table and the ledger footer. Alerts open the
/// selected resource in its feature section via onJump.
struct AlertCenterView: View {
    @ObservedObject var prefs: MonitoringPreferences
    var alerts: [MonitorAlert]
    var lastSnapshot: Date?
    var onJump: (MonitorAlert) -> Void
    var onOpenPreferences: () -> Void
    var onOpenNotificationSettings: () -> Void
    var onMarkRead: () -> Void

    @State private var appFilter: String?
    @State private var typeFilter: MonitorAlert.Kind?
    @State private var unreadOnly = false

    private var visibleAlerts: [MonitorAlert] {
        alerts.filter { alert in
            if unreadOnly, alert.isRead { return false }
            if let typeFilter, alert.kind != typeFilter { return false }
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heading
                    filters
                    preferencesColumns
                    alertsTable
                }
                .padding(24)
            }
            actionBar
        }
        .background(ShipyardTheme.tableBackground)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cross-app alert center")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            Text("Local observed changes and reminders · last successful poll \(snapshotText)")
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
        }
    }

    private var snapshotText: String {
        guard let lastSnapshot else { return "never" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: lastSnapshot)
    }

    private var filters: some View {
        HStack(spacing: 8) {
            Menu {
                Button("All") { appFilter = nil }
            } label: {
                ShipyardMenuLabel(text: "App: \(appFilter ?? "All")")
            }
            .menuStyle(.borderlessButton)
            Menu {
                Button("All") { typeFilter = nil }
                Button("Builds") { typeFilter = .buildTransition }
                Button("Expiry") { typeFilter = .certificateExpiry }
            } label: {
                ShipyardMenuLabel(text: "Type: All")
            }
            .menuStyle(.borderlessButton)
            Button(unreadOnly ? "Unread only •" : "Unread only") {
                unreadOnly.toggle()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            ShipyardMenuLabel(text: "Auto-poll: Builds 30 sec · Resources 5 min")
        }
    }

    private var preferencesColumns: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Monitor preferences")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                checkRow(
                    title: "Build status changes",
                    subtitle: "Build: PROCESSING / FAILED / INVALID / VALID. TestFlight readiness is checked separately.",
                    isOn: $prefs.monitorBuildStatusChanges
                )
                checkRow(
                    title: "Review and expiry alerts",
                    subtitle: "Version/review states from Apple; expiry reminders derived locally from expirationDate.",
                    isOn: $prefs.monitorReviewAndExpiry
                )
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("macOS notifications")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                Text("Native macOS notifications are optional. In-app alerts remain if denied. Polling pauses/backoffs per scope when offline, unauthorized or rate-limited.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
            }
        }
    }

    private func checkRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                isOn.wrappedValue.toggle()
            } label: {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .foregroundColor(isOn.wrappedValue ? ShipyardTheme.accent : ShipyardTheme.body)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.title)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
            }
        }
        .padding(.vertical, 4)
    }

    private var alertsTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Resource").frame(maxWidth: .infinity, alignment: .leading)
                Text("Transition / alert").frame(maxWidth: .infinity, alignment: .leading)
                Text("Observed locally").frame(maxWidth: .infinity, alignment: .leading)
                Text("Jump").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 11))
            .foregroundColor(ShipyardTheme.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(ShipyardTheme.tableHeader)
            ForEach(visibleAlerts) { alert in
                HStack(spacing: 12) {
                    Text(alert.resource)
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(alert.transition)
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(alert.observed)
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(alert.jumpLabel) { onJump(alert) }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(alert.isRead ? Color.clear : ShipyardTheme.infoSurface.opacity(0.4))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(LaunchTheme.border, lineWidth: 1))
        .cornerRadius(6)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Text("Local observation ledger — not complete Apple history. Refresh each resource for current state.")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
            Spacer()
            Button("Monitoring Preferences", action: onOpenPreferences)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("Notification Settings…", action: onOpenNotificationSettings)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("Mark Read", action: onMarkRead)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(ShipyardTheme.sidebarBackground)
        .overlay(ShipyardTheme.rowDivider.frame(height: 1), alignment: .top)
    }
}

// MARK: - Notification permission preprompt (Figma 114-10924)

/// "Allow Shipyard notifications?" — optional macOS preprompt. Allow opens
/// the native permission prompt; denied shows "Notifications off" plus Open
/// System Settings; allowed shows "Notifications enabled". Returns to the
/// originating screen on dismiss.
struct NotificationPermissionSheet: View {
    var status: String
    var isDenied: Bool
    var onNotNow: () -> Void
    var onRequestPermission: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Allow Shipyard notifications?")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            VStack(alignment: .leading, spacing: 12) {
                Text("Optional macOS notifications")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                Text("Allow notifications for the build transitions, review changes, and expiry reminders enabled in Monitoring. Declining does not disable the in-app alert center.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Current permission")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                Text("Allow opens the native macOS permission prompt. If denied, show “Notifications off” and Open System Settings; if allowed, show “Notifications enabled”. No separate desktop notification concept is recreated.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
                VStack(alignment: .leading, spacing: 5) {
                    Text("macOS status")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.title)
                    Text(status)
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.body)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ShipyardTheme.readOnlyField)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(LaunchTheme.border, lineWidth: 1))
                }
                if isDenied {
                    Link("Open System Settings", destination: URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                        .font(.system(size: 12))
                }
            }
            HStack {
                Spacer()
                Button("Not Now", action: onNotNow)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Request macOS Permission", action: onRequestPermission)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 560)
    }
}

// MARK: - M12-O · Monitoring paused offline (Figma 195-2261)

/// Offline branch: the local scheduler is paused, the last successful
/// snapshot is explicitly stale (#412 stays last-known PROCESSING), cached
/// reads and drafts stay available, network writes stay blocked. Check
/// Connection verifies connectivity only — it never accelerates Apple
/// processing and never promises a completion time.
struct MonitoringOfflineView: View {
    var lastSnapshot: Date?
    var rows: [OfflineSnapshotRow]
    var onOpenPreferences: () -> Void
    var onCheckConnection: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Monitoring paused · offline")
                        .font(.system(size: 18))
                        .foregroundColor(ShipyardTheme.title)
                    Text("Acme Mobile / Orbit · com.acme.orbit · Apple ID 148923481")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                }
                warningBanner(
                    title: "Stale snapshot · last successful snapshot \(snapshotText)",
                    body: "Shipyard’s local scheduler is paused. Orbit #412 was PROCESSING at the last successful observation; its current Apple state is unknown. No new server data has been received while offline."
                )
                HStack(spacing: 8) {
                    ShipyardMenuLabel(text: "App: Orbit")
                    ShipyardMenuLabel(text: "Scope: Acme Mobile")
                    Text("Read-only cached resources · freshness tracked per resource and scope")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                }
                snapshotTable
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reconnect, then refresh resources")
                            .font(.system(size: 13))
                            .foregroundColor(ShipyardTheme.title)
                        Text("Check Connection verifies connectivity, not resource freshness. Once online and authorized, refresh each affected scope. Checking now cannot accelerate Apple processing and does not guarantee a completion time.")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Local work remains available")
                            .font(.system(size: 13))
                            .foregroundColor(ShipyardTheme.title)
                        Text("Read cached records, edit drafts and mark alerts read locally. In-app alerts and macOS notifications may reflect cached observations or local reminders — not new Apple data. Saves, revocations and other network writes stay blocked.")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                    }
                }
                Text("Client policy: active builds 30 sec · general resources 5 min, only when enabled, running, online and authorized. These intervals are not a freshness SLA.")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
            }
            .padding(24)
        }
        .background(ShipyardTheme.tableBackground)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Text("Cached reads and local drafts available · network writes blocked")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                Spacer()
                Button("Monitoring Preferences", action: onOpenPreferences)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Check Connection", action: onCheckConnection)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.horizontal, 24)
            .frame(height: 56)
            .background(ShipyardTheme.sidebarBackground)
        }
    }

    private var snapshotText: String {
        guard let lastSnapshot else { return "unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: lastSnapshot)
    }

    private var snapshotTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Resource / scope").frame(maxWidth: .infinity, alignment: .leading)
                Text("Last known Apple value").frame(maxWidth: .infinity, alignment: .leading)
                Text("Successful local observation").frame(maxWidth: .infinity, alignment: .leading)
                Text("Freshness / next step").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 11))
            .foregroundColor(ShipyardTheme.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(ShipyardTheme.tableHeader)
            ForEach(rows) { row in
                HStack(spacing: 12) {
                    Text(row.resource).frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.lastKnown).frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.observed).frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.freshness)
                        .foregroundColor(ShipyardTheme.warningBorder)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.title)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(LaunchTheme.border, lineWidth: 1))
        .cornerRadius(6)
    }
}

struct OfflineSnapshotRow: Identifiable {
    let id = UUID()
    let resource: String
    let lastKnown: String
    let observed: String
    let freshness: String
}

// MARK: - M12-L · Monitoring backoff after rate limit (Figma 195-2391)

/// Rate-limit branch: the selected scope returned an illustrative HTTP 429.
/// One poll is queued, overlap is prevented, Retry stays disabled until the
/// local backoff policy permits another request. X-Rate-Limit values are
/// shown only if actually received — no fixed 3500 limit, no universal
/// Retry-After countdown. Other reads continue only as budget/scope allows;
/// no automatic writes.
struct MonitoringRateLimitView: View {
    var lastSnapshot: Date?
    var backoffAvailableDate: Date?
    var rateLimitHeader: String?
    var onOpenPreferences: () -> Void
    var onRetry: () -> Void

    private var retryLocked: Bool { backoffAvailableDate.map { $0 > Date() } ?? true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Monitoring waiting · rate limit")
                        .font(.system(size: 18))
                        .foregroundColor(ShipyardTheme.title)
                    Text("Selected scope: Acme Mobile / Orbit builds · illustrative received response")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                }
                warningBanner(
                    title: "HTTP 429 · RATE_LIMIT_EXCEEDED",
                    body: "The selected scope returned a rate-limit error. Its last successful snapshot is stale. Shipyard has queued one poll and entered client backoff; retry remains disabled until the backoff policy permits another request."
                )
                HStack(spacing: 8) {
                    ShipyardMenuLabel(text: "App: Orbit")
                    ShipyardMenuLabel(text: "Scope: Orbit build polling")
                    Text("GET /v1/builds · selected authorized scope")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(ShipyardTheme.body)
                }
                rateLimitTable
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Received header details · optional metadata")
                            .font(.system(size: 13))
                            .foregroundColor(ShipyardTheme.title)
                        Text(headerDetails)
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Wait is governed by client policy")
                            .font(.system(size: 13))
                            .foregroundColor(ShipyardTheme.title)
                        Text("Honor actual response headers when available. Otherwise use the local backoff policy and persisted queue state. Re-evaluate eligibility before dispatch; a queued poll is not a promise of new data in 30 seconds.")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("After backoff")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                    Text("When eligible, run one authorized read and update only successfully refreshed resources. A check cannot accelerate Apple processing. Keep drafts and local alert read flags; never auto-retry writes or hot-retry a forbidden operation.")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                }
                Text("Last successful Orbit build snapshot: \(snapshotText) · observation time is a local poll time, not Apple event history.")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
            }
            .padding(24)
        }
        .background(ShipyardTheme.tableBackground)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Text("1 deduplicated poll queued · no overlapping requests · no automatic writes")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                Spacer()
                Button("Monitoring Preferences", action: onOpenPreferences)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button(retryLocked ? "Retry Selected Scope · locked" : "Retry Selected Scope", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(retryLocked)
            }
            .padding(.horizontal, 24)
            .frame(height: 56)
            .background(ShipyardTheme.sidebarBackground)
        }
    }

    private var headerDetails: String {
        if let rateLimitHeader, !rateLimitHeader.isEmpty {
            return "X-Rate-Limit: \(rateLimitHeader) (as received, rolling user-hour). Retry-After: not received; no countdown is shown."
        }
        return "X-Rate-Limit: not received in this illustrative response. If returned, show user-hour-lim and user-hour-rem exactly as received (rolling user-hour). No fixed entitlement is assumed. Retry-After: not received; no countdown is shown."
    }

    private var snapshotText: String {
        guard let lastSnapshot else { return "unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: lastSnapshot)
    }

    private var rateLimitTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Resource / scope").frame(maxWidth: .infinity, alignment: .leading)
                Text("Last successful snapshot").frame(maxWidth: .infinity, alignment: .leading)
                Text("Current scheduler state").frame(maxWidth: .infinity, alignment: .leading)
                Text("Guard").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 11))
            .foregroundColor(ShipyardTheme.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(ShipyardTheme.tableHeader)
            rateRow(
                resource: "Orbit #412 · Build",
                snapshot: "\(snapshotText)\nPROCESSING · stale",
                state: "Poll queued · client backoff",
                guard: "Retry locked · no overlapping poll"
            )
            rateRow(
                resource: "Orbit · Beta detail",
                snapshot: "Separate cached snapshot\nNot refreshed by the 429 response",
                state: "Dependent poll held",
                guard: "No inferred TestFlight readiness"
            )
            rateRow(
                resource: "Other authorized resources",
                snapshot: "Independent per-resource timestamps",
                state: "May continue as budget / scope allows",
                guard: "No blanket freshness claim; no writes"
            )
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(LaunchTheme.border, lineWidth: 1))
        .cornerRadius(6)
    }

    private func rateRow(resource: String, snapshot: String, state: String, guard guardText: String) -> some View {
        HStack(spacing: 12) {
            Text(resource).frame(maxWidth: .infinity, alignment: .leading)
            Text(snapshot).frame(maxWidth: .infinity, alignment: .leading)
            Text(state)
                .foregroundColor(ShipyardTheme.warningBorder)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(guardText).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12))
        .foregroundColor(ShipyardTheme.title)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - General settings (Figma 3-4361 settings-general-light)

/// Opens an App Store Connect URL honoring the "Open Links in External
/// Browser" preference. On macOS every Link already leaves the app, so the
/// toggle governs programmatic opens: external browser vs. Jaeger-style
/// in-app handling stays a single chokepoint for future call sites.
enum ASCLink {
    static func open(_ url: URL) {
        // NSWorkspace.open is the external-browser path; the preference
        // exists so in-app routing can be introduced without touching
        // call sites.
        NSWorkspace.shared.open(url)
    }
}

/// General Settings window (Figma 3-4361): General / Teams / Monitoring /
/// Notifications / Snippets / Advanced. Light and dark variants come from
/// system colors — no separate theme code.
struct ShipyardSettingsSheet: View {
    @AppStorage(UserDefaultsKeys.defaultStartupView) private var startupView = "apps"
    @AppStorage(UserDefaultsKeys.defaultMetadataLocale) private var defaultLocale = "en-US"
    @AppStorage(UserDefaultsKeys.openLinksInExternalBrowser) private var openLinksExternal = true
    @AppStorage(UserDefaultsKeys.showExtendedInfo) private var showExtendedInfo = true
    @ObservedObject private var prefs = MonitoringPreferences.shared
    @ObservedObject private var credentialStorage = CredentialStorage.shared
    @Environment(\.colorScheme) private var colorScheme

    enum Pane: String, CaseIterable {
        case general, teams, monitoring, notifications, snippets, advanced

        var title: String {
            switch self {
            case .general: return "General"
            case .teams: return "Teams"
            case .monitoring: return "Monitoring"
            case .notifications: return "Notifications"
            case .snippets: return "Snippets"
            case .advanced: return "Advanced"
            }
        }
    }

    @State private var pane: Pane = .general
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $pane) {
                ForEach(Pane.allCases, id: \.self) { item in
                    Text(item.title).tag(item)
                }
            }
            .frame(width: 200)
            paneContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 760, height: 520)
    }

    @ViewBuilder
    private var paneContent: some View {
        switch pane {
        case .general: generalPane
        case .teams: teamsPane
        case .monitoring:
            MonitoringPreferencesView(
                prefs: prefs,
                lastSnapshot: nil,
                processingCount: 0,
                lastPollSucceeded: true
            )
        case .notifications:
            notificationsPane
        case .snippets:
            snippetsPane
        case .advanced:
            advancedPane
        }
    }

    private var generalPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("General Configuration")
                    .font(.system(size: 16))
                    .foregroundColor(ShipyardTheme.title)
                generalRow(
                    title: "Default Startup View",
                    subtitle: "Choose the screen displayed when launching Shipyard.",
                    control: AnyView(
                        Menu {
                            Button("Apps") { startupView = "apps" }
                            Button("Builds") { startupView = "builds" }
                            Button("Processing Builds") { startupView = "monitoring" }
                        } label: {
                            ShipyardMenuLabel(text: "View: \(startupName)")
                        }
                        .menuStyle(.borderlessButton)
                    )
                )
                Divider()
                generalRow(
                    title: "Default Metadata Locale",
                    subtitle: "Default editing locale only; does not change Apple’s primaryLocale.",
                    control: AnyView(
                        Menu {
                            ForEach(BetaLocalizationLocales.supported, id: \.self) { code in
                                Button("\(BetaLocalizationLocales.displayName(for: code)) (\(code))") {
                                    defaultLocale = code
                                }
                            }
                        } label: {
                            ShipyardMenuLabel(text: "Locale: \(BetaLocalizationLocales.displayName(for: defaultLocale))")
                        }
                        .menuStyle(.borderlessButton)
                    )
                )
                Divider()
                generalRow(
                    title: "Open Links in External Browser",
                    subtitle: "Redirect App Store Connect links to your default macOS browser.",
                    control: AnyView(
                        Toggle("", isOn: $openLinksExternal)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    )
                )
            }
            .padding(24)
        }
        .background(ShipyardTheme.tableBackground)
    }

    private var startupName: String {
        switch startupView {
        case "builds": return "Builds"
        case "monitoring": return "Processing Builds"
        default: return "Apps"
        }
    }

    private func generalRow(title: String, subtitle: String, control: AnyView) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.title)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
            }
            Spacer()
            control
        }
    }

    private var teamsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Teams")
                    .font(.system(size: 16))
                    .foregroundColor(ShipyardTheme.title)
                Text("API credentials live in your Keychain and are never logged. Declared access controls navigation only; Apple's response still decides whether an operation is authorized.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
                ForEach(credentialStorage.teams, id: \.self) { team in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(team)
                                    .font(.system(size: 13))
                                    .foregroundColor(ShipyardTheme.title)
                                if credentialStorage.selectedTeam?.key == team {
                                    Text(credentialStorage.selectedTeam?.access?.displayName ?? "Access not configured · all navigation shown")
                                        .font(.system(size: 10))
                                        .foregroundColor(ShipyardTheme.body)
                                }
                            }
                            Spacer()
                            if credentialStorage.selectedTeam?.key == team {
                                Text("Active")
                                    .font(.system(size: 11))
                                    .foregroundColor(ShipyardTheme.body)
                            } else {
                                Button("Switch") {
                                    credentialStorage.changeTeam = team
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }

                        if credentialStorage.selectedTeam?.key == team {
                            HStack(spacing: 8) {
                                Menu {
                                    ForEach(AppStoreConnectKeyKind.allCases) { kind in
                                        Button(kind.displayName) {
                                            updateActiveAccess(kind: kind)
                                        }
                                    }
                                } label: {
                                    ShipyardMenuLabel(text: credentialStorage.selectedTeam?.access?.kind.displayName ?? "Key Type")
                                }
                                .menuStyle(.borderlessButton)

                                Menu {
                                    ForEach(AppStoreConnectKeyRole.allCases) { role in
                                        Button(role.displayName) {
                                            updateActiveAccess(role: role)
                                        }
                                    }
                                } label: {
                                    ShipyardMenuLabel(text: credentialStorage.selectedTeam?.access?.role.displayName ?? "Access Role")
                                }
                                .menuStyle(.borderlessButton)

                                if credentialStorage.selectedTeam?.access != nil {
                                    Button("Clear") {
                                        _ = credentialStorage.updateAccess(nil, for: team)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(LaunchTheme.card)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(LaunchTheme.border, lineWidth: 1))
                }
            }
            .padding(24)
        }
        .background(ShipyardTheme.tableBackground)
    }

    private func updateActiveAccess(kind: AppStoreConnectKeyKind? = nil,
                                    role: AppStoreConnectKeyRole? = nil) {
        guard let credential = credentialStorage.selectedTeam else { return }
        let current = credential.access ?? AppStoreConnectKeyAccess(kind: .team, role: .developer)
        let updated = AppStoreConnectKeyAccess(
            kind: kind ?? current.kind,
            role: role ?? current.role
        )
        _ = credentialStorage.updateAccess(updated, for: credential.key)
    }

    private var notificationsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Notifications")
                    .font(.system(size: 16))
                    .foregroundColor(ShipyardTheme.title)
                Text("Native macOS permission controls apply to desktop notifications. In-app alerts in the Processing Builds section remain available even if desktop notifications are denied.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
                Button("Open Notification Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        ASCLink.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(24)
        }
        .background(ShipyardTheme.tableBackground)
    }

    private var snippetsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Snippets")
                    .font(.system(size: 16))
                    .foregroundColor(ShipyardTheme.title)
                Text("Release-note building blocks. Copy one, then paste it into any whats-new or description draft.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
                ForEach(ReleaseNoteSnippets.all, id: \.self) { snippet in
                    HStack(alignment: .top, spacing: 8) {
                        Text(snippet)
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.title)
                            .lineLimit(3)
                        Spacer()
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(snippet, forType: .string)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(LaunchTheme.card)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(LaunchTheme.border, lineWidth: 1))
                }
            }
            .padding(24)
        }
        .background(ShipyardTheme.tableBackground)
    }

    private var advancedPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Advanced")
                    .font(.system(size: 16))
                    .foregroundColor(ShipyardTheme.title)
                Toggle("Dark Mode", isOn: Binding(
                    get: { colorScheme == .dark },
                    set: { _ in AppAppearance.toggle() }
                ))
                .font(.system(size: 12))
                Toggle("Show App Info, Reviews & Resources", isOn: $showExtendedInfo)
                    .font(.system(size: 12))
            }
            .padding(24)
        }
        .background(ShipyardTheme.tableBackground)
    }
}

// MARK: - Shared warning banner

/// Amber status-message banner shared by the monitoring branches.
func warningBanner(title: String, body: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
        Text("⚠")
            .font(.system(size: 16))
            .foregroundColor(ShipyardTheme.warningBorder)
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.warningBorder)
            Text(body)
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
        }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(ShipyardTheme.warningSurface)
    .cornerRadius(8)
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ShipyardTheme.warningBorder, lineWidth: 0.5))
}
