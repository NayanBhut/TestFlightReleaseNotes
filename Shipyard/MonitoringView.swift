//
//  MonitoringView.swift
//  App Store
//
//  Module 12 monitoring section: the local observed alert center
//  (Figma 114-10778) with the offline-paused (M12-O) and rate-limit
//  backoff (M12-L) branches, the full-screen monitoring preferences
//  (3-6386) and the notification-permission preprompt (114-10924).
//
//  Alerts are local observations (poll diffs, locally derived expiry
//  reminders), never complete Apple history. Jumps open the selected
//  resource in its feature section; dismissal returns to origin.
//

import SwiftUI
@preconcurrency import UserNotifications

struct MonitoringView: View {
    @ObservedObject var monitor: BuildProcessingMonitor
    @ObservedObject var resourcesVM: ResourcesViewModel
    @ObservedObject private var prefs = MonitoringPreferences.shared

    var onOpenBuilds: () -> Void
    var onOpenApps: () -> Void
    var onOpenCertificate: (String?) -> Void
    var onOpenProfile: (String?) -> Void

    @State private var showPreferences = false
    @State private var showNotificationSettings = false
    @State private var notificationStatus = "Not determined"
    @State private var notificationDenied = false
    @State private var isCheckingConnection = false

    /// App-owned read flags (contract: read flags / Mark Read are local).
    @AppStorage("monitoring.readAlertIds") private var readAlertIdsData = Data()

