//
//  ViewStateTests.swift
//  App Store Tests
//
//  Batch I (I8): ViewState transitions and accessor coverage. Pure logic,
//  no API key or keychain needed.
//

import XCTest
@testable import Shipyard

@MainActor
final class InitialBuildVersionTests: XCTestCase {
    private let latest = Data(#"{"data":[{"type":"builds","relationships":{"preReleaseVersion":{"data":{"type":"preReleaseVersions","id":"recent-upload"}}}}],"included":[{"type":"preReleaseVersions","id":"recent-upload","attributes":{"version":"1.5","platform":"MAC_OS"}}]}"#.utf8)
    private let emptyBuilds = Data(#"{"data":[],"meta":{"paging":{"total":0,"limit":5}}}"#.utf8)

    private func model(request: @escaping DetailViewModel.BuildsRequest) async -> DetailViewModel {
        let sidebar = SideBarViewModel()
        let model = DetailViewModel(sidebarViewModel: sidebar, readsStoredTeam: false, buildsRequest: request)
        sidebar.selectedApp = AppsData(id: "app", appStoreVersions: [])
        await eventually { model.selectedApp?.id == "app" }
        model.versionsState = .loaded([PreReleaseVersionsModel(id: "highest-version")])
        return model
    }

    func testSelectsNewestUploadInsteadOfFirstVersionAndLoadsItsBuilds() async {
        var methods: [APIMethod] = []
        let model = await model { method in
            methods.append(method)
            return self.query(method)["limit"] == "1" ? self.latest : self.emptyBuilds
        }
        await model.selectInitialBuildVersionIfNeeded()
        await eventually { methods.count == 2 && model.buildsState == .empty }
        XCTAssertEqual(model.selectedVersion?.id, "recent-upload")
        XCTAssertEqual(model.selectedVersion?.version, "1.5")
        XCTAssertEqual(model.selectedVersion?.platform, "MAC_OS")
        XCTAssertEqual(query(methods[0]), [
            "filter[app]": "app", "sort": "-uploadedDate", "limit": "1",
            "include": "preReleaseVersion", "fields[builds]": "preReleaseVersion",
            "fields[preReleaseVersions]": "version,platform"
        ])
        XCTAssertEqual(query(methods[1])["filter[preReleaseVersion]"], "recent-upload")
        await model.selectInitialBuildVersionIfNeeded()
        XCTAssertEqual(methods.count, 2, "Returning to Builds must preserve the chosen version")
    }

    func testManualSelectionWhileDefaultLoadsWins() async {
        var pending: CheckedContinuation<Data, Error>?
        let model = await model { method in
            if self.query(method)["limit"] == "1" {
                return try await withCheckedThrowingContinuation { pending = $0 }
            }
            return self.emptyBuilds
        }
        let task = Task { await model.selectInitialBuildVersionIfNeeded() }
        await eventually { pending != nil }
        model.setSelectedVersionAndGetBuilds(selectedVersion: PreReleaseVersionsModel(id: "manual"))
        pending?.resume(returning: latest)
        await task.value
        XCTAssertEqual(model.selectedVersion?.id, "manual")
    }

    func testAppSwitchDiscardsLateDefault() async {
        var pending: CheckedContinuation<Data, Error>?
        let model = await model { _ in
            try await withCheckedThrowingContinuation { pending = $0 }
        }
        let task = Task { await model.selectInitialBuildVersionIfNeeded() }
        await eventually { pending != nil }
        model.activateAppForDetail(AppsData(id: "other", appStoreVersions: []))
        pending?.resume(returning: latest)
        await task.value
        XCTAssertNil(model.selectedVersion)
        XCTAssertEqual(model.buildsState, .idle)
    }

    func testTeamResetDiscardsLateDefaultForSameApp() async {
        var pending: CheckedContinuation<Data, Error>?
        let model = await model { _ in
            try await withCheckedThrowingContinuation { pending = $0 }
        }
        let task = Task { await model.selectInitialBuildVersionIfNeeded() }
        await eventually { pending != nil }
        model.resetForTeamSwitch()
        model.activateAppForDetail(AppsData(id: "app", appStoreVersions: []))
        pending?.resume(returning: latest)
        await task.value
        XCTAssertNil(model.selectedVersion)
        XCTAssertEqual(model.buildsState, .idle)
    }

    func testNoUploadsStopsLoadingWithoutSelectingUnrelatedVersion() async {
        let model = await model { _ in self.emptyBuilds }
        await model.selectInitialBuildVersionIfNeeded()
        XCTAssertNil(model.selectedVersion)
        XCTAssertEqual(model.buildsState, .empty)
    }

    func testFailureCanRetryAndUsesPermissionsHint() async {
        var denied = true
        let model = await model { method in
            if denied { throw APIError.httpError(statusCode: 403) }
            return self.query(method)["limit"] == "1" ? self.latest : self.emptyBuilds
        }
        await model.selectInitialBuildVersionIfNeeded()
        XCTAssertTrue(model.buildsErrorMessage?.contains("TestFlight access") == true)
        denied = false
        await model.selectInitialBuildVersionIfNeeded()
        XCTAssertEqual(model.selectedVersion?.id, "recent-upload")
    }

    func testMalformedVersionDoesNotLeaveSpinnerRunning() async {
        let model = await model { _ in Data(#"{"data":[{"type":"builds"}]}"#.utf8) }
        await model.selectInitialBuildVersionIfNeeded()
        XCTAssertNil(model.selectedVersion)
        XCTAssertNotNil(model.buildsErrorMessage)
        XCTAssertFalse(model.isBuildsLoading)
    }

    func testCancelledSelectionDoesNotApplyLateResultOrKeepSpinner() async {
        var pending: CheckedContinuation<Data, Error>?
        let model = await model { _ in
            try await withCheckedThrowingContinuation { pending = $0 }
        }
        let task = Task { await model.selectInitialBuildVersionIfNeeded() }
        await eventually { pending != nil }
        task.cancel()
        pending?.resume(returning: latest)
        await task.value
        XCTAssertNil(model.selectedVersion)
        XCTAssertEqual(model.buildsState, .idle)
    }

    private func query(_ method: APIMethod) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (method.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { await Task.yield() }
        XCTAssertTrue(condition(), "Expected async state transition", file: file, line: line)
    }
}

final class ViewStateTests: XCTestCase {
    func testIdleAccessors() {
        let state = ViewState<[String]>.idle
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.loadedValue)
        XCTAssertNil(state.errorMessage)
    }

    func testLoadingAccessor() {
        let state = ViewState<[String]>.loading
        XCTAssertTrue(state.isLoading)
        XCTAssertNil(state.loadedValue)
        XCTAssertNil(state.errorMessage)
    }

    func testLoadedValue() {
        let state = ViewState<[String]>.loaded(["a", "b"])
        XCTAssertFalse(state.isLoading)
        XCTAssertEqual(state.loadedValue, ["a", "b"])
        XCTAssertNil(state.errorMessage)
    }

    func testEmptyAccessors() {
        let state = ViewState<[String]>.empty
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.loadedValue)
        XCTAssertNil(state.errorMessage)
    }

    func testErrorMessage() {
        let state = ViewState<[String]>.error("No team selected.")
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.loadedValue)
        XCTAssertEqual(state.errorMessage, "No team selected.")
    }

    func testEquality() {
        XCTAssertEqual(ViewState<[String]>.idle, .idle)
        XCTAssertEqual(ViewState<[String]>.loading, .loading)
        XCTAssertEqual(ViewState<[String]>.empty, .empty)
        XCTAssertEqual(ViewState<[String]>.loaded(["x"]), .loaded(["x"]))
        XCTAssertEqual(ViewState<[String]>.error("boom"), .error("boom"))
        XCTAssertNotEqual(ViewState<[String]>.idle, .loading)
        XCTAssertNotEqual(ViewState<[String]>.loaded(["x"]), .loaded(["y"]))
        XCTAssertNotEqual(ViewState<[String]>.error("a"), .error("b"))
        XCTAssertNotEqual(ViewState<[String]>.empty, .error("a"))
    }
}

@MainActor
final class AppStoreVersionsPreloadTests: XCTestCase {
    private func app(_ id: String = "app") -> AppsData {
        AppsData(id: id, appStoreVersions: [])
    }

