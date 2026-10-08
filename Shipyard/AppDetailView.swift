//
//  AppDetailView.swift
//  App Store
//
//  Per-app area from the app-info-light Figma frame: toolbar (Back, app
//  name + bundle pill) with the Builds / App Info / Reviews sub-navigation.
//  Builds includes inline TestFlight release notes per build; the other
//  tabs bring the App Store metadata editor, customer reviews, and App
//  Store Versions workspace.
//

import SwiftUI

struct AppDetailView: View {
    var app: AppsData
    @ObservedObject var sidebarVM: SideBarViewModel
    @ObservedObject var detailVM: DetailViewModel
    @ObservedObject var reviewsVM: ReviewsViewModel
    @ObservedObject var betaVM: BetaViewModel
    var onBack: () -> Void
    var onManage: (BuildsModel) -> Void

    @Binding var tab: AppTab
    @StateObject private var releaseSection = ReleaseSectionState()
    @ObservedObject private var credentialStorage = CredentialStorage.shared

    enum AppTab: String, CaseIterable {
        case builds = "Builds"
        case appInfo = "App Info"
        case reviews = "Reviews"
        case release = "App Store Versions"
    }

    private var visibleTabs: [AppTab] {
        guard let credential = credentialStorage.selectedTeam else { return AppTab.allCases }
        return AppTab.allCases.filter { item in
            switch item {
            case .builds: return credential.shows(.builds)
            case .appInfo: return credential.shows(.appInfo)
            case .reviews: return credential.shows(.reviews)
            case .release: return credential.shows(.appStoreVersions)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            subNavigation
            if visibleTabs.contains(tab) {
                switch tab {
                case .builds:
                    BuildsTableView(sidebarVM: sidebarVM, detailVM: detailVM, onManage: onManage, onBack: onBack)
                case .appInfo:
                    ShipyardAppInfoView(detailVM: detailVM, reviewsVM: reviewsVM, app: app)
                case .reviews:
                    ReviewsSectionView(reviewsVM: reviewsVM, app: app)
                case .release:
                    ReleaseTabView(app: app, detailVM: detailVM, reviewsVM: reviewsVM, section: releaseSection) {
                        tab = .appInfo
                    } onOpenBuilds: {
                        tab = .builds
                    }
                }
            } else {
                accessUnavailable
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShipyardTheme.tableBackground)
        .onAppear(perform: selectFirstVisibleTab)
        .onChange(of: credentialStorage.selectedTeam?.access) { _, _ in
            selectFirstVisibleTab()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Apps")
                        .font(.system(size: 12))
                }
                .foregroundColor(ShipyardTheme.body)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to apps")

            HStack(spacing: 8) {
                Text(app.name ?? "Unknown App")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.title)
                    .lineLimit(1)
                if let bundleId = app.bundleId {
                    Text(bundleId)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(ShipyardTheme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ShipyardTheme.accent.opacity(0.12))
                        .cornerRadius(10)
                }
            }

            Spacer()

            if tab == .release {
                ShipyardSearchField(prompt: "Search versions", text: $releaseSection.searchText)
                Menu {
                    ForEach(ReleaseStatusFilter.allCases, id: \.self) { filter in
                        Button(filter.rawValue) {
                            releaseSection.statusFilter = filter
                        }
                    }
                } label: {
                    ShipyardMenuLabel(text: "Status: \(releaseSection.statusFilter.rawValue)")
                }
                .menuStyle(.borderlessButton)
                Button("New Version") {
                    releaseSection.newVersionRequested = true
                }
                .buttonStyle(.launchPrimary)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(LaunchTheme.page)
    }

    private var subNavigation: some View {
        HStack(spacing: 16) {
            ForEach(visibleTabs, id: \.self) { item in
                Button {
                    tab = item
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 13))
                        .foregroundColor(tab == item ? ShipyardTheme.accent : ShipyardTheme.body)
                        .padding(.vertical, 4)
                        .overlay(
                            ShipyardTheme.accent.frame(height: 2)
                                .opacity(tab == item ? 1 : 0),
                            alignment: .bottom
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.rawValue)
                .accessibilityAddTraits(tab == item ? [.isButton, .isSelected] : .isButton)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(height: 36)
        .background(ShipyardTheme.tableBackground)
        .overlay(
            ShipyardTheme.rowDivider.frame(height: 1),
            alignment: .bottom
        )
    }

    private var accessUnavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 24))
                .foregroundColor(ShipyardTheme.body)
            Text("No App Features Configured")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            Text("Update this team's declared key role in Settings, or use an API key with app access.")
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectFirstVisibleTab() {
        guard !visibleTabs.contains(tab), let first = visibleTabs.first else { return }
        tab = first
    }
}
