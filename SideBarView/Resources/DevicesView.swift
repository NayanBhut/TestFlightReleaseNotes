//
//  DevicesView.swift
//  App Store
//
//  Devices management table from the devices-light Figma frame: toolbar
//  (title + total pill, search, platform filter, Register Device) over a
//  Device Name / UDID / Platform / Status / Added Date table. Presented as
//  the Resources devices sheet content and embedded in the Shipyard
//  section. All data, search, pagination and writes go through
//  ResourcesViewModel; the register form is the shared
//  RegisterDeviceForm.
//
//  Figma device-detail flow (114-3013/3123/3159/3177/12528/12605): tapping
//  a row opens an inline detail (editable name with Revert/Save Name via
//  PATCH name, read-only UDID + platform/device class, dependent-profiles
//  table, yearly-quota explainer, last-synced action bar). Enable/disable
//  runs through confirm sheets; the disable sheet shows the dependent
//  profiles that stop being eligible. The empty state offers CSV import
//  (parsed client-side, registered one POST at a time — there is no bulk
//  endpoint). Yearly counts and membership periods have no API endpoint,
//  so they render as static explainer copy, never live numbers.
//

import SwiftUI
import UniformTypeIdentifiers

struct DevicesView: View {
    @ObservedObject var viewModel: ResourcesViewModel
    @EnvironmentObject private var toastCenter: ShipyardToastCenter
    /// Sheet presentation keeps the fixed Figma-like sizing; the shell
    /// embeds the table flexibly instead.
    var fixedSize = true
    /// Jump to a profile in the Profiles section (Figma "Open Profile →").
    /// Wired by ShipyardShell (switches section + filters); nil in
    /// previews and sheet contexts without section navigation.
    var onOpenProfile: ((ProfileModel) -> Void)?
    /// Show the full Profiles section (Figma success-sheet Review Profiles).
    var onOpenProfilesList: (() -> Void)?
    @State private var showRegisterForm = false
    /// Raw platform value filter; nil is "All".
    @State private var platformFilter: String?
    @State private var bannerError: String?
    /// Inline detail selection (Figma 114-3013); nil shows the list.
    @State private var selectedDeviceId: String?
    @State private var disableTarget: DeviceModel?
    @State private var enableTarget: DeviceModel?
    @State private var showCSVImporter = false
    @State private var csvPreview: DeviceCSVPreview?
    @State private var csvImportResult: DeviceCSVImportResult?

    private var searched: [DeviceModel] { viewModel.filteredDevices }

    private var visibleDevices: [DeviceModel] {
        guard let platformFilter else { return searched }
        return searched.filter { $0.platform == platformFilter }
    }

    private var selectedDevice: DeviceModel? {
        guard let selectedDeviceId else { return nil }
        return (viewModel.devicesState.loadedValue ?? []).first { $0.id == selectedDeviceId }
    }

    private var platforms: [String] {
        let loaded = viewModel.devicesState.loadedValue ?? []
        return Array(Set(loaded.compactMap(\.platform))).sorted()
    }

    private var totalText: String {
        if let total = viewModel.totals[.devices] {
            return "\(total) Total"
        }
        return "\(viewModel.loadedCount(for: .devices)) Total"
    }

    private var disablePresented: Binding<Bool> {
        Binding(
            get: { disableTarget != nil },
            set: { if !$0 { disableTarget = nil } }
        )
    }

