//
//  BundleIDsTableView.swift
//  App Store
//
//  Bundle IDs list + identifier detail (Figma module 04 "Bundle
//  identifiers"). The list keeps the Figma table language (toolbar with
//  title + total pill, search, New Bundle ID over a Name / Identifier /
//  Platform / Seed ID table); a row opens the detail (114-2315) with
//  General, Dependent profiles and Capabilities plus a
//  Revert / Save / Delete action bar. Deletion branches on a dependency
//  pre-check: blocked (114-2665) or type-to-confirm (114-2700), then
//  deleted (114-2728). Capability disable confirms with 114-2622.
//  Creation reuses the shared CreateBundleIdForm.
//
//  API facts verified against Apple's OpenAPI spec — see the
//  "Bundle ID detail (Module 04)" section in ResourcesViewModel.
//

import SwiftUI

struct BundleIDsTableView: View {
    @ObservedObject var viewModel: ResourcesViewModel
    @EnvironmentObject private var toastCenter: ShipyardToastCenter
    @Environment(\.openURL) private var openURL

    @State private var showCreateForm = false
    /// Identifies the open detail. The model itself is re-resolved from
    /// the list each render so a rename made inside the detail shows up
    /// here without stale state.
    @State private var detailId: String?
    @State private var bannerError: String?

    /// Delete flow: tapping Delete loads dependencies, then the sheet
    /// branches to blocked / type-to-confirm / deleted.
    @State private var deleteTarget: BundleIdModel?
    @State private var confirmText = ""
    @State private var isDeleting = false
    @State private var deletedName: String?
    /// Delete failures render inside the sheet as well as the list
    /// banner: delete can start from the detail action bar, where the
    /// list banner is not on screen.
    @State private var deleteError: String?
    @State private var disablingCapability: BundleIdCapabilityModel?
    @State private var showEnableCapability = false

    /// Cross-section jumps, wired by ShipyardShell the same way
    /// DevicesView / ProfilesTableView do it (the shell owns `section`,
    /// and apps live in SideBarViewModel rather than this one). Each
    /// argument is a *search query* for the destination list — profile
    /// IDs are not searchable in `filteredProfiles`, so profile jumps
    /// pass the profile name.
    var onOpenApp: ((String) -> Void)?
    var onOpenProfile: ((String) -> Void)?

    private var bundleIds: [BundleIdModel] { viewModel.filteredBundleIds }

    /// Live row for the open detail, or nil once it is deleted.
    private var detailModel: BundleIdModel? {
        guard let detailId else { return nil }
        return viewModel.bundleIdsState.loadedValue?.first { $0.id == detailId }
    }

