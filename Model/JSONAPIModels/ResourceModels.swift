//
//  ResourceModels.swift
//  App Store
//
//  Batch C2: team-scoped resources (read-only) — devices, certificates,
//  bundle IDs, provisioning profiles and users. These are NOT app-scoped;
//  they need an API key with broader permissions than TestFlight-only.
//  Attribute sets verified against Apple's OpenAPI spec.
//

import Foundation
import JSONAPI

@ResourceWrapper(type: "devices")
struct DeviceModel: Equatable {
    static func == (lhs: DeviceModel, rhs: DeviceModel) -> Bool {
        return lhs.id == rhs.id
    }

    var id: String

    @ResourceAttribute var name: String?
    @ResourceAttribute var platform: String?
    @ResourceAttribute var udid: String?
    @ResourceAttribute var deviceClass: String?
    /// ENABLED / DISABLED
    @ResourceAttribute var status: String?
    @ResourceAttribute var model: String?
    @ResourceAttribute var addedDate: String?
}

@ResourceWrapper(type: "certificates")
struct CertificateModel: Equatable {
    static func == (lhs: CertificateModel, rhs: CertificateModel) -> Bool {
        return lhs.id == rhs.id
    }

    var id: String

    @ResourceAttribute var name: String?
    @ResourceAttribute var displayName: String?
    @ResourceAttribute var certificateType: String?
    @ResourceAttribute var serialNumber: String?
    @ResourceAttribute var platform: String?
    @ResourceAttribute var expirationDate: String?
    @ResourceAttribute var activated: Bool?
}

@ResourceWrapper(type: "bundleIds")
struct BundleIdModel: Equatable {
    static func == (lhs: BundleIdModel, rhs: BundleIdModel) -> Bool {
        return lhs.id == rhs.id
    }

    var id: String

    @ResourceAttribute var name: String?
    @ResourceAttribute var identifier: String?
    @ResourceAttribute var platform: String?
    @ResourceAttribute var seedId: String?
}

@ResourceWrapper(type: "profiles")
struct ProfileModel: Equatable {
    static func == (lhs: ProfileModel, rhs: ProfileModel) -> Bool {
        return lhs.id == rhs.id
    }

    var id: String

    @ResourceAttribute var name: String?
    @ResourceAttribute var platform: String?
    @ResourceAttribute var profileType: String?
    /// INVALID, ACTIVE, PROCESSING
    @ResourceAttribute var profileState: String?
    @ResourceAttribute var uuid: String?
    @ResourceAttribute var createdDate: String?
    @ResourceAttribute var expirationDate: String?
}

@ResourceWrapper(type: "users")
struct UserModel: Equatable {
    static func == (lhs: UserModel, rhs: UserModel) -> Bool {
        return lhs.id == rhs.id
    }

    var id: String

    @ResourceAttribute var username: String?
    @ResourceAttribute var firstName: String?
    @ResourceAttribute var lastName: String?
    @ResourceAttribute var roles: [String]?
    @ResourceAttribute var allAppsVisible: Bool?
    @ResourceAttribute var provisioningAllowed: Bool?
}

// Documents: all five collections are cursor-paginated and return paging
// meta alongside limit (verified against Apple's OpenAPI spec), so all
// use the paging Meta — "Load more" and real totals work for every kind.
typealias DevicesDocument = CompoundDocument<[DeviceModel], Meta>
typealias CertificatesDocument = CompoundDocument<[CertificateModel], Meta>
typealias BundleIdsDocument = CompoundDocument<[BundleIdModel], Meta>
typealias ProfilesDocument = CompoundDocument<[ProfileModel], Meta>
typealias UsersDocument = CompoundDocument<[UserModel], Meta>

