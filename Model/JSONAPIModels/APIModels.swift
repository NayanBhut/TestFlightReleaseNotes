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
    @ResourceRelationship var appStoreVersions: [AppStoreVersionsModel]
    
    var currentLiveVersion = ("", "") // id, versionString
    var currentState = ""
    var isSelected = false
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
    
    var isUpdatingLocalize = false
}

@ResourceWrapper(type: "appStoreVersionLocalizations")
struct AppStoreVersionLocalizationsModel: Equatable {
    var id: String
    @ResourceAttribute var descriptionData: String?
    @ResourceAttribute var keywords: String?
    @ResourceAttribute var marketingUrl: String?
    @ResourceAttribute var supportUrl: String?
    @ResourceAttribute var whatsNew: String?
}

@ResourceWrapper(type: "betaBuildLocalizations")
struct BuildLocalizationsModel: Equatable {
    var id: String
    @ResourceAttribute var locale: String?
    @ResourceAttribute var whatsNew: String?
    @ResourceRelationship var build: BuildsModel?
}

struct Meta: Equatable, Codable {
    struct Pagination: Equatable, Codable {
        let total: Int
        let limit: Int
        let nextCursor: String?
    }
    
    let paging: Pagination
}


typealias BuildsDocument = CompoundDocument<[BuildsModel], Meta>
typealias AppsDocument = CompoundDocument<[AppsData], Meta>
