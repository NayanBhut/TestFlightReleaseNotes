//
//  MonitoringDiagnostics.swift
//  App Store
//
//  Module 12 (Monitoring & Shared Actions), Flow 12E: original shared-error
//  concepts (Figma 3-4528) and the documented resource states (Figma 3-4894).
//  These are alternate states, not a sequential chain — each card renders
//  independently wherever its condition holds.
//
//  Contract notes:
//  - Permission failures return "broader permissions" hints, never raw
//    403s. Key roles: TestFlight key = builds/notes, App Manager+ = app
//    info writes, Admin = groups/testers/resources/users.
//  - 401 pauses the affected authorization; an expired JWT does not prove
//    the private key expired or was revoked.
//  - Offline states cache observations locally; they never present cached
//    data as fresh server state.
//

import SwiftUI

// MARK: - Shared error cards (Figma 3-4528, light)

/// The four original shared-error concepts. Each is independent: network
/// failure, authorization scope, empty collection, loading.
struct SharedErrorStatesView: View {
    var onRetryConnection: () -> Void
    var onShowDetails: () -> Void
    var onDismissPermission: () -> Void
    var onLearnAboutRoles: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            SharedErrorCard(
                icon: "exclamationmark.triangle.fill",
                iconColor: ShipyardTheme.warningBorder,
                title: "Unable to Load Builds",
                message: "Check your network connection and try again.",
                primaryTitle: "Retry Connection",
                primaryAction: onRetryConnection,
                secondaryTitle: "Show Details",
                secondaryAction: onShowDetails
            )
            SharedErrorCard(
                icon: "exclamationmark.octagon.fill",
                iconColor: ShipyardTheme.danger,
                title: "Insufficient Permissions",
                message: "This operation is not authorized. Required permissions depend on the action, app scope and provisioning access.",
                primaryTitle: "Dismiss",
                primaryAction: onDismissPermission,
                secondaryTitle: "Learn About Roles",
                secondaryAction: onLearnAboutRoles
            )
            SharedErrorCard(
                icon: "tray",
                iconColor: ShipyardTheme.body,
                title: "No Builds Yet",
                message: "No builds are available for version 2.4.0.",
                primaryTitle: nil,
                primaryAction: nil,
                secondaryTitle: nil,
                secondaryAction: nil
            )
            SharedLoadingCard(text: "Loading builds…")
        }
    }
}

struct SharedErrorCard: View {
    var icon: String
    var iconColor: Color
    var title: String
    var message: String
    var primaryTitle: String?
    var primaryAction: (() -> Void)?
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(iconColor)
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(ShipyardTheme.title)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.body)
                    .multilineTextAlignment(.center)
            }
            if primaryTitle != nil || secondaryTitle != nil {
                HStack(spacing: 12) {
                    if let primaryTitle {
                        Button(primaryTitle, action: { primaryAction?() })
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    if let secondaryTitle {
                        Button(secondaryTitle, action: { secondaryAction?() })
                            .buttonStyle(.link)
                            .font(.system(size: 12))
                    }
                }
            }
        }
        .padding(32)
        .background(ShipyardTheme.tableBackground)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(LaunchTheme.border, lineWidth: 1))
    }
}

struct SharedLoadingCard: View {
    var text: String

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text(text)
                    .font(.system(size: 14))
                    .foregroundColor(ShipyardTheme.title)
            }
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(ShipyardTheme.sidebarBackground)
                    .frame(height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(ShipyardTheme.sidebarBackground)
                    .frame(height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(ShipyardTheme.sidebarBackground)
                    .frame(height: 12)
                    .frame(width: 200)
            }
        }
        .padding(32)
        .background(ShipyardTheme.tableBackground)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(LaunchTheme.border, lineWidth: 1))
    }
}

// MARK: - Documented resource states (Figma 3-4894, dark)

/// The four documented diagnostic states. Rendered with system colors so
/// the dark Figma frame maps directly; copy preserves the contract guards
/// (401 ≠ expired key, offline ≠ fresh data).
struct DiagnosticsStatesView: View {
    var onRetryConnection: () -> Void
    var onReconnect: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            DiagnosticsCard(
                icon: "wifi.slash",
                title: "Network Offline",
                message: "Unable to reach the App Store Connect server API endpoints.",
                actionTitle: "Retry Connection",
                action: onRetryConnection
            )
            DiagnosticsCard(
                icon: "shield.lefthalf.filled",
                title: "Key Not Authorized",
                message: "Authentication is not confirmed. Check JWT validity, IDs and key status; 401 alone does not prove the private key expired or was revoked.",
                actionTitle: "Reconnect…",
                action: onReconnect
            )
            DiagnosticsCard(
                icon: "folder",
                title: "No Builds Uploaded",
                message: "No builds are available for this app bundle ID.",
                actionTitle: nil,
                action: nil
            )
            DiagnosticsCard(
                icon: nil,
                title: "Syncing Resources…",
                message: "Fetching documented resources for this app.",
                actionTitle: nil,
                action: nil,
                showsProgress: true
            )
        }
    }
}

struct DiagnosticsCard: View {
    var icon: String?
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var showsProgress = false

    var body: some View {
        VStack(spacing: 16) {
            if showsProgress {
                ProgressView()
                    .scaleEffect(1.2)
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundColor(ShipyardTheme.danger)
            }
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle {
                Button(actionTitle, action: { action?() })
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(24)
        .background(LaunchTheme.card)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(LaunchTheme.border, lineWidth: 1))
    }
}

// MARK: - Permission hints (never raw 403s)

/// Broader-permissions hints per action family. Key roles: TestFlight key
/// covers builds/notes, App Manager+ covers app info writes, Admin covers
/// groups/testers/resources/users.
enum PermissionHint {
    static func hint(for action: PermissionAction) -> String {
        switch action {
        case .builds:
            return "This needs a TestFlight key or broader. Check the key role and app scope."
        case .appInfo:
            return "App info writes need an App Manager key or broader. Check the key role and app scope."
        case .resources:
            return "Resources need an Admin key or broader. Check the key role and team provisioning access."
        case .users:
            return "Users need an Admin key or broader. Check the key role and team access."
        }
    }
}

enum PermissionAction {
    case builds
    case appInfo
    case resources
    case users
}
