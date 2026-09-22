//
//  APIManager.swift
//  App Store
//
//  Created by Nayan Bhut on 13/05/25.
//

import Foundation
import JSONAPI
import OSLog

private let apiLogger = Logger(subsystem: "com.appstore.release-notes", category: "API")

/// App Store Connect rejects tokens expiring more than 20 minutes ahead,
/// so this is both the signing duration and the basis for cache lifetime.
enum JWTLimits {
    static let expiryInterval: TimeInterval = 60 * 20
}

final class APIClient {
    typealias JSONTaskCompletionHandler = (Data?, APIError?) -> Void
    
    static let shared = APIClient()
    private let baseURL = "https://api.appstoreconnect.apple.com/"
    /// Injectable so tests can mock responses with a URLProtocol stub.
    private let session: URLSession
    
    private let jwtCacheQueue = DispatchQueue(label: "com.appstore.jwtcache", attributes: .concurrent)
    private var jwtCache: [String: (token: String, expiry: Date)] = [:]
    /// Cached slightly shorter than the token's own lifetime so a token
    /// pulled near the end of its life can't expire server-side mid-request.
    private let jwtCacheLifetime: TimeInterval = JWTLimits.expiryInterval - 120

    private init(session: URLSession = .shared) {
        self.session = session
    }

    /// Cache key includes a hash of the private key so re-adding a
    /// credential with the same Key ID + Issuer ID but a new .p8 never
    /// reuses tokens signed with the old key.
    private func cacheKey(for credential: Credential) -> String {
        "\(credential.keyID)-\(credential.issuerID)-\(credential.privateKey.hashValue)"
    }

    private func cachedJWTToken(for credential: Credential) -> String? {
        let key = cacheKey(for: credential)
        return jwtCacheQueue.sync {
            if let cached = jwtCache[key], Date() < cached.expiry {
                return cached.token
            }
            return nil
        }
    }

    private func storeJWTToken(_ token: String, for credential: Credential) {
        let key = cacheKey(for: credential)
        let expiry = Date().addingTimeInterval(jwtCacheLifetime)
        jwtCacheQueue.async(flags: .barrier) {
            self.jwtCache[key] = (token: token, expiry: expiry)
        }
    }

    /// Evict everything on auth rejection — a cached token that just
    /// produced a 401 must not poison subsequent requests.
    func clearAllJWTTokens() {
        jwtCacheQueue.async(flags: .barrier) {
            self.jwtCache.removeAll()
        }
    }

    private func signingToken(for credential: Credential) throws -> String {
        if let cached = cachedJWTToken(for: credential) {
            return cached
        }
        let token = try JWT(keyIdentifier: credential.keyID, issuerIdentifier: credential.issuerID, expireDuration: JWTLimits.expiryInterval).signedToken(using: credential.privateKey)
        storeJWTToken(token, for: credential)
        return token
    }

    private func decodingTask(with request: URLRequest, completionHandler completion: @escaping JSONTaskCompletionHandler) -> URLSessionDataTask {
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(nil, .apiError(error: error.localizedDescription))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(nil, .requestFailed)
                return
            }

            #if DEBUG
            apiLogger.debug("[API] \(request.httpMethod ?? "GET") \(httpResponse.statusCode) \(request.url?.path ?? "")")
            apiLogger.debug("[API][CURL] \(Self.curlCommand(for: request), privacy: .private)")
            // Bodies and queries carry PII (tester emails/names): emails
            // stay redacted, but bodies log in full (see sanitizedBody).
            if let url = request.url, let query = url.query {
                apiLogger.debug("[API] Query: \(Self.redactingPII(in: query))")
            }
            if let body = request.httpBody {
                apiLogger.debug("[API] Request body (\(body.count) bytes): \(Self.sanitizedBody(body))")
            }
            if let data = data {
                apiLogger.debug("[API] Response body (\(data.count) bytes): \(Self.sanitizedBody(data))")
            }
            #endif
            