    private func page(_ ids: [String], cursor: String? = nil) throws -> Data {
        var paging: [String: Any] = ["total": ids.count, "limit": 200]
        paging["nextCursor"] = cursor
        return try JSONSerialization.data(withJSONObject: [
            "data": ids.map { ["type": "appStoreVersions", "id": $0,
                "attributes": ["versionString": "1.0", "platform": "IOS", "appStoreState": "READY_FOR_SALE"],
                "relationships": ["appStoreVersionLocalizations": ["data": []]]] as [String: Any] },
            "meta": ["paging": paging]
        ])
    }

    func testPreloadAndForegroundShareOneRequestAndCachedResult() async throws {
        let gate = Gate()
        let model = ReviewsViewModel(appStoreVersionsRequest: gate.request)
        model.preloadAppStoreVersions(app: app())
        model.preloadAppStoreVersions(app: app())
        model.load(appId: "app")
        await eventually { gate.pending.count == 1 }
        XCTAssertEqual(gate.methods.first?.apiPath, "/app/appStoreVersions")
        XCTAssertEqual(model.reviewsState, .idle, "Preloading versions must not load customer reviews")
        XCTAssertEqual(model.submissionsState, .idle, "Preloading versions must not load review submissions")
        gate.finish(0, data: try page(["v1"]))
        await eventually { model.appStoreVersionsState.loadedValue?.count == 1 }
        model.preloadAppStoreVersions(app: app())
        model.load(appId: "app")
        await Task.yield()
        XCTAssertEqual(gate.methods.count, 1)
        XCTAssertEqual(model.appStoreVersionsState.loadedValue?.map(\.id), ["v1"])
    }

