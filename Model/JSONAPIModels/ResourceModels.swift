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

// MARK: - Batch I (I2): bundle ID writes
//
// Bodies verified against Apple's OpenAPI spec (EvanBacon mirror of the
// official spec):
// - POST /v1/bundleIds: attributes identifier + name + platform (all
//   required), seedId optional. Platform enum is BundleIdPlatform:
//   IOS, MAC_OS (no UNIVERSAL — that's device-only in practice).
// - PATCH /v1/bundleIds/{id}: attributes name only ("Modify a bundle id:
//   Update a specific bundle ID's name" — Apple docs).
// - DELETE /v1/bundleIds/{id}: delete (204, no body).
// Writes need an API key with an elevated role (Admin/Account Holder for
// provisioning); a TestFlight-only key 403s.

/// Bundle ID platform values (spec enum BundleIdPlatform).
enum BundleIdPlatformOption: String, CaseIterable {
    case IOS
    case MAC_OS

    /// Explicit mapping: derived `.capitalized` would render "Ios" /
    /// "Mac Os". Two stable cases, same precedent as DevicePlatform.
    var displayName: String {
        switch self {
        case .IOS: return "iOS"
        case .MAC_OS: return "macOS"
        }
    }
}

struct BundleIdCreateRequest: Encodable {
    var data: BundleIdCreateData
}

struct BundleIdCreateData: Encodable {
    var type = "bundleIds"
    var attributes: BundleIdCreateAttributes
}

struct BundleIdCreateAttributes: Encodable {
    var name: String
    var identifier: String
    var platform: String
    /// Optional team seed id; nil is omitted from the body (encodeIfPresent).
    var seedId: String?
}

struct BundleIdUpdateRequest: Encodable {
    var data: BundleIdUpdateData
}

struct BundleIdUpdateData: Encodable {
    var type = "bundleIds"
    var id: String
    var attributes: BundleIdUpdateAttributes
}

struct BundleIdUpdateAttributes: Encodable {
    var name: String
}

// MARK: - Batch I (I3): user + invitation writes
//
// Shapes verified against Apple's OpenAPI spec (EvanBacon mirror):
// - UserRole enum (11 values): ADMIN, FINANCE, TECHNICAL, ACCOUNT_HOLDER,
//   READ_ONLY, SALES, MARKETING, APP_MANAGER, DEVELOPER, ACCESS_TO_REPORTS,
//   CUSTOMER_SUPPORT.
// - PATCH /v1/users/{id}: attributes roles/allAppsVisible/provisioningAllowed
//   (all optional); DELETE /v1/users/{id} removes the user (204).
// - POST /v1/userInvitations: attributes email + firstName + lastName +
//   roles (all required), allAppsVisible/provisioningAllowed optional.
// - GET /v1/userInvitations supports filter[email] (used by resend: find
//   the pending invite, delete it, re-create). There is no dedicated
//   resend endpoint.
// Writes need an Admin/Account Holder key; a TestFlight-only key 403s.

/// User roles (spec enum UserRole). Raw values are the wire form.
enum UserRoleOption: String, CaseIterable {
    case ADMIN
    case FINANCE
    case TECHNICAL
    case ACCOUNT_HOLDER
    case READ_ONLY
    case SALES
    case MARKETING
    case APP_MANAGER
    case DEVELOPER
    case ACCESS_TO_REPORTS
    case CUSTOMER_SUPPORT

    /// SNAKE_CASE → title case ("APP_MANAGER" → "App Manager"). Derived so
    /// new enum values render sanely; "To" is lowercased to read naturally.
    var displayName: String {
        rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
            .replacingOccurrences(of: " To ", with: " to ")
    }
}

@ResourceWrapper(type: "userInvitations")
struct UserInvitationModel: Equatable {
    static func == (lhs: UserInvitationModel, rhs: UserInvitationModel) -> Bool {
        return lhs.id == rhs.id
    }

    var id: String

    @ResourceAttribute var email: String?
    @ResourceAttribute var firstName: String?
    @ResourceAttribute var lastName: String?
    @ResourceAttribute var expirationDate: String?
    @ResourceAttribute var roles: [String]?
    @ResourceAttribute var allAppsVisible: Bool?
    @ResourceAttribute var provisioningAllowed: Bool?
}

typealias UserInvitationsDocument = CompoundDocument<[UserInvitationModel], Meta>

struct UserUpdateRequest: Encodable {
    var data: UserUpdateData
}

struct UserUpdateData: Encodable {
    var type = "users"
    var id: String
    var attributes: UserUpdateAttributes
}

struct UserUpdateAttributes: Encodable {
    var roles: [String]
}

struct UserInvitationCreateRequest: Encodable {
    var data: UserInvitationCreateData
}

struct UserInvitationCreateData: Encodable {
    var type = "userInvitations"
    var attributes: UserInvitationCreateAttributes
}

struct UserInvitationCreateAttributes: Encodable {
    var email: String
    var firstName: String
    var lastName: String
    var roles: [String]
    var allAppsVisible: Bool
    var provisioningAllowed: Bool
}

// MARK: - Batch I (I4): provisioning profile writes
//
// Body verified against Apple's OpenAPI spec (EvanBacon mirror):
// - POST /v1/profiles: attributes name + profileType (both required);
//   relationships bundleId (single, required) + certificates (array,
//   required) + devices (array, optional — required server-side only for
//   development/adhoc types).
// - DELETE /v1/profiles/{id} (204, no body).
// Writes need an Admin/Account Holder key; a TestFlight-only key 403s.

/// Profile types (spec enum on ProfileCreateRequest attributes, 14 values).
enum ProfileTypeOption: String, CaseIterable {
    case IOS_APP_DEVELOPMENT
    case IOS_APP_STORE
    case IOS_APP_ADHOC
    case IOS_APP_INHOUSE
    case MAC_APP_DEVELOPMENT
    case MAC_APP_STORE
    case MAC_APP_DIRECT
    case TVOS_APP_DEVELOPMENT
    case TVOS_APP_STORE
    case TVOS_APP_ADHOC
    case TVOS_APP_INHOUSE
    case MAC_CATALYST_APP_DEVELOPMENT
    case MAC_CATALYST_APP_STORE
    case MAC_CATALYST_APP_DIRECT

    /// SNAKE_CASE → title case ("IOS_APP_ADHOC" → "iOS App Adhoc").
    /// Derived so new enum values render sanely without touching this.
    var displayName: String {
        rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
            .replacingOccurrences(of: "Ios", with: "iOS")
            .replacingOccurrences(of: "Tvos", with: "tvOS")
    }
}

struct ProfileCreateRequest: Encodable {
    var data: ProfileCreateData
}

struct ProfileCreateData: Encodable {
    var type = "profiles"
    var attributes: ProfileCreateAttributes
    var relationships: ProfileCreateRelationships
}

struct ProfileCreateAttributes: Encodable {
    var name: String
    var profileType: String
}

struct ProfileCreateRelationships: Encodable {
    var bundleId: ProfileCreateSingleRelationship
    var certificates: ProfileCreateArrayRelationship
    /// Omitted when empty (encodeIfPresent) — optional server-side except
    /// for development/adhoc types, where the server rejects the create.
    var devices: ProfileCreateArrayRelationship?
}

struct ProfileCreateSingleRelationship: Encodable {
    var data: ProfileCreateRef
}

struct ProfileCreateArrayRelationship: Encodable {
    var data: [ProfileCreateRef]
}

struct ProfileCreateRef: Encodable {
    var type: String
    var id: String
}