    private var enablePresented: Binding<Bool> {
        Binding(
            get: { enableTarget != nil },
            set: { if !$0 { enableTarget = nil } }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let bannerError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AppTheme.negative)
                    Text(bannerError)
                        .font(.appCaption)
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
            if selectedDevice != nil {
                detailContent
            } else {
                table
            }
        }
        // Wider than the generic resource sheet: the UDID column alone is
        // 320pt in Figma.
        .frame(minWidth: fixedSize ? 640 : 0, idealWidth: fixedSize ? 880 : nil, maxWidth: fixedSize ? 1024 : nil,
               minHeight: fixedSize ? 480 : 0, idealHeight: fixedSize ? 600 : nil, maxHeight: fixedSize ? maxSheetHeight : nil)
        .onAppear {
            viewModel.load(.devices)
        }
        .sheet(isPresented: $showRegisterForm) {
            RegisterDeviceForm(viewModel: viewModel) {
                showRegisterForm = false
            }
        }
        .sheet(isPresented: disablePresented) {
            if let target = disableTarget {
                DisableDeviceSheet(
                    viewModel: viewModel,
                    device: target,
                    onOpenProfile: onOpenProfile,
                    onReviewProfiles: {
                        disableTarget = nil
                        onOpenProfilesList?()
                    },
                    onOpenDevice: {
                        selectedDeviceId = target.id
                        disableTarget = nil
                    },
                    onDone: { disableTarget = nil }
                )
            }
        }
        .sheet(isPresented: enablePresented) {
            if let target = enableTarget {
                EnableDeviceSheet(
                    viewModel: viewModel,
                    device: target,
                    onDone: { enableTarget = nil }
                )
            }
        }
        .fileImporter(
            isPresented: $showCSVImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            switch result {
            case .success(let url):
                do {
                    let content = try DeviceCSVImport.load(from: url)
                    let parsed = DeviceCSVImport.parse(content)
                    csvPreview = DeviceCSVPreview(
                        fileName: url.lastPathComponent,
                        rows: parsed.rows,
                        rejected: parsed.rejected
                    )
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription
                        ?? "Couldn't read that file."
                    bannerError = message
                    toastCenter.show("Couldn't read device import", detail: message, variant: .error)
                }
            case .failure:
                let message = "Couldn't read that file. Pick a .csv or .txt file with one device per line."
                bannerError = message
                toastCenter.show("Couldn't read device import", detail: message, variant: .error)
            }
        }
        .sheet(item: $csvPreview) { preview in
            DeviceCSVImportSheet(
                viewModel: viewModel,
                preview: preview,
                onDone: { result in
                    csvPreview = nil
                    csvImportResult = result
                    if let result {
                        if result.failures.isEmpty {
                            toastCenter.show("\(result.registered) device\(result.registered == 1 ? "" : "s") registered", variant: .success)
                        } else {
                            toastCenter.show(
                                "Device import finished with failures",
                                detail: "\(result.registered) registered, \(result.failures.count) failed",
                                variant: result.registered > 0 ? .warning : .error)
                        }
                    }
                }
            )
        }
        .sheet(item: $csvImportResult) { result in
            DeviceCSVResultSheet(result: result) {
                csvImportResult = nil
            }
        }
    }

    /// Height cap from the presenting window's screen (same rule as the
    /// generic resource sheet — the sheet window doesn't exist yet when
    /// the body first evaluates).
    private var maxSheetHeight: CGFloat {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        return max(460, (screen?.visibleFrame.height ?? 1_000) - 120)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Devices")
                    .font(.appBody)
                    .foregroundColor(.primary)
                Text(totalText)
                    .font(.appCaption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(10)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.appCaption2)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
                TextField("Search Devices", text: viewModel.searchBinding(for: .devices))
                    .textFieldStyle(.plain)
                    .font(.appCaption)
            }
            .padding(.horizontal, 8)
            .frame(width: 160, height: 24)
            .background(AppTheme.textBackgroundColor)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppTheme.border, lineWidth: 1)
            )

            Menu {
                Button("All") { platformFilter = nil }
                ForEach(platforms, id: \.self) { platform in
                    Button(devicePlatformDisplayName(platform)) {
                        platformFilter = platform
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Platform: \(platformFilter.map(devicePlatformDisplayName) ?? "All")")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.appCaption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(AppTheme.textBackgroundColor)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Filter by platform")

            Button("Register Device") {
                showRegisterForm.toggle()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityLabel("Register a device")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        if let device = selectedDevice {
            DeviceDetailView(
                viewModel: viewModel,
                device: device,
                onBack: { selectedDeviceId = nil },
                onDisable: { disableTarget = $0 },
                onEnable: { enableTarget = $0 },
                onOpenProfile: onOpenProfile
            )
            .id(device.id)
        }
    }

    // MARK: - Table

    @ViewBuilder
    private var table: some View {
        switch viewModel.devicesState {
        case .idle, .loading:
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                Text("Loading devices…")
                    .font(.appBody)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            ErrorRetryView(
                title: "Couldn't Load Devices",
                message: message,
                retryTitle: "Retry",
                onRetry: { viewModel.retry(.devices) }
            )
        default:
            if visibleDevices.isEmpty {
                if viewModel.hasActiveSearch(for: .devices) || platformFilter != nil {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("No Matching Devices")
                            .font(.subheader)
                            .fontWeight(.medium)
                        Button("Clear Filters") {
                            viewModel.searchBinding(for: .devices).wrappedValue = ""
                            platformFilter = nil
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    devicesEmptyState
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        headerRow
                        ForEach(visibleDevices, id: \.id) { device in
                            deviceRow(device)
                            Divider()
                        }
                        paginationFooter
                    }
                }
            }
        }
    }

    /// Figma 114-12528: info banner + Get started + Register Your First
    /// Device / Import CSV actions. CSV import is client-side parsing over
    /// sequential POST /v1/devices (no bulk endpoint exists).
    private var devicesEmptyState: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DeviceStatusBanner(
                        variant: .info,
                        title: "No devices yet",
                        message: "Register a testing device or import a CSV / text file."
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Get started")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ShipyardTheme.title)
                        Text("Register Your First Device opens the device creation flow. CSV import registers one device per line (name, UDID, platform) — each counts against the yearly device limit.")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                Text("No devices registered for this team.")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                Spacer()
                Button("Import CSV…") {
                    showCSVImporter = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button("Register Your First Device…") {
                    showRegisterForm = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("Register your first device")
            }
            .padding(.horizontal, 24)
            .frame(height: 56)
            .background(AppTheme.secondaryBackground)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Text("Device Name")
                .frame(width: 180, alignment: .leading)
            Text("UDID")
                .frame(width: 320, alignment: .leading)
            Text("Platform")
                .frame(width: 120, alignment: .leading)
            Text("Status")
                .frame(width: 120, alignment: .leading)
            Text("Added Date")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.appCaption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(AppTheme.secondaryBackground)
    }

    private func deviceRow(_ device: DeviceModel) -> some View {
        let isDisabled = device.status == "DISABLED"
        return HStack(spacing: 12) {
            Text(device.name ?? "Unknown device")
                .font(.appCaption)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 180, alignment: .leading)

            Text(device.udid ?? "—")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 320, alignment: .leading)

            Text(devicePlatformDisplayName(device.platform ?? ""))
                .font(.appCaption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.12))
                .cornerRadius(4)
                .frame(width: 120, alignment: .leading)

            HStack(spacing: 6) {
                Circle()
                    .fill(isDisabled ? AppTheme.tertiaryText : AppTheme.readyForSale)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(deviceStatusDisplayName(device.status))
                    .font(.appCaption)
                    .foregroundColor(.primary)
            }
            .frame(width: 120, alignment: .leading)

            Text(formatDeviceDate(device.addedDate))
                .font(.appCaption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedDeviceId = device.id
        }
        .contextMenu {
            Button("View Details") {
                selectedDeviceId = device.id
            }
            Button(isDisabled ? "Enable…" : "Disable…") {
                if isDisabled {
                    enableTarget = device
                } else {
                    // Disabling revokes the device (no API delete exists)
                    // and still counts against the yearly limit — confirm
                    // in the Figma sheet with dependent profiles.
                    disableTarget = device
                }
            }
            .accessibilityLabel("\(isDisabled ? "Enable" : "Disable") \(device.name ?? "device")")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(device.name ?? "Unknown device"), \(deviceStatusDisplayName(device.status))")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the device detail.")
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if let nextCursor = viewModel.nextCursors[.devices] {
            HStack {
                Spacer()
                if viewModel.paginationFailedKinds.contains(.devices) {
                    Button("Couldn't load more — Retry") {
                        viewModel.loadMore(.devices, cursor: nextCursor)
                    }
                    .buttonStyle(.plain)
                    .font(.appCaption)
                    .foregroundColor(.red)
                    .padding(.vertical, 8)
                } else if viewModel.isPaginatingKinds.contains(.devices) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.vertical, 8)
                } else {
                    Button("Load more") {
                        viewModel.loadMore(.devices, cursor: nextCursor)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.vertical, 8)
                }
                Spacer()
            }
            .onAppear {
                // Cursor pagination without auto-chaining: kick the next
                // page when the footer scrolls into view.
                if !viewModel.isPaginatingKinds.contains(.devices) {
                    viewModel.loadMore(.devices, cursor: nextCursor)
                }
            }
        }
    }
}

