//
//  ShipyardShell.swift
//  App Store
//
//  Post-auth application shell: the Figma 260pt sidebar beside the section
//  content. Owns the shared view models (sidebar/detail for apps +
//  versions + builds, resources, reviews) and the team lifecycle that
//  SideBarView used to own (restore/load on appear, refresh on team
//  switch, reset on logout).
//

import SwiftUI

struct ShipyardShell: View {
    @ObservedObject var sidebarVM: SideBarViewModel
    @ObservedObject var detailVM: DetailViewModel
    @ObservedObject var monitor: BuildProcessingMonitor
    var onAddTeam: () -> Void

    @StateObject private var resourcesVM = ResourcesViewModel()
    @StateObject private var reviewsVM = ReviewsViewModel()
    @StateObject private var betaVM = BetaViewModel()
    @StateObject private var toastCenter = ShipyardToastCenter()
    @ObservedObject private var credentialStorage = CredentialStorage.shared

    /// Launch section honors the General settings default (Figma 3-4361).
    @State private var section: ShipyardSection = ShipyardSection(
        rawValue: UserDefaults.standard.string(forKey: UserDefaultsKeys.defaultStartupView) ?? "apps"
    ) ?? .apps
    /// Per-app area (Figma sub-nav). Set by app tap; Back clears it.
    @State private var detailApp: AppsData?
    @State private var detailTab: AppDetailView.AppTab = .builds
    /// Full-screen build detail (Figma build-detail screen). Set by Manage;
    /// Back clears it to return to the builds table.
    @State private var detailBuild: BuildsModel?
    @State private var activeTeamKey: String?
    /// Full-screen Settings screen (not a modal sheet). Sidebar Settings
    /// swaps the section content while keeping navigation chrome.
    @State private var settingsPresented = false

