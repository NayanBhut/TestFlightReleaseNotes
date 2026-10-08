//
//  ProfileViews.swift
//  App Store
//
//  Profiles flow from the Figma frames: list status helpers, the full-screen
//  profile detail with dependency inspector + signing chain (Detail 1/2/3),
//  the delete-confirm sheet, the regenerate wizard (dependencies → review
//  impact → result), the created-success sheet with Download + Install for
//  Xcode, and the install-result sheet. API contracts (spec-verified):
//  - GET /v1/profiles supports include=bundleId,certificates,devices;
//    profileState is ACTIVE/INVALID only ("Expired" derives from
//    expirationDate); no PATCH on profiles — regenerate = DELETE + POST.
//  - Writes need an Admin key; a TestFlight-only key 403s.
//

import SwiftUI
import AppKit

// MARK: - Shared display helpers

/// "iOS App Development" via the option's display name; unknown codes
/// pass through prettified.
func profileTypeName(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else { return "—" }
    if let option = ProfileTypeOption(rawValue: raw) {
        return option.displayName
    }
    return raw
        .replacingOccurrences(of: "_", with: " ")
        .capitalized
        .replacingOccurrences(of: "Ios", with: "iOS")
        .replacingOccurrences(of: "Tvos", with: "tvOS")
}

/// "IOS" → "iOS" platform chip (Figma 3-5273 Platforms column).
func profilePlatformChip(_ raw: String?) -> String {
    switch raw {
    case "IOS": return "iOS"
    case "MAC_OS": return "macOS"
    case "TVOS": return "tvOS"
    default:
        guard let raw, !raw.isEmpty else { return "—" }
        return raw
    }
}

func profileStatusColor(_ status: ProfileComputedStatus) -> Color {
    switch status {
    case .active: return ShipyardTheme.success
    case .expired: return ShipyardTheme.danger
    case .invalid: return Color(red: 1.0, green: 0.624, blue: 0.043)
    }
}

