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
@testable import Shipyard

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
        XCTAssertEqual(
            APIMethod.delete(name: .getAppStoreVersions, path: "version-id-1").apiPath,
            "/version-id-1"
        )
        XCTAssertEqual(
            APIMethod.delete(name: .getAppStoreVersions, path: "version-id-1").httpMethod.0,
            "DELETE"
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

    func testCreateVersionRequestEncoding() throws {
        let body = AppStoreVersionCreateRequest(
            data: AppStoreVersionCreateData(
                attributes: AppStoreVersionCreateAttributes(
                    platform: "IOS",
                    versionString: "2.1.0",
                    copyright: "© 2026 Example",
                    releaseType: "AFTER_APPROVAL"),
                relationships: AppStoreVersionCreateRelationships(
                    app: AppStoreVersionAppLinkage(
                        data: AppStoreVersionAppRef(id: "app-1")))))
        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let object = try XCTUnwrap(json["data"] as? [String: Any])
        let attributes = try XCTUnwrap(object["attributes"] as? [String: Any])
        let relationships = try XCTUnwrap(object["relationships"] as? [String: Any])
        let app = try XCTUnwrap(relationships["app"] as? [String: Any])
        let appData = try XCTUnwrap(app["data"] as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "appStoreVersions")
        XCTAssertEqual(attributes["platform"] as? String, "IOS")
        XCTAssertEqual(attributes["versionString"] as? String, "2.1.0")
        XCTAssertEqual(attributes["copyright"] as? String, "© 2026 Example")
        XCTAssertEqual(attributes["releaseType"] as? String, "AFTER_APPROVAL")
        XCTAssertEqual(appData["type"] as? String, "apps")
        XCTAssertEqual(appData["id"] as? String, "app-1")
    }

    func testBuildAttachmentRequestEncoding() throws {
        let body = AppStoreVersionBuildLinkageRequest(
            data: AppStoreVersionBuildRef(id: "build-1"))
        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let object = try XCTUnwrap(json["data"] as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "builds")
        XCTAssertEqual(object["id"] as? String, "build-1")
    }

    func testReleaseSettingsRequestEncoding() throws {
        let body = AppStoreVersionUpdateRequest(
            data: AppStoreVersionUpdateData(
                id: "version-1",
                attributes: AppStoreVersionUpdateAttributes(
                    releaseType: "SCHEDULED",
                    earliestReleaseDate: "2026-09-25T00:00:00Z")))
        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let object = try XCTUnwrap(json["data"] as? [String: Any])
        let attributes = try XCTUnwrap(object["attributes"] as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "appStoreVersions")
        XCTAssertEqual(object["id"] as? String, "version-1")
        XCTAssertEqual(attributes["releaseType"] as? String, "SCHEDULED")
        XCTAssertEqual(attributes["earliestReleaseDate"] as? String, "2026-09-25T00:00:00Z")
    }

    func testReleaseSettingsRequestEncodesCopyright() throws {
        let body = AppStoreVersionUpdateRequest(
            data: AppStoreVersionUpdateData(
                id: "version-1",
                attributes: AppStoreVersionUpdateAttributes(
                    releaseType: "MANUAL",
                    earliestReleaseDate: nil,
                    copyright: "© 2026 Example")))
        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let object = try XCTUnwrap(json["data"] as? [String: Any])
        let attributes = try XCTUnwrap(object["attributes"] as? [String: Any])
        XCTAssertEqual(attributes["copyright"] as? String, "© 2026 Example")
    }

    func testVersionLocalizationCreateRequestEncoding() throws {
        let body = VersionLocalizationCreateRequest(
            data: VersionLocalizationCreateData(
                attributes: VersionLocalizationCreateAttributes(
                    locale: "en-US",
                    descriptionData: nil,
                    keywords: nil,
                    marketingUrl: nil,
                    promotionalText: nil,
                    supportUrl: nil,
                    whatsNew: nil),
                relationships: VersionLocalizationCreateRelationships(
                    appStoreVersion: VersionLocalizationVersionLinkage(
                        data: AppStoreVersionCreateRef(id: "version-1")))))
        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let object = try XCTUnwrap(json["data"] as? [String: Any])
        let attributes = try XCTUnwrap(object["attributes"] as? [String: Any])
        let relationships = try XCTUnwrap(object["relationships"] as? [String: Any])
        let versionRelationship = try XCTUnwrap(relationships["appStoreVersion"] as? [String: Any])
        let versionData = try XCTUnwrap(versionRelationship["data"] as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "appStoreVersionLocalizations")
        XCTAssertEqual(attributes["locale"] as? String, "en-US")
        XCTAssertEqual(versionData["type"] as? String, "appStoreVersions")
        XCTAssertEqual(versionData["id"] as? String, "version-1")
    }

    func testVersionReleaseRequestEncoding() throws {
        let body = AppStoreVersionReleaseRequest(
            data: AppStoreVersionReleaseRequestData(
                relationships: AppStoreVersionReleaseRequestRelationships(
                    appStoreVersion: AppStoreVersionReleaseVersionLinkage(
                        data: AppStoreVersionCreateRef(id: "version-1")))))
        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let object = try XCTUnwrap(json["data"] as? [String: Any])
        let relationships = try XCTUnwrap(object["relationships"] as? [String: Any])
        let versionRelationship = try XCTUnwrap(relationships["appStoreVersion"] as? [String: Any])
        let versionData = try XCTUnwrap(versionRelationship["data"] as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "appStoreVersionReleaseRequests")
        XCTAssertEqual(versionData["type"] as? String, "appStoreVersions")
        XCTAssertEqual(versionData["id"] as? String, "version-1")
    }

    func testReleaseSettingsRequestEncodesNullScheduledDate() throws {
        let body = AppStoreVersionUpdateRequest(
            data: AppStoreVersionUpdateData(
                id: "version-1",
                attributes: AppStoreVersionUpdateAttributes(
                    releaseType: "AFTER_APPROVAL",
                    earliestReleaseDate: nil)))
        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let object = try XCTUnwrap(json["data"] as? [String: Any])
        let attributes = try XCTUnwrap(object["attributes"] as? [String: Any])
        XCTAssertTrue(attributes["earliestReleaseDate"] is NSNull)
        XCTAssertTrue(attributes["copyright"] is NSNull)
    }

    func testWriteRouteRawValues() {
        // Batch I write routes: bundleIds reuse the collection case across
        // verbs; invitations and version localizations have their own cases.
        XCTAssertEqual(APIName.getBundleIds.rawValue, "/bundleIds")
        XCTAssertEqual(APIName.userInvitations.rawValue, "/userInvitations")
        XCTAssertEqual(APIName.appStoreVersionLocalizations.rawValue, "/appStoreVersionLocalizations")
        XCTAssertEqual(APIName.appStoreVersionReleaseRequests.rawValue, "/appStoreVersionReleaseRequests")
        XCTAssertEqual(APIName.getBetaGroups.rawValue, "/betaGroups")
        XCTAssertEqual(APIName.getBetaTesters.rawValue, "/betaTesters")
        XCTAssertEqual(APIName.getProfiles.rawValue, "/profiles")
        XCTAssertEqual(APIName.getUsers.rawValue, "/users")
        XCTAssertEqual(APIName.merchantIds.rawValue, "/merchantIds")
        XCTAssertEqual(APIName.passTypeIds.rawValue, "/passTypeIds")
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
