//
//  SideBarViewModel.swift
//  App Store
//
//  Created by Nayan Bhut on 02/05/24.
//

import SwiftUI
import JSONAPI
import OSLog

private let sidebarLogger = Logger(subsystem: "com.appstore.release-notes", category: "Sidebar")

@MainActor
class SideBarViewModel: ObservableObject {
    @Published var isExpanded = false
    @Published var appsState: ViewState<[AppsData]> = .idle
    @Published var versionsState: ViewState<[PreReleaseVersionsModel]> = .idle
    @Published var appMeta: Meta?
    @Published var selectedApp: AppsData?

    @Published var isTeamChanged = false

    // MARK: - Convenience accessors for views

    var arrApps: [AppsData] {
        appsState.loadedValue ?? []
    }

    var arrVersion: [PreReleaseVersionsModel] {
        versionsState.loadedValue ?? []
    }

    var isAppsLoading: Bool {
        appsState.isLoading
    }

    var appsErrorMessage: String? {
        appsState.errorMessage
    }

    var versionsErrorMessage: String? {
        versionsState.errorMessage
    }

    // MARK: - Apps

    func getiOSApps(nextPage: String? = nil) {
        Task { await fetchApps(nextPage: nextPage) }
    }

    func fetchApps(nextPage: String? = nil) async {
        let isPaginating = nextPage != nil
        if !isPaginating {
            appsState = .loading
            // Team switch / refresh clears selection cleanly.
            selectedApp = nil
            versionsState = .idle
        }

        var queryParams = [
            "include": "appStoreVersions",
            "filter[appStoreVersions.platform]": "IOS",
            "sort": "-name",
            "fields[builds]": "icons",
            "limit": "10"
        ]

        if let nextPage = nextPage {
            queryParams["cursor"] = nextPage
        }

        guard let request = APIClient.shared.getRequest(api: .get(name: .getAllApps, queryParams: queryParams), apiVersion: .v1) else {
            if !isPaginating {
                appsState = .error("No team selected. Add a team to load apps.")
            }
            return
        }

        do {
            let data = try await APIClient.shared.callAPI(with: request)
            let model = try getDecoder().decode(AppsDocument.self, from: data)
            updateCurrentLiveVersion(responseApp: model, nextPage: nextPage)
        } catch {
            sidebarLogger.error("Failed to load apps: \(error.localizedDescription)")
            if !isPaginating {
                appsState = .error(friendlyMessage(for: error))
            }
        }
    }

    private func updateCurrentLiveVersion(responseApp: AppsDocument, nextPage: String? = nil) {
        let processedApps = responseApp.data.map { appData -> AppsData in
            var tempApp = appData
            let currentVersion = appData.appStoreVersions.first

            tempApp.currentLiveVersion = (
                currentVersion?.id ?? "",
                currentVersion?.versionString ?? "Not Last Version"
            )
            tempApp.currentState = currentVersion?.appVersionState ?? ""

            return tempApp
        }.sorted { $0.currentState < $1.currentState }

        let merged: [AppsData]
        if nextPage != nil, let existing = appsState.loadedValue {
            merged = existing + processedApps
        } else {
            merged = processedApps
        }

        appMeta = responseApp.meta
        if merged.isEmpty {
            appsState = .empty
        } else {
            appsState = .loaded(merged)
        }
    }

    func updateTeam() {
        getiOSApps()
    }

    func retryApps() {
        getiOSApps()
    }

    // MARK: - Versions

    func setSelectedAppAndGetVersions(app: AppsData) {
        selectedApp = app
        markAppSelected(app)
        getTestFlightVersions(app: app)
    }

    func retryVersions() {
        guard let app = selectedApp else { return }
        getTestFlightVersions(app: app)
    }

    private func markAppSelected(_ app: AppsData) {
        guard case .loaded(let apps) = appsState,
              let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
        var updated = apps.map { item -> AppsData in
            var temp = item
            temp.isSelected = false
            return temp
        }
        updated[index].isSelected = true
        // Preserve selection without dropping to loading.
        appsState = .loaded(updated)
    }

    private func getTestFlightVersions(app: AppsData) {
        Task { await fetchVersions(app: app) }
    }

    func fetchVersions(app: AppsData) async {
        versionsState = .loading

        let queryParams = [
            "filter[app]": app.id,
            "sort": "-version"
        ]

        guard let request = APIClient.shared.getRequest(api: .get(name: .getAppVersions, queryParams: queryParams), apiVersion: .v1) else {
            versionsState = .error("No team selected. Add a team to load versions.")
            return
        }

        do {
            let data = try await APIClient.shared.callAPI(with: request)
            let model = try getDecoder().decode([PreReleaseVersionsModel].self, from: data)
            let limited = model.count > 10 ? Array(model.prefix(10)) : model
            if limited.isEmpty {
                versionsState = .empty
            } else {
                versionsState = .loaded(limited)
            }
        } catch {
            sidebarLogger.error("Failed to load versions: \(error.localizedDescription)")
            versionsState = .error(friendlyMessage(for: error))
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.details
        }
        return error.localizedDescription
    }
}
