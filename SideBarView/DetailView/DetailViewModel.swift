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

enum CurrentAppState {
    case appListLoading, appVersionLoading, appVersionBuildLoading, appLocalizationLoading
    case betaGroupsLoading, betaTestersLoading, betaAssignmentUpdating, betaDetailUpdating
    case _none
}

private let detailLogger = Logger(subsystem: "com.appstore.release-notes", category: "Detail")

@MainActor
class DetailViewModel: ObservableObject {
    deinit {
        // A stuck network call must not keep the VM alive.
        appInfoFetchTask?.cancel()
        buildsFetchTask?.cancel()
    }
    @Published var versionsState: ViewState<[PreReleaseVersionsModel]> = .idle
    @Published var buildsState: ViewState<[BuildsModel]> = .idle
    @Published var currentTeam: Credential?
    @Published var selectedVersion: PreReleaseVersionsModel?
    @Published var selectedApp: AppsData?

    // MARK: Batch C1 — App Info (read-only)
    @Published var appInfoState: ViewState<[AppInfoModel]> = .idle
    @Published var versionLocalizationsState: ViewState<[AppStoreVersionLocalizationsModel]> = .idle
    @Published var exportComplianceState: ViewState<[AppEncryptionDeclarationModel]> = .idle

    @Published var nextPageCursor: String?
    @Published var meta: Meta?
    @Published var versionsNextCursor: String?
    @Published var versionsMeta: Meta?
    @Published var versionsPaginationFailed = false
    @Published var isLoadingMoreVersions = false

    /// In-flight save keys ("buildId|locale") — per-locale so saving locale B
    /// isn't blocked by an in-flight save of locale A.
    @Published private(set) var updatingSaveKeys: Set<String> = []
    /// A failed release-note save, surfaced to the UI with a Retry action.
    @Published var saveError: BuildSaveError?
    @Published var expireTogglingBuildId: String?
    /// Toast event with identity: consecutive identical messages still
    /// re-fire onChange (which only triggers on *value change*). The view
    /// owns dismissal — the view model just publishes events.
    @Published var toast: ToastEvent?

    private var cancellables = Set<AnyCancellable>()
    private let sidebarViewModel: SideBarViewModel
    /// Injectable so clipboard writes can be tested or redirected.
    private let pasteboard: PasteboardWriting

    /// In-flight builds fetch so a new fetch can cancel a stale one.
    private var buildsFetchTask: Task<Void, Never>?
    /// Suppresses duplicate pagination requests while one page is loading.
    private var isPaginatingBuilds = false

    // MARK: - Batch C1 — App Info bookkeeping (stored here: extensions
    // must not contain stored properties)

    /// In-flight App Info fetch so an app switch cancels a stale one.
    private var appInfoFetchTask: Task<Void, Never>?
    /// Staleness guards so switching tabs (which destroys tab @State) never
    /// refetches data already loaded for the current app — same idea as
    /// BetaViewModel.currentAppId.
    private(set) var appInfoLoadedAppId: String?
    private(set) var versionLocalizationsLoadedVersionId: String?
    private(set) var exportComplianceLoadedAppId: String?

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

    init(sidebarViewModel: SideBarViewModel, pasteboard: PasteboardWriting = NSPasteboard.general) {
        self.sidebarViewModel = sidebarViewModel
        self.pasteboard = pasteboard
        sidebarViewModel.$versionsState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] versionsState in
                self?.versionsState = versionsState
            }
            .store(in: &cancellables)

        sidebarViewModel.$versionsNextCursor
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cursor in
                self?.versionsNextCursor = cursor
            }
            .store(in: &cancellables)

        sidebarViewModel.$versionsMeta
            .receive(on: DispatchQueue.main)
            .sink { [weak self] meta in
                self?.versionsMeta = meta
            }
            .store(in: &cancellables)

        sidebarViewModel.$versionsPaginationFailed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] failed in
                self?.versionsPaginationFailed = failed
            }
            .store(in: &cancellables)

        sidebarViewModel.$isLoadingMoreVersions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in
                self?.isLoadingMoreVersions = loading
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
                // Batch C1: app switch clears the App Info panel cleanly —
                // the App Info tab refetches on appear for the new app.
                self.appInfoFetchTask?.cancel()
                self.appInfoState = .idle
                self.versionLocalizationsState = .idle
                self.exportComplianceState = .idle
                self.appInfoLoadedAppId = nil
                self.versionLocalizationsLoadedVersionId = nil
                self.exportComplianceLoadedAppId = nil
            }
            .store(in: &cancellables)
    }
}

