//
//  ResourcesViewModel.swift
//  App Store
//
//  Batch C2: team-scoped resources (read-only) — Devices, Certificates,
//  Bundle IDs, Profiles, Users. Follows the BetaViewModel pattern:
//  ViewState per list, in-flight task cancellation, cursor pagination
//  with retry, friendly 403 hint (these endpoints need an API key with
//  broader permissions than TestFlight-only). Create/revoke is a
//  follow-up; this is read-only.
//

import SwiftUI
import JSONAPI
import OSLog

private let resourcesLogger = Logger(subsystem: "com.appstore.release-notes", category: "Resources")

@MainActor
final class ResourcesViewModel: ObservableObject {

    // MARK: - Kinds

    enum Kind: String, CaseIterable, Identifiable {
        case devices
        case certificates
        case bundleIds
        case profiles
        case users

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .devices: return "Devices"
            case .certificates: return "Certificates"
            case .bundleIds: return "Bundle IDs"
            case .profiles: return "Profiles"
            case .users: return "Users"
            }
        }

        var systemImage: String {
            switch self {
            case .devices: return "iphone"
            case .certificates: return "checkmark.seal"
            case .bundleIds: return "square.grid.2x2"
            case .profiles: return "person.text.rectangle"
            case .users: return "person.2"
            }
        }

        var subtitle: String {
            switch self {
            case .devices: return "Test devices registered for the team"
            case .certificates: return "Signing certificates"
            case .bundleIds: return "Registered app identifiers"
            case .profiles: return "Provisioning profiles"
            case .users: return "App Store Connect team members"
            }
        }

        var apiName: APIName {
            switch self {
            case .devices: return .getDevices
            case .certificates: return .getCertificates
            case .bundleIds: return .getBundleIds
            case .profiles: return .getProfiles
            case .users: return .getUsers
            }
        }

        /// Sortable fields verified against Apple's OpenAPI spec per
        /// endpoint (inventing a sort field 400s the whole request).
        var sortParam: String? {
            switch self {
            case .devices: return "name"
            case .certificates: return "displayName"
            case .bundleIds: return "name"
            case .profiles: return "name"
            case .users: return "username"
            }
        }
    }

    // MARK: - State

    @Published var devicesState: ViewState<[DeviceModel]> = .idle
    @Published var certificatesState: ViewState<[CertificateModel]> = .idle
    @Published var bundleIdsState: ViewState<[BundleIdModel]> = .idle
    @Published var profilesState: ViewState<[ProfileModel]> = .idle
    @Published var usersState: ViewState<[UserModel]> = .idle

    /// Next-page cursor per kind (nil = no more pages).
    @Published var nextCursors: [Kind: String] = [:]
    /// Total count per kind from paging meta.
    @Published var totals: [Kind: Int] = [:]
    /// True when a pagination request failed, so the list can offer a retry.
    @Published var paginationFailed = false

    /// Kinds already loaded (or failed) — guards so re-opening a list
    /// doesn't refetch what's already there.
    private var loadedKinds: Set<Kind> = []
    private var fetchTasks: [Kind: Task<Void, Never>] = [:]
    private var isPaginating = false

    // MARK: - Loading

    /// Loads a kind's first page once per team session; `force` (Refresh)
    /// always refetches.
    func load(_ kind: Kind, force: Bool = false) {
        if loadedKinds.contains(kind), !force { return }
        fetchTasks[kind]?.cancel()
        fetchTasks[kind] = Task { await fetch(kind) }
    }

    func retry(_ kind: Kind) {
        fetchTasks[kind]?.cancel()
        fetchTasks[kind] = Task { await fetch(kind) }
    }

    func loadMore(_ kind: Kind, cursor: String) {
        guard !cursor.isEmpty else { return }
        fetchTasks[kind]?.cancel()
        fetchTasks[kind] = Task { await fetch(kind, cursor: cursor) }
    }

    // MARK: - Fetch

    private func fetch(_ kind: Kind, cursor: String? = nil) async {
        // A cancelled predecessor must not issue work: without this guard a
        // rapid re-entry fires a wasted request and overwrites cleared
        // state with .loading (the post-await guard alone can't prevent it).
        guard !Task.isCancelled else { return }
        let paginating = cursor != nil
        // Ignore duplicate "Load more" taps while a page is in flight.
        if paginating, isPaginating { return }
        if paginating {
            isPaginating = true
        } else {
            setLoading(for: kind)
        }
        paginationFailed = false
        defer {
            if paginating { self.isPaginating = false }
            loadedKinds.insert(kind)
        }

        var queryParams = ["limit": String(AppConfigs.resourceLimit)]
        if let cursor {
            queryParams["cursor"] = cursor
        }
        if let sort = kind.sortParam {
            queryParams["sort"] = sort
        }

        guard let request = APIClient.shared.getRequest(
            api: .get(name: kind.apiName, queryParams: queryParams), apiVersion: .v1) else {
            if !paginating {
                setError("No team selected. Add a team to load \(kind.displayName.lowercased()).", for: kind)
            }
            return
        }

        do {
            let data = try await APIClient.shared.callAPI(with: request)
            // Ignore stale responses superseded by a newer fetch.
            guard !Task.isCancelled else { return }
            try decodeAndApply(data: data, for: kind, isPaginating: paginating)
        } catch {
            guard !Task.isCancelled else { return }
            resourcesLogger.error("Failed to load \(kind.rawValue): \(error.localizedDescription)")
            if paginating {
                paginationFailed = true
            } else {
                setError(friendlyMessage(for: error), for: kind)
            }
        }
    }

    /// Per-kind decode + merge. Deduplicates by id so a double-fired cursor
    /// can never append the same rows twice (same contract as builds/apps).
    private func decodeAndApply(data: Data, for kind: Kind, isPaginating: Bool) throws {
        let decoder = getDecoder()
        switch kind {
        case .devices:
            let model = try decoder.decode(DevicesDocument.self, from: data)
            let existing = devicesState.loadedValue ?? []
            let merged = merge(existing: existing, incoming: model.data, isPaginating: isPaginating, id: \.id)
            nextCursors[kind] = model.meta.paging.nextCursor
            totals[kind] = model.meta.paging.total
            devicesState = merged.isEmpty ? .empty : .loaded(merged)
        case .certificates:
            let model = try decoder.decode(CertificatesDocument.self, from: data)
            let existing = certificatesState.loadedValue ?? []
            let merged = merge(existing: existing, incoming: model.data, isPaginating: isPaginating, id: \.id)
            // Certificates have no paging meta (see CertificatesDocument) —
            // one page, limit covers the whole team's certificates.
            nextCursors[kind] = nil
            totals[kind] = merged.count
            certificatesState = merged.isEmpty ? .empty : .loaded(merged)
        case .bundleIds:
            let model = try decoder.decode(BundleIdsDocument.self, from: data)
            let existing = bundleIdsState.loadedValue ?? []
            let merged = merge(existing: existing, incoming: model.data, isPaginating: isPaginating, id: \.id)
            nextCursors[kind] = model.meta.paging.nextCursor
            totals[kind] = model.meta.paging.total
            bundleIdsState = merged.isEmpty ? .empty : .loaded(merged)
        case .profiles:
            let model = try decoder.decode(ProfilesDocument.self, from: data)
            let existing = profilesState.loadedValue ?? []
            let merged = merge(existing: existing, incoming: model.data, isPaginating: isPaginating, id: \.id)
            nextCursors[kind] = model.meta.paging.nextCursor
            totals[kind] = model.meta.paging.total
            profilesState = merged.isEmpty ? .empty : .loaded(merged)
        case .users:
            let model = try decoder.decode(UsersDocument.self, from: data)
            let existing = usersState.loadedValue ?? []
            let merged = merge(existing: existing, incoming: model.data, isPaginating: isPaginating, id: \.id)
            nextCursors[kind] = model.meta.paging.nextCursor
            totals[kind] = model.meta.paging.total
            usersState = merged.isEmpty ? .empty : .loaded(merged)
        }
    }

    private func merge<T>(existing: [T], incoming: [T], isPaginating: Bool, id: KeyPath<T, String>) -> [T] {
        guard isPaginating else { return incoming }
        let existingIDs = Set(existing.map { $0[keyPath: id] })
        return existing + incoming.filter { !existingIDs.contains($0[keyPath: id]) }
    }

    /// Team switch / logout: drop everything so the next open refetches
    /// for the new team. Without this the sheet keeps showing the previous
    /// team's resources — and Load-more would paginate with a cursor from
    /// the wrong query epoch (cursors are only valid for the query that
    /// issued them). Called from SideBarView's existing team-change hooks.
    func resetForTeamSwitch() {
        for task in fetchTasks.values { task.cancel() }
        fetchTasks = [:]
        loadedKinds = []
        devicesState = .idle
        certificatesState = .idle
        bundleIdsState = .idle
        profilesState = .idle
        usersState = .idle
        nextCursors = [:]
        totals = [:]
        paginationFailed = false
        isPaginating = false
    }

    // MARK: - Per-kind state helpers

    private func setLoading(for kind: Kind) {
        switch kind {
        case .devices: devicesState = .loading
        case .certificates: certificatesState = .loading
        case .bundleIds: bundleIdsState = .loading
        case .profiles: profilesState = .loading
        case .users: usersState = .loading
        }
    }

    private func setError(_ message: String, for kind: Kind) {
        switch kind {
        case .devices: devicesState = .error(message)
        case .certificates: certificatesState = .error(message)
        case .bundleIds: bundleIdsState = .error(message)
        case .profiles: profilesState = .error(message)
        case .users: usersState = .error(message)
        }
    }

    // MARK: - Errors

    /// Team-scoped resource endpoints 403 with a TestFlight-only key —
    /// surface an actionable hint instead of a bare server message.
    private func friendlyMessage(for error: Error) -> String {
        if let apiError = error as? APIError {
            if apiError.statusCode == 403 {
                return "\(apiError.details) — resources need an API key with broader permissions than TestFlight-only."
            }
            return apiError.details
        }
        return error.localizedDescription
    }
}
