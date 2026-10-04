//
//  AppInfoView.swift
//  App Store
//
//  App Store metadata editor from the app-info-light / app-info-dark Figma
//  frames: title + localization picker + Save Changes over a two-column
//  form (general fields + per-locale fields) with character counters,
//  inline validation (red border/hint like Figma), and the GENERAL
//  INFORMATION inspector. General fields come from the app-info
//  localization, the rest from the editable App Store version's
//  localization; both PATCH through DetailViewModel. The numeric Apple ID
//  is not exposed by the API, so the inspector dashes it.
//

import SwiftUI

struct ShipyardAppInfoView: View {
    @ObservedObject var detailVM: DetailViewModel
    @ObservedObject var reviewsVM: ReviewsViewModel
    var app: AppsData

    @State private var locale = ""
    @State private var drafts: [String: String] = [:]
    @State private var draftSignature = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showRemoveConfirm = false
    @State private var isAddingLocale = false
    /// Tab switches remount this view — only wipe typing on actual app change.
    @State private var bootedAppId = ""

    // Draft keys.
    private enum Field: String, CaseIterable {
        case name, subtitle, privacyPolicy, support, marketing
        case description, keywords, promo
    }

    private var versionId: String? {
        reviewsVM.selectedAppStoreVersionId
    }

    /// The selected App Store version's state; metadata writes land on the
    /// editable (pending) version only.
    private var selectedVersionState: String? {
        guard let versionId,
              let version = reviewsVM.appStoreVersionsState.loadedValue?.first(where: { $0.id == versionId })
        else { return nil }
        return version.appStoreState ?? version.appVersionState
    }

    private var isEditable: Bool {
        versionId != nil && isVersionEditable(appStoreState: selectedVersionState)
    }

    private var canSave: Bool {
        // Either record suffices: a fresh app may have app-info rows
        // (name/subtitle) with no version localization yet, or vice versa.
        isDirty && isEditable && (canEditGeneral || versionLocalization != nil)
    }

    private var locales: [String] {
        let versionLocales = detailVM.versionLocalizationsState.loadedValue?.compactMap(\.locale) ?? []
        let infoLocales = detailVM.appInfoState.loadedValue?.flatMap { $0.appInfoLocalizations }.compactMap(\.locale) ?? []
        var seen: [String] = []
        for code in versionLocales + infoLocales where !seen.contains(code) {
            seen.append(code)
        }
        return seen
    }

    private func draft(_ field: Field) -> String {
        drafts[field.rawValue] ?? serverValue(field)
    }

    private func serverValue(_ field: Field) -> String {
        switch field {
        case .name: return appInfoLocalization?.name ?? ""
        case .subtitle: return appInfoLocalization?.subtitle ?? ""
        case .privacyPolicy: return appInfoLocalization?.privacyPolicyUrl ?? ""
        case .support: return versionLocalization?.supportUrl ?? ""
        case .marketing: return versionLocalization?.marketingUrl ?? ""
        case .description: return versionLocalization?.descriptionData ?? ""
        case .keywords: return versionLocalization?.keywords ?? ""
        case .promo: return versionLocalization?.promotionalText ?? ""
        }
    }

    private var appInfoLocalization: AppInfoLocalizationModel? {
        let all = detailVM.appInfoState.loadedValue?.flatMap { $0.appInfoLocalizations } ?? []
        return all.first(where: { $0.locale == locale })
            ?? all.first(where: { $0.locale == app.primaryLocale })
    }

    /// Name/subtitle/privacy live on the app-info record, which only exists
    /// per locale once created in App Store Connect — the API flow here
    /// creates version localizations only. Without an exact-locale record
    /// the general fields stay read-only so Save can't overwrite the
    /// primary locale's name.
    private var canEditGeneral: Bool {
        let all = detailVM.appInfoState.loadedValue?.flatMap { $0.appInfoLocalizations } ?? []
        return all.contains(where: { $0.locale == locale })
    }