    func testExpiredCacheRevalidatesWithoutHidingVersions() async throws {
        let gate = Gate()
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = ReviewsViewModel(appStoreVersionsRequest: gate.request, cacheNow: { now })
        model.preloadAppStoreVersions(app: app())
        await eventually { gate.pending.count == 1 }
        gate.finish(0, data: try page(["v1"]))
        await eventually { model.appStoreVersionsState.loadedValue != nil }
        now = now.addingTimeInterval(AppConfigs.appStoreVersionsCacheLifetime)
        model.preloadAppStoreVersions(app: app())
        await eventually { gate.pending.count == 2 }
        XCTAssertEqual(model.appStoreVersionsState.loadedValue?.map(\.id), ["v1"])
        gate.finish(1, data: try page(["v2"]))
        await eventually { model.appStoreVersionsState.loadedValue?.first?.id == "v2" }
    }

    func testEmptyResultIsCachedAndForceRefreshBypassesLifetime() async throws {
        let gate = Gate()
        let model = ReviewsViewModel(appStoreVersionsRequest: gate.request)
        model.preloadAppStoreVersions(app: app())
        await eventually { gate.pending.count == 1 }
        gate.finish(0, data: try page([]))
        await eventually { model.appStoreVersionsState == .empty }
        model.preloadAppStoreVersions(app: app())
        await Task.yield()
        XCTAssertEqual(gate.methods.count, 1)
        model.load(appId: "app", force: true)
        await eventually { gate.pending.count == 2 }
        gate.finish(1, data: try page(["created-version"]))
        await eventually { model.appStoreVersionsState.loadedValue?.first?.id == "created-version" }
    }

    func testFailedPreloadCanRetryWithoutWaitingForExpiry() async throws {
        let gate = Gate()
        let model = ReviewsViewModel(appStoreVersionsRequest: gate.request)
        model.preloadAppStoreVersions(app: app())
        await eventually { gate.pending.count == 1 }
        gate.fail(0)
        await eventually { model.appStoreVersionsState.errorMessage != nil }
        model.preloadAppStoreVersions(app: app())
        await eventually { gate.pending.count == 2 }
        gate.finish(1, data: try page(["retried"]))
        await eventually { model.appStoreVersionsState.loadedValue?.first?.id == "retried" }
    }

    func testAppAndTeamChangesDiscardCachedAndLateResults() async throws {
        let gate = Gate()
        let model = ReviewsViewModel(appStoreVersionsRequest: gate.request)
        model.preloadAppStoreVersions(app: app("a"))
        await eventually { gate.pending.count == 1 }
        model.preloadAppStoreVersions(app: app("b"))
        await eventually { gate.pending.count == 2 }
        gate.finish(1, data: try page(["b-version"]))
        await eventually { model.appStoreVersionsState.loadedValue != nil }
        gate.finish(0, data: try page(["late-a-version"]))
        await Task.yield()
        XCTAssertEqual(model.appStoreVersionsState.loadedValue?.map(\.id), ["b-version"])
        model.resetForTeamSwitch()
        XCTAssertEqual(model.appStoreVersionsState, .idle)
        model.preloadAppStoreVersions(app: app("b"))
        await eventually { gate.pending.count == 3 }
        gate.finish(2, data: try page(["new-team-version"]))
        await eventually { model.appStoreVersionsState.loadedValue?.first?.id == "new-team-version" }
    }