            guard (200..<300).contains(httpResponse.statusCode) else {
                // A cached token that just got rejected must not poison
                // subsequent requests.
                if httpResponse.statusCode == 401 {
                    self.clearAllJWTTokens()
                }
                var errorMessage = ""
                if let data = data {
                    if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let errors = json["errors"] as? [[String: Any]] {
                        errorMessage = errors.compactMap { $0["detail"] as? String ?? $0["title"] as? String }.joined(separator: "; ")
                    }
                }
                switch httpResponse.statusCode {
                case 401:
                    errorMessage = errorMessage.isEmpty ? "Invalid credentials" : errorMessage
                case 429:
                    // Only mention Retry-After when the header is present —
                    // otherwise the message ends with a dangling "Retry after ".
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After") ?? ""
                    if !retryAfter.isEmpty {
                        errorMessage = errorMessage.isEmpty ? "Rate limited. Retry after \(retryAfter)" : "\(errorMessage). Retry after \(retryAfter)"
                    } else if errorMessage.isEmpty {
                        errorMessage = "Rate limited"
                    }
                case 500:
                    errorMessage = errorMessage.isEmpty ? "Server error" : errorMessage
                default:
                    errorMessage = errorMessage.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode) : errorMessage
                }
                completion(nil, .apiErrorWithCode(error: errorMessage, httpResponse.statusCode))
                return
            }
            
            completion(data, nil)
        }
        return task
    }
    
    /// DEBUG-only API logging. Release builds emit nothing that can
    /// carry credentials or payloads: every request/response/curl line
    /// below is compiled out via #if DEBUG. In DEBUG, emails (PII) and
    /// the Bearer token are always redacted, but bodies log in full (no
    /// truncation) so failing writes can be debugged from the console.
    /// Use the [API][CURL] line to reproduce any request (fill in a fresh
    /// token — tokens are deliberately never printed).
    private static let piiRedactionRegex = try? NSRegularExpression(
        pattern: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#)

    private static func redactingPII(in text: String) -> String {
        guard let piiRedactionRegex else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return piiRedactionRegex.stringByReplacingMatches(
            in: text, options: [], range: range, withTemplate: "[redacted]")
    }

    private static func sanitizedBody(_ data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            return "<\(data.count) bytes, non-UTF-8>"
        }
        return redactingPII(in: text)
    }

    /// Copy-pasteable curl for the Xcode console (DEBUG only at call
    /// sites). Single-quoted throughout; embedded quotes are escaped.
    /// The Bearer token is always redacted — fill in a fresh token.
    static func curlCommand(for request: URLRequest) -> String {
        func shellQuoted(_ value: String) -> String {
            "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        var parts = ["curl", "-X", request.httpMethod ?? "GET"]
        if let url = request.url {
            parts.append(shellQuoted(url.absoluteString))
        }
        for (field, value) in (request.allHTTPHeaderFields ?? [:]).sorted(by: { $0.key < $1.key }) {
            let logged = field.lowercased() == "authorization" ? "Bearer <TOKEN>" : value
            parts.append("-H")
            parts.append(shellQuoted("\(field): \(logged)"))
        }
        if let body = request.httpBody, !body.isEmpty {
            parts.append("--data")
            parts.append(shellQuoted(redactingPII(in: String(data: body, encoding: .utf8) ?? "<non-UTF-8 body>")))
        }
        return parts.joined(separator: " ")
    }

    func callAPI(with request: URLRequest) async throws -> Data {
        #if DEBUG
        apiLogger.debug("[API] \(request.httpMethod ?? "GET") \(request.url?.path ?? "")")
        apiLogger.debug("[API][CURL] \(Self.curlCommand(for: request), privacy: .private)")
        if let body = request.httpBody, !body.isEmpty {
            apiLogger.debug("[API] Request body (\(body.count) bytes): \(Self.sanitizedBody(body), privacy: .private)")
        }
        #endif
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.requestFailed
            }
            #if DEBUG
            apiLogger.debug("[API] Response body (\(data.count) bytes): \(Self.sanitizedBody(data), privacy: .private)")
            #endif
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.requestFailed
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                apiLogger.error("[API] \(request.httpMethod ?? "GET") \(httpResponse.statusCode) \(request.url?.path ?? "")")
                if httpResponse.statusCode == 401 {
                    clearAllJWTTokens()
                }
                // Parse errors[] detail/title from response body for actionable messages.
                var errorMessage = ""
                if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let errors = json["errors"] as? [[String: Any]] {
                    errorMessage = errors.compactMap { $0["detail"] as? String ?? $0["title"] as? String }.joined(separator: "; ")
                }
                switch httpResponse.statusCode {
                case 401:
                    errorMessage = errorMessage.isEmpty ? "Invalid credentials" : errorMessage
                case 429:
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After") ?? ""
                    if !retryAfter.isEmpty {
                        errorMessage = errorMessage.isEmpty ? "Rate limited. Retry after \(retryAfter)" : "\(errorMessage). Retry after \(retryAfter)"
                    } else if errorMessage.isEmpty {
                        errorMessage = "Rate limited"
                    }
                default:
                    errorMessage = errorMessage.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode) : errorMessage
                }
                throw APIError.apiErrorWithCode(error: errorMessage, httpResponse.statusCode)
            }
            return data
        } catch let apiError as APIError {
            throw apiError
        } catch {
            throw APIError.apiError(error: error.localizedDescription)
        }
    }

    /// Legacy completion-handler shim. Kept until all callers migrate to async/await.
    func callAPI(with request: URLRequest, completion: @escaping (Result<Data, APIError>) -> Void) {
        let task = self.decodingTask(with: request) { data, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(Result.failure(error))
                    return
                }
                if let data = data {
                    completion(Result.success(data))
                } else {
                    completion(Result.failure(APIError.invalidData))
                }
            }
        }
        task.resume()
    }
    
    func getRequest(api: APIMethod, apiVersion: APIVersion = .v1) -> URLRequest? {
        guard let team = CredentialStorage.shared.selectedTeam else { return nil }
        guard let token = try? signingToken(for: team) else {
            // Distinguish 'bad private key' from 'no team selected' in logs.
            apiLogger.error("JWT signing failed — check the stored private key for team '\(team.key)'")
            return nil
        }
        if let url = getURL(api: api, apiVersion: apiVersion) {
            var request = URLRequest(url: url)
            request.allHTTPHeaderFields = getHeader(token: token)
            request.httpMethod = api.httpMethod.0
            request.httpBody = getAPIBody(httpMethod: api)
            return request
        }
        return nil
    }
    
    func getRequest(header: [String: String], api: APIMethod, apiVersion: APIVersion = .v1) -> URLRequest? {
        if let url = getURL(api: api, apiVersion: apiVersion) {
            var request = URLRequest(url: url)
            request.allHTTPHeaderFields = header
            request.httpMethod = api.httpMethod.0
            request.httpBody = getAPIBody(httpMethod: api)
            return request
        }
        return nil
    }
    
    private func getAPIBody(httpMethod: APIMethod) -> Data? {
        switch httpMethod {
        case .post(_ ,let body, _, _), .put(_, let body, _, _), .patch(_, let body, _, _):
            return body
        case .delete(_, _, _, let body):
            return body
        default:
            return nil
        }
    }
    
    private func getHeader(token: String) -> [String: String] {
        ["Content-Type": "application/json",
         "Authorization": "Bearer \(token)"]
    }
    
    private func getURL(api: APIMethod, apiVersion: APIVersion = .v1) -> URL? {
        let strUrl = baseURL + apiVersion.rawValue + api.httpMethod.1 + api.apiPath
        guard var components = URLComponents(string: strUrl) else { return nil }
        if let queryItems = api.queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url
    }
}

