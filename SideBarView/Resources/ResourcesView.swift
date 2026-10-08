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

enum IdentifierResourceKind: String, CaseIterable, Identifiable {
    case merchantIds
    case passTypeIds
    case appGroups

    var id: String { rawValue }

    var title: String {
        switch self {
        case .merchantIds: return "Merchant IDs"
        case .passTypeIds: return "Pass Type IDs"
        case .appGroups: return "App Groups"
        }
    }

    var resourceKind: ResourcesViewModel.Kind? {
        switch self {
        case .merchantIds: return .merchantIds
        case .passTypeIds: return .passTypeIds
        case .appGroups: return nil
        }
    }

    var promptName: String {
        switch self {
        case .merchantIds: return "Store Apple Pay"
        case .passTypeIds: return "Loyalty Pass"
        case .appGroups: return "Shared App Group"
        }
    }

    var promptIdentifier: String {
        switch self {
        case .merchantIds: return "merchant.com.example.store"
        case .passTypeIds: return "pass.com.example.loyalty"
        case .appGroups: return "group.com.example.shared"
        }
    }

    var createTitle: String {
        switch self {
        case .merchantIds: return "Create Merchant ID"
        case .passTypeIds: return "Create Pass Type ID"
        case .appGroups: return "Create App Group"
        }
    }

    var help: String {
        switch self {
        case .merchantIds:
            return "Merchant IDs back Apple Pay certificates and can be reused by multiple apps."
        case .passTypeIds:
            return "Pass Type IDs are required before creating Wallet pass certificates."
        case .appGroups:
            return "Apple's public App Store Connect API does not expose App Group create/list endpoints. Register App Groups in Apple Developer, then enable the App Groups capability from a Bundle ID."
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
    @EnvironmentObject private var toastCenter: ShipyardToastCenter
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
                    Text("40 hex characters for older devices, or 25 characters as 8 + dash + 16 for iPhone XS (A12) and newer.")
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
                                toastCenter.show("Device registered", detail: name, variant: .success)
                                onDone()
                            } else if case .failure(let message) = result {
                                // .ignored: duplicate in flight / cancelled —
                                // keep the form open, nothing was registered.
                                errorMessage = message
                                toastCenter.show("Couldn't register device", detail: message, variant: .error)
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
    @EnvironmentObject private var toastCenter: ShipyardToastCenter
    @State private var certificateType: CertificateTypeOption = .IOS_DEVELOPMENT
    @State private var relatedResourceId = ""
    /// Loaded CSR content (never displayed — file name is shown instead).
    @State private var csrContent = ""
    @State private var csrFileName: String?
    @State private var isSaving = false
    @State private var isDownloading = false
    @State private var didDownload = false
    @State private var errorMessage: String?
    /// Set on create success (the new row is prepended, so it is first).
    /// The form swaps to a success step offering the .cer download instead
    /// of dismissing — there is no other path to the file in this app.
    @State private var createdCertificate: CertificateModel?

    var body: some View {
        VStack(spacing: 0) {
            if let created = createdCertificate {
                CreateSuccessView(
                    title: "Certificate Created",
                    message: "“\(created.displayName ?? created.name ?? "Certificate")” is ready. Download the .cer file to install it into Keychain Access.",
                    downloadLabel: "Download .cer",
                    didDownload: didDownload,
                    isDownloading: isDownloading,
                    errorMessage: errorMessage,
                    onDownload: { download(created) },
                    onDone: onDone
                )
            } else {
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
                        ForEach(CertificateTypeOption.creatableCases, id: \.self) { option in
                            Button(option.displayName) {
                                let oldRelationship = certificateType.requiredCreateRelationship
                                certificateType = option
                                if oldRelationship != option.requiredCreateRelationship {
                                    relatedResourceId = ""
                                }
                                // Drop the previous submit error: leaving it up
                                // showed "you already have a current iOS
                                // Development certificate" *after* the type had
                                // been changed to Mac App Distribution, so the
                                // message described an input the user had just
                                // moved away from.
                                errorMessage = nil
                            }
                        }
                    } label: {
                        HStack {
                            Text(certificateType.displayName)
                                .font(.system(size: 13))
                                .foregroundColor(ShipyardTheme.title)
                            Spacer()
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

                    Link("Developer ID certificates must be created on the Apple Developer website or in Xcode.",
                         destination: URL(string: "https://developer.apple.com/help/account/certificates/create-developer-id-certificates/")!)
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.accent)
                }

                if let relationship = certificateType.requiredCreateRelationship {
                    relationshipField(relationship)
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
                                certificateType: certificateType,
                                csrContent: csrContent,
                                relatedResourceId: relatedResourceId)
                            if case .success = result {
                                // Always safe now: prependCertificate/prependProfile
                                // seed the list with the server-confirmed model even
                                // when the list wasn't loaded, so `first` is the cert
                                // just created (BUG_SWEEP #12).
                                createdCertificate = viewModel.certificatesState.loadedValue?.first
                                didDownload = false
                                errorMessage = nil
                                toastCenter.show("Certificate created", detail: certificateType.displayName, variant: .success)
                            } else if case .failure(let message) = result {
                                // .ignored: duplicate in flight / cancelled —
                                // keep the form open, nothing was created.
                                errorMessage = message
                                toastCenter.show("Couldn't create certificate", detail: message, variant: .error)
                            }
                        }
                    }
                    .buttonStyle(.launchPrimary)
                    .disabled(!canCreate)
                }
            }
            .padding(16)
            .background(ShipyardTheme.sidebarBackground)
            .overlay(
                ShipyardTheme.rowDivider.frame(height: 1),
                alignment: .top
            )
            }
        }
        .frame(width: 560)
    }

    private var canCreate: Bool {
        !csrContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (certificateType.requiredCreateRelationship == nil
                || !relatedResourceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func relationshipField(_ relationship: CertificateCreateRelationshipKind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(relationship.label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ShipyardTheme.body)
            relationshipPicker(relationship)
            TextField(relationship.prompt, text: $relatedResourceId)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(LaunchTheme.field)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(LaunchTheme.border, lineWidth: 1)
                )
                .disabled(isSaving)
                .accessibilityLabel(relationship.prompt)
                .onChange(of: relatedResourceId) { _ in errorMessage = nil }
            Text(relationship.help)
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: relationship) {
            viewModel.loadCertificateRelationshipOptions(relationship)
        }
    }

    @ViewBuilder
    private func relationshipPicker(_ relationship: CertificateCreateRelationshipKind) -> some View {
        switch viewModel.certificateRelationshipOptionsState(for: relationship) {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text(relationship.loadingMessage)
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
            }
        case .loaded(let options):
            if !options.isEmpty {
                Menu {
                    ForEach(options) { option in
                        Button(option.displayName) {
                            relatedResourceId = option.id
                            errorMessage = nil
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedRelationshipTitle(for: relationship, options: options))
                            .font(.system(size: 13))
                            .foregroundColor(ShipyardTheme.title)
                            .lineLimit(1)
                        Spacer()
                        Text("⌄")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
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
                .accessibilityLabel("Choose \(relationship.label.lowercased())")
            }
        case .empty:
            Text(relationship.emptyMessage)
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .fixedSize(horizontal: false, vertical: true)
        case .error(let message):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.negative)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry") {
                    viewModel.loadCertificateRelationshipOptions(relationship, force: true)
                }
                .buttonStyle(.launchSecondary)
                .disabled(isSaving)
            }
        }
    }

    private func selectedRelationshipTitle(
        for relationship: CertificateCreateRelationshipKind,
        options: [CertificateRelationshipOption]
    ) -> String {
        let trimmedId = relatedResourceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return relationship.pickerTitle }
        if let option = options.first(where: { $0.id == trimmedId }) {
            return option.displayName
        }
        return trimmedId
    }

    private func download(_ certificate: CertificateModel) {
        Task { @MainActor in
            isDownloading = true
            defer { isDownloading = false }
            switch await viewModel.downloadCertificate(certificate) {
            case .success:
                didDownload = true
                errorMessage = nil
                toastCenter.show("Certificate downloaded", variant: .success)
            case .failure(let message):
                errorMessage = message
                toastCenter.show("Couldn't download certificate", detail: message, variant: .error)
            case .ignored:
                break
            }
        }
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
            toastCenter.show("Couldn't read CSR", detail: error.localizedDescription, variant: .error)
        }
    }
}

