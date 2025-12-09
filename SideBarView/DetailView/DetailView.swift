//
//  DetailView.swift
//  App Store
//
//  Created by Nayan Bhut on 04/05/24.
//

import SwiftUI

struct DetailView: View {
    @ObservedObject var viewModel: DetailViewModel
    
    init(viewModel: DetailViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        Group {
            if viewModel.selectedApp != nil && viewModel.arrVersions.isEmpty && (viewModel.currentAppState == .appVersionLoading) {
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
        if viewModel.currentAppState == .appVersionLoading || viewModel.currentAppState == .appListLoading {
            HStack {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Spacer()
            }
            .padding(.vertical, 8)
        } else {
            versionView()
        }
    }
    
    private func versionView() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.arrVersions, id: \.id) { version in
                    VersionChip(version: version, isSelected: version.isSelected)
                        .onTapGesture {
                            viewModel.setSelectedVersionAndGetBuilds(selectedVersion: version)
                        }
                }
            }
        }
    }
    
    @ViewBuilder private func getBuildList() -> some View {
        if viewModel.selectedApp != nil {
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
