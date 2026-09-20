//
//  AppInfoView.swift
//  App Store
//
//  Batch C1: read-only App Info panel. Shows app identity (Apple ID,
//  bundle ID, SKU, locale, content rights), the appInfos records
//  (state, age rating, categories), app info localizations, the live
//  version's localizations and export compliance. Write lifecycle
//  deferred to Batch D4; no PATCH in this phase.
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
                emptyState(icon: "info.circle", title: "No App Selected",
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
                        InfoRow(label: loc.locale ?? "Locale", value: loc.name, valueFont: .body)
                            InfoRow(label: "Subtitle", value: loc.subtitle)
                            InfoRow(label: "Privacy Policy URL", value: loc.privacyPolicyUrl)
                            InfoRow(label: "Privacy Choices URL", value: loc.privacyChoicesUrl)
                        }
                    }
                }
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
                        Text(loc.locale ?? "Locale")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        InfoRow(label: "Description", value: loc.descriptionData)
                        InfoRow(label: "Keywords", value: loc.keywords)
                        InfoRow(label: "Promotional Text", value: loc.promotionalText)
                        InfoRow(label: "Marketing URL", value: loc.marketingUrl)
                        InfoRow(label: "Support URL", value: loc.supportUrl)
                        InfoRow(label: "What's New", value: loc.whatsNew)
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
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(title)
                .font(.title3)
                .fontWeight(.medium)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
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
