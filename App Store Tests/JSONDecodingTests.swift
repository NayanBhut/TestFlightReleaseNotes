//
//  JSONDecodingTests.swift
//  App Store Tests
//
//  Batch I (I8): JSON:API document decoding from fixtures, including the
//  `description` key fix on version localizations (a bare
//  `descriptionData` mapping silently drops the field). Pure logic,
//  no API key or keychain needed.
//

import XCTest
import JSONAPI
@testable import App_Store

final class JSONDecodingTests: XCTestCase {
    func testBundleIdsDocumentDecodes() throws {
        let json = """
        {"data":[{"type":"bundleIds","id":"bundle-1","attributes":{"name":"My App","identifier":"com.example.app","platform":"IOS","seedId":"ABCD1234"}}],"meta":{"paging":{"total":1,"limit":50}}}
        """
        let model = try getDecoder().decode(BundleIdsDocument.self, from: Data(json.utf8))
        XCTAssertEqual(model.data.count, 1)
        XCTAssertEqual(model.data[0].id, "bundle-1")
        XCTAssertEqual(model.data[0].name, "My App")
        XCTAssertEqual(model.data[0].identifier, "com.example.app")
        XCTAssertEqual(model.data[0].platform, "IOS")
        XCTAssertEqual(model.meta.paging.total, 1)
    }

    func testVersionLocalizationDescriptionKeyDecodes() throws {
        // The wire attribute is `description`; the model maps it via
        // @ResourceAttribute(key:) onto `descriptionData`.
        let json = """
        {"data":[{"type":"appStoreVersionLocalizations","id":"loc-1","attributes":{"locale":"en-US","description":"A great app","keywords":"fun,game","promotionalText":"Try now","whatsNew":"Bug fixes","marketingUrl":"https://example.com","supportUrl":"https://example.com/support"}}]}
        """
        let model = try getDecoder().decode(AppStoreVersionLocalizationsDocument.self, from: Data(json.utf8))
        XCTAssertEqual(model.data.count, 1)
        XCTAssertEqual(model.data[0].descriptionData, "A great app")
        XCTAssertEqual(model.data[0].locale, "en-US")
        XCTAssertEqual(model.data[0].keywords, "fun,game")
        XCTAssertEqual(model.data[0].whatsNew, "Bug fixes")
    }

    func testVersionLocalizationMissingDescriptionIsNil() throws {
        let json = """
        {"data":[{"type":"appStoreVersionLocalizations","id":"loc-2","attributes":{"locale":"fr-FR","keywords":"jeu"}}]}
        """
        let model = try getDecoder().decode(AppStoreVersionLocalizationsDocument.self, from: Data(json.utf8))
        XCTAssertNil(model.data[0].descriptionData)
        XCTAssertEqual(model.data[0].locale, "fr-FR")
    }

    func testUsersDocumentDecodesRoles() throws {
        let json = """
        {"data":[{"type":"users","id":"user-1","attributes":{"username":"a@b.com","firstName":"Ada","lastName":"Lovelace","roles":["ADMIN","DEVELOPER"],"allAppsVisible":true,"provisioningAllowed":false}}],"meta":{"paging":{"total":1,"limit":50}}}
        """
        let model = try getDecoder().decode(UsersDocument.self, from: Data(json.utf8))
        XCTAssertEqual(model.data[0].roles, ["ADMIN", "DEVELOPER"])
        XCTAssertEqual(model.data[0].allAppsVisible, true)
    }

    func testProfilesDocumentHydratesIncludedDevicesAndCertificates() throws {
        // GET /v1/profiles?include=devices,certificates shape: linkage in
        // relationships, resources in included. The dependent-profiles
        // lookup matches on these hydrated ids.
        let json = """
        {"data":[{"type":"profiles","id":"profile-1","attributes":{"name":"Orbit Development","profileType":"IOS_APP_DEVELOPMENT","profileState":"ACTIVE"},"relationships":{"devices":{"data":[{"type":"devices","id":"device-1"}]},"certificates":{"data":[{"type":"certificates","id":"cert-1"}]}}}],"included":[{"type":"devices","id":"device-1","attributes":{"name":"Dev iPhone","platform":"IOS","udid":"00008101-001C25D40"}},{"type":"certificates","id":"cert-1","attributes":{"displayName":"Apple Development: Ada (ABC123)","certificateType":"IOS_DEVELOPMENT"}}],"meta":{"paging":{"total":1,"limit":50}}}
        """
        let model = try getDecoder().decode(ProfilesDocument.self, from: Data(json.utf8))
        XCTAssertEqual(model.data.count, 1)
        XCTAssertEqual(model.data[0].devices.map(\.id), ["device-1"])
        XCTAssertEqual(model.data[0].devices[0].udid, "00008101-001C25D40")
        XCTAssertEqual(model.data[0].certificates.map(\.id), ["cert-1"])
        XCTAssertEqual(model.data[0].certificates[0].displayName, "Apple Development: Ada (ABC123)")
        // Pure matcher used by the device detail + disable sheet.
        let matches = ResourcesViewModel.dependents(matching: "device-1", in: model.data)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].certificateNames, ["Apple Development: Ada (ABC123)"])
        XCTAssertTrue(ResourcesViewModel.dependents(matching: "device-9", in: model.data).isEmpty)
    }

    func testProfilesDocumentWithoutIncludeDecodesEmptyRelationships() throws {
        // The plain profiles list (no include) must keep decoding — empty
        // linkage yields empty arrays, same as builds without includes.
        // (The relationships key itself is always present in real
        // responses; swift-jsonapi requires it when declared.)
        let json = """
        {"data":[{"type":"profiles","id":"profile-2","attributes":{"name":"Orbit Store","profileType":"IOS_APP_STORE","profileState":"ACTIVE"},"relationships":{"devices":{"data":[]},"certificates":{"data":[]}}}],"meta":{"paging":{"total":1,"limit":50}}}
        """
        let model = try getDecoder().decode(ProfilesDocument.self, from: Data(json.utf8))
        XCTAssertEqual(model.data.count, 1)
        XCTAssertTrue(model.data[0].devices.isEmpty)
        XCTAssertTrue(model.data[0].certificates.isEmpty)
    }
}