// MARK: - Device detail (Figma 114-3013)

/// Inline device detail: editable name (PATCH, Save Name/Revert),
/// read-only UDID + platform/device class, dependent-profiles table with
/// Open Profile jumps, yearly-quota explainer, and a last-synced action
/// bar with Disable/Enable. Internal (not private) so sheets share it.
struct DeviceDetailView: View {
    @ObservedObject var viewModel: ResourcesViewModel
    var device: DeviceModel
    var onBack: () -> Void
    var onDisable: (DeviceModel) -> Void
    var onEnable: (DeviceModel) -> Void
    var onOpenProfile: ((ProfileModel) -> Void)?
    @EnvironmentObject private var toastCenter: ShipyardToastCenter

    @State private var draftName: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        viewModel: ResourcesViewModel,
        device: DeviceModel,
        onBack: @escaping () -> Void,
        onDisable: @escaping (DeviceModel) -> Void,
        onEnable: @escaping (DeviceModel) -> Void,
        onOpenProfile: ((ProfileModel) -> Void)?
    ) {
        self.viewModel = viewModel
        self.device = device
        self.onBack = onBack
        self.onDisable = onDisable
        self.onEnable = onEnable
        self.onOpenProfile = onOpenProfile
        _draftName = State(initialValue: device.name ?? "")
    }

    private var isDisabled: Bool { device.status == "DISABLED" }
    private var isDirty: Bool {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines) != (device.name ?? "")
    }

    private var subtitle: String {
        var parts: [String] = []
        parts.append(deviceStatusDisplayName(device.status))
        let deviceClass = deviceClassDisplayName(device.deviceClass)
        if !deviceClass.isEmpty { parts.append(deviceClass) }
        let platform = devicePlatformDisplayName(device.platform ?? "")
        if !platform.isEmpty { parts.append(platform) }
        var text = parts.joined(separator: " · ")
        let registered = formatDeviceDate(device.addedDate)
        if registered != "—" {
            text += text.isEmpty ? "registered \(registered)" : " · registered \(registered)"
        }
        return text
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            onBack()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Devices")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(ShipyardTheme.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back to devices list")
                        Text(device.name ?? "Unknown device")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(ShipyardTheme.title)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 12))
                                .foregroundColor(ShipyardTheme.body)
                        }
                    }
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Device details")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(ShipyardTheme.title)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Name")
                                    .font(.system(size: 12))
                                    .foregroundColor(ShipyardTheme.title)
                                TextField("Device name", text: $draftName)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(LaunchTheme.field)
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(LaunchTheme.border, lineWidth: 1)
                                    )
                                    .disabled(isSaving)
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                Text("UDID")
                                    .font(.system(size: 12))
                                    .foregroundColor(ShipyardTheme.title)
                                Text(device.udid ?? "—")
                                    .font(.system(size: 13))
                                    .foregroundColor(ShipyardTheme.body)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(AppTheme.secondaryBackground)
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(AppTheme.border, lineWidth: 1)
                                    )
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Platform / device class")
                                    .font(.system(size: 12))
                                    .foregroundColor(ShipyardTheme.title)
                                Text("\(devicePlatformDisplayName(device.platform ?? "")) · \(deviceClassDisplayName(device.deviceClass))")
                                    .font(.system(size: 13))
                                    .foregroundColor(ShipyardTheme.body)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(AppTheme.secondaryBackground)
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(AppTheme.border, lineWidth: 1)
                                    )
                            }
                        }
                        .frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Dependent profiles")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(ShipyardTheme.title)
                            dependentsSection
                        }
                        .frame(maxWidth: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Yearly registrations")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ShipyardTheme.title)
                        Text("Disabling does not free a registration slot during the membership year. The API exposes no quota endpoint, so live counts aren't shown here — check your membership details on the developer website before registering test devices.")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.negative)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
            }
            Divider()
            HStack(spacing: 12) {
                Text(viewModel.lastSyncText(for: .devices) ?? "Not synced yet")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                Spacer()
                if isDisabled {
                    Button("Enable Device…") {
                        onEnable(device)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isSaving)
                } else {
                    Button("Disable Device…") {
                        onDisable(device)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(ShipyardTheme.danger)
                    .disabled(isSaving)
                }
                Button("Revert") {
                    draftName = device.name ?? ""
                    errorMessage = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!isDirty || isSaving)
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button("Save Name") {
                        saveName()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!isDirty || draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 56)
            .background(AppTheme.secondaryBackground)
        }
        .onAppear {
            viewModel.loadDependentProfiles(for: device)
        }
    }

    private func saveName() {
        errorMessage = nil
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            let result = await viewModel.renameDevice(device, to: draftName)
            switch result {
            case .success:
                toastCenter.show("Device name saved", detail: draftName, variant: .success)
            case .failure(let message):
                errorMessage = message
                toastCenter.show("Couldn't save device name", detail: message, variant: .error)
            case .ignored:
                // Duplicate in flight / unchanged — nothing to do.
                break
            }
        }
    }

    // MARK: - Dependent profiles

    @ViewBuilder
    private var dependentsSection: some View {
        switch viewModel.dependentProfilesState {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Loading dependent profiles…")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
            }
            .padding(.vertical, 8)
        case .error(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.negative)
                Button("Retry") {
                    viewModel.retryDependentProfiles(for: device)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        case .empty:
            Text("No profiles include this device.")
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
                .padding(.vertical, 8)
        case .loaded(let dependents):
            DependentProfilesTable(dependents: dependents, onOpenProfile: onOpenProfile)
        }
    }
}