extension Dictionary {
    var json: String {
        let invalidJson = "Not a valid JSON"
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: self, options: .prettyPrinted)
            return String(bytes: jsonData, encoding: String.Encoding.utf8) ?? invalidJson
        } catch {
            return invalidJson
        }
    }

    func printJson() {
        #if DEBUG
        print("======= API Body Params:======= \n\(json)\n\n")
        #endif
    }

    func printJsonResponse() {
        #if DEBUG
        print("======= API Response:======= \n\(json)\n=====================\n\n")
        #endif
    }

    func printHeader() {
        #if DEBUG
        print("======= API Header:======= \n\(json)\n")
        #endif
    }
}

extension Data {
    func getJsonValue() -> [String: AnyObject]? {
        do {
            if let jsonResult = try JSONSerialization.jsonObject(with: self, options:
                                                                    JSONSerialization.ReadingOptions.allowFragments) as? NSDictionary {
                if let responseDict = jsonResult as? [String: AnyObject] {
                    return responseDict
                }
            }
        } catch {
            #if DEBUG
            print("❌ \(String(data: self, encoding: .utf8) ?? error.localizedDescription)")
            #endif
        }
        return nil
    }
}

enum APIError: Error {
    case requestFailed
    case jsonConversionFailure
    case invalidData
    case responseUnsuccessful
    case jsonParsingFailure
    case apiErrorWithCode(error: String, _ statusCode: Int? = nil, _ apiError: Error? = nil)
    case apiError(error: String)
    case httpError(statusCode: Int)
    case noResponse(statusCode: String)
    case otherResponse(statusCode: String)
    case statusResponse(error: String)

