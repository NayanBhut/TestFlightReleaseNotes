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
    /// kind never swallows another kind's Load-more tap.
    private var isPaginatingKinds: Set<Kind> = []

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
            [$0.name, $0.uuid, $0.profileType, $0.profileState, $0.platform]
        }
    }

    var filteredUsers: [UserModel] {
        cachedFilter(&usersFilterCache, kind: .users, source: usersState.loadedValue ?? []) {
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
            return apiError.details
        }
        return error.localizedDescription
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

    /// POST /v1/certificates — create from a CSR. The caller pastes CSR
    /// content (Keychain Access → Request a Certificate, or
    /// `openssl req -new`); generating the key pair in-app is out of scope.
    func createCertificate(certificateType: CertificateTypeOption, csrContent: String) async -> WriteResult {
        let trimmedCSR = csrContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCSR.isEmpty else { return .failure("Paste the CSR content.") }
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
    // POST /v1/userInvitations (invite), PATCH /v1/users/{id} (roles),
    // DELETE /v1/users/{id} (remove), resend = find pending invite by
    // email → DELETE /v1/userInvitations/{id} → re-POST (no dedicated
    // resend endpoint exists). Same WriteResult contract as above.
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
            return .failure("Pick the app this user can access, or turn on \"All apps visible\".")
        }
        guard !isWriteInFlight(Self.inviteUserKey) else { return .ignored }
        writeInFlight.insert(Self.inviteUserKey)
        defer { writeInFlight.remove(Self.inviteUserKey) }

        guard let request = invitationCreateRequest(
            email: trimmedEmail,
            firstName: trimmedFirst,
            lastName: trimmedLast,
            roles: roles,
            allAppsVisible: allAppsVisible,
            provisioningAllowed: provisioningAllowed,
            visibleAppIds: visibleAppIds) else {
            return .failure("Couldn't build the invite request.")
        }

        do {
            _ = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .ignored }
            return .success
        } catch {
            resourcesLogger.error("Failed to invite user: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
    }

    /// Resend an invitation: find the pending invite by email, delete it,
    /// then re-create with the supplied details. Fails openly when no
    /// pending invite exists for the email.
    func resendInvitation(email: String,
                          firstName: String,
                          lastName: String,
                          roles: Set<UserRoleOption>,
                          allAppsVisible: Bool,
                          provisioningAllowed: Bool,
                          visibleAppIds: [String] = []) async -> WriteResult {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, trimmedEmail.contains("@") else {
            return .failure("Enter a valid email address.")
        }
        let resendKey = "resend-invitation-\(trimmedEmail.lowercased())"
        guard !isWriteInFlight(resendKey) else { return .ignored }
        writeInFlight.insert(resendKey)
        defer { writeInFlight.remove(resendKey) }

        do {
            guard let pendingId = try await pendingInvitationId(forEmail: trimmedEmail) else {
                return .failure("No pending invitation for \(trimmedEmail) — send a new invite instead.")
            }
            guard !Task.isCancelled else { return .ignored }
            guard let deleteRequest = APIClient.shared.getRequest(
                api: .delete(name: .userInvitations, path: pendingId),
                apiVersion: .v1) else {
                return .failure("Couldn't build the resend request.")
            }
            _ = try await APIClient.shared.callAPI(with: deleteRequest)
            guard !Task.isCancelled else { return .ignored }
            guard let createRequest = invitationCreateRequest(
                email: trimmedEmail,
                firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                roles: roles,
                allAppsVisible: allAppsVisible,
                provisioningAllowed: provisioningAllowed,
                visibleAppIds: visibleAppIds) else {
                return .failure("Couldn't build the resend request.")
            }
            _ = try await APIClient.shared.callAPI(with: createRequest)
            guard !Task.isCancelled else { return .ignored }
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
    private func pendingInvitationId(forEmail email: String) async throws -> String? {
        guard let request = APIClient.shared.getRequest(
            api: .get(name: .userInvitations,
                      queryParams: ["filter[email]": email, "limit": "1"]),
            apiVersion: .v1) else {
            throw APIError.requestFailed
        }
        let data = try await APIClient.shared.callAPI(with: request)
        guard !Task.isCancelled else { return nil }
        let model = try getDecoder().decode(UserInvitationsDocument.self, from: data)
        return model.data.first?.id
    }

    private func invitationCreateRequest(email: String,
                                         firstName: String,
                                         lastName: String,
                                         roles: Set<UserRoleOption>,
                                         allAppsVisible: Bool,
                                         provisioningAllowed: Bool,
                                         visibleAppIds: [String]) -> URLRequest? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard !firstName.isEmpty, !lastName.isEmpty, !roles.isEmpty,
              let data = try? encoder.encode(UserInvitationCreateRequest(
                data: UserInvitationCreateData(
                    attributes: UserInvitationCreateAttributes(
                        email: email,
                        firstName: firstName,
                        lastName: lastName,
                        roles: roles.map(\.rawValue).sorted(),
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

    /// PATCH /v1/users/{id} — replace the user's roles.
    func updateUserRoles(_ user: UserModel, roles: Set<UserRoleOption>) async -> WriteResult {
        guard !roles.isEmpty else { return .failure("Pick at least one role.") }
        guard !isWriteInFlight(user.id) else { return .ignored }
        writeInFlight.insert(user.id)
        defer { writeInFlight.remove(user.id) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(UserUpdateRequest(
            data: UserUpdateData(
                id: user.id,
                attributes: UserUpdateAttributes(roles: roles.map(\.rawValue).sorted())
            )
        )), let request = APIClient.shared.getRequest(
            api: .patch(name: .getUsers, body: data, path: user.id),
            apiVersion: .v1) else {
            return .failure("Couldn't build the role update request.")
        }

        do {
            let responseData = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return .ignored }
            let model = try getDecoder().decode(UserModel.self, from: responseData)
            // Re-locate after the await: the list may have changed
            // (refresh, pagination) since the edit started.
            guard case .loaded(var users) = usersState,
                  let index = users.firstIndex(where: { $0.id == user.id }) else { return .ignored }
            users[index] = model
            usersState = .loaded(users)
            dataVersion += 1
            return .success
        } catch {
            resourcesLogger.error("Failed to update user roles: \(error.localizedDescription)")
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
                    devices: deviceIds.isEmpty ? nil : ProfileCreateArrayRelationship(
                        data: deviceIds.sorted().map { ProfileCreateRef(type: "devices", id: $0) }
                    )
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
            guard case .loaded(var profiles) = profilesState,
                  let index = profiles.firstIndex(where: { $0.id == id }) else { return .ignored }
            profiles.remove(at: index)
            profilesState = profiles.isEmpty ? .empty : .loaded(profiles)
            if let total = totals[.profiles] {
                totals[.profiles] = max(0, total - 1)
            }
            dataVersion += 1
            return .success
        } catch {
            resourcesLogger.error("Failed to delete profile: \(error.localizedDescription)")
            guard !Task.isCancelled else { return .ignored }
            return .failure(writeErrorMessage(for: error))
        }
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
}
