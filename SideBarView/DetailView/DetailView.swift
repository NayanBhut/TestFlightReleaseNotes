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
    @State private var selectedTab: DetailTab = .builds

    enum DetailTab: String, CaseIterable {
        case builds = "Builds"
        case betaGroups = "Beta Groups"
    }

    init(viewModel: DetailViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Group {
            if viewModel.selectedApp != nil && viewModel.versionsState.isLoading && viewModel.arrVersions.isEmpty {
                // Full screen loading state
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading versions...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
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
                    Spacer()
                }
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
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Detail sections")
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            switch selectedTab {
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
            }
        } else {
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
            .padding()
        }
    }
}

#Preview {
    DetailView(viewModel: DetailViewModel(sidebarViewModel: SideBarViewModel()))
}
