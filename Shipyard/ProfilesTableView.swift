//
//  ProfilesTableView.swift
//  App Store
//
//  Profiles flow from the Figma frames: toolbar (title + total pill,
//  Type/Status filters, search, Create Profile) over a Name / Type /
//  Bundle ID / Expiration / Status / Platform table (3-5273). Rows tap
//  through to the full-screen detail; deletion runs from the row context
//  menu with the type-to-confirm sheet; creation reuses the shared
//  CreateProfileForm wizard.
//

import SwiftUI

struct ProfilesTableView: View {
    @ObservedObject var viewModel: ResourcesViewModel
    @EnvironmentObject private var toastCenter: ShipyardToastCenter
    var onOpenCertificate: (String) -> Void = { _ in }
    var onOpenBundleId: (String) -> Void = { _ in }
    var onOpenDevice: (String) -> Void = { _ in }
    @State private var showCreateForm = false
    @State private var selectedProfile: ProfileModel?
    @State private var deleting: ProfileModel?
    @State private var downloadingId: String?
    @State private var bannerError: String?
    @State private var typeFilter: String? = nil
    @State private var statusFilter: ProfileComputedStatus? = nil

    /// Module 12 bulk selection (Flow 12D): independent per-row DELETE /
    /// download over exactly the checked rows — never the whole list.
    @State private var selection: Set<String> = []
    @State private var showBulkDownload = false
    @State private var showBulkDelete = false
    @State private var deleteConfirmation = ""
    @State private var ledger: [BulkLedgerItem] = []
    @State private var showBulkResult = false
    @State private var bulkReconciled = false
    @State private var downloadResults: [SigningFileResult] = []
    @State private var showDownloadResult = false

    private var profiles: [ProfileModel] {
        viewModel.filteredProfiles.filter { profile in
            if let typeFilter, profile.profileType != typeFilter { return false }
            if let statusFilter, profile.computedStatus != statusFilter { return false }
            return true
        }
    }

    private var selectedProfiles: [ProfileModel] {
        profiles.filter { selection.contains($0.id) }
    }