    var details: String {
        switch self {
        case .requestFailed:
            return "Request Failed"
        case .invalidData:
            return "Invalid Data"
        case .responseUnsuccessful:
            return "Response Unsuccessful"
        case .jsonParsingFailure:
            return "JSON Parsing Failure"
        case .jsonConversionFailure:
            return "JSON Conversion Failure"
        case .apiErrorWithCode(let error, _, _):
            return error.localizedLowercase
        case .apiError(let error):
            return error
        case .httpError(let statusCode):
            return "Request failed (HTTP \(statusCode))"
        case .noResponse(let statusCode):
            return statusCode
        case .otherResponse(let statusCode):
            return statusCode
        case .statusResponse(let error):
            return error.localizedLowercase
        }
    }

    var statusCode: Int? {
        switch self {
        case .apiErrorWithCode(_, let code, _):
            return code
        case .httpError(let code):
            return code

        default:
            return nil
        }
    }
}

enum APIName: String {
    case getAllApps = "/apps"
    case getAppVersions = "/preReleaseVersions"
    // GET /builds fetches builds; PATCH on the same path (with a build id
    // in `path`) expires a build. One case covers both since enum raw
    // values must be unique.
    case getVersionBuilds = "/builds"
    case postReleaseNote = "/betaBuildLocalizations"
    case getBetaGroups = "/betaGroups"
    // GET and POST share the /betaTesters path, so one enum case covers both
    // (the HTTP verb comes from APIMethod): .get/.post(name: .getBetaTesters).
    case getBetaTesters = "/betaTesters"
    case patchBuildBetaDetail = "/buildBetaDetails"
    case postBetaAppReviewSubmission = "/betaAppReviewSubmissions"

    // MARK: Batch C endpoints (read-only)
    //
    // NOTE: app-scoped subpaths under /apps — GET /v1/apps/{id}/appInfos
    // and /v1/apps/{id}/customerReviews — are composed with the existing
    // `/apps` prefix (getAllApps) plus a `path` argument, e.g.
    // .get(name: .getAllApps, path: "\(appId)/appInfos"), mirroring the existing /builds/{id}/buildBetaDetail pattern. Enum raw
    // values must be unique, so `/apps` cannot have a second case (a literal
    // `case getAppInfos = "/appInfos"` would build /v1/appInfos/{path},
    // which is not a valid collection route and would 404).
    // GET /v1/appStoreVersions/{id}/appStoreVersionLocalizations via `path`.
    case getAppStoreVersions = "/appStoreVersions"
    // GET /v1/reviewSubmissions?filter[app]=... (top-level collection).
    case getReviewSubmissions = "/reviewSubmissions"
    // GET /v1/appEncryptionDeclarations?filter[app]=... (top-level collection).
    // There is no /v1/apps/{id}/appEncryptionDeclarations subpath — the
    // relationship doesn't exist on apps (server 400s it).
    case getAppEncryptionDeclarations = "/appEncryptionDeclarations"
    // MARK: - Write operations
    // POST /v1/customerReviews/{id}/customerReviewResponses — reply to a review.
    // C3: review replies (POST /v1/customerReviews/{id}/customerReviewResponses).
    // Not under /apps/{id}/ — it's a top-level subpath of /customerReviews.
    case postCustomerReviewResponse = "/customerReviews"

