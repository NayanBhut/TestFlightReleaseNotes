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
    @Published var versionsMeta: Meta?
    @Published var versionsNextCursor: String?
    @Published var versionsPaginationFailed = false
    @Published var selectedApp: AppsData?

    @Published var isTeamChanged = false

    // MARK: - Search / sort / filter (Phase 5)

    /// Local search gives instant feedback; a debounced server-side
    /// `filter[name]` fetch follows so results cover all apps, not just
    /// the pages loaded so far. The refresh is silent: it keeps the
    /// current list and selection visible while in flight.
    @Published var searchText: String = "" {
        didSet {
            guard !suppressFilterObservers, searchText != oldValue else { return }
            scheduleServerSearch()
        }
    }
    /// State filtering is server-side only (`filter[appStoreVersions.appStoreState]`);
    /// changing it triggers a fresh fetch so the list never mixes query epochs.
    @Published var selectedStateFilter: AppConfigs.AppStateFilter = .all {
        didSet {
            guard !suppressFilterObservers, selectedStateFilter != oldValue else { return }
            getiOSApps()
        }
    }
    @Published var selectedSortOption: AppConfigs.SortOption = .nameDescending

    /// Everything loaded so far (across pagination and search refreshes).
    private var allLoadedApps: [AppsData] = []

    /// True while a pagination request failed, so the sidebar can offer a retry.
    @Published var paginationFailed = false

    /// Apps the sidebar renders: everything loaded, searched and sorted locally.
    /// Derived (not stored) so it can never drift out of sync with
    /// allLoadedApps / searchText / selectedSortOption.
    var filteredApps: [AppsData] {
        var filtered = allLoadedApps

        // matchesSearch returns true for everything when the trimmed
        // search term is empty.
        filtered = filtered.filter(matchesSearch)

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

        return filtered
    }

    /// In-flight fetches so a new fetch can cancel a stale one.
    private var appsFetchTask: Task<Void, Never>?
    private var versionsFetchTask: Task<Void, Never>?
    /// Debounces the server-side search triggered by typing.
    private var searchDebounceTask: Task<Void, Never>?
    /// Suppresses didSet-triggered fetches while batch-resetting filter state
    /// (e.g. on team switch) so exactly one explicit fetch runs.
    private var suppressFilterObservers = false
    /// Suppresses duplicate pagination requests while one page is loading.
    private var isPaginatingApps = false
    /// Suppresses duplicate versions pagination requests while one page is loading.
    private var isPaginatingVersions = false

    // MARK: - Convenience accessors for views

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

    func getiOSApps(nextPage: String? = nil, isSearchRefresh: Bool = false) {
        let isPaginating = nextPage != nil
        // Ignore duplicate "Load more" taps while a page request is in flight
        // (double-tapping would otherwise append the same rows twice).
        if isPaginating, isPaginatingApps { return }
        // Cancel any in-flight fetch so a stale response can never overwrite
        // the state for a newer fetch.
        appsFetchTask?.cancel()
        appsFetchTask = Task { await fetchApps(nextPage: nextPage, isSearchRefresh: isSearchRefresh) }
    }

    func fetchApps(nextPage: String? = nil, isSearchRefresh: Bool = false) async {
        let isPaginating = nextPage != nil
        if isPaginating {
            isPaginatingApps = true
        } else if isSearchRefresh {
            // Silent refresh (search): keep the current list and selection
            // visible while the server query is in flight.
        } else {
            appsState = .loading
            // Team switch / refresh / filter change clears selection cleanly.
            selectedApp = nil
            versionsState = .idle
        }
        paginationFailed = false
        defer {
            if isPaginating { isPaginatingApps = false }
        }

        // Phase 5: app icons, configurable limit, server-side name search
        // and app-store-state filter. Sorting is intentionally local-only:
        // a server sort + a cursor issued under a different sort would
        // silently skip rows during pagination.
        var queryParams: [String: String] = [
            "include": "appStoreVersions,appStoreIcon",
            "filter[appStoreVersions.platform]": "IOS",
            "fields[builds]": "icons",
            "limit": String(AppConfigs.appListLimit)
        ]

        if !trimmedSearchText.isEmpty {
            queryParams["filter[name]"] = trimmedSearchText
        }

        if let stateFilter = selectedStateFilter.apiValue {
            queryParams["filter[appStoreVersions.appStoreState]"] = stateFilter
        }

        if let nextPage = nextPage {
            queryParams["cursor"] = nextPage
        }

        guard let request = APIClient.shared.getRequest(api: .get(name: .getAllApps, queryParams: queryParams), apiVersion: .v1) else {
            if !isPaginating, !isSearchRefresh {
                appsState = .error("No team selected. Add a team to load apps.")
            }
            return
        }

        do {
            let data = try await APIClient.shared.callAPI(with: request)
            let model = try getDecoder().decode(AppsDocument.self, from: data)
            // Ignore stale responses superseded by a newer fetch.
            guard !Task.isCancelled else { return }
            updateCurrentLiveVersion(responseApp: model, nextPage: nextPage, isSearchRefresh: isSearchRefresh)
        } catch {
            // A cancelled fetch means a newer one took over - don't surface
            // its failure or overwrite the newer state.
            guard !Task.isCancelled else { return }
            sidebarLogger.error("Failed to load apps: \(error.localizedDescription)")
            if isPaginating {
                // Surface pagination failure so the sidebar can offer a retry;
                // the loaded list stays intact.
                paginationFailed = true
            }
            // Silent refreshes keep the current list on failure.
            if !isPaginating, !isSearchRefresh {
                appsState = .error(friendlyMessage(for: error))
            }
        }
    }

    /// The search term with surrounding whitespace removed, used for both
    /// the server query and local matching so whitespace-only input can't
    /// fire a query that matches nothing.
    var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Debounces the server-side name search so typing doesn't fire a
    /// request per keystroke. An emptied search re-fetches the full list.
    private func scheduleServerSearch() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.getiOSApps(isSearchRefresh: true)
        }
    }

    /// True when an app matches the current search term (name or bundle ID).
    private func matchesSearch(_ app: AppsData) -> Bool {
        let term = trimmedSearchText
        guard !term.isEmpty else { return true }
        return (app.name ?? "").localizedCaseInsensitiveContains(term) ||
            (app.bundleId ?? "").localizedCaseInsensitiveContains(term)
    }

    private func updateCurrentLiveVersion(responseApp: AppsDocument, nextPage: String? = nil, isSearchRefresh: Bool = false) {
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
        // search/sort always sees every loaded app.
        if isSearchRefresh {
            // Union of the server's name matches and the already-loaded apps
            // that match locally (by name OR bundle ID) so bundle-ID matches
            // don't vanish once the server response arrives.
            let localMatches = allLoadedApps.filter(matchesSearch)
            let localIDs = Set(localMatches.map(\.id))
            allLoadedApps = localMatches + processedApps.filter { !localIDs.contains($0.id) }
        } else if nextPage != nil {
            // Deduplicate by id so a double-fired cursor can never append
            // the same rows twice.
            let existingIDs = Set(allLoadedApps.map(\.id))
            allLoadedApps.append(contentsOf: processedApps.filter { !existingIDs.contains($0.id) })
        } else {
            allLoadedApps = processedApps
        }

        // Keep the current selection highlighted if the app is still present
        // in the refreshed list.
        if let selected = selectedApp {
            for index in allLoadedApps.indices {
                allLoadedApps[index].isSelected = (allLoadedApps[index].id == selected.id)
            }
        }

        appMeta = responseApp.meta
        if allLoadedApps.isEmpty {
            appsState = .empty
        } else {
            appsState = .loaded(allLoadedApps)
        }
    }

    /// Clears the local search term (the debounced server fetch restores the full list).
    func clearSearch() {
        searchText = ""
    }

    func updateTeam() {
        // Reset search/filter state without firing per-field observers; the
        // single explicit fetch below is the only request for the new team.
        suppressFilterObservers = true
        allLoadedApps = []
        searchText = ""
        selectedStateFilter = .all
        suppressFilterObservers = false
        searchDebounceTask?.cancel()
        getiOSApps()
    }

    /// Full reset for logout (last team deleted): cancels in-flight work
    /// and drops every cached list/selection so no stale apps, versions,
    /// or builds linger behind the login sheet. DetailViewModel observes
    /// selectedApp/versionsState and clears its own state in turn.
    func clearOnLogout() {
        appsFetchTask?.cancel()
        versionsFetchTask?.cancel()
        searchDebounceTask?.cancel()
        suppressFilterObservers = true
        allLoadedApps = []
        searchText = ""
        selectedStateFilter = .all
        suppressFilterObservers = false
        appMeta = nil
        selectedApp = nil
        appsState = .empty
        versionsState = .idle
        versionsMeta = nil
        versionsNextCursor = nil
        versionsPaginationFailed = false
        paginationFailed = false
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
        // Mutate the backing list and mirror it into appsState; filteredApps
        // is derived, so the rendered list stays in sync automatically.
        for index in allLoadedApps.indices {
            allLoadedApps[index].isSelected = (allLoadedApps[index].id == app.id)
        }
        appsState = .loaded(allLoadedApps)
    }

    private func getTestFlightVersions(app: AppsData, cursor: String? = nil) {
        let isPaginating = cursor != nil
        // Ignore duplicate "Load more" taps while a page request is in flight
        // (double-tapping would otherwise append the same rows twice).
        if isPaginating, isPaginatingVersions { return }
        // Cancel any in-flight versions fetch so quickly switching apps
        // can't let a stale response overwrite the newer app's versions.
        versionsFetchTask?.cancel()
        versionsFetchTask = Task { await fetchVersions(app: app, cursor: cursor) }
    }

    /// Loads the next versions page. Guarded against duplicate concurrent
    /// requests via the isPaginatingVersions flag inside getTestFlightVersions.
    func loadMoreVersions(cursor: String) {
        guard let app = selectedApp else { return }
        getTestFlightVersions(app: app, cursor: cursor)
    }

    func fetchVersions(app: AppsData, cursor: String? = nil) async {
        let isPaginating = cursor != nil
        if isPaginating {
            isPaginatingVersions = true
        } else {
            versionsState = .loading
            versionsNextCursor = nil
            versionsMeta = nil
        }
        versionsPaginationFailed = false
        defer {
            if isPaginating { isPaginatingVersions = false }
        }

        var queryParams = [
            "filter[app]": app.id,
            "sort": "-version",
            "limit": String(AppConfigs.versionLimit)
        ]
        if let cursor = cursor {
            queryParams["cursor"] = cursor
        }

        guard let request = APIClient.shared.getRequest(api: .get(name: .getAppVersions, queryParams: queryParams), apiVersion: .v1) else {
            if !isPaginating {
                versionsState = .error("No team selected. Add a team to load versions.")
            }
            return
        }

        do {
            let data = try await APIClient.shared.callAPI(with: request)
            let model = try getDecoder().decode(PreReleaseVersionsDocument.self, from: data)
            // Ignore stale responses superseded by a newer fetch.
            guard !Task.isCancelled else { return }
            let merged: [PreReleaseVersionsModel]
            if isPaginating, let existing = versionsState.loadedValue {
                // Deduplicate by id so a double-fired cursor can never append
                // the same rows twice.
                let existingIDs = Set(existing.map(\.id))
                merged = existing + model.data.filter { !existingIDs.contains($0.id) }
            } else {
                merged = model.data
            }
            versionsMeta = model.meta
            versionsNextCursor = model.meta.paging.nextCursor
            if merged.isEmpty {
                versionsState = .empty
            } else {
                versionsState = .loaded(merged)
            }
        } catch {
            // A cancelled fetch means a newer one took over - don't surface
            // its failure or overwrite the newer state.
            guard !Task.isCancelled else { return }
            sidebarLogger.error("Failed to load versions: \(error.localizedDescription)")
            if isPaginating {
                // Surface pagination failure so the UI can offer a retry;
                // the loaded list stays intact.
                versionsPaginationFailed = true
            } else {
                versionsState = .error(friendlyMessage(for: error))
            }
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.details
        }
        return error.localizedDescription
    }
}
