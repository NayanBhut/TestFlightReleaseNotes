#if DEBUG
import Foundation

/// Shared by unit tests and the hermetic UI host. This transport is entirely
/// in memory; the test host also rejects HTTP(S) at the APIClient/URLProtocol layer.
@MainActor
final class SubmissionTestServer {
    enum Mode { case allIssues, retryReady, rateLimited, refreshFails, unknownPointer, unauthorized, forbidden, stateOnly }
    let mode: Mode
    var methods: [APIMethod] = []
    var submissions = 0
    var failFirst = true
    var holdRefresh: (() async -> Void)?
    init(_ mode: Mode) { self.mode = mode }
    static func data(_ value: String) -> Data { Data(value.utf8) }
    static func error(code: String = "ENTITY_ERROR.ATTRIBUTE.REQUIRED", field: String, detail: String, status: String = "422") -> String {
        "{\"status\":\"\(status)\",\"code\":\"\(code)\",\"title\":\"Validation failed\",\"detail\":\"\(detail)\",\"source\":{\"pointer\":\"/data/attributes/\(field)\"}}"
    }
    static var nested: Data {
        data("""
        {"errors":[{"status":"409","code":"STATE_ERROR.ENTITY_STATE_INVALID","title":"Cannot submit","detail":"This resource cannot be reviewed","meta":{"associatedErrors":{
        "/v1/ageRatingDeclarations/age-1":[\(error(field: "socialMedia", detail: "Social media answer is required.")),\(error(field: "violenceCartoonOrFantasy", detail: "Violence answer is required."))],
        "/v1/appStoreVersionLocalizations/locale-1":[\(error(field: "description", detail: "Description is required."))],
        "/v1/appStoreReviewDetails/review-1":[\(error(field: "contactEmail", detail: "Review email is required."))],
        "/v1/builds/build-1":[\(error(code: "ENTITY_ERROR.RELATIONSHIP.INVALID", field: "build", detail: "Build is not eligible.")),\(error(field: "usesNonExemptEncryption", detail: "Encryption answer is required."))],
        "/v1/appStoreVersions/ui-test-version-primary":[\(error(code: "FUTURE_UNKNOWN_CODE", field: "futureField", detail: "Apple original unknown detail: Ω."))]
        }}}]}
        """)
    }
    static var socialMedia: Data {
        data("""
        {"errors":[{"status":"409","code":"STATE_ERROR.ENTITY_STATE_INVALID","title":"Cannot submit","detail":"This resource cannot be reviewed","meta":{"associatedErrors":{"/v1/ageRatingDeclarations/age-1":[\(error(field: "socialMedia", detail: "Social media answer is required."))]}}}]}
        """)
    }
    static var version: Data {
        data("""
        {"data":{"type":"appStoreVersions","id":"ui-test-version-primary","attributes":{"versionString":"99.0","platform":"IOS","appStoreState":"PREPARE_FOR_SUBMISSION","appVersionState":"PREPARE_FOR_SUBMISSION","releaseType":"MANUAL"},"relationships":{"build":{"data":{"type":"builds","id":"build-1"}}}}}
        """)
    }
    func request(_ method: APIMethod) async throws -> Data {
        methods.append(method)
        switch method {
        case .post(name: .getReviewSubmissions, _, _, _):
            submissions += 1
            return Self.data("{\"data\":{\"type\":\"reviewSubmissions\",\"id\":\"draft-1\"}}")
        case .post(name: .reviewSubmissionItems, _, _, _):
            return Self.data("{}")
        case .patch(name: .getReviewSubmissions, _, _, _):
            if failFirst {
                failFirst = false
                switch mode {
                case .rateLimited:
                    throw APIError.structured(SubmissionFailure(status: 429, data: Self.data("{\"errors\":[{\"status\":\"429\",\"code\":\"RATE_LIMIT\",\"title\":\"Slow down\",\"detail\":\"Too many submission requests.\"}]}"), retryAfter: "120"))
                case .unauthorized, .forbidden, .stateOnly:
                    let status = mode == .unauthorized ? 401 : (mode == .forbidden ? 403 : 409)
                    let code = mode == .stateOnly ? "STATE_ERROR.ENTITY_STATE_INVALID" : "ACCESS_ERROR"
                    throw APIError.structured(SubmissionFailure(status: status, data: Self.data("{\"errors\":[{\"status\":\"\(status)\",\"code\":\"\(code)\",\"title\":\"Cannot submit\",\"detail\":\"Apple access or state error.\"}]}")))
                case .unknownPointer:
                    throw APIError.structured(SubmissionFailure(status: 422, data: Self.data("{\"errors\":[\(Self.error(field: "futureRequiredField", detail: "An unknown field is required."))]}")))
                default:
                    throw APIError.structured(SubmissionFailure(status: 409, data: mode == .allIssues ? Self.nested : Self.socialMedia))
                }
            }
            return Self.data("{}")
        case .get(let name, _, let path):
            if let holdRefresh { await holdRefresh() }
            if mode == .refreshFails { throw APIError.apiError(error: "Synthetic refresh failure") }
            switch (name, path) {
            case (.getAppStoreVersions, "ui-test-version-primary"): return Self.version
            case (.getAppStoreVersions, "ui-test-version-primary/appStoreVersionLocalizations"):
                return Self.data("{\"data\":[{\"type\":\"appStoreVersionLocalizations\",\"id\":\"locale-1\",\"attributes\":{\"locale\":\"en-US\",\"description\":\"Description\",\"keywords\":\"test\",\"supportUrl\":\"https://example.invalid/support\",\"whatsNew\":\"Fixture updates\"}}]}")
            case (.getAppStoreVersions, "ui-test-version-primary/appStoreReviewDetail"), (.appStoreReviewDetails, "review-1"):
                return Self.data("{\"data\":{\"type\":\"appStoreReviewDetails\",\"id\":\"review-1\",\"attributes\":{\"contactFirstName\":\"UI\",\"contactLastName\":\"Tester\",\"contactPhone\":\"5550100\",\"contactEmail\":\"ui@example.invalid\",\"demoAccountRequired\":false}}}")
            case (.getVersionBuilds, "build-1"):
                return Self.data("{\"data\":{\"type\":\"builds\",\"id\":\"build-1\",\"attributes\":{\"processingState\":\"VALID\",\"expired\":false,\"usesNonExemptEncryption\":false}},\"included\":[{\"type\":\"preReleaseVersions\",\"id\":\"pre-1\",\"attributes\":{\"version\":\"99.0\",\"platform\":\"IOS\"}}]}")
            case (.ageRatingDeclarations, "age-1"):
                return Self.data("{\"data\":{\"type\":\"ageRatingDeclarations\",\"id\":\"age-1\",\"attributes\":{\"socialMedia\":false,\"violenceCartoonOrFantasy\":\"NONE\"}}}")
            case (.appStoreVersionLocalizations, "locale-1"):
                return Self.data("{\"data\":{\"attributes\":{\"description\":\"Saved description\"}}}")
            case (.getReviewSubmissions, "draft-1"):
                return Self.data("{\"data\":{\"type\":\"reviewSubmissions\",\"id\":\"draft-1\",\"attributes\":{\"state\":\"READY_FOR_REVIEW\"}}}")
            case (.getReviewSubmissions, "draft-1/items"):
                return Self.data("{\"data\":[{\"type\":\"reviewSubmissionItems\",\"id\":\"item-1\",\"relationships\":{\"appStoreVersion\":{\"data\":{\"type\":\"appStoreVersions\",\"id\":\"ui-test-version-primary\"}}}}]}")
            default: throw APIError.apiError(error: "Unexpected mock request: \(name.rawValue)/\(path)")
            }
        default: throw APIError.apiError(error: "Unexpected mock write")
        }
    }
}
#endif
