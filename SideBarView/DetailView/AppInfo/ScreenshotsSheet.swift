import SwiftUI
import AppKit
import AVKit
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


private struct MediaSheetTarget: Identifiable { let id: String; let locale: String }

struct ScreenshotsGroupView: View {
    let title: String
    @ObservedObject var viewModel: DetailViewModel
    let state: ViewState<[AppStoreVersionLocalizationsModel]>
    let isEditable: Bool
    var primaryLocale: String?
    var platform: String?
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline.weight(.medium))
            switch state {
            case .idle, .loading: ProgressView().controlSize(.small)
            case .empty: Text("No version localizations.").foregroundStyle(.secondary)
            case .error(let message):
                Text(message).foregroundStyle(.red)
                Button("Retry", action: retry)
            case .loaded(let localizations):
                ForEach(localizations, id: \.id) { localization in
                    StoreMediaLocaleView(library: viewModel.storeMedia,
                        localizationID: localization.id, locale: localization.locale ?? "Locale",
                        primaryLocale: primaryLocale, platform: platform, isEditable: isEditable)
                }
            }
        }
    }
}

struct StoreMediaLocaleView: View {
    @ObservedObject var library: AppStoreMediaLibrary
    let localizationID: String
    let locale: String
    let primaryLocale: String?
    let platform: String?
    let isEditable: Bool
    @State private var target: MediaSheetTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(BetaLocalizationLocales.displayName(for: locale)).font(.appBody)
                Spacer()
                Button("Manage Screenshots & Videos") {
                    target = MediaSheetTarget(id: localizationID, locale: locale)
                }
                .accessibilityLabel("Manage screenshots for \(locale)")
                .accessibilityIdentifier("media.manage.\(locale)")
            }
            ForEach(StoreMediaKind.allCases, id: \.self) { kind in
                let entry = library.entry(localizationID, kind)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(kind.rawValue) · \(entry.allAssets.count)").font(.system(size: 12, weight: .medium))
                    if entry.isLoading { ProgressView().controlSize(.small) }
                    if let error = entry.error {
                        Text(error).font(.appCaption).foregroundStyle(.red)
                        Button("Retry \(kind.rawValue)") { Task { await library.refresh(localizationID: localizationID, kind: kind) } }
                    }
                    if entry.isLoaded && entry.allAssets.isEmpty {
                        Text(emptyMessage(kind)).font(.appCaption).foregroundStyle(.secondary)
                    }
                    ForEach(entry.sets) { set in
                        let assets = entry.assets[set.id] ?? []
                        if !assets.isEmpty {
                            Text("\(kind.displayName(set.displayType)) · \(assets.count)")
                                .font(.appCaption).foregroundStyle(.secondary)
                            ScrollView(.horizontal) {
                                HStack(alignment: .top, spacing: 10) {
                                    ForEach(assets) { asset in MediaAssetCard(asset: asset, compact: true) }
                                }
                            }
                            .frame(height: 150)
                        }
                    }
                }
            }
        }
        .task(id: localizationID) { await refresh() }
        .sheet(item: $target) { target in
            ScreenshotsSheet(localizationId: target.id, locale: target.locale, library: library,
                             isEditable: isEditable, platform: platform)
        }
    }

    private func refresh() async {
        for kind in StoreMediaKind.allCases {
            guard !Task.isCancelled else { return }
            await library.refresh(localizationID: localizationID, kind: kind)
        }
    }
    private func emptyMessage(_ kind: StoreMediaKind) -> String {
        if let primaryLocale, primaryLocale != locale {
            return "No \(kind.rawValue.lowercased()) uploaded for this locale. Check \(primaryLocale) for primary-locale media."
        }
        return "No \(kind.rawValue.lowercased()) uploaded."
    }
}