extension DetailViewModel {
    func retryVersions() {
        sidebarViewModel.retryVersions()
    }

    /// Loads the next versions page, like builds pagination.
    func loadMoreVersions(cursor: String) {
        sidebarViewModel.loadMoreVersions(cursor: cursor)
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
                           "limit": String(AppConfigs.buildLimit)]

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

    // MARK: - Multi-locale drafts (Phase 3)

    /// Draft ids for localizations the server hasn't issued yet. The
    /// create-vs-update decision keys off this prefix because a draft entry
    /// always exists in the list once the user types (so "missing locale"
    /// can never signal "needs POST").
    private static let tempLocalizationPrefix = "temp-"

    // MARK: - App Info (Batch C1, read-only)

    /// Loads everything the App Info tab shows. Guarded by the staleness
    /// ids so it is safe to call from onAppear on every tab switch.
    func loadAppInfo(force: Bool = false) {
        guard let app = selectedApp else { return }
        let needsFetch = force
            || appInfoLoadedAppId != app.id
            || exportComplianceLoadedAppId != app.id
            || versionLocalizationsLoadedVersionId != app.currentLiveVersion.0
        guard needsFetch else { return }

        appInfoFetchTask?.cancel()
        appInfoFetchTask = Task { await fetchAllAppInfo(app: app) }
    }

    func retryAppInfo() {
        loadAppInfo(force: true)
    }

    private func fetchAllAppInfo(app: AppsData) async {
        // Independent endpoints — fetch in parallel, not sequentially.
        // Each fetch sets only its own state and guards Task.isCancelled,
        // so semantics (incl. cancellation) match the sequential version.
        async let infos: Void = fetchAppInfos(appId: app.id)
        async let localizations: Void = fetchVersionLocalizations(versionId: app.currentLiveVersion.0)
        async let compliance: Void = fetchExportCompliance(appId: app.id)
        await infos
        await localizations
        await compliance
    }

