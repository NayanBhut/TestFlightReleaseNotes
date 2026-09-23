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
    @ResourceAttribute var uploadedDate: String?
    @ResourceAttribute var processingState: String?
    @ResourceAttribute var expired: Bool?
    @ResourceRelationship var preReleaseVersion: PreReleaseVersionsModel?
    /// Owning app — fetched by the Batch H poller (include=app; hydrated
    /// from the included array) so menu bar rows and notifications can name
    /// the app on multi-app accounts.
    @ResourceRelationship var app: AppsData?
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

// MARK: - Batch G (#10): App Info writes
//
// PATCH /v1/appInfoLocalizations/{id} — attribute set verified against
// Apple's OpenAPI spec (v4.4.1, AppInfoLocalizationUpdateRequest): name,
// subtitle, privacyPolicyUrl, privacyChoicesUrl, privacyPolicyText, all
// nullable. `locale` is intentionally absent — it is immutable on update.
//
// Attribute semantics: a field set to .unchanged is omitted from the JSON
// entirely; .clear encodes an explicit JSON null (spec-marked nullable),
// which is how a subtitle or privacy URL is removed; .set sends the value.
// Synthesized encodeIfPresent can't express "null vs absent", hence the
// custom encode(to:).
struct AppInfoLocalizationUpdateRequest: Encodable {
    var data: AppInfoLocalizationUpdateData
}

struct AppInfoLocalizationUpdateData: Encodable {
    var type = "appInfoLocalizations"
    var id: String
    var attributes: AppInfoLocalizationUpdateAttributes
}

enum AppInfoLocalizationFieldValue: Equatable {
    /// Omit from the request body (leave unchanged).
    case unchanged
    /// Send JSON null (clear the field server-side).
    case clear
    /// Send the string value.
    case set(String)
}

struct AppInfoLocalizationUpdateAttributes: Encodable {
    var name: AppInfoLocalizationFieldValue
    var subtitle: AppInfoLocalizationFieldValue
    var privacyPolicyUrl: AppInfoLocalizationFieldValue
    var privacyChoicesUrl: AppInfoLocalizationFieldValue

    private enum CodingKeys: String, CodingKey {
        case name, subtitle, privacyPolicyUrl, privacyChoicesUrl
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch name {
        case .unchanged: break
        case .clear: try container.encodeNil(forKey: .name)
        case .set(let value): try container.encode(value, forKey: .name)
        }
        switch subtitle {
        case .unchanged: break
        case .clear: try container.encodeNil(forKey: .subtitle)
        case .set(let value): try container.encode(value, forKey: .subtitle)
        }
        switch privacyPolicyUrl {
        case .unchanged: break
        case .clear: try container.encodeNil(forKey: .privacyPolicyUrl)
        case .set(let value): try container.encode(value, forKey: .privacyPolicyUrl)
        }
        switch privacyChoicesUrl {
        case .unchanged: break
        case .clear: try container.encodeNil(forKey: .privacyChoicesUrl)
        case .set(let value): try container.encode(value, forKey: .privacyChoicesUrl)
        }
    }
}

/// Client-side limits mirroring App Store Connect rules (Help: name 2–30
/// chars, subtitle ≤ 30 chars) so obvious rejections surface without a
/// network round-trip. The server remains the source of truth.
enum AppInfoLocalizationLimits {
    static let nameMinLength = 2
    static let nameMaxLength = 30
    static let subtitleMaxLength = 30
}

// MARK: - Batch I (I6): version localization writes
//
// PATCH /v1/appStoreVersionLocalizations/{id} — attribute set verified
// against Apple's OpenAPI spec (AppStoreVersionLocalizationUpdateRequest):
// description, keywords, marketingUrl, promotionalText, supportUrl,
// whatsNew, all nullable. `locale` is immutable on update.
// Field semantics reuse AppInfoLocalizationFieldValue (unchanged = omit,
// clear = JSON null, set = value) — the encoding contract is identical.

struct VersionLocalizationUpdateRequest: Encodable {
    var data: VersionLocalizationUpdateData
}

struct VersionLocalizationUpdateData: Encodable {
    var type = "appStoreVersionLocalizations"
    var id: String
    var attributes: VersionLocalizationUpdateAttributes
}

