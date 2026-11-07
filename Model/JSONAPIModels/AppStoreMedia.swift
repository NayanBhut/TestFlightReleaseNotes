import AVFoundation
import Combine
import CryptoKit
import Foundation
import UniformTypeIdentifiers

enum StoreMediaKind: String, CaseIterable, Hashable {
    case screenshots = "Screenshots"
    case previews = "App Previews"

    var setsName: APIName { self == .screenshots ? .appScreenshotSets : .appPreviewSets }
    var assetsName: APIName { self == .screenshots ? .appScreenshots : .appPreviews }
    var setsType: String { self == .screenshots ? "appScreenshotSets" : "appPreviewSets" }
    var assetsType: String { self == .screenshots ? "appScreenshots" : "appPreviews" }
    var typeAttribute: String { self == .screenshots ? "screenshotDisplayType" : "previewType" }
    var setRelationship: String { self == .screenshots ? "appScreenshotSet" : "appPreviewSet" }

    func displayTypes(platform: String?) -> [String] {
        let types = ScreenshotDisplayType.supported(for: platform)
        return types.filter { self == .screenshots || !$0.rawValue.contains("WATCH") }.map {
            self == .screenshots ? $0.rawValue : String($0.rawValue.dropFirst(4))
        }
    }

    func displayName(_ raw: String) -> String {
        ScreenshotDisplayType(rawValue: self == .screenshots ? raw : "APP_\(raw)")?.displayName
            ?? raw.replacingOccurrences(of: "_", with: " ")
    }
}

struct StoreMediaDelivery: Codable, Equatable {
    struct Issue: Codable, Equatable { var code: String?; var description: String? }
    var state: String?
    var errors: [Issue]?
    var warnings: [Issue]?

    var label: String {
        switch state {
        case "AWAITING_UPLOAD": return "Awaiting upload"
        case "UPLOAD_COMPLETE": return "Processing"
        case "PROCESSING": return "Processing"
        case "COMPLETE": return "Ready"
        case "FAILED": return "Failed"
        case .some(let state): return state.replacingOccurrences(of: "_", with: " ").capitalized
        case nil: return "Status unavailable"
        }
    }
    var isProcessing: Bool { state == "UPLOAD_COMPLETE" || state == "PROCESSING" }
    var details: String? {
        let messages = ((errors ?? []) + (warnings ?? [])).compactMap { $0.description ?? $0.code }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }
}

/// Sparse projections of Apple's media resources. A thumbnail is never used
/// as evidence that delivery has finished; the delivery state is authoritative.
struct StoreMediaResource: Codable, Identifiable, Equatable {
    struct Image: Codable, Equatable { var templateUrl: String?; var width: Int?; var height: Int? }
    struct Frame: Codable, Equatable { var image: Image? }
    struct Attributes: Codable, Equatable {
        var screenshotDisplayType: String?
        var previewType: String?
        var fileName: String?
        var fileSize: Int?
        var sourceFileChecksum: String?
        var imageAsset: Image?
        var previewImage: Image?
        var previewFrameImage: Frame?
        var videoUrl: String?
        var uploadOperations: [UploadOperation]?
        var assetDeliveryState: StoreMediaDelivery?
        var videoDeliveryState: StoreMediaDelivery?
    }
    var type: String
    var id: String
    var attributes: Attributes?
    var displayType: String { attributes?.screenshotDisplayType ?? attributes?.previewType ?? "" }
    var delivery: StoreMediaDelivery {
        attributes?.videoDeliveryState ?? attributes?.assetDeliveryState ?? StoreMediaDelivery()
    }
    var thumbnail: String? {
        attributes?.previewFrameImage?.image?.templateUrl ?? attributes?.previewImage?.templateUrl
            ?? attributes?.imageAsset?.templateUrl
    }
    var videoURL: URL? {
        guard let raw = attributes?.videoUrl, let url = URL(string: raw),
              url.scheme?.lowercased() == "https", url.user == nil, url.password == nil else { return nil }
        return url
    }
}

struct StoreMediaAPI {
    var request: @MainActor (APIMethod) async throws -> Data
    var upload: @MainActor (URL, String, [String: String], Data) async throws -> Void