    private var readIds: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: readAlertIdsData)) ?? []
    }

    var body: some View {
        Group {
            // Figma 3-6386 is a full Preferences screen, not a popup: it
            // takes over the whole section with a back toolbar. Dismissal
            // returns to the originating monitoring state.
            if showPreferences {
                preferencesScreen
            } else {
                switch monitor.connectionState {
                case .offline:
                    MonitoringOfflineView(
                        lastSnapshot: monitor.lastPollDate,
                        rows: offlineRows,
                        onOpenPreferences: { showPreferences = true },
                        onCheckConnection: checkConnection
                    )
                case .rateLimited:
                    MonitoringRateLimitView(
                        lastSnapshot: monitor.lastPollDate,
                        backoffAvailableDate: monitor.backoffAvailableDate,
                        rateLimitHeader: nil,
                        onOpenPreferences: { showPreferences = true },
                        onRetry: { Task { await monitor.pollNow() } }
                    )
                case .online:
                    AlertCenterView(
                        prefs: prefs,
                        alerts: alerts,
                        lastSnapshot: monitor.lastPollDate,
                        onJump: jump,
                        onOpenPreferences: { showPreferences = true },
                        onOpenNotificationSettings: openNotificationSettings,
                        onMarkRead: markAllRead
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShipyardTheme.tableBackground)
        .sheet(isPresented: $showNotificationSettings) {
            NotificationPermissionSheet(
                status: notificationStatus,
                isDenied: notificationDenied,
                onNotNow: { showNotificationSettings = false },
                onRequestPermission: requestNotificationPermission
            )
        }
    }

    // MARK: - Full-screen preferences (Figma 3-6386)

    /// "Monitoring Preferences" as a full section screen: back toolbar on
    /// top, the app-owned polling + notification preferences below.
    private var preferencesScreen: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: { showPreferences = false }) {
                    Text("‹ Monitoring")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to monitoring")
                Text("Monitoring Preferences")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.title)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(LaunchTheme.page)
            Divider()
            MonitoringPreferencesView(
                prefs: prefs,
                lastSnapshot: monitor.lastPollDate,
                processingCount: monitor.processingBuilds.count,
                lastPollSucceeded: monitor.lastError == nil && monitor.lastPollDate != nil
            )
        }
    }

    // MARK: - Alerts

    private var alerts: [MonitorAlert] {
        var items: [MonitorAlert] = []
        let read = readIds
        if prefs.monitorBuildStatusChanges {
            for build in monitor.processingBuilds {
                let resource = build.appName.isEmpty
                    ? "Build #\(build.buildNumber)"
                    : "\(build.appName) #\(build.buildNumber)"
                items.append(MonitorAlert(
                    id: "build-\(build.id)",
                    resource: resource,
                    transition: "Build PROCESSING · unchanged at poll",
                    observed: observedText(monitor.lastPollDate),
                    jumpLabel: "Open Build →",
                    kind: .buildProcessing,
                    isRead: read.contains("build-\(build.id)")
                ))
            }
        }
        if prefs.monitorReviewAndExpiry, prefs.notifyExpiryReminders {
            items += expiryAlerts(read: read)
        }
        return items
    }

    /// Expiry reminders derived locally from expirationDate (certificates
    /// + profiles). Only items expiring within 30 days surface — the API
    /// offers no reminder feed, so this is a local computation.
    private func expiryAlerts(read: Set<String>) -> [MonitorAlert] {
        var items: [MonitorAlert] = []
        let soon = Date().addingTimeInterval(30 * 24 * 3600)
        if case .loaded(let certificates) = resourcesVM.certificatesState {
            for cert in certificates {
                guard let raw = cert.expirationDate,
                      let date = ISO8601DateFormatter().date(from: raw),
                      date <= soon else { continue }
                let name = cert.displayName ?? cert.name ?? "Certificate"
                items.append(MonitorAlert(
                    id: "cert-\(cert.id)",
                    resource: name,
                    transition: "Certificate expires \(displayDate(date)) · derived from expirationDate",
                    observed: observedText(monitor.lastPollDate),
                    jumpLabel: "Open Certificate →",
                    kind: .certificateExpiry,
                    isRead: read.contains("cert-\(cert.id)"),
                    jumpQuery: name
                ))
            }
        }
        // Profiles state is internal to ResourcesViewModel; surface the
        // loaded profiles through its filtered list when available.
        for profile in resourcesVM.filteredProfiles {
            guard let raw = profile.expirationDate,
                  let date = ISO8601DateFormatter().date(from: raw),
                  date <= soon else { continue }
            let name = profile.name ?? "Profile"
            items.append(MonitorAlert(
                id: "profile-\(profile.id)",
                resource: name,
                transition: "Profile expires \(displayDate(date)) · derived from expirationDate",
                observed: observedText(monitor.lastPollDate),
                jumpLabel: "Open Profile →",
                kind: .profileExpiry,
                isRead: read.contains("profile-\(profile.id)"),
                jumpQuery: name
            ))
        }
        return items
    }

    private func observedText(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func markAllRead() {
        let ids = Set(alerts.map(\.id))
        readAlertIdsData = (try? JSONEncoder().encode(ids)) ?? Data()
    }

    private func jump(_ alert: MonitorAlert) {
        switch alert.kind {
        case .buildProcessing, .buildTransition, .buildExpiry:
            onOpenBuilds()
        case .versionTransition:
            onOpenApps()
        case .certificateExpiry:
            onOpenCertificate(alert.jumpQuery)
        case .profileExpiry:
            onOpenProfile(alert.jumpQuery)
        }
    }

    // MARK: - Offline snapshot rows (M12-O)

    private var offlineRows: [OfflineSnapshotRow] {
        let observed = observedText(monitor.lastPollDate)
        var rows = monitor.processingBuilds.map { build in
            OfflineSnapshotRow(
                resource: "\(build.appName.isEmpty ? "Unknown App" : build.appName) #\(build.buildNumber) · Build",
                lastKnown: "processingState: PROCESSING",
                observed: observed,
                freshness: "Stale · current state unknown"
            )
        }
        rows.append(OfflineSnapshotRow(
            resource: "Acme Mobile · Certificates",
            lastKnown: "Cached certificate records",
            observed: observed,
            freshness: "Stale · refresh this team scope"
        ))
        rows.append(OfflineSnapshotRow(
            resource: "Acme Mobile · Profiles",
            lastKnown: "Cached profile records",
            observed: observed,
            freshness: "Stale · refresh dependencies"
        ))
        return rows
    }

    private func checkConnection() {
        // Verifies connectivity only — never resource freshness, never an
        // acceleration of Apple processing.
        isCheckingConnection = true
        Task {
            await monitor.pollNow()
            isCheckingConnection = false
        }
    }

    // MARK: - Notification permission (114-10924)

    private func openNotificationSettings() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    notificationStatus = "Notifications enabled"
                    notificationDenied = false
                case .denied:
                    notificationStatus = "Notifications off"
                    notificationDenied = true
                case .notDetermined:
                    notificationStatus = "Not determined"
                    notificationDenied = false
                @unknown default:
                    notificationStatus = "Not determined"
                    notificationDenied = false
                }
                showNotificationSettings = true
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in
                notificationStatus = granted ? "Notifications enabled" : "Notifications off"
                notificationDenied = !granted
            }
        }
    }
}
