//
//  ScreenshotsSheet.swift
//  App Store
//
//  Batch J (F4): App Store screenshot manager for one version
//  localization. Sets are listed/created per localization; images are
//  uploaded through Apple's reserve → PUT operations → complete pipeline
//  (see DetailViewModel.uploadScreenshot).
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ScreenshotsSheet: View {
    let localizationId: String
    let locale: String
    @ObservedObject var viewModel: DetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newSetType: ScreenshotDisplayType = .iPhone67
    @State private var creatingSet = false
    @State private var screenshotToDelete: AppScreenshotModel?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.screenshotSetsLoading {
                LoadingStateView(text: "Loading screenshot sets…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        setsCard
                        screenshotsCard
                    }
                    .padding(20)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear {
            Task {
                await viewModel.loadScreenshotSets(localizationId: localizationId)
                if let setId = viewModel.selectedScreenshotSetId {
                    await viewModel.loadScreenshots(setId: setId)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Screenshots — \(locale)")
                .font(.title3)
                .fontWeight(.semibold)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .clipShape(Circle())
            .help("Close (Esc)")
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Sets

    private var setsCard: some View {
        InfoCard(title: "Screenshot Sets", systemImage: "photo.stack") {
            VStack(alignment: .leading, spacing: 10) {
                if viewModel.screenshotSets.isEmpty {
                    Text("No sets yet — create one for a device size first.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.screenshotSets, id: \.id) { set in
                        HStack {
                            Text(displayName(for: set))
                                .font(.subheadline)
                            Spacer()
                            if viewModel.selectedScreenshotSetId == set.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                                    .font(.caption)
                            } else {
                                Button("Select") {
                                    Task {
                                        await viewModel.loadScreenshots(setId: set.id)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        if set.id != viewModel.screenshotSets.last?.id { Divider() }
                    }
                }
                HStack {
                    Picker("Display type", selection: $newSetType) {
                        ForEach(ScreenshotDisplayType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                    Spacer()
                    if creatingSet {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("New Set") {
                            creatingSet = true
                            Task {
                                defer { creatingSet = false }
                                switch await viewModel.createScreenshotSet(
                                    localizationId: localizationId, displayType: newSetType) {
                                case .success:
                                    if let setId = viewModel.selectedScreenshotSetId {
                                        await viewModel.loadScreenshots(setId: setId)
                                    }
                                case .failure(let message):
                                    viewModel.screenshotError = message
                                case .ignored:
                                    break
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private func displayName(for set: AppScreenshotSetModel) -> String {
        if let raw = set.screenshotDisplayType,
           let type = ScreenshotDisplayType(rawValue: raw) {
            return type.displayName
        }
        return set.screenshotDisplayType ?? "Set"
    }

    // MARK: - Screenshots

    private var screenshotsCard: some View {
        InfoCard(title: "Screenshots", systemImage: "photo") {
            VStack(alignment: .leading, spacing: 10) {
                if viewModel.selectedScreenshotSetId == nil {
                    Text("Select a set above to view its screenshots.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if viewModel.screenshotsLoading {
                    LoadingStateView(text: "Loading screenshots…")
                } else {
                    if viewModel.screenshots.isEmpty {
                        Text("No screenshots in this set yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                            ForEach(viewModel.screenshots, id: \.id) { screenshot in
                                screenshotCell(screenshot)
                            }
                        }
                    }
                    uploadRow
                }
                if let error = viewModel.screenshotError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .confirmationDialog(
            "Delete Screenshot?",
            isPresented: Binding(
                get: { screenshotToDelete != nil },
                set: { if !$0 { screenshotToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: screenshotToDelete
        ) { screenshot in
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteScreenshot(screenshot) }
            }
        } message: { _ in
            Text("The screenshot is removed from App Store Connect.")
        }
    }

    @ViewBuilder private func screenshotCell(_ screenshot: AppScreenshotModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let url = thumbnailURL(screenshot.imageAsset?.templateUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    default:
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .frame(height: 120)
                            .overlay { ProgressView().controlSize(.small) }
                    }
                }
                .frame(maxHeight: 220)
                .cornerRadius(6)
            }
            Text(screenshot.fileName ?? "Screenshot")
                .font(.caption2)
                .lineLimit(1)
            HStack(spacing: 6) {
                StateChip(text: (screenshot.uploaded ?? false) ? "UPLOADED" : "PENDING")
                Spacer()
                if viewModel.deletingScreenshotIds.contains(screenshot.id) {
                    ProgressView().controlSize(.mini)
                } else {
                    Button {
                        screenshotToDelete = screenshot
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete screenshot")
                }
            }
        }
    }

    private var uploadRow: some View {
        HStack {
            if let fileName = viewModel.uploadingFileName {
                ProgressView(value: viewModel.screenshotUploadProgress ?? 0)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 200)
                Text("Uploading \(fileName)…")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                Button {
                    pickAndUpload()
                } label: {
                    Label("Upload Image", systemImage: "square.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.selectedScreenshotSetId == nil)
            }
        }
    }

    private func pickAndUpload() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg]
        panel.prompt = "Upload"
        guard panel.runModal() == .OK, let fileURL = panel.url,
              let setId = viewModel.selectedScreenshotSetId else { return }
        Task {
            switch await viewModel.uploadScreenshot(setId: setId, fileURL: fileURL) {
            case .success:
                break
            case .failure(let message):
                viewModel.screenshotError = message
            case .ignored:
                break
            }
        }
    }

    /// Same template resolution as the sidebar app icons
    /// ({w}x{h}bb / {w}x{h} / {w} / {h} placeholders, {f} → png).
    private func thumbnailURL(_ template: String?) -> URL? {
        guard var template, !template.isEmpty else { return nil }
        let size = 400
        template = template.replacingOccurrences(of: "{w}x{h}bb", with: "\(size)x\(size)bb")
        template = template.replacingOccurrences(of: "{w}x{h}", with: "\(size)x\(size)")
        template = template.replacingOccurrences(of: "{w}", with: "\(size)")
        template = template.replacingOccurrences(of: "{h}", with: "\(size)")
        template = template.replacingOccurrences(of: "{f}", with: "png")
        return URL(string: template)
    }
}

#Preview {
    ScreenshotsSheet(localizationId: "preview", locale: "en-US", viewModel: DetailViewModel(sidebarViewModel: SideBarViewModel()))
}
