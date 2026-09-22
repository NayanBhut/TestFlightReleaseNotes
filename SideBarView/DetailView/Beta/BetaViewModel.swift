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
import OSLog

private let betaLogger = Logger(subsystem: "com.appstore.release-notes", category: "Beta")

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
    /// Group id with a create/rename/delete in flight — per-group so one
    /// row's write never blocks another. "create" is the create-form key
    /// (never collides with a resource id).
    @Published var updatingGroupId: String?

    static let createGroupKey = "create-group"

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
        betaLogger.error("Beta request failed: \(error.details, privacy: .public)")
        errorMessage = error.details
        hasError = true
    }

    /// Generic catch-all so `catch` blocks log via Logger (no `print`)
    /// and surface a friendly message.
    private func presentError(_ error: Error) {
        if let apiError = error as? APIError {
            presentError(apiError)
            return
        }
        betaLogger.error("Beta request failed: \(error.localizedDescription, privacy: .public)")
        errorMessage = error.localizedDescription
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

    func fetchBetaGroups(app: AppsData) async {
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

        do {
            let data = try await APIClient.shared.callAPI(with: request)
            // Drop stale responses if the user switched apps mid-flight.
            guard self.currentAppId == app.id else { return }
            if viewState == stateToken { viewState = ._none }
            isGroupsLoaded = true
            do {
                // The server already sorts by name; trust its ordering.
                let model = try getDecoder().decode(BetaGroupsDocument.self, from: data)
                groups = model.data
                groupsMeta = model.meta
            } catch {
                groups = []
                presentMessage(serverMessage(from: data) ?? APIError.jsonParsingFailure.details)
            }
        } catch {
            // Drop stale failures: the user switched apps mid-flight and
            // the newer fetch owns the state now.
            guard self.currentAppId == app.id else { return }
            if viewState == stateToken { viewState = ._none }
            groups = []
            presentError(error)
            isGroupsLoaded = true
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
        Task { await fetchTesters(groupId: group.id) }
    }

    // MARK: - Group Testers

    func fetchTesters(groupId: String) async {
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getBetaGroups,
                      queryParams: ["limit": "100"],
                      path: "\(groupId)/betaTesters"),
            apiVersion: .v1) else { return }

        isTestersLoaded = false
        viewState = .betaTestersLoading
        let stateToken = viewState

        do {
            let data = try await APIClient.shared.callAPI(with: request)
            // Drop stale responses if the user switched groups mid-flight.
            guard self.selectedGroup?.id == groupId else { return }
            if viewState == stateToken { viewState = ._none }
            isTestersLoaded = true
            do {
                let model = try getDecoder().decode(BetaTestersDocument.self, from: data)
                testers = model.data
                testersMeta = model.meta
            } catch {
                // Reset loading state before falling back to the filter request.
                testers = []
                isTestersLoaded = false
                viewState = .betaTestersLoading
                await fetchTestersViaFilter(groupId: groupId)
            }
        } catch {
            // Drop stale failures: the user switched groups mid-flight and
            // the newer fetch owns the state now (incl. the 404 fallback —
            // a stale 404 must not fire a wasted filter request).
            guard self.selectedGroup?.id == groupId else { return }
            // Nested relationship endpoints may 404 for some groups;
            // fall back to the filter endpoint instead of erroring out.
            if (error as? APIError)?.statusCode == 404 {
                isTestersLoaded = false
                viewState = .betaTestersLoading
                await fetchTestersViaFilter(groupId: groupId)
            } else {
                if viewState == stateToken { viewState = ._none }
                testers = []
                presentError(error)
                isTestersLoaded = true
            }
        }
    }

    private func fetchTestersViaFilter(groupId: String) async {
        let queryParams = ["filter[betaGroups]": groupId, "limit": "100"]
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getBetaTesters, queryParams: queryParams), apiVersion: .v1) else {
            testers = []
            isTestersLoaded = true
            viewState = ._none
            return
        }
        let stateToken = viewState
        do {
            let data = try await APIClient.shared.callAPI(with: request)
            guard self.selectedGroup?.id == groupId else { return }
            if viewState == stateToken { viewState = ._none }
            isTestersLoaded = true
            do {
                let model = try getDecoder().decode(BetaTestersDocument.self, from: data)
                testers = model.data
                testersMeta = model.meta
            } catch {
                testers = []
                presentMessage(serverMessage(from: data) ?? APIError.jsonParsingFailure.details)
            }
        } catch {
            // Drop stale failures: the user switched groups mid-flight.
            guard self.selectedGroup?.id == groupId else { return }
            if viewState == stateToken { viewState = ._none }
            testers = []
            presentError(error)
            isTestersLoaded = true
        }
    }

    // MARK: - Tester Assignments

    func inviteTester(email: String, firstName: String? = nil, lastName: String? = nil, buildIds: [String] = []) async {
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

        do {
            let data = try await APIClient.shared.callAPI(with: request)
            // Always exit the updating state before handling the result:
            // the old guard-return left viewState stuck on
            // .betaAssignmentUpdating (permanently disabled controls).
            if viewState == stateToken { viewState = ._none }
            if let msg = serverMessage(from: data) {
                presentMessage(msg)
            } else if let groupId = selectedGroup?.id {
                await fetchTesters(groupId: groupId)
            }
        } catch {
            if viewState == stateToken { viewState = ._none }
            presentError(error)
        }
    }

    func addTestersToGroup(testerIds: [String]) async {
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
        do {
            let data = try await APIClient.shared.callAPI(with: request)
            // Always exit the updating state before handling the result:
            // the old guard-return left viewState stuck on
            // .betaAssignmentUpdating (permanently disabled controls).
            if viewState == stateToken { viewState = ._none }
            let serverError = serverMessage(from: data)
            if data.isEmpty || serverError == nil {
                await fetchTesters(groupId: groupId)
            } else {
                presentMessage(serverError ?? "Failed to add testers.")
            }
        } catch {
            if viewState == stateToken { viewState = ._none }
            presentError(error)
        }
    }

    func removeTesterFromGroup(_ tester: BetaTesterModel) async {
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

        do {
            let data = try await APIClient.shared.callAPI(with: request)
            updatingTesterId = nil
            if viewState == stateToken { viewState = ._none }
            let serverError = serverMessage(from: data)
            if data.isEmpty || serverError == nil {
                testers.removeAll { $0.id == tester.id }
                // Keep the group row's tester count in sync.
                if let groupIndex = groups.firstIndex(where: { $0.id == groupId }),
                   let testerIndex = groups[groupIndex].betaTesters.firstIndex(where: { $0.id == tester.id }) {
                    groups[groupIndex].betaTesters.remove(at: testerIndex)
                }
            } else {
                presentMessage(serverError ?? "Failed to remove tester.")
            }
        } catch {
            updatingTesterId = nil
            if viewState == stateToken { viewState = ._none }
            presentError(error)
        }
    }

    func assignBuildToGroup(build: BuildsModel) async {
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
        do {
            let data = try await APIClient.shared.callAPI(with: request)
            updatingBuildId = nil
            if viewState == stateToken { viewState = ._none }
            let serverError = serverMessage(from: data)
            if let serverError {
                presentMessage(serverError)
            } else {
                // Keep the group row's builds relationship in sync.
                if let groupIndex = groups.firstIndex(where: { $0.id == groupId }),
                   !groups[groupIndex].builds.contains(where: { $0.id == build.id }) {
                    groups[groupIndex].builds.append(build)
                }
                presentMessage("Build \(build.version ?? "") assigned to the group.")
            }
        } catch {
            updatingBuildId = nil
            if viewState == stateToken { viewState = ._none }
            presentError(error)
        }
    }

    // MARK: - Group CRUD (Batch I, I5)
    //
    // POST /v1/betaGroups (name + optional public-link options, with the
    // app relationship), PATCH /v1/betaGroups/{id} (rename),
    // DELETE /v1/betaGroups/{id}, DELETE /v1/betaTesters/{id} (removes the
    // tester from the team entirely — unlike removeTesterFromGroup, which
    // only unlinks from the selected group). Follows this file's existing
    // viewState/presentError pattern; forms stay open on failure (the
    // caller only dismisses when no error was presented).

    /// POST /v1/betaGroups. Returns true when the group was created (the
    /// caller can dismiss); false leaves the form open with the error shown.
    func createGroup(name: String, publicLinkEnabled: Bool, publicLinkLimit: Int?) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            presentMessage("Enter a name for the group.")
            return false
        }
        if let limit = publicLinkLimit, limit <= 0 {
            presentMessage("The public link limit must be a positive number.")
            return false
        }
        guard let appId = currentAppId else {
            presentMessage("Select an app first.")
            return false
        }
        guard updatingGroupId == nil else { return false }
        updatingGroupId = Self.createGroupKey

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let body = try? encoder.encode(BetaGroupCreateRequest(
            data: BetaGroupCreateData(
                attributes: BetaGroupCreateAttributes(
                    name: trimmedName,
                    publicLinkEnabled: publicLinkEnabled,
                    publicLinkLimitEnabled: publicLinkLimit != nil,
                    publicLinkLimit: publicLinkLimit
                ),
                relationships: BetaGroupCreateRelationships(
                    app: BetaGroupAppRelationship(data: BetaGroupAppRef(id: appId))
                )
            )
        )), let request = APIClient.shared.getRequest(
            api: .post(name: .getBetaGroups, body: body), apiVersion: .v1) else {
            updatingGroupId = nil
            presentMessage(APIError.jsonConversionFailure.details)
            return false
        }

        viewState = .betaAssignmentUpdating
        let stateToken = viewState
        do {
            let data = try await APIClient.shared.callAPI(with: request)
            updatingGroupId = nil
            if viewState == stateToken { viewState = ._none }
            guard !Task.isCancelled else { return false }
            do {
                let group = try getDecoder().decode(BetaGroupModel.self, from: data)
                // The list fetch sorts by name server-side — insert sorted
                // so the new row lands where a refresh would put it.
                groups.append(group)
                groups.sort { ($0.name ?? "") < ($1.name ?? "") }
                return true
            } catch {
                presentMessage(serverMessage(from: data) ?? APIError.jsonParsingFailure.details)
                return false
            }
        } catch {
            updatingGroupId = nil
            if viewState == stateToken { viewState = ._none }
            guard !Task.isCancelled else { return false }
            presentWriteError(error)
            return false
        }
    }

    /// PATCH /v1/betaGroups/{id} — rename only.
    func renameGroup(_ group: BetaGroupModel, newName: String) async -> Bool {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            presentMessage("Enter a name for the group.")
            return false
        }
        guard updatingGroupId == nil else { return false }
        updatingGroupId = group.id

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let body = try? encoder.encode(BetaGroupUpdateRequest(
            data: BetaGroupUpdateData(
                id: group.id,
                attributes: BetaGroupUpdateAttributes(name: trimmedName)
            )
        )), let request = APIClient.shared.getRequest(
            api: .patch(name: .getBetaGroups, body: body, path: group.id),
            apiVersion: .v1) else {
            updatingGroupId = nil
            presentMessage(APIError.jsonConversionFailure.details)
            return false
        }

        viewState = .betaAssignmentUpdating
        let stateToken = viewState
        do {
            let data = try await APIClient.shared.callAPI(with: request)
            updatingGroupId = nil
            if viewState == stateToken { viewState = ._none }
            guard !Task.isCancelled else { return false }
            do {
                let updated = try getDecoder().decode(BetaGroupModel.self, from: data)
                if let index = groups.firstIndex(where: { $0.id == group.id }) {
                    groups[index] = updated
                    groups.sort { ($0.name ?? "") < ($1.name ?? "") }
                }
                if selectedGroup?.id == group.id { selectedGroup = updated }
                return true
            } catch {
                presentMessage(serverMessage(from: data) ?? APIError.jsonParsingFailure.details)
                return false
            }
        } catch {
            updatingGroupId = nil
            if viewState == stateToken { viewState = ._none }
            guard !Task.isCancelled else { return false }
            presentWriteError(error)
            return false
        }
    }

    /// DELETE /v1/betaGroups/{id}. Callers must confirm first
    /// (destructive, cannot be undone).
    func deleteGroup(_ group: BetaGroupModel) async {
        guard updatingGroupId == nil else { return }
        updatingGroupId = group.id

        guard let request = APIClient.shared.getRequest(
            api: .delete(name: .getBetaGroups, path: group.id),
            apiVersion: .v1) else {
            updatingGroupId = nil
            presentMessage(APIError.jsonConversionFailure.details)
            return
        }

        viewState = .betaAssignmentUpdating
        let stateToken = viewState
        do {
            _ = try await APIClient.shared.callAPI(with: request)
            updatingGroupId = nil
            if viewState == stateToken { viewState = ._none }
            guard !Task.isCancelled else { return }
            groups.removeAll { $0.id == group.id }
            if selectedGroup?.id == group.id {
                selectedGroup = nil
                testers = []
                isTestersLoaded = false
            }
        } catch {
            updatingGroupId = nil
            if viewState == stateToken { viewState = ._none }
            guard !Task.isCancelled else { return }
            presentWriteError(error)
        }
    }

    /// DELETE /v1/betaTesters/{id} — deletes the tester from the team
    /// (stronger than removeTesterFromGroup). Callers must confirm first.
    func deleteTester(_ tester: BetaTesterModel) async {
        guard updatingTesterId == nil else { return }
        updatingTesterId = tester.id

        guard let request = APIClient.shared.getRequest(
            api: .delete(name: .getBetaTesters, path: tester.id),
            apiVersion: .v1) else {
            updatingTesterId = nil
            presentMessage(APIError.jsonConversionFailure.details)
            return
        }

        viewState = .betaAssignmentUpdating
        let stateToken = viewState
        do {
            _ = try await APIClient.shared.callAPI(with: request)
            updatingTesterId = nil
            if viewState == stateToken { viewState = ._none }
            guard !Task.isCancelled else { return }
            testers.removeAll { $0.id == tester.id }
            for index in groups.indices {
                groups[index].betaTesters.removeAll { $0.id == tester.id }
            }
        } catch {
            updatingTesterId = nil
            if viewState == stateToken { viewState = ._none }
            guard !Task.isCancelled else { return }
            presentWriteError(error)
        }
    }

    /// Group/tester writes need an Admin/Account Holder key — a
    /// TestFlight-only key 403s. Surface the permissions hint, not a raw
    /// error (same contract as the Resources writes).
    private func presentWriteError(_ error: Error) {
        if let apiError = error as? APIError, apiError.statusCode == 403 {
            presentMessage("\(apiError.details) — this action needs an API key with the Admin role.")
        } else {
            presentError(error)
        }
    }

    // MARK: - Tester Email Search

    /// Team roster for the invite sheet's user picker (search + tap
    /// replaces manual email entry). Drained once per session; silent on
    /// failure (manual entry still works, the sheet shows the error).
    @Published var teamUsers: [UserModel] = []
    @Published var isTeamUsersLoading = false
    @Published var teamUsersError: String?

    private var teamUsersTask: Task<Void, Never>?
    private var teamUsersLoaded = false

    func loadTeamUsers() {
        guard !teamUsersLoaded else { return }
        teamUsersTask?.cancel()
        teamUsersTask = Task { await fetchTeamUsers() }
    }

    private func fetchTeamUsers() async {
        guard !Task.isCancelled else { return }
        isTeamUsersLoading = true
        teamUsersError = nil
        defer { isTeamUsersLoading = false }

        var accumulated: [UserModel] = []
        var cursor: String? = nil
        repeat {
            guard !Task.isCancelled else { return }
            var queryParams = ["sort": "username", "limit": "200"]
            if let cursor {
                queryParams["cursor"] = cursor
            }
            guard let request = APIClient.shared.getRequest(
                api: .get(name: .getUsers, queryParams: queryParams), apiVersion: .v1) else {
                teamUsersError = "No team selected."
                return
            }
            do {
                let data = try await APIClient.shared.callAPI(with: request)
                guard !Task.isCancelled else { return }
                let model = try getDecoder().decode(UsersDocument.self, from: data)
                let knownIDs = Set(accumulated.map(\.id))
                accumulated.append(contentsOf: model.data.filter { !knownIDs.contains($0.id) })
                cursor = model.meta.paging.nextCursor
            } catch {
                guard !Task.isCancelled else { return }
                betaLogger.error("Failed to load team users: \(error.localizedDescription, privacy: .public)")
                teamUsersError = (error as? APIError)?.details ?? error.localizedDescription
                return
            }
        } while cursor != nil
        teamUsers = accumulated
        teamUsersLoaded = true
    }

    /// Local match for the invite picker — username plus names, Finder-style.
    func matchingTeamUsers(query: String) -> [UserModel] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Array(teamUsers.prefix(50)) }
        return teamUsers.filter {
            $0.username?.localizedStandardContains(trimmed) == true
                || $0.firstName?.localizedStandardContains(trimmed) == true
                || $0.lastName?.localizedStandardContains(trimmed) == true
        }
    }

    func clearSearch() {
        searchText = ""
        searchResult = nil
        hasSearched = false
        isSearching = false
    }

    /// GET /betaTesters?filter[email]=...&filter[apps]=...
    func searchTesterByEmail() async {
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
        do {
            let data = try await APIClient.shared.callAPI(with: request)
            // Reset the spinner BEFORE the staleness guard: a stale result
            // (app/query changed mid-flight) must never leave isSearching
            // stuck on — the spinner permanently replaces the Search button.
            isSearching = false
            // Drop stale results if the app or the query changed mid-flight.
            guard self.currentAppId == searchedAppId, self.searchText == query else { return }
            do {
                let model = try getDecoder().decode(BetaTestersDocument.self, from: data)
                searchResult = model.data.first
            } catch {
                presentMessage(serverMessage(from: data) ?? APIError.jsonParsingFailure.details)
            }
        } catch {
            isSearching = false
            presentError(error)
        }
    }

    // MARK: - Build Auto-Notify

    func fetchBuildBetaDetail(buildId: String) async {
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getVersionBuilds, path: "\(buildId)/buildBetaDetail"),
            apiVersion: .v1) else { return }

        viewState = .betaDetailUpdating
        let stateToken = viewState
        do {
            let data = try await APIClient.shared.callAPI(with: request)
            if viewState == stateToken { viewState = ._none }
            do {
                let detail = try getDecoder().decode(BuildBetaDetailModel.self, from: data)
                betaDetails[buildId] = detail

                if let pending = pendingAutoNotify.removeValue(forKey: buildId),
                   detail.autoNotifyEnabled != pending {
                    await setAutoNotify(buildId: buildId, enabled: pending)
                }
            } catch {
                // Don't leave a pending value replaying a stale PATCH on
                // some later successful fetch.
                pendingAutoNotify.removeValue(forKey: buildId)
                presentMessage(serverMessage(from: data) ?? APIError.jsonParsingFailure.details)
            }
        } catch {
            if viewState == stateToken { viewState = ._none }
            pendingAutoNotify.removeValue(forKey: buildId)
            presentError(error)
        }
    }

    func setAutoNotify(buildId: String, enabled: Bool) async {
        guard let detailId = betaDetails[buildId]?.id else {
            pendingAutoNotify[buildId] = enabled
            await fetchBuildBetaDetail(buildId: buildId)
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
        do {
            let data = try await APIClient.shared.callAPI(with: request)
            updatingBuildId = nil
            if viewState == stateToken { viewState = ._none }
            do {
                let updated = try getDecoder().decode(BuildBetaDetailModel.self, from: data)
                betaDetails[buildId] = updated
            } catch {
                if data.isEmpty {
                    var current = betaDetails[buildId]
                    current?.autoNotifyEnabled = enabled
                    if let current { betaDetails[buildId] = current }
                } else {
                    presentMessage(serverMessage(from: data) ?? APIError.jsonParsingFailure.details)
                }
            }
        } catch {
            updatingBuildId = nil
            if viewState == stateToken { viewState = ._none }
            presentError(error)
        }
    }

    // MARK: - External Review

    func fetchReviewStatus(buildId: String) async {
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getVersionBuilds, path: "\(buildId)/betaAppReviewSubmission"),
            apiVersion: .v1) else { return }
        reviewLoadingBuildId = buildId
        do {
            let data = try await APIClient.shared.callAPI(with: request)
            reviewLoadingBuildId = nil
            do {
                let submission = try getDecoder().decode(BetaAppReviewSubmissionModel.self, from: data)
                reviewStates[buildId] = submission.betaReviewState ?? "UNKNOWN"
            } catch {
                // JSONAPIDecoder supports bare single-resource decoding
                // (it unwraps the {"data": {...}} envelope itself), so a
                // decode failure here means the server returned a null
                // resource — i.e. no submission exists for this build.
                reviewStates[buildId] = "NO_SUBMISSION"
            }
        } catch {
            reviewLoadingBuildId = nil
            // 404 = no submission exists yet; treat as not submitted.
            if (error as? APIError)?.statusCode == 404 {
                reviewStates[buildId] = "NO_SUBMISSION"
            } else {
                reviewStates[buildId] = "UNKNOWN"
            }
        }
    }

    func submitForExternalReview(buildId: String) async {
        guard let body = BetaReviewSubmissionBody.submit(buildId: buildId) else {
            presentMessage(APIError.jsonConversionFailure.details)
            return
        }
        guard let request = APIClient.shared.getRequest(
            api: .post(name: .postBetaAppReviewSubmission, body: body), apiVersion: .v1) else { return }

        reviewLoadingBuildId = buildId
        do {
            let data = try await APIClient.shared.callAPI(with: request)
            reviewLoadingBuildId = nil
            do {
                let submission = try getDecoder().decode(BetaAppReviewSubmissionModel.self, from: data)
                reviewStates[buildId] = submission.betaReviewState ?? "WAITING_FOR_REVIEW"
            } catch {
                if let msg = serverMessage(from: data) {
                    presentMessage(msg)
                } else {
                    reviewStates[buildId] = "WAITING_FOR_REVIEW"
                }
            }
        } catch {
            reviewLoadingBuildId = nil
            presentError(error)
        }
    }
}