    var body: some View {
        Group {
            if let detail = detailModel {
                BundleIDDetailView(
                    viewModel: viewModel,
                    bundleId: detail,
                    onBack: { self.detailId = nil },
                    onDelete: { startDelete(for: $0) },
                    onDisableCapability: { disablingCapability = $0 },
                    onEnableCapability: { showEnableCapability = true },
                    onOpenProfile: { openProfile(named: $0) }
                )
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShipyardTheme.tableBackground)
        .onAppear {
            viewModel.load(.bundleIds)
        }
        .sheet(isPresented: $showCreateForm) {
            CreateBundleIdForm(
                viewModel: viewModel,
                onDone: { showCreateForm = false },
                onOpenBundleId: { detailId = $0 }
            )
        }
        .sheet(item: $disablingCapability) { capability in
            if let detail = detailModel {
                BundleIDDisableCapabilitySheet(
                    viewModel: viewModel,
                    bundleId: detail,
                    capability: capability,
                    onOpenProfile: { openProfile(named: $0) }
                )
            }
        }
        .sheet(isPresented: $showEnableCapability) {
            if let detail = detailModel {
                BundleIDEnableCapabilitySheet(
                    viewModel: viewModel,
                    bundleId: detail
                )
            }
        }
        .sheet(isPresented: deleteSheetPresented) {
            deleteSheet
        }
    }

    private var deleteSheetPresented: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { closeDeleteSheet() } }
        )
    }

    // MARK: - List

    private var list: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let bannerError {
                errorBanner(bannerError)
            }
            table
        }
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(ShipyardTheme.danger)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.danger)
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
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Bundle IDs")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                ShipyardCountPill(text: totalText)
            }

            Spacer()

            ShipyardSearchField(prompt: "Search Bundle IDs", text: viewModel.searchBinding(for: .bundleIds))

            Button("New Bundle ID") {
                showCreateForm = true
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(ShipyardTheme.accent)
            .cornerRadius(6)
            .buttonStyle(.plain)
            .accessibilityLabel("Register a bundle ID")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(LaunchTheme.page)
    }

    private var totalText: String {
        if let total = viewModel.totals[.bundleIds] {
            return "\(total) Total"
        }
        return "\(viewModel.loadedCount(for: .bundleIds)) Total"
    }

    // MARK: - Table

    @ViewBuilder
    private var table: some View {
        switch viewModel.bundleIdsState {
        case .idle, .loading:
            loadingState
        case .error(let message):
            ErrorRetryView(
                title: "Couldn't Load Bundle IDs",
                message: message,
                retryTitle: "Retry",
                onRetry: { viewModel.retry(.bundleIds) }
            )
        default:
            if bundleIds.isEmpty {
                // Two different empties: an empty team has nothing to
                // register, a filtered team still owns rows (114-12162 vs
                // 114-12329).
                if viewModel.hasActiveSearch(for: .bundleIds) {
                    noFilterResults
                } else {
                    emptyState
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        headerRow
                        ForEach(bundleIds, id: \.id) { bundleId in
                            bundleRow(bundleId)
                            ShipyardTheme.rowDivider.frame(height: 1)
                        }
                        paginationFooter
                    }
                }
            }
        }
    }

    /// Figma 114-12059: the loading branch keeps the toolbar, the status
    /// banner and the action bar in place and only substitutes skeleton
    /// rows, so the screen never collapses into a centred spinner.
    private var loadingState: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    BundleIDStatusMessage(
                        symbol: "clock",
                        tint: ShipyardTheme.warningBorder,
                        surface: ShipyardTheme.warningSurface,
                        title: "Loading bundle IDs",
                        message: "Fetching the first page from App Store Connect."
                    )
                    VStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { index in
                            skeletonRow
                            if index < 5 {
                                ShipyardTheme.rowDivider.frame(height: 1)
                            }
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(ShipyardTheme.rowDivider, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(24)
            }
            actionBar(status: "Loading…", trailingAccessory: { EmptyView() })
        }
    }

    private var skeletonRow: some View {
        HStack(spacing: 12) {
            skeletonBar(width: 180)
            skeletonBar(width: 240)
            skeletonBar(width: 140)
            skeletonBar(width: 100)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    private func skeletonBar(width: CGFloat) -> some View {
        Capsule()
            .fill(ShipyardTheme.readOnlyField)
            .frame(width: width, height: 10)
    }

    /// Figma 114-12162: an empty team is a status message plus guidance
    /// and one action in the bar — deliberately not a spinner or a dead
    /// "nothing here" label.
    private var emptyState: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    BundleIDStatusMessage(
                        symbol: "info.circle.fill",
                        tint: ShipyardTheme.infoBorder,
                        surface: ShipyardTheme.infoSurface,
                        title: "No bundle ids registered yet",
                        message: "\(teamLabel) has no bundle identifiers. Register one to tie apps, certificates and profiles together."
                    )
                    BundleIDFormSection(title: "Identifier details") {
                        Text("A bundle identifier is the reverse-DNS string Apple signs against — the value in your app's bundle ID. Register the exact string your build uses; it cannot be changed afterwards.")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
            }
            actionBar(status: "\(teamLabel) · 0 bundle IDs") {
                Button("Register Bundle ID") {
                    showCreateForm = true
                }
                .buttonStyle(.launchPrimary)
            }
        }
    }

    private var teamLabel: String {
        CredentialStorage.shared.selectedTeam?.key ?? "No Team"
    }

    /// Bottom bar shared by the loading and empty branches: status text on
    /// the left, actions on the right. Matches the detail view's action bar
    /// (Figma 114-2437) so the shell does not change height between states.
    private func actionBar<Accessory: View>(
        status: String,
        @ViewBuilder trailingAccessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            Text(status)
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
            Spacer()
            trailingAccessory()
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(ShipyardTheme.sidebarBackground)
        .overlay(ShipyardTheme.rowDivider.frame(height: 1), alignment: .top)
    }

    /// Figma 114-12329: a search that matched nothing is not an empty
    /// team, and must not offer "register a bundle ID".
    private var noFilterResults: some View {
        let query = viewModel.searchText(for: .bundleIds)
        return VStack(alignment: .leading, spacing: 20) {
            Spacer()
            BundleIDStatusMessage(
                symbol: "info.circle.fill",
                tint: ShipyardTheme.infoBorder,
                surface: ShipyardTheme.infoSurface,
                title: "No matching bundle ids",
                message: "No rows match “\(query)”. Your bundle IDs still exist; clear the search to see them. This is not an empty team."
            )
            HStack(spacing: 8) {
                Text("Search: \(query)")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(ShipyardTheme.tableBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(ShipyardTheme.rowDivider, lineWidth: 1)
                    )
                Button("Clear Search & Filters") {
                    viewModel.searchTexts[.bundleIds] = nil
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Text("Name").frame(width: 240, alignment: .leading)
            Text("Identifier").frame(width: 280, alignment: .leading)
            Text("Platform").frame(width: 120, alignment: .leading)
            Text("Seed ID").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(ShipyardTheme.body)
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(ShipyardTheme.tableHeader)
    }

    private func bundleRow(_ bundleId: BundleIdModel) -> some View {
        HStack(spacing: 12) {
            Text(bundleId.name ?? "Unknown bundle ID")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 240, alignment: .leading)

            Text(bundleId.identifier ?? "—")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(ShipyardTheme.body)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 280, alignment: .leading)

            Text(bundlePlatformDisplay(bundleId.platform))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(ShipyardTheme.body)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.12))
                .cornerRadius(4)
                .frame(width: 120, alignment: .leading)

            Text(bundleId.seedId ?? "—")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(ShipyardTheme.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .contentShape(Rectangle())
        .onTapGesture {
            detailId = bundleId.id
        }
        .contextMenu {
            Button("Open") {
                detailId = bundleId.id
            }
            Button("Rename…") {
                // Rename lives on the detail's General section; the row
                // menu jumps there rather than duplicating the editor.
                detailId = bundleId.id
            }
            Button("Delete…", role: .destructive) {
                startDelete(for: bundleId)
            }
            .accessibilityLabel("Delete \(bundleId.name ?? bundleId.identifier ?? "bundle ID")")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bundleId.name ?? "bundle ID"), \(bundleId.identifier ?? "")")
        .accessibilityHint("Opens the identifier detail")
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if let nextCursor = viewModel.nextCursors[.bundleIds] {
            HStack {
                Spacer()
                if viewModel.paginationFailedKinds.contains(.bundleIds) {
                    Button("Couldn't load more — Retry") {
                        viewModel.loadMore(.bundleIds, cursor: nextCursor)
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
                            if !viewModel.isPaginatingKinds.contains(.bundleIds) {
                                viewModel.loadMore(.bundleIds, cursor: nextCursor)
                            }
                        }
                }
                Spacer()
            }
        }
    }

    // MARK: - Delete flow (114-2665 / 114-2700 / 114-2728)

    private func startDelete(for bundleId: BundleIdModel) {
        confirmText = ""
        deletedName = nil
        deleteError = nil
        bannerError = nil
        isDeleting = false
        deleteTarget = bundleId
        viewModel.loadBundleIdDependencies(for: bundleId)
    }

    private func closeDeleteSheet() {
        deleteTarget = nil
        confirmText = ""
        deleteError = nil
        isDeleting = false
        viewModel.bundleIdDependenciesState = .idle
    }

    @ViewBuilder
    private var deleteSheet: some View {
        if let target = deleteTarget {
            // Deleted is sticky: after a 204 the row is gone, so the
            // success sheet must not depend on dependency state any more.
            if deletedName != nil {
                BundleIDDeletedSheet(identifier: deletedName ?? "") {
                    closeDeleteSheet()
                    detailId = nil
                }
            } else {
                switch viewModel.bundleIdDependenciesState {
                case .idle, .loading:
                    BundleIDSheetChrome(title: "Delete \(target.identifier ?? target.name ?? "bundle ID")?",
                                       onClose: { closeDeleteSheet() }) {
                        HStack(spacing: 12) {
                            Spacer()
                            ProgressView()
                            Text("Checking dependencies…")
                                .font(.system(size: 13))
                                .foregroundColor(ShipyardTheme.body)
                            Spacer()
                        }
                        .padding(.vertical, 28)
                    }
                case .error(let message):
                    BundleIDSheetChrome(title: "Couldn't check dependencies",
                                       onClose: { closeDeleteSheet() }) {
                        BundleIDStatusMessage(
                            symbol: "exclamationmark.triangle.fill",
                            tint: ShipyardTheme.dangerBorder,
                            surface: ShipyardTheme.dangerSurface,
                            title: "Couldn't check dependencies",
                            message: message
                        )
                        HStack(spacing: 8) {
                            Spacer()
                            Button("Close") { closeDeleteSheet() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            Button("Retry") {
                                viewModel.loadBundleIdDependencies(for: target)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                case .empty:
                    BundleIDDeleteConfirmSheet(
                        identifier: target.identifier ?? target.name ?? "this bundle ID",
                        confirmText: $confirmText,
                        isDeleting: isDeleting,
                        errorMessage: deleteError,
                        onCancel: { closeDeleteSheet() },
                        onDelete: { performDelete(target) }
                    )
                case .loaded(let dependencies):
                    BundleIDDeleteBlockedSheet(
                        identifier: target.identifier ?? target.name ?? "this bundle ID",
                        dependencies: dependencies,
                        errorMessage: deleteError,
                        onOpenApp: { name in openApp(named: name) },
                        onOpenProfile: { name in openProfile(named: name) },
                        onClose: { closeDeleteSheet() }
                    )
                }
            }
        }
    }

    private func performDelete(_ bundleId: BundleIdModel) {
        isDeleting = true
        Task { @MainActor in
            let result = await viewModel.deleteBundleId(id: bundleId.id)
            isDeleting = false
            switch result {
            case .success:
                let name = bundleId.identifier ?? bundleId.name ?? "Bundle ID"
                deletedName = name
                viewModel.invalidateBundleIdDetail(for: bundleId.id)
                toastCenter.show(
                    "\(name) deleted",
                    detail: "Existing builds are unaffected.",
                    variant: .success)
            case .failure(let message):
                // 400 here means Apple saw dependencies our pre-check
                // missed, so re-run it rather than showing a dead button.
                // Until the re-check lands the sheet stays on the confirm
                // branch with the error visible.
                deleteError = message
                bannerError = message
                toastCenter.show("Couldn't delete Bundle ID", detail: message, variant: .error)
                viewModel.loadBundleIdDependencies(for: bundleId)
            case .ignored:
                break
            }
        }
    }

    // MARK: - Jumps

    private var teamName: String {
        CredentialStorage.shared.selectedTeam?.key ?? "No Team"
    }

    private func openApp(named name: String) {
        viewModel.searchTexts[.bundleIds] = nil
        onOpenApp?(name)
    }

    private func openProfile(named name: String) {
        viewModel.searchTexts[.bundleIds] = nil
        onOpenProfile?(name)
    }
}

// MARK: - Detail (Figma 114-2315)

private struct BundleIDDetailView: View {
    @ObservedObject var viewModel: ResourcesViewModel
    @EnvironmentObject private var toastCenter: ShipyardToastCenter
    let bundleId: BundleIdModel
    var onBack: () -> Void
    var onDelete: (BundleIdModel) -> Void
    var onDisableCapability: (BundleIdCapabilityModel) -> Void
    var onEnableCapability: () -> Void
    var onOpenProfile: (String) -> Void

    @State private var nameDraft = ""
    @State private var isSaving = false
    @State private var saveError: String?

    private var savedName: String { bundleId.name ?? "" }
    private var isDirty: Bool {
        nameDraft.trimmingCharacters(in: .whitespacesAndNewlines) != savedName
    }
    private var teamName: String {
        CredentialStorage.shared.selectedTeam?.key ?? "No Team"
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heading
                    generalSection
                    dependentProfilesSection
                    capabilitiesSection
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            actionBar
        }
        .onAppear {
            nameDraft = savedName
            viewModel.loadBundleIdDetail(for: bundleId)
        }
        .onChange(of: bundleId.id) { _, _ in
            // Switching identifiers must not carry the previous draft or
            // the previous row's panes.
            nameDraft = savedName
            saveError = nil
            viewModel.loadBundleIdDetail(for: bundleId)
        }
        .onChange(of: savedName) { _, newValue in
            // Adopt the server's value after a successful save without
            // stomping an in-progress edit (the server value only moves
            // when it disagrees with what we last saved).
            if !isSaving {
                nameDraft = newValue
            }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Text("‹ Bundle IDs")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.accent)
            }
            .buttonStyle(.plain)
            Text(bundleId.identifier ?? bundleId.name ?? "Bundle ID")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Refresh") {
                viewModel.invalidateBundleIdDetail(for: bundleId.id)
                viewModel.loadBundleIdDetail(for: bundleId)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Refresh bundle ID detail")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(LaunchTheme.page)
    }

    // MARK: Heading

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(bundleId.identifier ?? "Unknown identifier")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            // `bundleIds` exposes no identifierType attribute; the trailing
            // * is the documented wildcard form, so this is derived.
            Text("\(bundleId.identifierKind.displayName) · \(bundlePlatformDisplay(bundleId.platform)) · \(teamName) · identifier is read-only")
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: General

    private var generalSection: some View {
        BundleIDFormSection(title: "General") {
            VStack(alignment: .leading, spacing: 12) {
                field(
                    label: "Display name",
                    readOnlyValue: nil,
                    field: AnyView(
                        TextField("Display name", text: $nameDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .disabled(isSaving)
                    )
                )
                field(
                    label: "Identifier",
                    readOnlyValue: bundleId.identifier ?? "—",
                    field: nil
                )
                field(
                    label: "Platform",
                    readOnlyValue: bundlePlatformDisplay(bundleId.platform),
                    field: nil
                )
                if let saveError {
                    Text(saveError)
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func field(label: String, readOnlyValue: String?, field: AnyView?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.title)
            if let readOnlyValue {
                Text(readOnlyValue)
                    .font(.system(size: 13, design: readOnlyValue == bundleId.identifier ? .monospaced : .default))
                    .foregroundColor(ShipyardTheme.body)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ShipyardTheme.readOnlyField)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(ShipyardTheme.rowDivider, lineWidth: 1)
                    )
            } else if let field {
                field
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ShipyardTheme.tableBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(ShipyardTheme.rowDivider, lineWidth: 1)
                    )
            }
        }
    }

    // MARK: Dependent profiles

    @ViewBuilder
    private var dependentProfilesSection: some View {
        BundleIDFormSection(title: "Dependent profiles") {
            switch viewModel.bundleIdProfilesState {
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading dependent profiles…")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                }
            case .error(let message):
                BundleIDStatusMessage(
                    symbol: "exclamationmark.triangle.fill",
                    tint: ShipyardTheme.dangerBorder,
                    surface: ShipyardTheme.dangerSurface,
                    title: "Couldn't load dependent profiles",
                    message: message
                )
                Button("Retry") {
                    viewModel.retryBundleIdProfiles(for: bundleId)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .empty:
                Text("No profiles use this identifier.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
            case .loaded(let profiles):
                BundleIDResourceTable(
                    headers: ["Profile", "Type", "Impact", "Jump"],
                    rows: profiles.map { profile in
                        [
                            profile.name ?? "Untitled profile",
                            ProfileTypeOption(rawValue: profile.profileType ?? "")?.displayName
                                ?? profile.profileType ?? "—",
                            "Recreate after entitlement changes",
                            "",
                        ]
                    },
                    linkColumn: 3,
                    linkLabels: profiles.map { _ in "Open Profile →" },
                    linkActions: profiles.map { profile in { onOpenProfile(profile.name ?? profile.id) } }
                )
            }
        }
    }

    // MARK: Capabilities

    @ViewBuilder
    private var capabilitiesSection: some View {
        BundleIDFormSection(title: "Capabilities") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Enable / disable changes entitlements. Affected profiles must be recreated to reflect the new capability set.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
                    .fixedSize(horizontal: false, vertical: true)

                switch viewModel.bundleIdCapabilitiesState {
                case .idle, .loading:
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("Loading capabilities…")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                    }
                case .error(let message):
                    BundleIDStatusMessage(
                        symbol: "exclamationmark.triangle.fill",
                        tint: ShipyardTheme.dangerBorder,
                        surface: ShipyardTheme.dangerSurface,
                        title: "Couldn't load capabilities",
                        message: message
                    )
                    Button("Retry") {
                        viewModel.retryBundleIdCapabilities(for: bundleId)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                case .empty:
                    Text("No capabilities are enabled on this identifier.")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                    enableButton
                case .loaded(let capabilities):
                    BundleIDResourceTable(
                        headers: ["Capability", "Enabled", "Advanced setup · manual"],
                        // A capability is enabled by existing at all, so
                        // every returned row is "On" (Figma 114-2315).
                        rows: capabilities.map { capability in
                            let option = CapabilityTypeOption(rawValue: capability.capabilityType ?? "")
                            return [
                                option?.displayName ?? capability.capabilityType ?? "Unknown capability",
                                "On",
                                (option?.needsManualAppleSetup ?? true) ? "apple" : "",
                            ]
                        },
                        linkColumn: 2,
                        linkLabels: capabilities.map { capability in
                            (CapabilityTypeOption(rawValue: capability.capabilityType ?? "")?
                                .needsManualAppleSetup ?? true) ? "Apple Developer ↗" : ""
                        },
                        linkActions: capabilities.map { capability in
                            (CapabilityTypeOption(rawValue: capability.capabilityType ?? "")?
                                .needsManualAppleSetup ?? true)
                                ? { openAppleDeveloper() }
                                : nil
                        },
                        disableColumn: 1,
                        disableLabels: capabilities.map { capability in
                            optionDisplay(capability)
                        },
                        disableActions: capabilities.map { capability in
                            { onDisableCapability(capability) }
                        }
                    )
                    enableButton
                }
            }
        }
    }

    /// Enable is the inverse of the per-row disable action: one add
    /// affordance below the table rather than a button on all 27 rows.
    private var enableButton: some View {
        Button("Enable capability…") { onEnableCapability() }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private func optionDisplay(_ capability: BundleIdCapabilityModel) -> String {
        CapabilityTypeOption(rawValue: capability.capabilityType ?? "")?.displayName
            ?? capability.capabilityType ?? "capability"
    }

    private func openAppleDeveloper() {
        // Design's "Apple Developer ↗" — the manual half of these
        // capabilities (APNs keys, iCloud/App Group containers).
        guard let url = URL(string: "https://developer.apple.com/account/resources/identifiers/list") else { return }
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }

    // MARK: Action bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            Text(actionBarStatus)
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .lineLimit(1)
            Spacer()
            Button("Delete Bundle ID…") {
                onDelete(bundleId)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundColor(ShipyardTheme.dangerBorder)
            .disabled(isSaving)
            Button("Revert") {
                nameDraft = savedName
                saveError = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!isDirty || isSaving)
            Button("Save") {
                save()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!isDirty || isSaving)
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(LaunchTheme.page)
    }

    private var actionBarStatus: String {
        let sync = viewModel.lastSyncText(for: .bundleIds) ?? "Not synced yet"
        return "\(sync) · \(teamName)"
    }

    private func save() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            saveError = "Enter a name for the bundle ID."
            toastCenter.show("Couldn't rename Bundle ID", detail: "Enter a name for the bundle ID.", variant: .error)
            return
        }
        isSaving = true
        saveError = nil
        Task { @MainActor in
            let result = await viewModel.renameBundleId(bundleId, newName: trimmed)
            isSaving = false
            switch result {
            case .success:
                // The state update lands inside renameBundleId before this
                // await returns, so onChange(of: savedName) fires while
                // isSaving is still true and is skipped — adopt the
                // normalized value here so the field doesn't keep the
                // untrimmed draft.
                nameDraft = trimmed
                toastCenter.show("Bundle ID renamed", detail: trimmed, variant: .success)
            case .failure(let message):
                saveError = message
                toastCenter.show("Couldn't rename Bundle ID", detail: message, variant: .error)
            case .ignored:
                break
            }
        }
    }
}

// MARK: - Sheets (114-2622 / 114-2665 / 114-2700 / 114-2728)

/// Enable a capability — POST /v1/bundleIdCapabilities.
///
/// Mirrors the disable sheet's posture (the same entitlement/profiles
/// warning applies in reverse) but has no Figma node of its own, so it
/// follows the disable sheet's structure rather than inventing a layout.
/// Only capabilities not already enabled are offered: the API has no
/// update-by-create and enabling a duplicate is a 409-class error.
private struct BundleIDEnableCapabilitySheet: View {
    @ObservedObject var viewModel: ResourcesViewModel
    @EnvironmentObject private var toastCenter: ShipyardToastCenter
    let bundleId: BundleIdModel

    @Environment(\.dismiss) private var dismiss
    @State private var selection: CapabilityTypeOption?
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// Already-enabled types, so they're filtered out of the picker.
    private var enabledTypes: Set<String> {
        Set((viewModel.bundleIdCapabilitiesState.loadedValue ?? [])
            .compactMap { $0.capabilityType })
    }

    private var available: [CapabilityTypeOption] {
        CapabilityTypeOption.allCases.filter { !enabledTypes.contains($0.rawValue) }
    }

    private var profiles: [ProfileModel] {
        viewModel.bundleIdProfilesState.loadedValue ?? []
    }

    var body: some View {
        BundleIDSheetChrome(title: "Enable a capability?", onClose: { dismiss() }) {
            VStack(alignment: .leading, spacing: 16) {
                BundleIDStatusMessage(
                    symbol: "exclamationmark.triangle.fill",
                    tint: ShipyardTheme.warningBorder,
                    surface: ShipyardTheme.warningSurface,
                    title: impactTitle,
                    message: "Enabling a capability adds an entitlement to the identifier. Existing profile files will not pick it up — regenerate them after this change."
                )

                BundleIDFormSection(title: "Capability") {
                    if available.isEmpty {
                        Text("All \(CapabilityTypeOption.allCases.count) capabilities are already enabled on this identifier.")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                    } else {
                        Picker("Capability", selection: $selection) {
                            Text("Select a capability…").tag(nil as CapabilityTypeOption?)
                            ForEach(available, id: \.rawValue) { option in
                                Text(option.displayName).tag(option as CapabilityTypeOption?)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                    }
                }

                if let errorMessage {
                    BundleIDStatusMessage(
                        symbol: "exclamationmark.triangle.fill",
                        tint: ShipyardTheme.dangerBorder,
                        surface: ShipyardTheme.dangerSurface,
                        title: "Couldn't enable capability",
                        message: errorMessage
                    )
                }

                HStack(spacing: 12) {
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isSaving)
                    Button("Enable Capability") { enable() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(selection == nil || isSaving || available.isEmpty)
                }
            }
        }
    }

    private var impactTitle: String {
        profiles.isEmpty
            ? "No profiles to regenerate"
            : "\(profiles.count) profile\(profiles.count == 1 ? "" : "s") will need recreating"
    }

    private func enable() {
        guard let selection, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task { @MainActor in
            let result = await viewModel.enableCapability(selection, for: bundleId)
            isSaving = false
            switch result {
            case .success:
                // Refetch already happened in the view model; only close on
                // success so a failure keeps the picker and error visible.
                dismiss()
                toastCenter.show(
                    "Capability updated",
                    detail: selection.displayName,
                    variant: .success)
            case .failure(let message):
                errorMessage = message
                toastCenter.show("Couldn't update capability", detail: message, variant: .error)
            case .ignored:
                break
            }
        }
    }
}

/// Figma 114-2622 — disabling a capability changes entitlements, so the
/// sheet names the affected profiles and requires an explicit ack.
private struct BundleIDDisableCapabilitySheet: View {
    @ObservedObject var viewModel: ResourcesViewModel
    @EnvironmentObject private var toastCenter: ShipyardToastCenter
    let bundleId: BundleIdModel
    let capability: BundleIdCapabilityModel
    var onOpenProfile: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var acknowledged = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var capabilityName: String {
        CapabilityTypeOption(rawValue: capability.capabilityType ?? "")?.displayName
            ?? capability.capabilityType ?? "capability"
    }

    private var profiles: [ProfileModel] {
        viewModel.bundleIdProfilesState.loadedValue ?? []
    }

    var body: some View {
        BundleIDSheetChrome(title: "Disable \(capabilityName)?") {
            BundleIDStatusMessage(
                symbol: "exclamationmark.triangle.fill",
                tint: ShipyardTheme.warningBorder,
                surface: ShipyardTheme.warningSurface,
                title: impactTitle,
                message: "The app must stop requesting the removed entitlement when signed with recreated profiles. Existing profile files will not update automatically."
            )

            Toggle(isOn: $acknowledged) {
                Text("I will update app entitlements and recreate profiles")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.title)
            }
            .toggleStyle(.checkbox)
            .disabled(isSaving)

            if !profiles.isEmpty {
                BundleIDResourceTable(
                    headers: ["Affected profile", "Type", "Impact", "Jump"],
                    rows: profiles.map { profile in
                        [
                            profile.name ?? "Untitled profile",
                            ProfileTypeOption(rawValue: profile.profileType ?? "")?.displayName
                                ?? profile.profileType ?? "—",
                            "Recreate after entitlement changes",
                            "",
                        ]
                    },
                    linkColumn: 3,
                    linkLabels: profiles.map { _ in "Open Profile →" },
                    linkActions: profiles.map { profile in { onOpenProfile(profile.name ?? profile.id) } }
                )
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.danger)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isSaving)
                Button("Disable Capability") {
                    disable()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!acknowledged || isSaving)
            }
        }
    }

    private var impactTitle: String {
        profiles.isEmpty
            ? "No profiles are affected"
            : "Entitlement change affects \(profiles.count) profile\(profiles.count == 1 ? "" : "s")"
    }

    private func disable() {
        isSaving = true
        errorMessage = nil
        Task { @MainActor in
            let result = await viewModel.disableCapability(capability, for: bundleId)
            isSaving = false
            switch result {
            case .success:
                dismiss()
                toastCenter.show("Capability disabled", detail: capabilityName, variant: .success)
            case .failure(let message):
                errorMessage = message
                toastCenter.show("Couldn't disable capability", detail: message, variant: .error)
            case .ignored:
                break
            }
        }
    }
}

