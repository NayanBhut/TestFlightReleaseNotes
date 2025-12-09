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
        VStack {
            if viewModel.currentAppState == .appVersionBuildLoading {
                SpinnerView()
            } else if viewModel.currentAppState == .appVersionLoading || viewModel.currentAppState == .appListLoading {
                EmptyView()
            } else {
                HStack {
                    Text("Builds").font(.title)
                    Text("Total Builds: \(viewModel.meta?.paging.total ?? 0)")
                    
                    Button("Refresh") {
                        viewModel.isBuildsLoaded = false
                        viewModel.nextPageCursor = nil
                        viewModel.meta = nil
                        refreshBuildList?()
                    }
                    
                    if viewModel.currentAppState == .appVersionBuildLoading {
                        SpinnerView()
                    }
                }
                
                if viewModel.selectedVersion != nil {
                    getBuildsList()
                } else {
                    Spacer().frame(height: 100)
                    Text("Please select version above to get builds")
                }
            }
            
            if viewModel.nextPageCursor != nil {
                Button("Load More") {
                    loadMoreBuild?()
                }
            }
        }
        .padding()
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
        if viewModel.isBuildsLoaded {
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
                    isUpdating: viewModel.currentAppState == .appLocalizationLoading
                )
            }
        } else {
            SpinnerView()
        }
    }
}

// Separate view to handle TextEditor state properly
struct BuildRowView: View {
    let buildId: String
    let version: String
    let uploadedDate: String
    let processingState: String
    let isExpired: Bool
    let whatsNew: String
    let localizationId: String?
    let selectedVersionString: String
    let formatDate: (String?) -> String
    let formatCustomDate: (String) -> String?
    let getBuildStatus: (String, Bool) -> (String, Color)
    let onTextChange: (String) -> Void
    let onUpdate: () -> Void
    let isUpdating: Bool
    
    @State private var whatsNewText: String = ""
    @State private var hasChanges: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(selectedVersionString)(\(version))")
                    .font(.headline)
                
                Text(formatDate(uploadedDate))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                let status = getBuildStatus(processingState, isExpired)
                Text(status.0)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(status.1.opacity(0.2))
                    .foregroundColor(status.1)
                    .cornerRadius(4)
                
                if let customDate = formatCustomDate(uploadedDate) {
                    Text(customDate)
                        .font(.caption)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                if isUpdating {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button("Update") {
                        onUpdate()
                        hasChanges = false
                    }
                    .disabled(!hasChanges || whatsNewText.isEmpty)
                }
            }
            
            TextEditor(text: $whatsNewText)
                .font(.body)
                .frame(minHeight: 100, maxHeight: 150)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(hasChanges ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: hasChanges ? 2 : 1)
                )
                .scrollContentBackground(.hidden)
                .onChange(of: whatsNewText) { newValue in
                    hasChanges = newValue != whatsNew
                    onTextChange(newValue)
                }
                .onAppear {
                    whatsNewText = whatsNew
                    hasChanges = false
                }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    BuildDetailsView(viewModel: DetailViewModel(sidebarViewModel: SideBarViewModel()))
}
