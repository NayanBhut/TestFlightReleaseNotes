//
//  ViewStateTests.swift
//  App Store Tests
//
//  Batch I (I8): ViewState transitions and accessor coverage. Pure logic,
//  no API key or keychain needed.
//

import XCTest
@testable import App_Store

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
