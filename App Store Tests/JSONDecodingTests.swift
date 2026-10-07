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
@testable import Shipyard

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

    func testCertificateRelationshipDocumentsDecode() throws {
        let merchantJSON = """
        {"data":[{"type":"merchantIds","id":"merchant-1","attributes":{"name":"Store Pay","identifier":"merchant.com.example.store"}}],"meta":{"paging":{"total":1,"limit":200}}}
        """
        let merchants = try getDecoder().decode(MerchantIdsDocument.self, from: Data(merchantJSON.utf8))
        XCTAssertEqual(merchants.data[0].id, "merchant-1")
        XCTAssertEqual(merchants.data[0].name, "Store Pay")
        XCTAssertEqual(merchants.data[0].identifier, "merchant.com.example.store")

        let passTypeJSON = """
        {"data":[{"type":"passTypeIds","id":"pass-1","attributes":{"name":"Loyalty Pass","identifier":"pass.com.example.loyalty"}}],"meta":{"paging":{"total":1,"limit":200}}}
        """
        let passTypes = try getDecoder().decode(PassTypeIdsDocument.self, from: Data(passTypeJSON.utf8))
        XCTAssertEqual(passTypes.data[0].id, "pass-1")
        XCTAssertEqual(passTypes.data[0].name, "Loyalty Pass")
        XCTAssertEqual(passTypes.data[0].identifier, "pass.com.example.loyalty")
    }

    func testCertificateDetailDecodesContent() throws {
        let json = """
        {"data":{"type":"certificates","id":"cert-1","attributes":{"name":"Apple Distribution","displayName":"Apple Distribution: Example LLC","certificateType":"IOS_DISTRIBUTION","serialNumber":"ABC123","platform":"IOS","expirationDate":"2027-10-06T10:00:00.000+00:00","activated":true,"certificateContent":"Q0VSVA=="}}}
        """
        let model = try getDecoder().decode(CertificateModel.self, from: Data(json.utf8))
        XCTAssertEqual(model.id, "cert-1")
        XCTAssertEqual(model.displayName, "Apple Distribution: Example LLC")
        XCTAssertEqual(model.certificateType, "IOS_DISTRIBUTION")
        XCTAssertEqual(model.serialNumber, "ABC123")
        XCTAssertEqual(model.platform, "IOS")
        XCTAssertEqual(model.activated, true)
        XCTAssertEqual(model.certificateContent, "Q0VSVA==")
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
        // The relationships key is always present in real responses;
        // swift-jsonapi requires it when a relationship is declared.
        let json = """
        {"data":[{"type":"users","id":"user-1","attributes":{"username":"a@b.com","firstName":"Ada","lastName":"Lovelace","roles":["ADMIN","DEVELOPER"],"allAppsVisible":true,"provisioningAllowed":false},"relationships":{"visibleApps":{"data":[]}}}],"meta":{"paging":{"total":1,"limit":50}}}
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
        {"data":[{"type":"profiles","id":"profile-1","attributes":{"name":"Orbit Development","profileType":"IOS_APP_DEVELOPMENT","profileState":"ACTIVE"},"relationships":{"devices":{"data":[{"type":"devices","id":"device-1"}]},"certificates":{"data":[{"type":"certificates","id":"cert-1"}]},"bundleId":{"data":{"type":"bundleIds","id":"bundle-1"}}}}],"included":[{"type":"devices","id":"device-1","attributes":{"name":"Dev iPhone","platform":"IOS","udid":"00008101-001C25D40"}},{"type":"certificates","id":"cert-1","attributes":{"displayName":"Apple Development: Ada (ABC123)","certificateType":"IOS_DEVELOPMENT"}},{"type":"bundleIds","id":"bundle-1","attributes":{"name":"Orbit","identifier":"com.acme.orbit","platform":"IOS"}}],"meta":{"paging":{"total":1,"limit":50}}}
        """
        let model = try getDecoder().decode(ProfilesDocument.self, from: Data(json.utf8))
        XCTAssertEqual(model.data.count, 1)
        XCTAssertEqual(model.data[0].bundleId?.identifier, "com.acme.orbit")
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
        {"data":[{"type":"profiles","id":"profile-2","attributes":{"name":"Orbit Store","profileType":"IOS_APP_STORE","profileState":"ACTIVE"},"relationships":{"devices":{"data":[]},"certificates":{"data":[]},"bundleId":{"data":null}}}],"meta":{"paging":{"total":1,"limit":50}}}
        """
        let model = try getDecoder().decode(ProfilesDocument.self, from: Data(json.utf8))
        XCTAssertEqual(model.data.count, 1)
        XCTAssertNil(model.data[0].bundleId)
        XCTAssertTrue(model.data[0].devices.isEmpty)
        XCTAssertTrue(model.data[0].certificates.isEmpty)
    }

    func testUsersDocumentHydratesIncludedVisibleApps() throws {
        // GET /v1/users?include=visibleApps shape: linkage in
        // relationships, app resources in included. Drives the App scope
        // column, the edit-user chooser and the resend recap. The second
        // user carries links-only linkage (unincluded shape) — that must
        // decode to [], not fail the document.
        let json = """
        {"data":[{"type":"users","id":"user-1","attributes":{"username":"sarah.c@sky.net","firstName":"Sarah","lastName":"Connor","roles":["DEVELOPER"],"allAppsVisible":false,"provisioningAllowed":true},"relationships":{"visibleApps":{"data":[{"type":"apps","id":"app-1"},{"type":"apps","id":"app-2"}]}}},{"type":"users","id":"user-2","attributes":{"username":"john@apple.com","firstName":"John","lastName":"Appleseed","roles":["ACCOUNT_HOLDER"],"allAppsVisible":true,"provisioningAllowed":true},"relationships":{"visibleApps":{"links":{"self":"https://api.appstoreconnect.apple.com/v1/users/user-2/relationships/visibleApps","related":"https://api.appstoreconnect.apple.com/v1/users/user-2/visibleApps"}}}}],"included":[{"type":"apps","id":"app-1","attributes":{"name":"Orbit","bundleId":"com.acme.orbit"},"relationships":{"appStoreVersions":{"data":[]},"appStoreIcon":{"data":null}}},{"type":"apps","id":"app-2","attributes":{"name":"Atlas","bundleId":"com.acme.atlas"},"relationships":{"appStoreVersions":{"data":[]},"appStoreIcon":{"data":null}}}],"meta":{"paging":{"total":2,"limit":50}}}
        """
        let model = try getDecoder().decode(UsersDocument.self, from: Data(json.utf8))
        XCTAssertEqual(model.data.count, 2)
        XCTAssertEqual(model.data[0].visibleApps.map(\.id), ["app-1", "app-2"])
        XCTAssertEqual(
            ResourcesViewModel.appScopeLabel(
                allAppsVisible: model.data[0].allAppsVisible,
                visibleAppNames: model.data[0].visibleApps.map { $0.name ?? $0.id }),
            "Orbit, Atlas")
        XCTAssertTrue(model.data[1].visibleApps.isEmpty)
        XCTAssertEqual(
            ResourcesViewModel.appScopeLabel(
                allAppsVisible: model.data[1].allAppsVisible,
                visibleAppNames: []),
            "All Apps")
    }

    func testUserInvitationsDocumentHydratesVisibleApps() throws {
        // GET /v1/userInvitations?include=visibleApps shape: the pending
        // list scope column + resend scope preservation read this.
        let json = """
        {"data":[{"type":"userInvitations","id":"invite-1","attributes":{"email":"jane.doe@acme.com","firstName":"Jane","lastName":"Doe","expirationDate":"2026-10-11T11:15:00-07:00","roles":["DEVELOPER"],"allAppsVisible":false,"provisioningAllowed":true},"relationships":{"visibleApps":{"data":[{"type":"apps","id":"app-1"}]}}}],"included":[{"type":"apps","id":"app-1","attributes":{"name":"Orbit","bundleId":"com.acme.orbit"},"relationships":{"appStoreVersions":{"data":[]},"appStoreIcon":{"data":null}}}],"meta":{"paging":{"total":1,"limit":200}}}
        """
        let model = try getDecoder().decode(UserInvitationsDocument.self, from: Data(json.utf8))
        XCTAssertEqual(model.data.count, 1)
        XCTAssertEqual(model.data[0].visibleApps.map(\.id), ["app-1"])
        XCTAssertEqual(model.data[0].expirationDate, "2026-10-11T11:15:00-07:00")
    }
}