    func testPreloadPreservesPaginationQueryAcrossPages() async throws {
        let gate = Gate()
        let model = ReviewsViewModel(appStoreVersionsRequest: gate.request)
        model.preloadAppStoreVersions(app: app())
        await eventually { gate.pending.count == 1 }
        gate.finish(0, data: try page(["v1"], cursor: "next+page="))
        await eventually { gate.pending.count == 2 }
        let first = Dictionary(uniqueKeysWithValues: (gate.methods[0].queryItems ?? []).map { ($0.name, $0.value) })
        var second = Dictionary(uniqueKeysWithValues: (gate.methods[1].queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(second.removeValue(forKey: "cursor"), "next+page=")
        XCTAssertEqual(first, second)
        gate.finish(1, data: try page(["v2"]))
        await eventually { model.appStoreVersionsState.loadedValue?.count == 2 }
        model.preloadAppStoreVersions(app: app())
        await Task.yield()
        XCTAssertEqual(gate.methods.count, 2)
    }

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { await Task.yield() }
        XCTAssertTrue(condition(), "Expected async state transition", file: file, line: line)
    }

    @MainActor
    private final class Gate {
        var methods: [APIMethod] = []
        var pending: [CheckedContinuation<Data, Error>?] = []
        var request: ReviewsViewModel.AppStoreVersionsRequest {
            { method in
                self.methods.append(method)
                return try await withCheckedThrowingContinuation { self.pending.append($0) }
            }
        }
        func finish(_ index: Int, data: Data) {
            guard pending.indices.contains(index), let continuation = pending[index] else {
                return XCTFail("Missing pending versions request")
            }
            pending[index] = nil
            continuation.resume(returning: data)
        }
        func fail(_ index: Int) {
            guard pending.indices.contains(index), let continuation = pending[index] else {
                return XCTFail("Missing pending versions request")
            }
            pending[index] = nil
            continuation.resume(throwing: URLError(.notConnectedToInternet))
        }
    }
}

@MainActor
final class AppStoreListingTests: XCTestCase {
    private func version(_ id: String, _ number: String, _ state: String, platform: String = "IOS") -> AppStoreVersionsModel {
        var version = AppStoreVersionsModel(id: id, appStoreVersionLocalizations: [])
        version.versionString = number
        version.appStoreState = state
        version.platform = platform
        return version
    }

    func testLiveAndUpcomingAreIndependentOfResponseOrderAndOldDrafts() {
        let versions = [version("old-draft", "1.0", "PREPARE_FOR_SUBMISSION"),
                        version("pending", "6.5.1", "PENDING_DEVELOPER_RELEASE"),
                        version("old-live", "6.4.9", "READY_FOR_SALE"),
                        version("live", "6.5.0", "READY_FOR_SALE")]
        for values in [versions, Array(versions.reversed())] {
            let summary = AppStoreListingSummary(versions: values)
            XCTAssertEqual(summary.primaryVersion?.id, "live")
            XCTAssertEqual(summary.platforms.first?.live?.versionString, "6.5.0")
            XCTAssertEqual(summary.platforms.first?.upcoming?.versionString, "6.5.1")
        }
    }

    func testNumericVersionsAndPlatformBoundaries() {
        let summary = AppStoreListingSummary(versions: [
            version("ios9", "1.9", "READY_FOR_SALE"), version("ios10", "1.10", "READY_FOR_SALE"),
            version("mac", "5.0", "PREPARE_FOR_SUBMISSION", platform: "MAC_OS")])
        XCTAssertEqual(summary.platforms.first(where: { $0.id == "IOS" })?.live?.id, "ios10")
        XCTAssertNil(summary.platforms.first(where: { $0.id == "MAC_OS" })?.live)
        XCTAssertEqual(summary.platforms.first(where: { $0.id == "MAC_OS" })?.upcoming?.id, "mac")
    }

