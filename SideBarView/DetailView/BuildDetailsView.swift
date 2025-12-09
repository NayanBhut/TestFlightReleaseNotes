//
//  BuildDetailsView.swift
//  App Store
//
//  Created by Nayan Bhut on 05/05/24.
//

import SwiftUI

struct BuildDetailsView: View {
    @ObservedObject var viewModel: DetailViewModel
    
    var getBuidsData: ((String) -> Void)?
    var setBuidsData: ((String, String, String) -> Void)?
    var refreshBuildList: (() -> Void)?
    var loadMoreBuild: (() -> Void)?
    
    private static let iso8601Formatter = ISO8601DateFormatter()
    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()
    
    private static let customFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter
    }()
    
    private static let customDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM HH:mm"
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: 0) {
            // Show full screen loading when fetching builds
            if !viewModel.isBuildsLoaded && viewModel.currentAppState == .appVersionBuildLoading {
                HStack {
                    Spacer()
                    VStack(spacing: 16) {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading builds...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    Spacer()
                }
            }
            // Show message when no version is selected
            else if viewModel.selectedVersion == nil {
                HStack {
                    Spacer()
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "cube.box")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Version Selected")
                            .font(.title3)
                            .fontWeight(.medium)
                        Text("Select a version above to view its builds")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding()
                    Spacer()
                }
            }
            // Show builds list
            else {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Builds")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        if let total = viewModel.meta?.paging.total {
                            Text("\(total) total")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Button(action: {
                            viewModel.isBuildsLoaded = false
                            viewModel.nextPageCursor = nil
                            viewModel.meta = nil
                            refreshBuildList?()
                        }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color(nsColor: .controlBackgroundColor))
                    
                    Divider()
                    
                    // Builds list
                    getBuildsList()
                    
                    // Load more button
                    if viewModel.nextPageCursor != nil {
                        VStack {
                            Divider()
                            Button("Load More Builds") {
                                loadMoreBuild?()
                            }
                            .buttonStyle(.bordered)
                            .padding(.vertical, 12)
                        }
                    }
                }
            }
        }
    }
    
    private func formatDate(_ dateString: String?) -> String {
        guard let dateString = dateString,
              let date = Self.iso8601Formatter.date(from: dateString) else {
            return ""
        }
        return Self.displayFormatter.string(from: date)
    }
    
    private func formatCustomDate(_ dateString: String) -> String? {
        guard let date = Self.customFormatter.date(from: dateString) else {
            return nil
        }
        return Self.customDisplayFormatter.string(from: date)
    }
    
    private func getBuildStatus(processingState: String, isExpired: Bool) -> (String, Color) {
        if isExpired {
            return ("EXPIRED", .red)
        }
        
        switch processingState {
        case "PROCESSING":
            return ("PROCESSING", .yellow)
        case "FAILED":
            return ("FAILED", .red)
        case "INVALID":
            return ("INVALID", .orange)
        case "VALID":
            return ("VALID", .green)
        default:
            return ("", .clear)
        }
    }
    
    @ViewBuilder private func getBuildsList() -> some View {
        if viewModel.arrBuilds.isEmpty {
            // Empty state
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "tray")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("No Builds Available")
                    .font(.title3)
                    .fontWeight(.medium)
                Text("This version doesn't have any builds yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding()
        } else {
            List(viewModel.arrBuilds, id: \.id) { build in
                BuildRowView(
                    buildId: build.id,
                    version: build.version ?? "",
                    uploadedDate: build.uploadedDate ?? "",
                    processingState: build.processingState ?? "",
                    isExpired: build.expired ?? false,
                    whatsNew: build.betaBuildLocalizations.first?.whatsNew ?? "",
                    localizationId: build.betaBuildLocalizations.first?.id,
                    selectedVersionString: viewModel.selectedVersion?.version ?? "",
                    formatDate: formatDate,
                    formatCustomDate: formatCustomDate,
                    getBuildStatus: getBuildStatus,
                    onTextChange: { newText in
                        viewModel.updateBuildWhatsNew(buildId: build.id, whatsNew: newText)
                    },
                    onUpdate: {
                        viewModel.saveBuildLocalization(buildId: build.id)
                    },
                    isUpdating: viewModel.isBuildUpdating(build.id)
                )
            }
        }
    }
}

#Preview {
    BuildDetailsView(viewModel: DetailViewModel(sidebarViewModel: SideBarViewModel()))
}
