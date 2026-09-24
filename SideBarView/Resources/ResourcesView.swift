//
//  ResourcesView.swift
//  App Store
//
//  Batch C2: team-scoped Resources section in the sidebar (like AppDab's
//  Resources group), shown below the apps list when the extended-info flag
//  is on. Tapping a kind opens a sheet with the read-only list.
//
//  Batch G (#10): device register/enable/disable (POST/PATCH /v1/devices —
//  no DELETE exists; disable is the API's revoke) and certificate
//  create/revoke (POST/DELETE /v1/certificates). Needs an Admin key;
//  TestFlight-only keys 403.
//
//  Batch F (#6): per-kind search field in the list sheet (local filter),
//  "No matches" state, and a filtering-aware row count in the header.
//
//  Batch F fix: the sheet window is bounded to the screen (width capped
//  too) and resizable; the Resources group starts expanded.
//
//  Batch F review fixes: the height cap resolves from the presenting
//  window's screen instead of NSScreen.main, and the no-matches view
//  hints that more matches may exist on unloaded pages.
//

import SwiftUI

/// Sidebar section listing the five team-scoped resource kinds.
struct ResourcesSectionView: View {
    @ObservedObject var viewModel: ResourcesViewModel
    /// Team apps for the single-app invite picker — threaded from the
    /// sidebar's already-loaded list, no extra fetch.
    var apps: [AppsData] = []
    // Starts expanded — one less tap to reach the five resource rows
    // (intentional Batch F default, confirmed in review).
    @State private var isExpanded = true
    @State private var selectedKind: ResourcesViewModel.Kind?

    var body: some View {
        VStack(spacing: 2) {
            // Button (not .onTapGesture) so the header is keyboard- and
            // VoiceOver-actionable; full-width contentShape so gaps
            // between subviews still hit. Standard macOS chevron: down
            // when collapsed, up when expanded.
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                    Image(systemName: "shippingbox")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                    Text("Resources")
                        .font(.appBody)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("Team-wide")
                        .font(.appCaption2)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Resources")
            .accessibilityHint(isExpanded ? "Collapses the resources section" : "Expands the resources section")
            .accessibilityAddTraits(.isHeader)
            if isExpanded {
                ForEach(ResourcesViewModel.Kind.allCases) { kind in
                    Button {
                        selectedKind = kind
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: kind.systemImage)
                                .font(.appCaption)
                                .foregroundColor(.secondary)
                                .frame(width: 16)
                            Text(kind.displayName)
                                .font(.appBody)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.appCaption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(kind.displayName)")
                }
            }
        }
        .padding(.top, 2)
        
        .sheet(item: $selectedKind) { kind in
            ResourceListContentView(kind: kind, viewModel: viewModel, apps: apps)
        }
    }
}