    /// GET /v1/apps/{id}/appInfos — composed with the /apps prefix plus
    /// `path` (see APIName.Batch C note): no `case getAppInfos = "/appInfos"`
    /// exists because that raw value would build /v1/appInfos/{path}, which
    /// is not a valid route.
    func fetchAppInfos(appId: String) async {
        // A cancelled predecessor must not issue work (see ResourcesViewModel.fetch).
        guard !Task.isCancelled else { return }
        appInfoState = .loading

        let queryParams = [
            "include": "ageRatingDeclaration,appInfoLocalizations,primaryCategory,primarySubcategoryOne,primarySubcategoryTwo,secondaryCategory,secondarySubcategoryOne,secondarySubcategoryTwo",
            "limit[appInfoLocalizations]": "50"
        ]
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getAllApps, queryParams: queryParams, path: "\(appId)/appInfos"),
            apiVersion: .v1) else {
            appInfoState = .error("No team selected. Add a team to load app info.")
            return
        }

        do {
            let data = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return }
            let model = try getDecoder().decode(AppInfosDocument.self, from: data)
            // Staleness id only on success: recording it before the fetch
            // would mark a failed load as "loaded" and suppress the
            // automatic retry on next appear (stuck on error forever).
            appInfoLoadedAppId = appId
            appInfoState = model.data.isEmpty ? .empty : .loaded(model.data)
        } catch {
            guard !Task.isCancelled else { return }
            detailLogger.error("Failed to load app infos: \(error.localizedDescription)")
            appInfoState = .error(appInfoErrorMessage(for: error))
        }
    }

    /// GET /v1/appStoreVersions/{id}/appStoreVersionLocalizations for the
    /// app's current live version. limit=200 (the endpoint maximum) so all
    /// locales arrive in one page.
    func fetchVersionLocalizations(versionId: String) async {
        guard !Task.isCancelled else { return }
        guard !versionId.isEmpty else {
            // Terminal state (no live version) — record it so we don't
            // re-evaluate on every appear.
            versionLocalizationsLoadedVersionId = versionId
            versionLocalizationsState = .empty
            return
        }
        versionLocalizationsState = .loading

        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getAppStoreVersions, queryParams: ["limit": "200"], path: "\(versionId)/appStoreVersionLocalizations"),
            apiVersion: .v1) else {
            versionLocalizationsState = .error("No team selected. Add a team to load version info.")
            return
        }

        do {
            let data = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return }
            let model = try getDecoder().decode(AppStoreVersionLocalizationsDocument.self, from: data)
            // Staleness id only on success (see fetchAppInfos).
            versionLocalizationsLoadedVersionId = versionId
            versionLocalizationsState = model.data.isEmpty ? .empty : .loaded(model.data)
        } catch {
            guard !Task.isCancelled else { return }
            detailLogger.error("Failed to load version localizations: \(error.localizedDescription)")
            versionLocalizationsState = .error(appInfoErrorMessage(for: error))
        }
    }

    /// GET /v1/apps/{id}/appEncryptionDeclarations — export compliance.
    func fetchExportCompliance(appId: String) async {
        guard !Task.isCancelled else { return }
        exportComplianceState = .loading

        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getAllApps, queryParams: ["limit": "200"], path: "\(appId)/appEncryptionDeclarations"),
            apiVersion: .v1) else {
            exportComplianceState = .error("No team selected. Add a team to load export compliance.")
            return
        }

        do {
            let data = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return }
            let model = try getDecoder().decode(AppEncryptionDeclarationsDocument.self, from: data)
            // Staleness id only on success (see fetchAppInfos).
            exportComplianceLoadedAppId = appId
            exportComplianceState = model.data.isEmpty ? .empty : .loaded(model.data)
        } catch {
            guard !Task.isCancelled else { return }
            detailLogger.error("Failed to load export compliance: \(error.localizedDescription)")
            exportComplianceState = .error(appInfoErrorMessage(for: error))
        }
    }

    /// Read-only App Info endpoints can 403 with a narrow (TestFlight-only)
    /// API key — surface a hint instead of a bare server message.
    private func appInfoErrorMessage(for error: Error) -> String {
        if let apiError = error as? APIError {
            if apiError.statusCode == 403 {
                return "\(apiError.details) — this section may need an API key with broader permissions (e.g. App Manager)."
            }
            return apiError.details
        }
        return error.localizedDescription
    }

    func updateBuildWhatsNew(buildId: String, locale: String, whatsNew: String) {
        guard case .loaded(var builds) = buildsState,
              let buildIndex = builds.firstIndex(where: { $0.id == buildId }) else { return }

        if let index = builds[buildIndex].betaBuildLocalizations.firstIndex(where: { $0.locale == locale }) {
            builds[buildIndex].betaBuildLocalizations[index].whatsNew = whatsNew
        } else {
            let betaBuildLocalization = BuildLocalizationsModel(
                id: "\(Self.tempLocalizationPrefix)\(UUID().uuidString)",
                locale: locale,
                whatsNew: whatsNew
            )
            builds[buildIndex].betaBuildLocalizations.append(betaBuildLocalization)
        }
        buildsState = .loaded(builds)
    }

    func getWhatsNew(for buildId: String, locale: String) -> String {
        guard let build = buildsState.loadedValue?.first(where: { $0.id == buildId }),
              let localization = build.betaBuildLocalizations.first(where: { $0.locale == locale }) else {
            return ""
        }
        return localization.whatsNew ?? ""
    }

    func getAllLocales(for buildId: String) -> [String] {
        guard let build = buildsState.loadedValue?.first(where: { $0.id == buildId }) else { return [BetaLocalizationLocales.defaultLocale] }
        let locales = build.betaBuildLocalizations.compactMap { $0.locale }
        return locales.isEmpty ? [BetaLocalizationLocales.defaultLocale] : locales
    }

    func saveBuildLocalization(buildId: String, locale: String) {
        guard case .loaded(let builds) = buildsState,
              let build = builds.first(where: { $0.id == buildId }),
              let localization = build.betaBuildLocalizations.first(where: { $0.locale == locale }),
              localization.whatsNew != nil else { return }

        createOrUpdate(buildId: buildId, buildLocalization: localization, localization: localization.whatsNew ?? "", locale: locale)
    }

    func isBuildUpdating(_ buildId: String) -> Bool {
        return updatingSaveKeys.contains { $0.hasPrefix("\(buildId)|") }
    }
}