struct VersionLocalizationUpdateAttributes: Encodable {
    var descriptionData: AppInfoLocalizationFieldValue
    var keywords: AppInfoLocalizationFieldValue
    var marketingUrl: AppInfoLocalizationFieldValue
    var promotionalText: AppInfoLocalizationFieldValue
    var supportUrl: AppInfoLocalizationFieldValue
    var whatsNew: AppInfoLocalizationFieldValue

    private enum CodingKeys: String, CodingKey {
        // The wire key is `description` (see the model comment above).
        case descriptionData = "description"
        case keywords, marketingUrl, promotionalText, supportUrl, whatsNew
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try Self.encodeField(descriptionData, forKey: .descriptionData, in: &container)
        try Self.encodeField(keywords, forKey: .keywords, in: &container)
        try Self.encodeField(marketingUrl, forKey: .marketingUrl, in: &container)
        try Self.encodeField(promotionalText, forKey: .promotionalText, in: &container)
        try Self.encodeField(supportUrl, forKey: .supportUrl, in: &container)
        try Self.encodeField(whatsNew, forKey: .whatsNew, in: &container)
    }

    private static func encodeField(_ field: AppInfoLocalizationFieldValue,
                                    forKey key: CodingKeys,
                                    in container: inout KeyedEncodingContainer<CodingKeys>) throws {
        switch field {
        case .unchanged: break
        case .clear: try container.encodeNil(forKey: key)
        case .set(let value): try container.encode(value, forKey: key)
        }
    }
}

/// Client-side limits from Apple's metadata rules: keywords ≤ 100,
/// promotionalText ≤ 170, description/whatsNew ≤ 4000, URLs must be http(s).
/// The server remains the source of truth.
enum VersionLocalizationLimits {
    static let keywordsMaxLength = 100
    static let promotionalTextMaxLength = 170
    static let descriptionMaxLength = 4000
    static let whatsNewMaxLength = 4000
}

// MARK: - Screenshots (Batch J F4)

// Display types verified against spec v4.3.1 (subset covering the current
// device lineup; the picker offers these — the server validates the rest).
enum ScreenshotDisplayType: String, CaseIterable {
    case iPhone67 = "APP_IPHONE_67"
    case iPhone61 = "APP_IPHONE_61"
    case iPhone65 = "APP_IPHONE_65"
    case iPhone58 = "APP_IPHONE_58"
    case iPad129 = "APP_IPAD_PRO_3GEN_129"
    case iPad11 = "APP_IPAD_PRO_3GEN_11"
    case desktop = "APP_DESKTOP"
    case watchUltra = "APP_WATCH_ULTRA"
    case appleTV = "APP_APPLE_TV"
    case visionPro = "APP_APPLE_VISION_PRO"

    var displayName: String {
        switch self {
        case .iPhone67: return "iPhone 6.7\""
        case .iPhone61: return "iPhone 6.1\""
        case .iPhone65: return "iPhone 6.5\""
        case .iPhone58: return "iPhone 5.8\""
        case .iPad129: return "iPad 12.9\""
        case .iPad11: return "iPad 11\""
        case .desktop: return "Desktop"
        case .watchUltra: return "Watch Ultra"
        case .appleTV: return "Apple TV"
        case .visionPro: return "Vision Pro"
        }
    }
}

@ResourceWrapper(type: "appScreenshotSets")
struct AppScreenshotSetModel: Equatable {
    static func == (lhs: AppScreenshotSetModel, rhs: AppScreenshotSetModel) -> Bool {
        return lhs.id == rhs.id
    }

    var id: String

    @ResourceAttribute var screenshotDisplayType: String?
}

struct HttpHeader: Equatable, Codable {
    var name: String?
    var value: String?
}

struct UploadOperation: Equatable, Codable {
    var method: String?
    var url: String?
    var length: Int?
    var offset: Int?
    var requestHeaders: [HttpHeader]?
}

@ResourceWrapper(type: "appScreenshots")
struct AppScreenshotModel: Equatable {
    static func == (lhs: AppScreenshotModel, rhs: AppScreenshotModel) -> Bool {
        return lhs.id == rhs.id
    }

    var id: String

    @ResourceAttribute var fileName: String?
    @ResourceAttribute var fileSize: Int?
    @ResourceAttribute var uploaded: Bool?
    @ResourceAttribute var sourceFileChecksum: String?
    @ResourceAttribute var imageAsset: IconAsset?
    @ResourceAttribute var uploadOperations: [UploadOperation]?
}

