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
        for task in certificateRelationshipTasks.values { task.cancel() }
        invitationsFetchTask?.cancel()
        dependentsTask?.cancel()
    }

    // MARK: - Kinds

    enum Kind: String, CaseIterable, Identifiable {
        case devices
        case certificates
        case merchantIds
        case passTypeIds
        case bundleIds
        case profiles
        case users

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .devices: return "Devices"
            case .certificates: return "Certificates"
            case .merchantIds: return "Merchant IDs"
            case .passTypeIds: return "Pass Type IDs"
            case .bundleIds: return "Bundle IDs"
            case .profiles: return "Profiles"
            case .users: return "Users"
            }
        }

        var systemImage: String {
            switch self {
            case .devices: return "iphone"
            case .certificates: return "checkmark.seal"
            case .merchantIds: return "creditcard"
            case .passTypeIds: return "wallet.pass"
            case .bundleIds: return "square.grid.2x2"
            case .profiles: return "person.text.rectangle"
            case .users: return "person.2"
            }
        }

        var subtitle: String {
            switch self {
            case .devices: return "Test devices registered for the team"
            case .certificates: return "Signing certificates"
            case .merchantIds: return "Apple Pay merchant identifiers"
            case .passTypeIds: return "Wallet pass type identifiers"
            case .bundleIds: return "Registered app identifiers"
            case .profiles: return "Provisioning profiles"
            case .users: return "App Store Connect team members"
            }
        }

        var apiName: APIName {
            switch self {
            case .devices: return .devices
            case .certificates: return .certificates
            case .merchantIds: return .merchantIds
            case .passTypeIds: return .passTypeIds
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
            case .merchantIds: return "name"
            case .passTypeIds: return "name"
            case .bundleIds: return "name"
            case .profiles: return "name"
            case .users: return "username"
            }
        }
    }

    // MARK: - State

    @Published var devicesState: ViewState<[DeviceModel]> = .idle
    @Published var certificatesState: ViewState<[CertificateModel]> = .idle
    @Published var merchantIdsState: ViewState<[MerchantIdModel]> = .idle
    @Published var passTypeIdsState: ViewState<[PassTypeIdModel]> = .idle
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
    private var certificateRelationshipTasks: [CertificateCreateRelationshipKind: Task<Void, Never>] = [:]
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

    /// Payload-carrying sibling of `WriteResult` for the two parallel
    /// pre-check fetches behind the delete sheets, where a failure must
    /// keep its message instead of collapsing to a bare `.ignored`.
    enum FetchResult<T> {
        case value(T)
        case failure(String)
    }

    /// Payload-carrying `WriteResult`. Registering a bundle ID has to hand
    /// the created resource back: the confirmation sheet (Figma 114-2284)
    /// reads its identifier type / seed ID and offers "Open Bundle ID".
    enum WriteValueResult<T> {
        case value(T)
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
    static let createMerchantIdKey = "create-merchant-id"
    static let createPassTypeIdKey = "create-pass-type-id"
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
    private var merchantIdsFilterCache = FilterCache<MerchantIdModel>()
    private var passTypeIdsFilterCache = FilterCache<PassTypeIdModel>()
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

    var filteredMerchantIds: [MerchantIdModel] {
        cachedFilter(&merchantIdsFilterCache, kind: .merchantIds, source: merchantIdsState.loadedValue ?? []) {
            [$0.name, $0.identifier]
        }
    }

    var filteredPassTypeIds: [PassTypeIdModel] {
        cachedFilter(&passTypeIdsFilterCache, kind: .passTypeIds, source: passTypeIdsState.loadedValue ?? []) {
            [$0.name, $0.identifier]
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

    func certificateRelationshipOptionsState(for kind: CertificateCreateRelationshipKind) -> ViewState<[CertificateRelationshipOption]> {
        switch kind {
        case .merchantId:
            return mapRelationshipOptions(merchantIdsState) {
                CertificateRelationshipOption(id: $0.id, name: $0.name, identifier: $0.identifier)
            }
        case .passTypeId:
            return mapRelationshipOptions(passTypeIdsState) {
                CertificateRelationshipOption(id: $0.id, name: $0.name, identifier: $0.identifier)
            }
        }
    }

    private func mapRelationshipOptions<T>(
        _ state: ViewState<[T]>,
        transform: (T) -> CertificateRelationshipOption
    ) -> ViewState<[CertificateRelationshipOption]> {
        switch state {
        case .idle: return .idle
        case .loading: return .loading
        case .loaded(let values): return .loaded(values.map(transform))
        case .empty: return .empty
        case .error(let message): return .error(message)
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
        case .merchantIds: return filteredMerchantIds.count
        case .passTypeIds: return filteredPassTypeIds.count
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
        case .merchantIds: return merchantIdsState.loadedValue?.count ?? 0
        case .passTypeIds: return passTypeIdsState.loadedValue?.count ?? 0
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
        case .merchantIds:
            let model = try decoder.decode(MerchantIdsDocument.self, from: data)
            let existing = merchantIdsState.loadedValue ?? []
            let merged = merge(existing: existing, incoming: model.data, isPaginating: isPaginating, id: \.id)
            nextCursors[kind] = model.meta.paging.nextCursor
            totals[kind] = model.meta.paging.total
            merchantIdsState = merged.isEmpty ? .empty : .loaded(merged)
        case .passTypeIds:
            let model = try decoder.decode(PassTypeIdsDocument.self, from: data)
            let existing = passTypeIdsState.loadedValue ?? []
            let merged = merge(existing: existing, incoming: model.data, isPaginating: isPaginating, id: \.id)
            nextCursors[kind] = model.meta.paging.nextCursor
            totals[kind] = model.meta.paging.total
            passTypeIdsState = merged.isEmpty ? .empty : .loaded(merged)
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
    private var teamGeneration = 0

    func resetForTeamSwitch() {
        teamGeneration += 1
        for task in fetchTasks.values { task.cancel() }
        fetchTasks = [:]
        for task in certificateRelationshipTasks.values { task.cancel() }
        certificateRelationshipTasks = [:]
        invitationsFetchTask?.cancel()
        invitationsFetchTask = nil
        invitationsState = .idle
        lastLoadedUsers = []
        lastLoadedInvitations = []
        dependentsTask?.cancel()
        dependentsTask = nil
        dependentsCache = [:]
        dependentProfilesState = .idle
        // Bundle ID detail state belongs to the old team too.
        bundleIdProfilesCache = [:]
        bundleIdCapabilitiesCache = [:]
        bundleIdProfilesState = .idle
        bundleIdCapabilitiesState = .idle
        bundleIdDependenciesState = .idle
        importProgress = nil
        loadedKinds = []
        devicesState = .idle
        certificatesState = .idle
        merchantIdsState = .idle
        passTypeIdsState = .idle
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
        case .merchantIds: merchantIdsState = .loading
        case .passTypeIds: passTypeIdsState = .loading
        case .bundleIds: bundleIdsState = .loading
        case .profiles: profilesState = .loading
        case .users: usersState = .loading
        }
    }

    private func setError(_ message: String, for kind: Kind) {
        switch kind {
        case .devices: devicesState = .error(message)
        case .certificates: certificatesState = .error(message)
        case .merchantIds: merchantIdsState = .error(message)
        case .passTypeIds: passTypeIdsState = .error(message)
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

    func loadCertificateRelationshipOptions(_ kind: CertificateCreateRelationshipKind, force: Bool = false) {
        if !force {
            switch certificateRelationshipOptionsState(for: kind) {
            case .loading, .loaded, .empty:
                return
            case .idle, .error:
                break
            }
        }
        certificateRelationshipTasks[kind]?.cancel()
        setCertificateRelationshipOptionsState(.loading, for: kind)
        certificateRelationshipTasks[kind] = Task { await fetchCertificateRelationshipOptions(kind) }
    }

    private func fetchCertificateRelationshipOptions(_ kind: CertificateCreateRelationshipKind) async {
        defer { certificateRelationshipTasks[kind] = nil }
        guard !Task.isCancelled else { return }

        let queryParams = [
            "limit": "200",
            "sort": "name",
            "fields[\(kind.resourceType)]": "name,identifier"
        ]
        guard let request = APIClient.shared.getRequest(
            api: .get(name: certificateRelationshipAPIName(for: kind), queryParams: queryParams),
            apiVersion: .v1) else {
            setCertificateRelationshipOptionsState(.error("No team selected. Add a team to load \(kind.label.lowercased())."), for: kind)
            return
        }

        do {
            let data = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return }
            let decoder = getDecoder()
            switch kind {
            case .merchantId:
                let model = try decoder.decode(MerchantIdsDocument.self, from: data)
                merchantIdsState = model.data.isEmpty ? .empty : .loaded(model.data)
            case .passTypeId:
                let model = try decoder.decode(PassTypeIdsDocument.self, from: data)
                passTypeIdsState = model.data.isEmpty ? .empty : .loaded(model.data)
            }
        } catch {
            guard !Task.isCancelled else { return }
            resourcesLogger.error("Failed to load \(kind.resourceType): \(error.localizedDescription)")
            setCertificateRelationshipOptionsState(.error(friendlyMessage(for: error)), for: kind)
        }
    }

    private func certificateRelationshipAPIName(for kind: CertificateCreateRelationshipKind) -> APIName {
        switch kind {
        case .merchantId: return .merchantIds
        case .passTypeId: return .passTypeIds
        }
    }

    private func setCertificateRelationshipOptionsState(_ state: ViewState<[Never]>, for kind: CertificateCreateRelationshipKind) {
        switch (kind, state) {
        case (.merchantId, .idle): merchantIdsState = .idle
        case (.merchantId, .loading): merchantIdsState = .loading
        case (.merchantId, .empty): merchantIdsState = .empty
        case (.merchantId, .error(let message)): merchantIdsState = .error(message)
        case (.merchantId, .loaded): merchantIdsState = .empty
        case (.passTypeId, .idle): passTypeIdsState = .idle
        case (.passTypeId, .loading): passTypeIdsState = .loading
        case (.passTypeId, .empty): passTypeIdsState = .empty
        case (.passTypeId, .error(let message)): passTypeIdsState = .error(message)
        case (.passTypeId, .loaded): passTypeIdsState = .empty
        }
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

    func createMerchantId(name: String, identifier: String) async -> WriteValueResult<MerchantIdModel> {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return .failure("Enter a name for the Merchant ID.") }
        guard !trimmedIdentifier.isEmpty else { return .failure("Enter the Merchant ID identifier (for example, merchant.com.example.store).") }
        guard !isWriteInFlight(Self.createMerchantIdKey) else { return .ignored }
        writeInFlight.insert(Self.createMerchantIdKey)
        defer { writeInFlight.remove(Self.createMerchantIdKey) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(MerchantIdCreateRequest(
            data: MerchantIdCreateData(
                attributes: IdentifierCreateAttributes(
                    name: trimmedName,
                    identifier: trimmedIdentifier
                )
            )
        )), let request = APIClient.shared.getRequest(
            api: .post(name: .merchantIds, body: data),
            apiVersion: .v1) else {
            return .failure("Couldn't build the Merchant ID request.")
        }

        do {
            let responseData = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .ignored }
            let model = try getDecoder().decode(MerchantIdModel.self, from: responseData)
            prependMerchantId(model)
            return .value(model)
        } catch {
            resourcesLogger.error("Failed to create Merchant ID: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
    }

    func createPassTypeId(name: String, identifier: String) async -> WriteValueResult<PassTypeIdModel> {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return .failure("Enter a name for the Pass Type ID.") }
        guard !trimmedIdentifier.isEmpty else { return .failure("Enter the Pass Type ID identifier (for example, pass.com.example.loyalty).") }
        guard !isWriteInFlight(Self.createPassTypeIdKey) else { return .ignored }
        writeInFlight.insert(Self.createPassTypeIdKey)
        defer { writeInFlight.remove(Self.createPassTypeIdKey) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(PassTypeIdCreateRequest(
            data: PassTypeIdCreateData(
                attributes: IdentifierCreateAttributes(
                    name: trimmedName,
                    identifier: trimmedIdentifier
                )
            )
        )), let request = APIClient.shared.getRequest(
            api: .post(name: .passTypeIds, body: data),
            apiVersion: .v1) else {
            return .failure("Couldn't build the Pass Type ID request.")
        }

        do {
            let responseData = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .ignored }
            let model = try getDecoder().decode(PassTypeIdModel.self, from: responseData)
            prependPassTypeId(model)
            return .value(model)
        } catch {
            resourcesLogger.error("Failed to create Pass Type ID: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
    }

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
            return .failure("That doesn't look like a UDID — expected 40 hex characters, or 25 characters as 8 + dash + 16 (Finder → device details, or Xcode → Devices window).")
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
    /// of scope). Apple Pay and Pass Type certificates also require a
    /// relationship link to their owning Merchant ID / Pass Type ID.
    func createCertificate(certificateType: CertificateTypeOption,
                           csrContent: String,
                           relatedResourceId: String? = nil) async -> WriteResult {
        guard certificateType.canCreateViaAPI else {
            return .failure("Developer ID certificates must be created on the Apple Developer website or in Xcode.")
        }
        let trimmedCSR = csrContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRelatedResourceId = relatedResourceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedCSR.isEmpty else { return .failure("Select a CSR file first.") }
        guard ProvisioningWriteValidation.isValidCSR(trimmedCSR) else {
            return .failure("That doesn't look like a CSR — expected PEM content with \"-----BEGIN CERTIFICATE REQUEST-----\" and \"-----END CERTIFICATE REQUEST-----\" markers.")
        }
        if let requiredRelationship = certificateType.requiredCreateRelationship,
           trimmedRelatedResourceId.isEmpty {
            return .failure(requiredRelationship.missingMessage)
        }
        guard !isWriteInFlight(Self.createCertificateKey) else { return .ignored }
        writeInFlight.insert(Self.createCertificateKey)
        defer { writeInFlight.remove(Self.createCertificateKey) }

        let relationships: CertificateCreateRelationships?
        switch certificateType.requiredCreateRelationship {
        case .merchantId:
            relationships = CertificateCreateRelationships(
                merchantId: CertificateCreateRelationship(
                    data: CertificateCreateRef(type: "merchantIds", id: trimmedRelatedResourceId)),
                passTypeId: nil)
        case .passTypeId:
            relationships = CertificateCreateRelationships(
                merchantId: nil,
                passTypeId: CertificateCreateRelationship(
                    data: CertificateCreateRef(type: "passTypeIds", id: trimmedRelatedResourceId)))
        case nil:
            relationships = nil
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(CertificateCreateRequest(
            data: CertificateCreateData(
                attributes: CertificateCreateAttributes(
                    csrContent: trimmedCSR,
                    certificateType: certificateType.rawValue
                ),
                relationships: relationships
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

    /// GET /v1/certificates/{id} — detail payload. The list response is
    /// enough for table rows, but the detail response is the only place Apple
    /// includes `certificateContent`, so the inspector verifies that round-trip
    /// without opening the save panel.
    func fetchCertificateDetail(id: String) async -> WriteValueResult<CertificateModel> {
        let key = "certificate-detail-\(id)"
        guard !isWriteInFlight(key) else { return .ignored }
        writeInFlight.insert(key)
        defer { writeInFlight.remove(key) }

        guard let request = APIClient.shared.getRequest(
            api: .get(name: .certificates, path: id),
            apiVersion: .v1) else {
            return .failure("Couldn't build the certificate detail request.")
        }

        do {
            let responseData = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .ignored }
            let model = try getDecoder().decode(CertificateModel.self, from: responseData)
            return .value(model)
        } catch {
            resourcesLogger.error("Failed to load certificate detail: \(error.localizedDescription)")
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
            // Revoking invalidates every profile signed by this certificate,
            // but nothing here touched `profilesState` — and `load(.profiles)`
            // early-returns on `loadedKinds`, so navigating away and back did
            // not refetch either. The Profiles list therefore kept rendering
            // `Active` for a profile Apple had just invalidated, disagreeing
            // with the profile detail screen (which does refetch). Refetch
            // now, and drop the loaded-once latch so a later visit re-reads.
            loadedKinds.remove(.profiles)
            fetchTasks[.profiles]?.cancel()
            fetchTasks[.profiles] = Task { await fetch(.profiles) }
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
    ///
    /// Returns the created resource rather than a bare `.success`: the
    /// register sheet swaps to the "Bundle identifier registered"
    /// confirmation (Figma 114-2284), which reads the identifier type and
    /// seed ID off the response and can deep-link into the new detail.
    func createBundleId(name: String,
                        identifier: String,
                        platform: BundleIdPlatformOption,
                        seedId: String?) async -> WriteValueResult<BundleIdModel> {
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
            return .value(model)
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

    // MARK: - Bundle ID detail (Module 04)
    //
    // Contracts verified against Apple's OpenAPI spec (developer.apple.com
    // sample-code download):
    // - GET /v1/bundleIds/{id}/profiles is a real related-resource route
    //   (devices have none, hence the scan in loadDependentProfiles). It
    //   accepts only limit + fields[profiles] — no `include` — so signing
    //   certificate names are NOT available for bundle-ID dependents.
    // - GET /v1/apps?filter[bundleId]= finds the apps that block a delete.
    //   Apps have no appleId attribute, so dependency rows carry the app
    //   name only (Figma 114-2665 shows an Apple ID we cannot render).
    // - DELETE /v1/bundleIds/{id} documents 204/400/401/403/404/429 —
    //   NO 409. So "blocked by dependencies" (Figma 114-2665) cannot be
    //   detected from the status code and is decided by pre-checking
    //   dependencies; a delete can still 400 if state changed meanwhile,
    //   which is why the unused-sheet copy warns about that.

    /// One row of the delete-blocked dependency table (Figma 114-2665).
    struct BundleIdDependency: Equatable, Identifiable {
        enum Kind: Equatable { case app, profile }

        var kind: Kind
        var name: String
        /// "App association blocks deletion" / "Active profile".
        var reason: String
        /// Target for the row's "Open Profile →" jump; nil for apps,
        /// which jump by name into the Apps list.
        var profileId: String?

        var id: String {
            switch kind {
            case .app: return "app-\(name)"
            case .profile: return "profile-\(profileId ?? name)"
            }
        }

        var jumpLabel: String {
            switch kind {
            case .app: return "Open App →"
            case .profile: return "Open Profile →"
            }
        }
    }

    /// Pure mapper, unit-tested like `dependents(matching:in:)` above.
    nonisolated static func bundleIdDependencies(apps: [AppsData],
                                                  profiles: [ProfileModel]) -> [BundleIdDependency] {
        var rows: [BundleIdDependency] = []
        for app in apps {
            rows.append(BundleIdDependency(
                kind: .app,
                name: app.name ?? "Untitled app",
                reason: "App association blocks deletion",
                profileId: nil))
        }
        for profile in profiles {
            rows.append(BundleIdDependency(
                kind: .profile,
                name: profile.name ?? "Untitled profile",
                // Design copy distinguishes live profiles; a non-ACTIVE
                // state is still a dependency, so say what it is.
                reason: (profile.profileState ?? "").uppercased() == "ACTIVE"
                    ? "Active profile"
                    : "Profile (\(profile.profileType ?? "unknown"))",
                profileId: profile.id))
        }
        return rows
    }

    @Published var bundleIdProfilesState: ViewState<[ProfileModel]> = .idle
    @Published var bundleIdCapabilitiesState: ViewState<[BundleIdCapabilityModel]> = .idle
    @Published var bundleIdDependenciesState: ViewState<[BundleIdDependency]> = .idle

    /// Profiles per bundle id; a rename does not change membership, but a
    /// profile delete/create does, so the delete paths evict their entry.
    private var bundleIdProfilesCache: [String: [ProfileModel]] = [:]
    private var bundleIdCapabilitiesCache: [String: [BundleIdCapabilityModel]] = [:]

    /// Loads both detail panes. Separate states so the Dependent-profiles
    /// table can retry without refetching capabilities, and vice versa.
    func loadBundleIdDetail(for bundleId: BundleIdModel) {
        loadBundleIdProfiles(for: bundleId)
        loadBundleIdCapabilities(for: bundleId)
    }

    func loadBundleIdProfiles(for bundleId: BundleIdModel) {
        if let cached = bundleIdProfilesCache[bundleId.id] {
            bundleIdProfilesState = cached.isEmpty ? .empty : .loaded(cached)
            return
        }
        Task { await fetchBundleIdProfiles(for: bundleId) }
    }

    func retryBundleIdProfiles(for bundleId: BundleIdModel) {
        bundleIdProfilesCache.removeValue(forKey: bundleId.id)
        loadBundleIdProfiles(for: bundleId)
    }

    func loadBundleIdCapabilities(for bundleId: BundleIdModel) {
        if let cached = bundleIdCapabilitiesCache[bundleId.id] {
            bundleIdCapabilitiesState = cached.isEmpty ? .empty : .loaded(cached)
            return
        }
        Task { await fetchBundleIdCapabilities(for: bundleId) }
    }

    func retryBundleIdCapabilities(for bundleId: BundleIdModel) {
        bundleIdCapabilitiesCache.removeValue(forKey: bundleId.id)
        loadBundleIdCapabilities(for: bundleId)
    }

    /// Query params for GET /v1/bundleIds/{id}/profiles. Kept as a named
    /// constant because the "no `limit`, no `cursor`" rule is the whole
    /// contract for this route and is asserted in the validation suite.
    static let bundleIdProfilesParams = [
        "fields[profiles]": "name,platform,profileType,profileState",
    ]

    /// Query params for GET /v1/bundleIds/{id}/bundleIdCapabilities — same
    /// rule, see `bundleIdProfilesParams`.
    static let bundleIdCapabilitiesParams = [
        "fields[bundleIdCapabilities]": "capabilityType",
    ]

    /// Params for the delete pre-check's profile fetch. Deliberately not
    /// `bundleIdProfilesParams`: the blocked-delete rows need no `platform`.
    static let bundleIdProfilesForDeleteParams = [
        "fields[profiles]": "name,profileType,profileState",
    ]

    /// GET /v1/bundleIds/{id}/profiles — single request.
    ///
    /// The live service 400s `limit` on this to-many-related route
    /// (PARAMETER_ERROR.ILLEGAL, "This relationship does not support this
    /// parameter") even though Apple's published spec still lists it.
    /// `fields[...]` is the only parameter it accepts, so there is no way
    /// to request a page size and no paging loop to run. Verified against
    /// the service, not inferred from the spec — and note the spec's
    /// silence on `cursor` is not evidence either way, since it omits
    /// cursor from every route including the paginated /v1/apps.
    private func fetchBundleIdProfiles(for bundleId: BundleIdModel) async {
        bundleIdProfilesState = .loading
        // No `include` on this route, so no devices/certificates.
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getBundleIds, queryParams: Self.bundleIdProfilesParams, path: "\(bundleId.id)/profiles"),
            apiVersion: .v1) else {
            bundleIdProfilesState = .error("No team selected. Add a team to load profiles.")
            return
        }
        do {
            let data = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return }
            let page = try getDecoder().decode(BundleIdProfilesDocument.self, from: data)
            finishBundleIdProfiles(page.data.map { $0.asProfileModel() }, for: bundleId)
        } catch {
            guard !Task.isCancelled else { return }
            resourcesLogger.error("Failed to load bundle ID profiles: \(error.localizedDescription)")
            bundleIdProfilesState = .error(friendlyMessage(for: error))
        }
    }

    private func finishBundleIdProfiles(_ profiles: [ProfileModel], for bundleId: BundleIdModel) {
        bundleIdProfilesCache[bundleId.id] = profiles
        bundleIdProfilesState = profiles.isEmpty ? .empty : .loaded(profiles)
    }

    /// GET /v1/bundleIds/{id}/bundleIdCapabilities — single request.
    /// Same live-service contract as the sibling profiles route: `limit`
    /// 400s with PARAMETER_ERROR.ILLEGAL on this relationship despite the
    /// published spec listing it, so `fields[...]` is all it accepts. No
    /// `include`, no `sort` — so ordering is local, by display name. A
    /// capability is "enabled" simply by existing; there is no status
    /// attribute.
    private func fetchBundleIdCapabilities(for bundleId: BundleIdModel) async {
        bundleIdCapabilitiesState = .loading
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getBundleIds, queryParams: Self.bundleIdCapabilitiesParams, path: "\(bundleId.id)/bundleIdCapabilities"),
            apiVersion: .v1) else {
            bundleIdCapabilitiesState = .error("No team selected. Add a team to load capabilities.")
            return
        }
        do {
            let data = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return }
            let page = try getDecoder().decode(BundleIdCapabilitiesDocument.self, from: data)
            finishBundleIdCapabilities(page.data, for: bundleId)
        } catch {
            guard !Task.isCancelled else { return }
            resourcesLogger.error("Failed to load bundle ID capabilities: \(error.localizedDescription)")
            bundleIdCapabilitiesState = .error(friendlyMessage(for: error))
        }
    }

    private func finishBundleIdCapabilities(_ capabilities: [BundleIdCapabilityModel],
                                            for bundleId: BundleIdModel) {
        let sorted = capabilities.sorted {
            Self.capabilitySortKey($0) < Self.capabilitySortKey($1)
        }
        bundleIdCapabilitiesCache[bundleId.id] = sorted
        bundleIdCapabilitiesState = sorted.isEmpty ? .empty : .loaded(sorted)
    }

    nonisolated private static func capabilitySortKey(_ capability: BundleIdCapabilityModel) -> String {
        let raw = capability.capabilityType ?? ""
        return CapabilityTypeOption(rawValue: raw)?.displayName ?? raw
    }

    /// Dependency pre-check for the delete sheets (Figma 114-2665 /
    /// 114-2700). Either fetch failing surfaces as an error state rather
    /// than silently reporting "unused" and offering a destructive sheet.
    func loadBundleIdDependencies(for bundleId: BundleIdModel) {
        bundleIdDependenciesState = .loading
        // Sequential, not async let: the results would cross an actor
        // boundary as non-Sendable payloads (Swift 6 warning), and two
        // GETs behind a user-initiated Delete tap is not worth that.
        Task { @MainActor in
            let appResult = await fetchApps(bundleIdId: bundleId.id)
            guard !Task.isCancelled else { return }
            if case .failure(let message) = appResult {
                bundleIdDependenciesState = .error(message)
                return
            }
            let profileResult = await fetchBundleIdProfilesForDelete(bundleId.id)
            guard !Task.isCancelled else { return }
            if case .failure(let message) = profileResult {
                bundleIdDependenciesState = .error(message)
                return
            }
            let rows: [BundleIdDependency]
            switch (appResult, profileResult) {
            case (.value(let apps), .value(let profiles)):
                rows = Self.bundleIdDependencies(apps: apps, profiles: profiles)
            default:
                rows = []
            }
            bundleIdDependenciesState = rows.isEmpty ? .empty : .loaded(rows)
        }
    }

    /// Apps attached to the identifier. Capped at `AppConfigs`' own page
    /// budget (20 × 50) — but a cap reached *with* a cursor left is a
    /// failure, not a short list: reporting "unused" from truncated data
    /// would send the user to a destructive confirm sheet on bad
    /// information.
    private func fetchApps(bundleIdId: String) async -> FetchResult<[AppsData]> {
        var all: [AppsData] = []
        var cursor: String?
        for _ in 0..<20 {
            guard !Task.isCancelled else { return .failure("Cancelled.") }
            // filter[bundleId] is a real array filter on /v1/apps (verified).
            var params = [
                "filter[bundleId]": bundleIdId,
                "limit": "50",
                "fields[apps]": "name",
            ]
            if let cursor { params["cursor"] = cursor }
            guard let request = APIClient.shared.getRequest(
                api: .get(name: .getAllApps, queryParams: params),
                apiVersion: .v1) else {
                return .failure("No team selected. Add a team to load apps.")
            }
            do {
                let data = try await APIClient.shared.callAPI(with: request)
                guard !Task.isCancelled else { return .failure("Cancelled.") }
                let page = try getDecoder().decode(AppsDocument.self, from: data)
                all += page.data
                guard let next = page.meta.paging.nextCursor, !next.isEmpty else {
                    return .value(all)
                }
                cursor = next
            } catch {
                guard !Task.isCancelled else { return .failure("Cancelled.") }
                resourcesLogger.error("Failed to load apps for bundle ID: \(error.localizedDescription)")
                return .failure(friendlyMessage(for: error))
            }
        }
        return .failure("This identifier has more dependent apps than can be listed at once. Remove them in Apple, then retry.")
    }

    /// Profiles attached to the identifier for the delete pre-check. Same
    /// unpaginated route as fetchBundleIdProfiles, so single request and no
    /// `limit`/`cursor`. There is no `include` here either, so
    /// signing-certificate names are unavailable for the rows.
    private func fetchBundleIdProfilesForDelete(_ bundleIdId: String) async -> FetchResult<[ProfileModel]> {
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .getBundleIds, queryParams: Self.bundleIdProfilesForDeleteParams, path: "\(bundleIdId)/profiles"),
            apiVersion: .v1) else {
            return .failure("No team selected. Add a team to load profiles.")
        }
        do {
            let data = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .failure("Cancelled.") }
            let page = try getDecoder().decode(BundleIdProfilesDocument.self, from: data)
            return .value(page.data.map { $0.asProfileModel() })
        } catch {
            guard !Task.isCancelled else { return .failure("Cancelled.") }
            resourcesLogger.error("Failed to load bundle ID profiles: \(error.localizedDescription)")
            return .failure(friendlyMessage(for: error))
        }
    }

    /// DELETE /v1/bundleIdCapabilities/{id} — disable a capability. The
    /// detail list is refetched rather than patched locally: the server
    /// owns the remaining settings, and the "Advanced setup · manual"
    /// column depends on what survives.
    func disableCapability(_ capability: BundleIdCapabilityModel,
                           for bundleId: BundleIdModel) async -> WriteResult {
        let key = "capability-\(capability.id)"
        guard !isWriteInFlight(key) else { return .ignored }
        writeInFlight.insert(key)
        defer { writeInFlight.remove(key) }

        guard let request = APIClient.shared.getRequest(
            api: .delete(name: .bundleIdCapabilities, path: capability.id),
            apiVersion: .v1) else {
            return .failure("Couldn't build the capability request.")
        }
        do {
            _ = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .ignored }
            bundleIdCapabilitiesCache.removeValue(forKey: bundleId.id)
            await fetchBundleIdCapabilities(for: bundleId)
            return .success
        } catch {
            resourcesLogger.error("Failed to disable capability: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
    }

    /// POST /v1/bundleIdCapabilities — enable a capability on the
    /// identifier. Apple's "Enable a capability" endpoint, 201 Created.
    ///
    /// The create body must carry `relationships.bundleId` (unlike every
    /// other write in this module, which keys off `path`), so this is
    /// built from the model rather than a query-param APIMethod.
    ///
    /// Lists are refetched rather than patched locally, matching
    /// disableCapability: the server owns the resulting capability id and
    /// its settings, and the disable rows depend on both.
    func enableCapability(_ option: CapabilityTypeOption,
                          for bundleId: BundleIdModel) async -> WriteResult {
        let key = "capability-enable-\(bundleId.id)-\(option.rawValue)"
        guard !isWriteInFlight(key) else { return .ignored }
        writeInFlight.insert(key)
        defer { writeInFlight.remove(key) }

        let body = BundleIdCapabilityCreateRequest(
            data: BundleIdCapabilityCreateData(
                attributes: BundleIdCapabilityCreateAttributes(capabilityType: option.rawValue),
                relationships: BundleIdCapabilityCreateRelationships(
                    bundleId: BundleIdCapabilityBundleIdRef(
                        data: BundleIdCapabilityBundleIdData(id: bundleId.id))))
        )
        guard let encoded = try? JSONEncoder().encode(body) else {
            return .failure("Couldn't build the capability request.")
        }
        guard let request = APIClient.shared.getRequest(
            api: .post(name: .bundleIdCapabilities, body: encoded),
            apiVersion: .v1) else {
            return .failure("Couldn't build the capability request.")
        }
        do {
            _ = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .ignored }
            bundleIdCapabilitiesCache.removeValue(forKey: bundleId.id)
            await fetchBundleIdCapabilities(for: bundleId)
            return .success
        } catch {
            resourcesLogger.error("Failed to enable capability: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
    }

    /// A profile row disappearing changes both the detail table and the
    /// delete pre-check, so both caches are evicted.
    func invalidateBundleIdDetail(for bundleIdId: String) {
        bundleIdProfilesCache.removeValue(forKey: bundleIdId)
        bundleIdCapabilitiesCache.removeValue(forKey: bundleIdId)
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
        guard EmailValidator.isValid(trimmedEmail) else {
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

        let generation = teamGeneration
        do {
            _ = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled, generation == teamGeneration else { return .ignored }
            loadInvitations()
            return .success
        } catch {
            resourcesLogger.error("Failed to invite user: \(error.localizedDescription)")
            guard !Task.isCancelled, generation == teamGeneration else { return .ignored }
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
        guard EmailValidator.isValid(trimmedEmail) else {
            return .failure("Enter a valid email address.")
        }
        let roles = invitation.roles ?? []
        guard !roles.isEmpty else { return .failure("The invitation has no roles to re-create.") }
        let allAppsVisible = invitation.allAppsVisible ?? true
        // An All-Apps invite must NOT carry a visibleApps relationship — Apple
        // rejects the pair ("if you set allAppsVisible to true, you must not
        // provide values for the visibleApps relationship"), which broke
        // resend for every All-Apps invitation. The hydrated linkage is still
        // kept for genuinely app-scoped invites.
        let visibleAppIds = allAppsVisible ? [] : invitation.visibleApps.map(\.id)
        if !allAppsVisible, visibleAppIds.isEmpty {
            return .failure("This invite is scoped to specific apps that couldn't be loaded. Revoke it and send a new invite with the app picker instead.")
        }
        let resendKey = "resend-invitation-\(invitation.id)"
        guard !isWriteInFlight(resendKey) else { return .ignored }
        writeInFlight.insert(resendKey)
        defer { writeInFlight.remove(resendKey) }

        let generation = teamGeneration
        do {
            guard let deleteRequest = APIClient.shared.getRequest(
                api: .delete(name: .userInvitations, path: invitation.id),
                apiVersion: .v1) else {
                return .failure("Couldn't build the resend request.")
            }
            _ = try await APIClient.shared.callAPI(with: deleteRequest)
            guard !Task.isCancelled, generation == teamGeneration else { return .ignored }
            var inviteRevoked = true
            defer {
                // The delete already happened — the list must reflect
                // reality no matter how the re-create goes.
                if inviteRevoked, generation == teamGeneration { loadInvitations() }
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
                guard !Task.isCancelled, generation == teamGeneration else { return .ignored }
                resourcesLogger.error("Failed to re-create invitation: \(error.localizedDescription)")
                return .failure("\(writeErrorMessage(for: error)) The previous invite was revoked — send a fresh invite.")
            }
            guard !Task.isCancelled, generation == teamGeneration else { return .ignored }
            inviteRevoked = false
            loadInvitations()
            return .success
        } catch {
            resourcesLogger.error("Failed to resend invitation: \(error.localizedDescription)")
            guard !Task.isCancelled, generation == teamGeneration else { return .ignored }
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
                    relationships: (allAppsVisible || visibleAppIds.isEmpty)
                        ? nil
                        : UserInvitationCreateRelationships(
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

        // Defence in depth: the Account Holder cannot be removed through this
        // client. The UI gates this (context menu + edit screen), but rows also
        // expose a `delete` accessibility action, so refuse here too rather
        // than trusting every caller to have checked.
        if case .loaded(let users) = usersState,
           let target = users.first(where: { $0.id == id }),
           isAccountHolderUser(target) {
            return .failure("The Account Holder can't be removed from this app.")
        }

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

    private func profileValidationError(type: ProfileTypeOption, certificateIds: Set<String>, deviceIds: Set<String>) -> String? {
        if let error = ProvisioningWriteValidation.profileSelectionError(type: type, certificateIds: certificateIds, deviceIds: deviceIds) { return error }
        let certificates = certificatesState.loadedValue ?? []
        guard certificateIds.allSatisfy({ id in certificates.contains { $0.id == id && type.acceptsCertificate($0) } }) else {
            return "Reload certificates and select active certificates compatible with this profile."
        }
        if type.allowsDevices {
            let devices = devicesState.loadedValue ?? []
            guard deviceIds.allSatisfy({ id in devices.contains {
                $0.id == id && $0.status == "ENABLED" && devicePlatformMatches($0.platform, profilePlatform: type.bundlePlatformCode)
            } }) else { return "Reload devices and select enabled devices compatible with this profile." }
        }
        return nil
    }

    /// POST /v1/profiles — create a provisioning profile. Certificates are
    /// required server-side; devices are required server-side only for
    /// development/adhoc types (omitted from the body when empty).
    func createProfile(name: String, profileType: ProfileTypeOption, bundleIdId: String?,
                       certificateIds: Set<String>, deviceIds: Set<String>) async -> WriteResult {
        guard !isWriteInFlight(Self.createProfileKey) else { return .ignored }
        writeInFlight.insert(Self.createProfileKey)
        defer { writeInFlight.remove(Self.createProfileKey) }
        return await performCreateProfile(name: name, profileType: profileType, bundleIdId: bundleIdId,
                                          certificateIds: certificateIds, deviceIds: deviceIds)
    }

    private func performCreateProfile(name: String,
                       profileType: ProfileTypeOption,
                       bundleIdId: String?,
                       certificateIds: Set<String>,
                       deviceIds: Set<String>) async -> WriteResult {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return .failure("Enter a name for the profile.") }
        guard let bundleIdId, !bundleIdId.isEmpty else {
            return .failure("Pick the bundle ID this profile is for.")
        }
        if let error = profileValidationError(type: profileType, certificateIds: certificateIds, deviceIds: deviceIds) { return .failure(error) }

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

        let generation = teamGeneration
        do {
            let responseData = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled, generation == teamGeneration else { return .ignored }
            let model = try getDecoder().decode(ProfileModel.self, from: responseData)
            prependProfile(model)
            return .success
        } catch {
            resourcesLogger.error("Failed to create profile: \(error.localizedDescription)")
            guard !Task.isCancelled, generation == teamGeneration else { return .ignored }
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
    /// provisioning file) → NSSavePanel. Same contract as
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
                                      fileExtension: profile.provisioningFileExtension)
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
        let fileName = safeFileName(model.name ?? profile.name)
            + "." + model.provisioningFileExtension
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
        if let error = profileValidationError(type: profileType, certificateIds: certificateIds, deviceIds: deviceIds) { return .failure(error) }
        guard !bundleIdId.isEmpty else { return .failure("Pick the bundle ID this profile is for.") }
        let key = "regenerate-profile-\(profileId)"
        guard !isWriteInFlight(key), !isWriteInFlight(Self.createProfileKey), !isWriteInFlight(profileId) else { return .ignored }
        writeInFlight.insert(key)
        writeInFlight.insert(Self.createProfileKey)
        writeInFlight.insert(profileId)
        defer {
            writeInFlight.remove(key)
            writeInFlight.remove(Self.createProfileKey)
            writeInFlight.remove(profileId)
        }

        let generation = teamGeneration
        do {
            guard let deleteRequest = APIClient.shared.getRequest(
                api: .delete(name: .getProfiles, path: profileId),
                apiVersion: .v1) else {
                return .failure("Couldn't build the regenerate request.")
            }
            _ = try await APIClient.shared.callAPI(with: deleteRequest)
            guard !Task.isCancelled, generation == teamGeneration else { return .ignored }
            // Snapshot before the delete so the replacement can be identified by
            // set difference afterwards — `createProfile` returns a bare
            // WriteResult with no payload to name it from.
            let idsBefore = Set((profilesState.loadedValue ?? []).map(\.id))
            dropProfileLocally(id: profileId)

            let createResult = await performCreateProfile(
                name: trimmedName, profileType: profileType, bundleIdId: bundleIdId,
                certificateIds: certificateIds, deviceIds: deviceIds)
            guard !Task.isCancelled, generation == teamGeneration else { return .ignored }
            switch createResult {
            case .success:
                lastRegeneratedProfileId = (profilesState.loadedValue ?? [])
                    .map(\.id)
                    .first { !idsBefore.contains($0) }
                return .success
            case .failure(let message):
                lastRegeneratedProfileId = nil
                return .failure("\(message) The old profile was already deleted — no replacement exists yet.")
            case .ignored:
                lastRegeneratedProfileId = nil
                return .failure("The old profile was deleted, but the replacement was not created — run the wizard again.")
            }
        } catch {
            resourcesLogger.error("Failed to regenerate profile: \(error.localizedDescription)")
            guard !Task.isCancelled, generation == teamGeneration else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
    }

    /// Id of the profile created by the most recent `regenerateProfile`, so the
    /// result stage can name *that* profile. It used to read
    /// `profilesState.loadedValue?.first?.name`, which labelled the replacement
    /// with whichever profile happened to sort first. Cleared when a regenerate
    /// fails so a stale id can't be shown.
    @Published private(set) var lastRegeneratedProfileId: String?

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

    /// Install for Xcode (Figma 114-3716): fetch the provisioning file and
    /// save it via a panel rooted at Xcode's provisioning-profiles
    /// directory (~/Library/Developer/Xcode/UserData/Provisioning Profiles/). A save
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
                .appendingPathComponent("Library/Developer/Xcode/UserData/Provisioning Profiles", isDirectory: true)
            let panel = NSSavePanel()
            panel.directoryURL = profilesDir
            panel.nameFieldStringValue = fileName
            panel.canCreateDirectories = true
            if let fileType = UTType(filenameExtension: profile.provisioningFileExtension) {
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
            // Same contract as prependCertificate: keep the server-confirmed
            // model visible, no racing retry (BUG_SWEEP #12).
            profilesState = .loaded([model])
            if let total = totals[.profiles] {
                totals[.profiles] = total + 1
            }
            searchTexts[.profiles] = nil
            dataVersion += 1
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

    private func prependMerchantId(_ model: MerchantIdModel) {
        guard case .loaded(var merchantIds) = merchantIdsState else {
            merchantIdsState = .loaded([model])
            if let total = totals[.merchantIds] {
                totals[.merchantIds] = total + 1
            }
            searchTexts[.merchantIds] = nil
            dataVersion += 1
            return
        }
        merchantIds.removeAll { $0.id == model.id }
        merchantIds.insert(model, at: 0)
        merchantIdsState = .loaded(merchantIds)
        if let total = totals[.merchantIds] {
            totals[.merchantIds] = total + 1
        }
        searchTexts[.merchantIds] = nil
        dataVersion += 1
    }

    private func prependPassTypeId(_ model: PassTypeIdModel) {
        guard case .loaded(var passTypeIds) = passTypeIdsState else {
            passTypeIdsState = .loaded([model])
            if let total = totals[.passTypeIds] {
                totals[.passTypeIds] = total + 1
            }
            searchTexts[.passTypeIds] = nil
            dataVersion += 1
            return
        }
        passTypeIds.removeAll { $0.id == model.id }
        passTypeIds.insert(model, at: 0)
        passTypeIdsState = .loaded(passTypeIds)
        if let total = totals[.passTypeIds] {
            totals[.passTypeIds] = total + 1
        }
        searchTexts[.passTypeIds] = nil
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
            // The create POST already returned a server-confirmed model, so
            // seed the list with it instead of dropping it (BUG_SWEEP #12).
            // Dropping it left the create form stuck with no error — and
            // since the CSR's private key is gone by then, the .cer was
            // unreachable from the app entirely.
            //
            // No retry() here on purpose: `fetch` calls `setLoading`, which
            // would clear the seed before the create form's success step
            // reads it. The full page returns on the next tab load/refresh.
            certificatesState = .loaded([model])
            if let total = totals[.certificates] {
                totals[.certificates] = total + 1
            }
            searchTexts[.certificates] = nil
            dataVersion += 1
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
