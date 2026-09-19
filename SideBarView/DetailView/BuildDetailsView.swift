//
//  BuildDetailsView.swift
//  App Store
//
//  Created by Nayan Bhut on 05/05/24.
//

import SwiftUI
import AppKit

struct BuildDetailsView: View {
    @ObservedObject var viewModel: DetailViewModel
    @StateObject private var exportManager = ExportManager()
    @State private var showExportMenu = false
    @State private var exportURL: URL?
    @State private var showExportSheet = false
    
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
            } else if viewModel.selectedVersion == nil {
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
            } else {
                VStack(spacing: 0) {
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
                    
                    getBuildsList()
                    
                    if viewModel.nextPageCursor != nil {
                        VStack {
                            Divider()
                            ProgressView()
                                .scaleEffect(0.8)
                                .onAppear {
                                    Task {
                                        await viewModel.loadMoreBuilds(cursor: viewModel.nextPageCursor!)
                                    }
                                }
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
