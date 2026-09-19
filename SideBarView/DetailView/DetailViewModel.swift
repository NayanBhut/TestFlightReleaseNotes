//
//  DetailViewModel.swift
//  App Store
//
//  Created by Nayan Bhut on 04/05/24.
//

import SwiftUI
import Combine
import JSONAPI
import OSLog

private let detailLogger = Logger(subsystem: "com.appstore.release-notes", category: "Detail")

@MainActor
class DetailViewModel: ObservableObject {
    @Published var versionsState: ViewState<[PreReleaseVersionsModel]> = .idle
    @Published var buildsState: ViewState<[BuildsModel]> = .idle
    @Published var currentTeam: Credential?
    @Published var selectedVersion: PreReleaseVersionsModel?
    @Published var selectedApp: AppsData?

    @Published var nextPageCursor: String?
    @Published var meta: Meta?

    @Published var updatingBuildId: String?
    /// A failed release-note save, surfaced to the UI with a Retry action.
    @Published var saveError: BuildSaveError?

    private var cancellables = Set<AnyCancellable>()
    private let sidebarViewModel: SideBarViewModel

    /// In-flight builds fetch so a new fetch can cancel a stale one.
    private var buildsFetchTask: Task<Void, Never>?
    /// Suppresses duplicate pagination requests while one page is loading.
    private var isPaginatingBuilds = false

    // MARK: - Convenience accessors for views

    var arrVersions: [PreReleaseVersionsModel] {
        versionsState.loadedValue ?? []
    }

    var arrBuilds: [BuildsModel] {
        buildsState.loadedValue ?? []
    }

    var isBuildsLoading: Bool {
        buildsState.isLoading
    }

    var buildsErrorMessage: String? {
        buildsState.errorMessage
    }

    var versionsErrorMessage: String? {
        versionsState.errorMessage
    }

    init(sidebarViewModel: SideBarViewModel) {
        self.sidebarViewModel = sidebarViewModel
        sidebarViewModel.$versionsState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] versionsState in
                self?.versionsState = versionsState
            }
            .store(in: &cancellables)

        sidebarViewModel.$selectedApp
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selectedApp in
                guard let self = self else { return }
                self.selectedApp = selectedApp
                // Team / app switch clears versions + builds cleanly.
                self.selectedVersion = nil
                self.buildsState = .idle
                self.nextPageCursor = nil
                self.meta = nil
            }
            .store(in: &cancellables)
    }
}

extension DetailViewModel {
    func retryVersions() {
        sidebarViewModel.retryVersions()
    }

    func setSelectedVersionAndGetBuilds(selectedVersion: PreReleaseVersionsModel, cursor: String? = nil) {
        markVersionSelected(selectedVersion)
        guard let app = selectedApp else { return }
        getBuilds(app: app, version: selectedVersion, cursor: cursor)
    }

    func retryBuilds() {
        guard let app = selectedApp, let version = selectedVersion else { return }
        getBuilds(app: app, version: version)
    }

    private func markVersionSelected(_ version: PreReleaseVersionsModel) {
        guard case .loaded(let versions) = versionsState else { return }
        let updated = versions.map { item -> PreReleaseVersionsModel in
            var temp = item
            temp.isSelected = temp.id == version.id
            return temp
        }
        versionsState = .loaded(updated)
    }

    func getBuilds(app: AppsData, version: PreReleaseVersionsModel, cursor: String? = nil) {
        let isPaginating = cursor != nil
        // Ignore duplicate "Load more" taps while a page request is in flight
        // (double-tapping would otherwise append the same rows twice).
        if isPaginating, isPaginatingBuilds { return }
        // Cancel any in-flight fetch so a stale response (older version's
        // builds) can never overwrite the state for the newer selection.
        buildsFetchTask?.cancel()
        buildsFetchTask = Task { await fetchBuilds(app: app, version: version, cursor: cursor) }
    }

