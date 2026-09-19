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

    private var currentAppId: String?
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

        APIClient.shared.callAPI(with: request) { [weak self] result in
            guard let self else { return }
            self.isGroupsLoaded = true
            self.viewState = ._none
            switch result {
            case .success(let data):
                do {
                    let model = try getDecoder().decode(BetaGroupsDocument.self, from: data)
                    self.groups = model.data.sorted { ($0.name ?? "") < ($1.name ?? "") }
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

    func selectGroup(_ group: BetaGroupModel) {
        clearSearch()
        groups = groups.map {
            var copy = $0
            copy.isSelected = $0.id == group.id
            return copy
        }
        selectedGroup = group
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

        APIClient.shared.callAPI(with: request) { [weak self] result in
            guard let self else { return }
            self.isTestersLoaded = true
            self.viewState = ._none
            switch result {
            case .success(let data):
                do {
                    let model = try getDecoder().decode(BetaTestersDocument.self, from: data)
                    self.testers = model.data
                    self.testersMeta = model.meta
                } catch {
                    self.fetchTestersViaFilter(groupId: groupId)
                }
            case .failure(let error):
                self.testers = []
                self.presentError(error)
            }
        }
    }

    private func fetchTestersViaFilter(groupId: String) {
        let queryParams = ["filter[betaGroups]": groupId, "limit": "100"]
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getBetaTesters, queryParams: queryParams), apiVersion: .v1) else {
            testers = []
            return
        }
        APIClient.shared.callAPI(with: request) { [weak self] result in
            guard let self else { return }
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
        updatingTesterId = trimmed

        APIClient.shared.callAPI(with: request) { [weak self] result in
            guard let self else { return }
            self.viewState = ._none
            self.updatingTesterId = nil
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
        APIClient.shared.callAPI(with: request) { [weak self] result in
            guard let self else { return }
            self.viewState = ._none
            switch result {
            case .success(let data):
                if data.isEmpty || self.serverMessage(from: data) == nil {
                    self.fetchTesters(groupId: groupId)
                } else {
                    self.presentMessage(self.serverMessage(from: data) ?? "Failed to add testers.")
                }
            case .failure(let error):
                self.presentError(error)
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

        APIClient.shared.callAPI(with: request) { [weak self] result in
            guard let self else { return }
            self.updatingTesterId = nil
            self.viewState = ._none
            switch result {
            case .success(let data):
                if data.isEmpty || self.serverMessage(from: data) == nil {
                    self.testers.removeAll { $0.id == tester.id }
                } else {
                    self.presentMessage(self.serverMessage(from: data) ?? "Failed to remove tester.")
                }
            case .failure(let error):
                self.presentError(error)
            }
        }
    }

    func assignBuildToGroup(buildId: String) {
        guard let groupId = selectedGroup?.id else {
            presentMessage("Select a beta group first.")
            return
        }
        guard let body = BetaRelationshipBody.buildLinkage(ids: [buildId]) else {
            presentMessage(APIError.jsonConversionFailure.details)
            return
        }
        guard let request = APIClient.shared.getRequest(
            api: .post(name: .getBetaGroups, body: body, path: "\(groupId)/relationships/builds"),
            apiVersion: .v1) else { return }

        updatingBuildId = buildId
        viewState = .betaAssignmentUpdating
        APIClient.shared.callAPI(with: request) { [weak self] result in
            guard let self else { return }
            self.updatingBuildId = nil
            self.viewState = ._none
            switch result {
            case .success(let data):
                if let msg = self.serverMessage(from: data) {
                    self.presentMessage(msg)
                }
            case .failure(let error):
                self.presentError(error)
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

        APIClient.shared.callAPI(with: request) { [weak self] result in
            guard let self else { return }
            self.isSearching = false
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

    // MARK: - Build Auto-Notify

    func fetchBuildBetaDetail(buildId: String) {
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getVersionBuilds, path: "\(buildId)/buildBetaDetail"),
            apiVersion: .v1) else { return }

        viewState = .betaDetailUpdating
        APIClient.shared.callAPI(with: request) { [weak self] result in
            guard let self else { return }
            self.viewState = ._none
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
                    self.presentMessage(self.serverMessage(from: data) ?? APIError.jsonParsingFailure.details)
                }
            case .failure(let error):
                self.presentError(error)
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
        APIClient.shared.callAPI(with: request) { [weak self] result in
            guard let self else { return }
            self.updatingBuildId = nil
            self.viewState = ._none
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

    // MARK: - External Review

    func fetchReviewStatus(buildId: String) {
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getVersionBuilds, path: "\(buildId)/betaAppReviewSubmission"),
            apiVersion: .v1) else { return }
        reviewLoadingBuildId = buildId
        APIClient.shared.callAPI(with: request) { [weak self] result in
            guard let self else { return }
            self.reviewLoadingBuildId = nil
            switch result {
            case .success(let data):
                do {
                    let submission = try getDecoder().decode(BetaAppReviewSubmissionModel.self, from: data)
                    self.reviewStates[buildId] = submission.betaReviewState ?? "UNKNOWN"
                } catch {
                    self.reviewStates[buildId] = "NO_SUBMISSION"
                }
            case .failure:
                self.reviewStates[buildId] = "UNKNOWN"
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