    /// Locales that can still be added (supported but not on this version).
    private var addableLocales: [String] {
        BetaLocalizationLocales.supported.filter { code in
            !(detailVM.versionLocalizationsState.loadedValue?.contains(where: { $0.locale == code }) ?? false)
        }
    }

    private var versionLocalization: AppStoreVersionLocalizationsModel? {
        detailVM.versionLocalizationsState.loadedValue?.first(where: { $0.locale == locale })
    }

    private var isDirty: Bool {
        Field.allCases.contains { draft($0) != serverValue($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShipyardTheme.tableBackground)
        .onAppear(perform: boot)
        .onChange(of: app.id) { _, _ in boot() }
        .onChange(of: reviewsVM.appStoreVersionsState) { _, _ in pickVersionIfNeeded() }
        .onChange(of: reviewsVM.selectedAppStoreVersionId) { _, newId in
            if let newId { detailVM.loadVersionLocalizations(versionId: newId) }
        }
        .onChange(of: draftSignatureSource) { _, _ in syncDrafts() }
    }

    private func boot() {
        // Same app (e.g. tab switch remount): refresh data but keep typing.
        if bootedAppId == app.id {
            detailVM.loadAppInfo()
            reviewsVM.load(app: app)
            pickVersionIfNeeded()
            syncDrafts()
            return
        }
        bootedAppId = app.id
        locale = app.primaryLocale ?? BetaLocalizationLocales.defaultLocale
        drafts = [:]
        draftSignature = ""
        detailVM.loadAppInfo()
        // load(app:) — not load(appId:) — sets the current app first;
        // the id-only overload no-ops until something else sets it, which
        // is why versions never arrived on first entry.
        reviewsVM.load(app: app)
        pickVersionIfNeeded()
        // Records may already be cached (warm from another tab): with no
        // state change coming, seed synchronously instead of waiting.
        syncDrafts()
    }

    /// Manual refresh: reloads all three records, keeps dirty typing,
    /// re-seeds everything else from the server.
    private func refreshAll() {
        let dirty = Set(Field.allCases.map(\.rawValue).filter { drafts[$0] != nil && drafts[$0] != serverValue(Field(rawValue: $0)!) })
        detailVM.loadAppInfo(force: true)
        reviewsVM.load(appId: app.id, force: true)
        if let versionId { detailVM.loadVersionLocalizations(versionId: versionId, force: true) }
        for field in Field.allCases where !dirty.contains(field.rawValue) {
            drafts.removeValue(forKey: field.rawValue)
        }
        draftSignature = ""
        syncDrafts()
    }

    private func pickVersionIfNeeded() {
        guard reviewsVM.selectedAppStoreVersionId == nil,
              let versions = reviewsVM.appStoreVersionsState.loadedValue,
              !versions.isEmpty else { return }
        let preferred = ReviewsViewModel.preferredAppStoreVersion(versions) ?? versions[0]
        reviewsVM.selectAppStoreVersion(preferred)
    }

    /// Anything that changes server values (locale, records) re-seeds
    /// untouched drafts; typing is never overwritten.
    private var draftSignatureSource: String {
        "\(app.id)|\(locale)|\(versionId ?? "")|\(detailVM.appInfoState.loadedValue?.count ?? 0)|\(detailVM.versionLocalizationsState.loadedValue?.map(\.id).joined() ?? "")"
    }

    private func syncDrafts() {
        guard draftSignature != draftSignatureSource else { return }
        draftSignature = draftSignatureSource
        for field in Field.allCases where drafts[field.rawValue] == nil {
            drafts[field.rawValue] = serverValue(field)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("App Store Metadata")
                .font(.system(size: 18))
                .foregroundColor(ShipyardTheme.title)

            Spacer()

            Menu {
                ForEach(locales, id: \.self) { code in
                    Button("\(BetaLocalizationLocales.displayName(for: code)) (\(code))") {
                        locale = code
                        for field in Field.allCases { drafts.removeValue(forKey: field.rawValue) }
                        draftSignature = ""
                        syncDrafts()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Localization: \(BetaLocalizationLocales.displayName(for: locale))")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                }
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(LaunchTheme.field)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(LaunchTheme.border, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Select localization")

            Menu {
                ForEach(addableLocales, id: \.self) { code in
                    Button("\(BetaLocalizationLocales.displayName(for: code)) (\(code))") {
                        Task { await addLocale(code) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if isAddingLocale || detailVM.creatingVersionLocalization {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                    }
                    Text("Add")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                }
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(LaunchTheme.field)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(LaunchTheme.border, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .disabled(isAddingLocale || detailVM.creatingVersionLocalization || !isEditable)
            .accessibilityLabel("Add localization")

            Button {
                showRemoveConfirm = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.danger)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(LaunchTheme.field)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(LaunchTheme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(versionLocalization == nil)
            .accessibilityLabel("Remove \(locale) localization")
            .confirmationDialog(
                "Remove the \(locale) localization? Its store metadata is deleted.",
                isPresented: $showRemoveConfirm,
                titleVisibility: .visible
            ) {
                Button("Remove Localization", role: .destructive) {
                    Task { await removeLocale() }
                }
                Button("Cancel", role: .cancel) {}
            }

            Button {
                refreshAll()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(LaunchTheme.field)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(LaunchTheme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reload metadata from App Store Connect")
            .help("Reload metadata from App Store Connect")

            if isSaving {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Button("Save Changes") {
                    Task { await save() }
                }
                .font(.system(size: 13))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(isDirty ? ShipyardTheme.accent : ShipyardTheme.accent.opacity(0.4))
                .cornerRadius(6)
                .buttonStyle(.plain)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Save metadata changes")
                .help(canSave ? "Save metadata changes" : saveDisabledHint)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(LaunchTheme.page)
    }

    /// Explains a disabled Save so it never reads as broken.
    private var saveDisabledHint: String {
        if versionId == nil { return "Loading versions…" }
        if !isEditable { return "This version is read-only" }
        if versionLocalization == nil { return "Add this localization first" }
        if !isDirty { return "No changes to save" }
        return "Save metadata changes"
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            if case .error(let message) = reviewsVM.appStoreVersionsState {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AppTheme.negative)
                    Text("Couldn't load versions: \(message)")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.negative)
                    Spacer()
                    Button("Retry") {
                        reviewsVM.retryAppStoreVersions()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                Divider()
            } else if versionId != nil, !isEditable {
                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundColor(AppTheme.pending)
                    Text("This version is live (read-only). Create a new version in App Store Connect to edit metadata.")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.pending)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                Divider()
            }

            HStack(spacing: 0) {
            ScrollView {
                HStack(alignment: .top, spacing: 32) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("General Information")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(ShipyardTheme.title)
                        if !canEditGeneral {
                            Text("App name, subtitle and privacy URL follow the primary locale until this locale is added in App Store Connect.")
                                .font(.system(size: 11))
                                .foregroundColor(ShipyardTheme.body)
                        }
                        metadataField(
                            label: "App Name",
                            field: .name, limit: 30,
                            hint: "The name of your app as it will appear in the App Store. Limit 30 characters.",
                            disabled: !canEditGeneral
                        )
                        metadataField(
                            label: "Subtitle",
                            field: .subtitle, limit: 30,
                            hint: "A brief summary of your app. Limit 30 characters.",
                            disabled: !canEditGeneral
                        )
                        metadataField(
                            label: "Privacy Policy URL",
                            field: .privacyPolicy, limit: nil, url: true,
                            hint: "Where users can read your privacy policy.",
                            disabled: !canEditGeneral
                        )
                        metadataField(
                            label: "Support URL",
                            field: .support, limit: nil, url: true,
                            hint: "Where users can get help with your app."
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: 20) {
                        Text("Localization (\(BetaLocalizationLocales.displayName(for: locale)))")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(ShipyardTheme.title)
                        if versionLocalization == nil {
                            Text("Add this localization above to start editing its fields.")
                                .font(.system(size: 11))
                                .foregroundColor(ShipyardTheme.body)
                        }
                        metadataField(
                            label: "Description",
                            field: .description, limit: 4000, multiline: true,
                            hint: "A detailed description of your app, its features, and functionality."
                        )
                        metadataField(
                            label: "Keywords",
                            field: .keywords, limit: 100,
                            hint: "One or more keywords that describe your app. Separate with commas."
                        )
                        metadataField(
                            label: "Promotional Text",
                            field: .promo, limit: 170,
                            hint: "Short promotional copy shown above the description."
                        )
                        metadataField(
                            label: "Marketing URL",
                            field: .marketing, limit: nil, url: true,
                            hint: "Where users can learn more about your app."
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .disabled(versionLocalization == nil)
                }
                .padding(24)

                screenshotsSection
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                if let saveError {
                    Text(saveError)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.negative)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }
            }

            inspector
            }
        }
    }

    // MARK: - Screenshots

    /// Per-locale screenshot sets, ported from the legacy App Info view:
    /// thumbnails per version localization, with set creation, image
    /// upload (DetailViewModel's reserve → PUT → complete pipeline), and
    /// delete — all gated on the same `isEditable` as metadata.
    private var screenshotsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Screenshots")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            if versionId == nil {
                Text("Loading versions…")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
            } else {
                ScreenshotsGroupView(
                    title: "Version \(selectedVersionString)",
                    viewModel: detailVM,
                    state: detailVM.versionLocalizationsState,
                    isEditable: isEditable,
                    primaryLocale: app.primaryLocale,
                    retry: { detailVM.retryVersionLocalizations() })
            }
        }
    }

    private var selectedVersionString: String {
        guard let versionId,
              let version = reviewsVM.appStoreVersionsState.loadedValue?.first(where: { $0.id == versionId })
        else { return "—" }
        return version.versionString ?? version.id
    }

    // MARK: - Fields

    private func fieldBinding(_ field: Field) -> Binding<String> {
        Binding(
            get: { drafts[field.rawValue] ?? serverValue(field) },
            set: { drafts[field.rawValue] = $0 }
        )
    }

    /// Client-side validity mirroring Apple's caps (the view model
    /// re-validates on save): length caps plus http(s) URLs.
    private func fieldError(_ field: Field, limit: Int?, url: Bool) -> String? {
        let text = draft(field)
        if let limit, text.count > limit {
            switch field {
            case .name: return "Name exceeds maximum App Store limit of \(limit) characters."
            default: return "Exceeds the \(limit)-character limit."
            }
        }
        if field == .name, text.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
            return "Name must be at least 2 characters."
        }
        if url, !text.isEmpty {
            // Same rule as DetailViewModel.validateAppInfoLocalization
            // (URL(string:) + http(s) scheme + non-nil host) so text the
            // inline message accepts can't still fail on Save
            // (BUG_SWEEP #26). A bare prefix check used to let
            // "https://" through and then reject it at save time.
            guard let parsed = URL(string: text),
                  let scheme = parsed.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  parsed.host != nil else {
                return "Invalid URL — use a full http(s) address with a host."
            }
        }
        return nil
    }

    @ViewBuilder
    private func metadataField(label: String, field: Field, limit: Int?, multiline: Bool = false, url: Bool = false, hint: String, disabled: Bool = false) -> some View {
        let text = draft(field)
        let error = fieldError(field, limit: limit, url: url)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
                Spacer()
                if let limit {
                    Text("\(text.count) / \(limit)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(error == nil ? ShipyardTheme.body : ShipyardTheme.danger)
                }
            }

            if multiline {
                TextEditor(text: fieldBinding(field))
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.title)
                    .padding(10)
                    .frame(height: 110)
                    .background(LaunchTheme.field)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(error == nil ? LaunchTheme.border : ShipyardTheme.danger, lineWidth: 1)
                    )
                    .scrollContentBackground(.hidden)
                    .disabled(disabled)
            } else {
                TextField(label, text: fieldBinding(field))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.title)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(LaunchTheme.field)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(error == nil ? LaunchTheme.border : ShipyardTheme.danger, lineWidth: 1)
                    )
                    .disabled(disabled)
            }

            Text(error ?? hint)
                .font(.system(size: 11))
                .foregroundColor(error == nil ? ShipyardTheme.body : ShipyardTheme.danger)
        }
    }

    // MARK: - Inspector

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("GENERAL INFORMATION")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ShipyardTheme.body)

            VStack(alignment: .leading, spacing: 12) {
                inspectorRow(label: "APPLE ID", value: "—", mono: true)
                inspectorRow(label: "BUNDLE ID", value: app.bundleId ?? "—", mono: true)
                inspectorRow(label: "SKU", value: app.sku ?? "—", mono: false)
                inspectorRow(
                    label: "PRIMARY LOCALE",
                    value: BetaLocalizationLocales.displayName(for: app.primaryLocale ?? ""),
                    mono: false
                )
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(ShipyardTheme.sidebarBackground)
        .overlay(
            ShipyardTheme.rowDivider.frame(width: 1),
            alignment: .leading
        )
    }

    private func inspectorRow(label: String, value: String, mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(ShipyardTheme.body)
            Text(value.isEmpty ? "—" : value)
                .font(mono ? .system(size: 12, design: .monospaced) : .system(size: 12))
                .foregroundColor(ShipyardTheme.title)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Save

    private func addLocale(_ code: String) async {
        guard let versionId else { return }
        isAddingLocale = true
        defer { isAddingLocale = false }
        if await detailVM.createVersionLocalization(versionId: versionId, locale: code) {
            locale = code
            for field in Field.allCases { drafts.removeValue(forKey: field.rawValue) }
            draftSignature = ""
            syncDrafts()
        } else if let message = detailVM.createVersionLocalizationError {
            saveError = message
        }
    }

    private func removeLocale() async {
        guard let record = versionLocalization else { return }
        if let message = await detailVM.deleteVersionLocalization(id: record.id, locale: locale) {
            saveError = message
            return
        }
        for field in Field.allCases { drafts.removeValue(forKey: field.rawValue) }
        draftSignature = ""
        syncDrafts()
    }

    private func save() async {
        // Client-side gate mirrors fieldError so over-limit/ malformed
        // input never reaches the API. Surface it instead of no-op'ing:
        // the Save button stays enabled, so the failure must be visible
        // (BUG_SWEEP #11).
        for field in Field.allCases {
            let limit: Int? = switch field {
            case .name, .subtitle: 30
            case .keywords: 100
            case .promo: 170
            case .description: 4000
            default: nil
            }
            let url = field == .privacyPolicy || field == .support || field == .marketing
            if let error = fieldError(field, limit: limit, url: url) {
                saveError = error
                return
            }
        }
        guard let infoId = appInfoLocalization?.id,
              let versionLoc = versionLocalization else {
            saveError = "No \(BetaLocalizationLocales.displayName(for: locale)) localization exists yet for this app."
            return
        }
        isSaving = true
        defer { isSaving = false }
        saveError = nil

        if canEditGeneral, let infoId = appInfoLocalization?.id {
            let infoResult = await detailVM.saveAppInfoLocalization(
                id: infoId,
                name: draft(.name),
                subtitle: draft(.subtitle),
                privacyPolicyUrl: draft(.privacyPolicy),
                privacyChoicesUrl: appInfoLocalization?.privacyChoicesUrl ?? ""
            )
            if case .failure(let message) = infoResult {
                saveError = message
                return
            }
        }
        if let versionLoc = versionLocalization {
            let versionResult = await detailVM.saveVersionLocalization(
                id: versionLoc.id,
                description: draft(.description),
                keywords: draft(.keywords),
                promotionalText: draft(.promo),
                whatsNew: versionLoc.whatsNew ?? "",
                marketingUrl: draft(.marketing),
                supportUrl: draft(.support)
            )
            if case .failure(let message) = versionResult {
                saveError = message
                return
            }
        } else if !canEditGeneral {
            saveError = "No \(BetaLocalizationLocales.displayName(for: locale)) localization exists yet for this app."
            return
        }
        detailVM.loadAppInfo(force: true)
        if let versionId { detailVM.loadVersionLocalizations(versionId: versionId, force: true) }
        draftSignature = ""
        syncDrafts()
    }
}
