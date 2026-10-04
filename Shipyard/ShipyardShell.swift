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
    @ObservedObject private var credentialStorage = CredentialStorage.shared

    @State private var section: ShipyardSection = .apps
    /// Per-app area (Figma sub-nav). Set by app tap; Back clears it.
    @State private var detailApp: AppsData?
    @State private var detailTab: AppDetailView.AppTab = .builds
    /// Full-screen build detail (Figma build-detail screen). Set by Manage;
    /// Back clears it to return to the builds table.
    @State private var detailBuild: BuildsModel?
    @State private var reviewApp: AppsData?

    var body: some View {
        HStack(spacing: 0) {
            ShipyardSidebar(
                selection: $section,
                processingCount: monitor.processingBuilds.count,
                onAddTeam: onAddTeam,
                onDeleteTeam: deleteTeam,
                onSelectTeam: selectTeam
            )
            .frame(width: 260)

            ShipyardTheme.rowDivider
                .frame(width: 1)

            sectionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LaunchTheme.page)
        .onAppear {
            if CredentialStorage.shared.selectedTeam == nil {
                CredentialStorage.shared.restoreDefaultTeam()
            }
            sidebarVM.getiOSApps()
        }
        // Sidebar navigation always leaves app/build detail: the detail
        // screens take precedence over the section, so a section change
        // must clear them or taps would appear to do nothing.
        .onChange(of: section) { _, _ in
            detailApp = nil
            detailBuild = nil
        }
        .onChange(of: sidebarVM.isTeamChanged) { _, changed in
            if changed {
                sidebarVM.updateTeam()
                resourcesVM.resetForTeamSwitch()
                reviewsVM.resetForTeamSwitch()
                sidebarVM.isTeamChanged = false
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
        if let detailBuild {
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
                MonitoringView(monitor: monitor)
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
            case .bundleIDs:
                BundleIDsTableView(viewModel: resourcesVM)
            case .profiles:
                ProfilesTableView(viewModel: resourcesVM)
            case .users:
                UsersTableView(viewModel: resourcesVM, apps: loadedApps)
            case .reviews:
                ReviewsSectionView(reviewsVM: reviewsVM, apps: loadedApps, selectedApp: $reviewApp)
            }
        }
    }

    private var loadedApps: [AppsData] {
        sidebarVM.appsState.loadedValue ?? []
    }

    /// Switches the active team: the keychain write alone refreshes
    /// nothing — the isTeamChanged flag drives updateTeam via onChange,
    /// and the section resets so stale builds/resources never show.
    private func selectTeam(_ team: String) {
        CredentialStorage.shared.changeTeam = team
        sidebarVM.isTeamChanged = true
        section = .apps
    }

    /// Removes a team: wipes everything on logout (last team), or resets
    /// onto the restored team when the active one was deleted. Ported from
    /// the old sidebar — ContentView flips to FirstLaunch when empty.
    private func deleteTeam(_ team: String) {
        let wasSelected = CredentialStorage.shared.selectedTeam?.key == team
        CredentialStorage.shared.deleteCredential(for: team)
        if credentialStorage.teams.isEmpty {
            sidebarVM.clearOnLogout()
            resourcesVM.resetForTeamSwitch()
            reviewsVM.resetForTeamSwitch()
        } else if wasSelected {
            CredentialStorage.shared.restoreDefaultTeam()
            sidebarVM.updateTeam()
            resourcesVM.resetForTeamSwitch()
            reviewsVM.resetForTeamSwitch()
        }
    }
}

/// Reviews needs an app context (Figma shows per-app "Orbit Reviews"):
/// app picker over the existing ReviewsView, or a fixed app inside the
/// app detail (picker hidden, loads directly). Internal so AppDetailView
/// reuses it.
struct ReviewsSectionView: View {
    @ObservedObject var reviewsVM: ReviewsViewModel
    var apps: [AppsData]
    @Binding var selectedApp: AppsData?
    var fixedApp: AppsData? = nil

    var body: some View {
        VStack(spacing: 0) {
            if fixedApp == nil {
                HStack(spacing: 12) {
                    Text("\(selectedApp?.name ?? "Reviews")")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    Menu {
                        ForEach(apps, id: \.id) { app in
                            Button(app.name ?? "Unknown App") {
                                selectedApp = app
                                reviewsVM.load(app: app)
                            }
                        }
                    } label: {
                        ShipyardMenuLabel(text: selectedApp?.name ?? "Select App")
                    }
                    .menuStyle(.borderlessButton)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(LaunchTheme.page)
                Divider()
            }
            ReviewsView(reviewsViewModel: reviewsVM, selectedApp: fixedApp ?? selectedApp)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if let fixedApp {
                selectedApp = fixedApp
                reviewsVM.load(app: fixedApp)
            } else if selectedApp == nil, let first = apps.first {
                selectedApp = first
                reviewsVM.load(app: first)
            }
        }
    }
}
