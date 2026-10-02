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
        if kind == .devices {
            // Figma devices-light: the devices kind renders the dedicated
            // table (toolbar, search, platform filter, register, pagination)
            // instead of the generic rows — everything lives in DevicesView.
            DevicesView(viewModel: viewModel)
        } else {
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
/// Internal (not private) so the Figma devices table reuses the same form.
struct RegisterDeviceForm: View {
    @ObservedObject var viewModel: ResourcesViewModel
    var onDone: () -> Void
    @State private var name = ""
    @State private var platform: DevicePlatform = .IOS
    @State private var udid = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Register Device")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(ShipyardTheme.title)
                Text("Add a new hardware device to provision testing and ad-hoc profiles.")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.body)
            }

            VStack(alignment: .leading, spacing: 14) {
                sheetField(label: "Device Name", text: $name, prompt: "John's iPhone 16 Pro", mono: false)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Platform")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                    Menu {
                        ForEach(DevicePlatform.allCases, id: \.self) { option in
                            Button(option.displayName) {
                                platform = option
                            }
                        }
                    } label: {
                        HStack {
                            Text(platform.displayName)
                                .font(.system(size: 13))
                                .foregroundColor(ShipyardTheme.title)
                            Spacer()
                            ShipyardIcon(name: "ShipyardChevron", size: 10)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(LaunchTheme.field)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(LaunchTheme.border, lineWidth: 1)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(isSaving)
                    .accessibilityLabel("Select platform")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("UDID")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                    sheetField(label: "", text: $udid, prompt: "00008101-001C25D40C28001E", mono: true)
                    Text("40-character hex UDID for older devices, or 25-character formatted for Apple Silicon/newer iPhones.")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                }
            }

            Text("Needs an API key with the Admin role. Verify with a throwaway device first — registrations count against the yearly device limit.")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel") { onDone() }
                    .buttonStyle(.launchSecondary)
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
                    .buttonStyle(.launchPrimary)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || udid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.top, 12)
        }
        .padding(24)
        .frame(width: 480)
    }

    private func sheetField(label: String, text: Binding<String>, prompt: String, mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.title)
            }
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .font(mono ? .system(size: 12, design: .monospaced) : .system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(LaunchTheme.field)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(LaunchTheme.border, lineWidth: 1)
                )
                .disabled(isSaving)
        }
    }
}

