import XCTest
@testable import Shipyard

@MainActor
final class BetaFeedbackTests: XCTestCase {
    private func page(_ ids: [String], kind: BetaFeedbackKind = .screenshots, cursor: String? = nil) throws -> Data {
        var doc: [String: Any] = ["data": ids.map { ["type": kind.rawValue, "id": $0, "attributes": ["comment": "Note \($0)"]] }]
        if let cursor { doc["meta"] = ["paging": ["limit": 50, "nextCursor": cursor]] }
        return try JSONSerialization.data(withJSONObject: doc)
    }

    func testSparseIncludedResourcesAndOptionalPaging() throws {
        let json = #"{"data":[{"type":"betaFeedbackScreenshotSubmissions","id":"s1","attributes":{"comment":"Clipped text","screenshots":[{"url":"https://example.invalid/image.png","expirationDate":"2026-10-15T00:00:00.000Z"}],"appUptimeInMilliseconds":9007199254740991},"relationships":{"build":{"data":{"type":"builds","id":"b1"}},"tester":{"data":{"type":"betaTesters","id":"t1"}}}}],"included":[{"type":"builds","id":"b1","attributes":{"version":"42"}},{"type":"betaTesters","id":"t1","attributes":{"firstName":"Alex","lastName":"Morgan","email":"alex@example.invalid"}}],"links":{"next":"https://example.invalid/ignored?cursor=a%2Bb%3D"}}"#
        let result = try BetaFeedbackPage.decode(Data(json.utf8), kind: .screenshots)
        let item = try XCTUnwrap(result.items.first)
        XCTAssertEqual(item.buildNumber, "42")
        XCTAssertEqual(item.tester, "Alex Morgan")
        XCTAssertEqual(item.email, "alex@example.invalid")
        XCTAssertEqual(item.attributes.appUptimeInMilliseconds, 9007199254740991)
        XCTAssertEqual(result.nextCursor, "a+b=")
        XCTAssertNil(result.total)
        XCTAssertTrue(try XCTUnwrap(item.attributes.screenshots?.first).isExpired(at: Date(timeIntervalSince1970: 1_800_000_000)))
    }

    func testAnonymousAndLinksOnlyCrashRelationship() throws {
        let json = #"{"data":[{"type":"betaFeedbackCrashSubmissions","id":"c1","attributes":null,"relationships":{"tester":{"data":null},"crashLog":{"links":{"related":"https://example.invalid/log"}}}}]}"#
        let item = try XCTUnwrap(BetaFeedbackPage.decode(Data(json.utf8), kind: .crashes).items.first)
        XCTAssertEqual(item.tester, "Anonymous tester")
        XCTAssertEqual(item.note, "No comment provided.")
        XCTAssertNil(item.attributes.screenshots)
        XCTAssertThrowsError(try BetaFeedbackPage.decode(Data(json.utf8), kind: .screenshots))
    }

    func testScreenshotURLsRequireHTTPSAndExpirationIsOptional() throws {
        func attachment(_ url: String) throws -> BetaFeedbackScreenshot {
            try JSONDecoder().decode(BetaFeedbackScreenshot.self, from: JSONSerialization.data(withJSONObject: ["url": url]))
        }
        XCTAssertNil(try attachment("http://example.invalid/a").secureURL)
        XCTAssertNil(try attachment("file:///tmp/a").secureURL)
        XCTAssertNil(try attachment("https://user:password@example.invalid/a").secureURL)
        XCTAssertNotNil(try attachment("https://example.invalid/a").secureURL)
        XCTAssertFalse(try attachment("https://example.invalid/a").isExpired())
    }

