//
//  APIModels.swift
//  App Store
//
//  Created by Nayan Bhut on 11/05/25.
//

import JSONAPI
import Foundation

@ResourceWrapper(type: "apps")
struct AppsData: Equatable {
    static func == (lhs: AppsData, rhs: AppsData) -> Bool {
        return lhs.id == rhs.id
    }
    
    var id: String
    
    @ResourceAttribute var name: String?
    @ResourceAttribute var bundleId: String?
    @ResourceAttribute var sku: String?
    // Batch C1: primary locale, content rights and kids flag come along free
    // with the existing GET /apps fetch (attributes return by default when
    // no fields[apps] restriction is passed).
    @ResourceAttribute var primaryLocale: String?
    @ResourceAttribute var contentRightsDeclaration: String?
    @ResourceAttribute var isOrEverWasMadeForKids: Bool?
    @ResourceRelationship var appStoreVersions: [AppStoreVersionsModel]
    @ResourceRelationship var appStoreIcon: AppIcon?
    
    var currentLiveVersion = ("", "") // id, versionString
    var currentState = ""
    var isSelected = false
    var iconURL: String?
}

@ResourceWrapper(type: "preReleaseVersions")
struct PreReleaseVersionsModel: Equatable {
    var id: String
    
    @ResourceAttribute var version: String?
    @ResourceAttribute var appStoreState: String?
    @ResourceAttribute var appVersionState: String?
    @ResourceAttribute var createdDate: String?
    @ResourceAttribute var storeIcon: StoreIcon?
//    @ResourceRelationship var appStoreVersionLocalizations: [AppStoreVersionLocalizationsModel]
    
    var isSelected = false
}

@ResourceWrapper(type: "appStoreVersions")
struct AppStoreVersionsModel: Equatable {
    var id: String
    
    @ResourceAttribute var versionString: String?
    @ResourceAttribute var appStoreState: String?
    @ResourceAttribute var appVersionState: String?
    @ResourceAttribute var createdDate: String?
    @ResourceAttribute var storeIcon: StoreIcon?
    @ResourceRelationship var appStoreVersionLocalizations: [AppStoreVersionLocalizationsModel]
}

struct StoreIcon: Equatable, Codable {
    var templateUrl: String?
    var width: Int?
    var height: Int?
}

// The resource type is "buildIcons" (Apple reuses it for app icons), but the
// relationship on apps is appStoreIcon, hence the Swift name.
@ResourceWrapper(type: "buildIcons")
struct AppIcon: Equatable {
    var id: String
    @ResourceAttribute var iconAsset: IconAsset?
}

struct IconAsset: Equatable, Codable {
    var templateUrl: String?
    var width: Int?
    var height: Int?
    var assetType: String?
}

@ResourceWrapper(type: "builds")
struct BuildsModel: Equatable {
    var id: String
    
    @ResourceAttribute var version: String?
    @ResourceAttribute var app: String?
    @ResourceAttribute var uploadedDate: String?
    @ResourceAttribute var processingState: String?
    @ResourceAttribute var expired: Bool?
    @ResourceRelationship var preReleaseVersion: PreReleaseVersionsModel?
    @ResourceRelationship var betaBuildLocalizations: [BuildLocalizationsModel]
}

@ResourceWrapper(type: "appStoreVersionLocalizations")
struct AppStoreVersionLocalizationsModel: Equatable {
    var id: String
    // The JSON:API attribute is `description`; an explicit key is required
    // or the decoder looks for `descriptionData` and the description is
    // silently dropped (latent bug surfaced by Batch C1's read-only panel).
    @ResourceAttribute(key: "description") var descriptionData: String?
    @ResourceAttribute var keywords: String?
    @ResourceAttribute var marketingUrl: String?
    @ResourceAttribute var supportUrl: String?
    @ResourceAttribute var whatsNew: String?
    @ResourceAttribute var locale: String?
    @ResourceAttribute var promotionalText: String?
}

