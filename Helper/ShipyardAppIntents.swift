import AppIntents
import AppKit
import Combine
import CryptoKit
import Foundation
import JSONAPI

/// No credentials are exposed to Shortcuts. The hash distinguishes accounts
/// even when a locally saved team name is reused with another issuer.
struct ShipyardIntentScope: Equatable, Sendable {
    let teamName: String
    let accountHash: String

    init(teamName: String, issuerID: String) {
        self.teamName = teamName
        accountHash = SHA256.hash(data: Data(issuerID.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private init(teamName: String, accountHash: String) {
        self.teamName = teamName
        self.accountHash = accountHash
    }

    @MainActor static var current: Self? {
        guard let team = CredentialStorage.shared.selectedTeam else { return nil }
        return Self(teamName: team.key, issuerID: team.issuerID)
    }

    func identifier(appID: String) -> String {
        "\(Data(teamName.utf8).base64EncodedString()).\(accountHash).\(appID)"
    }

    static func reference(_ identifier: String) -> (scope: Self, appID: String)? {
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let data = Data(base64Encoded: parts[0]),
              let name = String(data: data, encoding: .utf8), !name.isEmpty,
              parts[1].count == 64, parts[1].allSatisfy({ "0123456789abcdef".contains($0) }),
              !parts[2].isEmpty, parts[2].allSatisfy({ "0123456789".contains($0) }) else { return nil }
        return (Self(teamName: name, accountHash: parts[1]), parts[2])
    }
}

struct ShipyardAppEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "App Store Connect App"
    static let defaultQuery = ShipyardAppQuery()

    var id: String
    @Property(title: "Name") var name: String
    @Property(title: "Bundle Identifier") var bundleIdentifier: String
    @Property(title: "Team") var teamName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(teamName) · \(bundleIdentifier)")
    }

    init(appID: String, name: String, bundleIdentifier: String, scope: ShipyardIntentScope) {
        id = scope.identifier(appID: appID)
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        teamName = scope.teamName
    }
}

struct ShipyardAppQuery: EntityStringQuery {
    func suggestedEntities() async throws -> [ShipyardAppEntity] {
        try await ShipyardIntentService.shared.apps()
    }

    func entities(matching string: String) async throws -> [ShipyardAppEntity] {
        try await ShipyardIntentService.shared.apps(matching: string)
    }

    func entities(for identifiers: [String]) async throws -> [ShipyardAppEntity] {
        try await ShipyardIntentService.shared.resolve(identifiers)
    }
}

/// A fetched snapshot, rather than a cached entity that might later claim an
/// older build is still the latest. Each property is usable by another action.
struct ShipyardBuildResult: TransientAppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "TestFlight Build"
    var id = UUID()
    @Property(title: "App Name") var appName: String
    @Property(title: "Version") var version: String
    @Property(title: "Build Number") var buildNumber: String
    @Property(title: "Processing Status") var processingStatus: String
    @Property(title: "Platform") var platform: String
    @Property(title: "Upload Date") var uploadDate: Date?
    @Property(title: "Expired") var expired: Bool
    @Property(title: "Build ID") var buildID: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(appName) \(version) (\(buildNumber))",
                              subtitle: "\(platform) · \(processingStatus)")
    }

    init() {
        appName = ""
        version = ""
        buildNumber = ""
        processingStatus = ""
        platform = ""
        uploadDate = nil
        expired = false
        buildID = ""
    }

    @MainActor init(build: BuildsModel, appName: String) {
        self.init()
        self.appName = appName
        version = build.preReleaseVersion?.version ?? "Not available"
        buildNumber = build.version ?? "Not available"
        processingStatus = build.processingState ?? "UNKNOWN"
        platform = build.preReleaseVersion?.platform ?? "Not available"
        uploadDate = BuildDisplayHelper.uploadedDate(from: build.uploadedDate)
        if uploadDate == nil, let raw = build.uploadedDate {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            uploadDate = formatter.date(from: raw)
        }
        expired = build.expired ?? false
        buildID = build.id
    }
}

enum ShipyardIntentError: Error, LocalizedError, CustomLocalizedStringResourceConvertible {
    case noTeam
    case wrongTeam(String)
    case invalidApp
    case noBuilds(String)
    case invalidResponse
    case request(String)

    var errorDescription: String? {
        switch self {
        case .noTeam: return "Open Shipyard and connect or select an App Store Connect team first."
        case .wrongTeam(let team): return "Select \(team) in Shipyard, then run this action again."
        case .invalidApp: return "Choose an app from the selected team again."
        case .noBuilds(let name): return "\(name) has no uploaded TestFlight builds."
        case .invalidResponse: return "App Store Connect returned an unexpected response. Try again."
        case .request(let message): return message
        }
    }

    var localizedStringResource: LocalizedStringResource { "\(errorDescription ?? "Couldn't complete the action.")" }
}

@MainActor
final class ShipyardIntentService {
    static let shared = ShipyardIntentService()
    typealias Request = @MainActor (APIMethod) async throws -> Data
    private let request: Request
    private let scope: @MainActor () -> ShipyardIntentScope?