typealias AppScreenshotSetsDocument = CompoundDocument<[AppScreenshotSetModel], Meta>
typealias AppScreenshotsDocument = CompoundDocument<[AppScreenshotModel], Meta>

/// POST /v1/appScreenshotSets — attributes.screenshotDisplayType required,
/// relationships.appStoreVersionLocalization required.
struct ScreenshotSetCreateRequest: Codable {
    let data: ScreenshotSetCreateData
}

struct ScreenshotSetCreateData: Codable {
    let type: String = "appScreenshotSets"
    let attributes: ScreenshotSetCreateAttributes
    let relationships: ScreenshotSetLocalizationLinkage
}

struct ScreenshotSetCreateAttributes: Codable {
    let screenshotDisplayType: String
}

struct ScreenshotSetLocalizationLinkage: Codable {
    let appStoreVersionLocalization: ScreenshotSetLocalizationRef
}

struct ScreenshotSetLocalizationRef: Codable {
    let data: ScreenshotSetLocalizationRefData
}

struct ScreenshotSetLocalizationRefData: Codable {
    let type: String = "appStoreVersionLocalizations"
    let id: String
}

/// POST /v1/appScreenshots — fileName + fileSize required, linked to a set.
/// The response carries uploadOperations used for the PUT phase.
struct ScreenshotCreateRequest: Codable {
    let data: ScreenshotCreateData
}

struct ScreenshotCreateData: Codable {
    let type: String = "appScreenshots"
    let attributes: ScreenshotCreateAttributes
    let relationships: ScreenshotSetLinkage
}

struct ScreenshotCreateAttributes: Codable {
    let fileName: String
    let fileSize: Int
}

struct ScreenshotSetLinkage: Codable {
    let appScreenshotSet: ScreenshotSetRef
}

struct ScreenshotSetRef: Codable {
    let data: ScreenshotSetRefData
}

struct ScreenshotSetRefData: Codable {
    let type: String = "appScreenshotSets"
    let id: String
}

/// PATCH /v1/appScreenshots/{id} — marks the asset uploaded after the
/// PUT phase completes. sourceFileChecksum is optional; omitted here.
struct ScreenshotUpdateRequest: Codable {
    let data: ScreenshotUpdateData
}

struct ScreenshotUpdateData: Codable {
    let type: String = "appScreenshots"
    let id: String
    let attributes: ScreenshotUpdateAttributes
}

struct ScreenshotUpdateAttributes: Codable {
    let uploaded: Bool
}

// MARK: - In-app events + webhooks (Batch J F5, read-only)

// GET /v1/apps/{id}/appEvents — composed with the /apps prefix + path,
// like appInfos. Attributes verified against spec v4.3.1 (badge enum:
// LIVE_EVENT, PREMIERE, CHALLENGE, COMPETITION, NEW_SEASON,
// MAJOR_UPDATE, SPECIAL_EVENT).
@ResourceWrapper(type: "appEvents")
struct AppEventModel: Equatable {
    static func == (lhs: AppEventModel, rhs: AppEventModel) -> Bool {
        return lhs.id == rhs.id
    }

    var id: String

    @ResourceAttribute var referenceName: String?
    @ResourceAttribute var badge: String?
    /// DRAFT, READY_FOR_REVIEW, WAITING_FOR_REVIEW, IN_REVIEW, ACCEPTED, …
    @ResourceAttribute var eventState: String?
}

// GET /v1/apps/{id}/webhooks — same composition. Attributes verified
// against spec v4.3.1 (enabled: boolean, eventTypes: array, name, url).
@ResourceWrapper(type: "webhooks")
struct WebhookModel: Equatable {
    static func == (lhs: WebhookModel, rhs: WebhookModel) -> Bool {
        return lhs.id == rhs.id
    }

    var id: String

    @ResourceAttribute var name: String?
    @ResourceAttribute var url: String?
    @ResourceAttribute var enabled: Bool?
    @ResourceAttribute var eventTypes: [String]?
}

typealias AppEventsDocument = CompoundDocument<[AppEventModel], Meta>
typealias WebhooksDocument = CompoundDocument<[WebhookModel], Meta>
