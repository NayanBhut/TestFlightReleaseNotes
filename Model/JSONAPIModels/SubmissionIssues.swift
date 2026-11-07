import Foundation

/// Lossless JSON for Apple's open-ended error metadata. Invalid metadata must
/// never prevent an otherwise useful error from being displayed.
enum SubmissionJSON: Codable, Hashable {
    case object([String: SubmissionJSON]), array([SubmissionJSON]), string(String)
    case number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([String: Self].self) { self = .object(v) }
        else { self = .array(try c.decode([Self].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    subscript(_ key: String) -> Self? {
        guard case .object(let v) = self else { return nil }; return v[key]
    }
    var string: String? { if case .string(let v) = self { return v }; return nil }
    var array: [Self] { if case .array(let v) = self { return v }; return [] }
    var object: [String: Self] { if case .object(let v) = self { return v }; return [:] }
    var isPresent: Bool {
        switch self {
        case .null: return false
        case .string(let v): return !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return true // false is a valid saved questionnaire answer.
        }
    }
    func at(pointer: String) -> Self? {
        guard pointer.hasPrefix("/") else { return nil }
        return pointer.dropFirst().split(separator: "/", omittingEmptySubsequences: false).reduce(Optional(self)) { value, token in
            let key = token.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
            if let index = Int(key), case .array(let values) = value, values.indices.contains(index) { return values[index] }
            return value?[key]
        }
    }
}

struct SubmissionIssue: Hashable, Identifiable {
    let status: String?
    let code: String?
    let title: String?
    let detail: String?
    let pointer: String?
    /// Full chain, including the resource path at every nesting level.
    let resourcePaths: [String]
    let hasAssociatedErrors: Bool
    var id: Self { self }
    var field: String? { pointer?.split(separator: "/").last.map(String.init) }
    var affectedResource: String {
        ([pointer].compactMap { $0 } + resourcePaths).joined(separator: " · ")
    }
    private var context: String { (resourcePaths + [pointer ?? "", code ?? ""]).joined(separator: "/").lowercased() }
    private var isAgeRating: Bool {
        context.contains("agerating") || AgeRatingQuestion.all.contains { $0.id == field }
    }
    var isLocalization: Bool {
        context.contains("appstoreversionlocalization") || context.contains("app_store_version_localization") ||
            ["whatsNew", "description", "keywords", "supportUrl", "marketingUrl", "promotionalText"].contains(field ?? "")
    }
    var isReviewInformation: Bool {
        context.contains("appstorereviewdetail") || context.contains("app_review") ||
            ["contactFirstName", "contactLastName", "contactPhone", "contactEmail", "demoAccountRequired", "demoAccountName", "demoAccountPassword"].contains(field ?? "")
    }
    private var friendlyField: String {
        (field ?? "metadata").replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ").capitalized
    }
    var friendlyTitle: String {
        switch status {
        case "401": return "API key could not be authenticated"
        case "403": return "Submission permission required"
        case "429": return "Apple’s request limit reached"
        default: break
        }
        if code == "ENTITY_ERROR.ATTRIBUTE.REQUIRED" { return "Missing required field: \(friendlyField)" }
        if isAgeRating { return "Age Rating information required" }
        if context.contains("exportcompliance") || context.contains("export_compliance") || context.contains("encryption") { return "Export compliance incomplete" }
        if isReviewInformation { return "App Review information required" }
        if isLocalization { return "Version metadata incomplete" }
        if context.contains("build") { return "Eligible build required" }
        if code == "STATE_ERROR.ENTITY_STATE_INVALID" { return "Version cannot be submitted in its current state" }
        if status == "409" { return "Version needs to be refreshed" }
        return title ?? "App Store submission error"
    }
    var solution: String? {
        switch status {
        case "401": return "Check whether the API key was revoked and verify the Key ID, Issuer ID, and private key."
        case "403": return "The selected API key lacks permission. Submission normally requires App Manager or broader access."
        case "429": return "Apple rate-limited the request. Wait for the retry delay, then refresh the version."
        default: break
        }
        // Only classify recognized validation codes. Unknown codes retain Apple's
        // text and pointer without a speculative diagnosis or suggested fix.
        let validation = code?.hasPrefix("ENTITY_ERROR.") == true || code?.hasPrefix("STATE_ERROR.") == true
        if validation {
            if isAgeRating {
                if field?.lowercased() == "socialmedia" {
                    return "Open App Information → Age Ratings and answer the Social Media question."
                }
                return "Complete and save the Age Rating questionnaire."
            }
            if isLocalization { return "Complete What’s New, description, keywords, URLs, and required localizations." }
            if isReviewInformation { return "Add review contact information and any required demo credentials." }
            if context.contains("exportcompliance") || context.contains("export_compliance") || context.contains("encryption") { return "Answer the build’s export-compliance questions." }
            if context.contains("build") { return "Select an eligible processed build for this version." }
        }
        if code == "STATE_ERROR.ENTITY_STATE_INVALID", !hasAssociatedErrors {
            let refresh = status == "409"
                ? "Refresh the version because its state may have changed, then resolve any associated validation errors."
                : "Refresh the version to check its current state."
            return "The version’s current state does not permit this action. \(refresh)"
        }
        if status == "409" { return "Refresh the version because its state may have changed, then resolve any associated validation errors." }
        return nil
    }
}

struct SubmissionFailure: Error, Identifiable {
    let id = UUID()
    let httpStatus: Int?
    let payload: SubmissionJSON?
    let rawBody: String?
    let retryAfter: String?
    let retryNotBefore: Date?
    let issues: [SubmissionIssue]

    init(status: Int?, data: Data?, retryAfter: String? = nil, now: Date = Date(), fallback: String? = nil) {
        httpStatus = status
        payload = data.flatMap { try? JSONDecoder().decode(SubmissionJSON.self, from: $0) }
        rawBody = data.flatMap { String(data: $0, encoding: .utf8) }
        self.retryAfter = retryAfter
        if status == 429 {
            if let seconds = retryAfter.flatMap(Double.init), seconds.isFinite, seconds >= 0 {
                retryNotBefore = now.addingTimeInterval(seconds)
            } else if let header = retryAfter, let date = Self.httpDate(header) {
                retryNotBefore = max(now, date)
            } else {
                // A local backoff when Apple supplies no usable delay, labeled
                // explicitly in the UI instead of inventing a Retry-After value.
                retryNotBefore = now.addingTimeInterval(60)
            }
        } else { retryNotBefore = nil }
        var flattened: [SubmissionIssue] = []
        func visit(_ value: SubmissionJSON, paths: [String]) {
            if case .array(let values) = value { values.forEach { visit($0, paths: paths) }; return }
            guard case .object(let object) = value else { return }
            let isError = ["status", "code", "title", "detail", "source"].contains { object[$0] != nil }
            if !isError {
                for key in object.keys.sorted() {
                    visit(object[key]!, paths: key == "errors" ? paths : paths + [key])
                }
                return
            }
            let before = flattened.count
            if let associated = value["meta"]?["associatedErrors"] { visit(associated, paths: paths) }
            flattened.append(SubmissionIssue(
                status: value["status"]?.string ?? status.map(String.init),
                code: value["code"]?.string, title: value["title"]?.string,
                detail: value["detail"]?.string, pointer: value["source"]?["pointer"]?.string,
                resourcePaths: paths, hasAssociatedErrors: flattened.count > before))
        }
        if let errors = payload?["errors"] { visit(errors, paths: []) }
        if flattened.isEmpty {
            flattened = [SubmissionIssue(status: status.map(String.init), code: nil,
                title: "App Store request failed", detail: fallback ?? rawBody ?? "Apple returned no error details.",
                pointer: nil, resourcePaths: [], hasAssociatedErrors: false)]
        }
        var seen = Set<SubmissionIssue>()
        issues = flattened.filter { seen.insert($0).inserted }
    }
    init(error: Error, now: Date = Date()) {
        if let error = error as? APIError, case .structured(let failure) = error { self = failure; return }
        self.init(status: (error as? APIError)?.statusCode, data: nil, now: now,
                  fallback: (error as? APIError)?.details ?? error.localizedDescription)
    }
    var summary: String { issues.first?.detail ?? issues.first?.title ?? "Submission failed" }
    var technicalDetails: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let json = payload.flatMap { try? encoder.encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        return "HTTP status: \(httpStatus.map(String.init) ?? "unavailable")\nRetry-After: \(retryAfter ?? "not supplied")\n\n\(json ?? rawBody ?? summary)"
    }
    private static func httpDate(_ value: String) -> Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }
}