struct ScreenshotsSheet: View {
    let localizationId: String
    let locale: String
    @ObservedObject var library: AppStoreMediaLibrary
    var isEditable = true
    var platform: String?
    @Environment(\.dismiss) private var dismiss
    @State private var kind: StoreMediaKind = .screenshots
    @State private var displayType = ""
    @State private var importing = false
    @State private var uploadingBatch = false
    @State private var assetToDelete: StoreMediaResource?

    private var entry: AppStoreMediaLibrary.Entry { library.entry(localizationId, kind) }
    private var selectedSet: StoreMediaResource? { entry.sets.first { $0.displayType == displayType } }
    private var assets: [StoreMediaResource] { selectedSet.flatMap { entry.assets[$0.id] } ?? [] }
    private var displayTypes: [String] {
        var values = kind.displayTypes(platform: platform)
        for set in entry.sets where !values.contains(set.displayType) { values.append(set.displayType) }
        return values
    }
    private var busy: Bool { library.busy || uploadingBatch }
    private var canUpload: Bool { isEditable && !busy && !entry.isLoading && entry.error == nil && selectedSet != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Screenshots & App Previews — \(locale)").font(.title3.weight(.semibold))
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await refresh() } }
                    .disabled(busy || entry.isLoading)
                    .accessibilityIdentifier("media.refresh")
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
            }
            Picker("Media", selection: $kind) {
                ForEach(StoreMediaKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(busy)
            .accessibilityIdentifier("media.kind")
            HStack {
                Picker("Device size", selection: $displayType) {
                    ForEach(displayTypes, id: \.self) { raw in Text(kind.displayName(raw)).tag(raw) }
                }
                .disabled(busy || entry.isLoading)
                .accessibilityIdentifier("media.display-type")
                if selectedSet == nil {
                    Button("Create Set") {
                        Task { await library.createSet(localizationID: localizationId, kind: kind, displayType: displayType) }
                    }
                    .disabled(!isEditable || busy || entry.isLoading || displayType.isEmpty || entry.error != nil)
                    .accessibilityIdentifier("media.create-set")
                }
            }
            if !isEditable {
                Text("This version is read-only. You can view media; uploads and deletion require an editable version.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if kind == .previews {
                Text("Up to 3 videos per device size and locale. MOV, MP4, or M4V; 15–30 seconds; up to 500 MB.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if entry.isLoading { ProgressView("Refreshing media…").controlSize(.small) }
            if let error = entry.error { Text(error).foregroundStyle(.red).font(.callout) }
            if let error = library.actionError { Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled) }
            Text("\(kind.displayName(displayType)) · \(assets.count) \(kind == .screenshots ? "images" : "videos")")
                .font(.callout.weight(.medium))
                .accessibilityIdentifier("media.count")
            ScrollView {
                if assets.isEmpty && !entry.isLoading {
                    ContentUnavailableView(selectedSet == nil ? "No Set for This Device Size" : "No Media in This Set",
                        systemImage: kind == .screenshots ? "photo" : "video",
                        description: Text(selectedSet == nil ? "Choose an existing device size or create a set." : "Use the upload button to add media."))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 14)], alignment: .leading) {
                        ForEach(assets) { asset in
                            VStack(alignment: .leading, spacing: 6) {
                                MediaAssetCard(asset: asset)
                                if isEditable {
                                    Button("Delete", role: .destructive) { assetToDelete = asset }
                                        .disabled(busy || entry.isLoading)
                                        .accessibilityIdentifier("media.delete.\(asset.id)")
                                }
                            }
                        }
                    }
                }
            }
            HStack {
                Button(kind == .screenshots ? "Upload Image" : "Upload Video", systemImage: "square.and.arrow.up") {
                    importing = true
                }
                .disabled(!canUpload)
                .accessibilityIdentifier("media.upload")
                if let name = library.uploadingName {
                    ProgressView(value: library.progress ?? 0).frame(width: 130)
                    Text("Uploading \(name)…").font(.callout).lineLimit(1)
                }
                Spacer()
                Text("Status comes from App Store Connect. Refresh to check processing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .frame(minWidth: 720, minHeight: 540)
        .interactiveDismissDisabled(busy)
        .task(id: localizationId) {
            library.actionError = nil
            reconcileSelection()
            await refresh()
            reconcileSelection(keepCurrent: true)
        }
        .onChange(of: kind) { _, _ in library.actionError = nil; reconcileSelection() }
        .onChange(of: entry.sets.map(\.id)) { _, _ in reconcileSelection(keepCurrent: true) }
        .fileImporter(isPresented: $importing,
            allowedContentTypes: kind == .screenshots ? [.png, .jpeg] : [.quickTimeMovie, .mpeg4Movie, UTType(filenameExtension: "m4v") ?? .movie],
            allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result, let setID = selectedSet?.id else {
                    if case .failure(let error) = result { library.actionError = error.localizedDescription }
                    return
                }
                let uploadingKind = kind
                uploadingBatch = true
                Task { @MainActor in
                    defer { uploadingBatch = false }
                    for url in urls {
                        guard await library.upload(localizationID: localizationId, kind: uploadingKind, setID: setID, fileURL: url) else { return }
                    }
                }
            }
        .confirmationDialog("Delete \(assetToDelete?.attributes?.fileName ?? "media")?", isPresented: Binding(
            get: { assetToDelete != nil }, set: { if !$0 { assetToDelete = nil } }), presenting: assetToDelete) { asset in
                Button("Delete", role: .destructive) {
                    Task { await library.delete(localizationID: localizationId, kind: kind, asset: asset) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in Text("This removes the asset from App Store Connect.") }
    }

    private func refresh() async {
        for kind in StoreMediaKind.allCases {
            guard !Task.isCancelled else { return }
            await library.refresh(localizationID: localizationId, kind: kind)
        }
    }
    private func reconcileSelection(keepCurrent: Bool = false) {
        if keepCurrent, displayTypes.contains(displayType) { return }
        displayType = entry.sets.first?.displayType ?? displayTypes.first ?? ""
    }
}

private struct MediaAssetCard: View {
    let asset: StoreMediaResource
    var compact = false
    @State private var playing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(AppTheme.secondaryBackground)
                if let url = screenshotThumbnailURL(asset.thumbnail, maxDimension: compact ? 200 : 400) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFit() }
                        else if phase.error != nil { Image(systemName: "photo").foregroundStyle(.secondary) }
                        else { ProgressView().controlSize(.small) }
                    }
                } else {
                    Image(systemName: asset.type == "appPreviews" ? "video" : "photo").foregroundStyle(.secondary)
                }
                if asset.videoURL != nil {
                    Button { playing = true } label: {
                        Image(systemName: "play.circle.fill").font(.system(size: 30))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play \(asset.attributes?.fileName ?? "App Preview")")
                    .accessibilityIdentifier("media.play.\(asset.id)")
                }
            }
            .frame(height: compact ? 90 : 150)
            Text(asset.attributes?.fileName ?? asset.id).font(.caption).lineLimit(1)
                .help(asset.attributes?.fileName ?? asset.id)
            Text(asset.delivery.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(asset.delivery.state == "FAILED" ? Color.red : Color.secondary)
                .accessibilityIdentifier("media.status.\(asset.id)")
            if let details = asset.delivery.details { Text(details).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(width: compact ? 140 : nil, alignment: .leading)
        .padding(compact ? 0 : 8)
        .background(compact ? Color.clear : AppTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .sheet(isPresented: $playing) {
            if let url = asset.videoURL { MediaVideoPlayer(url: url) }
        }
    }
}

private struct MediaVideoPlayer: View {
    @State private var player: AVPlayer
    @Environment(\.dismiss) private var dismiss
    init(url: URL) { _player = State(initialValue: AVPlayer(url: url)) }
    var body: some View {
        VStack {
            HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
            VideoPlayer(player: player)
        }
        .padding()
        .frame(minWidth: 700, minHeight: 450)
        .onAppear { player.play() }
        .onDisappear { player.pause() }
    }
}