/// App Store Connect caps beta release notes at 4000 characters.
enum WhatsNewLimits {
    static let maxLength = 4000
}

/// Locales supported for TestFlight beta build localizations.
enum BetaLocalizationLocales {
    static let defaultLocale = "en-US"

    static let supported: [String] = [
        "ar-SA", "ca", "cs", "da", "de", "el", "en-AU", "en-CA", "en-GB", "en-US",
        "es-ES", "es-MX", "fi", "fr-FR", "he", "hi", "hr", "hu", "id", "it",
        "ja", "ko", "ms", "nl", "no", "pl", "pt-BR", "pt-PT", "ro", "ru",
        "sk", "sv", "th", "tr", "uk", "vi", "zh-Hans", "zh-Hant"
    ]
}

/// Injectable pasteboard so clipboard writes can be tested or redirected.
protocol PasteboardWriting {
    func clear()
    func setString(_ string: String)
}

extension NSPasteboard: PasteboardWriting {
    func clear() { clearContents() }
    func setString(_ string: String) { setString(string, forType: .string) }
}

/// Toast event with identity so consecutive identical messages still
/// re-fire `onChange` (which only triggers on value change).
struct ToastEvent: Equatable {
    let id = UUID()
    let message: String
}

extension DetailViewModel {
    func createOrUpdate(buildId: String, buildLocalization: BuildLocalizationsModel, localization: String, locale: String) {
        let saveKey = "\(buildId)|\(locale)"
        guard !updatingSaveKeys.contains(saveKey) else {
            showToast("A save is already in progress for this build.")
            return
        }
        updatingSaveKeys.insert(saveKey)

        Task {
            if buildLocalization.id.hasPrefix(Self.tempLocalizationPrefix) {
                await createBuildLocalization(buildId: buildId, buildLocalization: buildLocalization, localization: localization, locale: locale)
            } else {
                await updateBuildLocalization(buildId: buildId, buildLocalization: buildLocalization, localization: localization, locale: locale)
            }
        }
    }

    private func updateBuildLocalization(buildId: String, buildLocalization: BuildLocalizationsModel, localization: String, locale: String) async {
        defer { updatingSaveKeys.remove("\(buildId)|\(locale)") }

        let model = BuildLocalizationsModel.updateBody(id: buildLocalization.id, whatsNew: buildLocalization.whatsNew)
        let encoder = JSONAPIEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(model),
              let request = APIClient.shared.getRequest(api: .patch(name: .postReleaseNote, body: data, path: buildLocalization.id), apiVersion: .v1) else {
            saveError = BuildSaveError(buildId: buildId, locale: locale, message: "Couldn't build the update request.")
            return
        }

        do {
            let responseData = try await APIClient.shared.callAPI(with: request)
            let model = try getDecoder().decode(BuildLocalizationsModel.self, from: responseData)

            // Re-locate the build after the await: the list may have changed
            // (refresh, pagination) since the save started, so a captured
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
            saveError = BuildSaveError(buildId: buildId, locale: locale, message: friendlySaveMessage(for: error))
        }
    }

