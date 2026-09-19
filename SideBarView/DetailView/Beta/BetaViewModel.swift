//
//  BetaViewModel.swift
//  App Store
//
//  Created by Nayan Bhut for Phase 4: TestFlight Groups/Testers.
//  Reuses Phase 1 error handling (APIError) + Phase 2 ViewState (CurrentAppState).
//

import SwiftUI
import Combine
import JSONAPI

@MainActor
final class BetaViewModel: ObservableObject {
    // MARK: - ViewState
    @Published var viewState: CurrentAppState = ._none

    // MARK: - Data
    @Published var groups: [BetaGroupModel] = []
    @Published var selectedGroup: BetaGroupModel?
    @Published var testers: [BetaTesterModel] = []
    @Published var groupsMeta: Meta?
    @Published var testersMeta: Meta?

    // MARK: - Error Handling
    @Published var errorMessage: String?
    @Published var hasError = false

    // MARK: - Loading Flags
    @Published var isGroupsLoaded = false
    @Published var isTestersLoaded = false
    @Published var updatingTesterId: String?
    @Published var updatingBuildId: String?

    // MARK: - Build TestFlight State
    @Published var betaDetails: [String: BuildBetaDetailModel] = [:]
    @Published var reviewStates: [String: String] = [:]
    @Published var reviewLoadingBuildId: String?

    // MARK: - Tester Email Search
    @Published var searchText = ""
    @Published var searchResult: BetaTesterModel?
    @Published var isSearching = false
    @Published var hasSearched = false

    private(set) var currentAppId: String?
    private var pendingAutoNotify: [String: Bool] = [:]

    private var cancellables = Set<AnyCancellable>()

