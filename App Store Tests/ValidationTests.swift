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

    // MARK: - CSR file upload (replaces pasted CSR text)

    func testLoadCSRFromValidFile() throws {
        let url = try writeTempCSR("  \n-----BEGIN CERTIFICATE REQUEST-----\nMIIB\n-----END CERTIFICATE REQUEST-----\n")
        defer { try? FileManager.default.removeItem(at: url) }
        // Trims surrounding whitespace; inner PEM newlines are preserved
        // for the server.
        XCTAssertEqual(
            try ProvisioningWriteValidation.loadCSR(from: url),
            "-----BEGIN CERTIFICATE REQUEST-----\nMIIB\n-----END CERTIFICATE REQUEST-----"
        )
    }

    func testLoadCSRRejectsNonCSRFile() throws {
        let url = try writeTempCSR("just some text, not a CSR")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try ProvisioningWriteValidation.loadCSR(from: url)) { error in
            XCTAssertEqual(error as? CSRFileLoadError, .invalidFormat)
        }
    }

    func testLoadCSRRejectsEmptyFile() throws {
        let url = try writeTempCSR("   \n  ")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try ProvisioningWriteValidation.loadCSR(from: url)) { error in
            XCTAssertEqual(error as? CSRFileLoadError, .invalidFormat)
        }
    }

    func testLoadCSRMissingFile() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString).csr")
        XCTAssertThrowsError(try ProvisioningWriteValidation.loadCSR(from: missing)) { error in
            XCTAssertEqual(error as? CSRFileLoadError, .unreadable)
        }
    }

    func testCSRFileErrorsAreUserFacing() {
        // Shown verbatim in the form — must never be empty or technical.
        for error in [CSRFileLoadError.unreadable, .invalidFormat, .tooLarge] {
            let message = error.errorDescription ?? ""
            XCTAssertFalse(message.isEmpty)
            XCTAssertTrue(message.contains("CSR") || message.contains("file"))
        }
    }

    private func writeTempCSR(_ content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).csr")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
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

    // MARK: - User update body + scope labels (users flow)

    func testUserUpdateBodyOmitsAbsentKeys() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        // Roles-only edit omits scope keys — never nulls untouched fields.
        let rolesOnly = UserUpdateRequest(
            data: UserUpdateData(
                id: "user-1",
                attributes: UserUpdateAttributes(
                    roles: ["DEVELOPER"], allAppsVisible: nil, provisioningAllowed: nil),
                relationships: nil))
        let rolesJSON = String(data: try encoder.encode(rolesOnly), encoding: .utf8) ?? ""
        XCTAssertTrue(rolesJSON.contains("\"roles\":[\"DEVELOPER\"]"))
        XCTAssertFalse(rolesJSON.contains("allAppsVisible"))
        XCTAssertFalse(rolesJSON.contains("provisioningAllowed"))
        XCTAssertFalse(rolesJSON.contains("relationships"))

        // Full edit sends all three + the visibleApps linkage.
        let full = UserUpdateRequest(
            data: UserUpdateData(
                id: "user-1",
                attributes: UserUpdateAttributes(
                    roles: ["APP_MANAGER"], allAppsVisible: false, provisioningAllowed: true),
                relationships: UserUpdateRelationships(
                    visibleApps: UserInvitationVisibleAppsRelationship(
                        data: [UserInvitationAppRef(id: "app-1")]))))
        let fullJSON = String(data: try encoder.encode(full), encoding: .utf8) ?? ""
        XCTAssertTrue(fullJSON.contains("\"allAppsVisible\":false"))
        XCTAssertTrue(fullJSON.contains("\"provisioningAllowed\":true"))
        XCTAssertTrue(fullJSON.contains("\"app-1\""))
    }

    func testAppScopeLabels() {
        XCTAssertEqual(
            ResourcesViewModel.appScopeLabel(allAppsVisible: true, visibleAppNames: []),
            "All Apps")
        XCTAssertEqual(
            ResourcesViewModel.appScopeLabel(allAppsVisible: nil, visibleAppNames: []),
            "All Apps")
        XCTAssertEqual(
            ResourcesViewModel.appScopeLabel(allAppsVisible: false, visibleAppNames: ["Orbit", "Atlas"]),
            "Orbit, Atlas")
        // Unhydrated linkage never renders blank.
        XCTAssertEqual(
            ResourcesViewModel.appScopeLabel(allAppsVisible: false, visibleAppNames: []),
            "Selected apps")
    }

    func testRoleGrantableCasesExcludeAccountHolder() {
        XCTAssertFalse(UserRoleOption.grantableCases.contains(.ACCOUNT_HOLDER))
        XCTAssertEqual(UserRoleOption.grantableCases.count, UserRoleOption.allCases.count - 1)
        // Every offered role has description copy for the checkboxes.
        for role in UserRoleOption.grantableCases {
            XCTAssertFalse(role.displayName.isEmpty)
            XCTAssertFalse(role.description.isEmpty)
        }
    }

    // MARK: - Profiles flow (status, type resolve, eligibility)

    private func profileFixture(id: String, state: String?, expiry: String?) -> ProfileModel {
        var model = ProfileModel(id: id, devices: [], certificates: [], bundleId: nil)
        model.profileState = state
        model.expirationDate = expiry
        return model
    }

    func testProfileComputedStatus() {
        let active = profileFixture(id: "p1", state: "ACTIVE", expiry: "2027-09-22T00:00:00-07:00")
        XCTAssertEqual(active.computedStatus, .active)

        let invalid = profileFixture(id: "p2", state: "INVALID", expiry: "2027-09-22T00:00:00-07:00")
        XCTAssertEqual(invalid.computedStatus, .invalid)

        // Server INVALID wins even past expiry.
        let invalidExpired = profileFixture(id: "p3", state: "INVALID", expiry: "2020-01-01T00:00:00-07:00")
        XCTAssertEqual(invalidExpired.computedStatus, .invalid)

        let expired = profileFixture(id: "p4", state: "ACTIVE", expiry: "2025-09-20T00:00:00-07:00")
        XCTAssertEqual(expired.computedStatus, .expired)

        // Missing/unparseable dates never claim expiry.
        let undated = profileFixture(id: "p5", state: "ACTIVE", expiry: nil)
        XCTAssertEqual(undated.computedStatus, .active)
        let garbage = profileFixture(id: "p6", state: "ACTIVE", expiry: "not-a-date")
        XCTAssertEqual(garbage.computedStatus, .active)
    }

    func testProfileTypeResolve() {
        XCTAssertEqual(
            ProfileTypeOption.resolve(platformCode: "IOS", kind: .development),
            .IOS_APP_DEVELOPMENT)
        XCTAssertEqual(
            ProfileTypeOption.resolve(platformCode: "IOS", kind: .adHoc),
            .IOS_APP_ADHOC)
        XCTAssertEqual(
            ProfileTypeOption.resolve(platformCode: "IOS", kind: .appStore),
            .IOS_APP_STORE)
        XCTAssertEqual(
            ProfileTypeOption.resolve(platformCode: "MAC_OS", kind: .development),
            .MAC_APP_DEVELOPMENT)
        // macOS has no Ad Hoc type — wizard must block, not guess.
        XCTAssertNil(ProfileTypeOption.resolve(platformCode: "MAC_OS", kind: .adHoc))
        XCTAssertEqual(
            ProfileTypeOption.resolve(platformCode: "TVOS", kind: .adHoc),
            .TVOS_APP_ADHOC)
        // Enterprise/direct via the Other picker.
        XCTAssertEqual(
            ProfileTypeOption.resolve(platformCode: "IOS", kind: nil, otherType: .IOS_APP_INHOUSE),
            .IOS_APP_INHOUSE)
        XCTAssertNil(ProfileTypeOption.resolve(platformCode: "IOS", kind: nil, otherType: nil))
        XCTAssertTrue(ProfileTypeOption.otherTypes(for: "MAC_OS").contains(.MAC_APP_DIRECT))
        XCTAssertFalse(ProfileTypeOption.otherTypes(for: "MAC_OS").contains(.IOS_APP_STORE))
    }

    func testCertificateEligibility() {
        // Only signing identities belong in profiles — Apple Pay, Pass,
        // Identity Access and Developer ID certs are hidden, not listed.
        XCTAssertTrue(CertificateTypeOption.IOS_DEVELOPMENT.isSigningIdentity)
        XCTAssertTrue(CertificateTypeOption.IOS_DISTRIBUTION.isSigningIdentity)
        XCTAssertTrue(CertificateTypeOption.DEVELOPMENT.isSigningIdentity)
        XCTAssertTrue(CertificateTypeOption.DISTRIBUTION.isSigningIdentity)
        XCTAssertTrue(CertificateTypeOption.MAC_APP_DEVELOPMENT.isSigningIdentity)
        XCTAssertFalse(CertificateTypeOption.APPLE_PAY.isSigningIdentity)
        XCTAssertFalse(CertificateTypeOption.APPLE_PAY_MERCHANT_IDENTITY.isSigningIdentity)
        XCTAssertFalse(CertificateTypeOption.PASS_TYPE_ID.isSigningIdentity)
        XCTAssertFalse(CertificateTypeOption.IDENTITY_ACCESS.isSigningIdentity)
        XCTAssertFalse(CertificateTypeOption.DEVELOPER_ID_APPLICATION.isSigningIdentity)
        // Kind matching: development kinds take *DEVELOPMENT* only.
        XCTAssertTrue(CertificateTypeOption.IOS_DEVELOPMENT.matchesKind(development: true))
        XCTAssertFalse(CertificateTypeOption.IOS_DEVELOPMENT.matchesKind(development: false))
        XCTAssertTrue(CertificateTypeOption.IOS_DISTRIBUTION.matchesKind(development: false))
        XCTAssertFalse(CertificateTypeOption.IOS_DISTRIBUTION.matchesKind(development: true))
        XCTAssertTrue(CertificateTypeOption.MAC_APP_DISTRIBUTION.matchesKind(development: false))
        // Legacy unprefixed types match every platform.
        XCTAssertTrue(CertificateTypeOption.DEVELOPMENT.matchesPlatform("IOS"))
        XCTAssertTrue(CertificateTypeOption.DEVELOPMENT.matchesPlatform("MAC_OS"))
        XCTAssertTrue(CertificateTypeOption.DISTRIBUTION.matchesPlatform("TVOS"))
        // Prefixed types stay on their platform; tvOS shares iOS identities.
        XCTAssertTrue(CertificateTypeOption.IOS_DEVELOPMENT.matchesPlatform("TVOS"))
        XCTAssertFalse(CertificateTypeOption.MAC_APP_DEVELOPMENT.matchesPlatform("IOS"))
        XCTAssertFalse(CertificateTypeOption.IOS_DISTRIBUTION.matchesPlatform("MAC_OS"))
    }

    func testDevicePlatformMatches() {
        XCTAssertTrue(devicePlatformMatches("IOS", profilePlatform: "IOS"))
        XCTAssertTrue(devicePlatformMatches("UNIVERSAL", profilePlatform: "MAC_OS"))
        XCTAssertTrue(devicePlatformMatches(nil, profilePlatform: "IOS"))
        XCTAssertFalse(devicePlatformMatches("MAC_OS", profilePlatform: "IOS"))
        XCTAssertTrue(devicePlatformMatches("MAC_OS", profilePlatform: "MAC_OS"))
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

    // MARK: - Device CSV import (Devices empty state)

    func testCSVParsesCommaRowsWithHeader() {
        let content = """
        name,udid,platform
        John's iPhone 16 Pro,00008101-001C25D40,IOS
        iPad Air,abcdef1234567890abcdef1234567890abcd1234,
        """
        let parsed = DeviceCSVImport.parse(content)
        XCTAssertEqual(parsed.rejected, 0)
        XCTAssertEqual(parsed.rows.count, 2)
        XCTAssertEqual(parsed.rows[0], DeviceCSVRow(name: "John's iPhone 16 Pro", udid: "00008101-001C25D40", platform: .IOS))
        // Blank platform defaults to iOS (same default as the form).
        XCTAssertEqual(parsed.rows[1].platform, .IOS)
    }

    func testCSVSkipsCommentsBlanksAndRejectsBadRows() {
        let content = """
        # team devices
        Legacy iPhone 12\t00008030-001A2B3C4\tMAC_OS

        nameless,,IOS
        bad-udid,not-a-udid,IOS
        mystery,00008101-001C25D40,WATCH_OS
        single-field-only
        """
        let parsed = DeviceCSVImport.parse(content)
        XCTAssertEqual(parsed.rows.count, 1)
        XCTAssertEqual(parsed.rows[0].platform, .MAC_OS)
        XCTAssertEqual(parsed.rejected, 4)
    }

    func testCSVPlatformAliases() {
        let content = """
        a,00008101-001C25D40,macos
        b,00008101-001C25D40,universal
        c,00008101-001C25D40,MAC
        """
        let parsed = DeviceCSVImport.parse(content)
        XCTAssertEqual(parsed.rows.map(\.platform), [.MAC_OS, .UNIVERSAL, .MAC_OS])
        XCTAssertEqual(parsed.rejected, 0)
    }

    func testCSVLoadRejectsMissingFile() {
        XCTAssertThrowsError(try DeviceCSVImport.load(from: URL(fileURLWithPath: "/nonexistent-devices.csv")))
    }

    // MARK: - Device PATCH bodies (rename + enable/disable)

    func testDeviceRenameBodyOmitsStatus() throws {
        let request = DeviceUpdateRequest(
            data: DeviceUpdateData(
                id: "device-1",
                attributes: DeviceUpdateAttributes(name: "New Name", status: nil)
            )
        )
        let data = try JSONEncoder().encode(request)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payload = try XCTUnwrap(root["data"] as? [String: Any])
        // PATCH must not send `"status": null` — only the renamed attribute
        // (a null would fail the [String: String] cast below).
        XCTAssertEqual(payload["id"] as? String, "device-1")
        XCTAssertEqual(payload["type"] as? String, "devices")
        XCTAssertEqual(payload["attributes"] as? [String: String], ["name": "New Name"])
    }

    func testDeviceStatusBodyOmitsName() throws {
        let request = DeviceUpdateRequest(
            data: DeviceUpdateData(
                id: "device-1",
                attributes: DeviceUpdateAttributes(name: nil, status: "DISABLED")
            )
        )
        let data = try JSONEncoder().encode(request)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payload = try XCTUnwrap(root["data"] as? [String: Any])
        XCTAssertEqual(payload["attributes"] as? [String: String], ["status": "DISABLED"])
    }

    // MARK: - ASN1 malformed-input guard (BUG_SWEEP #2)

    /// A truncated/garbage .p8 body must throw `invalidASN1`, never trap on
    /// out-of-bounds subscripts. Swift runtime traps are fatal, so the
    /// onboarding `try?` cannot catch them — the parser must bounds-check.
    func testToECKeyDataGarbageThrowsNotTraps() {
        let cases: [Data] = [
            Data(),
            Data([0x30, 0x00]),                                       // empty sequence
            Data([0x30, 0x02, 0x02, 0x01]),                           // seq missing [2]
            Data([0x30, 0x06, 0x02, 0x01, 0x00, 0x04, 0x01, 0xAA]),   // outer ok, octet not a seq
            Data([0x04, 0x02, 0xAA, 0xBB]),                           // not a sequence at all
        ]
        for bytes in cases {
            XCTAssertThrowsError(try bytes.toECKeyData()) { error in
                XCTAssertEqual(error as? JWT.Error, .invalidASN1)
            }
        }
    }

    func testToRawSignatureShortSequenceThrows() {
        // seq with only INTEGER R — element [1] (S) must not subscript.
        let data = Data([0x30, 0x03, 0x02, 0x01, 0x01])
        XCTAssertThrowsError(try data.toRawSignature()) { error in
            XCTAssertEqual(error as? JWT.Error, .invalidASN1)
        }
    }
}