/// "Sep 22, 2027"; missing/unparseable values pass through untouched.
func profileDateText(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else { return "—" }
    if let date = ProfileModel.parseDate(raw) {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    return raw
}

/// Certificate display for inspector rows: name + serial.
func profileCertificateLabel(_ certificate: CertificateModel) -> String {
    let name = certificate.displayName ?? certificate.name ?? "Certificate"
    if let serial = certificate.serialNumber, !serial.isEmpty {
        return "\(name) · \(serial)"
    }
    return name
}

/// Expiry-derived cert status for inspector rows. The API carries no
/// revoked flag — a linkage id with no hydrated resource reads
/// "Unavailable" (the cert is gone from the team, likely revoked).
func profileCertificateStatus(_ certificate: CertificateModel?) -> String {
    guard let certificate else { return "Unavailable" }
    if let raw = certificate.expirationDate,
       let date = ProfileModel.parseDate(raw), date < Date() {
        return "Expired · \(profileDateText(raw))"
    }
    return "Active"
}

// MARK: - Profile detail (Figma 114-3781 / 3914 / 4013)

/// Full-screen profile detail: dependency inspector with jump links,
/// profile fields, signing-chain inspector, and the
/// Delete… / Regenerate… / Download action bar. Invalid and expired
/// profiles render their Figma banner variants.
struct ProfileDetailView: View {
    @ObservedObject var viewModel: ResourcesViewModel
    @EnvironmentObject private var toastCenter: ShipyardToastCenter
    var profile: ProfileModel
    var onBack: () -> Void
    var onOpenCertificate: (String) -> Void
    var onOpenBundleId: (String) -> Void
    var onOpenDevice: (String) -> Void

    @State private var detail: ProfileModel?
    @State private var detailError: String?
    @State private var isLoadingDetail = true
    @State private var isDownloading = false
    @State private var bannerError: String?
    @State private var deleteProfile: ProfileModel?
    @State private var regenerateProfile: ProfileModel?
    @State private var localKeySerials: Set<String> = []
    @State private var keyCheckDone = false

    private var shown: ProfileModel { detail ?? profile }

    private var status: ProfileComputedStatus { shown.computedStatus }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if status == .invalid {
                        DeviceStatusBanner(
                            variant: .error,
                            title: "Signing certificate revoked",
                            message: "This profile cannot be used for new signing. Select a compatible certificate and recreate the profile.")
                    } else if status == .expired {
                        DeviceStatusBanner(
                            variant: .error,
                            title: "Expired \(profileDateText(shown.expirationDate))",
                            message: "Create a compatible replacement; expiry cannot be extended by downloading the same file.")
                    }
                    if let detailError, detail == nil {
                        DeviceStatusBanner(
                            variant: .warning,
                            title: "Couldn't load profile details",
                            message: "\(detailError) Showing list data; dependency names may be missing.")
                    }
                    HStack(alignment: .top, spacing: 24) {
                        dependencyInspector
                            .frame(maxWidth: .infinity, alignment: .leading)
                        profileFields
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let bannerError {
                        Text(bannerError)
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.negative)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
            }
            Divider()
            HStack(spacing: 12) {
                Text(viewModel.lastSyncText(for: .profiles) ?? "Not synced yet")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                Spacer()
                Button("Delete…") { deleteProfile = shown }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.danger)
                Button("Regenerate…") { regenerateProfile = shown }
                    .buttonStyle(.launchSecondary)
                if isDownloading {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button("Download .\(profile.provisioningFileExtension)") {
                        Task { @MainActor in await runDownload() }
                    }
                    .buttonStyle(.launchPrimary)
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 56)
            .background(LaunchTheme.page)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShipyardTheme.tableBackground)
        .overlay {
            if isLoadingDetail, detail == nil {
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Profiles")
                                .font(.system(size: 13))
                        }
                        .foregroundColor(ShipyardTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to profiles")
                    .padding(24)
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading profile details…")
                                .font(.system(size: 13))
                                .foregroundColor(ShipyardTheme.body)
                        }
                        Spacer()
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ShipyardTheme.tableBackground)
            }
        }
        .onAppear {
            Task { @MainActor in
                await loadDetail()
                checkLocalKeys()
            }
        }
        .sheet(item: $deleteProfile) { p in
            DeleteProfileSheet(viewModel: viewModel, profile: p) {
                deleteProfile = nil
                onBack()
            }
        }
        .sheet(item: $regenerateProfile) { p in
            RegenerateProfileSheet(viewModel: viewModel, profile: p) {
                regenerateProfile = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Profiles")
                        .font(.system(size: 13))
                }
                .foregroundColor(ShipyardTheme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to profiles")
            Text(shown.name ?? "Unknown profile")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(ShipyardTheme.title)
            Text("\(status.displayName) · \(profileTypeName(shown.profileType)) · expires \(profileDateText(shown.expirationDate))")
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
        }
    }

    private var dependencyInspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dependency inspector")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            VStack(spacing: 0) {
                inspectorHeader(columns: ["Dependency", "Value", "Status", "Jump"])
                ForEach(dependencyRows, id: \.id) { row in
                    HStack(spacing: 12) {
                        Text(row.dependency)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.value)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(2)
                        Text(row.status)
                            .foregroundColor(row.statusDestructive ? ShipyardTheme.danger : ShipyardTheme.title)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(row.jumpLabel) { row.jump() }
                            .buttonStyle(.link)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(minHeight: 38, alignment: .leading)
                    .background(row.striped ? LaunchTheme.page : ShipyardTheme.tableBackground)
                    ShipyardTheme.rowDivider.frame(height: 1)
                }
            }
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(ShipyardTheme.rowDivider, lineWidth: 1))
        }
    }

    private struct DependencyRow: Identifiable {
        var id: String
        var dependency: String
        var value: String
        var status: String
        var statusDestructive: Bool
        var jumpLabel: String
        var jump: () -> Void
        var striped = false
    }

    private var dependencyRows: [DependencyRow] {
        var rows: [DependencyRow] = []
        var stripe = false
        func append(_ row: DependencyRow) {
            var copy = row
            copy.striped = stripe
            stripe.toggle()
            rows.append(copy)
        }
        let certificates = shown.certificates
        if certificates.isEmpty {
            append(DependencyRow(
                id: "cert-none", dependency: "Certificate", value: "—",
                status: "Unavailable", statusDestructive: true,
                jumpLabel: "", jump: {}))
        } else {
            for certificate in certificates {
                let certStatus = profileCertificateStatus(certificate)
                append(DependencyRow(
                    id: "cert-\(certificate.id)", dependency: "Certificate",
                    value: profileCertificateLabel(certificate),
                    status: certStatus,
                    statusDestructive: certStatus != "Active",
                    jumpLabel: "Open Certificate →",
                    jump: { onOpenCertificate(certificate.displayName ?? certificate.name ?? "") }))
            }
        }
        append(DependencyRow(
            id: "profile", dependency: "Profile",
            value: shown.name ?? "—", status: status.displayName,
            statusDestructive: status != .active,
            jumpLabel: "Copy Profile ID →",
            jump: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(shown.id, forType: .string)
            }))
        if let bundle = shown.bundleId {
            append(DependencyRow(
                id: "bundle", dependency: "Bundle ID",
                value: bundle.identifier ?? bundle.id,
                status: "Explicit / \(profilePlatformChip(bundle.platform))",
                statusDestructive: false,
                jumpLabel: "Open Bundle ID →",
                jump: { onOpenBundleId(bundle.identifier ?? "") }))
        } else {
            append(DependencyRow(
                id: "bundle", dependency: "Bundle ID", value: "—",
                status: "Unavailable", statusDestructive: true,
                jumpLabel: "", jump: {}))
        }
        let devices = shown.devices
        if devices.isEmpty {
            append(DependencyRow(
                id: "device-none", dependency: "Device",
                value: shownAllowsDevices ? "None selected" : "Not applicable",
                status: shownAllowsDevices ? "—" : "Skipped",
                statusDestructive: false,
                jumpLabel: "", jump: {}))
        } else {
            for device in devices {
                append(DependencyRow(
                    id: "device-\(device.id)", dependency: "Device",
                    value: device.name ?? device.udid ?? device.id,
                    status: device.status == "ENABLED" ? "Enabled" : (device.status ?? "—"),
                    statusDestructive: false,
                    jumpLabel: "Open Device →",
                    jump: { onOpenDevice(device.name ?? device.udid ?? "") }))
            }
        }
        return rows
    }

    private var shownAllowsDevices: Bool {
        ProfileTypeOption(rawValue: shown.profileType ?? "")?.allowsDevices ?? true
    }

    private func inspectorHeader(columns: [String]) -> some View {
        HStack(spacing: 12) {
            ForEach(columns, id: \.self) { column in
                Text(column)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(size: 11))
        .foregroundColor(ShipyardTheme.body)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(ShipyardTheme.tableHeader)
    }

    private var profileFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Profile details")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            detailField(label: "Type / platform",
                        value: "\(profileShortKind) · \(profilePlatformChip(shown.platform))")
            detailField(label: "Expiration", value: profileDateText(shown.expirationDate))
            detailField(label: "Name", value: shown.name ?? "—")
            Text("SIGNING CHAIN")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
                .padding(.top, 8)
            Text("Certificate → Profile → Bundle ID → Device. All selected signing resources must remain compatible.")
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
                .fixedSize(horizontal: false, vertical: true)
            detailField(label: "Private key", value: privateKeyStatus)
        }
    }

    private var profileShortKind: String {
        ProfileTypeOption(rawValue: shown.profileType ?? "")?.shortKindName
            ?? profileTypeName(shown.profileType)
    }

    private var privateKeyStatus: String {
        guard keyCheckDone else { return "Checking keychain…" }
        let serials = shown.certificates.compactMap(\.serialNumber).filter { !$0.isEmpty }
        guard !serials.isEmpty else { return "No certificate to check" }
        let found = serials.filter { localKeySerials.contains($0.uppercased()) }
        if found.isEmpty { return "Not found locally" }
        return "\(found.joined(separator: ", ")) · found locally"
    }

    private func detailField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.title)
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LaunchTheme.page)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(LaunchTheme.border, lineWidth: 1))
        }
    }

    private func loadDetail() async {
        defer { isLoadingDetail = false }
        do {
            detail = try await viewModel.fetchProfileDetail(id: profile.id)
            detailError = nil
        } catch is CancellationError {
            // Task torn down with the view — nothing to report.
        } catch {
            detailError = (error as? APIError)?.details ?? error.localizedDescription
        }
    }

    private func checkLocalKeys() {
        let serials = (detail ?? profile).certificates.compactMap(\.serialNumber)
        var found: Set<String> = []
        for serial in serials where ResourcesViewModel.hasLocalIdentity(serialNumber: serial) {
            found.insert(serial.uppercased())
        }
        localKeySerials = found
        keyCheckDone = true
    }

    private func runDownload() async {
        isDownloading = true
        defer { isDownloading = false }
        bannerError = nil
        switch await viewModel.downloadProfile(shown) {
        case .success:
            toastCenter.show("Profile downloaded", variant: .success)
        case .failure(let message):
            bannerError = message
            toastCenter.show("Couldn't download profile", detail: message, variant: .error)
        case .ignored:
            break
        }
    }
}

