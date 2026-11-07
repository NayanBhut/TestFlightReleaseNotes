import Foundation
import Combine

/// Owns the multi-request submission transaction. A failure consumes the retry
/// permit; only fresh, read-only validation can issue another permit. Draft IDs
/// survive failures so retry never blindly creates a second submission.
@MainActor
final class SubmissionCoordinator: ObservableObject {
    typealias Request = @MainActor (APIMethod) async throws -> Data
    @Published private(set) var failure: SubmissionFailure?
    @Published private(set) var refreshFailure: SubmissionFailure?
    @Published private(set) var refreshing = false
    @Published private(set) var busy = false
    @Published private(set) var validated = false
    @Published private(set) var validationMessage: String?
    private let request: Request
    private let now: () -> Date
    private var context: (app: String, version: String)?
    private var draftID: String?
    private var itemLinked = false
    private var uncertainCreate = false
    private var uncertainLink = false
    private var epoch = 0
    private(set) var refreshedVersionData: Data?

    init(request: @escaping Request = { method in
        guard let urlRequest = APIClient.shared.getRequest(api: method, apiVersion: .v1) else { throw APIError.requestFailed }
        return try await APIClient.shared.callAPI(with: urlRequest)
    }, now: @escaping () -> Date = Date.init) {
        self.request = request; self.now = now
    }
    func reset() {
        epoch += 1; context = nil; draftID = nil; itemLinked = false
        uncertainCreate = false; uncertainLink = false
        failure = nil; refreshFailure = nil; validated = false; validationMessage = nil
        busy = false; refreshing = false; refreshedVersionData = nil
    }
    func matches(app: String, version: String) -> Bool { context?.app == app && context?.version == version }
    func canRetry(at date: Date) -> Bool {
        failure != nil && validated && !busy && !refreshing && !isCoolingDown(at: date)
    }
    var rateLimitFailure: SubmissionFailure? {
        [failure, refreshFailure].compactMap { $0 }.filter { $0.retryNotBefore != nil }
            .max { $0.retryNotBefore! < $1.retryNotBefore! }
    }
    var technicalDetails: String {
        [failure.map { "Submission request\n\($0.technicalDetails)" },
         refreshFailure.map { "Refresh request\n\($0.technicalDetails)" }]
            .compactMap { $0 }.joined(separator: "\n\n")
    }
    func invalidateValidation() { validated = false }
    func isCoolingDown(at date: Date) -> Bool { rateLimitFailure?.retryNotBefore.map { date < $0 } ?? false }
    private func check(_ generation: Int) throws {
        try Task.checkCancellation()
        guard epoch == generation else { throw CancellationError() }
    }
    private func send(_ method: APIMethod, generation: Int) async throws -> Data {
        try check(generation)
        let data = try await request(method)
        try check(generation)
        return data
    }
    private func json(_ data: Data) throws -> SubmissionJSON { try JSONDecoder().decode(SubmissionJSON.self, from: data) }
    private func body<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }

    func submit(app: String, version: String) async -> Bool {
        guard !busy, !refreshing else { return false }
        guard context == nil || matches(app: app, version: version) else { return false }
        if failure != nil && !canRetry(at: now()) { return false }
        context = (app, version)
        let generation = epoch
        busy = true; validated = false; validationMessage = nil; refreshFailure = nil
        defer { if epoch == generation { busy = false } }
        do {
            if draftID == nil {
                uncertainCreate = true
                let data = try await send(.post(name: .getReviewSubmissions, body: body(ReviewSubmissionCreateRequest(
                    data: ReviewSubmissionCreateData(attributes: nil, relationships: ReviewSubmissionAppLinkage(
                        app: ReviewSubmissionAppRef(data: ReviewSubmissionAppRefData(id: app))))))), generation: generation)
                guard let id = try json(data)["data"]?["id"]?.string, !id.isEmpty else { throw APIError.invalidData }
                draftID = id; uncertainCreate = false
            }
            guard let id = draftID else { throw APIError.invalidData }
            if !itemLinked {
                uncertainLink = true
                _ = try await send(.post(name: .reviewSubmissionItems, body: body(ReviewSubmissionItemCreateRequest(
                    data: ReviewSubmissionItemCreateData(relationships: ReviewSubmissionItemRelationships(
                        reviewSubmission: ReviewSubmissionItemRef(data: ReviewSubmissionItemRefData(id: id)),
                        appStoreVersion: ReviewSubmissionItemVersionRef(data: ReviewSubmissionItemVersionRefData(id: version))))))), generation: generation)
                itemLinked = true; uncertainLink = false
            }
            _ = try await send(.patch(name: .getReviewSubmissions, body: body(ReviewSubmissionUpdateRequest(
                data: ReviewSubmissionUpdateData(id: id, attributes: ReviewSubmissionUpdateAttributes(submitted: true, canceled: nil)))), path: id), generation: generation)
            failure = nil; validationMessage = nil
            return true
        } catch {
            guard !Task.isCancelled, epoch == generation else { return false }
            // A 4xx response is a definite rejection, unlike a transport timeout
            // (or 5xx), whose write may already have reached Apple.
            if let status = (error as? APIError)?.statusCode, (400..<500).contains(status) {
                uncertainCreate = false; uncertainLink = false
            }
            failure = SubmissionFailure(error: error, now: now())
            return false
        }
    }

    /// No writes. In addition to the version prerequisites, re-read every
    /// recognized required field Apple named, and reconcile any partial draft.
    func refresh(app: String, version: String, requiresWhatsNew: Bool) async {
        guard matches(app: app, version: version), failure != nil, !busy, !refreshing,
              !isCoolingDown(at: now()) else { return }
        let generation = epoch
        refreshing = true; validated = false; validationMessage = nil
        refreshFailure = nil; refreshedVersionData = nil
        defer { if epoch == generation { refreshing = false } }
        do {
            let data = try await send(.get(name: .getAppStoreVersions,
                queryParams: ["include": "build"], path: version), generation: generation)
            let document = try json(data)
            guard let resource = document["data"], resource["id"]?.string == version else { throw APIError.invalidData }
            refreshedVersionData = data
            let state = resource["attributes"]?["appVersionState"]?.string ?? resource["attributes"]?["appStoreState"]?.string
            guard isVersionEditable(appStoreState: state) else { throw ValidationBlocked("The version’s current state does not permit submission.") }
            guard let buildID = resource["relationships"]?["build"]?["data"]?["id"]?.string else {
                throw ValidationBlocked("Select an eligible processed build for this version.")
            }
            let buildDoc = try json(try await send(.get(name: .getVersionBuilds,
                queryParams: ["include": "preReleaseVersion"], path: buildID), generation: generation))
            let build = buildDoc["data"]
            guard build?["attributes"]?["processingState"]?.string == "VALID",
                  build?["attributes"]?["expired"] == .bool(false),
                  let preRelease = buildDoc["included"]?.array.first(where: { $0["type"]?.string == "preReleaseVersions" }),
                  preRelease["attributes"]?["version"] == resource["attributes"]?["versionString"],
                  preRelease["attributes"]?["platform"] == resource["attributes"]?["platform"] else {
                throw ValidationBlocked("Select an eligible processed build for this version.")
            }
            guard build?["attributes"]?["usesNonExemptEncryption"] != nil,
                  build?["attributes"]?["usesNonExemptEncryption"] != .null else {
                throw ValidationBlocked("Answer the build’s export-compliance questions.")
            }
            let localizations = try await collection(name: .getAppStoreVersions, path: "\(version)/appStoreVersionLocalizations", generation: generation)
            guard !localizations.isEmpty, localizations.allSatisfy({ locale in
                let fields = ["description", "keywords", "supportUrl"] + (requiresWhatsNew ? ["whatsNew"] : [])
                return fields.allSatisfy { locale["attributes"]?[$0]?.isPresent == true }
            }) else {
                throw ValidationBlocked("Complete What’s New, description, keywords, URLs, and required localizations.")
            }
            let reviewDocument = try json(try await send(.get(name: .getAppStoreVersions, path: "\(version)/appStoreReviewDetail"), generation: generation))
            guard let review = reviewDocument["data"],
                  ["contactFirstName", "contactLastName", "contactPhone", "contactEmail"].allSatisfy({ review["attributes"]?[$0]?.isPresent == true }),
                  review["attributes"]?["demoAccountRequired"] == .bool(false) ||
                    (review["attributes"]?["demoAccountRequired"] == .bool(true) && ["demoAccountName", "demoAccountPassword"].allSatisfy({ review["attributes"]?[$0]?.isPresent == true })) else {
                throw ValidationBlocked("Add review contact information and any required demo credentials.")
            }
            if resource["attributes"]?["releaseType"]?.string == "SCHEDULED", resource["attributes"]?["earliestReleaseDate"]?.isPresent != true {
                throw ValidationBlocked("Save a scheduled release date before retrying.")
            }
            // Resolve pointers only against same-service, explicitly supported
            // resource routes. Never follow an arbitrary URL from an error body.
            var resourceCache: [String: SubmissionJSON] = [:]
            for issue in failure?.issues ?? [] where issue.code == "ENTITY_ERROR.ATTRIBUTE.REQUIRED" {
                guard let pointer = issue.pointer else { throw ValidationBlocked("Apple did not identify the missing field. Review the technical details before retrying.") }
                let target: SubmissionJSON
                if let path = issue.resourcePaths.last {
                    if let cached = resourceCache[path] { target = cached }
                    else {
                        guard let method = Self.resourceRead(path) else {
                            throw ValidationBlocked("The affected resource could not be validated automatically: \(path)")
                        }
                        target = try json(try await send(method, generation: generation)); resourceCache[path] = target
                    }
                } else if issue.isReviewInformation {
                    target = reviewDocument
                } else if issue.isLocalization {
                    guard localizations.allSatisfy({ SubmissionJSON.object(["data": $0]).at(pointer: pointer)?.isPresent == true }) else {
                        throw ValidationBlocked("Still missing: \(issue.affectedResource). Save this field and refresh again.")
                    }
                    continue
                } else if issue.field == "usesNonExemptEncryption" {
                    target = buildDoc
                } else { target = document }
                guard target.at(pointer: pointer)?.isPresent == true else {
                    throw ValidationBlocked("Still missing: \(issue.affectedResource). Save this field and refresh again.")
                }
            }
            try await reconcileDraft(app: app, version: version, generation: generation)
            try check(generation)
            validated = true
            validationMessage = "Version refreshed and local validation passed. Apple will validate it again on submission."
        } catch {
            guard !Task.isCancelled, epoch == generation else { return }
            validationMessage = (error as? ValidationBlocked)?.message ?? "Refresh failed. \((error as? APIError)?.details ?? error.localizedDescription)"
            if !(error is ValidationBlocked) {
                refreshFailure = SubmissionFailure(error: error, now: now())
            }
        }
    }

    private func reconcileDraft(app: String, version: String, generation: Int) async throws {
        if let id = draftID {
            let draft = try json(try await send(.get(name: .getReviewSubmissions, path: id), generation: generation))["data"]
            guard draft?["attributes"]?["state"]?.string == "READY_FOR_REVIEW" else {
                throw ValidationBlocked("This submission is already submitted or no longer editable. Refresh App Store Versions to see its current status.")
            }
            let items = try await collection(name: .getReviewSubmissions, path: "\(id)/items", generation: generation)
            let matching = items.filter { $0["relationships"]?["appStoreVersion"]?["data"]?["id"]?.string == version }
            guard items.count == matching.count, matching.count <= 1 else {
                throw ValidationBlocked("This draft contains other or duplicate items. Resolve the draft in App Store Connect before retrying.")
            }
            itemLinked = !matching.isEmpty
            guard itemLinked || !uncertainLink else {
                throw ValidationBlocked("Apple has not confirmed whether the version was linked. Refresh again before retrying.")
            }
        } else {
            let drafts = try await collection(name: .getAllApps, path: "\(app)/reviewSubmissions", generation: generation)
            // Never guess which unrelated draft to reuse after an uncertain POST.
            guard !uncertainCreate else {
                throw ValidationBlocked("Apple has not confirmed whether a draft was created. Check App Store Connect before starting another submission.")
            }
            for draft in drafts where draft["attributes"]?["state"]?.string != "COMPLETE" {
                guard let id = draft["id"]?.string else { throw APIError.invalidData }
                let items = try await collection(name: .getReviewSubmissions, path: "\(id)/items", generation: generation)
                if items.contains(where: { $0["relationships"]?["appStoreVersion"]?["data"]?["id"]?.string == version }) {
                    throw ValidationBlocked("An existing submission already contains this version. Refresh App Store Versions and resolve that submission before retrying.")
                }
            }
        }
    }
    private func collection(name: APIName, path: String, generation: Int) async throws -> [SubmissionJSON] {
        var result: [SubmissionJSON] = []; var cursor: String?; var seen = Set<String>()
        repeat {
            var query: [String: String] = name == .getReviewSubmissions && path.hasSuffix("/items")
                ? ["include": "appStoreVersion"] : [:]
            if let cursor { query["cursor"] = cursor }
            let document = try json(try await send(.get(name: name, queryParams: query, path: path), generation: generation))
            guard case .array(let rows) = document["data"] else { throw APIError.invalidData }
            result += rows
            cursor = document["meta"]?["paging"]?["nextCursor"]?.string
            if let cursor, !seen.insert(cursor).inserted { throw APIError.invalidData }
            if cursor == nil, let next = document["links"]?["next"], next != .null {
                // Fail closed if Apple supplies a next link we cannot follow.
                throw ValidationBlocked("Not all submission records were loaded. Refresh again before retrying.")
            }
        } while cursor != nil
        return result
    }
    static func resourceRead(_ path: String) -> APIMethod? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard path.hasPrefix("/v1/"), parts.count == 3,
              parts[2].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        let routes: [String: APIName] = ["ageRatingDeclarations": .ageRatingDeclarations,
            "appStoreVersionLocalizations": .appStoreVersionLocalizations,
            "appStoreReviewDetails": .appStoreReviewDetails, "builds": .getVersionBuilds,
            "appStoreVersions": .getAppStoreVersions]
        return routes[parts[1]].map { .get(name: $0, path: parts[2]) }
    }
    private struct ValidationBlocked: Error { let message: String; init(_ message: String) { self.message = message } }
}