// MARK: - Batch G (#10): device + certificate writes
//
// Bodies verified against Apple's OpenAPI spec (v4.4.1):
// - POST /v1/devices: attributes name + platform + udid (all required).
//   Platform enum is BundleIdPlatform: IOS, MAC_OS, UNIVERSAL.
// - PATCH /v1/devices/{id}: attributes name?, status? (ENABLED/DISABLED).
//   There is NO DELETE on devices — devices can only be disabled via the
//   API (removal is Apple Developer website only), so "revoke" = disable.
// - POST /v1/certificates: attributes csrContent + certificateType.
// - DELETE /v1/certificates/{id}: revoke (204, no body).
// Writes need an API key with an elevated role (Admin/Account Holder for
// provisioning); a TestFlight-only key 403s.

/// Device platform values (spec enum BundleIdPlatform).
enum DevicePlatform: String, CaseIterable {
    case IOS
    case MAC_OS
    case UNIVERSAL

    var displayName: String {
        switch self {
        case .IOS: return "iOS"
        case .MAC_OS: return "macOS"
        case .UNIVERSAL: return "Universal"
        }
    }
}

struct DeviceCreateRequest: Encodable {
    var data: DeviceCreateData
}

struct DeviceCreateData: Encodable {
    var type = "devices"
    var attributes: DeviceCreateAttributes
}

struct DeviceCreateAttributes: Encodable {
    var name: String
    var platform: String
    var udid: String
}

struct DeviceUpdateRequest: Encodable {
    var data: DeviceUpdateData
}

struct DeviceUpdateData: Encodable {
    var type = "devices"
    var id: String
    var attributes: DeviceUpdateAttributes
}

struct DeviceUpdateAttributes: Encodable {
    var name: String?
    var status: String?
}

/// Certificate types (spec enum CertificateType, v4.4.1) for the create
/// form's picker. A curated UI list would drift silently when Apple adds
/// types, so this mirrors the full enum.
enum CertificateTypeOption: String, CaseIterable {
    case APPLE_PAY
    case APPLE_PAY_MERCHANT_IDENTITY
    case APPLE_PAY_PSP_IDENTITY
    case APPLE_PAY_RSA
    case DEVELOPER_ID_KEXT
    case DEVELOPER_ID_KEXT_G2
    case DEVELOPER_ID_APPLICATION
    case DEVELOPER_ID_APPLICATION_G2
    case DEVELOPMENT
    case DISTRIBUTION
    case IDENTITY_ACCESS
    case IOS_DEVELOPMENT
    case IOS_DISTRIBUTION
    case MAC_APP_DISTRIBUTION
    case MAC_INSTALLER_DISTRIBUTION
    case MAC_APP_DEVELOPMENT
    case PASS_TYPE_ID
    case PASS_TYPE_ID_WITH_NFC

    /// SNAKE_CASE → title case for the picker (e.g. IOS_DEVELOPMENT →
    /// "Ios Development"). Derived, so new enum values render sanely
    /// without touching this.
    var displayName: String {
        rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
            .replacingOccurrences(of: "Ios", with: "iOS")
            .replacingOccurrences(of: "Id ", with: "ID ")
            .replacingOccurrences(of: "Nfc", with: "NFC")
    }
}

/// Client-side format checks for the create forms so obvious rejections
/// surface without a network round-trip (server remains the source of
/// truth). UDID: 25–27 hex chars with a dash (newer hardware) or 40 hex
/// (classic). CSR: PEM marker.
enum ProvisioningWriteValidation {
    static func isValidUDID(_ udid: String) -> Bool {
        let pattern = "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{9}$|^[0-9A-Fa-f]{40}$"
        return udid.range(of: pattern, options: .regularExpression) != nil
    }

    static func isValidCSR(_ content: String) -> Bool {
        content.contains("-----BEGIN CERTIFICATE REQUEST-----")
            && content.contains("-----END CERTIFICATE REQUEST-----")
    }
}

struct CertificateCreateRequest: Encodable {
    var data: CertificateCreateData
}

struct CertificateCreateData: Encodable {
    var type = "certificates"
    var attributes: CertificateCreateAttributes
}

struct CertificateCreateAttributes: Encodable {
    var csrContent: String
    var certificateType: String
}
