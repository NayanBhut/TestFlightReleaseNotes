//
//  ContentModel.swift
//  App Store
//
//  Created by Nayan Bhut on 15/02/24.
//

import Foundation
import AppStoreConnect_Swift_SDK


// [AppModel]
    // [Versions]
        // [Builds]
            // BuildData


struct AppDataModel: Identifiable, Equatable {
    static func == (lhs: AppDataModel, rhs: AppDataModel) -> Bool {
        lhs.id == rhs.id
    }
    
    var id: String
    let app: AppStoreConnect_Swift_SDK.App
    var arrVersions: [VersionDataModel]
    var isExpanded = false
}

struct VersionDataModel: Identifiable {
    var id: String
    var version: AppStoreConnect_Swift_SDK.PrereleaseVersion
    var arrBuilds: [BuildDataModel]
    var isSelected = false
}

struct BuildDataModel: Identifiable {
    var id: String
    var build: Build
    var localization: [AppStoreConnect_Swift_SDK.BetaBuildLocalization]
}