    func fetchBuilds(app: AppsData, version: PreReleaseVersionsModel, cursor: String? = nil) async {
        let isPaginating = cursor != nil
        if isPaginating {
            isPaginatingBuilds = true
        } else {
            buildsState = .loading
        }
        defer {
            if isPaginating { isPaginatingBuilds = false }
        }

        var queryParams = ["filter[app]": app.id,
                           "filter[preReleaseVersion]": version.id,
                           "sort": "-version",
                           "include": "appStoreVersion,betaBuildLocalizations,preReleaseVersion",
                           "limit": "5"]

        if let cursor = cursor {
            queryParams["cursor"] = cursor
        }

        guard let request = APIClient.shared.getRequest(api: .get(name: .getVersionBuilds, queryParams: queryParams), apiVersion: .v1) else {
            if !isPaginating {
                buildsState = .error("No team selected. Add a team to load builds.")
            }
            return
        }

        do {
            let data = try await APIClient.shared.callAPI(with: request)
            let model = try getDecoder().decode(BuildsDocument.self, from: data)
            // Ignore stale responses superseded by a newer fetch.
            guard !Task.isCancelled else { return }
            selectedVersion = version

            let merged: [BuildsModel]
            if isPaginating, let existing = buildsState.loadedValue {
                merged = existing + model.data
            } else {
                merged = model.data
            }

            meta = model.meta
            nextPageCursor = model.meta.paging.nextCursor
            if merged.isEmpty {
                buildsState = .empty
            } else {
                buildsState = .loaded(merged)
            }
        } catch {
            // A cancelled fetch means a newer one took over - don't surface
            // its failure or overwrite the newer state.
            guard !Task.isCancelled else { return }
            detailLogger.error("Failed to load builds: \(error.localizedDescription)")
            if !isPaginating {
                selectedVersion = version
                meta = nil
                if let apiError = error as? APIError {
                    buildsState = .error(apiError.details)
                } else {
                    buildsState = .error(error.localizedDescription)
                }
            }
        }
    }

    func updateBuildWhatsNew(buildId: String, whatsNew: String) {
        guard case .loaded(var builds) = buildsState,
              let buildIndex = builds.firstIndex(where: { $0.id == buildId }) else { return }

        if builds[buildIndex].betaBuildLocalizations.isEmpty {
            let betaBuildLocalization = BuildLocalizationsModel(
                id: buildId,
                locale: Constants.defaultLocale,
                whatsNew: whatsNew
            )
            builds[buildIndex].betaBuildLocalizations.append(betaBuildLocalization)
        } else {
            builds[buildIndex].betaBuildLocalizations[0].whatsNew = whatsNew
        }
        buildsState = .loaded(builds)
    }

    func saveBuildLocalization(buildId: String) {
        guard case .loaded(let builds) = buildsState,
              let build = builds.first(where: { $0.id == buildId }),
              let betaBuildLocalization = build.betaBuildLocalizations.first,
              betaBuildLocalization.whatsNew != nil else { return }

        createOrUpdate(buildId: buildId, buildLocalization: betaBuildLocalization, localization: betaBuildLocalization.whatsNew ?? "")
    }

    func isBuildUpdating(_ buildId: String) -> Bool {
        return updatingBuildId == buildId
    }
}

// Constants
private enum Constants {
    static let defaultLocale = "en-US"
}

extension DetailViewModel {
    func createOrUpdate(buildId: String, buildLocalization: BuildLocalizationsModel, localization: String) {
        guard updatingBuildId != buildId else { return }
        updatingBuildId = buildId

        Task {
            guard case .loaded(let builds) = buildsState,
                  let buildIndex = builds.firstIndex(where: { $0.id == buildId }) else {
                updatingBuildId = nil
                return
            }
            let arrLocalizations = builds[buildIndex].betaBuildLocalizations
            if arrLocalizations.isEmpty {
                await createBuildLocalization(buildId: buildId, buildLocalization: buildLocalization, localization: localization)
            } else {
                await updateBuildLocalization(buildId: buildId, buildLocalization: buildLocalization, localization: localization)
            }
        }
    }

