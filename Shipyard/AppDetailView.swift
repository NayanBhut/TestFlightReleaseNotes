//
//  AppDetailView.swift
//  App Store
//
//  Per-app area from the app-info-light Figma frame: toolbar (Back, app
//  name + bundle pill) with the Builds / TestFlight / App Info / Reviews
//  sub-navigation. Each tab brings its own content: the builds table, the
//  TestFlight release-notes browser for a picked version + build, the App
//  Store metadata editor, and the app's customer reviews.
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

    enum AppTab: String, CaseIterable {
        case builds = "Builds"
        case testflight = "TestFlight"
        case appInfo = "App Info"
        case reviews = "Reviews"
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            subNavigation
            switch tab {
            case .builds:
                BuildsTableView(sidebarVM: sidebarVM, detailVM: detailVM, onManage: onManage, onBack: onBack)
            case .testflight:
                TestFlightTabView(detailVM: detailVM)
            case .appInfo:
                ShipyardAppInfoView(detailVM: detailVM, reviewsVM: reviewsVM, app: app)
            case .reviews:
                ReviewsSectionView(reviewsVM: reviewsVM, apps: [], selectedApp: .constant(app), fixedApp: app)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShipyardTheme.tableBackground)
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
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(LaunchTheme.page)
    }

    private var subNavigation: some View {
        HStack(spacing: 16) {
            ForEach(AppTab.allCases, id: \.self) { item in
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
}

/// TestFlight tab: version + build pickers over the per-build release
/// notes browser (same component as the build-detail tab).
private struct TestFlightTabView: View {
    @ObservedObject var detailVM: DetailViewModel
    @State private var buildId: String?

    private var effectiveBuildId: String? {
        if let buildId, detailVM.arrBuilds.contains(where: { $0.id == buildId }) {
            return buildId
        }
        return detailVM.arrBuilds.first?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Menu {
                    ForEach(detailVM.arrVersions, id: \.id) { version in
                        Button("v\(version.version ?? "")") {
                            detailVM.setSelectedVersionAndGetBuilds(selectedVersion: version)
                        }
                    }
                } label: {
                    ShipyardMenuLabel(text: "Version: \(detailVM.selectedVersion?.version ?? "—")")
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Select version")

                Menu {
                    ForEach(detailVM.arrBuilds, id: \.id) { build in
                        Button("Build \(build.version ?? "")") {
                            buildId = build.id
                        }
                    }
                } label: {
                    ShipyardMenuLabel(text: "Build: \(selectedBuildNumber ?? "—")")
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Select build")

                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(LaunchTheme.page)
            Divider()

            if let effectiveBuildId {
                ReleaseNotesView(detailVM: detailVM, buildId: effectiveBuildId)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Text("No Builds")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    Text("Pick a version with builds to edit TestFlight notes")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.body)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: detailVM.selectedVersion?.id) { _, _ in
            buildId = nil
        }
    }

    private var selectedBuildNumber: String? {
        effectiveBuildId.flatMap { id in detailVM.arrBuilds.first(where: { $0.id == id })?.version }
    }
}