/// Figma 114-2665 — DELETE /v1/bundleIds/{id} documents no 409, so this
/// sheet is driven by the dependency pre-check, not by a caught status.
private struct BundleIDDeleteBlockedSheet: View {
    let identifier: String
    let dependencies: [ResourcesViewModel.BundleIdDependency]
    var errorMessage: String?
    var onOpenApp: (String) -> Void
    var onOpenProfile: (String) -> Void
    var onClose: () -> Void

    var body: some View {
        BundleIDSheetChrome(title: "Cannot delete \(identifier)") {
            BundleIDStatusMessage(
                symbol: "hand.raised.fill",
                tint: ShipyardTheme.dangerBorder,
                surface: ShipyardTheme.dangerSurface,
                title: "Deletion blocked by dependencies",
                message: dependencySummary
            )

            BundleIDResourceTable(
                headers: ["Dependency", "Reason", "Jump"],
                rows: dependencies.map { [$0.name, $0.reason, ""] },
                linkColumn: 2,
                linkLabels: dependencies.map { $0.jumpLabel },
                linkActions: dependencies.map { dependency in
                    {
                        switch dependency.kind {
                        case .app:
                            onOpenApp(dependency.name)
                        case .profile:
                            onOpenProfile(dependency.name)
                        }
                    }
                }
            )

            if let errorMessage {
                BundleIDStatusMessage(
                    symbol: "exclamationmark.triangle.fill",
                    tint: ShipyardTheme.dangerBorder,
                    surface: ShipyardTheme.dangerSurface,
                    title: "Delete failed",
                    message: errorMessage
                )
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Close", action: onClose)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                // Deliberately inert: the design keeps the destructive
                // action visible but disabled while dependencies exist.
                Button("Delete Bundle ID", action: onClose)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(true)
            }
        }
    }

