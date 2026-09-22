//
//  APIMethodTests.swift
//  App Store Tests
//
//  Batch I (I8): APIMethod path composition (empty vs non-empty path) and
//  query-item mapping (nil vs empty params). Pure logic — exercises the
//  pieces APIClient.getURL composes, without credentials or network.
//

import XCTest
import Foundation
@testable import App_Store

final class APIMethodTests: XCTestCase {
    func testGetPathEmpty() {
        XCTAssertEqual(APIMethod.get(name: .devices).apiPath, "")
    }

    func testGetPathComposed() {
        // App-scoped subpath: /v1/apps/{id}/appInfos.
        XCTAssertEqual(
            APIMethod.get(name: .getAllApps, path: "abc123/appInfos").apiPath,
            "/abc123/appInfos"
        )
    }

    func testPatchPathComposed() {
        XCTAssertEqual(
            APIMethod.patch(name: .getBundleIds, body: Data(), path: "bundle-id-1").apiPath,
            "/bundle-id-1"
        )
    }

    func testDeletePathComposed() {
        XCTAssertEqual(
            APIMethod.delete(name: .getUsers, path: "user-id-1").apiPath,
            "/user-id-1"
        )
    }

    func testPostPathComposed() {
        XCTAssertEqual(
            APIMethod.post(name: .userInvitations, body: Data()).apiPath,
            ""
        )
    }

    func testQueryItemsEmpty() {
        // Empty params must produce no query items (no trailing "?" in URLs).
        XCTAssertEqual(APIMethod.get(name: .devices).queryItems, [])
        XCTAssertEqual(APIMethod.get(name: .devices, queryParams: [:]).queryItems, [])
    }

    func testQueryItemsMapped() {
        let items = APIMethod.get(
            name: .getBetaTesters,
            queryParams: ["filter[email]": "a@b.com", "limit": "1"]
        ).queryItems ?? []
        let mapped = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(mapped["filter[email]"], "a@b.com")
        XCTAssertEqual(mapped["limit"], "1")
    }

    func testHttpMethods() {
        XCTAssertEqual(APIMethod.get(name: .devices).httpMethod.0, "GET")
        XCTAssertEqual(APIMethod.post(name: .devices, body: Data()).httpMethod.0, "POST")
        XCTAssertEqual(APIMethod.patch(name: .devices, body: Data(), path: "1").httpMethod.0, "PATCH")
        XCTAssertEqual(APIMethod.delete(name: .devices, path: "1").httpMethod.0, "DELETE")
    }

    func testWriteRouteRawValues() {
        // Batch I write routes: bundleIds reuse the collection case across
        // verbs; invitations and version localizations have their own cases.
        XCTAssertEqual(APIName.getBundleIds.rawValue, "/bundleIds")
        XCTAssertEqual(APIName.userInvitations.rawValue, "/userInvitations")
        XCTAssertEqual(APIName.appStoreVersionLocalizations.rawValue, "/appStoreVersionLocalizations")
        XCTAssertEqual(APIName.getBetaGroups.rawValue, "/betaGroups")
        XCTAssertEqual(APIName.getBetaTesters.rawValue, "/betaTesters")
        XCTAssertEqual(APIName.getProfiles.rawValue, "/profiles")
        XCTAssertEqual(APIName.getUsers.rawValue, "/users")
    }

    // TEMPORARY (matches the temporary live-token logging): asserts the
    // token is present for debugging while emails stay redacted. Update
    // alongside the logging when it is removed before merge.
    func testCurlCommandKeepsTokenRedactsEmail() {
        var request = URLRequest(url: URL(string: "https://api.appstoreconnect.apple.com/v1/users")!)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = [
            "Content-Type": "application/json",
            "Authorization": "Bearer live-token-value",
        ]
        request.httpBody = Data(#"{"email":"tester@example.com"}"#.utf8)
        let curl = APIClient.curlCommand(for: request)
        XCTAssertTrue(curl.hasPrefix("curl -X POST"))
        XCTAssertTrue(curl.contains("https://api.appstoreconnect.apple.com/v1/users"))
        XCTAssertTrue(curl.contains("Bearer live-token-value"))
        XCTAssertFalse(curl.contains("<TOKEN>"))
        XCTAssertTrue(curl.contains("[redacted]"))
        XCTAssertFalse(curl.contains("tester@example.com"))
    }
}