/// Read-only list for a single resource kind, with cursor pagination.
struct ResourceListContentView: View {
    let kind: ResourcesViewModel.Kind
    @ObservedObject var viewModel: ResourcesViewModel
    /// Team apps for the single-app invite picker.
    var apps: [AppsData] = []
    @Environment(\.dismiss) private var dismiss
    // Batch G (#10): write forms toggle from the header.
    @State private var showRegisterDeviceForm = false
    @State private var showCreateCertificateForm = false
    // Batch I (I2): bundle ID create form toggles from the header.
    @State private var showCreateBundleIdForm = false
    // Batch I (I3): user invite form toggles from the header.
    @State private var showInviteUserForm = false
    // Batch I (I4): profile create form toggles from the header.
    @State private var showCreateProfileForm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if kind == .devices, showRegisterDeviceForm {
                RegisterDeviceForm(viewModel: viewModel) {
                    showRegisterDeviceForm = false
                }
                Divider()
            }
            if kind == .certificates, showCreateCertificateForm {
                CreateCertificateForm(viewModel: viewModel) {
                    showCreateCertificateForm = false
                }
                Divider()
            }
            if kind == .bundleIds, showCreateBundleIdForm {
                CreateBundleIdForm(viewModel: viewModel) {
                    showCreateBundleIdForm = false
                }
                Divider()
            }
            if kind == .users, showInviteUserForm {
                InviteUserForm(viewModel: viewModel, apps: apps) {
                    showInviteUserForm = false
                }
                Divider()
            }
            if kind == .profiles, showCreateProfileForm {
                CreateProfileForm(viewModel: viewModel) {
                    showCreateProfileForm = false
                }
                Divider()
            }
            content
        }
        // min→max ranges make the sheet window resizable; the screen-
        // derived height cap keeps it fully on screen. Without a cap the
        // ScrollView's ideal height sizes the window past the bottom edge
        // (Load-more footer unreachable; scrolling just moves content
        // inside the off-screen part of the window).
        .frame(minWidth: 480, idealWidth: 540, maxWidth: 720,
               minHeight: 420, idealHeight: 560, maxHeight: maxSheetHeight)
        .onAppear {
            viewModel.load(kind)
            if kind == .users {
                viewModel.loadInvitations()
            }
        }
    }

    /// Height cap from the *presenting* window's screen: the sheet's body
    /// evaluates before the sheet window exists, so the key window (the
    /// presenter) is the right multi-display anchor — NSScreen.main can
    /// point elsewhere when the body runs before the sheet is keyed.
    /// Attached sheets are modal, so the host can't move mid-presentation.
    private var maxSheetHeight: CGFloat {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        return max(460, (screen?.visibleFrame.height ?? 1_000) - 120)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label(kind.displayName, systemImage: kind.systemImage)
                .font(.subheader)
                .fontWeight(.semibold)
            Spacer()
            if let total = viewModel.totals[kind] {
                // Local search only covers loaded rows — show "N of M loaded"
                // while filtering so the count can't read as a server total.
                if viewModel.hasActiveSearch(for: kind) {
                    Text("\(viewModel.filteredCount(for: kind)) of \(viewModel.loadedCount(for: kind)) loaded")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(total) total")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                }
            }
            Button(action: { viewModel.retry(kind) }) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.appCaption)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Refresh \(kind.displayName)")
            // Batch G (#10): writes need an Admin key; TestFlight-only keys
            // 403. Forms stay available so the 403 hint is discoverable.
            if kind == .devices {
                Button {
                    showRegisterDeviceForm.toggle()
                } label: {
                    Label("Register", systemImage: "plus")
                        .font(.appCaption)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Register a device")
            }
            if kind == .certificates {
                Button {
                    showCreateCertificateForm.toggle()
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.appCaption)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Create a certificate")
            }
            if kind == .bundleIds {
                Button {
                    showCreateBundleIdForm.toggle()
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.appCaption)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Register a bundle ID")
            }
            if kind == .users {
                Button {
                    showInviteUserForm.toggle()
                } label: {
                    Label("Invite", systemImage: "plus")
                        .font(.appCaption)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Invite a user")
            }
            if kind == .profiles {
                Button {
                    showCreateProfileForm.toggle()
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.appCaption)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Create a provisioning profile")
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .clipShape(Circle())
            .help("Close (Esc)")
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.secondaryBackground)
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch listState.state {
        case .idle, .loading:
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                    .scaleEffect(1.1)
                Text("Loading \(kind.displayName.lowercased())...")
                    .font(.appBody)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        case .empty:
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: kind.systemImage)
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("No \(kind.displayName.lowercased()) found")
                    .font(.subheader)
                Text(kind.subtitle)
                    .font(.appBody)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        case .error(let message):
            ErrorRetryView(
                title: "Couldn't Load \(kind.displayName)",
                message: message,
                retryTitle: "Retry"
            ) {
                viewModel.retry(kind)
            }
        case .loaded:
            VStack(spacing: 0) {
                searchField
                Divider()
                if viewModel.hasActiveSearch(for: kind), viewModel.filteredCount(for: kind) == 0 {
                    noMatchesView
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            rows
                        }
                        .padding(12)
                    }
                }
                // Pinned outside the ScrollView (same as the Builds tab's
                // "Load More Builds"): an inline footer scrolls away with
                // the rows, so Load-more seemed to disappear after
                // scrolling. Hidden while the invite form is open — the
                // footer belongs to the list, not the form.
                if !(kind == .users && showInviteUserForm) {
                    paginationFooter
                }
            }
        }
    }

    // MARK: - Search (Batch F #6)

    /// Same capsule style as the sidebar's app search field.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.appCaption)
                .accessibilityHidden(true)

            TextField("Search \(kind.displayName.lowercased())", text: viewModel.searchBinding(for: kind))
                .textFieldStyle(.plain)
                .font(.appBody)

            if !viewModel.searchText(for: kind).isEmpty {
                Button {
                    viewModel.searchBinding(for: kind).wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.appCaption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .help("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.textBackgroundColor)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Shown when loaded rows exist but none match the active query.
    private var noMatchesView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No Matches")
                .font(.subheader)
                .fontWeight(.medium)
            Text("No \(kind.displayName.lowercased()) match \"\(viewModel.searchText(for: kind))\"")
                .font(.appBody)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            if viewModel.nextCursors[kind] != nil {
                // Search is local — matches may still exist on pages that
                // haven't been loaded yet (review finding).
                Text("More results may exist on unloaded pages — try Load more below")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Clear Search") {
                viewModel.searchBinding(for: kind).wrappedValue = ""
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var rows: some View {
        switch kind {
        case .devices:
            ForEach(viewModel.filteredDevices, id: \.id) { device in
                DeviceRow(device: device, viewModel: viewModel)
            }
        case .certificates:
            ForEach(viewModel.filteredCertificates, id: \.id) { certificate in
                CertificateRow(certificate: certificate, viewModel: viewModel)
            }
        case .bundleIds:
            ForEach(viewModel.filteredBundleIds, id: \.id) { bundleId in
                BundleIdRow(bundleId: bundleId, viewModel: viewModel)
            }
        case .profiles:
            ForEach(viewModel.filteredProfiles, id: \.id) { profile in
                ProfileRow(profile: profile, viewModel: viewModel)
            }
        case .users:
            // Pending (unaccepted) invites render first, then accepted
            // users — no separate section. A failed invites fetch
            // surfaces as a retry row so it never blocks the users list.
            ForEach(viewModel.filteredInvitations, id: \.id) { invitation in
                InvitationRow(invitation: invitation, viewModel: viewModel)
            }
            ForEach(viewModel.filteredUsers, id: \.id) { user in
                UserRow(user: user, viewModel: viewModel)
            }
            if case .error(let message) = viewModel.invitationsState {
                HStack {
                    Text("Couldn't load pending invitations: \(message)")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Retry") { viewModel.loadInvitations() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
            }
        }
    }

    /// Type-erased access to the kind's ViewState for the switch above.
    private var listState: ViewStateListState {
        switch kind {
        case .devices: return ViewStateListState(viewModel.devicesState)
        case .certificates: return ViewStateListState(viewModel.certificatesState)
        case .bundleIds: return ViewStateListState(viewModel.bundleIdsState)
        case .profiles: return ViewStateListState(viewModel.profilesState)
        case .users: return ViewStateListState(viewModel.usersState)
        }
    }

    @ViewBuilder private var paginationFooter: some View {
        if let nextCursor = viewModel.nextCursors[kind] {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Spacer()
                    if viewModel.paginationFailedKinds.contains(kind) {
                        Button("Couldn't load more — Retry") {
                            viewModel.loadMore(kind, cursor: nextCursor)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else if kind == .users && viewModel.isPaginatingKinds.contains(kind) {
                        // Users auto-drain: show progress, not a dead button
                        // (taps during the drain are ignored by the guard).
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading all users… (\(viewModel.loadedCount(for: kind)) so far)")
                            .font(.appCaption)
                            .foregroundColor(.secondary)
                    } else {
                        Button("Load more") {
                            viewModel.loadMore(kind, cursor: nextCursor)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            // Chrome background so rows never peek through behind the pinned bar.
            .background(AppTheme.secondaryBackground)
        }
    }
}

/// Minimal type-erased ViewState for the shared list shell — enough to
/// drive idle/loading/empty/error/loaded rendering without duplicating the
/// switch per kind.
struct ViewStateListState {
    enum State {
        case idle
        case loading
        case empty
        case loaded
        case error(String)
    }

    let state: State

    init<T>(_ viewState: ViewState<T>) {
        switch viewState {
        case .idle: state = .idle
        case .loading: state = .loading
        case .empty: state = .empty
        case .error(let message): state = .error(message)
        case .loaded: state = .loaded
        }
    }
}

// MARK: - Write forms (Batch G #10)

// Forms stay open on failure so typed input is never silently discarded
// (same contract as the review ReplySection); on success the caller
// collapses the form and the new row appears at the top of the list.

/// POST /v1/devices — name, platform (spec enum BundleIdPlatform) and UDID
/// are all required. Needs an Admin key role; a TestFlight-only key 403s.
private struct RegisterDeviceForm: View {
    @ObservedObject var viewModel: ResourcesViewModel
    var onDone: () -> Void
    @State private var name = ""
    @State private var platform: DevicePlatform = .IOS
    @State private var udid = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Register Device")
                .font(.appBody)
                .fontWeight(.medium)
            TextField("Device name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.appBody)
                .disabled(isSaving)
            HStack {
                Picker("Platform", selection: $platform) {
                    ForEach(DevicePlatform.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
                .disabled(isSaving)
                Spacer()
            }
            TextField("UDID (40 hex characters, or 8-8-9 hex groups with dashes)", text: $udid)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .disabled(isSaving)
            Text("Needs an API key with the Admin role. Verify with a throwaway device first — registrations count against the yearly device limit.")
                .font(.appCaption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let errorMessage {
                Text(errorMessage)
                    .font(.appCaption)
                    .foregroundColor(AppTheme.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel") { onDone() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.secondary)
                    .disabled(isSaving)
                Spacer()
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button("Register") {
                        Task { @MainActor in
                            isSaving = true
                            defer { isSaving = false }
                            let result = await viewModel.registerDevice(
                                name: name, platform: platform, udid: udid)
                            if case .success = result {
                                onDone()
                            } else if case .failure(let message) = result {
                                // .ignored: duplicate in flight / cancelled —
                                // keep the form open, nothing was registered.
                                errorMessage = message
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || udid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(12)
        .background(AppTheme.windowBackground)
    }
}

/// POST /v1/certificates — certificate type plus pasted CSR content
/// (Keychain Access → Request a Certificate, or `openssl req -new`).
private struct CreateCertificateForm: View {
    @ObservedObject var viewModel: ResourcesViewModel
    var onDone: () -> Void
    @State private var certificateType: CertificateTypeOption = .IOS_DEVELOPMENT
    @State private var csrContent = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New Certificate")
                .font(.appBody)
                .fontWeight(.medium)
            Picker("Type", selection: $certificateType) {
                ForEach(CertificateTypeOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            .disabled(isSaving)
            TextEditor(text: $csrContent)
                .font(.system(size: 11, design: .monospaced))
                .frame(minHeight: 70, maxHeight: 120)
                .border(AppTheme.border, width: 1)
                .accessibilityLabel("Certificate signing request content")
                .disabled(isSaving)
            Text("Paste the CSR content. Needs an API key with the Admin role.")
                .font(.appCaption2)
                .foregroundColor(.secondary)
            if let errorMessage {
                Text(errorMessage)
                    .font(.appCaption)
                    .foregroundColor(AppTheme.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel") { onDone() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.secondary)
                    .disabled(isSaving)
                Spacer()
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button("Create") {
                        Task { @MainActor in
                            isSaving = true
                            defer { isSaving = false }
                            let result = await viewModel.createCertificate(
                                certificateType: certificateType, csrContent: csrContent)
                            if case .success = result {
                                onDone()
                            } else if case .failure(let message) = result {
                                // .ignored: duplicate in flight / cancelled —
                                // keep the form open, nothing was created.
                                errorMessage = message
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(csrContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(12)
        .background(AppTheme.windowBackground)
    }
}

/// POST /v1/bundleIds — name, identifier and platform are required;
/// seedId is optional. Needs an Admin key role; a TestFlight-only key 403s.
private struct CreateBundleIdForm: View {
    @ObservedObject var viewModel: ResourcesViewModel
    var onDone: () -> Void
    @State private var name = ""
    @State private var identifier = ""
    @State private var platform: BundleIdPlatformOption = .IOS
    @State private var seedId = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New Bundle ID")
                .font(.appBody)
                .fontWeight(.medium)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.appBody)
                .disabled(isSaving)
            TextField("Bundle identifier (e.g. com.example.app)", text: $identifier)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .disabled(isSaving)
            HStack {
                Picker("Platform", selection: $platform) {
                    ForEach(BundleIdPlatformOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
                .disabled(isSaving)
                Spacer()
            }
            TextField("Seed ID (optional)", text: $seedId)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .disabled(isSaving)
            Text("Test on a throwaway identifier first. Needs an API key with the Admin role.")
                .font(.appCaption2)
                .foregroundColor(.secondary)
            if let errorMessage {
                Text(errorMessage)
                    .font(.appCaption)
                    .foregroundColor(AppTheme.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel") { onDone() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.secondary)
                    .disabled(isSaving)
                Spacer()
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button("Create") {
                        Task { @MainActor in
                            isSaving = true
                            defer { isSaving = false }
                            let result = await viewModel.createBundleId(
                                name: name,
                                identifier: identifier,
                                platform: platform,
                                seedId: seedId)
                            if case .success = result {
                                onDone()
                            } else if case .failure(let message) = result {
                                // .ignored: duplicate in flight / cancelled —
                                // keep the form open, nothing was created.
                                errorMessage = message
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(12)
        .background(AppTheme.windowBackground)
    }
}

/// Inline multi-select for user roles — used by the per-row role editor
/// (tighter space than the dropdown, same UserRoleOption source so the
/// two can't drift).
private struct RoleMultiSelect: View {
    @Binding var selection: Set<UserRoleOption>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(UserRoleOption.allCases, id: \.self) { role in
                Toggle(role.displayName, isOn: Binding(
                    get: { selection.contains(role) },
                    set: { isOn in
                        if isOn { selection.insert(role) } else { selection.remove(role) }
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.appBody)
            }
        }
    }
}

/// Dropdown multi-select for user roles — a Menu of checkable items so
/// eleven roles don't stretch the invite form.
private struct RoleDropdownMenu: View {
    @Binding var selection: Set<UserRoleOption>

    private var label: String {
        switch selection.count {
        case 0: return "Select roles"
        case 1: return selection.first?.displayName ?? "Select roles"
        default: return "\(selection.count) roles selected"
        }
    }

    var body: some View {
        Menu {
            ForEach(UserRoleOption.allCases, id: \.self) { role in
                Toggle(role.displayName, isOn: Binding(
                    get: { selection.contains(role) },
                    set: { isOn in
                        if isOn { selection.insert(role) } else { selection.remove(role) }
                    }
                ))
            }
        } label: {
            Text(label)
                .font(.appBody)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(AppTheme.textBackgroundColor)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}

/// POST /v1/userInvitations — email, names and at least one role are
/// required. Resend re-issues a pending invite with the form's details
/// (find by email → delete → re-create; no dedicated resend endpoint).
/// Needs an Admin key role; a TestFlight-only key 403s.
private struct InviteUserForm: View {
    @ObservedObject var viewModel: ResourcesViewModel
    /// Team apps for single-app invites (allAppsVisible == false).
    var apps: [AppsData] = []
    var onDone: () -> Void
    @State private var email = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var roles: Set<UserRoleOption> = [.DEVELOPER]
    @State private var allAppsVisible = true
    @State private var selectedAppIds: Set<String> = []
    @State private var provisioningAllowed = false
    @State private var isSaving = false
    @State private var isResending = false
    @State private var errorMessage: String?
    @State private var noticeMessage: String?

    private var isBusy: Bool { isSaving || isResending }

    /// App ids for the invite body: empty = all apps.
    private var visibleAppIds: [String] {
        guard !allAppsVisible else { return [] }
        return selectedAppIds.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Invite User")
                .font(.appBody)
                .fontWeight(.medium)
            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .font(.appBody)
                .disabled(isBusy)
            HStack(spacing: 8) {
                TextField("First name", text: $firstName)
                    .textFieldStyle(.roundedBorder)
                    .font(.appBody)
                    .disabled(isBusy)
                TextField("Last name", text: $lastName)
                    .textFieldStyle(.roundedBorder)
                    .font(.appBody)
                    .disabled(isBusy)
            }
            Text("Roles")
                .font(.appCaption)
                .foregroundColor(.secondary)
            RoleDropdownMenu(selection: $roles)
                .disabled(isBusy)
            Toggle("All apps visible", isOn: $allAppsVisible)
                .font(.appBody)
                .disabled(isBusy)
                .onChange(of: allAppsVisible) { _, newValue in
                    // Turning all-apps back on drops the per-app picks so
                    // stale ids can never leak into an all-apps invite.
                    if newValue { selectedAppIds = [] }
                }
            if !allAppsVisible {
                ChecklistDropdownMenu(
                    title: "Apps",
                    items: apps.map { app in
                        let name = app.name ?? app.bundleId ?? app.id
                        return ChecklistDropdownMenu.Item(
                            id: app.id,
                            title: name,
                            subtitle: app.name == nil ? nil : app.bundleId
                        )
                    },
                    selection: $selectedAppIds,
                    emptyHint: "No apps loaded — open the sidebar app list first so the picker has something to offer.",
                    allowsSelectAll: true
                )
                .disabled(isBusy)
            }
            Toggle("Provisioning allowed", isOn: $provisioningAllowed)
                .font(.appBody)
                .disabled(isBusy)
            Text("Needs an API key with the Admin role. Invites count against the team member limit.")
                .font(.appCaption2)
                .foregroundColor(.secondary)
            if let noticeMessage {
                Text(noticeMessage)
                    .font(.appCaption)
                    .foregroundColor(.secondary)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.appCaption)
                    .foregroundColor(AppTheme.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel") { onDone() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.secondary)
                    .disabled(isBusy)
                Spacer()
                if isBusy {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button("Resend") {
                        Task { @MainActor in
                            await runInvite(mode: .resend)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!canSubmit)
                    .help("Re-issue the pending invite for this email")
                    Button("Send Invite") {
                        Task { @MainActor in
                            await runInvite(mode: .send)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!canSubmit)
                }
            }
        }
        .padding(12)
        .background(AppTheme.windowBackground)
    }

    private enum InviteMode {
        case send
        case resend
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !roles.isEmpty
            && (allAppsVisible || !selectedAppIds.isEmpty)
    }

    private func runInvite(mode: InviteMode) async {
        if mode == .send { isSaving = true } else { isResending = true }
        defer {
            isSaving = false
            isResending = false
        }
        errorMessage = nil
        noticeMessage = nil
        let result: ResourcesViewModel.WriteResult
        switch mode {
        case .send:
            result = await viewModel.inviteUser(
                email: email, firstName: firstName, lastName: lastName,
                roles: roles, allAppsVisible: allAppsVisible,
                provisioningAllowed: provisioningAllowed,
                visibleAppIds: visibleAppIds)
        case .resend:
            result = await viewModel.resendInvitation(
                email: email, firstName: firstName, lastName: lastName,
                roles: roles.map(\.rawValue), allAppsVisible: allAppsVisible,
                provisioningAllowed: provisioningAllowed)
        }
        switch result {
        case .success:
            // .ignored: duplicate in flight / cancelled — keep the form
            // open, nothing was sent.
            noticeMessage = mode == .send ? "Invitation sent." : "Invitation re-sent."
            onDone()
        case .failure(let message):
            errorMessage = message
        case .ignored:
            break
        }
    }
}

/// POST /v1/profiles — name, type, bundle ID and at least one
/// certificate; devices optional (required server-side only for
/// development/adhoc types). Pickers read the lists the view model
/// already fetched — opening one kind never refetches another.
/// Needs an Admin key role; a TestFlight-only key 403s.
private struct CreateProfileForm: View {
    @ObservedObject var viewModel: ResourcesViewModel
    var onDone: () -> Void
    @State private var name = ""
    @State private var profileType: ProfileTypeOption = .IOS_APP_DEVELOPMENT
    @State private var bundleIdId: String?
    @State private var certificateIds: Set<String> = []
    @State private var deviceIds: Set<String> = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var bundleIds: [BundleIdModel] { viewModel.bundleIdsState.loadedValue ?? [] }
    private var certificates: [CertificateModel] { viewModel.certificatesState.loadedValue ?? [] }
    private var devices: [DeviceModel] { viewModel.devicesState.loadedValue ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New Provisioning Profile")
                .font(.appBody)
                .fontWeight(.medium)
            TextField("Profile name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.appBody)
                .disabled(isSaving)
            Picker("Type", selection: $profileType) {
                ForEach(ProfileTypeOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            .disabled(isSaving)
            Picker("Bundle ID", selection: $bundleIdId) {
                Text("Select a bundle ID").tag(nil as String?)
                ForEach(bundleIds, id: \.id) { bundleId in
                    Text("\(bundleId.name ?? bundleId.identifier ?? bundleId.id) (\(bundleId.identifier ?? ""))")
                        .tag(bundleId.id as String?)
                }
            }
            .pickerStyle(.menu)
            .disabled(isSaving || bundleIds.isEmpty)
            if bundleIds.isEmpty {
                Text("No bundle IDs loaded — open Resources → Bundle IDs first so the picker has something to offer.")
                    .font(.appCaption2)
                    .foregroundColor(.secondary)
            }
            Text("Certificates (\(certificateIds.count) selected)")
                .font(.appCaption)
                .foregroundColor(.secondary)
            ChecklistDropdownMenu(
                title: "Certificates",
                items: certificates.map {
                    ChecklistDropdownMenu.Item(
                        id: $0.id,
                        title: certificatePickerLabel($0),
                        subtitle: nil
                    )
                },
                selection: $certificateIds,
                emptyHint: "No certificates loaded — open Resources → Certificates first.",
                allowsSelectAll: true
            )
            .disabled(isSaving)
            Text("Devices (\(deviceIds.count) selected, optional)")
                .font(.appCaption)
                .foregroundColor(.secondary)
            ChecklistDropdownMenu(
                title: "Devices",
                items: devices.map {
                    ChecklistDropdownMenu.Item(
                        id: $0.id,
                        title: "\($0.name ?? $0.id) (\($0.udid ?? ""))",
                        subtitle: nil
                    )
                },
                selection: $deviceIds,
                emptyHint: "No devices loaded — open Resources → Devices first.",
                allowsSelectAll: true
            )
            .disabled(isSaving)
            Text("Test on a throwaway profile first. Needs an API key with the Admin role.")
                .font(.appCaption2)
                .foregroundColor(.secondary)
            if let errorMessage {
                Text(errorMessage)
                    .font(.appCaption)
                    .foregroundColor(AppTheme.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel") { onDone() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.secondary)
                    .disabled(isSaving)
                Spacer()
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button("Create") {
                        Task { @MainActor in
                            isSaving = true
                            defer { isSaving = false }
                            let result = await viewModel.createProfile(
                                name: name,
                                profileType: profileType,
                                bundleIdId: bundleIdId,
                                certificateIds: certificateIds,
                                deviceIds: deviceIds)
                            if case .success = result {
                                onDone()
                            } else if case .failure(let message) = result {
                                // .ignored: duplicate in flight / cancelled —
                                // keep the form open, nothing was created.
                                errorMessage = message
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || bundleIdId == nil
                              || certificateIds.isEmpty)
                }
            }
        }
        .padding(12)
        .background(AppTheme.windowBackground)
        .onAppear {
            // Relationship pickers reuse the existing fetches — load() is a
            // no-op for kinds already loaded, so this never refetches.
            // Relationship pickers reuse the existing fetches — but a
            // first page alone silently truncates the picker on teams
            // with >200 items, so the profile form drains ALL pages
            // (loadAllPages is a no-op refetch guard when already loaded).
            viewModel.loadAllPages(.bundleIds)
            viewModel.loadAllPages(.certificates)
            viewModel.loadAllPages(.devices)
        }
    }
}

/// Dropdown multi-select of checkable rows — compacts long picker lists
/// (certificates, devices) so the create form fits the sheet instead of
/// pushing its buttons and the list off-screen. Same styling as
/// RoleDropdownMenu. Rows support a subtitle line (e.g. certificate
/// expiry) so same-named items stay distinguishable.
private struct ChecklistDropdownMenu: View {
    struct Item: Hashable {
        let id: String
        let title: String
        let subtitle: String?
    }

    let title: String
    let items: [Item]
    @Binding var selection: Set<String>
    var emptyHint: String? = nil
    /// When true, the menu opens with Select All / Clear actions on top
    /// (mirrors the Apple Developer site's picker).
    var allowsSelectAll = false

    private var label: String {
        switch selection.count {
        case 0: return "\(title): none selected"
        case 1: return "\(title): 1 selected"
        default: return "\(title): \(selection.count) selected"
        }
    }

    var body: some View {
        if items.isEmpty {
            Text(emptyHint ?? "Nothing loaded yet.")
                .font(.appCaption2)
                .foregroundColor(.secondary)
        } else {
            Menu {
                if allowsSelectAll {
                    Button("Select All") {
                        selection = Set(items.map(\.id))
                    }
                    Button("Clear") {
                        selection = []
                    }
                    Divider()
                }
                ForEach(items, id: \.id) { item in
                    Toggle(isOn: Binding(
                        get: { selection.contains(item.id) },
                        set: { isOn in
                            if isOn { selection.insert(item.id) } else { selection.remove(item.id) }
                        }
                    )) {
                        if let subtitle = item.subtitle {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                Text(subtitle)
                                    .font(.appCaption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text(item.title)
                        }
                    }
                }
            } label: {
                Text(label)
                    .font(.appBody)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(AppTheme.textBackgroundColor)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
        }
    }
}

/// Shared certificate expiry parsing — the row and the profile picker
/// both render it. App Store Connect returns fractional seconds on some
/// endpoints; the plain parser silently fails on those, so try it as a
/// fallback.
private let certificateExpiryParser = ISO8601DateFormatter()
private let certificateExpiryParserFractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let certificateExpiryDisplayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MMM d, yyyy"
    return formatter
}()

private func certificateExpiryDate(_ raw: String?) -> Date? {
    guard let raw, !raw.isEmpty else { return nil }
    return certificateExpiryParserFractional.date(from: raw) ?? certificateExpiryParser.date(from: raw)
}

/// "expires Feb 9, 2027" / "expired Feb 9, 2027" / nil when unknown —
/// mirrors the Apple Developer site's certificate picker rows.
private func certificateExpiryLabel(_ raw: String?) -> String? {
    guard let date = certificateExpiryDate(raw) else { return nil }
    let formatted = certificateExpiryDisplayFormatter.string(from: date)
    return date < Date() ? "expired \(formatted)" : "expires \(formatted)"
}

/// Compact Dev/Prod tag for picker rows ("IOS_DEVELOPMENT" → "Dev").
/// Anything else falls back to the raw type string.
private func certificateTypeShort(_ raw: String?) -> String {
    guard let raw else { return "Cert" }
    if raw.contains("DEVELOPMENT") { return "Dev" }
    if raw.contains("DISTRIBUTION") { return "Prod" }
    return raw
}

/// One-line picker label: name · Dev/Prod · expiry. Compact by design —
/// the dropdown menu sizes to content, so every extra line costs space.
private func certificatePickerLabel(_ certificate: CertificateModel) -> String {
    let name = certificate.displayName ?? certificate.name ?? certificate.id
    let type = certificateTypeShort(certificate.certificateType)
    let expiry = certificateExpiryLabel(certificate.expirationDate) ?? "expiry unknown"
    return "\(name) · \(type) · \(expiry)"
}

// MARK: - Rows

private struct DeviceRow: View {
    let device: DeviceModel
    @ObservedObject var viewModel: ResourcesViewModel
    @State private var errorMessage: String?

    private var isDisabled: Bool { device.status == "DISABLED" }
    private var isBusy: Bool { viewModel.isWriteInFlight(device.id) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "iphone")
                .font(.appCaption)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.name ?? "Unknown device")
                        .font(.appBody)
                        .fontWeight(.medium)
                    StateChip(text: device.status ?? "")
                }
                Text(device.model ?? "")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
                Text(device.udid ?? "")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.appCaption2)
                        .foregroundColor(AppTheme.negative)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(device.deviceClass ?? "")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
                Text(device.platform ?? "")
                    .font(.appCaption2)
                    .foregroundColor(.secondary)
                // Batch G (#10): disable is the API's "revoke" (no DELETE
                // on devices); re-enabling reverses it, so no confirm.
                if isBusy {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button(isDisabled ? "Enable" : "Disable") {
                        Task { @MainActor in
                            if case .failure(let message) = await viewModel.setDeviceEnabled(
                                device, enabled: isDisabled) {
                                errorMessage = message
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("\(isDisabled ? "Enable" : "Disable") \(device.name ?? "device")")
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.secondaryBackground))
    }
}

private struct CertificateRow: View {
    let certificate: CertificateModel
    @ObservedObject var viewModel: ResourcesViewModel
    @State private var showRevokeConfirm = false
    @State private var errorMessage: String?

    private var isBusy: Bool { viewModel.isWriteInFlight(certificate.id) }

    private var isExpired: Bool {
        guard let date = certificateExpiryDate(certificate.expirationDate) else { return false }
        return date < Date()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.appCaption)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(certificate.displayName ?? certificate.name ?? "Unknown certificate")
                        .font(.appBody)
                        .fontWeight(.medium)
                    if certificate.activated == true {
                        StateChip(text: "ACTIVE")
                    }
                }
                Text("Serial: \(certificate.serialNumber ?? "—")")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                Text("Expires: \(certificate.expirationDate ?? "—")")
                    .font(.appCaption2)
                    .foregroundColor(isExpired ? AppTheme.negative : .secondary)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.appCaption2)
                        .foregroundColor(AppTheme.negative)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(certificate.certificateType ?? "")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
                // Batch G (#10): revoking is destructive — confirm first
                // (alert pattern mirrors BuildRowView's expire/remove).
                if isBusy {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button("Revoke") { showRevokeConfirm = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundColor(AppTheme.negative)
                        .accessibilityLabel("Revoke \(certificate.displayName ?? certificate.name ?? "certificate")")
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.secondaryBackground))
        .alert("Revoke this certificate?", isPresented: $showRevokeConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Revoke", role: .destructive) {
                Task { @MainActor in
                    if case .failure(let message) = await viewModel.revokeCertificate(id: certificate.id) {
                        errorMessage = message
                    }
                }
            }
        } message: {
            Text("Apps signed with this certificate will stop working. This cannot be undone.")
        }
    }
}

private struct BundleIdRow: View {
    let bundleId: BundleIdModel
    @ObservedObject var viewModel: ResourcesViewModel
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    private var isBusy: Bool { viewModel.isWriteInFlight(bundleId.id) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.appCaption)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                if isRenaming {
                    TextField("Bundle ID name", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .font(.appBody)
                        .disabled(isBusy)
                } else {
                    Text(bundleId.name ?? "Unknown identifier")
                        .font(.appBody)
                        .fontWeight(.medium)
                }
                Text(bundleId.identifier ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.appCaption2)
                        .foregroundColor(AppTheme.negative)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(bundleId.platform ?? "")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
                if isRenaming {
                    HStack(spacing: 6) {
                        Button("Cancel") {
                            isRenaming = false
                            errorMessage = nil
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isBusy)
                        if isBusy {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Button("Save") {
                                Task { @MainActor in
                                    if case .failure(let message) = await viewModel.renameBundleId(
                                        bundleId, newName: draftName) {
                                        errorMessage = message
                                    } else {
                                        isRenaming = false
                                        errorMessage = nil
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                } else if isBusy {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    HStack(spacing: 6) {
                        Button("Rename") {
                            draftName = bundleId.name ?? ""
                            errorMessage = nil
                            isRenaming = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Rename \(bundleId.name ?? "bundle ID")")
                        // Deleting is destructive — confirm first (same alert
                        // pattern as CertificateRow's revoke).
                        Button("Delete") { showDeleteConfirm = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .foregroundColor(AppTheme.negative)
                            .accessibilityLabel("Delete \(bundleId.name ?? "bundle ID")")
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.secondaryBackground))
        .alert("Delete this bundle ID?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { @MainActor in
                    if case .failure(let message) = await viewModel.deleteBundleId(id: bundleId.id) {
                        errorMessage = message
                    }
                }
            }
        } message: {
            Text("Profiles and capabilities using this identifier will break. This cannot be undone.")
        }
    }
}

private struct ProfileRow: View {
    let profile: ProfileModel
    @ObservedObject var viewModel: ResourcesViewModel
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    private var isBusy: Bool { viewModel.isWriteInFlight(profile.id) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.text.rectangle")
                .font(.appCaption)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile.name ?? "Unknown profile")
                        .font(.appBody)
                        .fontWeight(.medium)
                    StateChip(text: profile.profileState ?? "")
                }
                Text("UUID: \(profile.uuid ?? "—")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Expires: \(profile.expirationDate ?? "—")")
                    .font(.appCaption2)
                    .foregroundColor(.secondary)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.appCaption2)
                        .foregroundColor(AppTheme.negative)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(profile.profileType ?? "")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
                Text(profile.platform ?? "")
                    .font(.appCaption2)
                    .foregroundColor(.secondary)
                // Deleting is destructive — confirm first (same alert
                // pattern as CertificateRow's revoke).
                if isBusy {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button("Delete") { showDeleteConfirm = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundColor(AppTheme.negative)
                        .accessibilityLabel("Delete \(profile.name ?? "profile")")
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.secondaryBackground))
        .alert("Delete this profile?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { @MainActor in
                    if case .failure(let message) = await viewModel.deleteProfile(id: profile.id) {
                        errorMessage = message
                    }
                }
            }
        } message: {
            Text("Builds signed with this profile will fail to install. This cannot be undone.")
        }
    }
}

/// Shared role chips — one rendering for user rows and invitation rows
/// so the two can't drift.
private struct RoleChips: View {
    let roles: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(roles, id: \.self) { role in
                Text(role)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(AppTheme.secondaryText.opacity(0.12))
                    .cornerRadius(4)
            }
        }
    }
}

/// A pending (unaccepted) team invitation: Resend re-issues it with its
/// stored details, Revoke deletes it (confirm first). Failures stay
/// inline; the row never disappears on failure.
private struct InvitationRow: View {
    let invitation: UserInvitationModel
    @ObservedObject var viewModel: ResourcesViewModel
    @State private var isResending = false
    @State private var showRevokeConfirm = false
    @State private var errorMessage: String?

    private var isBusy: Bool { viewModel.isWriteInFlight(invitation.id) || isResending }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "envelope")
                .font(.appCaption)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(invitation.email ?? "Unknown email")
                        .font(.appBody)
                        .fontWeight(.medium)
                        .textSelection(.enabled)
                    Text("Pending")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(AppTheme.pending)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(AppTheme.pending.opacity(0.12))
                        .cornerRadius(4)
                }
                Text("\(invitation.firstName ?? "") \(invitation.lastName ?? "")")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
                RoleChips(roles: invitation.roles ?? [])
                if let expirationDate = invitation.expirationDate {
                    Text("Expires: \(expirationDate)")
                        .font(.appCaption2)
                        .foregroundColor(.secondary)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.appCaption2)
                        .foregroundColor(AppTheme.negative)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if isBusy {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    HStack(spacing: 6) {
                        Button("Resend") {
                            Task { @MainActor in
                                await resend()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Resend invitation to \(invitation.email ?? "user")")
                        Button("Revoke") { showRevokeConfirm = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .foregroundColor(AppTheme.negative)
                            .accessibilityLabel("Revoke invitation for \(invitation.email ?? "user")")
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.secondaryBackground))
        .alert("Revoke this invitation?", isPresented: $showRevokeConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Revoke", role: .destructive) {
                Task { @MainActor in
                    if case .failure(let message) = await viewModel.revokeInvitation(id: invitation.id) {
                        errorMessage = message
                    }
                }
            }
        } message: {
            Text("They will need a new invite to join the team. This cannot be undone.")
        }
    }

    private func resend() async {
        isResending = true
        defer { isResending = false }
        errorMessage = nil
        let result = await viewModel.resendInvitation(
            email: invitation.email ?? "",
            firstName: invitation.firstName ?? "",
            lastName: invitation.lastName ?? "",
            roles: invitation.roles ?? [],
            allAppsVisible: invitation.allAppsVisible ?? true,
            provisioningAllowed: invitation.provisioningAllowed ?? false)
        if case .failure(let message) = result {
            // .success refreshes the invitations list; .ignored (duplicate
            // in flight / cancelled) leaves the row untouched.
            errorMessage = message
        }
    }
}

private struct UserRow: View {
    let user: UserModel
    @ObservedObject var viewModel: ResourcesViewModel
    @State private var isEditingRoles = false
    @State private var draftRoles: Set<UserRoleOption> = []
    @State private var showRemoveConfirm = false
    @State private var errorMessage: String?

    private var isBusy: Bool { viewModel.isWriteInFlight(user.id) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle")
                .font(.appCaption)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.username ?? "Unknown user")
                    .font(.appBody)
                    .fontWeight(.medium)
                    .textSelection(.enabled)
                Text("\(user.firstName ?? "") \(user.lastName ?? "")")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
                if isEditingRoles {
                    RoleMultiSelect(selection: $draftRoles)
                        .disabled(isBusy)
                } else {
                    RoleChips(roles: user.roles ?? [])
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.appCaption2)
                        .foregroundColor(AppTheme.negative)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if user.allAppsVisible == true {
                    Text("All apps")
                        .font(.appCaption2)
                        .foregroundColor(.secondary)
                }
                if user.provisioningAllowed == true {
                    Text("Provisioning")
                        .font(.appCaption2)
                        .foregroundColor(.secondary)
                }
                if isEditingRoles {
                    HStack(spacing: 6) {
                        Button("Cancel") {
                            isEditingRoles = false
                            errorMessage = nil
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isBusy)
                        if isBusy {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Button("Save") {
                                Task { @MainActor in
                                    if case .failure(let message) = await viewModel.updateUserRoles(
                                        user, roles: draftRoles) {
                                        errorMessage = message
                                    } else {
                                        isEditingRoles = false
                                        errorMessage = nil
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(draftRoles.isEmpty)
                        }
                    }
                } else if isBusy {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    HStack(spacing: 6) {
                        Button("Edit roles") {
                            draftRoles = Set((user.roles ?? []).compactMap(UserRoleOption.init(rawValue:)))
                            errorMessage = nil
                            isEditingRoles = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Edit roles for \(user.username ?? "user")")
                        // Removing is destructive — confirm first (same alert
                        // pattern as CertificateRow's revoke).
                        Button("Remove") { showRemoveConfirm = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .foregroundColor(AppTheme.negative)
                            .accessibilityLabel("Remove \(user.username ?? "user")")
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.secondaryBackground))
        .alert("Remove this user?", isPresented: $showRemoveConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task { @MainActor in
                    if case .failure(let message) = await viewModel.removeUser(id: user.id) {
                        errorMessage = message
                    }
                }
            }
        } message: {
            Text("They will immediately lose access to App Store Connect. This cannot be undone.")
        }
    }
}

#Preview {
    ResourcesSectionView(viewModel: ResourcesViewModel())
        .frame(width: 240)
}
