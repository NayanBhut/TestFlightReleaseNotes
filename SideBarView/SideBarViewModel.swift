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

    // MARK: - Search / sort / filter (Phase 5)

    @Published var searchText: String = "" {
        didSet { applyFilters() }
    }
    @Published var selectedStateFilter: AppConfigs.AppStateFilter = .all {
        didSet { applyFilters() }
    }
    @Published var selectedSortOption: AppConfigs.SortOption = .nameDescending {
        didSet { applyFilters() }
    }
    /// The list the sidebar renders: searched / filtered / sorted locally.
    @Published var filteredApps: [AppsData] = []
    /// Everything loaded so far (across pagination); filtering applies to this.
    private var allLoadedApps: [AppsData] = []

    /// In-flight fetches so a new fetch can cancel a stale one.
    private var appsFetchTask: Task<Void, Never>?
    private var versionsFetchTask: Task<Void, Never>?
    /// Suppresses duplicate pagination requests while one page is loading.
    private var isPaginatingApps = false

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
        let isPaginating = nextPage != nil
        // Ignore duplicate "Load more" taps while a page request is in flight
        // (double-tapping would otherwise append the same rows twice).
        if isPaginating, isPaginatingApps { return }
        // Cancel any in-flight fetch so a stale response can never overwrite
        // the state for a newer fetch.
        appsFetchTask?.cancel()
        appsFetchTask = Task { await fetchApps(nextPage: nextPage) }
    }

    func fetchApps(nextPage: String? = nil) async {
        let isPaginating = nextPage != nil
        if isPaginating {
            isPaginatingApps = true
        } else {
            appsState = .loading
            // Team switch / refresh clears selection cleanly.
            selectedApp = nil
            versionsState = .idle
        }
        defer {
            if isPaginating { isPaginatingApps = false }
        }

        // Phase 5: app icons, configurable limit, server-side sort,
        // name search and app-store-state filter.
        var queryParams: [String: String] = [
            "include": "appStoreVersions,appStoreIcon",
            "filter[appStoreVersions.platform]": "IOS",
            "fields[builds]": "icons",
            "limit": String(AppConfigs.appListLimit)
        ]

        queryParams["sort"] = selectedSortOption.queryValue

        if !AppConfigs.filterName.isEmpty {
            queryParams["filter[name]"] = AppConfigs.filterName
        }

        if let stateFilter = selectedStateFilter.apiValue {
            queryParams["filter[appStoreVersions.appStoreState]"] = stateFilter
        }

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
            // Ignore stale responses superseded by a newer fetch.
            guard !Task.isCancelled else { return }
            updateCurrentLiveVersion(responseApp: model, nextPage: nextPage)
        } catch {
            // A cancelled fetch means a newer one took over - don't surface
            // its failure or overwrite the newer state.
            guard !Task.isCancelled else { return }
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
            // Phase 5: app icon template URL (resolved to a concrete size in the view).
            tempApp.iconURL = appData.appStoreIcon?.iconAsset?.templateUrl

            return tempApp
        }

        // Phase 5: keep a full backing list across pagination so local
        // search/filter/sort always sees every loaded app.
        if nextPage != nil {
            allLoadedApps += processedApps
        } else {
            allLoadedApps = processedApps
        }

        appMeta = responseApp.meta
        if allLoadedApps.isEmpty {
            appsState = .empty
        } else {
            appsState = .loaded(allLoadedApps)
        }
        applyFilters()
    }

    /// Phase 5: local search + state filter + sort fallback over everything
    /// loaded so far. Server-side sort/filter run in the query as well.
    func applyFilters() {
        var filtered = allLoadedApps

        if !searchText.isEmpty {
            filtered = filtered.filter { app in
                (app.name ?? "").localizedCaseInsensitiveContains(searchText) ||
                (app.bundleId ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }

        if selectedStateFilter != .all {
            filtered = filtered.filter { app in
                app.currentState == selectedStateFilter.rawValue ||
                app.currentState.replacingOccurrences(of: "_", with: " ").uppercased() == selectedStateFilter.rawValue
            }
        }

        filtered = filtered.sorted { app1, app2 in
            switch selectedSortOption {
            case .nameAscending:
                return (app1.name ?? "") < (app2.name ?? "")
            case .nameDescending:
                return (app1.name ?? "") > (app2.name ?? "")
            case .stateAscending:
                return app1.currentState < app2.currentState
            case .stateDescending:
                return app1.currentState > app2.currentState
            }
        }

        filteredApps = filtered
    }

    func updateTeam() {
        // Phase 5: reset search/filter state on team switch.
        allLoadedApps = []
        filteredApps = []
        searchText = ""
        AppConfigs.filterName = ""
        selectedStateFilter = .all
        getiOSApps()
    }

    func retryApps() {
        getiOSApps()
    }

    func loadMoreApps(cursor: String) async {
        await fetchApps(nextPage: cursor)
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
        // Cancel any in-flight versions fetch so quickly switching apps
        // can't let a stale response overwrite the newer app's versions.
        versionsFetchTask?.cancel()
        versionsFetchTask = Task { await fetchVersions(app: app) }
    }

    func fetchVersions(app: AppsData) async {
        versionsState = .loading

        let queryParams = [
            "filter[app]": app.id,
            "sort": "-version",
            "limit": String(AppConfigs.versionLimit)
        ]

        guard let request = APIClient.shared.getRequest(api: .get(name: .getAppVersions, queryParams: queryParams), apiVersion: .v1) else {
            versionsState = .error("No team selected. Add a team to load versions.")
            return
        }

        do {
            let data = try await APIClient.shared.callAPI(with: request)
            let model = try getDecoder().decode([PreReleaseVersionsModel].self, from: data)
            // Ignore stale responses superseded by a newer fetch.
            guard !Task.isCancelled else { return }
            let limited = model.count > AppConfigs.versionLimit ? Array(model.prefix(AppConfigs.versionLimit)) : model
            if limited.isEmpty {
                versionsState = .empty
            } else {
                versionsState = .loaded(limited)
            }
        } catch {
            // A cancelled fetch means a newer one took over - don't surface
            // its failure or overwrite the newer state.
            guard !Task.isCancelled else { return }
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