/// POST /v1/certificates — certificate type plus a CSR file
/// (Keychain Access → Certificate Assistant → Request a Certificate,
/// or `openssl req -new`). File upload only: raw CSR text is never
/// shown or pasted — users pick the file the same way as the .p8 key.
/// Internal (not private) so the Figma certificates table reuses it.
struct CreateCertificateForm: View {
    @ObservedObject var viewModel: ResourcesViewModel
    var onDone: () -> Void
    @State private var certificateType: CertificateTypeOption = .IOS_DEVELOPMENT
    /// Loaded CSR content (never displayed — file name is shown instead).
    @State private var csrContent = ""
    @State private var csrFileName: String?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Text("Create Certificate")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(ShipyardTheme.title)
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(ShipyardTheme.sidebarBackground)
                .overlay(
                    ShipyardTheme.rowDivider.frame(height: 1),
                    alignment: .bottom
                )

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CERTIFICATE TYPE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ShipyardTheme.body)
                    Menu {
                        ForEach(CertificateTypeOption.allCases, id: \.self) { option in
                            Button(option.displayName) {
                                certificateType = option
                            }
                        }
                    } label: {
                        HStack {
                            Text(certificateType.displayName)
                                .font(.system(size: 13))
                                .foregroundColor(ShipyardTheme.title)
                            Spacer()
                            ShipyardIcon(name: "ShipyardChevron", size: 10)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(LaunchTheme.field)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(LaunchTheme.border, lineWidth: 1)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(isSaving)
                    .accessibilityLabel("Select certificate type")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("CERTIFICATE SIGNING REQUEST (CSR)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ShipyardTheme.body)
                    HStack(spacing: 12) {
                        Spacer(minLength: 0)
                        Button("Choose File…") { selectCSRFile() }
                            .buttonStyle(.launchSecondary)
                            .disabled(isSaving)
                            .accessibilityLabel("Select certificate signing request file")
                        Text(csrFileName ?? "No file selected")
                            .font(.system(size: 11))
                            .foregroundColor(ShipyardTheme.body)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(csrFileName ?? "")
                        if csrFileName != nil {
                            Button {
                                csrContent = ""
                                csrFileName = nil
                                errorMessage = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(isSaving)
                            .accessibilityLabel("Remove selected CSR file")
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .background(LaunchTheme.page)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(LaunchTheme.border, lineWidth: 1)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    )
                    Text("A Certificate Signing Request (CSR) can be generated from Keychain Access on your Mac.")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.negative)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)

            HStack {
                Spacer()
                Button("Cancel") { onDone() }
                    .buttonStyle(.launchSecondary)
                    .disabled(isSaving)
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
                    .buttonStyle(.launchPrimary)
                    .disabled(csrContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
            .background(ShipyardTheme.sidebarBackground)
            .overlay(
                ShipyardTheme.rowDivider.frame(height: 1),
                alignment: .top
            )
        }
        .frame(width: 560)
    }

    /// File picker for the CSR (same pattern as the .p8 key import).
    /// No `allowedContentTypes` filter: a valid CSR named `request.txt`
    /// must still be selectable. Content validation (PEM markers) is the
    /// sole gate, so an oddly-named but valid CSR loads fine.
    private func selectCSRFile() {
        let openPanel = NSOpenPanel()
        openPanel.prompt = "Choose"
        openPanel.canChooseFiles = true
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.title = "Select your certificate signing request"
        guard openPanel.runModal() == .OK, let url = openPanel.url else { return }
        do {
            csrContent = try ProvisioningWriteValidation.loadCSR(from: url)
            csrFileName = url.lastPathComponent
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// POST /v1/bundleIds — name, identifier and platform are required;
/// seedId is optional. Needs an Admin key role; a TestFlight-only key 403s.
/// Internal (not private) so the Figma bundle-IDs table reuses the form.
struct CreateBundleIdForm: View {
    @ObservedObject var viewModel: ResourcesViewModel
    var onDone: () -> Void
    @State private var name = ""
    @State private var identifier = ""
    @State private var platform: BundleIdPlatformOption = .IOS
    @State private var seedId = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Text("Create Bundle ID")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(ShipyardTheme.title)
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(ShipyardTheme.sidebarBackground)
                .overlay(
                    ShipyardTheme.rowDivider.frame(height: 1),
                    alignment: .bottom
                )

            VStack(alignment: .leading, spacing: 20) {
                sheetField(label: "NAME", text: $name, prompt: "My App", mono: false)
                sheetField(
                    label: "IDENTIFIER",
                    text: $identifier,
                    prompt: "com.example.app",
                    mono: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text("PLATFORM")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ShipyardTheme.body)
                    Menu {
                        ForEach(BundleIdPlatformOption.allCases, id: \.self) { option in
                            Button(option.displayName) {
                                platform = option
                            }
                        }
                    } label: {
                        HStack {
                            Text(platform.displayName)
                                .font(.system(size: 13))
                                .foregroundColor(ShipyardTheme.title)
                            Spacer()
                            ShipyardIcon(name: "ShipyardChevron", size: 10)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(LaunchTheme.field)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(LaunchTheme.border, lineWidth: 1)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(isSaving)
                    .accessibilityLabel("Select platform")
                }
                VStack(alignment: .leading, spacing: 8) {
                    sheetField(
                        label: "SEED ID (OPTIONAL)",
                        text: $seedId,
                        prompt: "Team seed identifier",
                        mono: true)
                    Text("Leave blank unless Apple assigned a seed ID to this identifier.")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.negative)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)

            HStack {
                Spacer()
                Button("Cancel") { onDone() }
                    .buttonStyle(.launchSecondary)
                    .disabled(isSaving)
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
                    .buttonStyle(.launchPrimary)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
            .background(ShipyardTheme.sidebarBackground)
            .overlay(
                ShipyardTheme.rowDivider.frame(height: 1),
                alignment: .top
            )
        }
        .frame(width: 560)
    }

    private func sheetField(label: String, text: Binding<String>, prompt: String, mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ShipyardTheme.body)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .font(mono ? .system(size: 13, design: .monospaced) : .system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(LaunchTheme.field)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(LaunchTheme.border, lineWidth: 1)
                )
                .disabled(isSaving)
        }
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
/// Internal (not private) so the Figma users table reuses the same form.
struct InviteUserForm: View {
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
    @State private var errorMessage: String?
    @State private var noticeMessage: String?

    /// The Figma sheet picks a single role; the API takes a set.
    private var selectedRole: UserRoleOption {
        roles.first ?? .DEVELOPER
    }

    private var isBusy: Bool { isSaving }

    /// App ids for the invite body: empty = all apps.
    private var visibleAppIds: [String] {
        guard !allAppsVisible else { return [] }
        return selectedAppIds.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Invite User")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(ShipyardTheme.title)
                Text("Send an Apple Developer team invitation to grant immediate access.")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.body)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    inviteField(label: "First Name", text: $firstName, prompt: "Jane")
                    inviteField(label: "Last Name", text: $lastName, prompt: "Doe")
                }

                inviteField(label: "Email Address", text: $email, prompt: "jane.doe@acme.com")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Role")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                    Menu {
                        ForEach(UserRoleOption.allCases, id: \.self) { option in
                            Button(option.displayName) {
                                roles = [option]
                            }
                        }
                    } label: {
                        HStack {
                            Text(selectedRole.displayName)
                                .font(.system(size: 13))
                                .foregroundColor(ShipyardTheme.title)
                            Spacer()
                            ShipyardIcon(name: "ShipyardChevron", size: 10)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(LaunchTheme.field)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(LaunchTheme.border, lineWidth: 1)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(isBusy)
                    .accessibilityLabel("Select role")
                    Text(roleDescription(selectedRole))
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("App Access")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("All Apps (Including New)", isOn: $allAppsVisible)
                            .font(.system(size: 12))
                            .toggleStyle(.checkbox)
                            .disabled(isBusy)
                            .onChange(of: allAppsVisible) { _, newValue in
                                // Turning all-apps back on drops the per-app
                                // picks so stale ids can never leak into an
                                // all-apps invite.
                                if newValue { selectedAppIds = [] }
                            }
                        ForEach(apps, id: \.id) { app in
                            Toggle("\(app.name ?? app.bundleId ?? app.id) (\(app.bundleId ?? ""))", isOn: Binding(
                                get: { selectedAppIds.contains(app.id) },
                                set: { checked in
                                    if checked { selectedAppIds.insert(app.id) }
                                    else { selectedAppIds.remove(app.id) }
                                }
                            ))
                            .font(.system(size: 12))
                            .toggleStyle(.checkbox)
                            .disabled(isBusy || allAppsVisible)
                        }
                        if apps.isEmpty {
                            Text("No apps loaded — apps appear here once the Apps table loads.")
                                .font(.system(size: 11))
                                .foregroundColor(ShipyardTheme.body)
                        }
                    }
                    .padding(12)
                    .background(LaunchTheme.page)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(LaunchTheme.border, lineWidth: 1)
                    )
                }
            }

            if let noticeMessage {
                Text(noticeMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel") { onDone() }
                    .buttonStyle(.launchSecondary)
                    .disabled(isBusy)
                Spacer()
                if isBusy {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button("Send Invitation") {
                        Task { @MainActor in
                            await runInvite()
                        }
                    }
                    .buttonStyle(.launchPrimary)
                    .disabled(!canSubmit)
                }
            }
            .padding(.top, 12)
        }
        .padding(24)
        .frame(minWidth: 480, idealWidth: 560, maxWidth: 640)
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !roles.isEmpty
            && (allAppsVisible || !selectedAppIds.isEmpty)
    }

    private func runInvite() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        noticeMessage = nil
        let result = await viewModel.inviteUser(
            email: email, firstName: firstName, lastName: lastName,
            roles: roles, allAppsVisible: allAppsVisible,
            provisioningAllowed: provisioningAllowed,
            visibleAppIds: visibleAppIds)
        switch result {
        case .success:
            // .ignored: duplicate in flight / cancelled — keep the form
            // open, nothing was sent.
            noticeMessage = "Invitation sent."
            onDone()
        case .failure(let message):
            errorMessage = message
        case .ignored:
            break
        }
    }

    private func inviteField(label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(LaunchTheme.field)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(LaunchTheme.border, lineWidth: 1)
                )
                .disabled(isBusy)
        }
    }

    /// One-line remit per role for the hint under the picker.
    private func roleDescription(_ role: UserRoleOption) -> String {
        switch role {
        case .ADMIN: return "Admins manage everything: apps, users, certificates, and agreements."
        case .ACCOUNT_HOLDER: return "The account holder has ultimate legal and financial responsibility."
        case .APP_MANAGER: return "App Managers edit store listings, versions, and TestFlight details."
        case .DEVELOPER: return "Developers have access to write code, create sandbox profiles, and download builds."
        case .MARKETING: return "Marketing roles manage promotional artwork and store copy."
        case .FINANCE: return "Finance roles access sales, payments, and tax reports."
        case .SALES: return "Sales roles manage customers and pricing."
        case .CUSTOMER_SUPPORT: return "Customer support roles reply to reviews and manage users."
        case .TECHNICAL: return "Technical roles manage certificates, devices, and provisioning."
        case .READ_ONLY: return "Read-only access to apps, builds, and reports."
        case .ACCESS_TO_REPORTS: return "Access to sales and finance reports only."
        }
    }
}

