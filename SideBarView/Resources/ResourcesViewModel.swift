//
//  ResourcesViewModel.swift
//  App Store
//
//  Batch C2: team-scoped resources (read-only) — Devices, Certificates,
//  Bundle IDs, Profiles, Users. Follows the BetaViewModel pattern:
//  ViewState per list, in-flight task cancellation, cursor pagination
//  with retry, friendly 403 hint (these endpoints need an API key with
//  broader permissions than TestFlight-only).
//
//  Batch G (#10): device register/enable/disable + certificate
//  create/revoke (Admin key role required).
//
//  Batch F (#6): per-kind search text + local, case-insensitive filtering
//  across each model's display fields (search is local — server-side
//  search params aren't supported on these endpoints).
//
//  Batch F review fixes: filter results memoized per kind (the view runs
//  the pipeline 2–3× per body evaluation), hasActiveSearch(for:) label
//  aligned with its siblings, and matching switched to
//  localizedStandardContains (Finder-style: diacritics-insensitive,
//  number-aware, per user locale).
//

import SwiftUI
import JSONAPI
import OSLog
import Security
import UniformTypeIdentifiers

private let resourcesLogger = Logger(subsystem: "com.appstore.release-notes", category: "Resources")

@MainActor
final class ResourcesViewModel: ObservableObject {
    deinit {
        // A stuck network call must not keep the VM alive.
        for task in fetchTasks.values { task.cancel() }
        invitationsFetchTask?.cancel()
        dependentsTask?.cancel()
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
            case .devices: return .devices
            case .certificates: return .certificates
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
    /// kind never swallows another kind's Load-more tap. Published so the
    /// footer can render the auto-drain progress (users kind).
    @Published private(set) var isPaginatingKinds: Set<Kind> = []

    // MARK: - Writes (Batch G #10)

    /// Outcome of a provisioning write, so callers can tell "saved" apart
    /// from "ignored" (already in flight / task cancelled) — an ignored
    /// write must leave the form open, not close it like a success.
    enum WriteResult {
        case success
        case failure(String)
        case ignored
    }

    /// In-flight write keys: device/certificate ids for row actions plus
    /// one key per create form — per-item so saving one row never blocks
    /// another (same rule as DetailViewModel.updatingSaveKeys).
    @Published private(set) var writeInFlight: Set<String> = []

    /// Create-form write keys (never collide with resource ids).
    static let registerDeviceKey = "register-device"
    static let createCertificateKey = "create-certificate"
    static let createBundleIdKey = "create-bundle-id"
    static let inviteUserKey = "invite-user"
    static let createProfileKey = "create-profile"

    // MARK: - Pending invitations (Batch I follow-up)
    //
    // Pending invites live in /userInvitations, not /users — without this
    // list an unaccepted invitee is invisible until they accept.

    /// Pending team invitations. Single page (limit 200): pending invites
    /// are a handful, and paging them is out of scope.
    @Published var invitationsState: ViewState<[UserInvitationModel]> = .idle
    private var invitationsFetchTask: Task<Void, Never>?

    /// Last successfully loaded rows, retained across failures so the
    /// Users error state can show the stale cache with editing disabled
    /// (Figma 114-13286) instead of a bare error. Cleared on team switch.
    private(set) var lastLoadedUsers: [UserModel] = []
    private(set) var lastLoadedInvitations: [UserInvitationModel] = []

    func isWriteInFlight(_ key: String) -> Bool { writeInFlight.contains(key) }

    // MARK: - Search (Batch F #6)

    /// Bumped on every mutation of the loaded arrays (fetch completion,
    /// team reset) — validates the per-kind filter caches below so a
    /// (query + version) match guarantees a current result (review fix).
    private var dataVersion = 0

    /// Per-kind filter cache: body evaluation runs the pipeline 2–3×
    /// (rows + header count + no-matches check) and any unrelated
    /// @Published change re-renders too — with many loaded pages that
    /// is real work per keystroke. Empty queries bypass the cache and
    /// return the source array untouched.
    private struct FilterCache<T> {
        var query = ""
        var version = -1
        var results: [T] = []
    }

    private var devicesFilterCache = FilterCache<DeviceModel>()
    private var certificatesFilterCache = FilterCache<CertificateModel>()
    private var bundleIdsFilterCache = FilterCache<BundleIdModel>()
    private var profilesFilterCache = FilterCache<ProfileModel>()
    private var usersFilterCache = FilterCache<UserModel>()
    private var invitationsFilterCache = FilterCache<UserInvitationModel>()

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
    /// Label matches searchText(for:)/filteredCount(for:)/loadedCount(for:)
    /// (review fix).
    func hasActiveSearch(for kind: Kind) -> Bool { !query(for: kind).isEmpty }

    /// Cached local match across the fields each kind's row displays —
    /// searching must surface a device whose UDID matches even when its
    /// name doesn't. localizedStandardContains: Finder-style matching
    /// (diacritics-insensitive, number-aware, per user locale).
    private func cachedFilter<T>(
        _ cache: inout FilterCache<T>,
        kind: Kind,
        source: [T],
        fields: (T) -> [String?]
    ) -> [T] {
        let active = query(for: kind)
        guard !active.isEmpty else { return source }
        if cache.version == dataVersion, cache.query == active {
            return cache.results
        }
        let results = source.filter { item in
            fields(item).contains { $0?.localizedStandardContains(active) == true }
        }
        cache = FilterCache(query: active, version: dataVersion, results: results)
        return results
    }

    var filteredDevices: [DeviceModel] {
        cachedFilter(&devicesFilterCache, kind: .devices, source: devicesState.loadedValue ?? []) {
            [$0.name, $0.model, $0.udid, $0.deviceClass, $0.platform, $0.status]
        }
    }

    var filteredCertificates: [CertificateModel] {
        cachedFilter(&certificatesFilterCache, kind: .certificates, source: certificatesState.loadedValue ?? []) {
            // The row shows displayName with name as fallback — match both.
            [$0.displayName, $0.name, $0.serialNumber, $0.certificateType, $0.platform]
        }
    }

    var filteredBundleIds: [BundleIdModel] {
        cachedFilter(&bundleIdsFilterCache, kind: .bundleIds, source: bundleIdsState.loadedValue ?? []) {
            [$0.name, $0.identifier, $0.platform]
        }
    }

    var filteredProfiles: [ProfileModel] {
        cachedFilter(&profilesFilterCache, kind: .profiles, source: profilesState.loadedValue ?? []) {
            [$0.name, $0.uuid, $0.profileType, $0.profileState, $0.platform,
             $0.bundleId.flatMap(\.identifier), $0.bundleId.flatMap(\.name)]
        }
    }

    var filteredUsers: [UserModel] {
        cachedFilter(&usersFilterCache, kind: .users, source: usersState.loadedValue ?? []) {
            // Roles render as chips — searchable as one joined string.
            [$0.username, $0.firstName, $0.lastName, ($0.roles ?? []).joined(separator: " ")]
        }
    }

    /// Pending invites share the users search box (same kind query) so a
    /// typed email matches members and invitees together.
    var filteredInvitations: [UserInvitationModel] {
        cachedFilter(&invitationsFilterCache, kind: .users, source: invitationsState.loadedValue ?? []) {
            [$0.email, $0.firstName, $0.lastName, ($0.roles ?? []).joined(separator: " ")]
        }
    }

    /// Pending list order (Figma 114-4654 "Sort: Date sent"). The API
    /// exposes no sent-date on invitations — expirationDate is the closest
    /// proxy (fixed lifetime, so ordering matches). Newest first, undated
    /// rows last.
    var pendingInvitationsByRecency: [UserInvitationModel] {
        filteredInvitations.sorted {
            switch ($0.expirationDate, $1.expirationDate) {
            case let (lhs?, rhs?): return lhs > rhs
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return ($0.email ?? "") < ($1.email ?? "")
            }
        }
    }

    /// App-scope label shared by the users table, pending list, detail
    /// summaries and sheets ("All Apps" vs "Orbit, Atlas"). Empty names
    /// with a scoped flag means the linkage didn't hydrate — say so
    /// instead of showing a blank.
    nonisolated static func appScopeLabel(allAppsVisible: Bool?, visibleAppNames: [String]) -> String {
        if allAppsVisible ?? true { return "All Apps" }
        let names = visibleAppNames.filter { !$0.isEmpty }
        if names.isEmpty { return "Selected apps" }
        return names.joined(separator: ", ")
    }

    /// Row count after filtering, without the view needing to know which
    /// array backs the current kind (drives the header's "N of M").
    /// Users includes pending invitations (same list, same search box).
    func filteredCount(for kind: Kind) -> Int {
        switch kind {
        case .devices: return filteredDevices.count
        case .certificates: return filteredCertificates.count
        case .bundleIds: return filteredBundleIds.count
        case .profiles: return filteredProfiles.count
        case .users: return filteredUsers.count + filteredInvitations.count
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
        case .users: return (usersState.loadedValue?.count ?? 0) + (invitationsState.loadedValue?.count ?? 0)
        }
    }

    // MARK: - Loading

    /// Loads a kind's first page once per team session; the Refresh
    /// button refetches via retry(_:). Users drain ALL pages up front so
    /// local search covers the whole team (a match on an unloaded page
    /// would otherwise never surface).
    func load(_ kind: Kind) {
        if loadedKinds.contains(kind) { return }
        if kind == .users {
            loadAllPages(kind)
        } else {
            fetchTasks[kind]?.cancel()
            fetchTasks[kind] = Task { await fetch(kind) }
        }
    }

    func retry(_ kind: Kind) {
        if kind == .users {
            loadAllPages(kind)
            return
        }
        fetchTasks[kind]?.cancel()
        fetchTasks[kind] = Task { await fetch(kind) }
    }

    func loadMore(_ kind: Kind, cursor: String) {
        // In-flight check BEFORE cancelling: the successor task starts
        // before the cancelled predecessor runs its defer, so the internal
        // guard would no-op the tap while leaving the first request killed.
        guard !cursor.isEmpty, !isPaginatingKinds.contains(kind) else { return }
        // Users auto-drain: footer taps resume the drain from the current
        // cursor instead of appending a single page.
        if kind == .users {
            loadAllPages(kind)
            return
        }
        fetchTasks[kind]?.cancel()
        fetchTasks[kind] = Task { await fetch(kind, cursor: cursor) }
    }

    /// Fetches every page for a kind, one after another. Sequential awaits
    /// keep cursor epochs safe (no overlapping page requests) and each
    /// fetch() carries its own cancellation/merge guards. Cancelling the
    /// task stops the drain at a page boundary — the loaded rows stay.
    func loadAllPages(_ kind: Kind) {
        // A fresh drain owns its failure flag: a previous page failure
        // must not wedge the loop below before its first fetch runs
        // (each fetch re-arms the flag on failure).
        paginationFailedKinds.remove(kind)
        fetchTasks[kind]?.cancel()
        fetchTasks[kind] = Task { await drainPages(kind) }
    }

    private func drainPages(_ kind: Kind) async {
        if !loadedKinds.contains(kind) {
            await fetch(kind)
        }
        // Stops on: last page (cursor nil), page failure (flag set —
        // footer offers Retry, which resumes via loadMore), cancellation.
        while let cursor = nextCursors[kind],
              !paginationFailedKinds.contains(kind),
              !Task.isCancelled {
            await fetch(kind, cursor: cursor)
        }
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
        if kind == .users {
            // Hydrate app-scope names (table "App scope" column, edit-user
            // chooser, resend recap). spec: include=visibleApps is valid
            // on GET /v1/users; links-only linkage decodes to [].
            queryParams["include"] = "visibleApps"
        }
        if kind == .profiles {
            // Hydrate bundle names for the Bundle ID column (Figma 3-5273)
            // and the profile detail inspector. spec: include=bundleId.
            queryParams["include"] = "bundleId"
        }

        guard let request = APIClient.shared.getRequest(
            api: .get(name: kind.apiName, queryParams: queryParams), apiVersion: .v1) else {
            if !paginating {
                nextCursors[kind] = nil
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
                // A failed first page invalidates any cursor from an older
                // query epoch — the drain loop must not chase it.
                nextCursors[kind] = nil
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
            lastLoadedUsers = merged
        }
        // Staleness only on success: a failed load must NOT mark the kind
        // loaded, or reopening the list would never auto-retry the error.
        loadedKinds.insert(kind)
        // Successful fetch — stamps Figma's "Last synced …" action bars.
        lastSyncDates[kind] = Date()
        // Loaded arrays changed — invalidate filter caches (review fix).
        dataVersion += 1
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
        invitationsFetchTask?.cancel()
        invitationsFetchTask = nil
        invitationsState = .idle
        lastLoadedUsers = []
        lastLoadedInvitations = []
        dependentsTask?.cancel()
        dependentsTask = nil
        dependentsCache = [:]
        dependentProfilesState = .idle
        importProgress = nil
        loadedKinds = []
        devicesState = .idle
        certificatesState = .idle
        bundleIdsState = .idle
        profilesState = .idle
        usersState = .idle
        nextCursors = [:]
        totals = [:]
        lastSyncDates = [:]
        paginationFailedKinds = []
        searchTexts = [:]
        isPaginatingKinds = []
        // Loaded arrays changed — invalidate filter caches (review fix).
        dataVersion += 1
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
            return FriendlyErrorMessage.message(for: error)
        }
        return FriendlyErrorMessage.message(for: error)
    }

    // MARK: - Writes (Batch G #10)
    //
    // All four methods return a WriteResult: .success saved, .failure the
    // inline error message (forms/rows stay put so typed input is never
    // silently discarded — same contract as review replies), .ignored when
    // a duplicate write is already in flight or the task was cancelled
    // (the form must stay open in that case too, not close like a success).
    // Provisioning writes need an Admin/Account Holder key role — a
    // TestFlight-only key 403s, hence the write-specific hint below.

    /// POST /v1/devices — register a device. On success the search filter
    /// is cleared (a filter could otherwise hide the new row) and the row
    /// is prepended to the loaded list; server sort order returns on the
    /// next refresh.
    func registerDevice(name: String, platform: DevicePlatform, udid: String) async -> WriteResult {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUdid = udid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return .failure("Enter a device name.") }
        guard !trimmedUdid.isEmpty else { return .failure("Enter the device UDID.") }
        guard ProvisioningWriteValidation.isValidUDID(trimmedUdid) else {
            return .failure("That doesn't look like a UDID — expected 40 hex characters, or 8-8-9 hex groups separated by a dash ( Finder → device details, or Xcode → Devices window).")
        }
        guard !isWriteInFlight(Self.registerDeviceKey) else { return .ignored }
        writeInFlight.insert(Self.registerDeviceKey)
        defer { writeInFlight.remove(Self.registerDeviceKey) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(DeviceCreateRequest(
            data: DeviceCreateData(
                attributes: DeviceCreateAttributes(
                    name: trimmedName,
                    platform: platform.rawValue,
                    udid: trimmedUdid
                )
            )
        )), let request = APIClient.shared.getRequest(
            api: .post(name: .devices, body: data),
            apiVersion: .v1) else {
            return .failure("Couldn't build the register request.")
        }

        do {
            let responseData = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .ignored }
            let model = try getDecoder().decode(DeviceModel.self, from: responseData)
            prependDevice(model)
            return .success
        } catch {
            resourcesLogger.error("Failed to register device: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
    }

    /// PATCH /v1/devices/{id} with status ENABLED/DISABLED. There is no
    /// DELETE on devices — disabling is the API's "revoke" (removal is
    /// Apple Developer website only).
    func setDeviceEnabled(_ device: DeviceModel, enabled: Bool) async -> WriteResult {
        guard !isWriteInFlight(device.id) else { return .ignored }
        writeInFlight.insert(device.id)
        defer { writeInFlight.remove(device.id) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(DeviceUpdateRequest(
            data: DeviceUpdateData(
                id: device.id,
                attributes: DeviceUpdateAttributes(
                    name: nil,
                    status: enabled ? "ENABLED" : "DISABLED"
                )
            )
        )), let request = APIClient.shared.getRequest(
            api: .patch(name: .devices, body: data, path: device.id),
            apiVersion: .v1) else {
            return .failure("Couldn't build the device update request.")
        }

        do {
            let responseData = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .ignored }
            let model = try getDecoder().decode(DeviceModel.self, from: responseData)
            // Re-locate after the await: the list may have changed
            // (refresh, pagination) since the toggle started.
            guard case .loaded(var devices) = devicesState,
                  let index = devices.firstIndex(where: { $0.id == device.id }) else { return .ignored }
            devices[index] = model
            devicesState = .loaded(devices)
            dataVersion += 1
            return .success
        } catch {
            resourcesLogger.error("Failed to update device: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
    }

    /// PATCH /v1/devices/{id} with a new name (Figma device detail's Save
    /// Name — Apple docs "Modify a Registered Device": name and status are
    /// both updatable attributes). Passing status nil leaves it untouched.
    /// Same WriteResult contract as setDeviceEnabled.
    func renameDevice(_ device: DeviceModel, to name: String) async -> WriteResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure("Enter a device name.") }
        guard trimmed != (device.name ?? "") else { return .ignored }
        guard !isWriteInFlight(device.id) else { return .ignored }
        writeInFlight.insert(device.id)
        defer { writeInFlight.remove(device.id) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(DeviceUpdateRequest(
            data: DeviceUpdateData(
                id: device.id,
                attributes: DeviceUpdateAttributes(
                    name: trimmed,
                    status: nil
                )
            )
        )), let request = APIClient.shared.getRequest(
            api: .patch(name: .devices, body: data, path: device.id),
            apiVersion: .v1) else {
            return .failure("Couldn't build the rename request.")
        }

        do {
            let responseData = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .ignored }
            let model = try getDecoder().decode(DeviceModel.self, from: responseData)
            guard case .loaded(var devices) = devicesState,
                  let index = devices.firstIndex(where: { $0.id == device.id }) else { return .ignored }
            devices[index] = model
            devicesState = .loaded(devices)
            dataVersion += 1
            return .success
        } catch {
            resourcesLogger.error("Failed to rename device: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
    }

    // MARK: - Dependent profiles (device detail)

    /// Dependent-profiles lookup for one device (Figma 114-3013/3123).
    /// There is no GET /v1/devices/{id}/profiles endpoint (verified in the
    /// OpenAPI spec — devices expose no relationships), so this scans
    /// GET /v1/profiles?include=devices,certificates and matches hydrated
    /// device ids. Caveat: limit[devices]=50 caps the included devices per
    /// profile, so a device past the first 50 on a huge profile is missed
    /// (vendor limitation, surfaced in the UI copy).
    @Published var dependentProfilesState: ViewState<[DependentProfile]> = .idle
    /// Memoized per device id so reopening a detail never refetches; a
    /// device enable/disable/rename invalidates nothing here (membership
    /// only changes via profile edits), but team switch clears it.
    private var dependentsCache: [String: [DependentProfile]] = [:]
    private var dependentsTask: Task<Void, Never>?

    /// Pure matcher, unit-tested: profiles whose hydrated devices contain
    /// the id, paired with their signing-certificate display names.
    /// Nonisolated (pure function of its arguments) so tests and views
    /// can call it off the main actor.
    nonisolated static func dependents(matching deviceId: String, in profiles: [ProfileModel]) -> [DependentProfile] {
        profiles.compactMap { profile in
            guard profile.devices.contains(where: { $0.id == deviceId }) else { return nil }
            let certNames = profile.certificates.map { $0.displayName ?? $0.name ?? "—" }
            return DependentProfile(profile: profile, certificateNames: certNames)
        }
    }

    func loadDependentProfiles(for device: DeviceModel) {
        if let cached = dependentsCache[device.id] {
            dependentProfilesState = cached.isEmpty ? .empty : .loaded(cached)
            return
        }
        dependentsTask?.cancel()
        dependentsTask = Task { await fetchDependentProfiles(for: device) }
    }

    func retryDependentProfiles(for device: DeviceModel) {
        dependentsCache.removeValue(forKey: device.id)
        loadDependentProfiles(for: device)
    }

    private func fetchDependentProfiles(for device: DeviceModel) async {
        guard !Task.isCancelled else { return }
        dependentProfilesState = .loading
        // Fields trimmed to what the table renders; relationships must be
        // named in fields[profiles] or the server drops them. Sort verified
        // against the spec (inventing a sort field 400s the request).
        let baseParams = [
            "include": "devices,certificates",
            "limit": "50",
            "limit[devices]": "50",
            "limit[certificates]": "50",
            "sort": "name",
            "fields[profiles]": "name,profileType,profileState,devices,certificates",
            "fields[devices]": "name",
            "fields[certificates]": "name,displayName",
        ]
        var all: [ProfileModel] = []
        var cursor: String? = nil
        // Profiles are few; the cap stops a runaway drain, not real data.
        for _ in 0..<20 {
            guard !Task.isCancelled else { return }
            var queryParams = baseParams
            if let cursor {
                queryParams["cursor"] = cursor
            }
            guard let request = APIClient.shared.getRequest(
                api: .get(name: .getProfiles, queryParams: queryParams),
                apiVersion: .v1) else {
                dependentProfilesState = .error("No team selected. Add a team to load profiles.")
                return
            }
            do {
                let data = try await APIClient.shared.callAPI(with: request)
                guard !Task.isCancelled else { return }
                let page = try getDecoder().decode(ProfilesDocument.self, from: data)
                all += page.data
                if let next = page.meta.paging.nextCursor, !next.isEmpty {
                    cursor = next
                } else {
                    break
                }
            } catch {
                guard !Task.isCancelled else { return }
                resourcesLogger.error("Failed to load dependent profiles: \(error.localizedDescription)")
                dependentProfilesState = .error(friendlyMessage(for: error))
                return
            }
        }
        let matches = Self.dependents(matching: device.id, in: all)
        dependentsCache[device.id] = matches
        dependentProfilesState = matches.isEmpty ? .empty : .loaded(matches)
    }

    // MARK: - Last sync (device action bars)

    /// Last successful fetch per kind, for Figma's "Last synced …" action
    /// bars. Client-side only — the API exposes no sync timestamps.
    @Published var lastSyncDates: [Kind: Date] = [:]

    private static let syncFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter
    }()

    func lastSyncText(for kind: Kind) -> String? {
        guard let date = lastSyncDates[kind] else { return nil }
        return "Last synced \(Self.syncFormatter.string(from: date))"
    }

    // MARK: - CSV import (devices empty state)

    /// Progress of a running CSV import (done/total), nil when idle.
    /// Published so the import sheet can render a progress bar.
    @Published var importProgress: (done: Int, total: Int)?

    /// Registers parsed CSV rows one POST /v1/devices at a time — there is
    /// no bulk-register endpoint. Sequential awaits keep yearly-limit
    /// failures attributable per row; the loop stops early on task
    /// cancellation. Returns counts + per-row failures for the summary.
    func importDevices(_ rows: [DeviceCSVRow]) async -> DeviceCSVImportResult {
        var registered = 0
        var failures: [DeviceCSVFailure] = []
        importProgress = (done: 0, total: rows.count)
        defer { importProgress = nil }
        for row in rows {
            guard !Task.isCancelled else { break }
            let result = await registerDevice(name: row.name, platform: row.platform, udid: row.udid)
            switch result {
            case .success:
                registered += 1
            case .failure(let message):
                failures.append(DeviceCSVFailure(row: row, message: message))
            case .ignored:
                failures.append(DeviceCSVFailure(row: row, message: "Skipped — another registration was already in flight."))
            }
            importProgress = (done: registered + failures.count, total: rows.count)
        }
        return DeviceCSVImportResult(registered: registered, failures: failures)
    }

    /// POST /v1/certificates — create from a CSR file's content (loaded
    /// via the form's file picker; generating the key pair in-app is out
    /// of scope).
    func createCertificate(certificateType: CertificateTypeOption, csrContent: String) async -> WriteResult {
        let trimmedCSR = csrContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCSR.isEmpty else { return .failure("Select a CSR file first.") }
        guard ProvisioningWriteValidation.isValidCSR(trimmedCSR) else {
            return .failure("That doesn't look like a CSR — expected PEM content with \"-----BEGIN CERTIFICATE REQUEST-----\" and \"-----END CERTIFICATE REQUEST-----\" markers.")
        }
        guard !isWriteInFlight(Self.createCertificateKey) else { return .ignored }
        writeInFlight.insert(Self.createCertificateKey)
        defer { writeInFlight.remove(Self.createCertificateKey) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(CertificateCreateRequest(
            data: CertificateCreateData(
                attributes: CertificateCreateAttributes(
                    csrContent: trimmedCSR,
                    certificateType: certificateType.rawValue
                )
            )
        )), let request = APIClient.shared.getRequest(
            api: .post(name: .certificates, body: data),
            apiVersion: .v1) else {
            return .failure("Couldn't build the certificate request.")
        }

        do {
            let responseData = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .ignored }
            let model = try getDecoder().decode(CertificateModel.self, from: responseData)
            prependCertificate(model)
            return .success
        } catch {
            resourcesLogger.error("Failed to create certificate: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
    }

    /// DELETE /v1/certificates/{id} — revoke. The row is dropped locally on
    /// 204; callers must confirm first (destructive, cannot be undone).
    func revokeCertificate(id: String) async -> WriteResult {
        guard !isWriteInFlight(id) else { return .ignored }
        writeInFlight.insert(id)
        defer { writeInFlight.remove(id) }

        guard let request = APIClient.shared.getRequest(
            api: .delete(name: .certificates, path: id),
            apiVersion: .v1) else {
            return .failure("Couldn't build the revoke request.")
        }

        do {
            _ = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .ignored }
            // Re-locate after the await: the list may have changed.
            guard case .loaded(var certificates) = certificatesState,
                  let index = certificates.firstIndex(where: { $0.id == id }) else { return .ignored }
            certificates.remove(at: index)
            certificatesState = certificates.isEmpty ? .empty : .loaded(certificates)
            if let total = totals[.certificates] {
                totals[.certificates] = max(0, total - 1)
            }
            dataVersion += 1
            return .success
        } catch {
            resourcesLogger.error("Failed to revoke certificate: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
    }

    /// GET /v1/certificates/{id} → attributes.certificateContent (base64
    /// DER) → NSSavePanel → .cer file. List responses never carry the
    /// content, so download always needs this round-trip. Cancellation of
    /// the save panel reports .ignored (nothing failed).
    func downloadCertificate(_ certificate: CertificateModel) async -> WriteResult {
        let key = "download-certificate-\(certificate.id)"
        guard !isWriteInFlight(key) else { return .ignored }
        writeInFlight.insert(key)
        defer { writeInFlight.remove(key) }

        guard let request = APIClient.shared.getRequest(
            api: .get(name: .certificates, path: certificate.id),
            apiVersion: .v1) else {
            return .failure("Couldn't build the download request.")
        }

        do {
            let responseData = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .ignored }
            let model = try getDecoder().decode(CertificateModel.self, from: responseData)
            guard let base64 = model.certificateContent,
                  let fileData = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
                return .failure("Apple didn't return certificate data for this certificate.")
            }
            guard !Task.isCancelled else { return .ignored }
            return saveDownloadedFile(data: fileData,
                                     suggestedName: safeFileName(certificate.displayName ?? certificate.name) + ".cer",
                                     fileExtension: "cer")
        } catch {
            resourcesLogger.error("Failed to download certificate: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
    }

    // MARK: - Bundle ID writes (Batch I, I2)
    //
    // POST /v1/bundleIds (identifier + name + platform required, seedId
    // optional), PATCH /v1/bundleIds/{id} (name only), DELETE
    // /v1/bundleIds/{id}. Same WriteResult contract as the Batch G writes.

    /// POST /v1/bundleIds — register a bundle ID. On success the search
    /// filter is cleared and the row is prepended (same as devices).
    func createBundleId(name: String,
                        identifier: String,
                        platform: BundleIdPlatformOption,
                        seedId: String?) async -> WriteResult {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSeedId = (seedId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return .failure("Enter a name for the bundle ID.") }
        guard !trimmedIdentifier.isEmpty else { return .failure("Enter the bundle identifier (e.g. com.example.app).") }
        guard !isWriteInFlight(Self.createBundleIdKey) else { return .ignored }
        writeInFlight.insert(Self.createBundleIdKey)
        defer { writeInFlight.remove(Self.createBundleIdKey) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(BundleIdCreateRequest(
            data: BundleIdCreateData(
                attributes: BundleIdCreateAttributes(
                    name: trimmedName,
                    identifier: trimmedIdentifier,
                    platform: platform.rawValue,
                    seedId: trimmedSeedId.isEmpty ? nil : trimmedSeedId
                )
            )
        )), let request = APIClient.shared.getRequest(
            api: .post(name: .getBundleIds, body: data),
            apiVersion: .v1) else {
            return .failure("Couldn't build the bundle ID request.")
        }

        do {
            let responseData = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .ignored }
            let model = try getDecoder().decode(BundleIdModel.self, from: responseData)
            prependBundleId(model)
            return .success
        } catch {
            resourcesLogger.error("Failed to create bundle ID: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
    }

    /// PATCH /v1/bundleIds/{id} — rename only (the server exposes no other
    /// updatable attribute).
    func renameBundleId(_ bundleId: BundleIdModel, newName: String) async -> WriteResult {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return .failure("Enter a name for the bundle ID.") }
        guard !isWriteInFlight(bundleId.id) else { return .ignored }
        writeInFlight.insert(bundleId.id)
        defer { writeInFlight.remove(bundleId.id) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(BundleIdUpdateRequest(
            data: BundleIdUpdateData(
                id: bundleId.id,
                attributes: BundleIdUpdateAttributes(name: trimmedName)
            )
        )), let request = APIClient.shared.getRequest(
            api: .patch(name: .getBundleIds, body: data, path: bundleId.id),
            apiVersion: .v1) else {
            return .failure("Couldn't build the rename request.")
        }

        do {
            let responseData = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .ignored }
            let model = try getDecoder().decode(BundleIdModel.self, from: responseData)
            // Re-locate after the await: the list may have changed
            // (refresh, pagination) since the rename started.
            guard case .loaded(var bundleIds) = bundleIdsState,
                  let index = bundleIds.firstIndex(where: { $0.id == bundleId.id }) else { return .ignored }
            bundleIds[index] = model
            bundleIdsState = .loaded(bundleIds)
            dataVersion += 1
            return .success
        } catch {
            resourcesLogger.error("Failed to rename bundle ID: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
    }

    /// DELETE /v1/bundleIds/{id}. The row is dropped locally on 204;
    /// callers must confirm first (destructive, cannot be undone).
    func deleteBundleId(id: String) async -> WriteResult {
        guard !isWriteInFlight(id) else { return .ignored }
        writeInFlight.insert(id)
        defer { writeInFlight.remove(id) }

        guard let request = APIClient.shared.getRequest(
            api: .delete(name: .getBundleIds, path: id),
            apiVersion: .v1) else {
            return .failure("Couldn't build the delete request.")
        }

        do {
            _ = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .ignored }
            // Re-locate after the await: the list may have changed.
            guard case .loaded(var bundleIds) = bundleIdsState,
                  let index = bundleIds.firstIndex(where: { $0.id == id }) else { return .ignored }
            bundleIds.remove(at: index)
            bundleIdsState = bundleIds.isEmpty ? .empty : .loaded(bundleIds)
            if let total = totals[.bundleIds] {
                totals[.bundleIds] = max(0, total - 1)
            }
            dataVersion += 1
            return .success
        } catch {
            resourcesLogger.error("Failed to delete bundle ID: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
    }

    // MARK: - User + invitation writes (Batch I, I3)
    //
    // POST /v1/userInvitations (invite), PATCH /v1/users/{id} (roles +
    // app scope + provisioning), DELETE /v1/users/{id} (remove),
    // resend = DELETE /v1/userInvitations/{id} → re-POST identical (no
    // dedicated resend endpoint exists). Same WriteResult contract as above.
    // Removing users needs an Admin key — a TestFlight-only key 403s,
    // hence the write-specific hint.

    /// POST /v1/userInvitations — invite a team member. Success carries no
    /// local list mutation: pending invitees don't appear in /users until
    /// they accept, so there is no row to prepend. Pass app ids to scope
    /// a single-app invite (allAppsVisible == false); empty = all apps.
    func inviteUser(email: String,
                    firstName: String,
                    lastName: String,
                    roles: Set<UserRoleOption>,
                    allAppsVisible: Bool,
                    provisioningAllowed: Bool,
                    visibleAppIds: [String] = []) async -> WriteResult {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, trimmedEmail.contains("@") else {
            return .failure("Enter a valid email address.")
        }
        guard !trimmedFirst.isEmpty else { return .failure("Enter the invitee's first name.") }
        guard !trimmedLast.isEmpty else { return .failure("Enter the invitee's last name.") }
        guard !roles.isEmpty else { return .failure("Pick at least one role.") }
        if !allAppsVisible, visibleAppIds.isEmpty {
            return .failure("Pick at least one app this user can access, or turn on \"All apps visible\".")
        }
        guard !isWriteInFlight(Self.inviteUserKey) else { return .ignored }
        writeInFlight.insert(Self.inviteUserKey)
        defer { writeInFlight.remove(Self.inviteUserKey) }

        guard let request = invitationCreateRequest(
            email: trimmedEmail,
            firstName: trimmedFirst,
            lastName: trimmedLast,
            roles: roles.map(\.rawValue),
            allAppsVisible: allAppsVisible,
            provisioningAllowed: provisioningAllowed,
            visibleAppIds: visibleAppIds) else {
            return .failure("Couldn't build the invite request.")
        }

        do {
            _ = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .ignored }
            loadInvitations()
            return .success
        } catch {
            resourcesLogger.error("Failed to invite user: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
    }

    /// Resend an invitation: delete the pending invite and re-create it
    /// with identical details. Roles pass through as raw strings so a
    /// role this client doesn't recognize is preserved verbatim instead
    /// of being silently dropped. Scoped invites reuse the hydrated
    /// visibleApps ids (fetches use include=visibleApps); when the
    /// linkage didn't hydrate the resend is blocked — recreating without
    /// app ids would silently mis-scope the invite, so revoke + send a
    /// new invite with the app picker instead.
    func resendInvitation(_ invitation: UserInvitationModel) async -> WriteResult {
        let trimmedEmail = (invitation.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, trimmedEmail.contains("@") else {
            return .failure("Enter a valid email address.")
        }
        let roles = invitation.roles ?? []
        guard !roles.isEmpty else { return .failure("The invitation has no roles to re-create.") }
        let allAppsVisible = invitation.allAppsVisible ?? true
        let visibleAppIds = invitation.visibleApps.map(\.id)
        if !allAppsVisible, visibleAppIds.isEmpty {
            return .failure("This invite is scoped to specific apps that couldn't be loaded. Revoke it and send a new invite with the app picker instead.")
        }
        let resendKey = "resend-invitation-\(invitation.id)"
        guard !isWriteInFlight(resendKey) else { return .ignored }
        writeInFlight.insert(resendKey)
        defer { writeInFlight.remove(resendKey) }

        do {
            guard let deleteRequest = APIClient.shared.getRequest(
                api: .delete(name: .userInvitations, path: invitation.id),
                apiVersion: .v1) else {
                return .failure("Couldn't build the resend request.")
            }
            _ = try await APIClient.shared.callAPI(with: deleteRequest)
            guard !Task.isCancelled else { return .ignored }
            var inviteRevoked = true
            defer {
                // The delete already happened — the list must reflect
                // reality no matter how the re-create goes.
                if inviteRevoked { loadInvitations() }
            }
            guard let createRequest = invitationCreateRequest(
                email: trimmedEmail,
                firstName: (invitation.firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                lastName: (invitation.lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                roles: roles,
                allAppsVisible: allAppsVisible,
                provisioningAllowed: invitation.provisioningAllowed ?? false,
                visibleAppIds: visibleAppIds) else {
                return .failure("The old invite was revoked, but the new one couldn't be built — send a fresh invite.")
            }
            do {
                _ = try await APIClient.shared.callAPI(with: createRequest)
            } catch {
                guard !Task.isCancelled else { return .ignored }
                resourcesLogger.error("Failed to re-create invitation: \(error.localizedDescription)")
                return .failure("\(writeErrorMessage(for: error)) The previous invite was revoked — send a fresh invite.")
            }
            guard !Task.isCancelled else { return .ignored }
            inviteRevoked = false
            loadInvitations()
            return .success
        } catch {
            resourcesLogger.error("Failed to resend invitation: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
    }

    /// GET /v1/userInvitations?filter[email]=… — the pending invite id for
    /// an email, or nil when none is pending. Ephemeral lookup: no list
    /// state, the caller owns what happens next.
    func loadInvitations() {
        invitationsFetchTask?.cancel()
        invitationsFetchTask = Task { await fetchInvitations() }
    }

    private func fetchInvitations() async {
        guard !Task.isCancelled else { return }
        invitationsState = .loading

        guard let request = APIClient.shared.getRequest(
            api: .get(name: .userInvitations,
                      queryParams: ["sort": "email", "limit": "200", "include": "visibleApps"]),
            apiVersion: .v1) else {
            invitationsState = .error("No team selected. Add a team to load invitations.")
            return
        }

        do {
            let data = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return }
            let model = try getDecoder().decode(UserInvitationsDocument.self, from: data)
            invitationsState = model.data.isEmpty ? .empty : .loaded(model.data)
            lastLoadedInvitations = model.data
            // Loaded rows changed — invalidate the shared users filter cache.
            dataVersion += 1
        } catch {
            guard !Task.isCancelled else { return }
            resourcesLogger.error("Failed to load invitations: \(error.localizedDescription)")
            invitationsState = .error(friendlyMessage(for: error))
        }
    }

    /// DELETE /v1/userInvitations/{id} — revoke a pending invite. The row
    /// is dropped locally on 204; callers must confirm first.
    func revokeInvitation(id: String) async -> WriteResult {
        guard !isWriteInFlight(id) else { return .ignored }
        writeInFlight.insert(id)
        defer { writeInFlight.remove(id) }

        guard let request = APIClient.shared.getRequest(
            api: .delete(name: .userInvitations, path: id),
            apiVersion: .v1) else {
            return .failure("Couldn't build the revoke request.")
        }

        do {
            _ = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .ignored }
            guard case .loaded(var invitations) = invitationsState,
                  let index = invitations.firstIndex(where: { $0.id == id }) else { return .ignored }
            invitations.remove(at: index)
            invitationsState = invitations.isEmpty ? .empty : .loaded(invitations)
            lastLoadedInvitations = invitations
            dataVersion += 1
            return .success
        } catch {
            resourcesLogger.error("Failed to revoke invitation: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
    }

    private func invitationCreateRequest(email: String,
                                         firstName: String,
                                         lastName: String,
                                         roles: [String],
                                         allAppsVisible: Bool,
                                         provisioningAllowed: Bool,
                                         visibleAppIds: [String]) -> URLRequest? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Roles pass through as raw strings (deduped, sorted) so callers
        // can preserve role values this client doesn't recognize.
        guard !firstName.isEmpty, !lastName.isEmpty, !roles.isEmpty,
              let data = try? encoder.encode(UserInvitationCreateRequest(
                data: UserInvitationCreateData(
                    attributes: UserInvitationCreateAttributes(
                        email: email,
                        firstName: firstName,
                        lastName: lastName,
                        roles: Array(Set(roles)).sorted(),
                        allAppsVisible: allAppsVisible,
                        provisioningAllowed: provisioningAllowed
                    ),
                    relationships: visibleAppIds.isEmpty ? nil : UserInvitationCreateRelationships(
                        visibleApps: UserInvitationVisibleAppsRelationship(
                            data: visibleAppIds.map { UserInvitationAppRef(id: $0) }
                        )
                    )
                )
              )) else {
            return nil
        }
        return APIClient.shared.getRequest(
            api: .post(name: .userInvitations, body: data),
            apiVersion: .v1)
    }

    /// PATCH /v1/users/{id} — replace roles, app scope and provisioning
    /// access (spec UserUpdateRequest: all three optional + visibleApps
    /// linkage). Roles the client can't parse (a future Apple role) are
    /// preserved verbatim and unioned into the outgoing array — editing
    /// one role must never silently strip another. The PATCH response
    /// carries no hydrated apps, so the row keeps its visibleApps names.
    func updateUser(_ user: UserModel,
                    roles: Set<UserRoleOption>,
                    allAppsVisible: Bool,
                    provisioningAllowed: Bool,
                    visibleAppIds: [String] = []) async -> WriteResult {
        guard !roles.isEmpty else { return .failure("Pick at least one role.") }
        if !allAppsVisible, visibleAppIds.isEmpty {
            return .failure("Pick at least one app this user can access, or turn on \"All apps visible\".")
        }
        guard !isWriteInFlight(user.id) else { return .ignored }
        writeInFlight.insert(user.id)
        defer { writeInFlight.remove(user.id) }

        let knownRoles = Set(roles.map(\.rawValue))
        // Unrecognized raw roles ride along untouched.
        let outgoingRoles = Array(knownRoles.union((user.roles ?? []).filter { !knownRoles.contains($0) })).sorted()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(UserUpdateRequest(
            data: UserUpdateData(
                id: user.id,
                attributes: UserUpdateAttributes(
                    roles: outgoingRoles,
                    allAppsVisible: allAppsVisible,
                    provisioningAllowed: provisioningAllowed
                ),
                relationships: allAppsVisible ? nil : UserUpdateRelationships(
                    visibleApps: UserInvitationVisibleAppsRelationship(
                        data: visibleAppIds.map { UserInvitationAppRef(id: $0) }
                    )
                )
            )
        )), let request = APIClient.shared.getRequest(
            api: .patch(name: .getUsers, body: data, path: user.id),
            apiVersion: .v1) else {
            return .failure("Couldn't build the user update request.")
        }

        do {
            let responseData = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .ignored }
            var model = try getDecoder().decode(UserModel.self, from: responseData)
            // The PATCH response has no hydrated apps — keep the row's.
            model.visibleApps = user.visibleApps
            // Re-locate after the await: the list may have changed
            // (refresh, pagination) since the edit started.
            guard case .loaded(var users) = usersState,
                  let index = users.firstIndex(where: { $0.id == user.id }) else { return .ignored }
            users[index] = model
            usersState = .loaded(users)
            lastLoadedUsers = users
            dataVersion += 1
            return .success
        } catch {
            resourcesLogger.error("Failed to update user: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
    }

    /// DELETE /v1/users/{id} — remove a team member. The row is dropped
    /// locally on 204; callers must confirm first (destructive). May 403
    /// on a non-Admin key — the permissions hint surfaces, not a raw error.
    func removeUser(id: String) async -> WriteResult {
        guard !isWriteInFlight(id) else { return .ignored }
        writeInFlight.insert(id)
        defer { writeInFlight.remove(id) }

        guard let request = APIClient.shared.getRequest(
            api: .delete(name: .getUsers, path: id),
            apiVersion: .v1) else {
            return .failure("Couldn't build the remove request.")
        }

        do {
            _ = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .ignored }
            // Re-locate after the await: the list may have changed.
            guard case .loaded(var users) = usersState,
                  let index = users.firstIndex(where: { $0.id == id }) else { return .ignored }
            users.remove(at: index)
            usersState = users.isEmpty ? .empty : .loaded(users)
            lastLoadedUsers = users
            if let total = totals[.users] {
                totals[.users] = max(0, total - 1)
            }
            dataVersion += 1
            return .success
        } catch {
            resourcesLogger.error("Failed to remove user: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
    }

    // MARK: - Provisioning profile writes (Batch I, I4)
    //
    // POST /v1/profiles (name + profileType + bundleId/certificates/devices
    // relationships), DELETE /v1/profiles/{id}. Same WriteResult contract
    // as above. Pickers read the already-loaded devices/certificates/
    // bundleIds lists — no new fetch paths.

    /// POST /v1/profiles — create a provisioning profile. Certificates are
    /// required server-side; devices are required server-side only for
    /// development/adhoc types (omitted from the body when empty).
    func createProfile(name: String,
                       profileType: ProfileTypeOption,
                       bundleIdId: String?,
                       certificateIds: Set<String>,
                       deviceIds: Set<String>) async -> WriteResult {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return .failure("Enter a name for the profile.") }
        guard let bundleIdId, !bundleIdId.isEmpty else {
            return .failure("Pick the bundle ID this profile is for.")
        }
        guard !certificateIds.isEmpty else { return .failure("Pick at least one certificate.") }
        guard !isWriteInFlight(Self.createProfileKey) else { return .ignored }
        writeInFlight.insert(Self.createProfileKey)
        defer { writeInFlight.remove(Self.createProfileKey) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(ProfileCreateRequest(
            data: ProfileCreateData(
                attributes: ProfileCreateAttributes(
                    name: trimmedName,
                    profileType: profileType.rawValue
                ),
                relationships: ProfileCreateRelationships(
                    bundleId: ProfileCreateSingleRelationship(
                        data: ProfileCreateRef(type: "bundleIds", id: bundleIdId)
                    ),
                    certificates: ProfileCreateArrayRelationship(
                        data: certificateIds.sorted().map { ProfileCreateRef(type: "certificates", id: $0) }
                    ),
                    // Store/in-house/direct profiles reject devices (409) —
                    // only development and ad-hoc types embed them.
                    devices: profileType.allowsDevices && !deviceIds.isEmpty ? ProfileCreateArrayRelationship(
                        data: deviceIds.sorted().map { ProfileCreateRef(type: "devices", id: $0) }
                    ) : nil
                )
            )
        )), let request = APIClient.shared.getRequest(
            api: .post(name: .getProfiles, body: data),
            apiVersion: .v1) else {
            return .failure("Couldn't build the profile request.")
        }

        do {
            let responseData = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .ignored }
            let model = try getDecoder().decode(ProfileModel.self, from: responseData)
            prependProfile(model)
            return .success
        } catch {
            resourcesLogger.error("Failed to create profile: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
    }

    /// DELETE /v1/profiles/{id}. The row is dropped locally on 204;
    /// callers must confirm first (destructive, cannot be undone).
    func deleteProfile(id: String) async -> WriteResult {
        guard !isWriteInFlight(id) else { return .ignored }
        writeInFlight.insert(id)
        defer { writeInFlight.remove(id) }

        guard let request = APIClient.shared.getRequest(
            api: .delete(name: .getProfiles, path: id),
            apiVersion: .v1) else {
            return .failure("Couldn't build the delete request.")
        }

        do {
            _ = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .ignored }
            // Re-locate after the await: the list may have changed.
            dropProfileLocally(id: id)
            guard case .loaded = profilesState else { return .ignored }
            return .success
        } catch {
            resourcesLogger.error("Failed to delete profile: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
    }

    /// GET /v1/profiles/{id} → attributes.profileContent (base64
    /// .mobileprovision) → NSSavePanel. Same contract as
    /// downloadCertificate: save-panel cancel reports .ignored.
    func downloadProfile(_ profile: ProfileModel) async -> WriteResult {
        let key = "download-profile-\(profile.id)"
        guard !isWriteInFlight(key) else { return .ignored }
        writeInFlight.insert(key)
        defer { writeInFlight.remove(key) }

        guard APIClient.shared.getRequest(
            api: .get(name: .getProfiles, path: profile.id),
            apiVersion: .v1) != nil else {
            return .failure("Couldn't build the download request.")
        }

        do {
            guard let (fileData, fileName) = try await profileFileData(profile) else {
                return .failure("Apple didn't return profile data for this profile.")
            }
            guard !Task.isCancelled else { return .ignored }
            return saveDownloadedFile(data: fileData,
                                      suggestedName: fileName,
                                      fileExtension: "mobileprovision")
        } catch {
            resourcesLogger.error("Failed to download profile: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
    }

    /// GET /v1/profiles/{id}?include=bundleId,certificates,devices —
    /// one fetch hydrating everything the detail inspector shows
    /// (Figma 114-3781). Ephemeral: no list state, the caller owns the
    /// result. Throws user-facing errors via writeErrorMessage wording.
    func fetchProfileDetail(id: String) async throws -> ProfileModel {
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getProfiles,
                      queryParams: ["include": "bundleId,certificates,devices"],
                      path: id),
            apiVersion: .v1) else {
            throw APIError.requestFailed
        }
        let responseData = try await APIClient.shared.callAPI(with: request)
        guard !Task.isCancelled else { throw CancellationError() }
        return try getDecoder().decode(ProfileModel.self, from: responseData)
    }

    /// GET /v1/profiles/{id} → decoded profileContent bytes + file name.
    /// Shared by Download and Install-for-Xcode so both read one path.
    /// Returns nil when Apple sends no profile data (caller reports it).
    func profileFileData(_ profile: ProfileModel) async throws -> (data: Data, fileName: String)? {
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getProfiles, path: profile.id),
            apiVersion: .v1) else {
            throw APIError.requestFailed
        }
        let responseData = try await APIClient.shared.callAPI(with: request)
        guard !Task.isCancelled else { throw CancellationError() }
        let model = try getDecoder().decode(ProfileModel.self, from: responseData)
        guard let base64 = model.profileContent,
              let fileData = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
            return nil
        }
        let fileName = safeFileName(profile.name) + ".mobileprovision"
        return (fileData, fileName)
    }

    /// Regenerate (Figma 114-4103/4164): DELETE the old profile, then POST
    /// a same-type replacement with a new certificate + device set. There
    /// is no update endpoint for profiles — delete-and-recreate is the
    /// only path, and the review sheet says so. Mirrors resendInvitation's
    /// partial-failure handling: when the create fails after the delete,
    /// the message says the old profile is already gone.
    func regenerateProfile(profileId: String,
                           name: String,
                           profileType: ProfileTypeOption,
                           bundleIdId: String,
                           certificateIds: Set<String>,
                           deviceIds: Set<String>) async -> WriteResult {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return .failure("Enter a name for the replacement profile.") }
        guard !certificateIds.isEmpty else { return .failure("Pick at least one certificate.") }
        let key = "regenerate-profile-\(profileId)"
        guard !isWriteInFlight(key) else { return .ignored }
        writeInFlight.insert(key)
        defer { writeInFlight.remove(key) }

        do {
            guard let deleteRequest = APIClient.shared.getRequest(
                api: .delete(name: .getProfiles, path: profileId),
                apiVersion: .v1) else {
                return .failure("Couldn't build the regenerate request.")
            }
            _ = try await APIClient.shared.callAPI(with: deleteRequest)
            guard !Task.isCancelled else { return .ignored }
            dropProfileLocally(id: profileId)

            let createResult = await createProfile(
                name: trimmedName, profileType: profileType, bundleIdId: bundleIdId,
                certificateIds: certificateIds, deviceIds: deviceIds)
            switch createResult {
            case .success:
                return .success
            case .failure(let message):
                return .failure("\(message) The old profile was already deleted — no replacement exists yet.")
            case .ignored:
                return .failure("The old profile was deleted, but the replacement was not created — run the wizard again.")
            }
        } catch {
            resourcesLogger.error("Failed to regenerate profile: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
    }

    /// Drops a row locally without a network call (shared by delete and
    /// regenerate-after-delete).
    private func dropProfileLocally(id: String) {
        guard case .loaded(var profiles) = profilesState,
              let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles.remove(at: index)
        profilesState = profiles.isEmpty ? .empty : .loaded(profiles)
        if let total = totals[.profiles] {
            totals[.profiles] = max(0, total - 1)
        }
        dataVersion += 1
    }

    /// Install-for-Xcode outcome (Figma 114-3716/3746): the result sheet
    /// needs the file name + install location, which WriteResult can't
    /// carry.
    enum ProfileInstallOutcome {
        case success(fileName: String, directory: URL, fileURL: URL)
        case failure(String)
        case ignored
    }

    /// Install for Xcode (Figma 114-3716): fetch the .mobileprovision and
    /// save it via a panel rooted at Xcode's provisioning-profiles
    /// directory (~/Library/MobileDevice/Provisioning Profiles/). A save
    /// panel carries user consent, so this works under the app sandbox —
    /// a silent copy would not. Cancel reports .ignored.
    func installProfileForXcode(_ profile: ProfileModel) async -> ProfileInstallOutcome {
        let key = "install-profile-\(profile.id)"
        guard !isWriteInFlight(key) else { return .ignored }
        writeInFlight.insert(key)
        defer { writeInFlight.remove(key) }

        do {
            guard let (fileData, fileName) = try await profileFileData(profile) else {
                return .failure("Apple didn't return profile data for this profile.")
            }
            guard !Task.isCancelled else { return .ignored }
            let profilesDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/MobileDevice/Provisioning Profiles", isDirectory: true)
            let panel = NSSavePanel()
            panel.directoryURL = profilesDir
            panel.nameFieldStringValue = fileName
            panel.canCreateDirectories = true
            if let fileType = UTType(filenameExtension: "mobileprovision") {
                panel.allowedContentTypes = [fileType]
            }
            panel.message = "Save into Provisioning Profiles so Xcode picks it up automatically."
            guard panel.runModal() == .OK, let url = panel.url else { return .ignored }
            try fileData.write(to: url, options: .atomic)
            return .success(fileName: url.lastPathComponent,
                            directory: url.deletingLastPathComponent(), fileURL: url)
        } catch {
            guard !Task.isCancelled else { return .ignored }
            resourcesLogger.error("Failed to install profile: \(error.localizedDescription)")
            return .failure(writeErrorMessage(for: error))
        }
    }

    /// Local private-key check for the detail's signing-chain inspector
    /// (Figma 114-3781 "7168F2F9 · found locally"): true when the login
    /// keychain holds an identity whose certificate serial matches.
    /// Best-effort — any keychain error reads as "not found", never
    /// thrown, so a locked keychain degrades to honest copy.
    nonisolated static func hasLocalIdentity(serialNumber: String?) -> Bool {
        guard let serial = serialNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
              !serial.isEmpty else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let identities = result as? [SecIdentity] else { return false }
        for identity in identities {
            var cert: SecCertificate?
            guard SecIdentityCopyCertificate(identity, &cert) == errSecSuccess,
                  let cert, let data = SecCertificateCopyData(cert) as Data? else { continue }
            if certificateSerialNumber(der: data).uppercased() == serial.uppercased() { return true }
        }
        return false
    }

    /// DER serial-number parse: INTEGER tag, length, bytes → hex. Returns
    /// "" when the shape is unexpected (caller compares, never crashes).
    nonisolated private static func certificateSerialNumber(der: Data) -> String {
        // First certificate in the chain: outer SEQUENCE, tbsCertificate
        // SEQUENCE, then [0] version (optional), then serial INTEGER.
        var index = der.startIndex
        func readLength() -> Int? {
            guard index < der.endIndex else { return nil }
            let first = Int(der[index]); index = der.index(after: index)
            if first & 0x80 == 0 { return first }
            let count = first & 0x7F
            guard count <= 4 else { return nil }
            var length = 0
            for _ in 0..<count {
                guard index < der.endIndex else { return nil }
                length = (length << 8) | Int(der[index]); index = der.index(after: index)
            }
            return length
        }
        func readTL(expectedTag: UInt8) -> Data? {
            guard index < der.endIndex, der[index] == expectedTag else { return nil }
            index = der.index(after: index)
            guard let length = readLength(), length >= 0,
                  let end = der.index(index, offsetBy: length, limitedBy: der.endIndex) else { return nil }
            defer { index = end }
            return der[index..<end]
        }
        guard let _ = readTL(expectedTag: 0x30),
              let tbs = readTL(expectedTag: 0x30) else { return "" }
        var inner = tbs.startIndex
        // Optional [0] EXPLICIT version wrapper.
        if tbs[inner] == 0xA0 {
            inner = tbs.index(after: inner)
            guard inner < tbs.endIndex else { return "" }
            var len = Int(tbs[inner]); inner = tbs.index(after: inner)
            if len & 0x80 != 0 {
                let count = len & 0x7F
                guard count <= 2 else { return "" }
                len = 0
                for _ in 0..<count {
                    guard inner < tbs.endIndex else { return "" }
                    len = (len << 8) | Int(tbs[inner]); inner = tbs.index(after: inner)
                }
            }
            guard let end = tbs.index(inner, offsetBy: len, limitedBy: tbs.endIndex) else { return "" }
            inner = end
        }
        guard inner < tbs.endIndex, tbs[inner] == 0x02 else { return "" }
        inner = tbs.index(after: inner)
        guard inner < tbs.endIndex else { return "" }
        var serialLen = Int(tbs[inner]); inner = tbs.index(after: inner)
        if serialLen & 0x80 != 0 {
            let count = serialLen & 0x7F
            guard count <= 2 else { return "" }
            serialLen = 0
            for _ in 0..<count {
                guard inner < tbs.endIndex else { return "" }
                serialLen = (serialLen << 8) | Int(tbs[inner]); inner = tbs.index(after: inner)
            }
        }
        guard let end = tbs.index(inner, offsetBy: serialLen, limitedBy: tbs.endIndex) else { return "" }
        var bytes = tbs[inner..<end]
        // Strip leading zero pad (DER pads negatives).
        while bytes.count > 1, bytes.first == 0x00 { bytes = bytes.dropFirst() }
        return bytes.map { String(format: "%02X", $0) }.joined()
    }

    private func prependProfile(_ model: ProfileModel) {
        guard case .loaded(var profiles) = profilesState else {
            retry(.profiles)
            return
        }
        profiles.removeAll { $0.id == model.id }
        profiles.insert(model, at: 0)
        profilesState = .loaded(profiles)
        if let total = totals[.profiles] {
            totals[.profiles] = total + 1
        }
        searchTexts[.profiles] = nil
        dataVersion += 1
    }

    private func prependBundleId(_ model: BundleIdModel) {
        guard case .loaded(var bundleIds) = bundleIdsState else {
            retry(.bundleIds)
            return
        }
        bundleIds.removeAll { $0.id == model.id }
        bundleIds.insert(model, at: 0)
        bundleIdsState = .loaded(bundleIds)
        if let total = totals[.bundleIds] {
            totals[.bundleIds] = total + 1
        }
        searchTexts[.bundleIds] = nil
        dataVersion += 1
    }

    /// Prepends only when the list is loaded — otherwise a failed/idle
    /// list must not be replaced by a one-item ".loaded" list pretending
    /// to be the whole collection; a reload fetches the real first page.
    private func prependDevice(_ model: DeviceModel) {
        guard case .loaded(var devices) = devicesState else {
            // The new row exists server-side now; fetch the real list
            // (retry bypasses the loadedKinds staleness guard).
            retry(.devices)
            return
        }
        devices.removeAll { $0.id == model.id }
        devices.insert(model, at: 0)
        devicesState = .loaded(devices)
        if let total = totals[.devices] {
            totals[.devices] = total + 1
        }
        // A filter (e.g. a UDID search from before registration) could
        // otherwise hide the new row.
        searchTexts[.devices] = nil
        dataVersion += 1
    }

    private func prependCertificate(_ model: CertificateModel) {
        guard case .loaded(var certificates) = certificatesState else {
            retry(.certificates)
            return
        }
        certificates.removeAll { $0.id == model.id }
        certificates.insert(model, at: 0)
        certificatesState = .loaded(certificates)
        if let total = totals[.certificates] {
            totals[.certificates] = total + 1
        }
        searchTexts[.certificates] = nil
        dataVersion += 1
    }

    private func writeErrorMessage(for error: Error) -> String {
        if let apiError = error as? APIError {
            if apiError.statusCode == 403 {
                return "\(apiError.details) — this action needs an API key with the Admin role."
            }
            return apiError.details
        }
        return error.localizedDescription
    }

    /// Filename-safe fallback: blank names become "download", path
    /// separators become dashes so the save panel never escapes.
    private func safeFileName(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "download" }
        return trimmed.replacingOccurrences(of: "/", with: "-")
    }

    /// NSSavePanel + atomic write for downloaded signing files. Must run
    /// on the main actor (all callers are @MainActor-isolated Tasks from
    /// SwiftUI actions, same as the rest of this view model).
    private func saveDownloadedFile(data: Data, suggestedName: String, fileExtension: String) -> WriteResult {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        if let fileType = UTType(filenameExtension: fileExtension) {
            panel.allowedContentTypes = [fileType]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return .ignored }
        do {
            try data.write(to: url, options: .atomic)
            return .success
        } catch {
            return .failure("Couldn't write the file: \(error.localizedDescription)")
        }
    }
}