    static var live: Self {
        Self(request: { method in
            guard let request = APIClient.shared.getRequest(api: method, apiVersion: .v1) else {
                throw StoreMediaError.message("Select a team before loading media.")
            }
            return try await APIClient.shared.callAPI(with: request)
        }, upload: { url, method, headers, data in
            try await APIClient.shared.upload(to: url, method: method, headers: headers, body: data)
        })
    }

#if DEBUG
    /// Offline UI fixtures exercise both media kinds without account access.
    static var sample: Self {
        Self(request: { method in
            let path = method.apiPath
            let previews = path.contains("appPreview")
            let kind: StoreMediaKind = previews ? .previews : .screenshots
            let resources: [[String: Any]]
            if path.hasSuffix("Sets") {
                resources = previews
                    ? [["type": kind.setsType, "id": "sample-video-set", "attributes": [kind.typeAttribute: "DESKTOP"]]]
                    : [["type": kind.setsType, "id": "sample-image-set", "attributes": [kind.typeAttribute: "APP_DESKTOP"]],
                       ["type": kind.setsType, "id": "sample-tablet-set", "attributes": [kind.typeAttribute: "APP_IPAD_PRO_3GEN_129"]]]
            } else {
                var attributes: [String: Any] = ["fileName": previews ? "Preview.mov" : (path.contains("sample-tablet-set") ? "Tablet.png" : "Screenshot.png"),
                    "fileSize": 4, previews ? "videoDeliveryState" : "assetDeliveryState": ["state": "COMPLETE"]]
                if previews { attributes["videoUrl"] = "https://example.invalid/preview.mov" }
                resources = [["type": kind.assetsType, "id": previews ? "sample-video" : (path.contains("sample-tablet-set") ? "sample-tablet" : "sample-image"),
                              "attributes": attributes]]
            }
            return try JSONSerialization.data(withJSONObject: ["data": resources])
        }, upload: { _, _, _, _ in throw StoreMediaError.message("Uploads are disabled in the screenshot fixture.") })
    }
#endif
}

enum StoreMediaError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct StoreMediaFile {
    let name: String
    let bytes: Data
    let checksum: String
    let mimeType: String?

    init(name: String, bytes: Data, mimeType: String? = nil) {
        self.name = name
        self.bytes = bytes
        self.mimeType = mimeType
        checksum = Insecure.MD5.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    static func read(_ url: URL, kind: StoreMediaKind) async throws -> Self {
        let ext = url.pathExtension.lowercased()
        let accepted = kind == .screenshots ? ["png", "jpg", "jpeg"] : ["mov", "mp4", "m4v"]
        guard accepted.contains(ext) else { throw StoreMediaError.message("Choose a \(kind == .screenshots ? "PNG or JPEG image" : "MOV, MP4, or M4V video").") }
        if kind == .previews {
            let asset = AVURLAsset(url: url)
            let seconds = try await asset.load(.duration).seconds
            guard seconds.isFinite, seconds >= 15, seconds <= 30 else {
                throw StoreMediaError.message("App Preview videos must be 15–30 seconds long.")
            }
        }
        return try await Task.detached(priority: .userInitiated) {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, kind != .previews || size <= 500_000_000 else {
                throw StoreMediaError.message("The file is empty or exceeds the 500 MB video limit.")
            }
            return Self(name: url.lastPathComponent, bytes: try Data(contentsOf: url, options: .mappedIfSafe),
                        mimeType: kind == .previews ? (ext == "mov" ? "video/quicktime" : "video/mp4") : nil)
        }.value
    }
}

@MainActor
final class AppStoreMediaLibrary: ObservableObject {
    struct Key: Hashable { let localizationID: String; let kind: StoreMediaKind }
    struct Entry {
        var sets: [StoreMediaResource] = []
        var assets: [String: [StoreMediaResource]] = [:]
        var isLoaded = false
        var isLoading = false
        var error: String?
        var allAssets: [StoreMediaResource] { sets.flatMap { assets[$0.id] ?? [] } }
    }
    private struct UploadKey: Hashable { let key: Key; let setID: String; let checksum: String }
    private struct Reservation {
        var id: String?
        let fileName: String
        let fileSize: Int
        let previousIDs: Set<String>
    }
    @Published private(set) var entries: [Key: Entry] = [:]
    @Published private(set) var busy = false
    @Published private(set) var progress: Double?
    @Published private(set) var uploadingName: String?
    @Published var actionError: String?
    private var generation = UUID()
    private var requests: [Key: UUID] = [:]
    private var operationID: UUID?
    private var reservations: [UploadKey: Reservation] = [:]
    var api: StoreMediaAPI

