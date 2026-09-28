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

    @MainActor
    func testBuildEligibilityRequiresValidMatchingPlatformAndUnexpired() {
        var preRelease = PreReleaseVersionsModel(id: "pre-1")
        preRelease.version = "2.1.0"
        preRelease.platform = "IOS"
        var build = BuildsModel(id: "build-1", betaBuildLocalizations: [])
        build.processingState = "VALID"
        build.expired = false
        build.preReleaseVersion = preRelease
        XCTAssertTrue(ReviewsViewModel.isEligibleBuild(build, versionString: "2.1.0", platform: "IOS"))

        build.expired = nil
        XCTAssertFalse(ReviewsViewModel.isEligibleBuild(build, versionString: "2.1.0", platform: "IOS"))
        build.expired = false

        build.processingState = "PROCESSING"
        XCTAssertFalse(ReviewsViewModel.isEligibleBuild(build, versionString: "2.1.0", platform: "IOS"))
        build.processingState = "VALID"
        build.expired = true
        XCTAssertFalse(ReviewsViewModel.isEligibleBuild(build, versionString: "2.1.0", platform: "IOS"))
        build.expired = false
        XCTAssertFalse(ReviewsViewModel.isEligibleBuild(build, versionString: "2.1.0", platform: "MAC_OS"))
        XCTAssertFalse(ReviewsViewModel.isEligibleBuild(build, versionString: "2.2.0", platform: "IOS"))
    }

    @MainActor
    func testVersionCaseStateUsesSpecifiedLivePendingAndIgnoredStates() {
        var version = AppStoreVersionsModel(id: "version-1", appStoreVersionLocalizations: [])
        for state in ["PREPARE_FOR_SUBMISSION", "WAITING_FOR_REVIEW", "IN_REVIEW",
                      "PENDING_DEVELOPER_RELEASE", "REJECTED", "METADATA_REJECTED",
                      "DEVELOPER_REJECTED", "INVALID_BINARY", "PENDING_CONTRACT",
                      "PROCESSING_FOR_DISTRIBUTION"] {
            version.appStoreState = state
            XCTAssertTrue(ReviewsViewModel.isPendingApprovalVersion(version), state)
        }
        for state in ["READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "PENDING_APPLE_RELEASE",
                      "REPLACED_WITH_NEW_VERSION", "REMOVED_FROM_SALE", "UNKNOWN"] {
            version.appStoreState = state
            XCTAssertFalse(ReviewsViewModel.isPendingApprovalVersion(version), state)
        }

        let live = Self.version(id: "live", state: "READY_FOR_SALE", created: "2026-09-20T10:00:00Z")
        let pending = Self.version(id: "pending", state: "PREPARE_FOR_SUBMISSION", created: "2026-09-24T10:00:00Z")
        let ignored = Self.version(id: "ignored", state: "REPLACED_WITH_NEW_VERSION", created: "2026-09-25T10:00:00Z")

        XCTAssertEqual(getVersionCaseState(versions: [ignored]).`case`, .noVersion)
        XCTAssertEqual(getVersionCaseState(versions: [live]).`case`, .liveOnly)
        XCTAssertEqual(getVersionCaseState(versions: [pending]).`case`, .pendingOnly)
        XCTAssertEqual(getVersionCaseState(versions: [ignored, live, pending]).`case`, .both)
        XCTAssertEqual(getVersionCaseState(versions: [ignored, live, pending]).liveVersion?.id, "live")
        XCTAssertEqual(getVersionCaseState(versions: [ignored, live, pending]).pendingVersion?.id, "pending")

        let olderPending = Self.version(id: "older", state: "IN_REVIEW", created: "2026-09-23T10:00:00Z")
        XCTAssertEqual(getVersionCaseState(versions: [olderPending, pending]).pendingVersion?.id, "pending")
        XCTAssertEqual(ReviewsViewModel.preferredAppStoreVersion([live, pending])?.id, "pending")

        let vm = ReviewsViewModel()
        vm.appStoreVersionsState = .loaded([ignored, live, pending])
        XCTAssertEqual(vm.appStoreVersionDisplayState, .both)
        XCTAssertEqual(vm.displayedAppStoreVersions.map(\.id), ["live", "pending"])
        XCTAssertFalse(vm.canCreateAppStoreVersion)
        XCTAssertEqual(vm.submissionVersion?.id, "pending")

        vm.appStoreVersionsState = .loaded([live])
        XCTAssertEqual(vm.displayedAppStoreVersions.map(\.id), ["live"])
        XCTAssertTrue(vm.canCreateAppStoreVersion)

        var macLive = live
        macLive.id = "mac-live"
        macLive.platform = "MAC_OS"
        var tvInReview = Self.version(id: "tv-review", state: "IN_REVIEW", created: "2026-09-25T10:00:00Z")
        tvInReview.platform = "TV_OS"
        vm.appStoreVersionsState = .loaded([live, macLive, tvInReview])
        vm.appStoreVersionPlatforms = ["IOS", "MAC_OS", "TV_OS"]
        XCTAssertEqual(vm.creatableAppStoreVersionPlatforms, [.iOS, .macOS])
    }

    func testStatusLabelsAndEditability() {
        let labels = [
            "PREPARE_FOR_SUBMISSION": "Draft",
            "WAITING_FOR_REVIEW": "Waiting for Review",
            "IN_REVIEW": "In Review",
            "PENDING_DEVELOPER_RELEASE": "Approved – Ready to Release",
            "REJECTED": "Rejected",
            "DEVELOPER_REJECTED": "Rejected",
            "METADATA_REJECTED": "Metadata Rejected",
            "INVALID_BINARY": "Invalid Binary – Needs New Build",
            "PENDING_CONTRACT": "Pending Contract",
            "PROCESSING_FOR_DISTRIBUTION": "Processing"
        ]
        for (state, label) in labels {
            XCTAssertEqual(getStatusLabel(appStoreState: state), label)
        }
        for state in ["PREPARE_FOR_SUBMISSION", "REJECTED", "DEVELOPER_REJECTED",
                      "METADATA_REJECTED", "INVALID_BINARY"] {
            XCTAssertTrue(isVersionEditable(appStoreState: state), state)
        }
        for state in ["WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE",
                      "PENDING_CONTRACT", "PROCESSING_FOR_DISTRIBUTION",
                      "READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "PENDING_APPLE_RELEASE"] {
            XCTAssertFalse(isVersionEditable(appStoreState: state), state)
        }
    }

    private static func version(id: String, state: String, created: String) -> AppStoreVersionsModel {
        var version = AppStoreVersionsModel(id: id, appStoreVersionLocalizations: [])
        version.appStoreState = state
        version.platform = "IOS"
        version.createdDate = created
        return version
    }

    @MainActor
    func testSubmitRequiresAttachedBuild() {
        let vm = ReviewsViewModel()
        XCTAssertFalse(vm.canSubmitForReview)
        var approved = AppStoreVersionsModel(id: "version-1", appStoreVersionLocalizations: [])
        approved.appVersionState = "READY_FOR_DISTRIBUTION"
        approved.build = BuildsModel(id: "build-1", betaBuildLocalizations: [])
        vm.appStoreVersionsState = .loaded([approved])
        XCTAssertFalse(vm.canSubmitForReview)
    }

    @MainActor
    func testStaleResponseProtection() {
        XCTAssertTrue(ReviewsViewModel.responseIsCurrent(generation: 3, current: 3))
        XCTAssertFalse(ReviewsViewModel.responseIsCurrent(generation: 2, current: 3))
    }

    @MainActor
    func testWorkflowFailurePreservesLoadedVersions() {
        let vm = ReviewsViewModel()
        vm.appStoreVersionsState = .loaded([])
        vm.recordAppStoreVersionsFailure("server unavailable")
        XCTAssertEqual(vm.appStoreVersionsState, .loaded([]))
        XCTAssertEqual(vm.appStoreVersionsError, "server unavailable")
    }



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