    func testOldDraftCannotReplaceLiveAndPendingAppleReleaseIsNotLive() {
        let summary = AppStoreListingSummary(versions: [
            version("draft", "1.0", "PREPARE_FOR_SUBMISSION"),
            version("live", "2.0", "READY_FOR_DISTRIBUTION"),
            version("apple", "2.1", "PENDING_APPLE_RELEASE")])
        XCTAssertEqual(summary.platforms.first?.live?.id, "live")
        XCTAssertEqual(summary.platforms.first?.upcoming?.id, "apple")
        XCTAssertNil(AppStoreListingSummary(versions: [version("apple", "2.1", "PENDING_APPLE_RELEASE")]).platforms.first?.live)
    }

    func testEmptyRemovedAndUnknownStatesDoNotBecomeLive() {
        XCTAssertTrue(AppStoreListingSummary(versions: []).platforms.isEmpty)
        for state in ["REMOVED_FROM_SALE", "REPLACED_WITH_NEW_VERSION", "NEW_SERVER_STATE"] {
            let summary = AppStoreListingSummary(versions: [version("other", "1.0", state)])
            XCTAssertNil(summary.platforms.first?.live)
            XCTAssertNil(summary.platforms.first?.upcoming)
            XCTAssertEqual(summary.platforms.first?.other?.id, "other")
        }
    }

    private func page(_ id: String, _ number: String, _ state: String, cursor: String? = nil) -> Data {
        let next = cursor.map { "\"\($0)\"" } ?? "null"
        return Data("""
        {"data":[{"type":"appStoreVersions","id":"\(id)","attributes":{"versionString":"\(number)","platform":"IOS","appStoreState":"\(state)"}}],"meta":{"paging":{"nextCursor":\(next)}}}
        """.utf8)
    }

    func testLoadsEveryAppStorePageWithoutBuildsOrTestFlight() async {
        var methods: [APIMethod] = []
        let model = SideBarViewModel { method in
            methods.append(method)
            if methods.count == 1 {
                return Data(#"{"data":[{"type":"appStoreVersions","id":"draft","attributes":{"versionString":"1.0","platform":"IOS","appStoreState":"PREPARE_FOR_SUBMISSION"}}],"links":{"next":"https://api.appstoreconnect.apple.com/v1/apps/sun-sand/appStoreVersions?cursor=store-next"}}"#.utf8)
            }
            return self.page("live", "6.5.0", "READY_FOR_SALE")
        }
        await model.loadListingVersions(appID: "sun-sand")
        let versions = model.listingVersionStates["sun-sand"]?.loadedValue ?? []
        XCTAssertEqual(versions.count, 2)
        XCTAssertEqual(AppStoreListingSummary(versions: versions).primaryVersion?.id, "live")
        XCTAssertEqual(methods.map(\.apiPath), ["/sun-sand/appStoreVersions", "/sun-sand/appStoreVersions"])
        let query = Dictionary(uniqueKeysWithValues: (methods[1].queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["cursor"], "store-next")
        XCTAssertEqual(query["limit"], "200")
        XCTAssertNil(query["include"], "The list must not fetch TestFlight builds or localization content")
    }

    func testFailedLaterPageDoesNotPresentPartialDataAsAuthoritative() async {
        var count = 0
        let model = SideBarViewModel { _ in
            count += 1
            if count == 1 { return self.page("draft", "1.0", "PREPARE_FOR_SUBMISSION", cursor: "next") }
            throw URLError(.notConnectedToInternet)
        }
        await model.loadListingVersions(appID: "app")
        XCTAssertNotNil(model.listingVersionStates["app"]?.errorMessage)
        XCTAssertNil(model.listingVersionStates["app"]?.loadedValue)
    }

    func testLogoutDiscardsLateSummaryResponse() async {
        var pending: CheckedContinuation<Data, Error>?
        let model = SideBarViewModel { _ in
            try await withCheckedThrowingContinuation { pending = $0 }
        }
        let task = Task { await model.loadListingVersions(appID: "old-team-app") }
        for _ in 0..<100 where pending == nil { await Task.yield() }
        XCTAssertNotNil(pending)
        model.clearOnLogout()
        pending?.resume(returning: page("live", "1.0", "READY_FOR_SALE"))
        await task.value
        XCTAssertTrue(model.listingVersionStates.isEmpty)
    }
}