// MARK: - Delete profile sheet (Figma 114-4237)

/// Delete confirm with type-name-to-confirm and the Dependency/Effect
/// table (certs stay valid, bundle ID and devices untouched).
struct DeleteProfileSheet: View {
    @ObservedObject var viewModel: ResourcesViewModel
    @EnvironmentObject private var toastCenter: ShipyardToastCenter
    var profile: ProfileModel
    var onDone: () -> Void
    @State private var confirmation = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var name: String { profile.name ?? "This profile" }

    private var confirmed: Bool {
        !name.isEmpty
            && confirmation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                == name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var effectRows: [(key: String, value: String)] {
        var rows = [(key: String, value: String)]()
        let serials = profile.certificates.compactMap(\.serialNumber).filter { !$0.isEmpty }
        rows.append((
            serials.isEmpty ? "Certificate" : "Certificate \(serials.joined(separator: ", "))",
            "Not revoked"))
        let bundleLabel = profile.bundleId.flatMap(\.identifier) ?? "Bundle ID"
        rows.append((bundleLabel, "Not deleted"))
        let deviceCount = profile.devices.count
        rows.append((
            deviceCount == 0 ? "Devices" : "\(deviceCount) registered device\(deviceCount == 1 ? "" : "s")",
            "Not disabled"))
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete \(name)?")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(ShipyardTheme.title)

            DeviceStatusBanner(
                variant: .warning,
                title: "Profile record removal is irreversible",
                message: "This removes the selected profile from the team. Local downloaded copies are not automatically removed. Future builds should use another valid compatible profile.")

            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm profile")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                Text("This does not remove current App Store versions or delete the app record.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Type profile name")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
                TextField(name, text: $confirmation)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .disabled(isSaving)
            }

            PermissionSummaryTable(
                title: "",
                keyHeader: "Dependency", valueHeader: "Effect",
                rows: effectRows)

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
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button("Delete Profile") {
                        Task { @MainActor in
                            isSaving = true
                            defer { isSaving = false }
                            errorMessage = nil
                            switch await viewModel.deleteProfile(id: profile.id) {
                            case .success:
                                toastCenter.show("Profile deleted", variant: .success)
                                onDone()
                            case .failure(let message):
                                toastCenter.show("Couldn't delete profile", detail: message, variant: .error)
                                errorMessage = message
                            case .ignored: break
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(confirmed ? ShipyardTheme.danger : ShipyardTheme.body.opacity(0.4))
                    .cornerRadius(6)
                    .disabled(!confirmed)
                    .accessibilityLabel("Delete profile")
                }
            }
        }
        .padding(24)
        .frame(minWidth: 480, idealWidth: 560, maxWidth: 640)
    }
}

