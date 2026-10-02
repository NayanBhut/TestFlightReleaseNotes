//
//  DevicesView.swift
//  App Store
//
//  Devices management table from the devices-light Figma frame: toolbar
//  (title + total pill, search, platform filter, Register Device) over a
//  Device Name / UDID / Platform / Status / Added Date table. Presented as
//  the Resources devices sheet content. All data, search, pagination and
//  writes go through ResourcesViewModel; the register form is the shared
//  RegisterDeviceForm. Enable/disable lives in the row context menu — the
//  Figma rows carry no inline actions.
//

import SwiftUI

struct DevicesView: View {
    @ObservedObject var viewModel: ResourcesViewModel
    /// Sheet presentation keeps the fixed Figma-like sizing; the shell
    /// embeds the table flexibly instead.
    var fixedSize = true
    @State private var showRegisterForm = false
    /// Raw platform value filter; nil is "All".
    @State private var platformFilter: String?
    @State private var bannerError: String?

    private var searched: [DeviceModel] { viewModel.filteredDevices }

    private var visibleDevices: [DeviceModel] {
        guard let platformFilter else { return searched }
        return searched.filter { $0.platform == platformFilter }
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

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if showRegisterForm {
                RegisterDeviceForm(viewModel: viewModel) {
                    showRegisterForm = false
                }
                Divider()
            }
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
            table
        }
        // Wider than the generic resource sheet: the UDID column alone is
        // 320pt in Figma.
        .frame(minWidth: fixedSize ? 640 : 0, idealWidth: fixedSize ? 880 : nil, maxWidth: fixedSize ? 1024 : nil,
               minHeight: fixedSize ? 480 : 0, idealHeight: fixedSize ? 600 : nil, maxHeight: fixedSize ? maxSheetHeight : nil)
        .onAppear {
            viewModel.load(.devices)
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
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "iphone.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No Devices")
                            .font(.subheader)
                            .fontWeight(.medium)
                        Text("Register a device to enable development installs")
                            .font(.appBody)
                            .foregroundColor(.secondary)
                        Button("Register Device") {
                            showRegisterForm = true
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .contextMenu {
            Button(isDisabled ? "Enable" : "Disable") {
                Task { @MainActor in
                    if case .failure(let message) = await viewModel.setDeviceEnabled(
                        device, enabled: isDisabled) {
                        bannerError = message
                    } else {
                        bannerError = nil
                    }
                }
            }
            .accessibilityLabel("\(isDisabled ? "Enable" : "Disable") \(device.name ?? "device")")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(device.name ?? "Unknown device"), \(deviceStatusDisplayName(device.status))")
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

// MARK: - Display helpers

/// API platform codes to the Figma labels (unknown codes pass through).
private func devicePlatformDisplayName(_ platform: String) -> String {
    switch platform.uppercased() {
    case "IOS": return "iOS"
    case "MAC_OS": return "macOS"
    case "UNIVERSAL": return "Universal"
    default: return platform
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
