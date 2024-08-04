//
//  AppDataModel.swift
//  App Store
//
//  Created by Nayan Bhut on 26/04/24.
//

import Foundation
import AppStoreConnect_Swift_SDK

struct AppModel: Identifiable {
    var id: String
    let app: AppStoreConnect_Swift_SDK.App
    var arrBuilds: [BuildModel]
    var isExpanded = false
}

struct BuildModel: Identifiable {
    var id: String
    var build: Build
    var localization: [AppStoreConnect_Swift_SDK.BetaBuildLocalization]
}