// MARK: - Regenerate wizard (Figma 114-4103 / 4164 / 4204)

/// Delete-and-recreate for invalid/expired profiles: pick a compatible
/// certificate + device set (same type and bundle ID), review the
/// old-vs-replacement impact, then Delete & Recreate. The review copy is
/// explicit that a failed create leaves no replacement.
struct RegenerateProfileSheet: View {
    @ObservedObject var viewModel: ResourcesViewModel
    var profile: ProfileModel
    var onDone: () -> Void
    @EnvironmentObject private var toastCenter: ShipyardToastCenter

    private enum RegenStage {
        case dependencies
        case review
        case result
    }

    @State private var stage = RegenStage.dependencies
    @State private var detail: ProfileModel?
    @State private var certificateIds: Set<String> = []
    @State private var deviceIds: Set<String> = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var newProfileName: String?

    private var profileType: ProfileTypeOption? {
        ProfileTypeOption(rawValue: profile.profileType ?? "")
    }

    private var developmentKind: Bool {
        profileType?.needsDevelopmentCertificates ?? true
    }

    private var allowsDevices: Bool {
        profileType?.allowsDevices ?? false
    }

    private var bundleName: String {
        let bundle = detail?.bundleId ?? profile.bundleId
        return bundle?.identifier ?? bundle?.name ?? "—"
    }

