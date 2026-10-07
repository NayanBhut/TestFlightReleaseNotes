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

/// Same template resolution as the sidebar app icons
/// ({w}x{h}bb / {w}x{h} / {w} / {h} placeholders, {f} → png).
func screenshotThumbnailURL(_ template: String?, maxDimension: Int = 400) -> URL? {
    guard var template, !template.isEmpty else { return nil }
    let size = maxDimension
    template = template.replacingOccurrences(of: "{w}x{h}bb", with: "\(size)x\(size)bb")
    template = template.replacingOccurrences(of: "{w}x{h}", with: "\(size)x\(size)")
    template = template.replacingOccurrences(of: "{w}", with: "\(size)")
    template = template.replacingOccurrences(of: "{h}", with: "\(size)")
    template = template.replacingOccurrences(of: "{f}", with: "png")
    return URL(string: template)
}

private struct ScreenshotSheetTarget: Identifiable {
    let id: String
    let locale: String
}

struct ScreenshotsGroupView: View {
    let title: String
    @ObservedObject var viewModel: DetailViewModel
    let state: ViewState<[AppStoreVersionLocalizationsModel]>
    let isEditable: Bool
    var primaryLocale: String?
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            switch state {
            case .idle, .loading:
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
            case .empty:
                Text("No version localizations.")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
            case .loaded(let localizations):
                ForEach(localizations, id: \.id) { localization in
                    localeGroup(localization)
                }
            case .error(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(.appCaption)
                        .foregroundColor(.red)
                    Button("Retry", action: retry)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .onAppear { loadPreviews() }
        .onChange(of: state.loadedValue?.map(\.id) ?? []) { _, _ in loadPreviews() }
    }

    private func loadPreviews() {
        guard let localizations = state.loadedValue else { return }
        for localization in localizations {
            viewModel.loadLocalizationScreenshotPreview(localizationId: localization.id)
        }
    }

    @ViewBuilder private func localeGroup(_ localization: AppStoreVersionLocalizationsModel) -> some View {
        let locale = localization.locale ?? "Locale"
        let fallback = fallbackLocale(for: localization)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(locale)
                    .font(.appBody)
                if let fallback {
                    StateChip(text: "USING \(fallback)")
                }
                Spacer()
                if let count = viewModel.localizationScreenshotPreviews[localization.id]?.loadedValue?.count,
                   count > 0 {
                    Text("\(count) image\(count == 1 ? "" : "s")")
                        .font(.appCaption2)
                        .foregroundColor(.secondary)
                } else if let fallback {
                    Text("\(fallbackImageCount(for: fallback) ?? 0) image\(fallbackImageCount(for: fallback) == 1 ? "" : "s") from \(fallback)")
                        .font(.appCaption2)
                        .foregroundColor(.secondary)
                }
                Button("Manage") {
                    sheetTarget = ScreenshotSheetTarget(id: localization.id, locale: locale)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Manage screenshots for \(locale)")
            }
            screenshotStrip(localization, fallback: fallback)
        }
        .sheet(item: $sheetTarget) { target in
            ScreenshotsSheet(
                localizationId: target.id,
                locale: target.locale,
                viewModel: viewModel,
                isEditable: isEditable,
                primaryLocale: primaryLocale
            )
        }
    }

    private func primaryImageCount(locale: String) -> Int? {
        guard let localization = state.loadedValue?.first(where: { $0.locale == locale }) else { return nil }
        return viewModel.localizationScreenshotPreviews[localization.id]?.loadedValue?.count
    }

    private func fallbackImageCount(for locale: String) -> Int? {
        primaryImageCount(locale: locale)
    }

    private func fallbackLocale(for localization: AppStoreVersionLocalizationsModel) -> String? {
        guard let primaryLocale,
              !primaryLocale.isEmpty,
              primaryLocale != localization.locale,
              let count = primaryImageCount(locale: primaryLocale),
              count > 0 else { return nil }
        return primaryLocale
    }

