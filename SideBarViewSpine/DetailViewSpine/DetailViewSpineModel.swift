//
//  DetailViewSpineModel.swift
//  App Store
//
//  Created by Nayan Bhut on 04/05/24.
//

import SwiftUI

class DetailViewSpineModel: ObservableObject {
    @Published var currentAppState: CurrentAppState = .appListLoading
    @Published var arrVersions: [PreReleaseVersions] = []
    @Published var currentTeam: Team = .appName
    @Published var selectedVersion: PreReleaseVersions?
    @Published var arrBuilds: [Builds] = []
    
    var selectedApp: AppStoreApp?
    @Published var isBuildsLoaded = false
    
    init(selectedApp: AppStoreApp?, arrVersions: [PreReleaseVersions], currentTeam: Team, currentAppState: CurrentAppState) {
        self.selectedApp = selectedApp
        self.arrVersions = arrVersions
        self.currentTeam = currentTeam
        self.currentAppState = currentAppState
    }
}

extension DetailViewSpineModel {
    func setSelectedVersionAndGetBuilds(selectedVersion: PreReleaseVersions) {
        isBuildsLoaded = false
        arrVersions = arrVersions.map { version in
            let tempVersion = version
            tempVersion.isSelected = tempVersion.id == selectedVersion.id
            return tempVersion
        }
        
        guard let app = selectedApp else { return }
        getBuilds(app: app, version: selectedVersion)
    }
    
    func getBuilds(app: AppStoreApp, version: PreReleaseVersions) {
        currentAppState = .appVersionBuildLoading
        SpineManager().getVersionBuilds(for: app, for: version, for: currentTeam) { result in
            self.isBuildsLoaded = true
            self.currentAppState = ._none
            switch result {
            case .success(let success):
                print(success)
                self.selectedVersion = version
                self.arrBuilds = success as? [Builds] ?? []
//                ((successData.resources as? [Builds])?[9]?.betaBuildLocalizations?[0] as? BuildLocalizations)?.whatsNew
            case .failure(let failure):
                print(failure)
                self.selectedVersion = version
                self.arrBuilds = []
            }
        }
    }
}

extension DetailViewSpineModel {
    func createOrUpdate(buildLocalization: BuildLocalizations, localization: String, buildIndex: Int) {
        if let arrLocalizations =  arrBuilds[buildIndex].betaBuildLocalizations?.resources as? [BuildLocalizations] {
            if arrLocalizations.first(where: {$0.id != nil}) == nil {
                createBuildLocalization(buildLocalization: buildLocalization, localization: localization, buildIndex:buildIndex)
            } else {
                updateBuildLocalization(buildLocalization: buildLocalization, localization: localization, buildIndex:buildIndex)
            }
        }
    }
    
    func updateBuildLocalization(buildLocalization: BuildLocalizations, localization: String, buildIndex: Int) {
        currentAppState = .appLocalizationLoading
        SpineManager().updateBuildLocalization(for: currentTeam, localize: buildLocalization) { result in
            self.currentAppState = ._none
            switch result {
            case .success(let success):
                print(success)
                if let updatedData = (success.first as? UpdateBuildLocalizations),
                   let arrLocalizations = self.arrBuilds[buildIndex].betaBuildLocalizations?.resources  as? [BuildLocalizations],
                   let index = arrLocalizations.firstIndex(where: { $0.id == updatedData.id}) {
                    (self.arrBuilds[buildIndex].betaBuildLocalizations?.resources[index] as? BuildLocalizations)?.whatsNew = updatedData.whatsNew
                }
            case .failure(let failure):
                print(failure)
            }
        }
    }
    
    func createBuildLocalization(buildLocalization: BuildLocalizations, localization: String, buildIndex: Int) {
        currentAppState = .appLocalizationLoading
        SpineManager().createBuildLocalization(for: currentTeam, localize: buildLocalization, build: arrBuilds[buildIndex]) { result in
            self.currentAppState = ._none
            switch result {
            case .success(let success):
                print(success)
                if let updatedData = (success.first as? UpdateBuildLocalizations),
                   let arrLocalizations = self.arrBuilds[buildIndex].betaBuildLocalizations?.resources  as? [BuildLocalizations],
                   let index = arrLocalizations.firstIndex(where: { $0.id == updatedData.id}) {
                    (self.arrBuilds[buildIndex].betaBuildLocalizations?.resources[index] as? BuildLocalizations)?.whatsNew = updatedData.whatsNew
                }
            case .failure(let failure):
                print(failure)
            }
        }
    }
}