    private var certificates: [CertificateModel] {
        viewModel.certificatesState.loadedValue ?? []
    }

    private var devices: [DeviceModel] {
        viewModel.devicesState.loadedValue ?? []
    }

    /// Only active certs of the matching kind (Figma: "Only active
    /// distribution certificates appear as selectable replacements").
    private var eligibleCertificates: [CertificateModel] {
        certificates.filter { cert in
            guard let option = cert.certificateType.flatMap(CertificateTypeOption.init(rawValue:)) else { return false }
            guard option.matchesKind(development: developmentKind) else { return false }
            if let raw = cert.expirationDate,
               let date = ProfileModel.parseDate(raw), date < Date() { return false }
            return true
        }
    }

    private var eligibleDevices: [DeviceModel] {
        devices.filter { device in
            (device.status ?? "") == "ENABLED"
                && devicePlatformMatches(device.platform, profilePlatform: profile.platform)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if stage == .result {
                regenerateResult
            } else {
                Text(stage == .dependencies
                     ? "Regenerate \(profile.name ?? "profile")"
                     : "Review delete-and-recreate impact")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(ShipyardTheme.title)
                regenStepper
                if stage == .dependencies {
                    dependenciesStep
                } else {
                    reviewStep
                }
            }

            if let errorMessage, stage != .result {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if stage != .result {
                HStack {
                    Spacer()
                    if stage == .dependencies {
                        Button("Cancel") { onDone() }
                            .buttonStyle(.launchSecondary)
                            .disabled(isSaving)
                        Button("Review Replacement") { withAnimation { stage = .review } }
                            .buttonStyle(.launchPrimary)
                            .disabled(isSaving || certificateIds.isEmpty)
                    } else {
                        Button("Back") { withAnimation { stage = .dependencies } }
                            .buttonStyle(.launchSecondary)
                            .disabled(isSaving)
                        if isSaving {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Button("Delete & Recreate") {
                                Task { @MainActor in await runRegenerate() }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(ShipyardTheme.danger)
                            .cornerRadius(6)
                            .accessibilityLabel("Delete and recreate profile")
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 520, idealWidth: 600, maxWidth: 680)
        .onAppear {
            viewModel.loadAllPages(.certificates)
            viewModel.loadAllPages(.devices)
            Task { @MainActor in
                do {
                    let loaded = try await viewModel.fetchProfileDetail(id: profile.id)
                    detail = loaded
                    // Preselect the profile's current eligible devices.
                    deviceIds = Set(loaded.devices.map(\.id).filter { id in
                        eligibleDevices.contains(where: { $0.id == id })
                    })
                } catch is CancellationError {
                } catch {
                    errorMessage = (error as? APIError)?.details ?? error.localizedDescription
                }
            }
        }
    }

    private var regenStepper: some View {
        HStack(spacing: 8) {
            regenStage(label: "Dependencies", active: stage == .dependencies, done: stage != .dependencies)
            regenStage(label: "Review", active: stage == .review, done: false)
            regenStage(label: "Result", active: false, done: false)
        }
    }

    private func regenStage(label: String, active: Bool, done: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Rectangle()
                .fill(active || done ? ShipyardTheme.accent : ShipyardTheme.rowDivider)
                .frame(height: 3)
                .cornerRadius(2)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(active ? ShipyardTheme.accent : ShipyardTheme.body)
        }
        .frame(maxWidth: .infinity)
    }

    private var dependenciesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compatible replacement")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            Text(developmentKind
                 ? "Only active development certificates appear as selectable replacements."
                 : "Only active distribution certificates appear as selectable replacements. Development certificates are excluded.")
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
                .fixedSize(horizontal: false, vertical: true)
            profileReadOnlyField(label: "Profile type",
                                 value: "\(profileTypeName(profile.profileType)) · \(profilePlatformChip(profile.platform))")
            profileReadOnlyField(label: "Bundle ID", value: bundleName)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text(certificateIds.isEmpty
                         ? "CERTIFICATES" : "CERTIFICATES (\(certificateIds.count) SELECTED)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ShipyardTheme.body)
                    Spacer(minLength: 0)
                    Button("Select All") {
                        certificateIds = Set(eligibleCertificates.map(\.id))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ShipyardTheme.accent)
                    .disabled(isSaving || eligibleCertificates.isEmpty)
                    .accessibilityLabel("Select all eligible certificates")
                    Button("Clear") {
                        certificateIds = []
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ShipyardTheme.body)
                    .disabled(isSaving || certificateIds.isEmpty)
                }
                ForEach(eligibleCertificates, id: \.id) { cert in
                    Toggle(isOn: Binding(
                        get: { certificateIds.contains(cert.id) },
                        set: { checked in
                            if checked { certificateIds.insert(cert.id) }
                            else { certificateIds.remove(cert.id) }
                        })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profileCertificateLabel(cert))
                                    .font(.system(size: 13))
                                    .foregroundColor(ShipyardTheme.title)
                                Text("Active · \(profilePlatformChip(cert.platform))")
                                    .font(.system(size: 11))
                                    .foregroundColor(ShipyardTheme.body)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(isSaving)
                        .padding(.vertical, 4)
                }
                if eligibleCertificates.isEmpty {
                    Text("No active compatible certificates — create one first.")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                }
            }
            if allowsDevices {
                HStack(spacing: 12) {
                    Text(deviceIds.isEmpty
                         ? "DEVICES" : "DEVICES (\(deviceIds.count) SELECTED)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ShipyardTheme.body)
                    Spacer(minLength: 0)
                    Button("Select All") {
                        deviceIds = Set(eligibleDevices.map(\.id))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ShipyardTheme.accent)
                    .disabled(isSaving || eligibleDevices.isEmpty)
                    .accessibilityLabel("Select all eligible devices")
                    Button("Clear") {
                        deviceIds = []
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ShipyardTheme.body)
                    .disabled(isSaving || deviceIds.isEmpty)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(eligibleDevices, id: \.id) { device in
                            Toggle(isOn: Binding(
                                get: { deviceIds.contains(device.id) },
                                set: { checked in
                                    if checked { deviceIds.insert(device.id) }
                                    else { deviceIds.remove(device.id) }
                                })) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.name ?? "Unknown device")
                                            .font(.system(size: 13))
                                            .foregroundColor(ShipyardTheme.title)
                                        Text("Enabled · \(profilePlatformChip(device.platform))")
                                            .font(.system(size: 11))
                                            .foregroundColor(ShipyardTheme.body)
                                    }
                                }
                                .toggleStyle(.checkbox)
                                .disabled(isSaving)
                                .padding(.vertical, 4)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            DeviceStatusBanner(
                variant: .warning,
                title: "Regeneration replaces the profile record",
                message: "The old \(statusWord) \(profile.name ?? "profile") profile is deleted, then a new profile is created with a new identifier. If creation fails after deletion, no replacement exists yet.")
            Text("Required follow-up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            Text("Download the replacement, update Xcode / CI to use it, and re-sign future builds. This does not automatically modify uploaded App Store builds or revoke the replacement certificate.")
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
                .fixedSize(horizontal: false, vertical: true)
            oldReplacementTable
        }
    }

    private var statusWord: String {
        switch profile.computedStatus {
        case .invalid: return "invalid"
        case .expired: return "expired"
        case .active: return "active"
        }
    }

    private var oldReplacementTable: some View {
        let oldCert = (detail?.certificates ?? profile.certificates).first
            .map(profileCertificateLabel) ?? "—"
        let newCerts = eligibleCertificates
            .filter { certificateIds.contains($0.id) }
            .map(profileCertificateLabel)
        let newCert = newCerts.isEmpty ? "—"
            : newCerts.count == 1 ? newCertSerial(newCerts[0])
            : "\(newCerts.count) certificates"
        let oldDeviceCount = (detail?.devices ?? profile.devices).count
        let rows = [
            ("Signing certificate",
             oldCertSerial(oldCert),
             newCertSerial(newCert)),
            ("Device set",
             "\(oldDeviceCount) iOS device\(oldDeviceCount == 1 ? "" : "s")",
             "\(deviceIds.count) enabled device\(deviceIds.count == 1 ? "" : "s")"),
            ("Profile identity", "Old profile ID", "New ID / new file"),
        ]
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Property").frame(maxWidth: .infinity, alignment: .leading)
                Text("Old").frame(maxWidth: .infinity, alignment: .leading)
                Text("Replacement").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 11))
            .foregroundColor(ShipyardTheme.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(ShipyardTheme.tableHeader)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 12) {
                    Text(row.0).frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.2).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.title)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(minHeight: 38, alignment: .leading)
                .background(index % 2 == 0 ? ShipyardTheme.tableBackground : LaunchTheme.page)
                if index < rows.count - 1 {
                    ShipyardTheme.rowDivider.frame(height: 1)
                }
            }
        }
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ShipyardTheme.rowDivider, lineWidth: 1))
    }

    private func oldCertSerial(_ label: String) -> String {
        // "Apple Development · 7168F2F9" → "7168F2F9 · revoked-ish" is
        // unknowable; show the label's serial half when present.
        let parts = label.components(separatedBy: " · ")
        if parts.count == 2 { return "\(parts[1]) · replaced" }
        return label
    }

    private func newCertSerial(_ label: String) -> String {
        let parts = label.components(separatedBy: " · ")
        if parts.count == 2 { return "\(parts[1]) · active" }
        return label
    }

    private var regenerateResult: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Profile recreated")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(ShipyardTheme.title)
            DeviceStatusBanner(
                variant: .success,
                title: "\(newProfileName ?? "Replacement") · Active",
                message: "New profile ID and file created. The previous profile record was removed.")
            Text("Update Xcode and CI references before the next signing operation.")
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
            HStack {
                Spacer()
                Button("Download Replacement") {
                    Task { @MainActor in await runDownloadReplacement() }
                }
                .buttonStyle(.launchSecondary)
                Button("Open Profile") { onDone() }
                    .buttonStyle(.launchPrimary)
            }
        }
    }

    private func profileReadOnlyField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.title)
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LaunchTheme.page)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(LaunchTheme.border, lineWidth: 1))
        }
    }

    private func runRegenerate() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        guard let bundleId = (detail?.bundleId ?? profile.bundleId)?.id, !bundleId.isEmpty else {
            errorMessage = "Couldn't determine the profile's bundle ID — reload and try again."
            return
        }
        let result = await viewModel.regenerateProfile(
            profileId: profile.id,
            name: profile.name ?? "Regenerated profile",
            profileType: profileType ?? .IOS_APP_DEVELOPMENT,
            bundleIdId: bundleId,
            certificateIds: certificateIds,
            deviceIds: deviceIds)
        switch result {
        case .success:
            // Name the profile this regenerate actually created. Reading
            // `first` from the list labelled the replacement with whichever
            // profile happened to be first (BUG-4).
            newProfileName = viewModel.profilesState.loadedValue?
                .first { $0.id == viewModel.lastRegeneratedProfileId }?
                .name
                ?? profile.name
            toastCenter.show("Profile regenerated", detail: newProfileName, variant: .success)
            stage = .result
        case .failure(let message):
            errorMessage = message
            toastCenter.show("Couldn't regenerate profile", detail: message, variant: .error)
        case .ignored:
            break
        }
    }

    private func runDownloadReplacement() async {
        guard let replacement = viewModel.profilesState.loadedValue?
            .first(where: { $0.id == viewModel.lastRegeneratedProfileId }) else { return }
        switch await viewModel.downloadProfile(replacement) {
        case .success:
            toastCenter.show("Profile downloaded", variant: .success)
        case .failure(let message):
            errorMessage = message
            toastCenter.show("Couldn't download profile", detail: message, variant: .error)
        case .ignored:
            break
        }
    }
}

