//
//  ResourcesViewModel.swift
//  App Store
//
//  Batch C2: team-scoped resources (read-only) — Devices, Certificates,
//  Bundle IDs, Profiles, Users. Follows the BetaViewModel pattern:
//  ViewState per list, in-flight task cancellation, cursor pagination
//  with retry, friendly 403 hint (these endpoints need an API key with
//  broader permissions than TestFlight-only). Write lifecycle deferred
//  to Batch D4; this is read-only.
//
//  Batch F (#6): per-kind search text + local, case-insensitive filtering
//  across each model's display fields (search is local — server-side
//  search params aren't supported on these endpoints).
//

import SwiftUI
import JSONAPI
import OSLog

private let resourcesLogger = Logger(subsystem: "com.appstore.release-notes", category: "Resources")

@MainActor
final class ResourcesViewModel: ObservableObject {
    deinit {
        // A stuck network call must not keep the VM alive.
        for task in fetchTasks.values { task.cancel() }
    }

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
    /// Kinds whose pagination request failed, so only that kind's list
    /// offers a retry (a shared flag leaks one kind's failure into another's
    /// footer).
    @Published var paginationFailedKinds: Set<Kind> = []

    /// Per-kind search text — each kind's sheet filters independently (a
    /// UDID fragment typed in Devices must not leak into Certificates).
    @Published var searchTexts: [Kind: String] = [:]

    /// Kinds already loaded (or failed) — guards so re-opening a list
    /// doesn't refetch what's already there.
    private var loadedKinds: Set<Kind> = []
    private var fetchTasks: [Kind: Task<Void, Never>] = [:]
    /// Kinds with a page request in flight — per-kind so paginating one
    /// kind never swallows another kind's Load-more tap.
    private var isPaginatingKinds: Set<Kind> = []

    // MARK: - Search (Batch F #6)

    func searchText(for kind: Kind) -> String { searchTexts[kind] ?? "" }

    /// Per-kind binding for the sheet's search field.
    func searchBinding(for kind: Kind) -> Binding<String> {
        Binding(
            get: { self.searchTexts[kind] ?? "" },
            set: { self.searchTexts[kind] = $0 }
        )
    }

    /// Active query, trimmed; whitespace-only text disables filtering.
    private func query(for kind: Kind) -> String {
        (searchTexts[kind] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True while the kind has an effective (non-whitespace) query.
    func hasActiveSearch(_ kind: Kind) -> Bool { !query(for: kind).isEmpty }

    /// Local, case-insensitive match across the fields each kind's row
    /// displays — searching must surface a device whose UDID matches even
    /// when its name doesn't.
    private func filter<T>(_ items: [T], kind: Kind, fields: (T) -> [String?]) -> [T] {
        let active = query(for: kind)
        guard !active.isEmpty else { return items }
        return items.filter { item in
            fields(item).contains { $0?.localizedCaseInsensitiveContains(active) == true }
        }
    }

    var filteredDevices: [DeviceModel] {
        filter(devicesState.loadedValue ?? [], kind: .devices) {
            [$0.name, $0.model, $0.udid, $0.deviceClass, $0.platform, $0.status]
        }
    }

    var filteredCertificates: [CertificateModel] {
        filter(certificatesState.loadedValue ?? [], kind: .certificates) {
            // The row shows displayName with name as fallback — match both.
            [$0.displayName, $0.name, $0.serialNumber, $0.certificateType, $0.platform]
        }
    }

    var filteredBundleIds: [BundleIdModel] {
        filter(bundleIdsState.loadedValue ?? [], kind: .bundleIds) {
            [$0.name, $0.identifier, $0.platform]
        }
    }

    var filteredProfiles: [ProfileModel] {
        filter(profilesState.loadedValue ?? [], kind: .profiles) {
            [$0.name, $0.uuid, $0.profileType, $0.profileState, $0.platform]
        }
    }

    var filteredUsers: [UserModel] {
        filter(usersState.loadedValue ?? [], kind: .users) {
            // Roles render as chips — searchable as one joined string.
            [$0.username, $0.firstName, $0.lastName, ($0.roles ?? []).joined(separator: " ")]
        }
    }

    /// Row count after filtering, without the view needing to know which
    /// array backs the current kind (drives the header's "N of M").
    func filteredCount(for kind: Kind) -> Int {
        switch kind {
        case .devices: return filteredDevices.count
        case .certificates: return filteredCertificates.count
        case .bundleIds: return filteredBundleIds.count
        case .profiles: return filteredProfiles.count
        case .users: return filteredUsers.count
        }
    }

    /// Rows actually loaded so far — search is local, so matches can't
    /// exceed this even when the server reports a larger total.
    func loadedCount(for kind: Kind) -> Int {
        switch kind {
        case .devices: return devicesState.loadedValue?.count ?? 0
        case .certificates: return certificatesState.loadedValue?.count ?? 0
        case .bundleIds: return bundleIdsState.loadedValue?.count ?? 0
        case .profiles: return profilesState.loadedValue?.count ?? 0
        case .users: return usersState.loadedValue?.count ?? 0
        }
    }

    // MARK: - Loading

    /// Loads a kind's first page once per team session; the Refresh
    /// button refetches via retry(_:).
    func load(_ kind: Kind) {
        if loadedKinds.contains(kind) { return }
        fetchTasks[kind]?.cancel()
        fetchTasks[kind] = Task { await fetch(kind) }
    }

    func retry(_ kind: Kind) {
        fetchTasks[kind]?.cancel()
        fetchTasks[kind] = Task { await fetch(kind) }
    }

    func loadMore(_ kind: Kind, cursor: String) {
        // In-flight check BEFORE cancelling: the successor task starts
        // before the cancelled predecessor runs its defer, so the internal
        // guard would no-op the tap while leaving the first request killed.
        guard !cursor.isEmpty, !isPaginatingKinds.contains(kind) else { return }
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
        if paginating, isPaginatingKinds.contains(kind) { return }
        if paginating {
            isPaginatingKinds.insert(kind)
        } else {
            setLoading(for: kind)
        }
        paginationFailedKinds.remove(kind)
        defer {
            if paginating { self.isPaginatingKinds.remove(kind) }
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
                paginationFailedKinds.insert(kind)
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
            nextCursors[kind] = model.meta.paging.nextCursor
            totals[kind] = model.meta.paging.total
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
        // Staleness only on success: a failed load must NOT mark the kind
        // loaded, or reopening the list would never auto-retry the error.
        loadedKinds.insert(kind)
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
        paginationFailedKinds = []
        searchTexts = [:]
        isPaginatingKinds = []
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