    @ViewBuilder private func screenshotStrip(_ localization: AppStoreVersionLocalizationsModel,
                                              fallback: String?) -> some View {
        switch viewModel.localizationScreenshotPreviews[localization.id] {
        case .some(.loading), .none:
            HStack {
                Spacer()
                ProgressView().controlSize(.mini)
                Spacer()
            }
        case .some(.error(let message)):
            Text(message)
                .font(.appCaption2)
                .foregroundColor(.red)
        case .some(.empty):
            fallbackMessage(for: localization, fallback: fallback)
        case .some(.loaded(let screenshots)):
            if screenshots.isEmpty {
                fallbackMessage(for: localization, fallback: fallback)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(screenshots, id: \.id) { screenshot in
                            AsyncImage(url: screenshotThumbnailURL(screenshot.imageAsset?.templateUrl, maxDimension: 200)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                case .failure:
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(AppTheme.secondaryBackground)
                                        .overlay { Image(systemName: "photo").foregroundColor(.secondary) }
                                default:
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(AppTheme.secondaryBackground)
                                        .overlay { ProgressView().controlSize(.mini) }
                                }
                            }
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .border(AppTheme.border, width: 1)
                            .help(screenshot.fileName ?? "Screenshot")
                        }
                    }
                }
                .frame(height: 104)
            }
        case .some(.idle):
            EmptyView()
        }
    }

    @ViewBuilder private func fallbackMessage(for localization: AppStoreVersionLocalizationsModel,
                                             fallback: String?) -> some View {
        let locale = localization.locale ?? "this locale"
        VStack(alignment: .leading, spacing: 4) {
            if let fallback {
                Text("No \(locale) screenshots uploaded. The App Store is using the \(fallback) screenshots for this locale.")
                    .font(.appCaption2)
                    .foregroundColor(.secondary)
                if isEditable {
                    Text("Use Manage to upload \(locale) screenshots and replace the \(fallback) images.")
                        .font(.appCaption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Text(isEditable ? "No screenshots uploaded yet." : "No screenshots uploaded.")
                    .font(.appCaption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    @State private var sheetTarget: ScreenshotSheetTarget?
}

struct ScreenshotsSheet: View {
    let localizationId: String
    let locale: String
    @ObservedObject var viewModel: DetailViewModel
    var isEditable: Bool = true
    var primaryLocale: String?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toastCenter: ShipyardToastCenter
    @State private var newSetType: ScreenshotDisplayType = .iPhone67
    @State private var creatingSet = false
    @State private var screenshotToDelete: AppScreenshotModel?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .overlay(LaunchTheme.border)
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
        .background(LaunchTheme.page)
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
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(ShipyardTheme.body)
                    .frame(width: 24, height: 24)
                    .background(LaunchTheme.field)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(LaunchTheme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(LaunchTheme.page)
    }

    // MARK: - Sets

    private var setsCard: some View {
        ScreenshotManagerCard(title: "Screenshot Sets", systemImage: "photo.stack") {
            VStack(alignment: .leading, spacing: 10) {
                if viewModel.screenshotSets.isEmpty {
                    if let primaryLocale, primaryLocale != locale {
                        Text("No sets for \(locale) — the App Store is using the \(primaryLocale) screenshots for this locale.")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                    } else {
                        Text("No sets yet — create one for a device size first.")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                    }
                } else {
                    ForEach(viewModel.screenshotSets, id: \.id) { set in
                        HStack {
                            Text(displayName(for: set))
                                .font(.system(size: 13))
                                .foregroundColor(ShipyardTheme.title)
                            Spacer()
                            if viewModel.selectedScreenshotSetId == set.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(ShipyardTheme.accent)
                                    .font(.system(size: 12, weight: .semibold))
                            } else {
                                Button {
                                    Task {
                                        await viewModel.loadScreenshots(setId: set.id)
                                    }
                                } label: {
                                    ScreenshotManagerButtonLabel("Select")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if set.id != viewModel.screenshotSets.last?.id {
                            Divider()
                                .overlay(ShipyardTheme.rowDivider)
                        }
                    }
                }
                if isEditable {
                    HStack {
                        Picker("Display type", selection: $newSetType) {
                            ForEach(ScreenshotDisplayType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.system(size: 11))
                        .tint(ShipyardTheme.body)
                        .frame(maxWidth: 200)
                        Spacer()
                        if creatingSet {
                            ProgressView().controlSize(.small)
                        } else {
                            Button {
                                creatingSet = true
                                Task {
                                    defer { creatingSet = false }
                                    switch await viewModel.createScreenshotSet(
                                        localizationId: localizationId, displayType: newSetType) {
                                    case .success:
                                        toastCenter.show("Screenshot set created", detail: newSetType.displayName, variant: .success)
                                        if let setId = viewModel.selectedScreenshotSetId {
                                            await viewModel.loadScreenshots(setId: setId)
                                        }
                                    case .failure(let message):
                                        viewModel.screenshotError = message
                                        toastCenter.show("Couldn't create screenshot set", detail: message, variant: .error)
                                    case .ignored:
                                        break
                                    }
                                }
                            } label: {
                                ScreenshotManagerButtonLabel("New Set", systemImage: "plus")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Text("Read-only: uploaded screenshots are shown, but new sets and uploads are disabled.")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
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
        ScreenshotManagerCard(title: "Screenshots", systemImage: "photo") {
            VStack(alignment: .leading, spacing: 10) {
                if viewModel.selectedScreenshotSetId == nil {
                    Text("Select a set above to view its screenshots.")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                } else if viewModel.screenshotsLoading {
                    LoadingStateView(text: "Loading screenshots…")
                } else {
                    if viewModel.screenshots.isEmpty {
                        Text("No screenshots in this set yet.")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                            ForEach(viewModel.screenshots, id: \.id) { screenshot in
                                screenshotCell(screenshot)
                            }
                        }
                    }
                    if isEditable {
                        uploadRow
                    }
                }
                if let error = viewModel.screenshotError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.danger)
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
                Task {
                    if await viewModel.deleteScreenshot(screenshot) {
                        refreshPreviewStrip()
                        toastCenter.show("Screenshot deleted", variant: .success)
                    } else if let message = viewModel.screenshotError {
                        toastCenter.show("Couldn't delete screenshot", detail: message, variant: .error)
                    }
                }
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
                    case .failure:
                        // A failed thumbnail must not sit on the spinner
                        // forever looking like a slow load.
                        RoundedRectangle(cornerRadius: 6)
                            .fill(LaunchTheme.page)
                            .frame(height: 120)
                            .overlay {
                                Image(systemName: "photo")
                                    .font(.title2)
                                    .foregroundColor(ShipyardTheme.body)
                            }
                    default:
                        RoundedRectangle(cornerRadius: 6)
                            .fill(LaunchTheme.page)
                            .frame(height: 120)
                            .overlay { ProgressView().controlSize(.small) }
                    }
                }
                .frame(maxHeight: 220)
                .cornerRadius(6)
            }
            Text(screenshot.fileName ?? "Screenshot")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.title)
                .lineLimit(1)
            HStack(spacing: 6) {
                ScreenshotStatusPill(text: (screenshot.uploaded ?? false) ? "UPLOADED" : "PENDING")
                Spacer()
                if isEditable {
                    if viewModel.deletingScreenshotIds.contains(screenshot.id) {
                        ProgressView().controlSize(.mini)
                    } else {
                        Button {
                            screenshotToDelete = screenshot
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(ShipyardTheme.danger)
                                .frame(width: 22, height: 22)
                                .background(LaunchTheme.field)
                                .cornerRadius(5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(LaunchTheme.border, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Delete screenshot")
                    }
                }
            }
        }
        .padding(8)
        .background(LaunchTheme.field)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(LaunchTheme.border, lineWidth: 1)
        )
    }

    private var uploadRow: some View {
        HStack {
            if let fileName = viewModel.uploadingFileName {
                ProgressView(value: viewModel.screenshotUploadProgress ?? 0)
                    .progressViewStyle(.linear)
                    .tint(ShipyardTheme.accent)
                    .animation(
                        .linear(duration: 0.15),
                        value: viewModel.screenshotUploadProgress
                    )
                    .frame(maxWidth: 200)
                Text("Uploading \(fileName)…")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
                    .lineLimit(1)
            } else {
                Button {
                    pickAndUpload()
                } label: {
                    ScreenshotManagerButtonLabel("Upload Image", systemImage: "square.and.arrow.up", isPrimary: true)
                }
                .buttonStyle(.plain)
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
                refreshPreviewStrip()
                toastCenter.show("Screenshot uploaded", detail: fileURL.lastPathComponent, variant: .success)
            case .failure(let message):
                viewModel.screenshotError = message
                toastCenter.show("Couldn't upload screenshot", detail: message, variant: .error)
            case .ignored:
                break
            }
        }
    }

    private func refreshPreviewStrip() {
        viewModel.localizationScreenshotPreviews[localizationId] =
            viewModel.screenshots.isEmpty ? .empty : .loaded(viewModel.screenshots)
    }

    /// Same template resolution as the sidebar app icons
    /// ({w}x{h}bb / {w}x{h} / {w} / {h} placeholders, {f} → png).
    private func thumbnailURL(_ template: String?) -> URL? {
        screenshotThumbnailURL(template)
    }
}

private struct ScreenshotManagerCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
            } icon: {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.body)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ShipyardTheme.tableBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(LaunchTheme.border, lineWidth: 1)
        )
    }
}

private struct ScreenshotManagerButtonLabel: View {
    let title: String
    var systemImage: String?
    var isPrimary = false

    init(_ title: String, systemImage: String? = nil, isPrimary: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.isPrimary = isPrimary
    }

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(isPrimary ? .white : ShipyardTheme.body)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(isPrimary ? ShipyardTheme.accent : LaunchTheme.field)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isPrimary ? ShipyardTheme.accent : LaunchTheme.border, lineWidth: 1)
        )
    }
}

private struct ScreenshotStatusPill: View {
    let text: String

    private var color: Color {
        text == "UPLOADED" ? ShipyardTheme.success : ShipyardTheme.warning
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14))
            .cornerRadius(4)
    }
}

#Preview {
    ScreenshotsSheet(localizationId: "preview", locale: "en-US", viewModel: DetailViewModel(sidebarViewModel: SideBarViewModel()))
}
