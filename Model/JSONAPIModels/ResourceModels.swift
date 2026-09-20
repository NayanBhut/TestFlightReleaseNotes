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

// Documents: devices/bundleIds/profiles/users are cursor-paginated
// collections (paging meta always returned alongside limit), certificates
// are not (no meta in the spec'd response) — hence NoMeta for certificates.
typealias DevicesDocument = CompoundDocument<[DeviceModel], Meta>
typealias CertificatesDocument = CompoundDocument<[CertificateModel], NoMeta>
typealias BundleIdsDocument = CompoundDocument<[BundleIdModel], Meta>
typealias ProfilesDocument = CompoundDocument<[ProfileModel], Meta>
typealias UsersDocument = CompoundDocument<[UserModel], Meta>