// MARK: - Create success + signing-file download

/// Post-create step shared by the certificate/profile sheets: confirms the
/// created item and offers its signing file (.cer/.mobileprovision) — the
/// only download path in this app — before Done dismisses the sheet.
struct CreateSuccessView: View {
    var title: String
    var message: String
    var downloadLabel: String
    var didDownload: Bool
    var isDownloading: Bool
    var errorMessage: String?
    var onDownload: () -> Void
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(ShipyardTheme.title)
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(ShipyardTheme.sidebarBackground)
                .overlay(
                    ShipyardTheme.rowDivider.frame(height: 1),
                    alignment: .bottom
                )
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(ShipyardTheme.success)
                        .accessibilityHidden(true)
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if didDownload {
                    Text("Saved.")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.negative)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Button("Done") { onDone() }
                        .buttonStyle(.launchSecondary)
                        .disabled(isDownloading)
                    if isDownloading {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Button(downloadLabel) { onDownload() }
                            .buttonStyle(.launchPrimary)
                    }
                }
            }
            .padding(24)
        }
    }
}

/// POST /v1/bundleIds — name, identifier and platform are required;
/// seedId is optional. Needs an Admin key role; a TestFlight-only key 403s.
///
/// The sheet is a three-step machine so it never nests sheets:
/// register (Figma 114-2194 explicit / 114-2239 wildcard) → registered
/// confirmation (114-2284) → optionally the profile form (the new bundle ID
/// is preselected). Internal (not private) so the Figma bundle-IDs table
/// reuses the form.
struct CreateBundleIdForm: View {
    @ObservedObject var viewModel: ResourcesViewModel
    var onDone: () -> Void
    @EnvironmentObject private var toastCenter: ShipyardToastCenter
    /// Deep-links the new bundle ID into its detail after "Open Bundle ID".
    var onOpenBundleId: ((String) -> Void)?
    /// Team label in the registered confirmation explanation (114-2284).
    private var teamName: String {
        CredentialStorage.shared.selectedTeam?.key ?? "this team"
    }