    private var dependencySummary: String {
        let apps = dependencies.filter { $0.kind == .app }.count
        let profiles = dependencies.filter { $0.kind == .profile }.count
        var parts: [String] = []
        if apps > 0 {
            parts.append("\(apps) app\(apps == 1 ? "" : "s")")
        }
        if profiles > 0 {
            parts.append("\(profiles) provisioning profile\(profiles == 1 ? "" : "s")")
        }
        return "This identifier is associated with \(parts.joined(separator: " and ")). Remove eligible dependencies in Apple before attempting deletion."
    }
}

/// Figma 114-2700 — no dependencies found, so the destructive action is
/// gated behind typing the identifier.
private struct BundleIDDeleteConfirmSheet: View {
    let identifier: String
    @Binding var confirmText: String
    let isDeleting: Bool
    var errorMessage: String?
    var onCancel: () -> Void
    var onDelete: () -> Void

    private var matches: Bool {
        confirmText.trimmingCharacters(in: .whitespacesAndNewlines) == identifier
    }

    var body: some View {
        BundleIDSheetChrome(title: "Delete unused bundle identifier?") {
            BundleIDStatusMessage(
                symbol: "exclamationmark.triangle.fill",
                tint: ShipyardTheme.warningBorder,
                surface: ShipyardTheme.warningSurface,
                title: "Delete \(identifier)",
                message: "No associated app or dependent profiles were found in this scenario. Deletion cannot be undone; Apple may still reject the request if dependencies have changed."
            )

            VStack(alignment: .leading, spacing: 12) {
                Text("Confirm identifier")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                Text("This does not delete any app or app record. Only the identifier above is removed.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Type identifier to confirm")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.title)
                    TextField("Type identifier to confirm", text: $confirmText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .disabled(isDeleting)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(ShipyardTheme.tableBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(matches ? ShipyardTheme.success : ShipyardTheme.rowDivider, lineWidth: 1)
                        )
                }
            }

            if let errorMessage {
                BundleIDStatusMessage(
                    symbol: "exclamationmark.triangle.fill",
                    tint: ShipyardTheme.dangerBorder,
                    surface: ShipyardTheme.dangerSurface,
                    title: "Delete failed",
                    message: errorMessage
                )
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isDeleting)
                Button("Delete Bundle ID", action: onDelete)
                    .buttonStyle(.borderedProminent)
                    .tint(ShipyardTheme.dangerBorder)
                    .controlSize(.small)
                    .disabled(!matches || isDeleting)
            }
        }
    }
}