    init(request: @escaping Request = { method in
        guard let request = APIClient.shared.getRequest(api: method, apiVersion: .v1) else {
            throw ShipyardIntentError.request("Open Shipyard and check the selected team's API key.")
        }
        return try await APIClient.shared.callAPI(with: request)
    }, scope: @escaping @MainActor () -> ShipyardIntentScope? = { .current }) {
        self.request = request
        self.scope = scope
    }

    private func selectedScope() throws -> ShipyardIntentScope {
        guard let scope = scope() else { throw ShipyardIntentError.noTeam }
        return scope
    }

    private func validate(_ expected: ShipyardIntentScope) throws {
        guard scope() == expected else { throw ShipyardIntentError.wrongTeam(expected.teamName) }
    }

    private func load(_ method: APIMethod, in expected: ShipyardIntentScope,
                      permission: AppStoreConnectPermission = .apps) async throws -> Data {
        try validate(expected)
        try Task.checkCancellation()
        do {
            let data = try await request(method)
            try Task.checkCancellation()
            try validate(expected)
            return data
        } catch {
            try Task.checkCancellation()
            try validate(expected)
            if error is ShipyardIntentError || error is CancellationError { throw error }
            throw ShipyardIntentError.request(FriendlyErrorMessage.message(for: error, requiring: permission))
        }
    }

    /// Suggestions are bounded. Name and exact bundle-ID searches also reach
    /// apps beyond the first page without draining the account's entire list.
    func apps(matching text: String = "") async throws -> [ShipyardAppEntity] {
        let expected = try selectedScope()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var parameters = ["fields[apps]": "name,bundleId", "limit": String(query.isEmpty ? AppConfigs.shortcutSuggestionsLimit : AppConfigs.appListLimit)]
        var resources: [AppResource] = []
        if query.isEmpty {
            let data = try await load(.get(name: .getAllApps, queryParams: parameters), in: expected)
            resources = try decode(AppList.self, from: data).data
        } else {
            parameters["filter[name]"] = query
            let nameData = try await load(.get(name: .getAllApps, queryParams: parameters), in: expected)
            resources = try decode(AppList.self, from: nameData).data
            parameters.removeValue(forKey: "filter[name]")
            parameters["filter[bundleId]"] = query
            let bundleData = try await load(.get(name: .getAllApps, queryParams: parameters), in: expected)
            resources += try decode(AppList.self, from: bundleData).data
        }
        var seen = Set<String>()
        return try resources.filter { seen.insert($0.id).inserted }.map { try $0.entity(scope: expected) }
    }

    func resolve(_ identifiers: [String]) async throws -> [ShipyardAppEntity] {
        var resolved: [ShipyardAppEntity] = []
        var seen = Set<String>()
        for identifier in identifiers where seen.insert(identifier).inserted {
            guard let reference = ShipyardIntentScope.reference(identifier) else { continue }
            try validate(reference.scope)
            let data = try await load(.get(name: .getAllApps, queryParams: ["fields[apps]": "name,bundleId"],
                                           path: reference.appID), in: reference.scope)
            let resource = try decode(AppSingle.self, from: data).data
            guard resource.id == reference.appID else { throw ShipyardIntentError.invalidResponse }
            resolved.append(try resource.entity(scope: reference.scope))
        }
        return resolved
    }

    static func latestBuildMethod(appID: String) -> APIMethod {
        // Verified against Apple's OpenAPI: newest upload across versions and
        // platforms, including expired builds, rather than highest build number.
        .get(name: .getVersionBuilds, queryParams: [
            "filter[app]": appID, "sort": "-uploadedDate", "limit": "1",
            "include": "preReleaseVersion",
            "fields[builds]": "version,uploadedDate,processingState,expired,preReleaseVersion",
            "fields[preReleaseVersions]": "version,platform"
        ])
    }

    func latestBuild(for app: ShipyardAppEntity) async throws -> ShipyardBuildResult {
        guard let reference = ShipyardIntentScope.reference(app.id) else { throw ShipyardIntentError.invalidApp }
        let data = try await load(Self.latestBuildMethod(appID: reference.appID), in: reference.scope, permission: .testFlight)
        // Sparse fields intentionally omit betaBuildLocalizations. The shared
        // JSON:API build model requires that to-many relationship while decoding,
        // so decode only this action's requested projection before mapping it.
        let document = try decode(BuildPayload.self, from: data)
        guard let resource = document.data.first else { throw ShipyardIntentError.noBuilds(app.name) }
        guard resource.type == "builds" else { throw ShipyardIntentError.invalidResponse }
        var build = BuildsModel(id: resource.id, betaBuildLocalizations: [])
        build.version = resource.attributes?.version
        build.uploadedDate = resource.attributes?.uploadedDate
        build.processingState = resource.attributes?.processingState
        build.expired = resource.attributes?.expired
        if let link = resource.relationships?.preReleaseVersion?.data {
            guard link.type == "preReleaseVersions" else { throw ShipyardIntentError.invalidResponse }
            if let version = document.included?.first(where: { $0.type == link.type && $0.id == link.id }) {
                var model = PreReleaseVersionsModel(id: version.id)
                model.version = version.attributes?.version
                model.platform = version.attributes?.platform
                build.preReleaseVersion = model
            }
        }
        return ShipyardBuildResult(build: build, appName: app.name)
    }