// MARK: - Dependent profiles table

/// Profile / Type / Signing certificate / Jump table shared by the device
/// detail and the disable sheet.
struct DependentProfilesTable: View {
    var dependents: [DependentProfile]
    var onOpenProfile: ((ProfileModel) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Profile")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Type")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Signing certificate")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Jump")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 11))
            .foregroundColor(ShipyardTheme.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(AppTheme.secondaryBackground)
            ForEach(Array(dependents.enumerated()), id: \.element.profile.id) { index, dependent in
                HStack(spacing: 12) {
                    Text(dependent.profile.name ?? "Unknown profile")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(dependent.profileTypeDisplayName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(dependent.certificateNames.joined(separator: ", "))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Open Profile →") {
                        onOpenProfile?(dependent.profile)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(ShipyardTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(onOpenProfile == nil)
                }
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.title)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(index % 2 == 0 ? AppTheme.textBackgroundColor : Color.clear)
                Divider()
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Status banner (Figma 114-31xx / 12528 / 12605)

/// Tinted status banner from the device sheets: info (blue), warning
/// (amber), success (green), error (red).
struct DeviceStatusBanner: View {
    enum Variant {
        case info
        case warning
        case success
        case error

        var tint: Color {
            switch self {
            case .info: return Color(red: 0.0, green: 0.478, blue: 1.0)
            case .warning: return Color(red: 0.651, green: 0.416, blue: 0.0)
            case .success: return Color(red: 0.141, green: 0.541, blue: 0.239)
            case .error: return Color(red: 0.851, green: 0.176, blue: 0.141)
            }
        }

        var wash: Color {
            switch self {
            case .info: return Color(red: 0.898, green: 0.945, blue: 1.0)
            case .warning: return Color(red: 1.0, green: 0.973, blue: 0.882)
            case .success: return Color(red: 0.918, green: 0.969, blue: 0.933)
            case .error: return Color(red: 1.0, green: 0.925, blue: 0.918)
            }
        }

        var systemImage: String {
            switch self {
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .success: return "checkmark.circle"
            case .error: return "exclamationmark.circle"
            }
        }
    }

    var variant: Variant
    var title: String
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: variant.systemImage)
                .font(.system(size: 16))
                .foregroundColor(variant.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(variant.tint)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(variant.wash)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(variant.tint.opacity(0.5), lineWidth: 0.5)
        )
    }
}

// MARK: - Disable sheet (Figma 114-3123 + 114-3159)

/// Disable confirm with dependent profiles and quota copy; on success it
/// swaps to the Figma success state (Review Profiles / Open Device).
struct DisableDeviceSheet: View {
    @ObservedObject var viewModel: ResourcesViewModel
    var device: DeviceModel
    var onOpenProfile: ((ProfileModel) -> Void)?
    var onReviewProfiles: () -> Void
    var onOpenDevice: () -> Void
    var onDone: () -> Void
    @EnvironmentObject private var toastCenter: ShipyardToastCenter

    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Figma 114-3159 success state after the PATCH lands.
    @State private var didDisable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if didDisable {
                Text("Device disabled")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(ShipyardTheme.title)
                DeviceStatusBanner(
                    variant: .success,
                    title: "\(device.name ?? "Device") · Disabled",
                    message: "Illustrative result: excluded from new profile selection. Yearly registration remains counted."
                )
                HStack {
                    Spacer()
                    Button("Review Profiles") {
                        onReviewProfiles()
                    }
                    .buttonStyle(.launchSecondary)
                    Button("Open Device") {
                        onOpenDevice()
                    }
                    .buttonStyle(.launchPrimary)
                }
                .padding(.top, 4)
            } else {
                Text("Disable this device?")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(ShipyardTheme.title)
                DeviceStatusBanner(
                    variant: .warning,
                    title: "Profile selection will change",
                    message: "\(device.name ?? "This device") will no longer be eligible for newly created or regenerated profiles. Review the dependent profiles below and regenerate if needed."
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quota remains used")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    Text("Disabling does not free a registration slot during the membership year. Existing profile files do not automatically update; do not assume installed apps are removed.")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                dependentsBlock
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.negative)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { onDone() }
                        .buttonStyle(.launchSecondary)
                        .disabled(isSaving)
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Button("Disable Device") {
                            disable()
                        }
                        .buttonStyle(.launchDestructive)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            viewModel.loadDependentProfiles(for: device)
        }
    }

    @ViewBuilder
    private var dependentsBlock: some View {
        switch viewModel.dependentProfilesState {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Loading dependent profiles…")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
            }
        case .error(let message):
            HStack(spacing: 8) {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.negative)
                Button("Retry") {
                    viewModel.retryDependentProfiles(for: device)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        case .empty:
            Text("No profiles include this device — disabling affects no profile selection.")
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
        case .loaded(let dependents):
            DependentProfilesTable(dependents: dependents, onOpenProfile: onOpenProfile)
            Text("Only the first 50 devices per profile are checked (API limit) — regenerate profiles after disabling to be sure.")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
        }
    }

    private func disable() {
        errorMessage = nil
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            let result = await viewModel.setDeviceEnabled(device, enabled: false)
            switch result {
            case .success:
                didDisable = true
                toastCenter.show("Device disabled", detail: device.name ?? device.udid, variant: .success)
            case .failure(let message):
                errorMessage = message
                toastCenter.show("Couldn't disable device", detail: message, variant: .error)
            case .ignored:
                break
            }
        }
    }
}

