import AppIntents
import XCTest
@testable import Shipyard

@MainActor
final class ShipyardAppIntentsTests: XCTestCase {
    private let account = ShipyardIntentScope(teamName: "Studio.a / नमस्ते", issuerID: "issuer-a")
    private var app: ShipyardAppEntity {
        ShipyardAppEntity(appID: "100", name: "Shipyard", bundleIdentifier: "com.example.shipyard", scope: account)
    }
    private func appsPage(_ ids: [String]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["data": ids.map {
            ["type": "apps", "id": $0, "attributes": ["name": "App \($0)", "bundleId": "com.example.\($0)"]]
        }])
    }
    private func buildPage(hasBuild: Bool = true, hasVersion: Bool = true) throws -> Data {
        var resource: [String: Any] = ["type": "builds", "id": "build-9", "attributes": [
            "version": "9", "processingState": "VALID", "uploadedDate": "2026-10-19T10:15:30.123Z", "expired": true
        ]]
        var included: [[String: Any]] = []
        if hasVersion {
            resource["relationships"] = ["preReleaseVersion": ["data": ["type": "preReleaseVersions", "id": "version-2"]]]
            included = [["type": "preReleaseVersions", "id": "version-2", "attributes": ["version": "2.1", "platform": "MAC_OS"]]]
        }
        return try JSONSerialization.data(withJSONObject: ["data": hasBuild ? [resource] : [], "included": included,
            "meta": ["paging": ["total": hasBuild ? 1 : 0, "limit": 1]]])
    }

    func testPersistentReferenceRoundTripsUnicodeAndSeparatorsAndSeparatesAccounts() throws {
        let identifier = account.identifier(appID: "100")
        let reference = try XCTUnwrap(ShipyardIntentScope.reference(identifier))
        XCTAssertEqual(reference.scope, account)
        XCTAssertEqual(reference.appID, "100")
        XCTAssertFalse(identifier.contains("issuer-a"))
        XCTAssertNotEqual(identifier, ShipyardIntentScope(teamName: account.teamName, issuerID: "issuer-b").identifier(appID: "100"))
        XCTAssertNil(ShipyardIntentScope.reference("bad-id"))
        XCTAssertNil(ShipyardIntentScope.reference(account.identifier(appID: "../builds")))
    }

    func testSuggestionsRequireSelectedTeamWithoutSendingRequests() async {
        let service = ShipyardIntentService(request: { _ in XCTFail("No credentials must mean no request"); return Data() }, scope: { nil })
        do { _ = try await service.apps(); XCTFail("Expected no-team error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("select")) }
    }

    func testSuggestionsAreBoundedAndDoNotEagerlyFetchBuilds() async throws {
        var methods: [APIMethod] = []
        let service = ShipyardIntentService(request: { method in
            methods.append(method)
            return try self.appsPage(["100", "200"])
        }, scope: { self.account })
        let result = try await service.apps()
        XCTAssertEqual(result.map(\.name), ["App 100", "App 200"])
        XCTAssertEqual(methods.count, 1)
        XCTAssertEqual(methods[0].httpMethod.0, "GET")
        XCTAssertEqual(query(methods[0]), ["fields[apps]": "name,bundleId", "limit": String(AppConfigs.shortcutSuggestionsLimit)])
    }

    func testSearchReachesServerNameAndBundleIDMatchesAndDeduplicates() async throws {
        var methods: [APIMethod] = []
        let service = ShipyardIntentService(request: { method in
            methods.append(method)
            return try self.appsPage(self.query(method)["filter[bundleId]"] == nil ? ["100"] : ["100", "200"])
        }, scope: { self.account })
        let result = try await service.apps(matching: "  com.example  ")
        XCTAssertEqual(result.map { ShipyardIntentScope.reference($0.id)?.appID }, ["100", "200"])
        XCTAssertEqual(methods.count, 2)
        XCTAssertEqual(query(methods[0])["filter[name]"], "com.example")
        XCTAssertEqual(query(methods[1])["filter[bundleId]"], "com.example")
        XCTAssertNil(query(methods[1])["filter[name]"])
    }

    func testResolveRefreshesNamesAndPreservesOrderWithoutDuplicateRequests() async throws {
        var paths: [String] = []
        let service = ShipyardIntentService(request: { method in
            paths.append(method.apiPath)
            let id = method.apiPath.hasSuffix("200") ? "200" : "100"
            return try JSONSerialization.data(withJSONObject: ["data": ["type": "apps", "id": id,
                "attributes": ["name": "Renamed \(id)", "bundleId": "com.example.\(id)"]]])
        }, scope: { self.account })
        let result = try await service.resolve([account.identifier(appID: "200"), "bad", app.id, app.id])
        XCTAssertEqual(result.map(\.name), ["Renamed 200", "Renamed 100"])
        XCTAssertEqual(paths, ["/200", "/100"])
    }

    func testSavedAppFromAnotherAccountIsRejectedBeforeNetworkAccess() async {
        let service = ShipyardIntentService(request: { _ in XCTFail("Wrong team must not send a request"); return Data() },
            scope: { ShipyardIntentScope(teamName: self.account.teamName, issuerID: "issuer-b") })
        do { _ = try await service.latestBuild(for: app); XCTFail("Expected wrong-team error") }
        catch { XCTAssertTrue(error.localizedDescription.contains(account.teamName)) }
    }

    func testLatestBuildReturnsStructuredSnapshotAndUsesNewestUpload() async throws {
        var methods: [APIMethod] = []
        let service = ShipyardIntentService(request: { method in
            methods.append(method)
            return try self.buildPage()
        }, scope: { self.account })
        let result = try await service.latestBuild(for: app)
        XCTAssertEqual(result.version, "2.1")
        XCTAssertEqual(result.buildNumber, "9")
        XCTAssertEqual(result.processingStatus, "VALID")
        XCTAssertEqual(result.platform, "MAC_OS")
        XCTAssertEqual(result.buildID, "build-9")
        XCTAssertNotNil(result.uploadDate)
        XCTAssertTrue(result.expired)
        XCTAssertEqual(methods.count, 1)
        XCTAssertEqual(methods[0].httpMethod.0, "GET")
        XCTAssertEqual(query(methods[0])["filter[app]"], "100")
        XCTAssertEqual(query(methods[0])["sort"], "-uploadedDate")
        XCTAssertEqual(query(methods[0])["limit"], "1")
        XCTAssertEqual(query(methods[0])["include"], "preReleaseVersion")
        XCTAssertNil(query(methods[0])["filter[expired]"], "Expired newest uploads must not silently select an older build")
    }

    func testBuildWithoutPrereleaseVersionStillReturnsStatus() async throws {
        let service = ShipyardIntentService(request: { _ in try self.buildPage(hasVersion: false) }, scope: { self.account })
        let result = try await service.latestBuild(for: app)
        XCTAssertEqual(result.version, "Not available")
        XCTAssertEqual(result.processingStatus, "VALID")
    }

    func testMalformedPayloadUsesUnexpectedResponseError() async {
        let service = ShipyardIntentService(request: { _ in Data("{}".utf8) }, scope: { self.account })
        do { _ = try await service.latestBuild(for: app); XCTFail("Expected decoding failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("unexpected response")) }
        do { _ = try await service.apps(); XCTFail("Expected decoding failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("unexpected response")) }
    }

    func testNoBuildsHasActionableError() async {
        let service = ShipyardIntentService(request: { _ in try self.buildPage(hasBuild: false) }, scope: { self.account })
        do { _ = try await service.latestBuild(for: app); XCTFail("Expected no-builds error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("no uploaded TestFlight builds")) }
    }

    func testPermissionFailureUsesTestFlightPermissionsHint() async {
        let service = ShipyardIntentService(request: { _ in throw APIError.httpError(statusCode: 403) }, scope: { self.account })
        do { _ = try await service.latestBuild(for: app); XCTFail("Expected permissions error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("TestFlight access")) }
    }

    func testTeamSwitchDuringRequestDropsLateResponse() async throws {
        var current: ShipyardIntentScope? = account
        let service = ShipyardIntentService(request: { _ in
            current = ShipyardIntentScope(teamName: "Other", issuerID: "issuer-b")
            return try self.buildPage()
        }, scope: { current })
        do { _ = try await service.latestBuild(for: app); XCTFail("Expected stale-response error") }
        catch { XCTAssertTrue(error.localizedDescription.contains(account.teamName)) }
    }

    func testCancelledRequestDoesNotReturnBuild() async throws {
        let service = ShipyardIntentService(request: { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return try self.buildPage()
        }, scope: { self.account })
        let task = Task { try await service.latestBuild(for: app) }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testOpenAppFetchesAuthoritativeAppWithoutChangingTeam() async throws {
        var methods: [APIMethod] = []
        let service = ShipyardIntentService(request: { method in
            methods.append(method)
            return Data(#"{"data":{"type":"apps","id":"100","attributes":{"name":"Renamed App","bundleId":"com.example.shipyard"},"relationships":{"appStoreVersions":{"data":[]},"appStoreIcon":{"data":null}}}}"#.utf8)
        }, scope: { self.account })
        let (result, scope) = try await service.appToOpen(app)
        XCTAssertEqual(result.name, "Renamed App")
        XCTAssertEqual(scope, account)
        XCTAssertEqual(methods[0].httpMethod.0, "GET")
        XCTAssertEqual(methods[0].apiPath, "/100")
    }

    func testNavigationKeepsColdStartRequestAndConsumesLatestOnlyOnce() throws {
        let navigation = ShipyardIntentNavigation()
        var presented = 0
        navigation.open(AppsData(id: "100", appStoreVersions: []), scope: account)
        XCTAssertNotNil(navigation.pending, "The scene may not exist yet")
        navigation.presentWindow = { presented += 1 }
        navigation.open(AppsData(id: "200", appStoreVersions: []), scope: account)
        XCTAssertEqual(presented, 1)
        XCTAssertEqual(try navigation.takeRequest(in: account)?.id, "200")
        XCTAssertNil(try navigation.takeRequest(in: account))
        navigation.open(AppsData(id: "100", appStoreVersions: []), scope: account)
        XCTAssertThrowsError(try navigation.takeRequest(in: nil))
        XCTAssertNil(navigation.pending, "A request for a removed team must not reopen stale content later")
    }

    private func query(_ method: APIMethod) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (method.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }
}
