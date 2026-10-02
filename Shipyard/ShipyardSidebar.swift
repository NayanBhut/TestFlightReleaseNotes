//
//  ShipyardSidebar.swift
//  App Store
//
//  Post-auth navigation sidebar from the *-light Figma frames: team
//  selector (44pt, switch/add/remove), Apps row, MONITORING with the live
//  processing-build count, TEAM RESOURCES rows (PNG glyphs), and the
//  Settings/Help footer.
//

import SwiftUI

/// Content sections reachable from the sidebar.
enum ShipyardSection: String, CaseIterable, Hashable {
    case apps
    case builds
    case monitoring
    case devices
    case certificates
    case bundleIDs
    case profiles
    case users
    case reviews

    var title: String {
        switch self {
        case .apps: return "Apps"
        case .builds: return "Builds"
        case .monitoring: return "Processing Builds"
        case .devices: return "Devices"
        case .certificates: return "Certificates"
        case .bundleIDs: return "Bundle IDs"
        case .profiles: return "Profiles"
        case .users: return "Users"
        case .reviews: return "Reviews"
        }
    }

    var iconName: String {
        switch self {
        case .apps: return "ShipyardGrid"
        case .builds: return "ShipyardGrid"
        case .monitoring: return "ShipyardMonitorX"
        case .devices: return "ShipyardPhone"
        case .certificates: return "ShipyardCertCheck"
        case .bundleIDs: return "ShipyardBadge"
        case .profiles: return "ShipyardFileCog"
        case .users: return "ShipyardTeamUser"
        case .reviews: return "ShipyardStar"
        }
    }
}

struct ShipyardSidebar: View {
    @Binding var selection: ShipyardSection
    /// Live count for the Monitoring badge.
    var processingCount: Int
    var onAddTeam: () -> Void
    var onDeleteTeam: (String) -> Void
    /// Switches the active team. The shell flips the view model onto the
    /// new team and resets the section — the keychain write alone does not
    /// refresh anything.
    var onSelectTeam: (String) -> Void

    @ObservedObject private var credentialStorage = CredentialStorage.shared
    @State private var showTeams = false
    @State private var showSettings = false
    @State private var pendingDeleteTeam: String?

    var body: some View {
        VStack(spacing: 0) {
            teamSelector

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    navRow(.apps)

                    VStack(alignment: .leading, spacing: 4) {
                        sectionHeader("MONITORING")
                        monitoringRow
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        sectionHeader("TEAM RESOURCES")
                        ForEach([ShipyardSection.devices, .certificates, .bundleIDs, .profiles, .users, .reviews], id: \.self) { section in
                            navRow(section)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            }

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShipyardTheme.sidebarBackground)
        .confirmationDialog(
            "Remove team “\(pendingDeleteTeam ?? "")”? Its API key is deleted from your Keychain.",
            isPresented: Binding(
                get: { pendingDeleteTeam != nil },
                set: { if !$0 { pendingDeleteTeam = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Team", role: .destructive) {
                if let team = pendingDeleteTeam {
                    onDeleteTeam(team)
                    if credentialStorage.teams.count <= 1 {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showTeams = false
                        }
                    }
                }
                pendingDeleteTeam = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteTeam = nil
            }
        }
    }

    // MARK: - Team selector

    private var teamSelector: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTeams.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(ShipyardTheme.accent)
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                    Text(credentialStorage.selectedTeam?.key ?? "No Team")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                        .lineLimit(1)
                    Spacer()
                    ShipyardIcon(name: "ShipyardChevron", size: 12)
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Switch team")

            if showTeams {
                VStack(spacing: 2) {
                    ForEach(credentialStorage.teams, id: \.self) { team in
                        HStack {
                            Text(team)
                                .font(.system(size: 12))
                                .foregroundColor(ShipyardTheme.title)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(ShipyardTheme.danger)
                                .padding(6)
                                .contentShape(Rectangle())
                                .highPriorityGesture(
                                    TapGesture().onEnded {
                                        pendingDeleteTeam = team
                                    }
                                )
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel("Remove \(team)")
                                .accessibilityAction(.default) { pendingDeleteTeam = team }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelectTeam(team)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showTeams = false
                            }
                        }
                    }
                    Button {
                        showTeams = false
                        onAddTeam()
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                                .font(.system(size: 11))
                            Text("Add Team")
                                .font(.system(size: 12))
                            Spacer()
                        }
                        .foregroundColor(ShipyardTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LaunchTheme.card)
                        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .overlay(
            ShipyardTheme.rowDivider.frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Rows

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(ShipyardTheme.body)
    }

    private func navRow(_ section: ShipyardSection) -> some View {
        let isSelected = selection == section
        return Button {
            selection = section
        } label: {
            HStack(spacing: 8) {
                ShipyardIcon(name: section.iconName)
                Text(section.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(ShipyardTheme.title)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? ShipyardTheme.selectedRow : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var monitoringRow: some View {
        let isSelected = selection == .monitoring
        return Button {
            selection = .monitoring
        } label: {
            HStack(spacing: 8) {
                ShipyardIcon(name: ShipyardSection.monitoring.iconName)
                Text(ShipyardSection.monitoring.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(ShipyardTheme.title)
                Spacer()
                if processingCount > 0 {
                    ShipyardCountPill(text: "\(processingCount)")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? ShipyardTheme.selectedRow : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Processing Builds, \(processingCount) processing")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                showSettings.toggle()
            } label: {
                HStack(spacing: 6) {
                    ShipyardIcon(name: "ShipyardGear")
                    Text("Settings")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                ShipyardSettingsPopover()
                    .padding(12)
                    .frame(width: 240)
            }

            Spacer()

            Link(destination: URL(string: "https://developer.apple.com/documentation/appstoreconnectapi")!) {
                HStack(spacing: 6) {
                    ShipyardIcon(name: "ShipyardHelp")
                    Text("Help")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .overlay(
            ShipyardTheme.rowDivider.frame(height: 1),
            alignment: .top
        )
    }
}

/// Real settings behind the footer entry: appearance plus the Batch C
/// extended-info flag that gates App Info / Reviews / Resources detail.
private struct ShipyardSettingsPopover: View {
    @AppStorage(UserDefaultsKeys.showExtendedInfo) private var showExtendedInfo = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            Toggle("Dark Mode", isOn: Binding(
                get: { colorScheme == .dark },
                set: { _ in AppAppearance.toggle() }
            ))
            .font(.system(size: 12))
            Toggle("Show App Info, Reviews & Resources", isOn: $showExtendedInfo)
                .font(.system(size: 12))
        }
    }
}

#Preview("ShipyardSidebar") {
    ShipyardSidebar(selection: .constant(.apps), processingCount: 2, onAddTeam: {}, onDeleteTeam: { _ in }, onSelectTeam: { _ in })
        .frame(width: 260, height: 700)
}
