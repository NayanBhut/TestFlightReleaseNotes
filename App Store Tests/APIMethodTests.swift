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

    // The token is always redacted (even in DEBUG); emails are redacted
    // as PII — including in URL query strings (filter[email]=…).
    func testCurlCommandRedactsSecrets() {
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
        XCTAssertTrue(curl.contains("Bearer <TOKEN>"))
        XCTAssertFalse(curl.contains("live-token-value"))
        XCTAssertTrue(curl.contains("[redacted]"))
        XCTAssertFalse(curl.contains("tester@example.com"))
    }

    func testCurlCommandRedactsQueryPII() {
        // Percent-encoded email in a query value (how URLSession encodes
        // filter[email]=…): private%40example.com must still redact.
        let url = URL(string: "https://api.appstoreconnect.apple.com/v1/userInvitations?filter%5Bemail%5D=private%40example.com&limit=1")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let curl = APIClient.curlCommand(for: request)
        XCTAssertFalse(curl.contains("private%40example.com"))
        XCTAssertFalse(curl.contains("private@example.com"))
        XCTAssertTrue(curl.contains("filter%5Bemail%5D=%5Bredacted%5D") || curl.contains("filter[email]=[redacted]"))
    }
}
