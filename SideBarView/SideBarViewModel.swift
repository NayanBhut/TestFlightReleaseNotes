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

    /// Local search gives instant feedback; a debounced server-side
    /// `filter[name]` fetch follows so results cover all apps, not just
    /// the pages loaded so far.
    @Published var searchText: String = "" {
        didSet {
            applyFilters()
            scheduleServerSearch()
        }
    }
    /// State filtering is server-side only (`filter[appStoreVersions.appStoreState]`);
    /// changing it triggers a fresh fetch so the list never mixes query epochs.
    @Published var selectedStateFilter: AppConfigs.AppStateFilter = .all {
        didSet {
            guard selectedStateFilter != oldValue else { return }
            getiOSApps()
        }
    }
    @Published var selectedSortOption: AppConfigs.SortOption = .nameDescending {
        didSet { applyFilters() }
    }
    /// The list the sidebar renders: searched / sorted locally.
    @Published var filteredApps: [AppsData] = []
    /// Everything loaded so far (across pagination); filtering applies to this.
    private var allLoadedApps: [AppsData] = []

    /// In-flight fetches so a new fetch can cancel a stale one.
    private var appsFetchTask: Task<Void, Never>?
    private var versionsFetchTask: Task<Void, Never>?
    /// Debounces the server-side search triggered by typing.
    private var searchDebounceTask: Task<Void, Never>?
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
            // Team switch / refresh / filter change clears selection cleanly.
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

        if !searchText.isEmpty {
            queryParams["filter[name]"] = searchText
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

    /// Debounces the server-side name search so typing doesn't fire a
    /// request per keystroke. An emptied search re-fetches the full list.
    private func scheduleServerSearch() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.getiOSApps()
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
        // search/sort always sees every loaded app. Deduplicate by id so a
        // double-fired cursor can never append the same rows twice.
        if nextPage != nil {
            let existingIDs = Set(allLoadedApps.map(\.id))
            let newApps = processedApps.filter { !existingIDs.contains($0.id) }
            allLoadedApps.append(contentsOf: newApps)
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

    /// Phase 5: local search + sort over everything loaded so far.
    /// Server-side sort/filter also run in the query; state filtering is
    /// intentionally server-side only (see selectedStateFilter).
    func applyFilters() {
        var filtered = allLoadedApps

        if !searchText.isEmpty {
            filtered = filtered.filter { app in
                (app.name ?? "").localizedCaseInsensitiveContains(searchText) ||
                (app.bundleId ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }

        switch selectedSortOption {
        case .nameAscending:
            filtered.sort { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
        case .nameDescending:
            filtered.sort { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedDescending }
        case .stateAscending:
            filtered.sort { $0.currentState.localizedCaseInsensitiveCompare($1.currentState) == .orderedAscending }
        case .stateDescending:
            filtered.sort { $0.currentState.localizedCaseInsensitiveCompare($1.currentState) == .orderedDescending }
        }

        filteredApps = filtered
    }

    /// Clears the local search term (the debounced server fetch restores the full list).
    func clearSearch() {
        searchText = ""
    }

    func updateTeam() {
        // Phase 5: reset search/filter state on team switch.
        allLoadedApps = []
        filteredApps = []
        searchText = ""
        selectedStateFilter = .all
        searchDebounceTask?.cancel()
        getiOSApps()
    }

    func retryApps() {
        getiOSApps()
    }

    /// Loads the next page. Guarded against duplicate concurrent requests
    /// via the isPaginatingApps flag inside getiOSApps(nextPage:).
    func loadMoreApps(cursor: String) {
        getiOSApps(nextPage: cursor)
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
        guard allLoadedApps.contains(where: { $0.id == app.id }) else { return }
        // Mutate the backing list (the snapshot appsState mirrors it) so the
        // rendered filteredApps snapshot stays in sync after applyFilters().
        for index in allLoadedApps.indices {
            allLoadedApps[index].isSelected = (allLoadedApps[index].id == app.id)
        }
        appsState = .loaded(allLoadedApps)
        applyFilters()
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