    // C2: team-scoped resources (top-level collections). Verb-neutral names:
    // the enum is a URL prefix, not a GET — the verb comes from APIMethod
    // (.post(name: .devices, …), .patch(name: .devices, path: …)).
    case devices = "/devices"
    case certificates = "/certificates"
    case getBundleIds = "/bundleIds"
    case getProfiles = "/profiles"
    case getUsers = "/users"
    // Batch I (I3): top-level collection for team invitations —
    // GET/POST /v1/userInvitations, DELETE /v1/userInvitations/{id}.
    case userInvitations = "/userInvitations"

    // Batch G (#10): top-level collection route for app info
    // localizations — PATCH /v1/appInfoLocalizations/{id} (verified in the
    // OpenAPI spec: patch/delete/get on /v1/appInfoLocalizations/{id}).
    // Unlike appInfos (app-scoped subpath only), this one is top-level, so
    // it gets its own case. Reused for POST (create) if that's ever added.
    case appInfoLocalizations = "/appInfoLocalizations"
    // Batch I (I6): top-level route for version localizations —
    // PATCH /v1/appStoreVersionLocalizations/{id}. Not under
    // /appStoreVersions/{id}/ (that subpath is read-only list); reusing
    // .getAppStoreVersions would build /v1/appStoreVersions/{id}, which is
    // the wrong resource entirely.
    case appStoreVersionLocalizations = "/appStoreVersionLocalizations"
}

enum APIVersion: String {
    case v1 = "v1"
    case v2 = "v2"
    case v3 = "v3"
}

enum APIMethod {
    case get(name: APIName, queryParams: [String: String] = [:], path: String = "")
    case post(name: APIName, body: Data, queryParams: [String: String] = [:], path: String = "")
    case put(name: APIName, body: Data, queryParams: [String: String] = [:], path: String = "")
    case patch(name: APIName, body: Data, queryParams: [String: String] = [:], path: String = "")
    case delete(name: APIName, queryParams: [String: String] = [:], path: String = "", body: Data? = nil)
    
    var httpMethod:(String, String) {
        switch self {
        case .get(let apiName, _, _):
            return ("GET",apiName.rawValue)
        case .post(let apiName, _, _, _):
            return ("POST",apiName.rawValue)
        case .put(let apiName, _, _, _):
            return ("PUT",apiName.rawValue)
        case .patch(let apiName, _, _, _):
            return ("PATCH",apiName.rawValue)
        case .delete(let apiName, _, _, _):
            return ("DELETE",apiName.rawValue)
        }
    }
    
    var queryItems:[URLQueryItem]? {
        switch self {
        case .get(_, let params, _), .delete(_, let params, _, _):
            return params.map{ URLQueryItem(name: $0, value: String(describing: $1)) }
        case .post(_, _, let params, _), .put(_, _, let params, _), .patch(_, _, let params, _):
            return params.map{ URLQueryItem(name: $0, value: String(describing: $1)) }
        }
    }
    
    var apiPath: String {
        switch self {
        case .get(_,  _, let path), .delete(_, _, let path, _), .post(_, _, _, let path), .put(_, _, _, let path), .patch(_, _, _, let path):
            return path.isEmpty ? "" : "/\(path)"
        }
    }
}


func getDecoder() -> JSONAPIDecoder {
    let decoder = JSONAPIDecoder()
    decoder.ignoresMissingResources = true
    decoder.ignoresUnhandledResourceTypes = true
    
    return decoder
}
