//
//  SpineAPIManager.swift
//  App Store
//
//  Created by Nayan Bhut on 01/05/24.
//

import Foundation
import Spine


class SpineManager {
    let strBaseURL = "https://api.appstoreconnect.apple.com/v1/"
    var tokenData = ""
    
    private func getToken(for team: Team) {
        do {
            let token = JWT(keyIdentifier: team.getPrivateKeyID(), issuerIdentifier: team.getIssuerId(), expireDuration: 60 * 20)
            self.tokenData = try token.signedToken(using: team.getPrivateKey())
            print(":Token ", self.tokenData)
        } catch { // Handle error
            print(":Token ", error.localizedDescription)
        }
    }
    
    func getSpine(for team: Team, strURL: String) -> Spine {
        let client = HTTPClient(session: URLSession.shared)
        
        Spine.setLogLevel(.debug, forDomain: .spine)
        Spine.setLogLevel(.debug, forDomain: .networking)
        Spine.setLogLevel(.debug, forDomain: .serializing)
        
        do {
            let token = JWT(keyIdentifier: team.getPrivateKeyID(), issuerIdentifier: team.getIssuerId(), expireDuration: 60 * 20)
            self.tokenData = try token.signedToken(using: team.getPrivateKey())
            print(":Token ", self.tokenData)
        } catch { // Handle error
            print(":Token ", error.localizedDescription)
        }
        
        client.setHeader("Authorization", to: "Bearer \(tokenData)")
        
        let spine = Spine(baseURL: URL(string: strBaseURL)!, networkClient: client)
        spine.keyFormatter = AsIsKeyFormatter()
        spine.registerResource(AppStoreApp.self)
        spine.registerResource(AppStoreVersions.self)
        spine.registerResource(PreReleaseVersions.self)
        spine.registerResource(Builds.self)
        spine.registerResource(BuildLocalizations.self)
        spine.registerResource(AppStoreVersionLocalizations.self)
        
        return spine
    }

    func callAPI<T: Resource>(strURL: String, for team: Team, query: Query<T>, completion: @escaping (Result<(resources: [Resource], meta: Metadata?, jsonapi: JSONAPIData?), Error>) -> Void) {
        let spine = getSpine(for: team, strURL: strURL)
        spine.find(query)
            .onSuccess { (resources: ResourceCollection, meta: Metadata?, jsonapi: JSONAPIData?) in
                print(resources)
                print(meta)
                print(jsonapi)
                completion(.success((resources.resources, meta, jsonapi)))
                //                ((resources.resources as! [AppStoreApp]).first?.appStoreVersions?.resources.first as! AppStoreVersions).appVersionState
            }.onFailure { error in
                print("Fetching failed: \(error)")
                completion(.failure(error))
            }
    }
    
    func updateAPI<T: Resource>(strURL: String, for team: Team, resourse: T, completion: @escaping (Result<(resources: [Resource], meta: Metadata?, jsonapi: JSONAPIData?), Error>) -> Void) {
        let spine = getSpine(for: team, strURL: strURL)
        
        spine.save(resourse)
            .onSuccess { localization in
                print("Localize is ", localization)
                completion(.success(([localization], nil, nil)))
            }.onFailure { error in
                print("Fetching failed: \(error)")
                completion(.failure(error))
            }
    }
}

extension SpineManager {
    func getAllApps<T:Resource>(for team: Team, completion: @escaping (Result<[T], Error>) -> Void) {
        var query = Query(resourceType: AppStoreApp.self, path: "apps")
        query.include("appStoreVersions")
//        query.include("displayableVersions")
//        query.restrictFieldsOfResourceType(AppStoreVersions.self, to: "versionString")
//        query.restrictFieldsOfResourceType(AppStoreVersions.self, to: "appStoreState")
//        query.restrictFieldsOfResourceType(AppStoreVersions.self, to: "appVersionState")
        query.addPredicateWithKey("appStoreVersions.platform", value: "IOS", type: .equalTo)
        query.addDescendingOrder("name")
        
        
        callAPI(strURL: strBaseURL, for: team, query: query) { result in
            switch result {
            case .success(let successData):
                completion(.success(successData.resources as? [T] ?? []))
            case .failure(let failure):
                completion(.failure(failure))
            }
        }
    }
    
    func getTestFlightVersions<T:Resource>(for app:AppStoreApp, for team: Team, completion: @escaping (Result<[T], Error>) -> Void) {
        var query = Query(resourceType: PreReleaseVersions.self, path: "preReleaseVersions")
        query.addDescendingOrder("version")
        query.addPredicateWithField("app", value: app.id ?? "", type: .equalTo)
        
        callAPI(strURL: strBaseURL, for: team, query: query) { result in
            switch result {
            case .success(let successData):
                completion(.success(successData.resources as? [T] ?? []))
            case .failure(let failure):
                completion(.failure(failure))
            }
        }
    }
    
    func getVersionBuilds<T:Resource>(for app:AppStoreApp, for version:PreReleaseVersions, for team: Team, completion: @escaping (Result<[T], Error>) -> Void) {
        var query = Query(resourceType: Builds.self, path: "builds")
        query.addDescendingOrder("version")
        query.addPredicateWithField("app", value: app.id ?? "", type: .equalTo)
        query.addPredicateWithField("preReleaseVersion", value: version.id ?? "", type: .equalTo)
        query.include("appStoreVersion")
        query.include("betaBuildLocalizations")
        query.include("preReleaseVersion")
        
        callAPI(strURL: strBaseURL, for: team, query: query) { result in
            switch result {
            case .success(let successData):
                completion(.success(successData.resources as? [T] ?? []))
            case .failure(let failure):
                completion(.failure(failure))
            }
        }
    }
    
    func updateBuildLocalization<T:Resource>(for team: Team, localize: BuildLocalizations ,completion: @escaping (Result<[T], Error>) -> Void) {
        let templocalize = UpdateBuildLocalizations(whatsNew: localize.whatsNew)
        templocalize.id = localize.id
        
        updateAPI(strURL: strBaseURL, for: team, resourse: templocalize) { result in
            switch result {
            case .success(let successData):
                completion(.success(successData.resources as? [T] ?? []))
            case .failure(let failure):
                completion(.failure(failure))
            }
        }
    }
    
    func createBuildLocalization<T:Resource>(for team: Team, localize: BuildLocalizations, build: Builds ,completion: @escaping (Result<[T], Error>) -> Void) {
        let templocalize = BuildLocalizations(whatsNew: localize.whatsNew, locale: "en-US")
        templocalize.build = build
        
        updateAPI(strURL: strBaseURL, for: team, resourse: templocalize) { result in
            switch result {
            case .success(let successData):
                completion(.success(successData.resources as? [T] ?? []))
            case .failure(let failure):
                completion(.failure(failure))
            }
        }
    }
}

extension SpineManager {
    func getAppStoreVersion<T:Resource>(for team: Team, appId: String) async -> (Result<[T], Error>) {
        var query = Query(resourceType: AppStoreVersions.self, path: "appStoreVersions/\(appId)")
        
        query.include("build")
        query.include("appStoreVersionLocalizations")
        
        print("query : ",query)
        
        let result = await withCheckedContinuation { continuation in
            callAPI(strURL: strBaseURL, for: team, query: query) { messages in
                continuation.resume(returning: messages)
            }
        }
        
        switch result {
        case .success(let successData):
            return .success(successData.resources as? [T] ?? [])
        case .failure(let failure):
            return  .failure(failure)
        }
    }
}