    init() {
        $searchText
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.hasSearched = false
                self.searchResult = nil
            }
            .store(in: &cancellables)
    }

    // MARK: - Error Helpers

    private func presentError(_ error: APIError) {
        errorMessage = error.details
        hasError = true
    }

    private func presentMessage(_ message: String) {
        errorMessage = message
        hasError = true
    }

    private func serverMessage(from data: Data) -> String? {
        guard let json = data.getJsonValue(),
              let errors = json["errors"] as? [[String: AnyObject]],
              let detail = errors.first?["detail"] as? String else { return nil }
        return detail
    }

    func clearError() {
        errorMessage = nil
        hasError = false
    }

    // MARK: - Staleness / Truncation Helpers

    /// Groups cap (limit 50) indicator until cursor pagination is added.
    var groupsTruncationMessage: String? {
        guard let total = groupsMeta?.paging.total, total > groups.count else { return nil }
        return "Showing \(groups.count) of \(total) groups"
    }

    /// Testers cap (limit 100) indicator until cursor pagination is added.
    var testersTruncationMessage: String? {
        guard let total = testersMeta?.paging.total, total > testers.count else { return nil }
        return "Showing \(testers.count) of \(total) testers"
    }

    /// Toggle state consults the pending (not-yet-persisted) value first so
    /// the switch reflects the user's intent while the detail is re-fetching.
    func autoNotifyState(for buildId: String) -> Bool {
        if let pending = pendingAutoNotify[buildId] { return pending }
        return betaDetails[buildId]?.autoNotifyEnabled ?? false
    }

    // MARK: - Beta Groups

    func fetchBetaGroups(app: AppsData) {
        currentAppId = app.id
        selectedGroup = nil
        testers = []
        isTestersLoaded = false
        groups = []
        groupsMeta = nil
        clearSearch()

        let queryParams = [
            "filter[app]": app.id,
            "include": "betaTesters,builds",
            "sort": "name",
            "limit": "50"
        ]
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getBetaGroups, queryParams: queryParams), apiVersion: .v1) else { return }

        isGroupsLoaded = false
        viewState = .betaGroupsLoading
        let stateToken = viewState

        APIClient.shared.callAPI(with: request) { [weak self] result in
            Task { @MainActor in
                // Drop stale responses if the user switched apps mid-flight.
                guard let self, self.currentAppId == app.id else { return }
                if self.viewState == stateToken { self.viewState = ._none }
                self.isGroupsLoaded = true
                switch result {
                case .success(let data):
                    do {
                        // The server already sorts by name; trust its ordering.
                        let model = try getDecoder().decode(BetaGroupsDocument.self, from: data)
                        self.groups = model.data
                        self.groupsMeta = model.meta
                    } catch {
                        self.groups = []
                        self.presentMessage(self.serverMessage(from: data) ?? APIError.jsonParsingFailure.details)
                    }
                case .failure(let error):
                    self.groups = []
                    self.presentError(error)
                }
            }
        }
    }

    func selectGroup(_ group: BetaGroupModel) {
        clearSearch()
        // Re-tapping the already-loaded group shouldn't refetch testers.
        // Row highlighting is derived from selectedGroup?.id in the view.
        guard group.id != selectedGroup?.id || !isTestersLoaded else { return }
        selectedGroup = group
        // Clear the previous group's testers so stale rows never show while loading.
        testers = []
        fetchTesters(groupId: group.id)
    }

    // MARK: - Group Testers

    func fetchTesters(groupId: String) {
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getBetaGroups,
                      queryParams: ["limit": "100"],
                      path: "\(groupId)/betaTesters"),
            apiVersion: .v1) else { return }

        isTestersLoaded = false
        viewState = .betaTestersLoading
        let stateToken = viewState

        APIClient.shared.callAPI(with: request) { [weak self] result in
            Task { @MainActor in
                // Drop stale responses if the user switched groups mid-flight.
                guard let self, self.selectedGroup?.id == groupId else { return }
                if self.viewState == stateToken { self.viewState = ._none }
                self.isTestersLoaded = true
                switch result {
                case .success(let data):
                    do {
                        let model = try getDecoder().decode(BetaTestersDocument.self, from: data)
                        self.testers = model.data
                        self.testersMeta = model.meta
                    } catch {
                        // Reset loading state before falling back to the filter request.
                        self.testers = []
                        self.isTestersLoaded = false
                        self.viewState = .betaTestersLoading
                        self.fetchTestersViaFilter(groupId: groupId)
                    }
                case .failure(let error):
                    // Nested relationship endpoints may 404 for some groups;
                    // fall back to the filter endpoint instead of erroring out.
                    if error.statusCode == 404 {
                        self.isTestersLoaded = false
                        self.viewState = .betaTestersLoading
                        self.fetchTestersViaFilter(groupId: groupId)
                    } else {
                        self.testers = []
                        self.presentError(error)
                    }
                }
            }
        }
    }

    private func fetchTestersViaFilter(groupId: String) {
        let queryParams = ["filter[betaGroups]": groupId, "limit": "100"]
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getBetaTesters, queryParams: queryParams), apiVersion: .v1) else {
            testers = []
            isTestersLoaded = true
            viewState = ._none
            return
        }
        let stateToken = viewState
        APIClient.shared.callAPI(with: request) { [weak self] result in
            Task { @MainActor in
                guard let self, self.selectedGroup?.id == groupId else { return }
                if self.viewState == stateToken { self.viewState = ._none }
                self.isTestersLoaded = true
                switch result {
                case .success(let data):
                    do {
                        let model = try getDecoder().decode(BetaTestersDocument.self, from: data)
                        self.testers = model.data
                        self.testersMeta = model.meta
                    } catch {
                        self.testers = []
                        self.presentMessage(self.serverMessage(from: data) ?? APIError.jsonParsingFailure.details)
                    }
                case .failure(let error):
                    self.testers = []
                    self.presentError(error)
                }
            }
        }
    }

    // MARK: - Tester Assignments

    func inviteTester(email: String, firstName: String? = nil, lastName: String? = nil, buildIds: [String] = []) {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard EmailValidator.isValid(trimmed) else {
            presentMessage("Enter a valid tester email address.")
            return
        }
        guard currentAppId != nil else {
            presentMessage("Select an app first.")
            return
        }
        guard let body = BetaTesterInvitationBody.invite(
            email: trimmed, firstName: firstName, lastName: lastName,
            betaGroupId: selectedGroup?.id, buildIds: buildIds) else {
            presentMessage(APIError.jsonConversionFailure.details)
            return
        }
        guard let request = APIClient.shared.getRequest(
            api: .post(name: .getBetaTesters, body: body), apiVersion: .v1) else { return }

        viewState = .betaAssignmentUpdating
        let stateToken = viewState

        APIClient.shared.callAPI(with: request) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                if self.viewState == stateToken { self.viewState = ._none }
                switch result {
                case .success(let data):
                    if let msg = self.serverMessage(from: data) {
                        self.presentMessage(msg)
                    } else if let groupId = self.selectedGroup?.id {
                        self.fetchTesters(groupId: groupId)
                    }
                case .failure(let error):
                    self.presentError(error)
                }
            }
        }
    }

    func addTestersToGroup(testerIds: [String]) {
        guard let groupId = selectedGroup?.id, !testerIds.isEmpty else { return }
        guard let body = BetaRelationshipBody.testerLinkage(ids: testerIds) else {
            presentMessage(APIError.jsonConversionFailure.details)
            return
        }
        guard let request = APIClient.shared.getRequest(
            api: .post(name: .getBetaGroups, body: body, path: "\(groupId)/relationships/betaTesters"),
            apiVersion: .v1) else { return }

        viewState = .betaAssignmentUpdating
        let stateToken = viewState
        APIClient.shared.callAPI(with: request) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                if self.viewState == stateToken { self.viewState = ._none }
                switch result {
                case .success(let data):
                    let serverError = self.serverMessage(from: data)
                    if data.isEmpty || serverError == nil {
                        self.fetchTesters(groupId: groupId)
                    } else {
                        self.presentMessage(serverError ?? "Failed to add testers.")
                    }
                case .failure(let error):
                    self.presentError(error)
                }
            }
        }
    }

    func removeTesterFromGroup(_ tester: BetaTesterModel) {
        guard let groupId = selectedGroup?.id else { return }
        guard let body = BetaRelationshipBody.testerLinkage(ids: [tester.id]) else {
            presentMessage(APIError.jsonConversionFailure.details)
            return
        }
        guard let request = APIClient.shared.getRequest(
            api: .delete(name: .getBetaGroups, path: "\(groupId)/relationships/betaTesters", body: body),
            apiVersion: .v1) else { return }

        updatingTesterId = tester.id
        viewState = .betaAssignmentUpdating
        let stateToken = viewState

        APIClient.shared.callAPI(with: request) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.updatingTesterId = nil
                if self.viewState == stateToken { self.viewState = ._none }
                switch result {
                case .success(let data):
                    let serverError = self.serverMessage(from: data)
                    if data.isEmpty || serverError == nil {
                        self.testers.removeAll { $0.id == tester.id }
                        // Keep the group row's tester count in sync.
                        if let groupIndex = self.groups.firstIndex(where: { $0.id == groupId }),
                           let testerIndex = self.groups[groupIndex].betaTesters.firstIndex(where: { $0.id == tester.id }) {
                            self.groups[groupIndex].betaTesters.remove(at: testerIndex)
                        }
                    } else {
                        self.presentMessage(serverError ?? "Failed to remove tester.")
                    }
                case .failure(let error):
                    self.presentError(error)
                }
            }
        }
    }

    func assignBuildToGroup(build: BuildsModel) {
        guard let groupId = selectedGroup?.id else {
            presentMessage("Select a beta group first.")
            return
        }
        guard let body = BetaRelationshipBody.buildLinkage(ids: [build.id]) else {
            presentMessage(APIError.jsonConversionFailure.details)
            return
        }
        guard let request = APIClient.shared.getRequest(
            api: .post(name: .getBetaGroups, body: body, path: "\(groupId)/relationships/builds"),
            apiVersion: .v1) else { return }

        updatingBuildId = build.id
        viewState = .betaAssignmentUpdating
        let stateToken = viewState
        APIClient.shared.callAPI(with: request) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.updatingBuildId = nil
                if self.viewState == stateToken { self.viewState = ._none }
                switch result {
                case .success(let data):
                    let serverError = self.serverMessage(from: data)
                    if let serverError {
                        self.presentMessage(serverError)
                    } else {
                        // Keep the group row's builds relationship in sync.
                        if let groupIndex = self.groups.firstIndex(where: { $0.id == groupId }),
                           !self.groups[groupIndex].builds.contains(where: { $0.id == build.id }) {
                            self.groups[groupIndex].builds.append(build)
                        }
                        self.presentMessage("Build \(build.version ?? "") assigned to the group.")
                    }
                case .failure(let error):
                    self.presentError(error)
                }
            }
        }
    }

    // MARK: - Tester Email Search

    func clearSearch() {
        searchText = ""
        searchResult = nil
        hasSearched = false
        isSearching = false
    }

    /// GET /betaTesters?filter[email]=...&filter[apps]=...
    func searchTesterByEmail() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard EmailValidator.isValid(query) else {
            presentMessage("Enter a valid email to search.")
            return
        }
        guard currentAppId != nil else {
            presentMessage("Select an app first.")
            return
        }

        var queryParams = [
            "filter[email]": query,
            "limit": "1"
        ]
        if let appId = currentAppId {
            queryParams["filter[apps]"] = appId
        }
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getBetaTesters, queryParams: queryParams), apiVersion: .v1) else { return }

        isSearching = true
        hasSearched = true
        searchResult = nil

        let searchedAppId = currentAppId
        APIClient.shared.callAPI(with: request) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isSearching = false
                // Drop stale results if the app or the query changed mid-flight.
                guard self.currentAppId == searchedAppId, self.searchText == query else { return }
                switch result {
                case .success(let data):
                    do {
                        let model = try getDecoder().decode(BetaTestersDocument.self, from: data)
                        self.searchResult = model.data.first
                    } catch {
                        self.presentMessage(self.serverMessage(from: data) ?? APIError.jsonParsingFailure.details)
                    }
                case .failure(let error):
                    self.presentError(error)
                }
            }
        }
    }

    // MARK: - Build Auto-Notify

    func fetchBuildBetaDetail(buildId: String) {
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getVersionBuilds, path: "\(buildId)/buildBetaDetail"),
            apiVersion: .v1) else { return }

        viewState = .betaDetailUpdating
        let stateToken = viewState
        APIClient.shared.callAPI(with: request) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                if self.viewState == stateToken { self.viewState = ._none }
                switch result {
                case .success(let data):
                    do {
                        let detail = try getDecoder().decode(BuildBetaDetailModel.self, from: data)
                        self.betaDetails[buildId] = detail

                        if let pending = self.pendingAutoNotify.removeValue(forKey: buildId),
                           detail.autoNotifyEnabled != pending {
                            self.setAutoNotify(buildId: buildId, enabled: pending)
                        }
                    } catch {
                        // Don't leave a pending value replaying a stale PATCH on
                        // some later successful fetch.
                        self.pendingAutoNotify.removeValue(forKey: buildId)
                        self.presentMessage(self.serverMessage(from: data) ?? APIError.jsonParsingFailure.details)
                    }
                case .failure(let error):
                    self.pendingAutoNotify.removeValue(forKey: buildId)
                    self.presentError(error)
                }
            }
        }
    }

    func setAutoNotify(buildId: String, enabled: Bool) {
        guard let detailId = betaDetails[buildId]?.id else {
            pendingAutoNotify[buildId] = enabled
            fetchBuildBetaDetail(buildId: buildId)
            return
        }
        let detail = BuildBetaDetailModel.updateBody(id: detailId, autoNotifyEnabled: enabled)
        let encoder = JSONAPIEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let body = try? encoder.encode(detail),
              let request = APIClient.shared.getRequest(
                api: .patch(name: .patchBuildBetaDetail, body: body, path: detailId),
                apiVersion: .v1) else {
            presentMessage(APIError.jsonConversionFailure.details)
            return
        }
        updatingBuildId = buildId
        viewState = .betaDetailUpdating
        let stateToken = viewState
        APIClient.shared.callAPI(with: request) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.updatingBuildId = nil
                if self.viewState == stateToken { self.viewState = ._none }
                switch result {
                case .success(let data):
                    do {
                        let updated = try getDecoder().decode(BuildBetaDetailModel.self, from: data)
                        self.betaDetails[buildId] = updated
                    } catch {
                        if data.isEmpty {
                            var current = self.betaDetails[buildId]
                            current?.autoNotifyEnabled = enabled
                            if let current { self.betaDetails[buildId] = current }
                        } else {
                            self.presentMessage(self.serverMessage(from: data) ?? APIError.jsonParsingFailure.details)
                        }
                    }
                case .failure(let error):
                    self.presentError(error)
                }
            }
        }
    }

    // MARK: - External Review

    func fetchReviewStatus(buildId: String) {
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getVersionBuilds, path: "\(buildId)/betaAppReviewSubmission"),
            apiVersion: .v1) else { return }
        reviewLoadingBuildId = buildId
        APIClient.shared.callAPI(with: request) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.reviewLoadingBuildId = nil
                switch result {
                case .success(let data):
                    do {
                        let submission = try getDecoder().decode(BetaAppReviewSubmissionModel.self, from: data)
                        self.reviewStates[buildId] = submission.betaReviewState ?? "UNKNOWN"
                    } catch {
                        // JSONAPIDecoder supports bare single-resource decoding
                        // (it unwraps the {"data": {...}} envelope itself), so a
                        // decode failure here means the server returned a null
                        // resource — i.e. no submission exists for this build.
                        self.reviewStates[buildId] = "NO_SUBMISSION"
                    }
                case .failure(let error):
                    // 404 = no submission exists yet; treat as not submitted.
                    if error.statusCode == 404 {
                        self.reviewStates[buildId] = "NO_SUBMISSION"
                    } else {
                        self.reviewStates[buildId] = "UNKNOWN"
                    }
                }
            }
        }
    }

    func submitForExternalReview(buildId: String) {
        guard let body = BetaReviewSubmissionBody.submit(buildId: buildId) else {
            presentMessage(APIError.jsonConversionFailure.details)
            return
        }
        guard let request = APIClient.shared.getRequest(
            api: .post(name: .postBetaAppReviewSubmission, body: body), apiVersion: .v1) else { return }

        reviewLoadingBuildId = buildId
        APIClient.shared.callAPI(with: request) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.reviewLoadingBuildId = nil
                switch result {
                case .success(let data):
                    do {
                        let submission = try getDecoder().decode(BetaAppReviewSubmissionModel.self, from: data)
                        self.reviewStates[buildId] = submission.betaReviewState ?? "WAITING_FOR_REVIEW"
                    } catch {
                        if let msg = self.serverMessage(from: data) {
                            self.presentMessage(msg)
                        } else {
                            self.reviewStates[buildId] = "WAITING_FOR_REVIEW"
                        }
                    }
                case .failure(let error):
                    self.presentError(error)
                }
            }
        }
    }
}