// MARK: - Created success + Xcode install (Figma 114-3716 / 114-3746)

/// Post-create success (Figma 114-3716): Download the provisioning file,
/// Install for Xcode (save panel rooted at Xcode's provisioning
/// directory — works sandboxed), then Done.
struct ProfileCreatedSheet: View {
    @ObservedObject var viewModel: ResourcesViewModel
    var profile: ProfileModel
    var onDone: () -> Void
    @EnvironmentObject private var toastCenter: ShipyardToastCenter
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var installResult: ResourcesViewModel.ProfileInstallOutcome?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch installResult {
            case .success(let fileName, let directory, let fileURL):
                ProfileInstallResultSheet(
                    fileName: fileName, directory: directory, fileURL: fileURL,
                    onOpenProfile: onDone, onDone: onDone)
            case .failure, .ignored, nil:
                Text("Provisioning profile created")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(ShipyardTheme.title)
                DeviceStatusBanner(
                    variant: .success,
                    title: profile.name ?? "Profile",
                    message: "\(profileTypeName(profile.profileType)) · \(profilePlatformChip(profile.platform)) · expires \(profileDateText(profile.expirationDate)). Download and install this new file before using it in Xcode.")
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.negative)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    if isWorking {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Button("Download .\(profile.provisioningFileExtension)") {
                            Task { @MainActor in await runDownload() }
                        }
                        .buttonStyle(.launchSecondary)
                        Button("Install for Xcode") {
                            Task { @MainActor in await runInstall() }
                        }
                        .buttonStyle(.launchSecondary)
                    }
                    Button("Done") { onDone() }
                        .buttonStyle(.launchPrimary)
                        .disabled(isWorking)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 480, idealWidth: 560, maxWidth: 640)
    }

    private func runDownload() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        switch await viewModel.downloadProfile(profile) {
        case .success:
            toastCenter.show("Profile downloaded", variant: .success)
        case .failure(let message):
            errorMessage = message
            toastCenter.show("Couldn't download profile", detail: message, variant: .error)
        case .ignored:
            break
        }
    }

    private func runInstall() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        switch await viewModel.installProfileForXcode(profile) {
        case .success(let fileName, let directory, let fileURL):
            installResult = .success(fileName: fileName, directory: directory, fileURL: fileURL)
            toastCenter.show("Profile installed", detail: fileName, variant: .success)
        case .failure(let message):
            errorMessage = message
            toastCenter.show("Couldn't install profile", detail: message, variant: .error)
        case .ignored:
            break
        }
    }
}