    init(api: StoreMediaAPI = .live) { self.api = api }

    func entry(_ localizationID: String, _ kind: StoreMediaKind) -> Entry {
        entries[Key(localizationID: localizationID, kind: kind)] ?? Entry()
    }
    func reset() {
        generation = UUID()
        entries = [:]
        requests = [:]
        reservations = [:]
        operationID = nil
        busy = false
        progress = nil
        uploadingName = nil
        actionError = nil
    }
    private func check(_ epoch: UUID) throws {
        try Task.checkCancellation()
        guard generation == epoch else { throw CancellationError() }
    }

    private func message(_ error: Error) -> String {
        if let error = error as? StoreMediaError { return error.localizedDescription }
        return FriendlyErrorMessage.message(for: error, requiring: .appInfo)
    }

    private struct Page: Decodable {
        struct Links: Decodable { var next: String? }
        struct Meta: Decodable { struct Paging: Decodable { var nextCursor: String? }; var paging: Paging? }
        var data: [StoreMediaResource]
        var links: Links?
        var meta: Meta?
        var cursor: String? {
            meta?.paging?.nextCursor ?? links?.next.flatMap { URLComponents(string: $0) }?
                .queryItems?.first(where: { $0.name == "cursor" })?.value
        }
    }
    private struct Single: Decodable { var data: StoreMediaResource }

    private func list(_ name: APIName, path: String, expected: String, epoch: UUID) async throws -> [StoreMediaResource] {
        var result: [StoreMediaResource] = []
        var cursor: String?
        var visited = Set<String>()
        var seen = Set<String>()
        repeat {
            try check(epoch)
            var query = ["limit": "200"]
            if let cursor {
                guard visited.insert(cursor).inserted else { throw StoreMediaError.message("The server repeated a media page. Refresh to retry.") }
                query["cursor"] = cursor
            }
            let data = try await api.request(.get(name: name, queryParams: query, path: path))
            try check(epoch)
            let page = try JSONDecoder().decode(Page.self, from: data)
            guard page.data.allSatisfy({ $0.type == expected }) else { throw StoreMediaError.message("Unexpected media response.") }
            result += page.data.filter { seen.insert($0.id).inserted }
            cursor = page.cursor
        } while cursor != nil
        return result
    }

    func refresh(localizationID: String, kind: StoreMediaKind) async {
        await refresh(Key(localizationID: localizationID, kind: kind), duringWrite: false)
    }
    private func refresh(_ key: Key, duringWrite: Bool) async {
        guard !busy || duringWrite else { return }
        let epoch = generation
        let token = UUID()
        requests[key] = token
        entries[key, default: Entry()].isLoading = true
        entries[key]?.error = nil
        defer {
            if generation == epoch, requests[key] == token { entries[key]?.isLoading = false }
        }
        do {
            let sets = try await list(.appStoreVersionLocalizations,
                path: "\(key.localizationID)/\(key.kind.setsType)", expected: key.kind.setsType, epoch: epoch)
            var assets: [String: [StoreMediaResource]] = [:]
            for set in sets {
                assets[set.id] = try await list(key.kind.setsName, path: "\(set.id)/\(key.kind.assetsType)",
                                               expected: key.kind.assetsType, epoch: epoch)
            }
            try check(epoch)
            guard requests[key] == token else { return }
            entries[key] = Entry(sets: sets, assets: assets, isLoaded: true)
        } catch {
            guard generation == epoch, requests[key] == token, !Task.isCancelled else { return }
            entries[key]?.error = message(error)
        }
    }