    var body: some View {
        HStack(spacing: 0) {
            ShipyardSidebar(
                selection: $section,
                processingCount: monitor.processingBuilds.count,
                onAddTeam: onAddTeam,
                onDeleteTeam: deleteTeam,
                onSelectTeam: selectTeam,
                onShowSettings: { settingsPresented = true }
            )
            .frame(width: 260)

            ShipyardTheme.rowDivider
                .frame(width: 1)

            sectionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // One toast overlay for the whole app: any section posts a
                // write result and it surfaces here, bottom-trailing.
                .shipyardToast(toastCenter.current, center: toastCenter)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LaunchTheme.page)
        .environmentObject(toastCenter)
        .onAppear {
            if CredentialStorage.shared.selectedTeam == nil {
                CredentialStorage.shared.restoreDefaultTeam()
            }
            activeTeamKey = CredentialStorage.shared.selectedTeam?.key
            refreshForActiveTeam(resetNavigation: false)
        }
        // Sidebar navigation always leaves app/build detail: the detail
        // screens take precedence over the section, so a section change
        // must clear them or taps would appear to do nothing.
        .onChange(of: section) { _, _ in
            detailApp = nil
            detailBuild = nil
            settingsPresented = false
        }
        .onChange(of: sidebarVM.isTeamChanged) { _, changed in
            if changed {
                refreshForActiveTeam(resetNavigation: true)
                sidebarVM.isTeamChanged = false
            }
        }
        .onChange(of: credentialStorage.selectedTeam?.key) { _, newKey in
            guard activeTeamKey != newKey else { return }
            activeTeamKey = newKey
            refreshForActiveTeam(resetNavigation: true)
        }
        .onChange(of: credentialStorage.selectedTeam?.access) { _, _ in
            guard isSectionVisible(section) else {
                clearDetail()
                section = .apps
                return
            }
        }
        // App tap lands on the builds list (Figma builds-list): auto-select
        // the newest version once versions arrive. Guarded by nil so user
        // picks and pagination appends never retrigger it.
        .onChange(of: detailVM.arrVersions) { _, versions in
            if detailVM.selectedVersion == nil, let first = versions.first {
                detailVM.setSelectedVersionAndGetBuilds(selectedVersion: first)
            }
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        if settingsPresented {
            ShipyardSettingsSheet(onClose: { settingsPresented = false })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let detailBuild {
            BuildDetailView(
                build: detailBuild,
                detailVM: detailVM,
                betaVM: betaVM,
                app: detailVM.selectedApp ?? sidebarVM.selectedApp,
                onBack: { self.detailBuild = nil }
            )
        } else if let detailApp {
            AppDetailView(
                app: detailApp,
                sidebarVM: sidebarVM,
                detailVM: detailVM,
                reviewsVM: reviewsVM,
                betaVM: betaVM,
                onBack: {
                    self.detailApp = nil
                    section = .apps
                },
                onManage: { build in
                    self.detailBuild = build
                },
                tab: $detailTab
            )
        } else {
            switch section {
            case .apps:
                AppsTableView(sidebarVM: sidebarVM) { app in
                    sidebarVM.setSelectedAppAndGetVersions(app: app)
                    detailTab = .builds
                    detailApp = app
                }
            case .builds:
                BuildsTableView(
                    sidebarVM: sidebarVM,
                    detailVM: detailVM,
                    onManage: { build in
                        detailBuild = build
                    },
                    onBack: { section = .apps }
                )
            case .monitoring:
                MonitoringView(
                    monitor: monitor,
                    resourcesVM: resourcesVM,
                    onOpenBuilds: { section = .builds },
                    onOpenApps: { section = .apps },
                    onOpenCertificate: { query in
                        resourcesVM.searchTexts[.certificates] = query
                        section = .certificates
                    },
                    onOpenProfile: { query in
                        resourcesVM.searchTexts[.profiles] = query
                        section = .profiles
                    }
                )
            case .devices:
                DevicesView(
                    viewModel: resourcesVM,
                    fixedSize: false,
                    onOpenProfile: { profile in
                        // Figma "Open Profile →": land on the Profiles
                        // section filtered to that profile.
                        resourcesVM.searchTexts[.profiles] = profile.name ?? ""
                        section = .profiles
                    },
                    onOpenProfilesList: {
                        resourcesVM.searchTexts[.profiles] = nil
                        section = .profiles
                    }
                )
            case .certificates:
                CertificatesTableView(viewModel: resourcesVM)
            case .identifiers:
                IdentifiersTableView(viewModel: resourcesVM)
            case .bundleIDs:
                BundleIDsTableView(
                    viewModel: resourcesVM,
                    onOpenApp: { name in
                        // Figma "Open App →" from the blocked-delete
                        // dependency table: land on Apps filtered to it.
                        sidebarVM.searchText = name
                        section = .apps
                    },
                    onOpenProfile: { query in
                        resourcesVM.searchTexts[.profiles] = query
                        section = .profiles
                    }
                )
            case .profiles:
                ProfilesTableView(
                    viewModel: resourcesVM,
                    onOpenCertificate: { query in
                        resourcesVM.searchTexts[.certificates] = query
                        section = .certificates
                    },
                    onOpenBundleId: { query in
                        resourcesVM.searchTexts[.bundleIds] = query
                        section = .bundleIDs
                    },
                    onOpenDevice: { query in
                        resourcesVM.searchTexts[.devices] = query
                        section = .devices
                    })
            case .users:
                UsersTableView(viewModel: resourcesVM, apps: loadedApps)
            }
        }
    }

    private var loadedApps: [AppsData] {
        sidebarVM.appsState.loadedValue ?? []
    }

    private func isSectionVisible(_ section: ShipyardSection) -> Bool {
        guard let credential = credentialStorage.selectedTeam else { return true }
        switch section {
        case .apps: return true
        case .builds: return credential.shows(.builds)
        case .monitoring: return credential.shows(.monitoring)
        case .devices, .certificates, .identifiers, .bundleIDs, .profiles:
            return credential.shows(.provisioningResources)
        case .users: return credential.shows(.users)
        }
    }

    /// Switches the active team: the keychain write alone refreshes
    /// nothing — the isTeamChanged flag drives updateTeam via onChange,
    /// and the section resets so stale builds/resources never show.
    private func selectTeam(_ team: String) {
        guard CredentialStorage.shared.selectedTeam?.key != team else { return }
        CredentialStorage.shared.changeTeam = team
    }

    /// Removes a team: wipes everything on logout (last team), or resets
    /// onto the restored team when the active one was deleted. Ported from
    /// the old sidebar — ContentView flips to FirstLaunch when empty.
    private func deleteTeam(_ team: String) {
        let wasSelected = CredentialStorage.shared.selectedTeam?.key == team
        CredentialStorage.shared.deleteCredential(for: team)
        clearDetail()
        if credentialStorage.teams.isEmpty {
            sidebarVM.clearOnLogout()
            detailVM.resetForTeamSwitch()
            resourcesVM.resetForTeamSwitch()
            reviewsVM.resetForTeamSwitch()
        } else if wasSelected {
            CredentialStorage.shared.restoreDefaultTeam()
            activeTeamKey = CredentialStorage.shared.selectedTeam?.key
            refreshForActiveTeam(resetNavigation: true)
        }
    }

    private func refreshForActiveTeam(resetNavigation: Bool) {
        if resetNavigation {
            section = .apps
            clearDetail()
            settingsPresented = false
            detailTab = .builds
        }
        detailVM.resetForTeamSwitch()
        resourcesVM.resetForTeamSwitch()
        reviewsVM.resetForTeamSwitch()
        toastCenter.dismiss()
        sidebarVM.updateTeam()
    }

    /// Team lifecycle reset: detail screens take precedence over section,
    /// so leaving them set would keep rendering the old team's app/build
    /// (including its notes editor) after a switch or delete.
    private func clearDetail() {
        detailApp = nil
        detailBuild = nil
    }
}

/// Reviews are app-scoped, so the screen lives only inside App Detail.
struct ReviewsSectionView: View {
    @ObservedObject var reviewsVM: ReviewsViewModel
    var app: AppsData

    var body: some View {
        ReviewsView(reviewsViewModel: reviewsVM, selectedApp: app)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                reviewsVM.load(app: app)
            }
            .onChange(of: app.id) { _, _ in
                reviewsVM.load(app: app)
            }
    }
}
