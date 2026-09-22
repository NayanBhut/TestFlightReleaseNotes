//
//  AppInfoView.swift
//  App Store
//
//  Batch C1: read-only App Info panel. Shows app identity (Apple ID,
//  bundle ID, SKU, locale, content rights), the appInfos records
//  (state, age rating, categories), app info localizations, the live
//  version's localizations and export compliance.
//
//  Batch G (#10): inline editor for app info localizations
//  (PATCH /v1/appInfoLocalizations/{id} — name, subtitle, privacy URLs).
//  Needs an App Manager+ key; TestFlight-only keys 403.
//

import SwiftUI

struct AppInfoView: View {
    @ObservedObject var viewModel: DetailViewModel
    var selectedApp: AppsData?

    var body: some View {
        Group {
            if let app = selectedApp {
                VStack(spacing: 0) {
                    header(app: app)
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            generalSection(app: app)
                            appInfosSection
                            appInfoLocalizationsSection
                            versionLocalizationsSection(app: app)
                            exportComplianceSection
                        }
                        .padding(20)
                    }
                }
                .onAppear {
                    viewModel.loadAppInfo()
                }
                .onChange(of: app.id) { _, _ in
                    viewModel.loadAppInfo()
                }
            } else {
                EmptyStateView(icon: "info.circle", title: "No App Selected",
                               subtitle: "Select an app from the sidebar to view its App Info")
            }
        }
    }

    // MARK: - Header

    private func header(app: AppsData) -> some View {
        HStack {
            Text("App Info")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Text(app.name ?? "")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Button(action: { viewModel.retryAppInfo() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.appInfoState.isLoading
                      || viewModel.versionLocalizationsState.isLoading
                      || viewModel.exportComplianceState.isLoading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - General

    private func generalSection(app: AppsData) -> some View {
        InfoCard(title: "General", systemImage: "app.badge") {
            InfoRow(label: "Apple ID", value: app.id)
            InfoRow(label: "Bundle ID", value: app.bundleId)
            InfoRow(label: "SKU", value: app.sku)
            InfoRow(label: "Primary Locale", value: app.primaryLocale)
            InfoRow(label: "Content Rights", value: contentRightsLabel(app.contentRightsDeclaration))
            InfoRow(label: "Made for Kids", value: kidsLabel(app.isOrEverWasMadeForKids))
            InfoRow(label: "Live Version", value: app.currentLiveVersion.1.isEmpty ? nil : app.currentLiveVersion.1)
        }
    }

    private func contentRightsLabel(_ raw: String?) -> String? {
        switch raw {
        case "DOES_NOT_USE_THIRD_PARTY_CONTENT": return "Doesn't use third-party content"
        case "USES_THIRD_PARTY_CONTENT": return "Uses third-party content"
        default: return raw
        }
    }

    private func kidsLabel(_ flag: Bool?) -> String? {
        switch flag {
        case true: return "Yes"
        case false: return "No"
        default: return nil
        }
    }

    // MARK: - App Infos (state, age rating, categories)

    @ViewBuilder private var appInfosSection: some View {
        section(state: viewModel.appInfoState, title: "App Store Info", systemImage: "doc.text",
                retry: { viewModel.retryAppInfos() }) { info in
            VStack(alignment: .leading, spacing: 12) {
                ForEach(info, id: \.id) { appInfo in
                    VStack(alignment: .leading, spacing: 8) {
                        if appInfo.id != info.first?.id { Divider() }
                        InfoRow(label: "State", value: appInfo.state)
                        InfoRow(label: "Age Rating", value: ageRatingLabel(appInfo))
                        InfoRow(label: "Kids Age Band", value: appInfo.kidsAgeBand)
                        categoryRows(appInfo)
                    }
                }
            }
        }
    }

    /// App Store age rating — one explicit mapping for both sources, so
    /// values like FOUR_PLUS render as "4+", not "FOUR+".
    private func ageRatingLabel(_ info: AppInfoModel) -> String? {
        let raw = info.appStoreAgeRating
            ?? info.ageRatingDeclaration?.ageRatingOverrideV2
        return Self.ageRatingDisplay(raw)
    }

    private static func ageRatingDisplay(_ raw: String?) -> String? {
        switch raw {
        case "FOUR_PLUS": return "4+"
        case "NINE_PLUS": return "9+"
        case "THIRTEEN_PLUS": return "13+"
        case "FOURTEEN_PLUS": return "14+"
        case "SIXTEEN_PLUS": return "16+"
        case "SEVENTEEN_PLUS": return "17+"
        case "EIGHTEEN_PLUS": return "18+"
        case "NINETEEN_PLUS": return "19+"
        case "NONE": return "None"
        case nil: return nil
        default: return raw
        }
    }

    @ViewBuilder private func categoryRows(_ info: AppInfoModel) -> some View {
        let primary = info.primaryCategory
        let secondary = info.secondaryCategory
        if primary != nil || secondary != nil {
            InfoRow(label: "Primary Category", value: primary?.id)
            if let sub = info.primarySubcategoryOne { InfoRow(label: "Primary Subcategory", value: sub.id) }
            if let sub = info.primarySubcategoryTwo { InfoRow(label: "Primary Subcategory 2", value: sub.id) }
            InfoRow(label: "Secondary Category", value: secondary?.id)
            if let sub = info.secondarySubcategoryOne { InfoRow(label: "Secondary Subcategory", value: sub.id) }
            if let sub = info.secondarySubcategoryTwo { InfoRow(label: "Secondary Subcategory 2", value: sub.id) }
        }
    }

    // MARK: - App Info Localizations

    @ViewBuilder private var appInfoLocalizationsSection: some View {
        let localizations = viewModel.appInfoState.loadedValue?.flatMap { $0.appInfoLocalizations } ?? []
        if !localizations.isEmpty {
            InfoCard(title: "App Info Localizations", systemImage: "globe") {
                VStack(alignment: .leading, spacing: 12) {
                ForEach(localizations, id: \.id) { loc in
                    VStack(alignment: .leading, spacing: 8) {
                        if loc.id != localizations.first?.id { Divider() }
                        AppInfoLocalizationRow(localization: loc, viewModel: viewModel)
                        }
                    }
                }
                Text("Editing needs an API key with the App Manager role or higher — a TestFlight-only key is rejected (403).")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Version Localizations (already decoded, never shown before)

    @ViewBuilder private func versionLocalizationsSection(app: AppsData) -> some View {
        section(state: viewModel.versionLocalizationsState,
                title: "Version Localizations",
                systemImage: "doc.plaintext",
                retry: { viewModel.retryVersionLocalizations() }) { localizations in
            VStack(alignment: .leading, spacing: 12) {
                if !app.currentLiveVersion.1.isEmpty {
                    Text("Version \(app.currentLiveVersion.1)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                ForEach(localizations, id: \.id) { loc in
                    VStack(alignment: .leading, spacing: 8) {
                        if loc.id != localizations.first?.id { Divider() }
                        VersionLocalizationRow(localization: loc, viewModel: viewModel)
                    }
                }
            }
        }
    }

    // MARK: - Export Compliance

    @ViewBuilder private var exportComplianceSection: some View {
        section(state: viewModel.exportComplianceState,
                title: "Export Compliance",
                systemImage: "lock.shield",
                retry: { viewModel.retryExportCompliance() }) { declarations in
            VStack(alignment: .leading, spacing: 12) {
                ForEach(declarations, id: \.id) { declaration in
                    VStack(alignment: .leading, spacing: 8) {
                        if declaration.id != declarations.first?.id { Divider() }
                        InfoRow(label: "State", value: declaration.appEncryptionDeclarationState)
                        InfoRow(label: "Uses Encryption", value: boolLabel(declaration.usesEncryption))
                        InfoRow(label: "Exempt from Export Compliance", value: boolLabel(declaration.exempt))
                        InfoRow(label: "Proprietary Cryptography", value: boolLabel(declaration.containsProprietaryCryptography))
                        InfoRow(label: "Third-Party Cryptography", value: boolLabel(declaration.containsThirdPartyCryptography))
                        InfoRow(label: "Available on French Store", value: boolLabel(declaration.availableOnFrenchStore))
                        InfoRow(label: "Created", value: declaration.createdDate)
                    }
                }
            }
        }
    }

    // MARK: - Shared section renderer

    @ViewBuilder
    private func section<T>(state: ViewState<[T]>,
                           title: String,
                           systemImage: String,
                           retry: @escaping () -> Void,
                           @ViewBuilder content: @escaping ([T]) -> some View) -> some View {
        switch state {
        case .idle, .loading:
            InfoCard(title: title, systemImage: systemImage) {
                LoadingStateView(text: "Loading...")
            }
        case .empty:
            InfoCard(title: title, systemImage: systemImage) {
                Text("No data")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .error(let message):
            InfoCard(title: title, systemImage: systemImage) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Retry", action: retry)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        case .loaded(let items):
            InfoCard(title: title, systemImage: systemImage) {
                content(items)
            }
        }
    }

    private func boolLabel(_ value: Bool?) -> String? {
        switch value {
        case true: return "Yes"
        case false: return "No"
        default: return nil
        }
    }
}

// MARK: - App Info localization editor (Batch G #10)

/// Read-only rows plus an inline editor for name, subtitle and privacy
/// URLs (PATCH /v1/appInfoLocalizations/{id}). The editor stays open on
/// failure so typed input is never silently discarded — same contract as
/// the review ReplySection.
struct AppInfoLocalizationRow: View {
    let localization: AppInfoLocalizationModel
    @ObservedObject var viewModel: DetailViewModel
    @State private var isEditing = false
    @State private var name = ""
    @State private var subtitle = ""
    @State private var privacyPolicyUrl = ""
    @State private var privacyChoicesUrl = ""
    @State private var errorMessage: String?

    private var isSaving: Bool {
        viewModel.savingAppInfoLocalizationIds.contains(localization.id)
    }

    // Mirrors updateField in the view model: trimmed == saved means
    // unchanged (omitted); anything else is .set or .clear — a change.
    private var hasChanges: Bool {
        trimmed(name) != (localization.name ?? "")
            || trimmed(subtitle) != (localization.subtitle ?? "")
            || trimmed(privacyPolicyUrl) != (localization.privacyPolicyUrl ?? "")
            || trimmed(privacyChoicesUrl) != (localization.privacyChoicesUrl ?? "")
    }

    private func trimmed(_ draft: String) -> String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(label: localization.locale ?? "Locale", value: localization.name, valueFont: .body)
                    InfoRow(label: "Subtitle", value: localization.subtitle)
                    InfoRow(label: "Privacy Policy URL", value: localization.privacyPolicyUrl)
                    InfoRow(label: "Privacy Choices URL", value: localization.privacyChoicesUrl)
                }
                Spacer()
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if !isEditing {
                    Button("Edit") {
                        name = localization.name ?? ""
                        subtitle = localization.subtitle ?? ""
                        privacyPolicyUrl = localization.privacyPolicyUrl ?? ""
                        privacyChoicesUrl = localization.privacyChoicesUrl ?? ""
                        errorMessage = nil
                        isEditing = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            if isEditing {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Name (2–30 characters)", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .disabled(isSaving)
                    TextField("Subtitle (up to 30 characters)", text: $subtitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .disabled(isSaving)
                    TextField("Privacy Policy URL", text: $privacyPolicyUrl)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .disabled(isSaving)
                    TextField("Privacy Choices URL", text: $privacyChoicesUrl)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .disabled(isSaving)
                    // Blank draft over a saved value clears that field.
                    Text("Blank a field to clear it. Edits apply only while the app info is in an editable state.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Button("Cancel") {
                            isEditing = false
                            errorMessage = nil
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundColor(.secondary)
                        .disabled(isSaving)
                        Spacer()
                        Button("Save") {
                            Task { @MainActor in
                                let result = await viewModel.saveAppInfoLocalization(
                                    id: localization.id,
                                    name: name,
                                    subtitle: subtitle,
                                    privacyPolicyUrl: privacyPolicyUrl,
                                    privacyChoicesUrl: privacyChoicesUrl
                                )
                                switch result {
                                case .success:
                                    isEditing = false
                                    errorMessage = nil
                                case .failure(let message):
                                    errorMessage = message
                                case .ignored:
                                    // In-flight duplicate or cancelled — keep
                                    // the editor open, nothing was saved.
                                    break
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isSaving || !hasChanges)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .windowBackgroundColor))
                .cornerRadius(6)
            }
        }
    }
}

// MARK: - Version localization editor (Batch I, I6)

/// Read-only rows plus an inline editor for description, keywords,
/// promotional text, what's new and marketing/support URLs
/// (PATCH /v1/appStoreVersionLocalizations/{id}). Mirrors
/// AppInfoLocalizationRow's Edit/Save/Cancel pattern: the editor stays
/// open on failure so typed input is never silently discarded.
struct VersionLocalizationRow: View {
    let localization: AppStoreVersionLocalizationsModel
    @ObservedObject var viewModel: DetailViewModel
    @State private var isEditing = false
    @State private var descriptionText = ""
    @State private var keywords = ""
    @State private var promotionalText = ""
    @State private var whatsNew = ""
    @State private var marketingUrl = ""
    @State private var supportUrl = ""
    @State private var errorMessage: String?

    private var isSaving: Bool {
        viewModel.savingVersionLocalizationIds.contains(localization.id)
    }

    // Mirrors updateField in the view model: trimmed == saved means
    // unchanged; anything else is .set or .clear — a change.
    private var hasChanges: Bool {
        trimmed(descriptionText) != (localization.descriptionData ?? "")
            || trimmed(keywords) != (localization.keywords ?? "")
            || trimmed(promotionalText) != (localization.promotionalText ?? "")
            || trimmed(whatsNew) != (localization.whatsNew ?? "")
            || trimmed(marketingUrl) != (localization.marketingUrl ?? "")
            || trimmed(supportUrl) != (localization.supportUrl ?? "")
    }

    private func trimmed(_ draft: String) -> String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localization.locale ?? "Locale")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    InfoRow(label: "Description", value: localization.descriptionData)
                    InfoRow(label: "Keywords", value: localization.keywords)
                    InfoRow(label: "Promotional Text", value: localization.promotionalText)
                    InfoRow(label: "Marketing URL", value: localization.marketingUrl)
                    InfoRow(label: "Support URL", value: localization.supportUrl)
                    InfoRow(label: "What's New", value: localization.whatsNew)
                }
                Spacer()
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if !isEditing {
                    Button("Edit") {
                        descriptionText = localization.descriptionData ?? ""
                        keywords = localization.keywords ?? ""
                        promotionalText = localization.promotionalText ?? ""
                        whatsNew = localization.whatsNew ?? ""
                        marketingUrl = localization.marketingUrl ?? ""
                        supportUrl = localization.supportUrl ?? ""
                        errorMessage = nil
                        isEditing = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            if isEditing {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description (up to 4000 characters)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $descriptionText)
                        .font(.subheadline)
                        .frame(minHeight: 80, maxHeight: 160)
                        .border(Color.gray.opacity(0.3), width: 1)
                        .disabled(isSaving)
                    TextField("Keywords, comma-separated (up to 100 characters)", text: $keywords)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .disabled(isSaving)
                    Text("Promotional Text (up to 170 characters)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $promotionalText)
                        .font(.subheadline)
                        .frame(minHeight: 44, maxHeight: 90)
                        .border(Color.gray.opacity(0.3), width: 1)
                        .disabled(isSaving)
                    Text("What's New (up to 4000 characters)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $whatsNew)
                        .font(.subheadline)
                        .frame(minHeight: 60, maxHeight: 140)
                        .border(Color.gray.opacity(0.3), width: 1)
                        .disabled(isSaving)
                    TextField("Marketing URL (http(s))", text: $marketingUrl)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .disabled(isSaving)
                    TextField("Support URL (http(s))", text: $supportUrl)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .disabled(isSaving)
                    // Blank draft over a saved value clears that field.
                    Text("Blank a field to clear it. Saving needs an API key with the App Manager role or higher.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Button("Cancel") {
                            isEditing = false
                            errorMessage = nil
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundColor(.secondary)
                        .disabled(isSaving)
                        Spacer()
                        Button("Save") {
                            Task { @MainActor in
                                let result = await viewModel.saveVersionLocalization(
                                    id: localization.id,
                                    description: descriptionText,
                                    keywords: keywords,
                                    promotionalText: promotionalText,
                                    whatsNew: whatsNew,
                                    marketingUrl: marketingUrl,
                                    supportUrl: supportUrl
                                )
                                switch result {
                                case .success:
                                    isEditing = false
                                    errorMessage = nil
                                case .failure(let message):
                                    errorMessage = message
                                case .ignored:
                                    // In-flight duplicate or cancelled — keep
                                    // the editor open, nothing was saved.
                                    break
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isSaving || !hasChanges)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .windowBackgroundColor))
                .cornerRadius(6)
            }
        }
    }
}

// MARK: - Reusable card + row

/// A bordered, read-only grouping used across the App Info and Reviews
/// tabs. Scoped name (`InfoCard`, not `Card`) so it can't collide with
/// other generic card views in the module.
struct InfoCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.25), lineWidth: 1)
        )
    }
}

/// Label + value row; hides itself entirely when the value is nil so the
/// panel never shows empty fields (read-only data is often sparse).
struct InfoRow: View {
    let label: String
    let value: String?
    var valueFont: Font = .subheadline

    var body: some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 160, alignment: .leading)
                Text(value)
                    .font(valueFont)
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                Spacer()
            }
        }
    }
}

#Preview {
    AppInfoView(viewModel: DetailViewModel(sidebarViewModel: SideBarViewModel()), selectedApp: nil)
}