// MARK: - Enable sheet (Figma 114-3177)

/// Enable confirm: re-enabling consumes no new registration slot.
struct EnableDeviceSheet: View {
    @ObservedObject var viewModel: ResourcesViewModel
    var device: DeviceModel
    var onDone: () -> Void
    @EnvironmentObject private var toastCenter: ShipyardToastCenter

    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Enable \(device.name ?? "this device")?")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(ShipyardTheme.title)
            DeviceStatusBanner(
                variant: .info,
                title: "No new registration slot",
                message: "Re-enabling does not create a second device record."
            )
            VStack(alignment: .leading, spacing: 12) {
                Text("Existing registration")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                Text("Re-enable this registered device, then regenerate compatible Development or Ad Hoc profiles to include it. It is already counted in this membership year.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Device")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.title)
                    Text(device.name ?? "—")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.body)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.secondaryBackground)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("UDID")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.title)
                    Text(device.udid ?? "—")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(ShipyardTheme.body)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.secondaryBackground)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { onDone() }
                    .buttonStyle(.launchSecondary)
                    .disabled(isSaving)
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button("Enable Device") {
                        enable()
                    }
                    .buttonStyle(.launchPrimary)
                }
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 560)
    }

    private func enable() {
        errorMessage = nil
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            let result = await viewModel.setDeviceEnabled(device, enabled: true)
            switch result {
            case .success:
                toastCenter.show("Device enabled", detail: device.name ?? device.udid, variant: .success)
                onDone()
            case .failure(let message):
                errorMessage = message
                toastCenter.show("Couldn't enable device", detail: message, variant: .error)
            case .ignored:
                break
            }
        }
    }
}