/// Figma 114-2728 — post-delete confirmation.
private struct BundleIDDeletedSheet: View {
    let identifier: String
    var onReturn: () -> Void

    var body: some View {
        BundleIDSheetChrome(title: "Unused bundle identifier deleted") {
            BundleIDStatusMessage(
                symbol: "checkmark.circle.fill",
                tint: ShipyardTheme.successBorder,
                surface: ShipyardTheme.successSurface,
                title: "\(identifier) removed",
                message: "Any apps and related identifiers are unchanged. No profiles were affected."
            )
            HStack {
                Spacer()
                Button("Return to Bundle IDs", action: onReturn)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }
}

// MARK: - Shared sheet/detail building blocks

/// "MVP · Bundle IDs · <team>" context strip with a close affordance —
/// every module 04 sheet carries it.
struct BundleIDSheetChrome<Content: View>: View {
    let title: String
    /// Nil falls back to `dismiss()` — used by sheets the parent does not
    /// track (capability disable), while the delete sheets must reset
    /// their own presentation state instead.
    var onClose: (() -> Void)?
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss

    private var teamName: String {
        CredentialStorage.shared.selectedTeam?.key ?? "No Team"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("MVP · Bundle IDs · \(teamName)")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                Spacer()
                Button {
                    if let onClose {
                        onClose()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 24)
            .frame(height: 40)
            .background(ShipyardTheme.sidebarBackground)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    content
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(ShipyardTheme.tableBackground)
        }
    }
}

/// Titled card section ("General", "Dependent profiles", "Capabilities").
struct BundleIDFormSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Bordered status banner (info / warning / danger / success).
struct BundleIDStatusMessage: View {
    let symbol: String
    let tint: Color
    let surface: Color
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundColor(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(tint)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(surface)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.6), lineWidth: 1)
        )
    }
}