    private func createBuildLocalization(buildId: String, buildLocalization: BuildLocalizationsModel, localization: String, locale: String) async {
        defer { updatingSaveKeys.remove("\(buildId)|\(locale)") }

        let body = CreateLocalizationRequest(
            data: CreateLocalizationData(
                attributes: CreateLocalizationAttributes(locale: locale, whatsNew: buildLocalization.whatsNew),
                relationships: CreateLocalizationRelationships(
                    build: CreateLocalizationBuildLink(
                        data: CreateLocalizationBuildRef(id: buildId)
                    )
                )
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(body),
              let request = APIClient.shared.getRequest(api: .post(name: .postReleaseNote, body: data), apiVersion: .v1) else {
            saveError = BuildSaveError(buildId: buildId, locale: locale, message: "Couldn't build the save request.")
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

            // Replace the temporary draft with the real one from the API.
            if let index = currentBuilds[buildIndex].betaBuildLocalizations.firstIndex(where: { $0.locale == locale }) {
                currentBuilds[buildIndex].betaBuildLocalizations[index] = buildLocalizationsModel
            } else {
                currentBuilds[buildIndex].betaBuildLocalizations.append(buildLocalizationsModel)
            }
            buildsState = .loaded(currentBuilds)
        } catch {
            detailLogger.error("Failed to create localization: \(error.localizedDescription)")
            saveError = BuildSaveError(buildId: buildId, locale: locale, message: friendlySaveMessage(for: error))
        }
    }

    private func friendlySaveMessage(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.details
        }
        return error.localizedDescription
    }

    // MARK: - Expire build (Phase 3)

    /// Expires a build. There is no unexpire API (PATCH expired=false
    /// returns 409), so the UI never offers this for expired builds.
    func expireBuild(buildId: String) {
        guard case .loaded(let builds) = buildsState,
              let build = builds.first(where: { $0.id == buildId }),
              build.expired != true,
              expireTogglingBuildId != buildId else { return }

        expireTogglingBuildId = buildId

        let requestBody = ExpireBuildRequest(
            data: ExpireBuildData(
                id: buildId,
                attributes: ExpireBuildAttributes(expired: true)
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(requestBody),
              let request = APIClient.shared.getRequest(api: .patch(name: .getVersionBuilds, body: data, path: buildId), apiVersion: .v1) else {
            expireTogglingBuildId = nil
            showToast("Couldn't build the expire request.")
            return
        }

        Task {
            defer { expireTogglingBuildId = nil }
            do {
                let responseData = try await APIClient.shared.callAPI(with: request)
                let model = try getDecoder().decode(BuildsModel.self, from: responseData)
                guard case .loaded(var currentBuilds) = buildsState,
                      let buildIndex = currentBuilds.firstIndex(where: { $0.id == buildId }) else { return }
                var updatedBuild = currentBuilds[buildIndex]
                updatedBuild.expired = model.expired ?? true
                currentBuilds[buildIndex] = updatedBuild
                buildsState = .loaded(currentBuilds)
                showToast("Build expired")
            } catch {
                detailLogger.error("Failed to expire build: \(error.localizedDescription)")
                showToast("Failed to expire build")
            }
        }
    }

    func copyVersionAndBuildId(buildId: String) {
        guard let build = buildsState.loadedValue?.first(where: { $0.id == buildId }),
              let version = selectedVersion?.version else { return }

        let versionBuildString = "\(version) (\(build.version ?? "")) - Build ID: \(buildId)"
        pasteboard.clear()
        pasteboard.setString(versionBuildString)
        showToast("Copied: \(versionBuildString)")
    }

    private func showToast(_ message: String) {
        // The view owns dismissal timing; each event carries a fresh UUID so
        // even identical consecutive messages re-trigger onChange.
        toast = ToastEvent(message: message)
    }
}

/// A failed release-note save, surfaced to the UI with a Retry action.
struct BuildSaveError: Identifiable, Equatable {
    let buildId: String
    let locale: String
    let message: String

    var id: String { "\(buildId)-\(locale)" }
}