@ResourceWrapper(type: "betaBuildLocalizations")
struct BuildLocalizationsModel: Equatable {
    var id: String
    @ResourceAttribute var locale: String?
    @ResourceAttribute var whatsNew: String?
    @ResourceRelationship var build: BuildsModel?
    
    static func updateBody(id: String, whatsNew: String) -> BuildLocalizationsModel {
        let model = BuildLocalizationsModel(id: id, locale: nil, whatsNew: whatsNew)
        return model
    }
}

/// POST body for creating a betaBuildLocalization. A plain Encodable struct
/// (not the @ResourceWrapper model) because relationship linkage cannot be
/// assigned through the wrapper's typed property.
struct CreateLocalizationRequest: Encodable {
    var data: CreateLocalizationData
}

struct CreateLocalizationData: Encodable {
    var type = "betaBuildLocalizations"
    var attributes: CreateLocalizationAttributes
    var relationships: CreateLocalizationRelationships
}

struct CreateLocalizationAttributes: Encodable {
    var locale: String
    var whatsNew: String?
}

struct CreateLocalizationRelationships: Encodable {
    var build: CreateLocalizationBuildLink
}

struct CreateLocalizationBuildLink: Encodable {
    var data: CreateLocalizationBuildRef
}

struct CreateLocalizationBuildRef: Encodable {
    var type = "builds"
    var id: String
}

struct Meta: Equatable, Codable {
    struct Pagination: Equatable, Codable {
        let total: Int
        let limit: Int
        let nextCursor: String?
    }
    
    let paging: Pagination
}

struct ExpireBuildRequest: Encodable {
    let data: ExpireBuildData
}

struct ExpireBuildData: Encodable {
    var type = "builds"
    let id: String
    let attributes: ExpireBuildAttributes
}

struct ExpireBuildAttributes: Encodable {
    let expired: Bool
}

typealias BuildsDocument = CompoundDocument<[BuildsModel], Meta>
typealias AppsDocument = CompoundDocument<[AppsData], Meta>
typealias PreReleaseVersionsDocument = CompoundDocument<[PreReleaseVersionsModel], Meta>

// MARK: - Batch C1: App Info (read-only)
//
// GET /v1/apps/{id}/appInfos?include=ageRatingDeclaration,appInfoLocalizations,
// primaryCategory,secondaryCategory(+subcategories)
//
// Meta is `NoMeta` (JSONAPI.Unit, not the paging Meta) because these are
// small, fixed lists and the response must decode whether or not the
// server includes paging. NOTE: CompoundDocument only decodes `meta` when
// the type isn't Unit. The alias exists because bare `Unit` is ambiguous
// (Foundation.Unit vs JSONAPI.Unit).
typealias NoMeta = JSONAPI.Unit

@ResourceWrapper(type: "appInfos")
struct AppInfoModel: Equatable {
    static func == (lhs: AppInfoModel, rhs: AppInfoModel) -> Bool {
        return lhs.id == rhs.id
    }

    var id: String

    @ResourceAttribute var state: String?
    // Deprecated upstream but still returned and the cheapest age rating to
    // display (e.g. FOUR_PLUS).
    @ResourceAttribute var appStoreAgeRating: String?
    @ResourceAttribute var kidsAgeBand: String?
    @ResourceRelationship var ageRatingDeclaration: AgeRatingDeclarationModel?
    @ResourceRelationship var appInfoLocalizations: [AppInfoLocalizationModel]
    @ResourceRelationship var primaryCategory: AppCategoryModel?
    @ResourceRelationship var primarySubcategoryOne: AppCategoryModel?
    @ResourceRelationship var primarySubcategoryTwo: AppCategoryModel?
    @ResourceRelationship var secondaryCategory: AppCategoryModel?
    @ResourceRelationship var secondarySubcategoryOne: AppCategoryModel?
    @ResourceRelationship var secondarySubcategoryTwo: AppCategoryModel?
}

