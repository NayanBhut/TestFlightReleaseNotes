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
    /// Base64 DER (.cer). Only present on GET /v1/certificates/{id} —
    /// never in list responses.
    @ResourceAttribute var certificateContent: String?
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
struct ProfileModel: Equatable, Identifiable {
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
    /// Base64 .mobileprovision. Only present on GET /v1/profiles/{id} —
    /// never in list responses.
    @ResourceAttribute var profileContent: String?
    /// Devices embedded in this profile — hydrated only when the fetch
    /// uses include=devices (dependent-profile lookup); empty linkage
    /// decodes to []. The relationships key itself is required by the
    /// decoder when declared — real list responses always carry linkage
    /// (same exposure as BuildsModel relationships on unincluded fetches).
    @ResourceRelationship var devices: [DeviceModel]
    /// Signing certificates — hydrated only with include=certificates.
    @ResourceRelationship var certificates: [CertificateModel]
    /// Bundle ID — hydrated only with include=bundleId (profiles list
    /// and detail fetches use it for the Bundle ID column/inspector).
    @ResourceRelationship var bundleId: BundleIdModel?
}

/// List/detail status. The API only reports ACTIVE/INVALID — "Expired"
/// is derived client-side from expirationDate (Figma 3-5273 red dot).
enum ProfileComputedStatus: Equatable {
    case active
    case expired
    case invalid

    var displayName: String {
        switch self {
        case .active: return "Active"
        case .expired: return "Expired"
        case .invalid: return "Invalid"
        }
    }
}

extension ProfileModel {
    /// Server INVALID wins; otherwise past-expiry means expired.
    /// Missing/unparseable dates never claim expiry.
    var computedStatus: ProfileComputedStatus {
        if profileState == "INVALID" { return .invalid }
        if let raw = expirationDate,
           let date = ProfileModel.parseDate(raw),
           date < Date() {
            return .expired
        }
        return .active
    }

    /// ISO-8601 with or without fractional seconds (same tolerance as
    /// the table's expiry display).
    static func parseDate(_ raw: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: raw) { return date }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: raw)
    }
}

@ResourceWrapper(type: "users")
struct UserModel: Equatable, Identifiable {
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
    /// Apps this user can access — hydrated only with include=visibleApps
    /// (app-scope labels, edit-user chooser). Links-only linkage on
    /// unincluded fetches decodes to [], same as other relationships.
    @ResourceRelationship var visibleApps: [AppsData]
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

    // PATCH semantics: only the supplied attribute is sent. Synthesized
    // Encodable would emit `"status": null` on a rename (and `"name":
    // null` on an enable/disable) — omit absent keys instead.
    private enum CodingKeys: String, CodingKey {
        case name
        case status
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(status, forKey: .status)
    }
}

/// One provisioning profile that embeds a given device, for the device
/// detail's "Dependent profiles" table (Figma 114-3013). There is no
/// GET /v1/devices/{id}/profiles endpoint, so these are resolved by
/// scanning GET /v1/profiles?include=devices,certificates and matching
/// hydrated device ids (see ResourcesViewModel.loadDependentProfiles).
/// Signing-certificate names come from include=certificates.
struct DependentProfile: Equatable {
    var profile: ProfileModel
    /// displayName ?? name per signing certificate on the profile.
    var certificateNames: [String]

    var profileTypeDisplayName: String {
        ProfileTypeOption(rawValue: profile.profileType ?? "")?.displayName
            ?? profile.profileType ?? "—"
    }
}

/// One parsed row of a devices CSV/text import file: `name,udid[,platform]`.
/// There is no bulk-register endpoint — the view model registers rows one
/// POST /v1/devices at a time and reports per-row failures.
struct DeviceCSVRow: Equatable {
    var name: String
    var udid: String
    var platform: DevicePlatform
}

/// Client-side parser for the devices empty-state "import a CSV / text
/// file" flow (Figma 114-12528). Pure logic, no API key needed. Rules:
/// one device per line, comma- or tab-separated `name,udid[,platform]`;
/// blank lines and `#` comments skipped; a leading `name,udid,...` header
/// skipped; blank platform defaults to iOS; rows with a blank name, an
/// unparseable UDID, or an unknown platform are rejected (counted, not
/// thrown, so the preview can report them).
enum DeviceCSVImport {
    /// Files larger than this are refused before parsing (1 MB ≈ 10k+
    /// devices; a real list is a few KB).
    private static let maxCSVFileSize = 1_024 * 1_024