    private func updateBuildLocalization(buildId: String, buildLocalization: BuildLocalizationsModel, localization: String) async {
        defer { updatingBuildId = nil }

        let model = BuildLocalizationsModel.updateBody(id: buildLocalization.id, whatsNew: buildLocalization.whatsNew)
        let encoder = JSONAPIEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(model),
              let request = APIClient.shared.getRequest(api: .patch(name: .postReleaseNote, body: data, path: buildLocalization.id), apiVersion: .v1) else {
            saveError = BuildSaveError(buildId: buildId, message: "Couldn't build the update request.")
            return
        }

        do {
            let responseData = try await APIClient.shared.callAPI(with: request)
            let model = try getDecoder().decode(BuildLocalizationsModel.self, from: responseData)

            // Re-locate the build after the await: the list may have changed
            // (refresh, pagination) since the save started, so the captured
            // index would be unreliable.
            guard case .loaded(var builds) = buildsState,
                  let buildIndex = builds.firstIndex(where: { $0.id == buildId }) else { return }
            let arrLocalizations = builds[buildIndex].betaBuildLocalizations

            if let index = arrLocalizations.firstIndex(where: { $0.id == model.id }) {
                let buildLocalizationsModel = BuildLocalizationsModel(
                    id: model.id,
                    locale: model.locale,
                    whatsNew: model.whatsNew
                )
                builds[buildIndex].betaBuildLocalizations[index] = buildLocalizationsModel
                buildsState = .loaded(builds)
            }
        } catch {
            detailLogger.error("Failed to update localization: \(error.localizedDescription)")
            saveError = BuildSaveError(buildId: buildId, message: friendlySaveMessage(for: error))
        }
    }

    private func createBuildLocalization(buildId: String, buildLocalization: BuildLocalizationsModel, localization: String) async {
        defer { updatingBuildId = nil }

        guard case .loaded(let builds) = buildsState,
              let currentBuildId = builds.first(where: { $0.id == buildId })?.id else {
            return
        }

        let model = BuildLocalizationsModel.createBody(
            locale: Constants.defaultLocale,
            whatsNew: buildLocalization.whatsNew,
            build: RelationshipOne(id: currentBuildId)
        )
        let encoder = JSONAPIEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(model),
              let request = APIClient.shared.getRequest(api: .post(name: .postReleaseNote, body: data), apiVersion: .v1) else {
            saveError = BuildSaveError(buildId: buildId, message: "Couldn't build the save request.")
            return
        }

        do {
            let responseData = try await APIClient.shared.callAPI(with: request)
            let model = try getDecoder().decode(BuildLocalizationsModel.self, from: responseData)

            // Re-locate the build after the await: the list may have changed
            // (refresh, pagination) since the save started.
            guard case .loaded(var currentBuilds) = buildsState,
                  let buildIndex = currentBuilds.firstIndex(where: { $0.id == buildId }) else { return }

            let buildLocalizationsModel = BuildLocalizationsModel(
                id: model.id,
                locale: model.locale,
                whatsNew: model.whatsNew
            )

            // Replace the temporary localization with the real one from API
            if currentBuilds[buildIndex].betaBuildLocalizations.isEmpty {
                currentBuilds[buildIndex].betaBuildLocalizations.append(buildLocalizationsModel)
            } else {
                currentBuilds[buildIndex].betaBuildLocalizations[0] = buildLocalizationsModel
            }
            buildsState = .loaded(currentBuilds)
        } catch {
            detailLogger.error("Failed to create localization: \(error.localizedDescription)")
            saveError = BuildSaveError(buildId: buildId, message: friendlySaveMessage(for: error))
        }
    }

    private func friendlySaveMessage(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.details
        }
        return error.localizedDescription
    }
}

/// A failed release-note save, surfaced to the UI with a Retry action.
struct BuildSaveError: Identifiable, Equatable {
    let buildId: String
    let message: String

    var id: String { buildId }
}