// MARK: - CSV import (Figma 114-12528)

// FileImporter needs an Identifiable value for .sheet(item:).
struct DeviceCSVPreview: Identifiable {
    var id: String { fileName + "-\(rows.count)-\(rejected)" }
    var fileName: String
    var rows: [DeviceCSVRow]
    var rejected: Int
}

/// Preview sheet: row counts, yearly-limit warning, then sequential import
/// with progress. Import runs here (not in the row view) so progress and
/// the result survive the preview dismissal path.
struct DeviceCSVImportSheet: View {
    @ObservedObject var viewModel: ResourcesViewModel
    var preview: DeviceCSVPreview
    /// Called with the import outcome (nil = cancelled before importing).
    var onDone: (DeviceCSVImportResult?) -> Void

    @State private var isImporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import \(preview.fileName)?")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(ShipyardTheme.title)
            if preview.rows.isEmpty {
                DeviceStatusBanner(
                    variant: .error,
                    title: "No importable rows",
                    message: preview.rejected > 0
                        ? "\(preview.rejected) lines rejected — expected name, UDID, platform per line."
                        : "The file has no device lines — expected name, UDID, platform per line."
                )
            } else {
                DeviceStatusBanner(
                    variant: .info,
                    title: "\(preview.rows.count) device\(preview.rows.count == 1 ? "" : "s") ready",
                    message: preview.rejected > 0
                        ? "\(preview.rejected) lines rejected (bad UDID, blank name, or unknown platform)."
                        : "All lines parsed. Blank platforms register as iOS."
                )
                // Preview the first rows so a wrong-column file is obvious.
                VStack(spacing: 0) {
                    ForEach(Array(preview.rows.prefix(5).enumerated()), id: \.offset) { _, row in
                        HStack {
                            Text(row.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(row.udid)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(row.platform.displayName)
                                .frame(width: 80, alignment: .leading)
                        }
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.title)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        Divider()
                    }
                    if preview.rows.count > 5 {
                        Text("…and \(preview.rows.count - 5) more")
                            .font(.system(size: 11))
                            .foregroundColor(ShipyardTheme.body)
                            .padding(.vertical, 6)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Text("Each registration counts against the yearly device limit and can't be undone via the API. Verify with a throwaway device first.")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .fixedSize(horizontal: false, vertical: true)
            if isImporting, let progress = viewModel.importProgress {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))) {
                    Text("Registering \(progress.done) of \(progress.total)…")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { onDone(nil) }
                    .buttonStyle(.launchSecondary)
                    .disabled(isImporting)
                Button("Import \(preview.rows.count) Device\(preview.rows.count == 1 ? "" : "s")") {
                    runImport()
                }
                .buttonStyle(.launchPrimary)
                .disabled(preview.rows.isEmpty || isImporting)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private func runImport() {
        isImporting = true
        Task { @MainActor in
            let result = await viewModel.importDevices(preview.rows)
            onDone(result)
        }
    }
}

/// Import result sheet: registered count + per-row failures.
struct DeviceCSVResultSheet: View {
    var result: DeviceCSVImportResult
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import complete")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(ShipyardTheme.title)
            if result.failures.isEmpty {
                DeviceStatusBanner(
                    variant: .success,
                    title: "\(result.registered) device\(result.registered == 1 ? "" : "s") registered",
                    message: "New rows appear at the top of the devices list."
                )
            } else {
                DeviceStatusBanner(
                    variant: result.registered > 0 ? .warning : .error,
                    title: "\(result.registered) registered, \(result.failures.count) failed",
                    message: "Failures are listed below — fix and re-import just those lines."
                )
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(result.failures.enumerated()), id: \.offset) { _, failure in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(failure.row.name) · \(failure.row.udid)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(ShipyardTheme.title)
                                Text(failure.message)
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.negative)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 240)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            HStack {
                Spacer()
                Button("Done") { onDone() }
                    .buttonStyle(.launchPrimary)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

// MARK: - Display helpers

/// API platform codes to the Figma labels (unknown codes pass through).
/// Shared with the profile wizard (same module).
func devicePlatformDisplayName(_ platform: String) -> String {
    switch platform.uppercased() {
    case "IOS": return "iOS"
    case "MAC_OS": return "macOS"
    case "UNIVERSAL": return "Universal"
    default: return platform
    }
}

/// API deviceClass codes to Figma labels (unknown codes pass through).
func deviceClassDisplayName(_ deviceClass: String?) -> String {
    switch deviceClass?.uppercased() {
    case "IPHONE": return "iPhone"
    case "IPAD": return "iPad"
    case "IPOD": return "iPod"
    case "MAC": return "Mac"
    case "APPLE_WATCH": return "Apple Watch"
    case "APPLE_TV": return "Apple TV"
    case nil, "": return ""
    default: return deviceClass ?? ""
    }
}

private func deviceStatusDisplayName(_ status: String?) -> String {
    switch status {
    case "ENABLED": return "Enabled"
    case "DISABLED": return "Disabled"
    case nil: return "—"
    default: return status ?? "—"
    }
}

/// API ISO-8601 timestamps to Figma's "Sep 22, 2024"; unparseable values
/// pass through untouched.
private func formatDeviceDate(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else { return "—" }
    if let date = iso8601DeviceDateParser.date(from: raw) {
        return deviceDatePrinter.string(from: date)
    }
    for formatter in deviceDateFallbackParsers {
        if let date = formatter.date(from: raw) {
            return deviceDatePrinter.string(from: date)
        }
    }
    return raw
}

// Formatters are main-thread only (all callers are SwiftUI view bodies),
// hence nonisolated(unsafe) rather than a lock.
private nonisolated(unsafe) let iso8601DeviceDateParser = ISO8601DateFormatter()

private let deviceDateFallbackParsers: [DateFormatter] = {
    let fractional = DateFormatter()
    fractional.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
    fractional.locale = Locale(identifier: "en_US_POSIX")
    let plain = DateFormatter()
    plain.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
    plain.locale = Locale(identifier: "en_US_POSIX")
    return [fractional, plain]
}()

private let deviceDatePrinter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, yyyy"
    return formatter
}()

#Preview("Devices") {
    DevicesView(viewModel: ResourcesViewModel())
        .frame(width: 900, height: 600)
}