/// Included resources arrive in the document's `included` array; the
/// @ResourceWrapper type strings must match exactly or the whole document
/// decode fails.
@ResourceWrapper(type: "ageRatingDeclarations")
struct AgeRatingDeclarationModel: Equatable {
    var id: String

    @ResourceAttribute(key: "ageRatingOverrideV2") var ageRatingOverrideV2: String?
    @ResourceAttribute var alcoholTobaccoOrDrugUseOrReferences: String?
    @ResourceAttribute var contests: String?
    @ResourceAttribute var gambling: Bool?
    @ResourceAttribute var gamblingSimulated: String?
    @ResourceAttribute var gunsOrOtherWeapons: String?
    @ResourceAttribute var horrorOrFearThemes: String?
    @ResourceAttribute var lootBox: Bool?
    @ResourceAttribute var matureOrSuggestiveThemes: String?
    @ResourceAttribute var medicalOrTreatmentInformation: String?
    @ResourceAttribute var messagingAndChat: Bool?
    @ResourceAttribute var profanityOrCrudeHumor: String?
    @ResourceAttribute var sexualContentOrNudity: String?
    @ResourceAttribute var sexualContentGraphicAndNudity: String?
    @ResourceAttribute var unrestrictedWebAccess: Bool?
    @ResourceAttribute var userGeneratedContent: Bool?
    @ResourceAttribute var violenceCartoonOrFantasy: String?
    @ResourceAttribute var violenceRealistic: String?
    @ResourceAttribute var violenceRealisticProlongedGraphicOrSadistic: String?
}

@ResourceWrapper(type: "appInfoLocalizations")
struct AppInfoLocalizationModel: Equatable {
    static func == (lhs: AppInfoLocalizationModel, rhs: AppInfoLocalizationModel) -> Bool {
        return lhs.id == rhs.id
    }

    var id: String

    @ResourceAttribute var locale: String?
    @ResourceAttribute var name: String?
    @ResourceAttribute var subtitle: String?
    @ResourceAttribute var privacyPolicyUrl: String?
    @ResourceAttribute var privacyChoicesUrl: String?
}

/// App Store categories expose no name attribute in the API — the raw id
/// (e.g. "APPS.MUSIC") is what App Store Connect returns, so display that.
@ResourceWrapper(type: "appCategories")
struct AppCategoryModel: Equatable {
    static func == (lhs: AppCategoryModel, rhs: AppCategoryModel) -> Bool {
        return lhs.id == rhs.id
    }

    var id: String
    @ResourceAttribute var platforms: [String]?
}

/// GET /v1/appEncryptionDeclarations?filter[app]={id} — the read-only
/// source for the app's export compliance state. Top-level collection:
/// no /v1/apps/{id}/appEncryptionDeclarations subpath exists.
@ResourceWrapper(type: "appEncryptionDeclarations")
struct AppEncryptionDeclarationModel: Equatable {
    static func == (lhs: AppEncryptionDeclarationModel, rhs: AppEncryptionDeclarationModel) -> Bool {
        return lhs.id == rhs.id
    }

    var id: String

    @ResourceAttribute var usesEncryption: Bool?
    @ResourceAttribute var exempt: Bool?
    @ResourceAttribute var containsProprietaryCryptography: Bool?
    @ResourceAttribute var containsThirdPartyCryptography: Bool?
    @ResourceAttribute var availableOnFrenchStore: Bool?
    @ResourceAttribute var appEncryptionDeclarationState: String?
    @ResourceAttribute var createdDate: String?
}

typealias AppInfosDocument = CompoundDocument<[AppInfoModel], NoMeta>
typealias AppEncryptionDeclarationsDocument = CompoundDocument<[AppEncryptionDeclarationModel], Meta>
typealias AppStoreVersionLocalizationsDocument = CompoundDocument<[AppStoreVersionLocalizationsModel], NoMeta>