    static func parse(_ content: String) -> (rows: [DeviceCSVRow], rejected: Int) {
        var rows: [DeviceCSVRow] = []
        var rejected = 0
        var isFirstLine = true
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            // Header row (`name,udid,platform`, any case) is skipped.
            if isFirstLine, isHeader(line) {
                isFirstLine = false
                continue
            }
            isFirstLine = false
            let fields = line.components(separatedBy: ",").count >= 2
                ? line.components(separatedBy: ",")
                : line.components(separatedBy: "\t")
            guard fields.count >= 2 else {
                rejected += 1
                continue
            }
            let name = fields[0].trimmingCharacters(in: .whitespaces)
            let udid = fields[1].trimmingCharacters(in: .whitespaces)
            let platformToken = fields.count >= 3
                ? fields[2].trimmingCharacters(in: .whitespaces).uppercased()
                : ""
            guard !name.isEmpty,
                  ProvisioningWriteValidation.isValidUDID(udid),
                  let platform = platform(matching: platformToken) else {
                rejected += 1
                continue
            }
            rows.append(DeviceCSVRow(name: name, udid: udid, platform: platform))
        }
        return (rows, rejected)
    }

    /// Loads import-file text from a user-picked .csv/.txt file: checks
    /// size, reads as UTF-8, rejects empty content. Throws user-facing
    /// errors so the form just displays `errorDescription`.
    static func load(from url: URL) throws -> String {
        // Security-scoped URLs (open panel) need explicit access.
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        guard fileSize > 0, fileSize <= maxCSVFileSize else {
            throw CSVFileLoadError.tooLarge
        }
        guard let data = try? Data(contentsOf: url),
              !data.isEmpty else {
            throw CSVFileLoadError.unreadable
        }
        let content = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw CSVFileLoadError.unreadable
        }
        return content
    }

    private static func isHeader(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return lowered.contains("name") && lowered.contains("udid")
    }

    /// Blank defaults to iOS (same default as the register form); known
    /// aliases map to the spec's BundleIdPlatform values (IOS, MAC_OS).
    /// UNIVERSAL is accepted — the register form offers it — but note the
    /// devices list filter only documents IOS/MAC_OS.
    private static func platform(matching token: String) -> DevicePlatform? {
        switch token {
        case "", "IOS", "IPHONE", "IPAD":
            return .IOS
        case "MAC_OS", "MACOS", "MAC":
            return .MAC_OS
        case "UNIVERSAL":
            return .UNIVERSAL
        default:
            return nil
        }
    }
}

/// File-picker failures for device CSV import. Messages are shown verbatim.
enum CSVFileLoadError: Error, LocalizedError, Equatable {
    case unreadable
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "Couldn't read that file. Pick a .csv or .txt file with one device per line."
        case .tooLarge:
            return "That file is too large to be a device list (max 1 MB)."
        }
    }
}

/// One CSV row that failed to register, with the server/client message.
struct DeviceCSVFailure: Equatable {
    var row: DeviceCSVRow
    var message: String
}

/// Outcome of a CSV import run: sequential POSTs, so successes and
/// per-row failures are both reported in the result sheet.
struct DeviceCSVImportResult: Equatable, Identifiable {
    var registered: Int
    var failures: [DeviceCSVFailure]

    var id: String { "import-\(registered)-\(failures.count)" }
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

    /// Wizard eligibility (Figma 114-3438 "matching type enforced"):
    /// development profile kinds only accept *DEVELOPMENT* certs,
    /// everything else only *DISTRIBUTION* certs. The legacy unprefixed
    /// DEVELOPMENT/DISTRIBUTION match every platform.
    func matchesKind(development: Bool) -> Bool {
        development ? rawValue.contains("DEVELOPMENT") : rawValue.contains("DISTRIBUTION")
    }