    var body: some View {
        if let selectedProfile {
            ProfileDetailView(
                viewModel: viewModel,
                profile: selectedProfile,
                onBack: { self.selectedProfile = nil },
                onOpenCertificate: onOpenCertificate,
                onOpenBundleId: onOpenBundleId,
                onOpenDevice: onOpenDevice)
        } else {
            VStack(spacing: 0) {
                toolbar
                Divider()
                if let bannerError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppTheme.negative)
                        Text(bannerError)
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.negative)
                        Spacer()
                        Button {
                            self.bannerError = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss error")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    Divider()
                }
                table
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ShipyardTheme.tableBackground)
            .onAppear {
                viewModel.load(.profiles)
            }
            .sheet(isPresented: $showCreateForm) {
                CreateProfileForm(viewModel: viewModel) {
                    showCreateForm = false
                }
            }
            .sheet(item: $deleting) { profile in
                DeleteProfileSheet(viewModel: viewModel, profile: profile) {
                    deleting = nil
                }
            }
            // MARK: - Module 12 bulk sheets (Flow 12D)
            .sheet(isPresented: $showBulkDownload) {
                DownloadSigningFilesSheet(
                    rows: selectedProfiles.map {
                        SigningDownloadRow(
                            id: $0.id,
                            rowLabel: $0.name ?? "Untitled profile",
                            outputName: bulkProfileFileName($0) + "." + $0.provisioningFileExtension
                        )
                    },
                    destination: "~/Downloads/Shipyard/Signing",
                    onChooseDestination: {},
                    onCancel: { showBulkDownload = false },
                    onDownload: {
                        showBulkDownload = false
                        runBulkDownload()
                    }
                )
            }
            .sheet(isPresented: $showBulkDelete) {
                DeleteProfilesSheet(
                    profiles: selectedProfiles.map {
                        (name: $0.name ?? "Untitled profile",
                         type: profileTypeName($0.profileType),
                         dependency: $0.bundleId.flatMap(\.identifier) ?? $0.bundleId.flatMap(\.name) ?? "—")
                    },
                    confirmationText: "DELETE \(selectedProfiles.count)",
                    typedConfirmation: $deleteConfirmation,
                    onCancel: { showBulkDelete = false },
                    onDelete: {
                        showBulkDelete = false
                        runBulkDelete()
                    }
                )
            }
            .sheet(isPresented: $showBulkResult) {
                BulkRevocationResultSheet(
                    title: "Bulk delete · partial result",
                    bannerTitle: bulkBannerTitle,
                    bannerBody: "Independent DELETE requests. Downloaded copies are not removed automatically. Do not repeat confirmed success. Resolve 403 access before retry; reconcile any unknown outcome first.",
                    itemNoun: "Profile",
                    confirmedVerb: "Deleted",
                    items: $ledger,
                    isReconciled: bulkReconciled,
                    onExport: exportLedger,
                    onRefreshReconcile: {
                        viewModel.load(.profiles)
                        bulkReconciled = true
                    },
                    onRetryUnknown: runBulkRetryUnknown,
                    onDone: {
                        showBulkResult = false
                        selection = []
                    }
                )
            }
            .sheet(isPresented: $showDownloadResult) {
                SigningDownloadResultSheet(
                    results: downloadResults,
                    destinationNote: "Original selected folder · per-file save panels",
                    canRetryLocalWrite: downloadResults.contains { if case .failed = $0.writeResult { return true }; return false },
                    onChooseWritableFolder: {},
                    onExport: exportDownloadLedger,
                    onRetryLocalWrite: retryFailedDownloads,
                    onDone: {
                        showDownloadResult = false
                        selection = []
                    }
                )
            }
        }
    }

    // MARK: - Module 12 bulk execution

    private func bulkProfileFileName(_ profile: ProfileModel) -> String {
        let raw = profile.name ?? "download"
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty ? "download" : trimmed).replacingOccurrences(of: "/", with: "-")
    }

    private var bulkBannerTitle: String {
        let confirmed = ledger.filter { $0.outcome?.isConfirmed == true }.count
        let unknown = ledger.filter { if case .unknown = $0.outcome { return true }; return false }.count
        if unknown > 0 {
            return "\(confirmed) deletion confirmed · \(unknown) outcome unknown"
        }
        return "\(confirmed) deletion confirmed · \(ledger.count - confirmed) denied"
    }

    /// Sequential independent DELETEs; every non-204 outcome stays in the
    /// ledger with its guard instead of failing the batch.
    private func runBulkDelete() {
        let targets = selectedProfiles
        guard !targets.isEmpty else { return }
        bulkReconciled = false
        ledger = targets.map {
            BulkLedgerItem(
                id: $0.id,
                label: $0.name ?? "Untitled profile",
                sublabel: "ID: \($0.id)",
                outcome: nil
            )
        }
        showBulkResult = true
        Task { @MainActor in
            for target in targets {
                let result = await viewModel.deleteProfile(id: target.id)
                if let index = ledger.firstIndex(where: { $0.id == target.id }) {
                    switch result {
                    case .success:
                        ledger[index].outcome = .confirmed("DELETE 204 · no response body")
                    case .failure(let message):
                        ledger[index].outcome = BulkOutcomeClassification.classify(message: message)
                    case .ignored:
                        ledger[index].outcome = .unknown("Request ignored — reconcile before retry")
                    }
                }
            }
            if ledger.allSatisfy({ $0.outcome?.isConfirmed == true }) {
                selection = []
                toastCenter.show("Profiles deleted", detail: "\(ledger.count) confirmed", variant: .success)
            }
        }
    }

    /// Retries only the unknown rows after Refresh / Reconcile unlocked
    /// them. Confirmed rows are never touched again.
    private func runBulkRetryUnknown() {
        let unknownIds = Set(ledger.filter { if case .unknown = $0.outcome { return true }; return false }.map(\.id))
        guard !unknownIds.isEmpty else { return }
        Task { @MainActor in
            for id in unknownIds {
                let result = await viewModel.deleteProfile(id: id)
                if let index = ledger.firstIndex(where: { $0.id == id }) {
                    switch result {
                    case .success:
                        ledger[index].outcome = .confirmed("DELETE 204 · no response body")
                    case .failure(let message):
                        ledger[index].outcome = BulkOutcomeClassification.classify(message: message)
                    case .ignored:
                        break
                    }
                }
            }
        }
    }

    private func exportLedger() {
        LocalResultsExport.saveLedger(
            filename: "bulk-delete-results.txt",
            lines: LocalResultsExport.lines(
                title: "Bulk delete · partial result",
                scope: "Profiles",
                when: Date(),
                rows: ledger.map { ($0.label, $0.outcome?.detail ?? "No result") }
            )
        )
    }

    private func runBulkDownload() {
        let targets = selectedProfiles
        guard !targets.isEmpty else { return }
        downloadResults = targets.map {
            SigningFileResult(
                id: $0.id,
                outputName: bulkProfileFileName($0) + "." + $0.provisioningFileExtension,
                material: $0.provisioningFileExtension == "provisionprofile"
                    ? "macOS provisioning profile"
                    : "Apple provisioning profile",
                fetchStage: "Authenticated GET profile",
                writeResult: nil
            )
        }
        showDownloadResult = true
        Task { @MainActor in
            for target in targets {
                let result = await viewModel.downloadProfile(target)
                if let index = downloadResults.firstIndex(where: { $0.id == target.id }) {
                    switch result {
                    case .success:
                        downloadResults[index].writeResult = .saved
                    case .failure(let message):
                        downloadResults[index].writeResult = .failed(message)
                    case .ignored:
                        downloadResults[index].writeResult = .failed("Save panel cancelled — no file written")
                    }
                }
            }
        }
    }

    private func retryFailedDownloads() {
        let failedIds = Set(downloadResults.filter { if case .failed = $0.writeResult { return true }; return false }.map(\.id))
        let targets = selectedProfiles.filter { failedIds.contains($0.id) }
        Task { @MainActor in
            for target in targets {
                let result = await viewModel.downloadProfile(target)
                if let index = downloadResults.firstIndex(where: { $0.id == target.id }) {
                    switch result {
                    case .success:
                        downloadResults[index].writeResult = .saved
                    case .failure(let message):
                        downloadResults[index].writeResult = .failed(message)
                    case .ignored:
                        break
                    }
                }
            }
        }
    }

    private func exportDownloadLedger() {
        LocalResultsExport.saveLedger(
            filename: "signing-download-results.txt",
            lines: LocalResultsExport.lines(
                title: "Signing downloads · local result",
                scope: "Profiles",
                when: Date(),
                rows: downloadResults.map { ($0.outputName, writeOutcomeText($0.writeResult)) }
            )
        )
    }

    private func writeOutcomeText(_ result: WriteStageResult?) -> String {
        switch result {
        case .saved: return "Saved locally"
        case .failed(let message): return "Local save failed — \(message)"
        case .none: return "Not attempted"
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Profiles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                ShipyardCountPill(text: totalText)
                if !selection.isEmpty {
                    Text("\(selection.count) selected")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.accent)
                    Button("Download") { showBulkDownload = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Delete…") {
                        deleteConfirmation = ""
                        showBulkDelete = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button("Clear") { selection = [] }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            }

            Spacer()

            ShipyardSearchField(prompt: "Search Profiles", text: viewModel.searchBinding(for: .profiles))

            Menu {
                Button("All") { typeFilter = nil }
                ForEach(ProfileTypeOption.allCases, id: \.self) { option in
                    Button(option.displayName) { typeFilter = option.rawValue }
                }
            } label: {
                filterChipLabel(typeFilter.map { ProfileTypeOption(rawValue: $0)?.displayName ?? $0 } ?? "All",
                                prefix: "Type")
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Filter by profile type")

            Menu {
                Button("All") { statusFilter = nil }
                Button("Active") { statusFilter = .active }
                Button("Expired") { statusFilter = .expired }
                Button("Invalid") { statusFilter = .invalid }
            } label: {
                filterChipLabel(statusFilter?.displayName ?? "All", prefix: "Status")
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Filter by profile status")

            Button("Create Profile") {
                showCreateForm.toggle()
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(ShipyardTheme.accent)
            .cornerRadius(6)
            .buttonStyle(.plain)
            .accessibilityLabel("Create a provisioning profile")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(LaunchTheme.page)
    }

    private func filterChipLabel(_ value: String, prefix: String) -> some View {
        HStack(spacing: 4) {
            Text("\(prefix): \(value)")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
            Text("⌄")
                .font(.system(size: 10))
                .foregroundColor(ShipyardTheme.body)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Color.white)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(LaunchTheme.border, lineWidth: 1))
    }

    private var totalText: String {
        if let total = viewModel.totals[.profiles] {
            return "\(total) Total"
        }
        return "\(viewModel.loadedCount(for: .profiles)) Total"
    }

    // MARK: - Table

    @ViewBuilder
    private var table: some View {
        switch viewModel.profilesState {
        case .idle, .loading:
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                Text("Loading profiles…")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.body)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            ErrorRetryView(
                title: "Couldn't Load Profiles",
                message: message,
                retryTitle: "Retry",
                onRetry: { viewModel.retry(.profiles) }
            )
        default:
            if profiles.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        headerRow
                        ForEach(profiles, id: \.id) { profile in
                            profileRow(profile)
                            ShipyardTheme.rowDivider.frame(height: 1)
                        }
                        paginationFooter
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(viewModel.hasActiveSearch(for: .profiles) || typeFilter != nil || statusFilter != nil
                 ? "No Matching Profiles" : "No Profiles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            Text("Create a profile to bind a bundle ID, certificates and devices")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
            Button("Create Profile") {
                showCreateForm = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Button {
                let visible = Set(profiles.map(\.id))
                selection = selection.isSuperset(of: visible) ? selection.subtracting(visible) : selection.union(visible)
            } label: {
                Image(systemName: profiles.allSatisfy { selection.contains($0.id) } && !profiles.isEmpty
                      ? "checkmark.square.fill" : "square")
                    .foregroundColor(ShipyardTheme.body)
            }
            .buttonStyle(.plain)
            .frame(width: 28, alignment: .leading)
            .accessibilityLabel("Select all profiles")
            Text("Name").frame(width: 200, alignment: .leading)
            Text("Type").frame(width: 140, alignment: .leading)
            Text("Bundle ID").frame(width: 200, alignment: .leading)
            Text("Expiration").frame(width: 120, alignment: .leading)
            Text("Status").frame(width: 110, alignment: .leading)
            Text("Platform").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(ShipyardTheme.body)
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(ShipyardTheme.tableHeader)
    }

    private func profileRow(_ profile: ProfileModel) -> some View {
        let status = profile.computedStatus
        let bundleLabel = profile.bundleId.flatMap(\.identifier)
            ?? profile.bundleId.flatMap(\.name) ?? "—"
        return HStack(spacing: 12) {
            Button {
                if selection.contains(profile.id) {
                    selection.remove(profile.id)
                } else {
                    selection.insert(profile.id)
                }
            } label: {
                Image(systemName: selection.contains(profile.id) ? "checkmark.square.fill" : "square")
                    .foregroundColor(selection.contains(profile.id) ? ShipyardTheme.accent : ShipyardTheme.body)
            }
            .buttonStyle(.plain)
            .frame(width: 28, alignment: .leading)
            .accessibilityLabel("Select \(profile.name ?? "profile")")
            Text(profile.name ?? "Unknown profile")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 200, alignment: .leading)

            Text(profileTypeName(profile.profileType))
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)

            Text(bundleLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(ShipyardTheme.body)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 200, alignment: .leading)

            Text(profileDateText(profile.expirationDate))
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
                .frame(width: 120, alignment: .leading)

            HStack(spacing: 6) {
                Circle()
                    .fill(profileStatusColor(status))
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(status.displayName)
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.title)
            }
            .frame(width: 110, alignment: .leading)

            Text(profilePlatformChip(profile.platform))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(ShipyardTheme.body)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.12))
                .cornerRadius(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedProfile = profile
        }
        .contextMenu {
            Button("Open") { selectedProfile = profile }
            if downloadingId == profile.id {
                Text("Downloading…")
            } else {
                Button("Download") {
                    Task { @MainActor in
                        downloadingId = profile.id
                        defer { downloadingId = nil }
                        let result = await viewModel.downloadProfile(profile)
                        if case .success = result {
                            toastCenter.show("Profile downloaded", variant: .success)
                        }
                        if case .failure(let message) = result {
                            bannerError = message
                            toastCenter.show("Couldn't download profile", detail: message, variant: .error)
                        }
                    }
                }
                .accessibilityLabel("Download \(profile.name ?? "profile")")
            }
            Button("Delete", role: .destructive) {
                deleting = profile
            }
            .accessibilityLabel("Delete \(profile.name ?? "profile")")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.name ?? "profile"), \(status.displayName)")
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if let nextCursor = viewModel.nextCursors[.profiles] {
            HStack {
                Spacer()
                if viewModel.paginationFailedKinds.contains(.profiles) {
                    Button("Couldn't load more — Retry") {
                        viewModel.loadMore(.profiles, cursor: nextCursor)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.danger)
                    .padding(.vertical, 8)
                } else {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.vertical, 8)
                        .onAppear {
                            if !viewModel.isPaginatingKinds.contains(.profiles) {
                                viewModel.loadMore(.profiles, cursor: nextCursor)
                            }
                        }
                }
                Spacer()
            }
        }
    }
}