/// POST /v1/profiles — name, type, bundle ID and at least one
/// certificate; devices optional (required server-side only for
/// development/adhoc types). Pickers read the lists the view model
/// already fetched — opening one kind never refetches another.
/// Needs an Admin key role; a TestFlight-only key 403s.
/// Internal (not private) so the Figma profiles table reuses the form.
struct CreateProfileForm: View {
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

    enum ProfileStep: Int, CaseIterable {
        case type = 1, bundleID, certificates, devices, name, review

        var title: String {
            switch self {
            case .type: return "Select Type"
            case .bundleID: return "Select Bundle ID"
            case .certificates: return "Select Certificates"
            case .devices: return "Select Devices"
            case .name: return "Name Profile"
            case .review: return "Review Profile"
            }
        }

        var subtitle: String {
            switch self {
            case .type: return "Pick the provisioning profile type for this build."
            case .bundleID: return "Pick the bundle ID this profile belongs to."
            case .certificates: return "Select one or more certificates to include in this provisioning profile."
            case .devices: return "Select test devices to include (development and ad-hoc only)."
            case .name: return "Give the profile a recognizable name."
            case .review: return "Confirm the details before creating the profile."
            }
        }

        var shortLabel: String {
            switch self {
            case .type: return "Type"
            case .bundleID: return "Bundle ID"
            case .certificates: return "Certificates"
            case .devices: return "Devices"
            case .name: return "Name"
            case .review: return "Review"
            }
        }
    }