    func testListRequestsUseVerifiedIncludesAndScopeCursors() {
        for kind in BetaFeedbackKind.allCases {
            let method = BetaFeedbackAPI.listMethod(appID: "app1", kind: kind, cursor: "opaque+cursor=")
            XCTAssertEqual(method.apiPath, "/app1/\(kind.rawValue)")
            XCTAssertEqual(method.httpMethod.0, "GET")
            let query = Dictionary(uniqueKeysWithValues: (method.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(query, ["sort": "-createdDate", "include": "build,tester", "fields[builds]": "version",
                "fields[betaTesters]": "firstName,lastName,email", "limit": "50", "cursor": "opaque+cursor="])
        }
    }

    func testIndependentPagesDeduplicationAndRetryPreservesCursor() async throws {
        var requests: [APIMethod] = []
        var fail = false
        let api = BetaFeedbackAPI(perform: { method in
            requests.append(method)
            if fail { throw URLError(.notConnectedToInternet) }
            if method.apiPath.hasSuffix(BetaFeedbackKind.crashes.rawValue) {
                return try self.page(["c1"], kind: .crashes, cursor: "crash-next")
            }
            let more = method.queryItems?.contains { $0.name == "cursor" } == true
            return try self.page(more ? ["s1", "s2"] : ["s1"], cursor: more ? nil : "screen-next")
        }, screenshot: { _ in XCTFail("List requests must not download images"); return Data() })
        let model = BetaFeedbackViewModel(api: api)
        model.activate(appID: "app", contextID: 1)
        await model.load()
        model.switchKind(.crashes)
        await model.load()
        XCTAssertEqual(model.page.nextCursor, "crash-next")
        model.switchKind(.screenshots)
        XCTAssertEqual(model.page.nextCursor, "screen-next")
        fail = true
        await model.load(more: true)
        XCTAssertEqual(model.page.items.map(\.submissionID), ["s1"])
        XCTAssertEqual(model.page.nextCursor, "screen-next")
        XCTAssertNotNil(model.page.error)
        fail = false
        await model.load(more: true)
        XCTAssertEqual(model.page.items.map(\.submissionID), ["s1", "s2"])
        XCTAssertNil(model.page.nextCursor)
        model.search = "s2"
        XCTAssertEqual(model.filteredItems.map(\.submissionID), ["s2"])
        XCTAssertEqual(requests.count, 4, "Local filters must not invalidate cursors or trigger network requests")
        fail = true
        await model.load(refresh: true)
        XCTAssertEqual(model.page.items.count, 2, "Refresh failure must retain loaded rows")
        XCTAssertFalse(model.page.isLoading)
    }

    func testContextChangeRejectsLateResponseForSameAppID() async throws {
        let gate = Gate()
        let model = BetaFeedbackViewModel(api: gate.api)
        model.activate(appID: "same-app", contextID: 1)
        let old = Task { await model.load() }
        await gate.waitForRequest(count: 1)
        model.activate(appID: "same-app", contextID: 2)
        XCTAssertTrue(model.page.items.isEmpty)
        let current = Task { await model.load() }
        await gate.waitForRequest(count: 2)
        gate.pending[1].resume(returning: try page(["new-team"]))
        await current.value
        gate.pending[0].resume(returning: try page(["old-team"]))
        await old.value
        XCTAssertEqual(model.page.items.map(\.submissionID), ["new-team"])
        XCTAssertFalse(model.page.isLoading)
    }

    func testCrashLogIsLazyAndDoesNotPublishForOldSelection() async throws {
        let gate = Gate()
        let model = BetaFeedbackViewModel(api: gate.api)
        model.activate(appID: "app", contextID: 1)
        model.switchKind(.crashes)
        let list = Task { await model.load() }
        await gate.waitForRequest(count: 1)
        gate.pending[0].resume(returning: try page(["c1", "c2"], kind: .crashes))
        await list.value
        XCTAssertEqual(gate.requests.count, 1)
        model.select(model.page.items[0].id)
        let oldLog = Task { await model.loadLog() }
        await gate.waitForRequest(count: 2)
        XCTAssertEqual(gate.requests[1].apiPath, "/c1/crashLog")
        model.select(model.page.items[1].id)
        let log = Task { await model.loadLog() }
        await gate.waitForRequest(count: 3)
        let newData = Data(#"{"data":{"type":"betaCrashLogs","attributes":{"logText":"Current log"}}}"#.utf8)
        gate.pending[2].resume(returning: newData)
        await log.value
        gate.pending[1].resume(returning: Data(#"{"data":{"type":"betaCrashLogs","attributes":{"logText":"Stale log"}}}"#.utf8))
        await oldLog.value
        XCTAssertEqual(model.logState, .loaded("Current log"))
    }

    func testPermissionFailureExplainsRequiredRoles() async {
        let model = BetaFeedbackViewModel(api: BetaFeedbackAPI(perform: { _ in
            throw APIError.apiErrorWithCode(error: "Forbidden", 403)
        }, screenshot: { _ in Data() }))
        model.activate(appID: "app", contextID: 1)
        await model.load()
        XCTAssertTrue(model.page.error?.contains("Developer, App Manager, or Admin") == true)
        XCTAssertTrue(model.page.error?.contains("broader permissions") == true)
        XCTAssertFalse(model.page.isLoading)
    }

    func testCancelledLoadDoesNotStartRequestAndCanRetry() async throws {
        var count = 0
        let data = try page(["s1"])
        let model = BetaFeedbackViewModel(api: BetaFeedbackAPI(perform: { _ in count += 1; return data }, screenshot: { _ in Data() }))
        model.activate(appID: "app", contextID: 1)
        let cancelled = Task { await model.load() }
        cancelled.cancel()
        await cancelled.value
        XCTAssertEqual(count, 0)
        XCTAssertFalse(model.page.isLoading)
        XCTAssertNil(model.page.error)
        await model.load()
        XCTAssertEqual(count, 1)
        XCTAssertEqual(model.page.items.count, 1)
    }

    func testLocalBuildAndPlatformFiltersKeepServerCursor() async throws {
        let data = Data(#"{"data":[{"type":"betaFeedbackScreenshotSubmissions","id":"s1","attributes":{"comment":"First note","appPlatform":"IOS"},"relationships":{"build":{"data":{"type":"builds","id":"b1"}}}},{"type":"betaFeedbackScreenshotSubmissions","id":"s2","attributes":{"comment":"Second note","appPlatform":"MAC_OS"},"relationships":{"build":{"data":{"type":"builds","id":"b2"}}}}],"meta":{"paging":{"limit":50,"nextCursor":"next"}}}"#.utf8)
        var count = 0
        let model = BetaFeedbackViewModel(api: BetaFeedbackAPI(perform: { _ in count += 1; return data }, screenshot: { _ in Data() }))
        model.activate(appID: "app", contextID: 1)
        await model.load()
        model.platformFilter = "MAC_OS"
        XCTAssertEqual(model.filteredItems.map(\.submissionID), ["s2"])
        model.buildFilter = "b1"
        XCTAssertTrue(model.filteredItems.isEmpty)
        model.platformFilter = "IOS"
        XCTAssertEqual(model.filteredItems.map(\.submissionID), ["s1"])
        XCTAssertEqual(model.page.nextCursor, "next")
        XCTAssertEqual(count, 1)
        model.clearFilters()
        XCTAssertEqual(model.filteredItems.count, 2)
    }

    func testCrashLogFailureCanRetryAndMissingTextIsSupported() async throws {
        var failLog = true
        var listCount = 0
        let model = BetaFeedbackViewModel(api: BetaFeedbackAPI(perform: { method in
            if method.apiPath.hasSuffix("/crashLog") {
                if failLog { throw URLError(.timedOut) }
                return Data(#"{"data":{"type":"betaCrashLogs","id":"log","attributes":{"logText":null}}}"#.utf8)
            }
            listCount += 1
            return try self.page(["c1"], kind: .crashes)
        }, screenshot: { _ in Data() }))
        model.activate(appID: "app", contextID: 1)
        model.switchKind(.crashes)
        await model.load()
        model.select(model.page.items[0].id)
        await model.loadLog()
        guard case .failed = model.logState else { return XCTFail("Expected retryable log error") }
        failLog = false
        await model.loadLog()
        XCTAssertEqual(model.logState, .loaded(nil))
        XCTAssertEqual(listCount, 1)
    }

    @MainActor
    private final class Gate {
        var pending: [CheckedContinuation<Data, Error>] = []
        var requests: [APIMethod] = []
        var api: BetaFeedbackAPI {
            BetaFeedbackAPI(perform: { method in
                self.requests.append(method)
                return try await withCheckedThrowingContinuation { self.pending.append($0) }
            }, screenshot: { _ in Data() })
        }
        func waitForRequest(count: Int) async {
            for _ in 0..<10_000 {
                if pending.count >= count { return }
                await Task.yield()
            }
            XCTFail("Request did not start")
        }
    }
}
