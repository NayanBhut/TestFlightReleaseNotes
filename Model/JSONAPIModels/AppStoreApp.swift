//
//  AppStoreApp.swift
//  App Store
//
//  Created by Nayan Bhut on 01/05/24.
//

import Foundation
import Spine

class AppStoreApp: Resource, Identifiable {
    var name: String?
    var bundleId: String?
    var sku: String?
    var appStoreVersions: LinkedResourceCollection?
    var displayableVersions: LinkedResourceCollection?
    var isSelected = false
    var currentLiveVersion = ("", "") // id, versionString
    var currentState = ""
    
    override class var resourceType: ResourceType {
        return "apps"
    }
    
    override class var fields: [Field] {
        return fieldsFromDictionary([
            "name": Attribute(),
            "bundleId":Attribute(),
            "sku":Attribute(),
            "appStoreVersions": ToManyRelationship(AppStoreVersions.self).serializeAs("appStoreVersions"),
            "displayableVersions": ToManyRelationship(AppStoreVersions.self).serializeAs("displayableVersions")
        ])
    }
    
    static func == (lhs: AppStoreApp, rhs: AppStoreApp) -> Bool {
        lhs.id == rhs.id
    }
}

@objcMembers class AppStoreVersions: Resource, Identifiable {
    override class var resourceType: ResourceType {
        return "appStoreVersions"
    }
    
    var versionString: String?
    var appStoreState: String?
    var appVersionState: String?
    var createdDate: NSDate?
    var storeIcon: NSDictionary?
    var distributions: NSArray?
    var appStoreVersionLocalizations: LinkedResourceCollection?
    var build: Resource?
    
    override class var fields: [Field] {
        return fieldsFromDictionary ([
            "versionString": Attribute(),
            "appStoreState": Attribute(),
            "appVersionState": Attribute(),
            "createdDate": Attribute(),
            "storeIcon": IconAttributes(),
            "distributions": Attribute(),
            "appStoreVersionLocalizations": ToManyRelationship(AppStoreVersionLocalizations.self).serializeAs("appStoreVersionLocalizations"),
            "build": ToOneRelationship(Builds.self).serializeAs("build")
        ])
    }
}

class IconAttributes: Attribute {
    var templateUrl: String?
    var width: NSNumber?
    var height: NSNumber?
    
    init(templateUrl: String? = nil, width: NSNumber? = nil, height: NSNumber? = nil) {
        self.templateUrl = templateUrl
        self.width = width
        self.height = height
    }
}

class PreReleaseVersions: Resource, Identifiable {
    override class var resourceType: ResourceType {
        return "preReleaseVersions"
    }
    
    var versionString: String?
    var app: String?
    var version: String?
    var isSelected = false
    
    override class var fields: [Field] {
        return fieldsFromDictionary ([
            "versionString": Attribute(),
            "app": Attribute(),
            "version": Attribute()
        ])
    }
}

class Builds: Resource, Identifiable {
    override class var resourceType: ResourceType {
        return "builds"
    }
    
    var version: String?
    var app: String?
    var uploadedDate: NSDate?
    var processingState: String?
    var preReleaseVersion: LinkedResourceCollection?
    var appStoreVersion: LinkedResourceCollection?
    var betaBuildLocalizations: LinkedResourceCollection?
    var isUpdatingLocalize = false
    
    override class var fields: [Field] {
        return fieldsFromDictionary ([
            "version": Attribute(),
            "app": Attribute(),
            "uploadedDate": Attribute(),
            "preReleaseVersion": ToManyRelationship(AppStoreVersions.self).serializeAs("preReleaseVersion"),
            "appStoreVersion": ToManyRelationship(AppStoreVersions.self).serializeAs("appStoreVersion"),
            "betaBuildLocalizations": ToManyRelationship(BuildLocalizations.self).serializeAs("betaBuildLocalizations"),
            "processingState": Attribute()
        ])
    }
}

class BuildLocalizations: Resource, Identifiable {
    override class var resourceType: ResourceType {
        return "betaBuildLocalizations"
    }
    
    var whatsNew: String?
    var locale: String?
    var build: Resource?
    
    init(whatsNew: String? = nil, locale: String? = nil, build: Resource? = nil) {
        super.init()
        self.whatsNew = whatsNew
        self.locale = locale
        self.build = build
    }
    
    required init() {
        super.init()
        print("Init data")
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override class var fields: [Field] {
        return fieldsFromDictionary([
            "whatsNew": Attribute(),
            "locale": Attribute(),
            "build": ToOneRelationship(Builds.self).serializeAs("build"),
        ])
    }
    
}

class UpdateBuildLocalizations: Resource, Identifiable {
    override class var resourceType: ResourceType {
        return "betaBuildLocalizations"
    }
    
    var whatsNew: String?
    
    init(whatsNew: String? = nil) {
        super.init()
        self.whatsNew = whatsNew
    }
    required init() {
        fatalError("init() has not been implemented")
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override class var fields: [Field] {
        return fieldsFromDictionary([
            "whatsNew": Attribute()
        ])
    }
}

class AppStoreVersionLocalizations: Resource, Identifiable {
    override class var resourceType: ResourceType {
        return "appStoreVersionLocalizations"
    }
    
    var descriptionData: String?
    var keywords: String?
    var marketingUrl: String?
    var supportUrl: String?
    var whatsNew: String?
    
    
    required init() {
        super.init()
        print("Init data")
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override class var fields: [Field] {
        return fieldsFromDictionary([
            "descriptionData": Attribute().serializeAs("description"),
            "keywords": Attribute(),
            "marketingUrl": Attribute(),
            "supportUrl": Attribute(),
            "whatsNew": Attribute()
        ])
    }
    
}