    @State private var step: ProfileStep = .type

    private var canContinue: Bool {
        switch step {
        case .bundleID: return bundleIdId != nil
        case .certificates: return !certificateIds.isEmpty
        case .name: return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .type, .devices, .review: return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(ShipyardTheme.title)
                Text(step.subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.body)
            }

            stepper

            stepBody
                .frame(minHeight: 220, alignment: .topLeading)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel") { onDone() }
                    .buttonStyle(.launchSecondary)
                    .disabled(isSaving)
                Spacer()
                if step != .type {
                    Button("Back") {
                        if let previous = ProfileStep(rawValue: step.rawValue - 1) {
                            step = previous
                        }
                    }
                    .buttonStyle(.launchSecondary)
                    .disabled(isSaving)
                }
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if step == .review {
                    Button("Create") {
                        Task { @MainActor in
                            await create()
                        }
                    }
                    .buttonStyle(.launchPrimary)
                } else {
                    Button("Continue") {
                        step = ProfileStep(rawValue: step.rawValue + 1) ?? .review
                    }
                    .buttonStyle(.launchPrimary)
                    .disabled(!canContinue)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, 12)
        }
        .padding(24)
        .frame(width: 560)
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

    private var stepper: some View {
        HStack(spacing: 0) {
            ForEach(ProfileStep.allCases, id: \.self) { item in
                HStack(spacing: 4) {
                    if item.rawValue < step.rawValue {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(ShipyardTheme.success)
                            .accessibilityHidden(true)
                    } else if item == step {
                        Text("\(item.rawValue)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(ShipyardTheme.accent))
                            .accessibilityHidden(true)
                    } else {
                        Text("\(item.rawValue)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(ShipyardTheme.body)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(Color.gray.opacity(0.2)))
                            .accessibilityHidden(true)
                    }
                    Text(item.shortLabel)
                        .font(.system(size: 11, weight: item == step ? .semibold : .regular))
                        .foregroundColor(item == step ? ShipyardTheme.accent : ShipyardTheme.body)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityLabel("Step \(step.rawValue) of 6: \(step.title)")
    }

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .type: typeStep
        case .bundleID: bundleStep
        case .certificates: certificatesStep
        case .devices: devicesStep
        case .name: nameStep
        case .review: reviewStep
        }
    }

    private var typeStep: some View {
        VStack(alignment: .leading, spacing: 8) {
                Text("PROFILE TYPE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(ShipyardTheme.body)
                Menu {
                    ForEach(ProfileTypeOption.allCases, id: \.self) { option in
                        Button(option.displayName) {
                            profileType = option
                        }
                    }
                } label: {
                    HStack {
                        Text(profileType.displayName)
                            .font(.system(size: 13))
                            .foregroundColor(ShipyardTheme.title)
                        Spacer()
                        ShipyardIcon(name: "ShipyardChevron", size: 10)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(LaunchTheme.field)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(LaunchTheme.border, lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .disabled(isSaving)
                .accessibilityLabel("Select profile type")
            }
    }

    private var bundleStep: some View {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(bundleIds, id: \.id) { bundleId in
                        pickRow(
                            title: bundleId.name ?? bundleId.identifier ?? bundleId.id,
                            subtitle: bundleId.identifier,
                            isPicked: bundleIdId == bundleId.id
                        ) {
                            bundleIdId = bundleId.id
                        }
                        ShipyardTheme.rowDivider.frame(height: 1)
                    }
                }
            }
            .background(LaunchTheme.field)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(LaunchTheme.border, lineWidth: 1)
            )
    }

    private var certificatesStep: some View {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(certificates, id: \.id) { certificate in
                        Toggle(isOn: Binding(
                            get: { certificateIds.contains(certificate.id) },
                            set: { checked in
                                if checked { certificateIds.insert(certificate.id) }
                                else { certificateIds.remove(certificate.id) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(certificate.displayName ?? certificate.name ?? "Unknown certificate")
                                    .font(.system(size: 13))
                                    .foregroundColor(ShipyardTheme.title)
                                Text("\(certificateTypeDisplayName(certificate.certificateType)) • Expires \(certificateExpiryDisplay(certificate.expirationDate))")
                                    .font(.system(size: 11))
                                    .foregroundColor(ShipyardTheme.body)
                            }
                        }
                        .font(.system(size: 13))
                        .toggleStyle(.checkbox)
                        .disabled(isSaving)
                    }
                }
                .padding(12)
            }
            .background(LaunchTheme.field)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(LaunchTheme.border, lineWidth: 1)
            )
    }

    private var devicesStep: some View {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(devices, id: \.id) { device in
                        Toggle(isOn: Binding(
                            get: { deviceIds.contains(device.id) },
                            set: { checked in
                                if checked { deviceIds.insert(device.id) }
                                else { deviceIds.remove(device.id) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name ?? "Unknown device")
                                    .font(.system(size: 13))
                                    .foregroundColor(ShipyardTheme.title)
                                Text("\(devicePlatformDisplayName(device.platform ?? "")) • \(device.udid ?? "")")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(ShipyardTheme.body)
                            }
                        }
                        .font(.system(size: 13))
                        .toggleStyle(.checkbox)
                        .disabled(isSaving)
                    }
                }
                .padding(12)
            }
            .background(LaunchTheme.field)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(LaunchTheme.border, lineWidth: 1)
            )
    }

    private var nameStep: some View {
            LaunchField(label: "Profile Name", text: $name, prompt: "Acme Development")
                .disabled(isSaving)
    }

    private var reviewStep: some View {
            VStack(alignment: .leading, spacing: 10) {
                reviewRow("Type", profileType.displayName)
                reviewRow("Bundle ID", bundleIds.first(where: { $0.id == bundleIdId }).map { "\($0.name ?? "") (\($0.identifier ?? ""))" } ?? "—")
                reviewRow("Certificates", "\(certificateIds.count) selected")
                reviewRow("Devices", deviceIds.isEmpty ? "None (distribution)" : "\(deviceIds.count) selected")
                reviewRow("Name", name.isEmpty ? "—" : name)
                Text("Test on a throwaway profile first. Needs an API key with the Admin role.")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
            }
    }

    private func pickRow(title: String, subtitle: String?, isPicked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ShipyardIcon(name: isPicked ? "ShipyardCheckSm" : "ShipyardCircleSm", size: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(ShipyardTheme.body)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    private func reviewRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
            Spacer(minLength: 0)
        }
    }

    private func create() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
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
/// nonisolated(unsafe): formatters are not Sendable, but every caller is
/// a SwiftUI view body — never concurrent. Zero per-render allocation.
private nonisolated(unsafe) let certificateExpiryParser = ISO8601DateFormatter()
private nonisolated(unsafe) let certificateExpiryParserFractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private nonisolated(unsafe) let certificateExpiryDisplayFormatter: DateFormatter = {
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
