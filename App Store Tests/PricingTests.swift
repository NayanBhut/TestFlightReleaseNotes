import XCTest
@testable import Shipyard

@MainActor
final class PricingTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    private func model(_ api: PricingAPI) -> PricingViewModel {
        let model = PricingViewModel(api: api, now: { self.fixedNow })
        model.activate(appID: "app", contextID: 1)
        return model
    }
    private func decode(_ data: Data) throws -> PricingDocument<[PricingResource]> {
        try JSONDecoder().decode(PricingDocument<[PricingResource]>.self, from: data)
    }
    private func fixtureRows() throws -> [AppPriceRow] {
        let doc = try decode(PricingSampleServer().respond(.get(name: .appPriceSchedules, path: "schedule/manualPrices")))
        return try XCTUnwrap(doc.data).map { AppPriceRow($0, included: doc.includedByID) }
    }

    func testSparsePricesNullDatesAndExactDecimalAmounts() throws {
        let json = #"{"data":[{"type":"appPrices","id":"p1","attributes":{"manual":false,"startDate":null,"endDate":null},"relationships":{"territory":{"data":{"type":"territories","id":"JPN"}},"appPricePoint":{"data":{"type":"appPricePoints","id":"point"}}}}],"included":[{"type":"appPricePoints","id":"point","attributes":{"customerPrice":"0.00","proceeds":"0.00"}},{"type":"territories","id":"JPN","attributes":{"currency":"JPY"}}],"links":{"next":"https://example.invalid/never-follow?cursor=next%2Bpage%3D"}}"#
        let doc = try decode(Data(json.utf8))
        let resource = try XCTUnwrap(doc.data?.first)
        let row = AppPriceRow(resource, included: doc.includedByID)
        XCTAssertEqual(resource.attributes?.manual, false)
        XCTAssertEqual(row.price, "JPY 0.00")
        XCTAssertEqual(row.developerProceeds, "JPY 0.00")
        XCTAssertEqual(row.phase(on: "2026-10-16"), "Current")
        XCTAssertEqual(doc.nextCursor, "next+page=")
        XCTAssertNil(doc.meta?.paging?.total)
    }

    func testPeriodBoundariesDatesAndAmounts() {
        XCTAssertTrue(PricingDisplay.validDay("2028-02-29"))
        XCTAssertFalse(PricingDisplay.validDay("2026-02-29"))
        XCTAssertFalse(PricingDisplay.validDay("2026-1-1"))
        XCTAssertTrue(PricingDisplay.validAmount("0.00"))
        XCTAssertTrue(PricingDisplay.validAmount("999.99"))
        for invalid in ["-1", "NaN", "1.99garbage", "1,99", "", " 2.99"] {
            XCTAssertFalse(PricingDisplay.validAmount(invalid))
        }
    }

    func testWritePreservesOverridesAndClosesOnlyCurrentBasePrice() throws {
        let prices = try fixtureRows()
        let payload = try PriceScheduleChangeRequest.make(appID: "app", baseTerritory: "USA", prices: prices,
            newPointID: "usd299", startDate: "2027-02-01", today: "2027-01-15")
        let data = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try XCTUnwrap(json["included"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 3)
        let baseAttrs = try XCTUnwrap(entries[0]["attributes"] as? [String: Any])
        XCTAssertTrue(baseAttrs["startDate"] is NSNull)
        XCTAssertEqual(baseAttrs["endDate"] as? String, "2027-02-01")
        let overrideAttrs = try XCTUnwrap(entries[1]["attributes"] as? [String: Any])
        XCTAssertTrue(overrideAttrs["startDate"] is NSNull)
        XCTAssertTrue(overrideAttrs["endDate"] is NSNull)
        let overrideRel = try XCTUnwrap(entries[1]["relationships"] as? [String: Any])
        let point = try XCTUnwrap(overrideRel["appPricePoint"] as? [String: Any])
        XCTAssertEqual((point["data"] as? [String: String])?["id"], "cad299")
        let newAttrs = try XCTUnwrap(entries[2]["attributes"] as? [String: Any])
        XCTAssertEqual(newAttrs["startDate"] as? String, "2027-02-01")
        XCTAssertTrue(newAttrs["endDate"] is NSNull)
        let schedule = try XCTUnwrap(json["data"] as? [String: Any])
        let rels = try XCTUnwrap(schedule["relationships"] as? [String: Any])
        let manual = try XCTUnwrap(rels["manualPrices"] as? [String: Any])
        XCTAssertEqual((manual["data"] as? [[String: String]])?.map { $0["id"] }, entries.map { $0["id"] as? String })
    }

    func testWriteRejectsSamePricePastDateAndFutureBaseSchedules() throws {
        let prices = try fixtureRows()
        for (point, day) in [("usd199", "2027-02-01"), ("usd299", "2027-01-15"), ("usd299", "2027-02-30")] {
            XCTAssertThrowsError(try PriceScheduleChangeRequest.make(appID: "app", baseTerritory: "USA", prices: prices,
                newPointID: point, startDate: day, today: "2027-01-15"))
        }
        let server = PricingSampleServer()
        server.postedDay = "2027-02-01"; server.postedPoint = "usd299"
        let doc = try decode(server.respond(.get(name: .appPriceSchedules, path: "schedule/manualPrices")))
        let scheduled = try XCTUnwrap(doc.data).map { AppPriceRow($0, included: doc.includedByID) }
        XCTAssertNil(PriceScheduleChangeRequest.editableBasePrice(scheduled, baseTerritory: "USA", today: "2027-01-15"))
    }

    func testRequestsUseCorrectAPIVersionsAndVerifiedIncludes() throws {
        for list in PricingList.allCases {
            let (method, version) = try XCTUnwrap(PricingViewModel.listMethod(list, appID: "app", scheduleID: "schedule",
                availabilityID: "availability", baseTerritory: "USA", cursor: "opaque"))
            let query = Dictionary(uniqueKeysWithValues: (method.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(query["limit"], "50")
            XCTAssertEqual(query["cursor"], "opaque")
            XCTAssertEqual(version, list == .availability ? .v2 : .v1)
            if list == .availability {
                XCTAssertEqual(method.httpMethod.1, "/appAvailabilities")
                XCTAssertEqual(method.apiPath, "/availability/territoryAvailabilities")
            }
            XCTAssertEqual(query["include"], list == .manual || list == .automatic ? "appPricePoint,territory" : "territory")
            if list == .points { XCTAssertEqual(query["filter[territory]"], "USA") }
        }
    }

    func testLoadAndPriceChangeAreReadOnlyUntilExplicitSaveThenReconcile() async throws {
        let server = PricingSampleServer()
        let model = model(server.api)
        await model.load()
        XCTAssertEqual(model.baseTerritory, "USA")
        XCTAssertEqual(model.baseCurrency, "USD")
        XCTAssertEqual(model.priceRows.count, 2)
        XCTAssertNil(model.editBlockReason)
        await model.loadPage(.points)
        XCTAssertTrue(server.requests.allSatisfy { $0.httpMethod.0 == "GET" })
        let day = PricingDisplay.day(model.tomorrow)
        let saved = await model.scheduleChange(pointID: "usd299", day: day)
        XCTAssertTrue(saved)
        XCTAssertEqual(server.requests.filter { $0.httpMethod.0 == "POST" }.count, 1)
        XCTAssertNotNil(model.pendingChange)
        XCTAssertNotNil(model.editBlockReason)
        await model.load(refresh: true)
        XCTAssertNil(model.pendingChange)
        XCTAssertTrue(model.message?.contains("confirmed") == true)
        XCTAssertEqual(model.rows(for: .manual).count, 3)
        XCTAssertEqual(model.rows(for: .manual).first { $0.id == "canada-override" }?.pointID, "cad299")
        XCTAssertNotNil(model.editBlockReason, "Existing future schedule needs portal management")
    }

    func testStaleServerScheduleBlocksWrite() async {
        let server = PricingSampleServer()
        let model = model(server.api)
        await model.load()
        await model.loadPage(.points)
        server.postedDay = PricingDisplay.day(model.tomorrow); server.postedPoint = "usd099"
        let saved = await model.scheduleChange(pointID: "usd299", day: PricingDisplay.day(model.tomorrow))
        XCTAssertFalse(saved)
        XCTAssertTrue(model.needsReload)
        XCTAssertTrue(model.saveError?.contains("changed while you were editing") == true)
        XCTAssertFalse(server.requests.contains { $0.httpMethod.0 == "POST" })
    }

    func testUncertainSaveRequiresConfirmationAndCannotBeResent() async {
        let server = PricingSampleServer()
        let api = PricingAPI { method, _ in
            if method.httpMethod.0 == "POST" { throw URLError(.networkConnectionLost) }
            return try server.respond(method)
        }
        let model = model(api)
        await model.load(); await model.loadPage(.points)
        let day = PricingDisplay.day(model.tomorrow)
        let saved = await model.scheduleChange(pointID: "usd299", day: day)
        XCTAssertFalse(saved)
        XCTAssertNotNil(model.pendingChange)
        await model.load(refresh: true)
        XCTAssertNotNil(model.pendingChange, "An unchanged read must not confirm an uncertain save")
        let resent = await model.scheduleChange(pointID: "usd299", day: day)
        XCTAssertFalse(resent)
        server.postedDay = day; server.postedPoint = "usd299"
        await model.load(refresh: true)
        XCTAssertNil(model.pendingChange)
    }

    func testAvailabilityFalseAndUnknownStatusRemainVisible() async {
        let model = model(PricingSampleServer().api)
        await model.load()
        model.section = .availability
        await model.loadPage(.availability)
        let japan = model.territoryRows.first { $0.id == "japan-availability" }
        XCTAssertEqual(japan?.attributes?.available, false)
        XCTAssertEqual(japan?.attributes?.contentStatuses, ["MISSING_RATING"])
        model.search = "JPN"
        XCTAssertEqual(model.territoryRows.count, 1)
        model.priceMode = .automatic; model.section = .prices; model.search = ""
        await model.loadPage(.automatic)
        XCTAssertEqual(model.priceRows.first?.price, "GBP 1.49")
    }

    func testDefinitiveWritePermissionFailureKeepsDraftRetryable() async {
        let server = PricingSampleServer()
        let model = model(PricingAPI { method, _ in
            if method.httpMethod.0 == "POST" { throw APIError.httpError(statusCode: 403) }
            return try server.respond(method)
        })
        await model.load(); await model.loadPage(.points)
        let saved = await model.scheduleChange(pointID: "usd299", day: PricingDisplay.day(model.tomorrow))
        XCTAssertFalse(saved)
        XCTAssertFalse(model.saving)
        XCTAssertNil(model.pendingChange)
        XCTAssertNil(model.editBlockReason)
        XCTAssertTrue(model.saveError?.contains("broader permissions") == true)
    }

    func testTeamChangeDuringWriteCannotUpdateNewContext() async throws {
        let server = PricingSampleServer()
        var pending: CheckedContinuation<Data, Error>?
        let model = model(PricingAPI { method, _ in
            if method.httpMethod.0 == "POST" {
                return try await withCheckedThrowingContinuation { pending = $0 }
            }
            return try server.respond(method)
        })
        await model.load(); await model.loadPage(.points)
        let day = PricingDisplay.day(model.tomorrow)
        let save = Task { await model.scheduleChange(pointID: "usd299", day: day) }
        for _ in 0..<10_000 { if pending != nil { break }; await Task.yield() }
        let continuation = try XCTUnwrap(pending)
        XCTAssertNotNil(model.pendingChange)
        model.activate(appID: "new-team-app", contextID: 2)
        await model.load()
        continuation.resume(returning: Data())
        let saved = await save.value
        XCTAssertFalse(saved)
        XCTAssertEqual(model.appID, "new-team-app")
        XCTAssertNil(model.pendingChange)
        XCTAssertNil(model.message)
        XCTAssertFalse(model.saving)
        XCTAssertNil(model.editBlockReason)
    }

    func testMissingSetupAndPermissionFailuresAreDistinct() async {
        let missing = model(PricingAPI { _, _ in throw APIError.httpError(statusCode: 404) })
        await missing.load()
        XCTAssertNil(missing.scheduleError)
        XCTAssertFalse(missing.loadingCurrentHeader)
        XCTAssertNotNil(missing.editBlockReason)
        let denied = model(PricingAPI { _, _ in throw APIError.httpError(statusCode: 403) })
        await denied.load()
        XCTAssertTrue(denied.scheduleError?.contains("broader permissions") == true)
        XCTAssertNil(denied.schedule)
    }

    func testAppContextChangeRejectsLateMetadata() async throws {
        let server = PricingSampleServer()
        var pending: CheckedContinuation<Data, Error>?
        let api = PricingAPI { method, _ in
            if method.apiPath == "/old/appPriceSchedule" {
                return try await withCheckedThrowingContinuation { pending = $0 }
            }
            return try server.respond(method)
        }
        let model = PricingViewModel(api: api)
        model.activate(appID: "old", contextID: 1)
        let old = Task { await model.load() }
        for _ in 0..<10_000 { if pending != nil { break }; await Task.yield() }
        let continuation = try XCTUnwrap(pending)
        model.activate(appID: "new", contextID: 2)
        await model.load()
        continuation.resume(throwing: APIError.httpError(statusCode: 403))
        await old.value
        XCTAssertEqual(model.appID, "new")
        XCTAssertEqual(model.schedule?.id, "sample-schedule")
        XCTAssertNil(model.scheduleError)
    }

    func testPaginationFailureRetainsCursorAndRows() async throws {
        let server = PricingSampleServer()
        var fail = true
        let api = PricingAPI { method, _ in
            if method.apiPath.hasSuffix("/manualPrices") {
                if method.queryItems?.contains(where: { $0.name == "cursor" }) == true {
                    if fail { throw URLError(.timedOut) }
                    return try server.respond(method)
                }
                var json = try XCTUnwrap(JSONSerialization.jsonObject(with: server.respond(method)) as? [String: Any])
                json["meta"] = ["paging": ["limit": 50, "nextCursor": "next"]]
                return try JSONSerialization.data(withJSONObject: json)
            }
            return try server.respond(method)
        }
        let model = model(api)
        await model.load()
        XCTAssertNotNil(model.editBlockReason, "Incomplete manual prices must block a replacement schedule")
        await model.loadPage(.manual, more: true)
        XCTAssertEqual(model.page.resources.count, 2)
        XCTAssertEqual(model.page.nextCursor, "next")
        XCTAssertNotNil(model.page.error)
        fail = false
        await model.loadPage(.manual, more: true)
        XCTAssertEqual(model.page.resources.count, 2, "Repeated IDs should be deduplicated")
        XCTAssertNil(model.page.nextCursor)
        XCTAssertNil(model.editBlockReason)
    }
}