    /// Platform prefix match for the wizard picker. tvOS has no dedicated
    /// cert types — it shares the iOS signing identities.
    func matchesPlatform(_ platformCode: String) -> Bool {
        if !(rawValue.hasPrefix("IOS_") || rawValue.hasPrefix("MAC_")) { return true }
        switch platformCode {
        case "MAC_OS": return rawValue.hasPrefix("MAC_")
        default: return rawValue.hasPrefix("IOS_")
        }
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

    /// Maximum CSR file size accepted (64 KB). A real CSR is ~1 KB; this
    /// stops a huge/missing file on a slow volume from freezing the UI or
    /// spiking memory before content validation even runs.
    private static let maxCSRFileSize = 64 * 1024

    /// Loads CSR content from a user-picked file: checks size, reads,
    /// trims, validates PEM markers. Throws user-facing errors so the
    /// form just displays `errorDescription` — the raw CSR text never
    /// surfaces in the UI.
    static func loadCSR(from url: URL) throws -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        guard fileSize > 0, fileSize <= maxCSRFileSize else {
            throw CSRFileLoadError.tooLarge
        }
        guard let data = try? Data(contentsOf: url) else {
            throw CSRFileLoadError.unreadable
        }
        let content = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidCSR(content) else {
            throw CSRFileLoadError.invalidFormat
        }
        return content
    }
}

/// File-picker failures for CSR upload. Messages are shown verbatim in
/// the create-certificate form.
enum CSRFileLoadError: Error, LocalizedError, Equatable {
    case unreadable
    case invalidFormat
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "Couldn't read that file. Try selecting it again."
        case .invalidFormat:
            return "That file doesn't look like a CSR — expected a PEM file with \"-----BEGIN CERTIFICATE REQUEST-----\" markers."
        case .tooLarge:
            return "That file is too large to be a CSR. Pick the .csr file from Keychain Access or openssl."
        }
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

    /// One-line remit shown under each role checkbox in the invite and
    /// edit-user flows (Figma 114-4499 / 114-4278 copy).
    var description: String {
        switch self {
        case .ADMIN: return "All team administration."
        case .APP_MANAGER: return "App lifecycle and metadata."
        case .DEVELOPER: return "Development and TestFlight access."
        case .MARKETING: return "Marketing metadata."
        case .CUSTOMER_SUPPORT: return "Customer review responses."
        case .FINANCE: return "Financial access."
        case .SALES: return "Sales access."
        case .ACCESS_TO_REPORTS: return "Report access is independent of app editing."
        case .TECHNICAL: return "Technical role."
        case .READ_ONLY: return "Read-only access."
        case .ACCOUNT_HOLDER: return "Account Holder — protected, not editable here."
        }
    }

    /// Roles the invite/edit checkboxes offer. Excludes ACCOUNT_HOLDER
    /// (cannot be granted via the API) — the holder renders read-only.
    static var grantableCases: [UserRoleOption] {
        allCases.filter { $0 != .ACCOUNT_HOLDER }
    }
}

@ResourceWrapper(type: "userInvitations")
struct UserInvitationModel: Equatable, Identifiable {
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
    /// Apps granted by this invitation — hydrated only with
    /// include=visibleApps (pending-list scope column, resend recap).
    @ResourceRelationship var visibleApps: [AppsData]
}

typealias UserInvitationsDocument = CompoundDocument<[UserInvitationModel], Meta>

struct UserUpdateRequest: Encodable {
    var data: UserUpdateData
}

struct UserUpdateData: Encodable {
    var type = "users"
    var id: String
    var attributes: UserUpdateAttributes
    /// Present only when the app scope changes (selected-apps edit).
    var relationships: UserUpdateRelationships?
}

/// Full PATCH body (spec UserUpdateRequest): roles, allAppsVisible and
/// provisioningAllowed are all optional; absent keys are omitted so an
/// edit never nulls a field it didn't touch.
struct UserUpdateAttributes: Encodable {
    var roles: [String]?
    var allAppsVisible: Bool?
    var provisioningAllowed: Bool?

    private enum CodingKeys: String, CodingKey {
        case roles
        case allAppsVisible
        case provisioningAllowed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(roles, forKey: .roles)
        try container.encodeIfPresent(allAppsVisible, forKey: .allAppsVisible)
        try container.encodeIfPresent(provisioningAllowed, forKey: .provisioningAllowed)
    }
}

struct UserUpdateRelationships: Encodable {
    var visibleApps: UserInvitationVisibleAppsRelationship
}

struct UserInvitationCreateRequest: Encodable {
    var data: UserInvitationCreateData
}

