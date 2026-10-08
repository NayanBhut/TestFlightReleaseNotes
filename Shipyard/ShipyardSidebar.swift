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
    case identifiers
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
        case .identifiers: return "Identifiers"
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
        case .identifiers: return "ShipyardBadge"
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
    @State private var showHelp = false
    @State private var pendingDeleteTeam: String?

    private var activeCredential: Credential? { credentialStorage.selectedTeam }

    private var resourceSections: [ShipyardSection] {
        var sections: [ShipyardSection] = []
        if activeCredential?.shows(.provisioningResources) ?? true {
            sections += [.devices, .certificates, .identifiers, .bundleIDs, .profiles]
        }
        if activeCredential?.shows(.users) ?? true {
            sections.append(.users)
        }
        if activeCredential?.shows(.reviews) ?? true {
            sections.append(.reviews)
        }
        return sections
    }

    var body: some View {
        VStack(spacing: 0) {
            teamSelector

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    navRow(.apps)

                    if activeCredential?.shows(.monitoring) ?? true {
                        VStack(alignment: .leading, spacing: 4) {
                            sectionHeader("MONITORING")
                            monitoringRow
                        }
                    }

                    if !resourceSections.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            sectionHeader("TEAM RESOURCES")
                            ForEach(resourceSections, id: \.self) { section in
                                navRow(section)
                            }
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
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(team)
                        .accessibilityAction(.default) {
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
            .sheet(isPresented: $showSettings) {
                ShipyardSettingsSheet(onClose: { showSettings = false })
            }

            Spacer()

            Button {
                showHelp.toggle()
            } label: {
                HStack(spacing: 6) {
                    ShipyardIcon(name: "ShipyardHelp")
                    Text("Help")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showHelp) {
                ShipyardHelpSheet(onClose: { showHelp = false })
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

private struct ShipyardHelpSheet: View {
    let onClose: () -> Void

    private let steps: [(title: String, detail: String)] = [
        ("1. Membership and access", "Join the Apple Developer Program, accept current agreements, and confirm your App Store Connect role."),
        ("2. App identity and signing", "Create the Bundle ID, enable required capabilities, and prepare distribution signing."),
        ("3. App record", "Create the App Store Connect record with the correct platform, name, Bundle ID, SKU, and primary language."),
        ("4. Build and upload", "Archive and upload from Xcode, then wait for Apple to finish processing the build."),
        ("5. Store information", "Complete metadata, privacy, age rating, pricing, availability, screenshots, and every enabled locale."),
        ("6. Review and submit", "Add review contact details and demo credentials, answer compliance questions, choose a build, and submit.")
    ]

    private let links: [(title: String, url: String)] = [
        ("Apple Developer Program", "https://developer.apple.com/help/account/membership/programs-overview"),
        ("Create an app record", "https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/"),
        ("Upload builds", "https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/"),
        ("Required metadata", "https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties/"),
        ("App privacy", "https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy"),
        ("Screenshots and previews", "https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/"),
        ("Submit for review", "https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/"),
        ("App Review Guidelines", "https://developer.apple.com/app-store/review/guidelines/"),
        ("App Store Connect API", "https://developer.apple.com/documentation/appstoreconnectapi")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Publish Your First App")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    Text("A practical checklist from account setup to App Review")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                }
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            ShipyardTheme.rowDivider.frame(height: 1)

            ScrollView {
                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Submission checklist")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(ShipyardTheme.title)

                        ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(ShipyardTheme.title)
                                Text(step.detail)
                                    .font(.system(size: 11))
                                    .foregroundColor(ShipyardTheme.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Text("Shipyard manages App Store Connect data and developer resources. Use Xcode or Transporter to build, sign, archive, and upload the binary.")
                            .font(.system(size: 11))
                            .foregroundColor(ShipyardTheme.body)
                            .padding(12)
                            .background(ShipyardTheme.infoSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Official Apple help")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(ShipyardTheme.title)

                        ForEach(Array(links.enumerated()), id: \.offset) { _, item in
                            if let destination = URL(string: item.url) {
                                Link(destination: destination) {
                                    HStack(spacing: 6) {
                                        Text(item.title)
                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 9, weight: .semibold))
                                    }
                                    .font(.system(size: 11))
                                    .foregroundColor(ShipyardTheme.accent)
                                }
                                .accessibilityHint("Opens Apple Developer documentation")
                            }
                        }
                    }
                    .frame(width: 220, alignment: .leading)
                }
                .padding(20)
            }
        }
        .frame(width: 760, height: 580)
        .background(ShipyardTheme.tableBackground)
    }
}

#Preview("ShipyardSidebar") {
    ShipyardSidebar(selection: .constant(.apps), processingCount: 2, onAddTeam: {}, onDeleteTeam: { _ in }, onSelectTeam: { _ in })
        .frame(width: 260, height: 700)
}
