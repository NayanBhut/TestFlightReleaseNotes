//
//  ValidationTests.swift
//  App Store Tests
//
//  Batch I (I8): client-side validation + enum display coverage for the
//  Batch G/I write forms. Pure logic, no API key or keychain needed.
//

import XCTest
@testable import App_Store

final class ValidationTests: XCTestCase {
    // MARK: - ProvisioningWriteValidation (Batch G)

    func testValidUDIDs() {
        // Newer hardware: 8 hex, dash, 9 hex. Classic: 40 hex.
        XCTAssertTrue(ProvisioningWriteValidation.isValidUDID("00008030-001A2B3C4"))
        XCTAssertTrue(ProvisioningWriteValidation.isValidUDID("abcdef1234567890abcdef1234567890abcd1234"))
    }

    func testInvalidUDIDs() {
        XCTAssertFalse(ProvisioningWriteValidation.isValidUDID(""))
        XCTAssertFalse(ProvisioningWriteValidation.isValidUDID("not-a-udid"))
        XCTAssertFalse(ProvisioningWriteValidation.isValidUDID("ZZZZ8030-001A2B3C4"))
        XCTAssertFalse(ProvisioningWriteValidation.isValidUDID("00008030-001A2B3C4D5E6F7A8"))
    }

    func testCSRValidation() {
        let valid = "-----BEGIN CERTIFICATE REQUEST-----\nMIIB\n-----END CERTIFICATE REQUEST-----"
        XCTAssertTrue(ProvisioningWriteValidation.isValidCSR(valid))
        XCTAssertFalse(ProvisioningWriteValidation.isValidCSR(""))
        XCTAssertFalse(ProvisioningWriteValidation.isValidCSR("-----BEGIN CERTIFICATE REQUEST-----\nMIIB"))
    }

    // MARK: - EmailValidator (Beta)

    func testEmailValidation() {
        XCTAssertTrue(EmailValidator.isValid("tester@example.com"))
        XCTAssertFalse(EmailValidator.isValid("not-an-email"))
        XCTAssertFalse(EmailValidator.isValid(""))
        // Normalized before validating: surrounding spaces are fine.
        XCTAssertTrue(EmailValidator.isValid(EmailValidator.normalized("  tester@example.com  ")))
    }

    // MARK: - Batch I option enums

    func testBundleIdPlatformOptions() {
        // Spec enum BundleIdPlatform: IOS + MAC_OS only (no UNIVERSAL).
        XCTAssertEqual(BundleIdPlatformOption.allCases.map(\.rawValue).sorted(), ["IOS", "MAC_OS"])
        XCTAssertEqual(BundleIdPlatformOption.IOS.displayName, "iOS")
        XCTAssertEqual(BundleIdPlatformOption.MAC_OS.displayName, "macOS")
    }

    func testUserRoleOptionsCoverSpec() {
        let rawValues = Set(UserRoleOption.allCases.map(\.rawValue))
        for role in ["ADMIN", "FINANCE", "TECHNICAL", "ACCOUNT_HOLDER", "READ_ONLY",
                     "SALES", "MARKETING", "APP_MANAGER", "DEVELOPER",
                     "ACCESS_TO_REPORTS", "CUSTOMER_SUPPORT"] {
            XCTAssertTrue(rawValues.contains(role), "Missing role \(role)")
        }
        XCTAssertEqual(UserRoleOption.APP_MANAGER.displayName, "App Manager")
        XCTAssertEqual(UserRoleOption.ACCESS_TO_REPORTS.displayName, "Access to Reports")
    }

    func testProfileTypeOptionsCoverSpec() {
        XCTAssertEqual(ProfileTypeOption.allCases.count, 14)
        XCTAssertTrue(ProfileTypeOption.allCases.map(\.rawValue).contains("IOS_APP_STORE"))
        XCTAssertFalse(ProfileTypeOption.allCases.map(\.displayName).contains(where: \.isEmpty))
    }

    // MARK: - Field-value encoding (Batch G/I shared contract)

    func testFieldValueEncoding() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        // .set sends the value; .clear sends null; .unchanged omits the key.
        let attributes = VersionLocalizationUpdateAttributes(
            descriptionData: .set("Hello"),
            keywords: .clear,
            marketingUrl: .unchanged,
            promotionalText: .unchanged,
            supportUrl: .unchanged,
            whatsNew: .unchanged
        )
        let data = try encoder.encode(attributes)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"description\":\"Hello\""))
        XCTAssertTrue(json.contains("\"keywords\":null"))
        XCTAssertFalse(json.contains("marketingUrl"))
        XCTAssertFalse(json.contains("whatsNew"))
    }

    // MARK: - Invite body relationships (Batch I fix)

    func testInviteBodyVisibleApps() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        // Single-app invite carries the visibleApps relationship.
        let scoped = UserInvitationCreateRequest(
            data: UserInvitationCreateData(
                attributes: UserInvitationCreateAttributes(
                    email: "a@b.com", firstName: "Ada", lastName: "L",
                    roles: ["DEVELOPER"], allAppsVisible: false, provisioningAllowed: false
                ),
                relationships: UserInvitationCreateRelationships(
                    visibleApps: UserInvitationVisibleAppsRelationship(
                        data: [UserInvitationAppRef(id: "app-1")]
                    )
                )
            )
        )
        let scopedJSON = String(data: try encoder.encode(scoped), encoding: .utf8) ?? ""
        XCTAssertTrue(scopedJSON.contains("\"visibleApps\""))
        XCTAssertTrue(scopedJSON.contains("\"app-1\""))

        // All-apps invite omits relationships entirely.
        let allApps = UserInvitationCreateRequest(
            data: UserInvitationCreateData(
                attributes: UserInvitationCreateAttributes(
                    email: "a@b.com", firstName: "Ada", lastName: "L",
                    roles: ["DEVELOPER"], allAppsVisible: true, provisioningAllowed: false
                ),
                relationships: nil
            )
        )
        let allAppsJSON = String(data: try encoder.encode(allApps), encoding: .utf8) ?? ""
        XCTAssertFalse(allAppsJSON.contains("visibleApps"))
    }

    // MARK: - CredentialStorage (keychain-backed: pure parts only)

    func testCredentialCodableRoundTrip() throws {
        let credential = Credential(key: "Team", issuerID: "issuer", privateKey: "key", keyID: "id")
        let data = try JSONEncoder().encode(credential)
        let decoded = try JSONDecoder().decode(Credential.self, from: data)
        XCTAssertEqual(decoded.key, "Team")
        XCTAssertEqual(decoded.issuerID, "issuer")
    }

    // NOTE: CredentialStorage's selection logic (changeTeam /
    // restoreDefaultTeam) is deliberately untested: the singleton's
    // private init runs a keychain migration + team refresh, so any test
    // would read the developer's real keychain. Covering it needs a
    // keychain seam (protocol + injected store), which is out of scope
    // for this batch.
}
