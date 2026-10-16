import Foundation

enum BetaFeedbackKind: String, CaseIterable, Identifiable {
    case screenshots = "betaFeedbackScreenshotSubmissions"
    case crashes = "betaFeedbackCrashSubmissions"

    var id: String { rawValue }
    var title: String { self == .screenshots ? "Screenshots" : "Crashes" }
}

struct BetaFeedbackScreenshot: Decodable, Equatable, Identifiable {
    let url: String?
    let width: Int?
    let height: Int?
    let expirationDate: String?

    var id: String { url ?? "\(width ?? 0)x\(height ?? 0)" }
    var secureURL: URL? {
        guard let url, let value = URL(string: url), value.scheme?.lowercased() == "https",
              value.host != nil, value.user == nil, value.password == nil else { return nil }
        return value
    }
    func isExpired(at date: Date = Date()) -> Bool {
        guard let expiration = BetaFeedbackItem.date(expirationDate) else { return false }
        return expiration <= date
    }
}

struct BetaFeedbackAttributes: Decodable, Equatable {
    var createdDate: String?
    var comment: String?
    var email: String?
    var deviceModel: String?
    var osVersion: String?
    var locale: String?
    var timeZone: String?
    var architecture: String?
    var connectionType: String?
    var pairedAppleWatch: String?
    var appUptimeInMilliseconds: Int64?
    var diskBytesAvailable: Int64?
    var diskBytesTotal: Int64?
    var batteryPercentage: Int?
    var screenWidthInPoints: Int?
    var screenHeightInPoints: Int?
    var appPlatform: String?
    var devicePlatform: String?
    var deviceFamily: String?
    var buildBundleId: String?
    var screenshots: [BetaFeedbackScreenshot]?
}

struct BetaFeedbackItem: Identifiable, Equatable {
    let submissionID: String
    let kind: BetaFeedbackKind
    let attributes: BetaFeedbackAttributes
    let buildID: String?
    let buildNumber: String?
    let testerName: String?
    let testerEmail: String?

    var id: String { "\(kind.rawValue):\(submissionID)" }
    var tester: String { testerName ?? email ?? "Anonymous tester" }
    var email: String? { attributes.email ?? testerEmail }
    var note: String { attributes.comment?.nilIfEmpty ?? "No comment provided." }
    var platform: String { attributes.appPlatform ?? "Unknown" }
    var buildLabel: String { buildNumber.map { "Build \($0)" } ?? "Unknown build" }
    var createdDate: Date? { Self.date(attributes.createdDate) }

    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private extension String {
    var nilIfEmpty: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}

/// Sparse JSON:API reader. Only build.version and tester identity are requested;
/// decoding these projections avoids requiring unrelated build relationships.
/// Contract verified against Apple's OpenAPI 4.5.1.
struct BetaFeedbackPage {
    let items: [BetaFeedbackItem]
    let nextCursor: String?
    let total: Int?

    private struct Document: Decodable {
        let data: [Resource]
        let included: [Included]?
        let meta: Meta?
        let links: Links?
    }
    private struct Resource: Decodable {
        let type: String
        let id: String
        let attributes: BetaFeedbackAttributes?
        let relationships: Relationships?
    }
    private struct Relationships: Decodable {
        let build: Relationship?
        let tester: Relationship?
        // crashLog is links-only: fetch its related endpoint on demand.
    }
    private struct Relationship: Decodable { let data: Reference? }
    private struct Reference: Decodable { let type: String; let id: String }
    private struct Included: Decodable {
        let type: String
        let id: String
        let attributes: Attributes?
        struct Attributes: Decodable {
            let version: String?
            let firstName: String?
            let lastName: String?
            let email: String?
        }
    }
    private struct Meta: Decodable {
        let paging: Paging?
        struct Paging: Decodable { let nextCursor: String?; let total: Int? }
    }
    private struct Links: Decodable { let next: String? }

    static func decode(_ data: Data, kind: BetaFeedbackKind) throws -> Self {
        let doc = try JSONDecoder().decode(Document.self, from: data)
        let included = Dictionary((doc.included ?? []).map { ("\($0.type):\($0.id)", $0) },
                                  uniquingKeysWith: { first, _ in first })
        let items = try doc.data.map { resource -> BetaFeedbackItem in
            guard resource.type == kind.rawValue else { throw URLError(.cannotParseResponse) }
            func related(_ reference: Reference?) -> Included? {
                reference.flatMap { included["\($0.type):\($0.id)"] }
            }
            let tester = related(resource.relationships?.tester?.data)?.attributes
            let name = [tester?.firstName, tester?.lastName].compactMap { $0?.nilIfEmpty }.joined(separator: " ")
            return BetaFeedbackItem(submissionID: resource.id, kind: kind,
                attributes: resource.attributes ?? BetaFeedbackAttributes(),
                buildID: resource.relationships?.build?.data?.id,
                buildNumber: related(resource.relationships?.build?.data)?.attributes?.version,
                testerName: name.nilIfEmpty, testerEmail: tester?.email)
        }
        // Extract only the opaque cursor. Never forward credentials to links.next.
        let linkCursor = doc.links?.next.flatMap { URLComponents(string: $0) }?
            .queryItems?.first(where: { $0.name == "cursor" })?.value
        return Self(items: items, nextCursor: doc.meta?.paging?.nextCursor ?? linkCursor,
                    total: doc.meta?.paging?.total)
    }
}

struct BetaFeedbackCrashLogDocument: Decodable {
    let data: Resource
    struct Resource: Decodable {
        let type: String
        let attributes: Attributes?
    }
    struct Attributes: Decodable { let logText: String? }

    static func text(from data: Data) throws -> String? {
        let resource = try JSONDecoder().decode(Self.self, from: data).data
        guard resource.type == "betaCrashLogs" else { throw URLError(.cannotParseResponse) }
        return resource.attributes?.logText
    }
}
