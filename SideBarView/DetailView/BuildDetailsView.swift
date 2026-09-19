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

    var body: some View {
        VStack(spacing: 0) {
            switch viewModel.buildsState {
            case .idle:
                // No version selected yet
                if viewModel.selectedVersion == nil {
                    noVersionSelectedView
                } else {
                    Spacer()
                }
            case .loading:
                // Show full screen loading when fetching builds
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
            case .error(let message):
                ErrorRetryView(
                    title: "Couldn't Load Builds",
                    message: message,
                    retryTitle: "Retry"
                ) {
                    viewModel.retryBuilds()
                }
            case .empty:
                if viewModel.selectedVersion == nil {
                    noVersionSelectedView
                } else {
                    buildsHeader()
                    Divider()
                    noBuildsView
                }
            case .loaded:
                if viewModel.selectedVersion == nil {
                    noVersionSelectedView
                } else {
                    buildsHeader()
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
        // Surface failed release-note saves instead of silently logging them.
        .alert(
            "Couldn't Save Release Notes",
            isPresented: Binding(
                get: { viewModel.saveError != nil },
                set: { if !$0 { viewModel.saveError = nil } }
            ),
            presenting: viewModel.saveError
        ) { saveError in
            Button("Retry") {
                viewModel.saveBuildLocalization(buildId: saveError.buildId)
            }
            Button("Cancel", role: .cancel) {}
        } message: { saveError in
            Text(saveError.message)
        }
    }

    private var noVersionSelectedView: some View {
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

    private var noBuildsView: some View {
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
    }

    private func buildsHeader() -> some View {
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
                refreshBuildList?()
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.buildsState.isLoading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder private func getBuildsList() -> some View {
        if viewModel.arrBuilds.isEmpty {
            noBuildsView
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

// MARK: - Shared build display helpers
//
// Single place for upload-date formatting (absolute + relative) and build
// status. Views use these instead of inline closures so formatting stays
// consistent and testable.

enum BuildDisplayHelper {
    private static let iso8601Formatter = ISO8601DateFormatter()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static func uploadedDate(from dateString: String?) -> Date? {
        guard let dateString = dateString, !dateString.isEmpty else { return nil }
        return iso8601Formatter.date(from: dateString)
    }

    /// Single absolute date format used across build rows.
    static func formattedUploadedDate(_ dateString: String?) -> String {
        guard let date = uploadedDate(from: dateString) else { return "" }
        return displayFormatter.string(from: date)
    }

    /// Relative time ("3 days ago") shown next to the absolute date.
    static func relativeUploadedTime(_ dateString: String?) -> String? {
        guard let date = uploadedDate(from: dateString) else { return nil }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func buildStatus(processingState: String, isExpired: Bool) -> (String, Color) {
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
}

extension BuildsModel {
    var displayStatus: (String, Color) {
        BuildDisplayHelper.buildStatus(
            processingState: processingState ?? "",
            isExpired: expired ?? false
        )
    }

    var formattedUploadedDate: String {
        BuildDisplayHelper.formattedUploadedDate(uploadedDate)
    }

    var relativeUploadedTime: String? {
        BuildDisplayHelper.relativeUploadedTime(uploadedDate)
    }
}

#Preview {
    BuildDetailsView(viewModel: DetailViewModel(sidebarViewModel: SideBarViewModel()))
}
