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
}