    /// Registered resource, or nil while the form is still open. Mirrors
    /// CreateProfileForm's `createdProfile` gate.
    @State private var createdBundleId: BundleIdModel?
    @State private var showProfileForm = false
    @State private var name = ""
    @State private var identifier = ""
    @State private var platform: BundleIdPlatformOption = .IOS
    @State private var identifierKind: BundleIdIdentifierKind = .explicit
    @State private var seedId = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            BundleIDSheetChrome(title: sheetTitle, onClose: onDone) {
                if let created = createdBundleId {
                    // "Create Profile…" steps sideways instead of pushing a
                    // second sheet, so the confirmation is still on the
                    // stack when the profile form closes.
                    if showProfileForm {
                        CreateProfileForm(
                            viewModel: viewModel,
                            onDone: { showProfileForm = false },
                            presetBundleIdId: created.id
                        )
                    } else {
                        BundleIDRegisteredSheet(
                            bundleId: created,
                            teamName: teamName,
                            onCreateProfile: { showProfileForm = true },
                            onOpenBundleId: {
                                onOpenBundleId?(created.id)
                                onDone()
                            }
                        )
                    }
                } else {
                    registerForm
                }
            }
        }
        .frame(width: 680)
    }

    // MARK: - Register (114-2194 explicit / 114-2239 wildcard)

    private var registerForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            BundleIDFormSection(title: "Identifier details") {
                VStack(alignment: .leading, spacing: 12) {
                    labelledField(label: "Name", text: $name, prompt: "Orbit Companion", mono: false)
                    platformField
                    // Both choices always stay on screen: 114-2239 shows
                    // the wildcard variant with wildcard preselected, but
                    // hiding Explicit here made it a one-way door with no
                    // way back once tapped.
                    identifierChoice(.explicit)
                    identifierChoice(.wildcard)
                    VStack(alignment: .leading, spacing: 5) {
                        labelledField(
                            label: "Bundle identifier",
                            text: $identifier,
                            prompt: identifierKind == .wildcard
                                ? "com.acme.orbit.*"
                                : "com.acme.orbit.companion",
                            mono: false)
                        Text("Reverse-DNS notation. Identifier is immutable after registration.")
                            .font(.system(size: 11))
                            .foregroundColor(ShipyardTheme.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    seedIdField
                    if let errorMessage {
                        BundleIDStatusMessage(
                            symbol: "exclamationmark.triangle.fill",
                            tint: ShipyardTheme.dangerBorder,
                            surface: ShipyardTheme.dangerSurface,
                            title: "Couldn't register this bundle ID",
                            message: errorMessage
                        )
                    }
                }
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { onDone() }
                    .buttonStyle(.launchSecondary)
                    .disabled(isSaving)
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button("Register Bundle ID") { register() }
                        .buttonStyle(.launchPrimary)
                        .disabled(!canRegister)
                }
            }
        }
    }

    /// The chrome renders the heading, so the title tracks the current
    /// step: the register variant (114-2194 / 114-2239), the registered
    /// confirmation (114-2284), or the sideways-stepped profile wizard.
    /// 114-2239 shows the wildcard variant with wildcard preselected, but
    /// both radios stay on screen in that variant so Explicit is always
    /// reachable again.
    private var sheetTitle: String {
        if showProfileForm { return "Create a profile" }
        if createdBundleId != nil { return "Bundle identifier registered" }
        return identifierKind == .wildcard
            ? "Register a wildcard bundle identifier"
            : "Register an explicit bundle identifier"
    }

    private var canRegister: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func identifierChoice(_ kind: BundleIdIdentifierKind) -> some View {
        let isSelected = identifierKind == kind
        return Button {
            identifierKind = kind
            if kind == .wildcard, !identifier.hasSuffix("*") {
                // Wildcards are the trailing-* form; keep the reverse-DNS
                // prefix the user typed and append it rather than dropping
                // their input on the toggle.
                let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    identifier = "com.example.*"
                } else if !trimmed.contains("*") {
                    identifier = trimmed + ".*"
                }
            } else if kind == .explicit {
                identifier = identifier.replacingOccurrences(of: ".*", with: "")
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15))
                    .foregroundColor(isSelected ? ShipyardTheme.accent : ShipyardTheme.body)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.displayName)
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                    Text(kind.explanation)
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityLabel("\(kind.displayName) identifier")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    /// Apple only honours `seedId` for wildcard identifiers, so the field
    /// is wildcard-only and the explicit request drops it.
    @ViewBuilder
    private var seedIdField: some View {
        if identifierKind == .wildcard {
            VStack(alignment: .leading, spacing: 5) {
                labelledField(
                    label: "Seed ID (optional)",
                    text: $seedId,
                    prompt: "Team seed identifier",
                    mono: false)
                Text("Leave blank unless Apple assigned a seed ID to this identifier.")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var platformField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Platform")
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.title)
            Menu {
                ForEach(BundleIdPlatformOption.allCases, id: \.self) { option in
                    Button(option.displayName) { platform = option }
                }
            } label: {
                HStack {
                    Text(platform.displayName)
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                    Spacer()
                    Text("\u{2304}")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(minHeight: 30)
                .background(ShipyardTheme.tableBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(ShipyardTheme.rowDivider, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .disabled(isSaving)
            .accessibilityLabel("Platform")
        }
    }

    private func labelledField(label: String, text: Binding<String>, prompt: String, mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.title)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .font(mono ? .system(size: 13, design: .monospaced) : .system(size: 13))
                .foregroundColor(ShipyardTheme.title)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(minHeight: 30)
                .background(ShipyardTheme.tableBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(ShipyardTheme.rowDivider, lineWidth: 1)
                )
                .disabled(isSaving)
        }
    }

    private func register() {
        Task { @MainActor in
            isSaving = true
            errorMessage = nil
            defer { isSaving = false }
            let result = await viewModel.createBundleId(
                name: name,
                identifier: identifier,
                platform: platform,
                seedId: identifierKind == .wildcard ? seedId : nil
            )
            switch result {
            case .value(let bundleId):
                createdBundleId = bundleId
                toastCenter.show("Bundle ID registered", detail: bundleId.identifier ?? identifier, variant: .success)
            case .failure(let message):
                // .ignored: duplicate in flight / cancelled — keep the
                // form open, nothing was created.
                errorMessage = message
                toastCenter.show("Couldn't register Bundle ID", detail: message, variant: .error)
            case .ignored:
                break
            }
        }
    }

}

/// Figma 114-2284 — confirmation after a successful register. Reports the
/// three properties Apple returns on the created resource and offers the
/// two follow-on actions: continue to a profile, or open the new detail.
struct BundleIDRegisteredSheet: View {
    let bundleId: BundleIdModel
    let teamName: String
    var onCreateProfile: () -> Void
    var onOpenBundleId: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            BundleIDStatusMessage(
                symbol: "checkmark.circle.fill",
                tint: ShipyardTheme.successBorder,
                surface: ShipyardTheme.successSurface,
                title: "\(bundleId.name ?? "Bundle ID") · \(bundlePlatformDisplay(bundleId.platform))",
                message: "\(bundleId.identifier ?? "This identifier") is registered for \(teamName)."
            )

            BundleIDResourceTable(
                headers: ["Property", "Value"],
                rows: [
                    ["Identifier type", bundleId.identifierKind.displayName],
                    ["Seed / team ID", bundleId.seedId ?? "None"],
                    // A freshly registered identifier has no capability
                    // rows yet; the detail view is where they get enabled.
                    ["Capabilities", "None enabled yet"]
                ]
            )

            HStack(spacing: 8) {
                Spacer()
                Button("Create Profile…", action: onCreateProfile)
                    .buttonStyle(.launchSecondary)
                Button("Open Bundle ID", action: onOpenBundleId)
                    .buttonStyle(.launchPrimary)
            }
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
    @EnvironmentObject private var toastCenter: ShipyardToastCenter
    /// Preselected bundle ID. Set when the form is reached from the
    /// bundle-IDs "Create Profile…" action (Figma 114-2284), where the
    /// profile must belong to the identifier that was just registered.
    var presetBundleIdId: String?
    @State private var name = ""
    /// Figma 114-3320: platform picker + distribution-kind radios resolve
    /// to a concrete type; `otherType` covers In-House/Direct/Catalyst
    /// picks outside the three kinds.
    @State private var platformCode = "IOS"
    @State private var kind: ProfileTypeOption.DistributionKind? = .development
    @State private var otherType: ProfileTypeOption?
    @State private var bundleIdId: String?
    @State private var didApplyPreset = false
    @State private var certificateIds: Set<String> = []
    @State private var deviceIds: Set<String> = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var resolvedType: ProfileTypeOption? {
        ProfileTypeOption.resolve(platformCode: platformCode, kind: kind, otherType: otherType)
    }

    private var bundleIds: [BundleIdModel] { viewModel.bundleIdsState.loadedValue ?? [] }
    private var certificates: [CertificateModel] { viewModel.certificatesState.loadedValue ?? [] }
    private var devices: [DeviceModel] { viewModel.devicesState.loadedValue ?? [] }

    /// BundleId platform code implied by the platform picker. Mac
    /// Catalyst profiles take Mac bundle IDs.
    private var profileBundlePlatform: String { platformCode }

    /// Bundle IDs usable with the chosen platform. Entries without
    /// platform data are kept (unclassifiable, not necessarily wrong);
    /// UNIVERSAL matches every platform.
    private var filteredBundleIds: [BundleIdModel] {
        bundleIds.filter { bundle in
            guard let platform = bundle.platform, !platform.isEmpty else { return true }
            return platform == profileBundlePlatform || platform == "UNIVERSAL"
        }
    }

    /// Certificates shown in the wizard picker: signing identities
    /// only (Apple Pay / Pass / Identity Access / Developer ID certs
    /// can't be embedded in profiles, so they're hidden, not listed as
    /// excluded rows).
    private var signingCertificates: [CertificateModel] {
        certificates.filter { cert in
            guard let option = cert.certificateType.flatMap(CertificateTypeOption.init(rawValue:)) else {
                return false
            }
            return option.isSigningIdentity
        }
    }

    /// Certificates selectable for the resolved type: matching kind +
    /// platform, and not expired (an expired cert guarantees a 409).
    private var eligibleCertificates: [CertificateModel] {
        guard let resolved = resolvedType else { return [] }
        let development = resolved.needsDevelopmentCertificates
        return signingCertificates.filter { cert in
            guard let option = cert.certificateType.flatMap(CertificateTypeOption.init(rawValue:)),
                  option.matchesKind(development: development),
                  option.matchesPlatform(profileBundlePlatform) else { return false }
            if let raw = cert.expirationDate,
               let date = ProfileModel.parseDate(raw), date < Date() { return false }
            return true
        }
    }

    private func certificateExclusionReason(_ cert: CertificateModel) -> String? {
        guard let resolved = resolvedType else { return "No profile type selected" }
        guard let option = cert.certificateType.flatMap(CertificateTypeOption.init(rawValue:)) else {
            return "Unknown type"
        }
        if !option.matchesKind(development: resolved.needsDevelopmentCertificates) {
            return "Excluded · wrong type"
        }
        if !option.matchesPlatform(profileBundlePlatform) {
            return "Excluded · wrong platform"
        }
        if let raw = cert.expirationDate,
           let date = ProfileModel.parseDate(raw), date < Date() {
            return "Excluded · expired"
        }
        return nil
    }

    /// Devices selectable for the profile: enabled with a matching (or
    /// universal) platform. Everything else renders as an excluded row.
    private var eligibleDevices: [DeviceModel] {
        devices.filter { device in
            (device.status ?? "") == "ENABLED"
                && devicePlatformMatches(device.platform, profilePlatform: profileBundlePlatform)
        }
    }

    private func deviceExclusionReason(_ device: DeviceModel) -> String? {
        if (device.status ?? "") != "ENABLED" { return "Disabled · excluded" }
        if !devicePlatformMatches(device.platform, profilePlatform: profileBundlePlatform) {
            return "Wrong platform · excluded"
        }
        return nil
    }

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
    /// Set on create success (the new row is prepended, so it is first).
    /// Swaps the wizard to the created sheet with Download + Install for
    /// Xcode instead of dismissing.
    @State private var createdProfile: ProfileModel?

    private var canContinue: Bool {
        switch step {
        case .type:
            return resolvedType != nil
        case .bundleID:
            return bundleIdId != nil
        case .certificates:
            return !certificateIds.isEmpty
        case .devices:
            // Development/ad-hoc profiles embed devices server-side —
            // an empty pick passes the old gate and 409s on create.
            return resolvedType?.allowsDevices == false || !deviceIds.isEmpty
        case .name:
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .review:
            return true
        }
    }

    /// Retire picks invalidated by a type change: unknown bundle IDs,
    /// ineligible certificates, and devices when the new type embeds
    /// none (or that no longer match).
    private func reconcilePicks() {
        if let selected = bundleIdId,
           !filteredBundleIds.contains(where: { $0.id == selected }) {
            bundleIdId = nil
        }
        certificateIds = certificateIds.filter { id in
            eligibleCertificates.contains(where: { $0.id == id })
        }
        if resolvedType?.allowsDevices == false {
            deviceIds = []
        } else {
            deviceIds = deviceIds.filter { id in
                eligibleDevices.contains(where: { $0.id == id })
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let created = createdProfile {
                ProfileCreatedSheet(
                    viewModel: viewModel,
                    profile: created,
                    onDone: onDone
                )
            } else {
                profileWizardContent
            }
        }
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
            // Preselect once: re-applying on a later appear would stomp a
            // deliberate re-pick after the profile form reports an error.
            if let presetBundleIdId, !didApplyPreset {
                didApplyPreset = true
                bundleIdId = presetBundleIdId
                if let match = bundleIds.first(where: { $0.id == presetBundleIdId }),
                   let matchPlatform = match.platform {
                    platformCode = matchPlatform
                }
            }
        }
    }

    private var profileWizardContent: some View {
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
                    .accessibilityLabel("Back to step \(step.rawValue)")
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Platform and distribution")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            Text("macOS profiles use .provisionprofile; iOS profiles use .mobileprovision. Certificate eligibility follows both platform and profile type.")
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Platform")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
                Menu {
                    Button("iOS") { platformCode = "IOS"; kind = .development; otherType = nil; reconcilePicks() }
                    Button("macOS") { platformCode = "MAC_OS"; kind = .development; otherType = nil; reconcilePicks() }
                    Button("tvOS") { platformCode = "TVOS"; kind = .development; otherType = nil; reconcilePicks() }
                } label: {
                    HStack {
                        Text(platformDisplayName)
                            .font(.system(size: 13))
                            .foregroundColor(ShipyardTheme.title)
                        Spacer()
                        Text("⌄").font(.system(size: 12)).foregroundColor(ShipyardTheme.body)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    .background(Color.white)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(LaunchTheme.border, lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .disabled(isSaving)
                .accessibilityLabel("Select platform")
            }
            Picker("", selection: Binding(
                get: { kind },
                set: { newKind in
                    kind = newKind
                    otherType = nil
                    reconcilePicks()
                })) {
                    ForEach(ProfileTypeOption.DistributionKind.allCases, id: \.self) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.rawValue)
                                .font(.system(size: 13))
                                .foregroundColor(ShipyardTheme.title)
                            Text(item.hint)
                                .font(.system(size: 11))
                                .foregroundColor(ShipyardTheme.body)
                        }
                        .tag(ProfileTypeOption.DistributionKind?(item))
                    }
                }
                .pickerStyle(.radioGroup)
                .disabled(isSaving)
                .labelsHidden()
            if resolvedType == nil {
                Text(kind == nil
                     ? "Pick a distribution kind above, or choose an enterprise/direct type below."
                     : "This combination has no provisioning profile type (macOS has no Ad Hoc). Pick another kind or platform.")
                    .font(.system(size: 11))
                    .foregroundColor(kind == nil ? ShipyardTheme.body : AppTheme.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Menu {
                Button("None — use the kinds above") {
                    kind = .development
                    otherType = nil
                    reconcilePicks()
                }
                ForEach(ProfileTypeOption.otherTypes(for: platformCode), id: \.self) { option in
                    Button(option.displayName) {
                        kind = nil
                        otherType = option
                        reconcilePicks()
                    }
                }
            } label: {
                Text(otherType == nil ? "Other profile types…" : otherType?.displayName ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.accent)
            }
            .menuStyle(.borderlessButton)
            .disabled(isSaving)
            .accessibilityLabel("Other profile types")
        }
    }

    private var platformDisplayName: String {
        switch platformCode {
        case "MAC_OS": return "macOS"
        case "TVOS": return "tvOS"
        default: return "iOS"
        }
    }

    private var bundleStep: some View {
            ScrollView {
                LazyVStack(spacing: 8) {
                    if filteredBundleIds.isEmpty {
                        Text("No \(profileBundleDisplayName) bundle IDs found. Register one first.")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    ForEach(filteredBundleIds, id: \.id) { bundleId in
                        pickerToggleRow(
                            title: bundleId.name ?? bundleId.identifier ?? bundleId.id,
                            subtitle: bundleId.identifier,
                            isOn: Binding(
                                get: { bundleIdId == bundleId.id },
                                set: { checked in bundleIdId = checked ? bundleId.id : nil }
                            )
                        )
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

    private var profileBundleDisplayName: String {
        switch profileBundlePlatform {
        case "MAC_OS": return "Mac"
        case "TVOS": return "tvOS"
        default: return "iOS"
        }
    }

    /// Checkbox row shared by the bundle/certificate/device pickers so all
    /// three lists align identically: box + leading text pinned to the
    /// row's leading edge. Bundle rows bind single-select (tap another
    /// row moves the pick); certs/devices bind set membership.
    private func pickerToggleRow(title: String, subtitle: String?, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.title)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 13))
        .toggleStyle(.checkbox)
        .disabled(isSaving)
    }

    private var certificatesStep: some View {
            ScrollView {
                LazyVStack(spacing: 8) {
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
                    .padding([.horizontal, .top], 12)
                    if !(resolvedType?.needsDevelopmentCertificates ?? true) {
                        Text("App Store and ad-hoc profiles use distribution certificates — development certificates are excluded below.")
                            .font(.system(size: 11))
                            .foregroundColor(ShipyardTheme.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding([.horizontal, .top], 12)
                    }
                    ForEach(signingCertificates, id: \.id) { certificate in
                        if let reason = certificateExclusionReason(certificate) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(certificate.displayName ?? certificate.name ?? "Unknown certificate")
                                        .font(.system(size: 13))
                                        .foregroundColor(ShipyardTheme.body)
                                        .lineLimit(1)
                                    Text(reason)
                                        .font(.system(size: 11))
                                        .foregroundColor(ShipyardTheme.body)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 4)
                            .opacity(0.7)
                            .accessibilityLabel("\(certificate.displayName ?? "certificate"), \(reason)")
                        } else {
                            pickerToggleRow(
                                title: certificate.displayName ?? certificate.name ?? "Unknown certificate",
                                subtitle: "\(certificateTypeDisplayName(certificate.certificateType)) • Expires \(certificateExpiryDisplay(certificate.expirationDate))",
                                isOn: Binding(
                                    get: { certificateIds.contains(certificate.id) },
                                    set: { checked in
                                        if checked { certificateIds.insert(certificate.id) }
                                        else { certificateIds.remove(certificate.id) }
                                    }
                                )
                            )
                        }
                    }
                    if signingCertificates.isEmpty {
                        Text("No signing certificates found. Create a development or distribution certificate first.")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
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
            VStack(alignment: .leading, spacing: 8) {
                if resolvedType?.allowsDevices == false {
                    // Figma 114-3561: store/in-house/direct profiles skip
                    // device registration — recap instead of an empty list.
                    DeviceStatusBanner(
                        variant: .info,
                        title: "No device registration required",
                        message: "\(resolvedType?.displayName ?? "This profile type") uses a compatible distribution certificate. Devices are skipped.")
                    devicesSkippedRecap
                } else {
                HStack(spacing: 12) {
                    Text(eligibleSelectedDeviceCount == 0
                         ? "DEVICES" : "DEVICES (\(eligibleSelectedDeviceCount) SELECTED)")
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
                .padding([.horizontal, .top], 12)
                Text("Development and Ad Hoc profiles include selected enabled devices.")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                    .padding(.horizontal, 12)
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(devices, id: \.id) { device in
                            if let reason = deviceExclusionReason(device) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.name ?? "Unknown device")
                                            .font(.system(size: 13))
                                            .foregroundColor(ShipyardTheme.body)
                                            .lineLimit(1)
                                        Text(reason)
                                            .font(.system(size: 11))
                                            .foregroundColor(ShipyardTheme.body)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 4)
                                .opacity(0.7)
                            } else {
                                pickerToggleRow(
                                    title: device.name ?? "Unknown device",
                                    subtitle: "\(devicePlatformDisplayName(device.platform ?? "")) • \(device.udid ?? "")",
                                    isOn: Binding(
                                        get: { deviceIds.contains(device.id) },
                                        set: { checked in
                                            if checked { deviceIds.insert(device.id) }
                                            else { deviceIds.remove(device.id) }
                                        }
                                    )
                                )
                            }
                        }
                        if devices.isEmpty {
                            Text("No devices found. Register one first.")
                                .font(.system(size: 12))
                                .foregroundColor(ShipyardTheme.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                    }
                    .padding(12)
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

    /// Picks still valid under the current type (stale ids from a
    /// previous type are reconciled away on type change).
    private var eligibleSelectedDeviceCount: Int {
        deviceIds.filter { id in eligibleDevices.contains(where: { $0.id == id }) }.count
    }

    /// Figma 114-3561 recap for types that embed no devices.
    private var devicesSkippedRecap: some View {
        VStack(spacing: 0) {
            skippedRecapRow(stage: "Type",
                            value: resolvedType.map { "\($0.displayName) · \(platformDisplayName)" } ?? "—")
            skippedRecapRow(stage: "Bundle ID",
                            value: bundleIds.first(where: { $0.id == bundleIdId })?.identifier ?? "—")
            skippedRecapRow(stage: "Certificate",
                            value: certificateIds.compactMap { id in
                                certificates.first(where: { $0.id == id })
                            }.map { cert in
                                if let serial = cert.serialNumber, !serial.isEmpty {
                                    return "\(cert.displayName ?? cert.name ?? "Certificate") · \(serial)"
                                }
                                return cert.displayName ?? cert.name ?? "Certificate"
                            }.joined(separator: ", "))
            skippedRecapRow(stage: "Devices", value: "Not applicable · skipped")
        }
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(LaunchTheme.border, lineWidth: 1))
    }

    private func skippedRecapRow(stage: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(stage)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
        }
        .font(.system(size: 12))
        .foregroundColor(ShipyardTheme.title)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 38, alignment: .leading)
        .background(LaunchTheme.field)
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(nameRecap)
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
                .fixedSize(horizontal: false, vertical: true)
            LaunchField(label: "Profile Name", text: $name, prompt: "Acme Development")
                .disabled(isSaving)
            Text("A descriptive, unique name.")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
        }
    }

    /// "iOS Development · com.acme.orbit · John Appleseed 7168F2F9 ·
    /// 2 devices selected." (Figma 114-3614).
    private var nameRecap: String {
        var parts: [String] = []
        if let resolved = resolvedType {
            parts.append("\(platformDisplayName) \(resolved.shortKindName)")
        }
        if let bundle = bundleIds.first(where: { $0.id == bundleIdId }),
           let identifier = bundle.identifier, !identifier.isEmpty {
            parts.append(identifier)
        }
        let certs = certificateIds.compactMap { id in certificates.first(where: { $0.id == id }) }
        if certs.count == 1, let cert = certs.first {
            let label = cert.displayName ?? cert.name ?? "Certificate"
            if let serial = cert.serialNumber, !serial.isEmpty {
                parts.append("\(label) \(serial)")
            } else {
                parts.append(label)
            }
        } else if !certs.isEmpty {
            parts.append("\(certs.count) certificates")
        }
        if resolvedType?.allowsDevices == true {
            parts.append("\(eligibleSelectedDeviceCount) device\(eligibleSelectedDeviceCount == 1 ? "" : "s") selected")
        }
        return parts.joined(separator: " · ")
    }

    private var reviewStep: some View {
            VStack(alignment: .leading, spacing: 10) {
                reviewRow("Type", resolvedType.map { "\($0.displayName) · \(platformDisplayName)" } ?? "—")
                reviewRow("Bundle ID", bundleIds.first(where: { $0.id == bundleIdId }).map { "\($0.name ?? "") (\($0.identifier ?? ""))" } ?? "—")
                reviewRow("Certificates", reviewNames(
                    certificateIds.compactMap { id in certificates.first(where: { $0.id == id }) }
                        .map { $0.displayName ?? $0.name ?? "Certificate" }))
                reviewRow("Devices", devicesReviewLabel)
                reviewRow("Name", name.isEmpty ? "—" : name)
                Text("Test on a throwaway profile first. Needs an API key with the Admin role.")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
            }
    }

    private var devicesReviewLabel: String {
        guard resolvedType?.allowsDevices == true else { return "Not applicable · skipped" }
        let names = deviceIds.compactMap { id in devices.first(where: { $0.id == id }) }
            .map { $0.name ?? $0.udid ?? $0.id }
        return reviewNames(names)
    }

    private func reviewNames(_ names: [String]) -> String {
        if names.isEmpty { return "—" }
        if names.count <= 3 { return names.joined(separator: "; ") }
        return names.prefix(3).joined(separator: "; ") + " +\(names.count - 3)"
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
        guard let resolved = resolvedType else {
            let message = "Pick a valid platform and profile type first."
            errorMessage = message
            toastCenter.show("Couldn't create profile", detail: message, variant: .error)
            return
        }
        // Defensive: only eligible devices ever reach the body (the
        // devices gate + reconcilePicks enforce this in the UI).
        let eligibleIds = Set(eligibleDevices.map(\.id))
        let result = await viewModel.createProfile(
            name: name,
            profileType: resolved,
            bundleIdId: bundleIdId,
            certificateIds: certificateIds,
            deviceIds: deviceIds.intersection(eligibleIds))
        if case .success = result {
            createdProfile = viewModel.profilesState.loadedValue?.first
            errorMessage = nil
            toastCenter.show("Profile created", detail: name, variant: .success)
        } else if case .failure(let message) = result {
            // .ignored: duplicate in flight / cancelled —
            // keep the form open, nothing was created.
            errorMessage = message
            toastCenter.show("Couldn't create profile", detail: message, variant: .error)
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





// MARK: - Identifiers

struct IdentifiersTableView: View {
    @ObservedObject var viewModel: ResourcesViewModel
    @EnvironmentObject private var toastCenter: ShipyardToastCenter
    @State private var selectedKind: IdentifierResourceKind = .merchantIds
    @State private var showCreateForm = false
    @State private var bannerError: String?

    var body: some View {
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
        .onAppear { loadSelectedKind() }
        .onChange(of: selectedKind) { _, _ in loadSelectedKind() }
        .sheet(isPresented: $showCreateForm) {
            CreateIdentifierForm(kind: selectedKind, viewModel: viewModel) { result in
                showCreateForm = false
                switch result {
                case .success(let message):
                    toastCenter.show(message, variant: .success)
                case .failure(let message):
                    bannerError = message
                    toastCenter.show("Couldn't create identifier", detail: message, variant: .error)
                case .ignored:
                    break
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Identifiers")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                ShipyardCountPill(text: totalText)
            }

            Menu {
                ForEach(IdentifierResourceKind.allCases) { kind in
                    Button(kind.title) { selectedKind = kind }
                }
            } label: {
                ShipyardMenuLabel(text: selectedKind.title)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Identifier type")

            Spacer()

            if let resourceKind = selectedKind.resourceKind {
                ShipyardSearchField(prompt: "Search \(selectedKind.title)", text: viewModel.searchBinding(for: resourceKind))
            }

            Button(selectedKind.createTitle) {
                showCreateForm = true
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(selectedKind.resourceKind == nil ? Color.gray.opacity(0.55) : ShipyardTheme.accent)
            .cornerRadius(6)
            .buttonStyle(.plain)
            .disabled(selectedKind.resourceKind == nil)
            .accessibilityLabel(selectedKind.createTitle)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(LaunchTheme.page)
    }

    private var totalText: String {
        guard let kind = selectedKind.resourceKind else { return "Unsupported" }
        if let total = viewModel.totals[kind] {
            return "\(total) Total"
        }
        return "\(viewModel.loadedCount(for: kind)) Total"
    }

    @ViewBuilder
    private var table: some View {
        switch selectedKind {
        case .merchantIds:
            identifierTable(
                state: viewModel.merchantIdsState,
                rows: viewModel.filteredMerchantIds.map {
                    IdentifierRow(id: $0.id, name: $0.name, identifier: $0.identifier, type: "Merchant ID")
                },
                kind: .merchantIds,
                emptyTitle: "No Merchant IDs",
                emptyMessage: "Create a Merchant ID before issuing Apple Pay certificates."
            )
        case .passTypeIds:
            identifierTable(
                state: viewModel.passTypeIdsState,
                rows: viewModel.filteredPassTypeIds.map {
                    IdentifierRow(id: $0.id, name: $0.name, identifier: $0.identifier, type: "Pass Type ID")
                },
                kind: .passTypeIds,
                emptyTitle: "No Pass Type IDs",
                emptyMessage: "Create a Pass Type ID before issuing Wallet pass certificates."
            )
        case .appGroups:
            unsupportedAppGroupsState
        }
    }

    @ViewBuilder
    private func identifierTable<T>(
        state: ViewState<[T]>,
        rows: [IdentifierRow],
        kind: ResourcesViewModel.Kind,
        emptyTitle: String,
        emptyMessage: String
    ) -> some View {
        switch state {
        case .idle, .loading:
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                Text("Loading \(selectedKind.title.lowercased())…")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.body)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            ErrorRetryView(
                title: "Couldn't Load \(selectedKind.title)",
                message: message,
                retryTitle: "Retry",
                onRetry: { viewModel.retry(kind) }
            )
        default:
            if rows.isEmpty {
                emptyState(kind: kind, title: emptyTitle, message: emptyMessage)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        headerRow
                        ForEach(rows) { row in
                            identifierRow(row)
                            ShipyardTheme.rowDivider.frame(height: 1)
                        }
                        paginationFooter(kind: kind)
                    }
                }
            }
        }
    }

    private var unsupportedAppGroupsState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "info.circle")
                .font(.system(size: 28))
                .foregroundColor(ShipyardTheme.body)
            Text("App Groups are not available in App Store Connect API")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            Text(IdentifierResourceKind.appGroups.help)
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Text("Name").frame(width: 240, alignment: .leading)
            Text("Identifier").frame(width: 320, alignment: .leading)
            Text("Type").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(ShipyardTheme.body)
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(ShipyardTheme.tableHeader)
    }

    private func identifierRow(_ row: IdentifierRow) -> some View {
        HStack(spacing: 12) {
            Text(row.name ?? "Untitled")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
                .lineLimit(1)
                .frame(width: 240, alignment: .leading)
            Text(row.identifier ?? "—")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(ShipyardTheme.body)
                .lineLimit(1)
                .frame(width: 320, alignment: .leading)
            Text(row.type)
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.name ?? row.identifier ?? row.id), \(row.type)")
    }

    private func emptyState(kind: ResourcesViewModel.Kind, title: String, message: String) -> some View {
        let hasSearch = viewModel.hasActiveSearch(for: kind)
        return VStack(spacing: 12) {
            Spacer()
            Text(hasSearch ? "No Matching \(selectedKind.title)" : title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            Text(hasSearch ? "Try a different name or identifier." : message)
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
            if !hasSearch {
                Button(selectedKind.createTitle) { showCreateForm = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func paginationFooter(kind: ResourcesViewModel.Kind) -> some View {
        if let nextCursor = viewModel.nextCursors[kind] {
            HStack {
                Spacer()
                if viewModel.paginationFailedKinds.contains(kind) {
                    Button("Couldn't load more — Retry") {
                        viewModel.loadMore(kind, cursor: nextCursor)
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
                            if !viewModel.isPaginatingKinds.contains(kind) {
                                viewModel.loadMore(kind, cursor: nextCursor)
                            }
                        }
                }
                Spacer()
            }
        }
    }

    private func loadSelectedKind() {
        if let kind = selectedKind.resourceKind {
            viewModel.load(kind)
        }
    }
}

private struct IdentifierRow: Identifiable {
    var id: String
    var name: String?
    var identifier: String?
    var type: String
}

struct CreateIdentifierForm: View {
    enum Completion {
        case success(String)
        case failure(String)
        case ignored
    }

    let kind: IdentifierResourceKind
    @ObservedObject var viewModel: ResourcesViewModel
    var onDone: (Completion) -> Void
    @EnvironmentObject private var toastCenter: ShipyardToastCenter

    @State private var name = ""
    @State private var identifier = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(kind.createTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(ShipyardTheme.title)
                Text(kind.help)
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                identifierField(label: "Name", text: $name, prompt: kind.promptName, mono: false)
                identifierField(label: "Identifier", text: $identifier, prompt: kind.promptIdentifier, mono: true)
                Text("Use Apple's reverse-DNS identifier exactly. It cannot be changed after creation.")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel") { onDone(.ignored) }
                    .buttonStyle(.launchSecondary)
                    .disabled(isSaving)
                Spacer()
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button(kind.createTitle) { create() }
                        .buttonStyle(.launchPrimary)
                        .disabled(!canCreate)
                }
            }
            .padding(.top, 12)
        }
        .padding(24)
        .frame(width: 520)
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && kind.resourceKind != nil
    }

    private func identifierField(label: String, text: Binding<String>, prompt: String, mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
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
                .onChange(of: text.wrappedValue) { _ in errorMessage = nil }
        }
    }

    private func create() {
        Task { @MainActor in
            isSaving = true
            errorMessage = nil
            defer { isSaving = false }
            switch kind {
            case .merchantIds:
                switch await viewModel.createMerchantId(name: name, identifier: identifier) {
                case .value:
                    onDone(.success("Merchant ID created"))
                case .failure(let message):
                    errorMessage = message
                    toastCenter.show("Couldn't create Merchant ID", detail: message, variant: .error)
                case .ignored:
                    break
                }
            case .passTypeIds:
                switch await viewModel.createPassTypeId(name: name, identifier: identifier) {
                case .value:
                    onDone(.success("Pass Type ID created"))
                case .failure(let message):
                    errorMessage = message
                    toastCenter.show("Couldn't create Pass Type ID", detail: message, variant: .error)
                case .ignored:
                    break
                }
            case .appGroups:
                onDone(.failure(IdentifierResourceKind.appGroups.help))
            }
        }
    }
}