struct UserInvitationCreateData: Encodable {
    var type = "userInvitations"
    var attributes: UserInvitationCreateAttributes
    /// Present only for single-app invites (allAppsVisible == false).
    var relationships: UserInvitationCreateRelationships?
}

struct UserInvitationCreateRelationships: Encodable {
    var visibleApps: UserInvitationVisibleAppsRelationship
}

struct UserInvitationVisibleAppsRelationship: Encodable {
    var data: [UserInvitationAppRef]
}

struct UserInvitationAppRef: Encodable {
    var type = "apps"
    var id: String
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

    /// Only development and ad-hoc profiles embed devices. Store,
    /// in-house and direct-distribution profiles reject the devices
    /// relationship (409 ENTITY_ERROR.RELATIONSHIP.NOT_ALLOWED).
    var allowsDevices: Bool {
        rawValue.hasSuffix("_DEVELOPMENT") || rawValue.hasSuffix("_ADHOC")
    }

    /// Short distribution kind ("Development", "Ad Hoc", "App Store",
    /// "In-House", "Direct") for recaps and detail subtitles.
    var shortKindName: String {
        if rawValue.hasSuffix("_DEVELOPMENT") { return "Development" }
        if rawValue.hasSuffix("_ADHOC") { return "Ad Hoc" }
        if rawValue.hasSuffix("_STORE") { return "App Store" }
        if rawValue.hasSuffix("_INHOUSE") { return "In-House" }
        if rawValue.hasSuffix("_DIRECT") { return "Direct" }
        return displayName
    }
    /// Distribution family for the wizard: development kinds need
    /// development certificates, everything else needs distribution
    /// certificates (Figma 114-3438 "matching type enforced").
    var needsDevelopmentCertificates: Bool {
        rawValue.hasSuffix("_DEVELOPMENT")
    }

    /// BundleId platform code implied by the type prefix (wizard +
    /// device picker filtering). Mac Catalyst profiles take Mac IDs.
    var bundlePlatformCode: String {
        if rawValue.hasPrefix("MAC_") { return "MAC_OS" }
        if rawValue.hasPrefix("TVOS_") { return "TVOS" }
        return "IOS"
    }

    /// Wizard distribution kind (Figma 114-3320 radios).
    enum DistributionKind: String, CaseIterable, Hashable {
        case development = "Development"
        case adHoc = "Ad Hoc"
        case appStore = "App Store"

        var hint: String {
            switch self {
            case .development:
                return "Requires development certificates and registered devices."
            case .adHoc:
                return "Requires distribution certificates and registered devices."
            case .appStore:
                return "Requires a compatible distribution certificate; devices are skipped."
            }
        }
    }

    /// Resolve platform + kind to a concrete type, or nil for
    /// unsupported combinations (e.g. macOS Ad Hoc doesn't exist).
    /// `otherType` covers In-House/Direct/Catalyst picks outside the
    /// three Figma kinds — nil kind means `otherType` must be set.
    static func resolve(platformCode: String,
                        kind: DistributionKind?,
                        otherType: ProfileTypeOption? = nil) -> ProfileTypeOption? {
        if let kind {
            switch (platformCode, kind) {
            case ("IOS", .development): return .IOS_APP_DEVELOPMENT
            case ("IOS", .adHoc): return .IOS_APP_ADHOC
            case ("IOS", .appStore): return .IOS_APP_STORE
            case ("MAC_OS", .development): return .MAC_APP_DEVELOPMENT
            case ("MAC_OS", .appStore): return .MAC_APP_STORE
            case ("TVOS", .development): return .TVOS_APP_DEVELOPMENT
            case ("TVOS", .adHoc): return .TVOS_APP_ADHOC
            case ("TVOS", .appStore): return .TVOS_APP_STORE
            default: return nil
            }
        }
        return otherType
    }

    /// Remaining types for a platform outside the three Figma kinds.
    static func otherTypes(for platformCode: String) -> [ProfileTypeOption] {
        switch platformCode {
        case "MAC_OS": return [.MAC_APP_DIRECT, .MAC_CATALYST_APP_DEVELOPMENT,
                               .MAC_CATALYST_APP_STORE, .MAC_CATALYST_APP_DIRECT]
        case "TVOS": return [.TVOS_APP_INHOUSE]
        default: return [.IOS_APP_INHOUSE]
        }
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
