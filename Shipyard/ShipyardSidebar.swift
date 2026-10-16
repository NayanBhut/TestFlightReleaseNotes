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
    /// Opens the full-screen Settings screen in the section content area.
    var onShowSettings: (() -> Void)? = nil

    @ObservedObject private var credentialStorage = CredentialStorage.shared
    @State private var showTeams = false
    @State private var showHelp = false
    @State private var pendingDeleteTeam: String?

    private var resourceSections: [ShipyardSection] {
        [.devices, .certificates, .identifiers, .bundleIDs, .profiles, .users]
    }

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
                ShipyardIcon(
                    name: section.iconName,
                    tint: isSelected ? ShipyardTheme.accent : nil
                )
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
                ShipyardIcon(
                    name: ShipyardSection.monitoring.iconName,
                    tint: isSelected ? ShipyardTheme.accent : nil
                )
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
                onShowSettings?()
            } label: {
                HStack(spacing: 6) {
                    ShipyardIcon(name: "ShipyardGear")
                    Text("Settings")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                }
            }
            .buttonStyle(.plain)

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
    @State private var topic: Topic = .usingShipyard

    private enum Topic: String, CaseIterable {
        case usingShipyard = "How to use Shipyard"
        case publishing = "Publish Your First App"
    }

    private let usageSteps: [(title: String, detail: String)] = [
        ("1. Connect or switch a team", "On the welcome screen, choose Add App Store Connect API Key. Enter a team name, Issuer ID, and Key ID, then import or paste your .p8 private key and complete validation. To add another team or switch accounts, open the team selector at the top of the sidebar."),
        ("2. Find your app", "Choose Apps in the sidebar, then open an app to see Builds, App Info, Reviews, and App Store Versions. Use search, filters, and Load More where available to find additional records. Use the back button to return to the list."),
        ("3. Update TestFlight release notes", "In Builds, choose Manage for a build and open Release Notes. Select a language, edit its What to Test text, and save that language. Use Save All to save all changed languages. Compliance and Groups let you manage the build's export compliance and beta-group assignments."),
        ("4. Edit app information, age ratings, and screenshots", "Open App Info, select a localization, edit the available fields, and choose Save Changes. Add a localization before entering translated content. Choose Edit Age Ratings for the app-wide content questionnaire and save its answers separately. In Screenshots, use Manage to upload or remove images. Editing is available only when the app information or version state allows it."),
        ("5. Prepare an App Store version", "Open App Store Versions and select a version, or choose New Version when available. Choose a processed build, complete What's New, App Review contact details, and any required sign-in information, then choose the release option. Save your changes and resolve missing requirements before choosing Submit for Review. Confirm the submission when prompted."),
        ("6. Read and reply to customer reviews", "Open Reviews within an app. Filter or search the loaded reviews, then open a review to read it and write a response. Save Draft keeps your work locally; Submit Response sends it after confirmation. Check the reply status to see whether it is waiting to publish or has been published."),
        ("7. Monitor processing builds", "Choose Processing Builds in the sidebar to check uploaded builds and their processing status. Configure polling and notifications in Settings. The menu-bar icon also shows processing builds and provides Check Now."),
        ("8. Manage team resources", "Use Devices, Certificates, Identifiers, Bundle IDs, Profiles, and Users in the sidebar to browse and manage the active team's resources. Open a row for details and use the available actions. Read confirmation dialogs before disabling, revoking, or deleting a resource."),
        ("9. Save, refresh, and resolve access issues", "Editors show a Save action when changes can be saved. Check the success or error message after saving. Use Refresh or Retry when data cannot be loaded. If an action needs broader permissions, switch to a key with the required role and app access."),
        ("10. Personalize the app and use shortcuts", "Open Settings for the startup screen, default editing locale, teams, monitoring, notifications, and release-note snippets. Press ⌘K for the command palette, ⌘R to refresh apps, and ⌘D to toggle dark mode.")
    ]

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
                    Text("Shipyard Help")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    Text("Learn how to use the app and prepare your first submission")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                }
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            ShipyardTheme.rowDivider.frame(height: 1)

            Picker("Help topic", selection: $topic) {
                ForEach(Topic.allCases, id: \.self) { topic in
                    Text(topic.rawValue).tag(topic)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Help topic")
            .padding(.horizontal, 20)
            .padding(.top, 16)

            ScrollView {
                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(topic == .usingShipyard ? "How to use Shipyard" : "Submission checklist")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(ShipyardTheme.title)

                        ForEach(Array((topic == .usingShipyard ? usageSteps : steps).enumerated()), id: \.offset) { _, step in
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
            .id(topic)
        }
        .frame(width: 760, height: 580)
        .background(ShipyardTheme.tableBackground)
    }
}

#Preview("ShipyardSidebar") {
    ShipyardSidebar(selection: .constant(.apps), processingCount: 2, onAddTeam: {}, onDeleteTeam: { _ in }, onSelectTeam: { _ in })
        .frame(width: 260, height: 700)
}