/// Header + body table used by the dependency / profile / capability
/// tables. `linkColumn` renders an optional action link per row.
struct BundleIDResourceTable: View {
    let headers: [String]
    let rows: [[String]]
    var linkColumn: Int?
    var linkLabels: [String] = []
    var linkActions: [(() -> Void)?] = []
    /// Column whose cells double as a "Disable…" action button.
    var disableColumn: Int?
    var disableLabels: [String] = []
    var disableActions: [() -> Void] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    Text(header)
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(ShipyardTheme.tableHeader)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 12) {
                    ForEach(Array(row.enumerated()), id: \.offset) { column, value in
                        cell(column: column, value: value, rowIndex: index)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(minHeight: 38)
                .background(index.isMultiple(of: 2) ? ShipyardTheme.readOnlyField : ShipyardTheme.tableBackground)

                if index < rows.count - 1 {
                    ShipyardTheme.rowDivider.frame(height: 1)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ShipyardTheme.rowDivider, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func cell(column: Int, value: String, rowIndex: Int) -> some View {
        if linkColumn == column, rowIndex < linkLabels.count, !linkLabels[rowIndex].isEmpty {
            Button {
                guard rowIndex < linkActions.count else { return }
                linkActions[rowIndex]?()
            } label: {
                Text(linkLabels[rowIndex])
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.accent)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if disableColumn == column, rowIndex < disableLabels.count {
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
                Spacer(minLength: 4)
                Button("Disable…") {
                    guard rowIndex < disableActions.count else { return }
                    disableActions[rowIndex]()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.dangerBorder)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.title)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// `IOS` / `MAC_OS` / `UNIVERSAL` are spec codes, not labels. Internal
/// because the register confirmation reports the platform it created.
func bundlePlatformDisplay(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else { return "—" }
    if let option = BundleIdPlatformOption(rawValue: raw) {
        return option.displayName
    }
    return shipyardPlatformDisplay(raw)
}