/// Install-for-Xcode result (Figma 114-3746): file + install location
/// with Reveal File and Open Profile actions.
struct ProfileInstallResultSheet: View {
    var fileName: String
    var directory: URL
    var fileURL: URL
    var onOpenProfile: () -> Void
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Profile installed for Xcode")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(ShipyardTheme.title)
            DeviceStatusBanner(
                variant: .success,
                title: "Installation complete",
                message: "The provisioning file has a local install destination.")
            VStack(alignment: .leading, spacing: 8) {
                Text("Local output")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                Text("Xcode's installation location can vary by version; verify on your system.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
                    .fixedSize(horizontal: false, vertical: true)
                installField(label: "File", value: fileName)
                installField(label: "Install location", value: directory.path)
            }
            HStack {
                Spacer()
                Button("Reveal File") {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
                .buttonStyle(.launchSecondary)
                Button("Open Profile") { onOpenProfile() }
                    .buttonStyle(.launchSecondary)
                Button("Done") { onDone() }
                    .buttonStyle(.launchPrimary)
            }
        }
    }

    private func installField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.title)
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LaunchTheme.page)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(LaunchTheme.border, lineWidth: 1))
        }
    }
}

// MARK: - Eligibility helpers (shared by wizard + regenerate)

/// Device usable in a profile of the given platform: enabled, with a
/// matching (or universal) platform. Disabled and mismatched devices
/// render as excluded rows, never selectable.
func devicePlatformMatches(_ devicePlatform: String?, profilePlatform: String?) -> Bool {
    let platform = (devicePlatform ?? "").uppercased()
    if platform.isEmpty || platform == "UNIVERSAL" { return true }
    let want = (profilePlatform ?? "IOS").uppercased()
    return platform == want
}
