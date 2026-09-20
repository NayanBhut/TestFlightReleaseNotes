//
//  DetailView.swift
//  App Store
//
//  Created by Nayan Bhut on 04/05/24.
//

import SwiftUI

struct DetailView: View {
    @ObservedObject var viewModel: DetailViewModel
    @StateObject private var betaViewModel = BetaViewModel()
    @StateObject private var reviewsViewModel = ReviewsViewModel()
    @State private var selectedTab: DetailTab = .builds
    /// Batch C flag: one switch that shows/hides the App Info and Reviews
    /// tabs (and the sidebar's Resources section — same UserDefaults key).
    @AppStorage(UserDefaultsKeys.showExtendedInfo) private var showExtendedInfo = true

    enum DetailTab: String, CaseIterable {
        case builds = "Builds"
        case betaGroups = "Beta Groups"
        case appInfo = "App Info"
        case reviews = "Reviews"

        /// Batch C tabs — hidden when the extended-info flag is off.
        var requiresExtendedInfo: Bool {
            switch self {
            case .appInfo, .reviews: return true
            case .builds, .betaGroups: return false
            }
        }
    }

    /// The tabs the picker renders for the current flag state.
    private var visibleTabs: [DetailTab] {
        DetailTab.allCases.filter { showExtendedInfo || !$0.requiresExtendedInfo }
    }

    /// The tab actually rendered. Clamps independently of the picker's
    /// onChange clamp, which can't fire when the flag is toggled while no
    /// app is selected (the picker doesn't exist then) — otherwise a
    /// hidden tab's view could render and even fetch via onAppear.
    private var effectiveTab: DetailTab {
        visibleTabs.contains(selectedTab) ? selectedTab : .builds
    }

    init(viewModel: DetailViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Group {
            if viewModel.selectedApp != nil && viewModel.versionsState.isLoading && viewModel.arrVersions.isEmpty {
                // Full screen loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading versions...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    // Header section
                    if viewModel.selectedApp != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Versions")
                                    .font(.title2)
                                    .fontWeight(.semibold)

                                Spacer()

                                Text("\(viewModel.arrVersions.count) available")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            loadVersion()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(Color(nsColor: .controlBackgroundColor))

                        Divider()
                    }

                    getBuildList()
                }
                // Expand to the full detail area and top-align content.
                // Without this the VStack hugs its width/height, so the
                // loading/empty states inside child tabs cannot center —
                // they render top-left (a trailing Spacer here would also
                // split the space with the loader and push it off-center).
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        // Reviews VM reset lives here, not in ReviewsView: the tab view only
        // exists while its tab is selected, but a team switch can happen on
        // any tab — this handler is installed whenever DetailView is.
        .onChange(of: viewModel.selectedApp?.id) { _, newId in
            if newId == nil {
                reviewsViewModel.resetForTeamSwitch()
            }
        }
    }

    @ViewBuilder private func loadVersion() -> some View {
        switch viewModel.versionsState {
        case .idle:
            versionEmptyMessage(title: "Versions", message: "Select an app to load versions")
        case .loading:
            HStack {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Spacer()
            }
            .padding(.vertical, 8)
        case .loaded(let versions):
            if versions.isEmpty {
                versionEmptyMessage(title: "No Versions", message: "This app has no pre-release versions")
            } else {
                versionView(versions: versions)
            }
        case .empty:
            versionEmptyMessage(title: "No Versions", message: "This app has no pre-release versions")
        case .error(let message):
            HStack {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundColor(.secondary)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Spacer()
                Button("Retry") {
                    viewModel.retryVersions()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.vertical, 8)
        }
    }

    private func versionView(versions: [PreReleaseVersionsModel]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(versions, id: \.id) { version in
                    VersionChip(version: version, isSelected: version.isSelected)
                        .onTapGesture {
                            viewModel.setSelectedVersionAndGetBuilds(selectedVersion: version)
                        }
                }
                // Cursor pagination, like apps/builds: offer the next page
                // inline after the chips, with a retry on pagination failure.
                if let nextCursor = viewModel.versionsNextCursor {
                    // In-flight feedback: taps are swallowed by the pagination
                    // guard while loading, so show a spinner instead of a
                    // button that appears broken.
                    if viewModel.isLoadingMoreVersions {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 8)
                    } else if viewModel.versionsPaginationFailed {
                        Button("Couldn't load more — Retry") {
                            viewModel.loadMoreVersions(cursor: nextCursor)
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                    } else {
                        Button("Load more") {
                            viewModel.loadMoreVersions(cursor: nextCursor)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private func versionEmptyMessage(title: String, message: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder private func getBuildList() -> some View {
        if viewModel.selectedApp != nil {
            Picker("", selection: $selectedTab) {
                ForEach(visibleTabs, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Detail sections")
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            // Hiding the extended info while one of its tabs is selected
            // would leave the picker on a tag it no longer renders.
            .onChange(of: showExtendedInfo) { _, shown in
                if !shown, !visibleTabs.contains(selectedTab) {
                    selectedTab = .builds
                }
            }

            switch effectiveTab {
            case .builds:
                BuildDetailsView(
                    viewModel: viewModel,
                    refreshBuildList: {
                        guard let version = viewModel.selectedVersion else { return }
                        viewModel.setSelectedVersionAndGetBuilds(selectedVersion: version)
                    },
                    loadMoreBuild: {
                        guard let nextPage = viewModel.nextPageCursor,
                              let version = viewModel.selectedVersion else { return }
                        viewModel.setSelectedVersionAndGetBuilds(selectedVersion: version, cursor: nextPage)
                    }
                )
            case .betaGroups:
                BetaGroupView(
                    betaViewModel: betaViewModel,
                    selectedApp: viewModel.selectedApp,
                    builds: viewModel.arrBuilds,
                    selectedVersionString: viewModel.selectedVersion?.version ?? ""
                )
            case .appInfo:
                AppInfoView(
                    viewModel: viewModel,
                    selectedApp: viewModel.selectedApp
                )
            case .reviews:
                ReviewsView(
                    reviewsViewModel: reviewsViewModel,
                    selectedApp: viewModel.selectedApp
                )
            }
        } else {
            HStack {
                Spacer()
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "app.badge")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No App Selected")
                        .font(.title3)
                        .fontWeight(.medium)
                    Text("Select an app from the sidebar to view versions and builds")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                Spacer()
            }
            .padding()
        }
    }
}

#Preview {
    DetailView(viewModel: DetailViewModel(sidebarViewModel: SideBarViewModel()))
}