    private func beginWrite(key: Key) -> (UUID, UUID)? {
        guard !busy else { return nil }
        let id = UUID()
        operationID = id
        busy = true
        requests[key] = nil // Discard reads that started before the mutation.
        entries[key]?.isLoading = false
        actionError = nil
        return (generation, id)
    }
    private func endWrite(_ id: UUID) {
        guard operationID == id else { return }
        busy = false
        operationID = nil
        progress = nil
        uploadingName = nil
    }
    private func body(type: String, id: String? = nil, attributes: [String: Any], relationship: (String, String, String)? = nil) throws -> Data {
        var data: [String: Any] = ["type": type, "attributes": attributes]
        if let id { data["id"] = id }
        if let (name, type, id) = relationship { data["relationships"] = [name: ["data": ["type": type, "id": id]]] }
        return try JSONSerialization.data(withJSONObject: ["data": data])
    }
    private func single(_ method: APIMethod, expected: String, epoch: UUID) async throws -> StoreMediaResource {
        try check(epoch)
        let data = try await api.request(method)
        try check(epoch)
        let resource = try JSONDecoder().decode(Single.self, from: data).data
        guard resource.type == expected else { throw StoreMediaError.message("Unexpected media response.") }
        return resource
    }

    func createSet(localizationID: String, kind: StoreMediaKind, displayType: String) async {
        let key = Key(localizationID: localizationID, kind: kind)
        guard let (epoch, id) = beginWrite(key: key) else { return }
        defer { endWrite(id) }
        do {
            let sets = try await list(.appStoreVersionLocalizations, path: "\(localizationID)/\(kind.setsType)", expected: kind.setsType, epoch: epoch)
            if !sets.contains(where: { $0.displayType == displayType }) {
                let data = try body(type: kind.setsType, attributes: [kind.typeAttribute: displayType],
                                    relationship: ("appStoreVersionLocalization", "appStoreVersionLocalizations", localizationID))
                _ = try await single(.post(name: kind.setsName, body: data), expected: kind.setsType, epoch: epoch)
            }
            await refresh(key, duringWrite: true)
        } catch {
            guard generation == epoch, !Task.isCancelled else { return }
            actionError = message(error)
            await refresh(key, duringWrite: true)
        }
    }

    func upload(localizationID: String, kind: StoreMediaKind, setID: String, fileURL: URL) async -> Bool {
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        let epoch = generation
        do {
            let file = try await StoreMediaFile.read(fileURL, kind: kind)
            try check(epoch)
            return await upload(localizationID: localizationID, kind: kind, setID: setID, file: file)
        } catch {
            if generation == epoch, !Task.isCancelled { actionError = error.localizedDescription }
            return false
        }
    }