    func appToOpen(_ entity: ShipyardAppEntity) async throws -> (AppsData, ShipyardIntentScope) {
        guard let reference = ShipyardIntentScope.reference(entity.id) else { throw ShipyardIntentError.invalidApp }
        let data = try await load(.get(name: .getAllApps, queryParams: ["include": "appStoreVersions,appStoreIcon"],
                                      path: reference.appID), in: reference.scope)
        var app: AppsData
        do { app = try getDecoder().decode(AppsData.self, from: data) }
        catch { throw ShipyardIntentError.invalidResponse }
        guard app.id == reference.appID else { throw ShipyardIntentError.invalidResponse }
        app.currentLiveVersion = (app.appStoreVersions.first?.id ?? "", app.appStoreVersions.first?.versionString ?? "")
        app.currentState = app.appStoreVersions.first?.appVersionState ?? ""
        app.iconURL = app.appStoreIcon?.iconAsset?.templateUrl
        return (app, reference.scope)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw ShipyardIntentError.invalidResponse }
    }

    private struct BuildPayload: Decodable {
        struct BuildResource: Decodable {
            struct Attributes: Decodable {
                var version: String?
                var uploadedDate: String?
                var processingState: String?
                var expired: Bool?
            }
            struct Relationships: Decodable {
                struct ToOne: Decodable {
                    struct Reference: Decodable { var type: String; var id: String }
                    var data: Reference?
                }
                var preReleaseVersion: ToOne?
            }
            var type: String
            var id: String
            var attributes: Attributes?
            var relationships: Relationships?
        }
        struct VersionResource: Decodable {
            struct Attributes: Decodable { var version: String?; var platform: String? }
            var type: String
            var id: String
            var attributes: Attributes?
        }
        var data: [BuildResource]
        var included: [VersionResource]?
    }

    private struct AppList: Decodable { var data: [AppResource] }
    private struct AppSingle: Decodable { var data: AppResource }
    private struct AppResource: Decodable {
        struct Attributes: Decodable { var name: String?; var bundleId: String? }
        var type: String
        var id: String
        var attributes: Attributes?

        func entity(scope: ShipyardIntentScope) throws -> ShipyardAppEntity {
            guard type == "apps", ShipyardIntentScope.reference(scope.identifier(appID: id)) != nil else {
                throw ShipyardIntentError.invalidResponse
            }
            return ShipyardAppEntity(appID: id, name: attributes?.name ?? "App \(id)",
                                     bundleIdentifier: attributes?.bundleId ?? "", scope: scope)
        }
    }
}

@MainActor
final class ShipyardIntentNavigation: ObservableObject {
    static let shared = ShipyardIntentNavigation()
    struct Request {
        let id = UUID()
        let app: AppsData
        let scope: ShipyardIntentScope
    }
    @Published private(set) var pending: Request?
    /// Registered by the main scene, retained so a closed window can reopen.
    var presentWindow: (() -> Void)?

    func open(_ app: AppsData, scope: ShipyardIntentScope) {
        pending = Request(app: app, scope: scope)
        presentWindow?()
    }

    func takeRequest(in currentScope: ShipyardIntentScope?) throws -> AppsData? {
        guard let request = pending else { return nil }
        pending = nil
        guard request.scope == currentScope else { throw ShipyardIntentError.wrongTeam(request.scope.teamName) }
        return request.app
    }
}

struct GetLatestShipyardBuildIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Latest Build"
    static let description = IntentDescription("Get the most recently uploaded TestFlight build across all versions and platforms, including its status. Uses the team selected in Shipyard.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @available(macOS 26.0, *) static var supportedModes: IntentModes { .background }

    @Parameter(title: "App", requestValueDialog: "Which app's latest build?") var app: ShipyardAppEntity
    static var parameterSummary: some ParameterSummary { Summary("Get latest build for \(\.$app)") }

    func perform() async throws -> some IntentResult & ReturnsValue<ShipyardBuildResult> & ProvidesDialog {
        let build = try await ShipyardIntentService.shared.latestBuild(for: app)
        return .result(value: build, dialog: "\(build.appName) \(build.version), build \(build.buildNumber): \(build.processingStatus).")
    }
}

struct OpenShipyardAppIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open App"
    static let description = IntentDescription("Open an App Store Connect app's Builds screen in Shipyard. Uses the team selected in Shipyard.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @available(macOS 26.0, *) static var supportedModes: IntentModes { .foreground }

    @Parameter(title: "App", requestValueDialog: "Which app would you like to open?") var target: ShipyardAppEntity
    static var parameterSummary: some ParameterSummary { Summary("Open \(\.$target) in Shipyard") }

    @MainActor func perform() async throws -> some IntentResult {
        let (app, scope) = try await ShipyardIntentService.shared.appToOpen(target)
        ShipyardIntentNavigation.shared.open(app, scope: scope)
        return .result()
    }
}
