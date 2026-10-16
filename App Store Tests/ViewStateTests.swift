//
//  ViewStateTests.swift
//  App Store Tests
//
//  Batch I (I8): ViewState transitions and accessor coverage. Pure logic,
//  no API key or keychain needed.
//

import XCTest
@testable import Shipyard

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
