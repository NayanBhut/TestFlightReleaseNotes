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
import AppKit

/// Sidebar section listing the five team-scoped resource kinds.
struct ResourcesSectionView: View {
    @ObservedObject var viewModel: ResourcesViewModel
    // Starts expanded — one less tap to reach the five resource rows
    // (intentional Batch F default, confirmed in review).
    @State private var isExpanded = true
    @State private var selectedKind: ResourcesViewModel.Kind?

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 2) {
                ForEach(ResourcesViewModel.Kind.allCases) { kind in
                    Button {
                        selectedKind = kind
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: kind.systemImage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 16)
                            Text(kind.displayName)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
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
            .padding(.top, 2)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Resources")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("Team-wide")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(item: $selectedKind) { kind in
            ResourceListContentView(kind: kind, viewModel: viewModel)
        }
    }
}

/// Read-only list for a single resource kind, with cursor pagination.
struct ResourceListContentView: View {
    let kind: ResourcesViewModel.Kind
    @ObservedObject var viewModel: ResourcesViewModel
    @Environment(\.dismiss) private var dismiss
    // Batch G (#10): write forms toggle from the header.
    @State private var showRegisterDeviceForm = false
    @State private var showCreateCertificateForm = false

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
                .font(.title3)
                .fontWeight(.semibold)
            Spacer()
            if let total = viewModel.totals[kind] {
                // Local search only covers loaded rows — show "N of M loaded"
                // while filtering so the count can't read as a server total.
                if viewModel.hasActiveSearch(for: kind) {
                    Text("\(viewModel.filteredCount(for: kind)) of \(viewModel.loadedCount(for: kind)) loaded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(total) total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Button(action: { viewModel.retry(kind) }) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
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
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Register a device")
            }
            if kind == .certificates {
                Button {
                    showCreateCertificateForm.toggle()
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Create a certificate")
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
        .background(Color(nsColor: .controlBackgroundColor))
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
                    .font(.subheadline)
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
                    .font(.headline)
                Text(kind.subtitle)
                    .font(.subheadline)
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
                // scrolling.
                paginationFooter
            }
        }
    }

    // MARK: - Search (Batch F #6)

    /// Same capsule style as the sidebar's app search field.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.caption)
                .accessibilityHidden(true)

            TextField("Search \(kind.displayName.lowercased())", text: viewModel.searchBinding(for: kind))
                .textFieldStyle(.plain)
                .font(.subheadline)

            if !viewModel.searchText(for: kind).isEmpty {
                Button {
                    viewModel.searchBinding(for: kind).wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .help("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
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
                .font(.title3)
                .fontWeight(.medium)
            Text("No \(kind.displayName.lowercased()) match \"\(viewModel.searchText(for: kind))\"")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            if viewModel.nextCursors[kind] != nil {
                // Search is local — matches may still exist on pages that
                // haven't been loaded yet (review finding).
                Text("More results may exist on unloaded pages — try Load more below")
                    .font(.caption)
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
                BundleIdRow(bundleId: bundleId)
            }
        case .profiles:
            ForEach(viewModel.filteredProfiles, id: \.id) { profile in
                ProfileRow(profile: profile)
            }
        case .users:
            ForEach(viewModel.filteredUsers, id: \.id) { user in
                UserRow(user: user)
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
            .background(Color(nsColor: .controlBackgroundColor))
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
                .font(.subheadline)
                .fontWeight(.medium)
            TextField("Device name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
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
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
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
        .background(Color(nsColor: .windowBackgroundColor))
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
                .font(.subheadline)
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
                .border(Color.gray.opacity(0.3), width: 1)
                .accessibilityLabel("Certificate signing request content")
                .disabled(isSaving)
            Text("Paste the CSR content. Needs an API key with the Admin role.")
                .font(.caption2)
                .foregroundColor(.secondary)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
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
        .background(Color(nsColor: .windowBackgroundColor))
    }
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
                .font(.caption)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.name ?? "Unknown device")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    StateChip(text: device.status ?? "")
                }
                Text(device.model ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(device.udid ?? "")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(device.deviceClass ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(device.platform ?? "")
                    .font(.caption2)
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
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

private struct CertificateRow: View {
    let certificate: CertificateModel
    @ObservedObject var viewModel: ResourcesViewModel
    @State private var showRevokeConfirm = false
    @State private var errorMessage: String?

    private var isBusy: Bool { viewModel.isWriteInFlight(certificate.id) }

    private static let expiryParser = ISO8601DateFormatter()
    /// App Store Connect returns fractional seconds on some endpoints;
    /// the plain parser silently fails on those, so try it as a fallback.
    private static let expiryParserFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private var isExpired: Bool {
        guard let date = certificate.expirationDate else { return false }
        let parsed = Self.expiryParserFractional.date(from: date) ?? Self.expiryParser.date(from: date)
        return parsed.map { $0 < Date() } ?? false
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.caption)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(certificate.displayName ?? certificate.name ?? "Unknown certificate")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if certificate.activated == true {
                        StateChip(text: "ACTIVE")
                    }
                }
                Text("Serial: \(certificate.serialNumber ?? "—")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                Text("Expires: \(certificate.expirationDate ?? "—")")
                    .font(.caption2)
                    .foregroundColor(isExpired ? .red : .secondary)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(certificate.certificateType ?? "")
                    .font(.caption)
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
                        .foregroundColor(.red)
                        .accessibilityLabel("Revoke \(certificate.displayName ?? certificate.name ?? "certificate")")
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.caption)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(bundleId.name ?? "Unknown identifier")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(bundleId.identifier ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Text(bundleId.platform ?? "")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

private struct ProfileRow: View {
    let profile: ProfileModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.text.rectangle")
                .font(.caption)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile.name ?? "Unknown profile")
                        .font(.subheadline)
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
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(profile.profileType ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(profile.platform ?? "")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

private struct UserRow: View {
    let user: UserModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle")
                .font(.caption)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.username ?? "Unknown user")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .textSelection(.enabled)
                Text("\(user.firstName ?? "") \(user.lastName ?? "")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    ForEach(user.roles ?? [], id: \.self) { role in
                        Text(role)
                            .font(.system(size: 9, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(4)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if user.allAppsVisible == true {
                    Text("All apps")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if user.provisioningAllowed == true {
                    Text("Provisioning")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

#Preview {
    ResourcesSectionView(viewModel: ResourcesViewModel())
        .frame(width: 240)
}