    /// Keep the reservation after any uncertain PUT/PATCH result. A retry
    /// reuses that ID, and never starts a second reservation for the file.
    func upload(localizationID: String, kind: StoreMediaKind, setID: String, file: StoreMediaFile) async -> Bool {
        let key = Key(localizationID: localizationID, kind: kind)
        guard let (epoch, id) = beginWrite(key: key) else { return false }
        defer { endWrite(id) }
        uploadingName = file.name
        progress = 0
        let uploadKey = UploadKey(key: key, setID: setID, checksum: file.checksum)
        do {
            let current = try await list(kind.setsName, path: "\(setID)/\(kind.assetsType)", expected: kind.assetsType, epoch: epoch)
            entries[key, default: Entry()].assets[setID] = current
            if current.contains(where: { $0.attributes?.sourceFileChecksum == file.checksum && ($0.delivery.state == "COMPLETE" || $0.delivery.isProcessing) }) {
                return true
            }
            if var pending = reservations[uploadKey], pending.id == nil {
                let candidates = current.filter {
                    !pending.previousIDs.contains($0.id) && $0.attributes?.fileName == file.name && $0.attributes?.fileSize == file.bytes.count
                        && ($0.attributes?.sourceFileChecksum == nil || $0.attributes?.sourceFileChecksum == file.checksum)
                }
                guard candidates.count == 1 else {
                    throw StoreMediaError.message("The previous reservation is unconfirmed. Refresh and review this set in App Store Connect before trying again; no duplicate was created.")
                }
                pending.id = candidates[0].id
                reservations[uploadKey] = pending
            }
            let reserved: StoreMediaResource
            if let resourceID = reservations[uploadKey]?.id {
                reserved = try await single(.get(name: kind.assetsName, path: resourceID), expected: kind.assetsType, epoch: epoch)
                if reserved.delivery.state == "COMPLETE" || reserved.delivery.isProcessing { return true }
            } else {
                guard !current.contains(where: { $0.attributes?.fileName == file.name }) else {
                    throw StoreMediaError.message("A file named \(file.name) already exists in this set. Review its delivery status and remove it before replacing it.")
                }
                guard current.count < (kind == .screenshots ? 10 : 3) else {
                    throw StoreMediaError.message("This set already has the maximum number of \(kind == .screenshots ? "screenshots (10)" : "App Previews (3)").")
                }
                reservations[uploadKey] = Reservation(fileName: file.name, fileSize: file.bytes.count, previousIDs: Set(current.map(\.id)))
                var attributes: [String: Any] = ["fileName": file.name, "fileSize": file.bytes.count]
                if let mime = file.mimeType { attributes["mimeType"] = mime }
                let data = try body(type: kind.assetsType, attributes: attributes,
                                    relationship: (kind.setRelationship, kind.setsType, setID))
                reserved = try await single(.post(name: kind.assetsName, body: data), expected: kind.assetsType, epoch: epoch)
                reservations[uploadKey]?.id = reserved.id
            }
            guard let operations = reserved.attributes?.uploadOperations, !operations.isEmpty else {
                throw StoreMediaError.message("The reserved file has no upload operations. Refresh to check its delivery status.")
            }
            for (index, operation) in operations.enumerated() {
                try check(epoch)
                guard let raw = operation.url, let url = URL(string: raw), url.scheme?.lowercased() == "https",
                      let offset = operation.offset, let length = operation.length, offset >= 0, length > 0,
                      offset <= file.bytes.count, length <= file.bytes.count - offset else {
                    throw StoreMediaError.message("Apple returned an invalid upload operation. The existing reservation was retained.")
                }
                var headers: [String: String] = [:]
                for header in operation.requestHeaders ?? [] { if let name = header.name, let value = header.value { headers[name] = value } }
                try await api.upload(url, operation.method ?? "PUT", headers, file.bytes.subdata(in: offset..<(offset + length)))
                try check(epoch)
                progress = Double(index + 1) / Double(operations.count)
            }
            let data = try body(type: kind.assetsType, id: reserved.id,
                                attributes: ["uploaded": true, "sourceFileChecksum": file.checksum])
            _ = try await single(.patch(name: kind.assetsName, body: data, path: reserved.id), expected: kind.assetsType, epoch: epoch)
            await refresh(key, duringWrite: true)
            return true
        } catch {
            guard generation == epoch, !Task.isCancelled else { return false }
            let detail = message(error)
            actionError = reservations[uploadKey] == nil ? detail : "\(detail) The upload reservation was kept. Select the same file to retry without creating another copy."
            await refresh(key, duringWrite: true)
            return false
        }
    }

    func delete(localizationID: String, kind: StoreMediaKind, asset: StoreMediaResource) async {
        let key = Key(localizationID: localizationID, kind: kind)
        guard let (epoch, id) = beginWrite(key: key) else { return }
        defer { endWrite(id) }
        do {
            _ = try await api.request(.delete(name: kind.assetsName, path: asset.id))
            try check(epoch)
            reservations = reservations.filter { $0.key.key != key || $0.value.id != asset.id }
            for setID in entries[key]?.assets.keys.map({ $0 }) ?? [] {
                entries[key]?.assets[setID]?.removeAll { $0.id == asset.id }
            }
            await refresh(key, duringWrite: true)
        } catch {
            guard generation == epoch, !Task.isCancelled else { return }
            actionError = message(error)
            await refresh(key, duringWrite: true)
        }
    }
}
