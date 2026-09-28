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
    @ObservedObject var reviewsViewModel: ReviewsViewModel
    var selectedApp: AppsData?
    @State private var showingNewVersion = false
    @State private var showingNewLocalization = false
    @State private var showingUploadGuide = false
    @State private var replacingVersionId: String?
    @State private var confirmingCompletePhased = false
    @State private var confirmingReleaseVersionId: String?
    @State private var confirmingDeleteVersionId: String?

    var body: some View {
        Group {
            if let app = selectedApp {
                VStack(spacing: 0) {
                    header(app: app)
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            generalSection(app: app)
                            versionWorkflowSection()
                            if displayedAppStoreVersion != nil {
                                versionLocalizationsSection()
                            }
                            liveVersionLocalizationsSection
                            screenshotsSection
                            appInfosSection
                            appInfoLocalizationsSection
                            exportComplianceSection
                            appEventsSection
                            webhooksSection
                        }
                        .padding(20)
                    }
                }
                .onAppear {
                    viewModel.loadAppInfo()
                    reviewsViewModel.load(app: app)
                    loadSelectedVersionResources()
                }
                .onChange(of: app.id) { _, _ in
                    viewModel.loadAppInfo()
                    reviewsViewModel.load(app: app)
                    loadSelectedVersionResources()
                }
                .onChange(of: viewModel.currentTeam?.key) { _, _ in
                    viewModel.loadAppInfo()
                    reviewsViewModel.load(app: app)
                    loadSelectedVersionResources()
                }
                .onChange(of: reviewsViewModel.selectedAppStoreVersionId) { _, _ in
                    loadSelectedVersionResources()
                }
                .onChange(of: reviewsViewModel.liveAppStoreVersion?.id) { _, _ in
                    loadSelectedVersionResources()
                }
                .sheet(isPresented: $showingNewVersion) {
                    NewVersionView(reviewsViewModel: reviewsViewModel, app: selectedApp)
                        .frame(minWidth: 480, minHeight: 420)
                }
                .sheet(isPresented: $showingNewLocalization) {
                    if let version = displayedAppStoreVersion {
                        NewVersionLocalizationView(versionId: version.id, viewModel: viewModel)
                            .frame(minWidth: 420, minHeight: 220)
                    }
                }
                .sheet(isPresented: $showingUploadGuide) {
                    AppStoreUploadGuideView()
                        .frame(minWidth: 620, minHeight: 520)
                }
            } else {
                EmptyStateView(icon: "info.circle", title: "No App Selected",
                               subtitle: "Select an app from the sidebar to view its App Info")
            }
        }
    }

    private var displayedAppStoreVersion: AppStoreVersionsModel? {
        reviewsViewModel.displayedAppStoreVersion
    }

    private var isStoreVersionEditable: Bool {
        guard let version = reviewsViewModel.pendingAppStoreVersion else { return false }
        return isVersionEditable(appStoreState: version.appStoreState ?? version.appVersionState)
    }

    private func loadSelectedVersionResources() {
        guard let version = displayedAppStoreVersion,
              reviewsViewModel.selectedAppStoreVersionId == version.id else {
            viewModel.loadLiveVersionLocalizations(versionId: nil)
            return
        }
        viewModel.loadVersionLocalizations(versionId: version.id)
        Task { await reviewsViewModel.loadPhasedRelease(versionId: version.id) }
        if reviewsViewModel.appStoreVersionDisplayState == .both,
           let live = reviewsViewModel.liveAppStoreVersion {
            viewModel.loadLiveVersionLocalizations(versionId: live.id)
        } else {
            viewModel.loadLiveVersionLocalizations(versionId: nil)
        }
    }

    // MARK: - Header

    private func header(app: AppsData) -> some View {
        HStack {
            Text("App Info")
                .font(.sectionHeader)
                .fontWeight(.semibold)
            Spacer()
            Text(app.name ?? "")
                .font(.appCaption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Button {
                showingUploadGuide = true
            } label: {
                Label("Info", systemImage: "info.circle")
                    .font(.appCaption)
            }
            .buttonStyle(.bordered)
            Button {
                viewModel.retryAppInfo()
                if let version = displayedAppStoreVersion {
                    viewModel.loadVersionLocalizations(versionId: version.id, force: true)
                }
                if reviewsViewModel.appStoreVersionDisplayState == .both,
                   let live = reviewsViewModel.liveAppStoreVersion {
                    viewModel.loadLiveVersionLocalizations(versionId: live.id, force: true)
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.appCaption)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.appInfoState.isLoading
                      || viewModel.versionLocalizationsState.isLoading
                      || viewModel.exportComplianceState.isLoading
                      || viewModel.appEventsState.isLoading
                      || viewModel.webhooksState.isLoading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(AppTheme.secondaryBackground)
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

    @ViewBuilder private func versionWorkflowSection() -> some View {
        InfoCard(title: "App Store Versions", systemImage: "shippingbox") {
            if reviewsViewModel.appStoreVersionPlatforms.count > 1 {
                Picker("Platform", selection: Binding(
                    get: { reviewsViewModel.selectedAppStoreVersionPlatform ?? "" },
                    set: { reviewsViewModel.selectAppStoreVersionPlatform($0) })) {
                    ForEach(reviewsViewModel.appStoreVersionPlatforms, id: \.self) { platform in
                        Text(platform.replacingOccurrences(of: "_", with: " ").capitalized)
                            .tag(platform)
                    }
                }
            }
            if reviewsViewModel.canCreateAppStoreVersion {
                HStack {
                    Text("Create a new App Store version and attach its build.")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        showingNewVersion = true
                    } label: {
                        Label("Create New Version", systemImage: "plus")
                            .font(.appCaption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(reviewsViewModel.creatingVersion)
                }
            }
            appStoreVersionRows
            if let version = reviewsViewModel.pendingAppStoreVersion,
               displayedAppStoreVersion?.id == version.id {
                Divider()
                releaseSettingsSection(version)
                phasedReleaseSection(version)
            }
        }
    }

    @ViewBuilder private func releaseSettingsSection(_ version: AppStoreVersionsModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Release Settings", systemImage: "calendar.badge.clock")
                .font(.subheader)
            if Self.canEditBuild(for: version) {
                AppStoreVersionReleaseSettingsEditor(version: version, reviewsViewModel: reviewsViewModel)
                    .id(version.id)
            } else {
                Text("Release settings are locked for this released version.")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
            }
            if version.releaseType == AppStoreVersionReleaseType.manual.rawValue,
               (version.appStoreState ?? version.appVersionState) == "PENDING_DEVELOPER_RELEASE" {
                Button("Release This Version") {
                    confirmingReleaseVersionId = version.id
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(reviewsViewModel.releasingVersionId != nil)
                .confirmationDialog(
                    "Release This Version?",
                    isPresented: Binding(
                        get: { confirmingReleaseVersionId == version.id },
                        set: { if !$0 { confirmingReleaseVersionId = nil } }),
                    titleVisibility: .visible
                ) {
                    Button("Release Now", role: .destructive) {
                        Task {
                            _ = await reviewsViewModel.releaseVersion(versionId: version.id)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This version will no longer be available to manually release later.")
                }
                if reviewsViewModel.releasingVersionId == version.id {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder private func phasedReleaseSection(_ version: AppStoreVersionsModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Phased Release", systemImage: "tortoise")
                .font(.subheader)
            if reviewsViewModel.phasedLoading {
                ProgressView().controlSize(.small)
            } else if let release = reviewsViewModel.phasedRelease,
                      reviewsViewModel.phasedVersionId == version.id {
                HStack {
                    StateChip(text: release.phasedReleaseState ?? "UNKNOWN")
                    Spacer()
                    switch (release.phasedReleaseState ?? "").uppercased() {
                    case "ACTIVE":
                        Button("Pause") {
                            Task { await reviewsViewModel.setPhasedReleaseState("PAUSED") }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    case "PAUSED", "INACTIVE":
                        Button("Resume") {
                            Task { await reviewsViewModel.setPhasedReleaseState("ACTIVE") }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        Button("Complete") {
                            confirmingCompletePhased = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .confirmationDialog(
                            "Complete Phased Release?",
                            isPresented: $confirmingCompletePhased,
                            titleVisibility: .visible
                        ) {
                            Button("Complete Release", role: .destructive) {
                                Task { await reviewsViewModel.setPhasedReleaseState("COMPLETE") }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("The version will be released to all remaining users immediately.")
                        }
                    default:
                        EmptyView()
                    }
                }
            } else if reviewsViewModel.phasedVersionId == version.id {
                HStack {
                    Text("Not started")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Start") {
                        Task { await reviewsViewModel.startPhasedRelease(versionId: version.id) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } else {
                ProgressView().controlSize(.small)
            }
            if let error = reviewsViewModel.writeError {
                Text(error)
                    .font(.appCaption)
                    .foregroundColor(.red)
            }
        }
    }

    @ViewBuilder private var appStoreVersionRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch reviewsViewModel.appStoreVersionsState {
            case .idle, .loading:
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
            case .empty:
                emptyVersionState
            case .loaded:
                if reviewsViewModel.displayedAppStoreVersions.isEmpty {
                    emptyVersionState
                } else {
                    ForEach(reviewsViewModel.displayedAppStoreVersions, id: \.id) { version in
                        appStoreVersionRow(version)
                    }
                }
            case .error(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(.appCaption)
                        .foregroundColor(.red)
                    Button("Retry") {
                        reviewsViewModel.retryAppStoreVersions()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            if let message = reviewsViewModel.workflowMessage {
                Text(message)
                    .font(.appCaption)
                    .foregroundColor(.green)
            }
            if let error = reviewsViewModel.appStoreVersionsError {
                Text(error)
                    .font(.appCaption)
                    .foregroundColor(.red)
            }
        }
    }

    private var emptyVersionState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No App Store Version")
                .font(.appBody)
                .fontWeight(.medium)
            Text("No live or pending version exists. Create the first version directly in App Store Connect.")
                .font(.appCaption)
                .foregroundColor(.secondary)
        }
    }

    private func appStoreVersionRow(_ version: AppStoreVersionsModel) -> some View {
        let state = version.appStoreState ?? version.appVersionState
        let isSelected = reviewsViewModel.selectedAppStoreVersionId == version.id
        let isPending = reviewsViewModel.pendingAppStoreVersion?.id == version.id
        let isLive = reviewsViewModel.liveAppStoreVersion?.id == version.id
        let isEditable = isPending && isVersionEditable(appStoreState: state)
        return VStack(alignment: .leading, spacing: 6) {
            if isPending {
                Button {
                    reviewsViewModel.selectAppStoreVersion(version)
                } label: {
                    appStoreVersionHeader(version, state: state, isSelected: isSelected)
                }
                .buttonStyle(.plain)
            } else {
                appStoreVersionHeader(version, state: state, isSelected: isSelected)
            }
            if isSelected || isLive {
                if let build = version.build {
                    buildSummary(build, attached: true)
                    if isEditable && replacingVersionId != version.id {
                        Button("Replace build") {
                            replacingVersionId = version.id
                            reviewsViewModel.loadEligibleBuilds(for: version)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else if isEditable {
                        eligibleBuildPicker(for: version)
                    }
                } else if isEditable {
                    eligibleBuildPicker(for: version)
                } else if isPending {
                    Text("No build is attached. This version is read-only in its current state.")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                }
            }
            if isEditable {
                Button("Delete Pending Version", role: .destructive) {
                    confirmingDeleteVersionId = version.id
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .confirmationDialog(
                    "Delete Pending Version?",
                    isPresented: Binding(
                        get: { confirmingDeleteVersionId == version.id },
                        set: { if !$0 { confirmingDeleteVersionId = nil } }),
                    titleVisibility: .visible
                ) {
                    Button("Delete Version", role: .destructive) {
                        Task { _ = await reviewsViewModel.deleteAppStoreVersion(versionId: version.id) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Delete this draft or rejected version? This cannot be undone.")
                }
                if reviewsViewModel.deletingVersionId == version.id {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func appStoreVersionHeader(_ version: AppStoreVersionsModel,
                                       state: String?,
                                       isSelected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(version.versionString ?? version.id)
                    .font(.appBody)
                    .fontWeight(.medium)
                if let platform = version.platform {
                    Text(platform.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.appCaption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            StateChip(text: getStatusLabel(appStoreState: state))
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppTheme.accent)
            }
        }
        .contentShape(Rectangle())
    }

    private static func canEditBuild(for version: AppStoreVersionsModel) -> Bool {
        isVersionEditable(appStoreState: version.appStoreState ?? version.appVersionState)
    }

    @ViewBuilder private func eligibleBuildPicker(for version: AppStoreVersionsModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch reviewsViewModel.eligibleBuildsState {
            case .idle, .loading:
                ProgressView().controlSize(.small)
                Text("Finding eligible builds...")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
            case .empty:
                Text("No eligible builds for this version")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
            case .error(let message):
                StateErrorView(message: message) {
                    reviewsViewModel.loadEligibleBuilds(for: version)
                }
            case .loaded(let builds):
                ForEach(builds, id: \.id) { build in
                    Button {
                        reviewsViewModel.selectBuild(build)
                    } label: {
                        HStack {
                            buildSummary(build, attached: false)
                            Spacer()
                            if reviewsViewModel.selectedBuildId == build.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(AppTheme.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    Task {
                        if await reviewsViewModel.attachSelectedBuild() {
                            replacingVersionId = nil
                        }
                    }
                } label: {
                    if reviewsViewModel.attachingBuild {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Attach selected build")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(reviewsViewModel.selectedBuildId == nil || reviewsViewModel.attachingBuild)
            }
            if let error = reviewsViewModel.eligibleBuildsError {
                Text(error)
                    .font(.appCaption)
                    .foregroundColor(.red)
            }
            if let error = reviewsViewModel.attachBuildError {
                Text(error)
                    .font(.appCaption)
                    .foregroundColor(.red)
            }
            if let nextCursor = reviewsViewModel.eligibleBuildsNextCursor {
                Button("Load more eligible builds") {
                    reviewsViewModel.loadEligibleBuilds(for: version, cursor: nextCursor)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(AppTheme.windowBackground)
        .cornerRadius(6)
    }

    private func buildSummary(_ build: BuildsModel, attached: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("Build \(build.version ?? "—")")
                    .font(.appCaption)
                    .fontWeight(.medium)
                StateChip(text: build.processingState ?? "UNKNOWN")
            }
            Text("Version \(build.preReleaseVersion?.version ?? "—") · Uploaded \(BuildDisplayHelper.formattedUploadedDate(build.uploadedDate))")
                .font(.appCaption2)
                .foregroundColor(.secondary)
            if attached {
                Text("Attached")
                    .font(.appCaption2)
                    .foregroundColor(AppTheme.accent)
            }
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
                        AppInfoLocalizationRow(localization: loc,
                                               viewModel: viewModel,
                                               isEditable: isStoreVersionEditable)
                        }
                    }
                }
                Text(isStoreVersionEditable
                     ? "Editing needs an API key with the App Manager role or higher — a TestFlight-only key is rejected (403)."
                     : "Read-only: the live version cannot be edited. Editable states are Draft, Rejected, Developer Rejected, Metadata Rejected, and Invalid Binary.")
                    .font(.appCaption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Version Localizations (already decoded, never shown before)

    @ViewBuilder private func versionLocalizationsSection() -> some View {
        if let version = displayedAppStoreVersion {
            section(state: viewModel.versionLocalizationsState,
                    title: "Version Localizations",
                    systemImage: "doc.plaintext",
                    retry: {
                        viewModel.loadVersionLocalizations(versionId: version.id)
                    }) { localizations in
                VStack(alignment: .leading, spacing: 12) {
                    Text("Version \(version.versionString ?? version.id)")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                    versionLocalizationAddButton
                    ForEach(localizations, id: \.id) { loc in
                        VStack(alignment: .leading, spacing: 8) {
                            if loc.id != localizations.first?.id { Divider() }
                            VersionLocalizationRow(localization: loc,
                                                   viewModel: viewModel,
                                                   isEditable: isStoreVersionEditable)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var liveVersionLocalizationsSection: some View {
        if reviewsViewModel.appStoreVersionDisplayState == .both,
           let live = reviewsViewModel.liveAppStoreVersion {
            section(state: viewModel.liveVersionLocalizationsState,
                    title: "Live Version Localizations",
                    systemImage: "lock.shield",
                    retry: { viewModel.retryLiveVersionLocalizations() }) { localizations in
                VStack(alignment: .leading, spacing: 12) {
                    Text("Live version \(live.versionString ?? live.id) — read-only, including screenshots")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                    ForEach(localizations, id: \.id) { loc in
                        VStack(alignment: .leading, spacing: 8) {
                            if loc.id != localizations.first?.id { Divider() }
                            VersionLocalizationRow(localization: loc,
                                                   viewModel: viewModel,
                                                   isEditable: false)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var screenshotsSection: some View {
        InfoCard(title: "Screenshots", systemImage: "photo.on.rectangle") {
            VStack(alignment: .leading, spacing: 16) {
                switch reviewsViewModel.appStoreVersionsState {
                case .idle, .loading:
                    HStack {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Spacer()
                    }
                case .error(let message):
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message)
                            .font(.appCaption)
                            .foregroundColor(.red)
                        Button("Retry") {
                            reviewsViewModel.retryAppStoreVersions()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                case .empty:
                    Text("No App Store version to show screenshots for.")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                case .loaded:
                    if let version = displayedAppStoreVersion {
                        if reviewsViewModel.appStoreVersionDisplayState == .both,
                           let live = reviewsViewModel.liveAppStoreVersion {
                            ScreenshotsGroupView(
                                title: "Live version \(live.versionString ?? live.id) — read-only",
                                viewModel: viewModel,
                                state: viewModel.liveVersionLocalizationsState,
                                isEditable: false,
                                primaryLocale: selectedApp?.primaryLocale,
                                retry: { viewModel.retryLiveVersionLocalizations() })
                        }
                        ScreenshotsGroupView(
                            title: "Version \(version.versionString ?? version.id)",
                            viewModel: viewModel,
                            state: viewModel.versionLocalizationsState,
                            isEditable: isStoreVersionEditable,
                            primaryLocale: selectedApp?.primaryLocale,
                            retry: { viewModel.retryVersionLocalizations() })
                    } else {
                        HStack {
                            Spacer()
                            ProgressView().controlSize(.small)
                            Spacer()
                        }
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

    // MARK: - In-App Events

    @ViewBuilder private var appEventsSection: some View {
        section(state: viewModel.appEventsState,
                title: "In-App Events",
                systemImage: "calendar.badge.clock",
                retry: { viewModel.retryAppEvents() }) { events in
            VStack(alignment: .leading, spacing: 12) {
                ForEach(events, id: \.id) { event in
                    VStack(alignment: .leading, spacing: 8) {
                        if event.id != events.first?.id { Divider() }
                        InfoRow(label: "Reference Name", value: event.referenceName)
                        InfoRow(label: "Badge", value: event.badge?.replacingOccurrences(of: "_", with: " ").capitalized)
                        InfoRow(label: "State", value: event.eventState)
                    }
                }
            }
        }
    }

    // MARK: - Webhooks

    @ViewBuilder private var webhooksSection: some View {
        section(state: viewModel.webhooksState,
                title: "Webhooks",
                systemImage: "cable.connector",
                retry: { viewModel.retryWebhooks() }) { webhooks in
            VStack(alignment: .leading, spacing: 12) {
                ForEach(webhooks, id: \.id) { webhook in
                    VStack(alignment: .leading, spacing: 8) {
                        if webhook.id != webhooks.first?.id { Divider() }
                        InfoRow(label: "Name", value: webhook.name)
                        InfoRow(label: "URL", value: webhook.url)
                        InfoRow(label: "Enabled", value: boolLabel(webhook.enabled))
                        InfoRow(label: "Event Types", value: webhook.eventTypes?.joined(separator: ", "))
                    }
                }
            }
        }
    }

    @ViewBuilder private var versionLocalizationAddButton: some View {
        if isStoreVersionEditable {
            Button {
                showingNewLocalization = true
            } label: {
                Label("Add Localization", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.creatingVersionLocalization)
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("No data")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                    if title == "Version Localizations" {
                        versionLocalizationAddButton
                    }
                }
            }
        case .error(let message):
            InfoCard(title: title, systemImage: systemImage) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(.appCaption)
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

private enum AppStoreUploadGuide {
    static let text = """
    APP STORE UPLOAD WORKFLOW

    1. Upload the binary
    Upload the app from Xcode Organizer or App Store Connect and wait until the build reaches VALID. This app manages the uploaded build; it does not upload the binary itself.

    2. Open App Info
    Select the app, then open the App Info tab. App Store Versions shows at most one live version and one pending version.
    • Live and pending — shows both cards and hides Create New Version.
    • Live only — shows the live card and shows Create New Version.
    • Pending only — shows the pending card with its status and hides Create New Version.
    • No version — shows the empty state; create the first version directly in App Store Connect.
    Use the Platform picker when the app has versions for more than one platform.

    3. Create the version
    In App Store Versions, click Create New Version. Enter the version string, platform, copyright, release type, date, and optional build number.

    4. Attach the build
    In the displayed version, choose a build from the eligible-build list and click Attach selected build. Use Replace build only when Apple allows changing the build.

    5. Complete store metadata
    In Version Localizations:
    • Click Add Localization for a new locale.
    • Click Edit to change description, keywords, promotional text, What's New, marketing URL, or support URL.
    • Click Screenshots to create screenshot sets and upload images.

    6. Confirm app information and compliance
    Use App Store Info for app-level metadata and categories. Check Export Compliance before review submission.

    7. Choose release behavior
    In Release Settings, select:
    • Manual — release yourself after approval.
    • After Approval — Apple releases automatically after approval.
    • Scheduled — choose the earliest release date.
    Click Save release settings.

    8. Optional phased release
    In Phased Release, click Start. Use Pause, Resume, and Complete while the phased release is active.

    9. Submit for review
    Open the Reviews tab. Click Submit for Review under Review Submissions after the version has an attached build. Use Cancel Submission only while Apple allows cancellation.

    10. Release after approval
    For an approved MANUAL release, return to App Info → App Store Versions and click Release This Version. After Approval and Scheduled releases do not use this button.

    SCREENSHOT UPLOAD AND DATA
    Screenshots have their own Screenshots section on the main App Info view, grouped by version and locale.
    • Each locale row shows an image count and an inline thumbnail strip that loads on appear.
    • A locale with no screenshots of its own shows a USING <primary locale> chip and states that the App Store is serving the primary-locale images for that locale.
    • In the BOTH case, the live version is listed first as a read-only group so its screenshots stay visible.
    • Click Manage on a locale row to open the Screenshots sheet for that locale. Upload, create sets, and delete only when editable.
    • Screenshot Sets lists AppScreenshotSetModel records grouped by display type. Click Select to switch, choose a Display type, then click New Set.
    • Screenshots lists the AppScreenshotModel records of the selected set as thumbnails, with Delete per screenshot.
    • Upload images with the file picker. Uploads use Apple’s reserve → PUT upload operations → commit pipeline, then the set is reloaded.
    • API routes: GET /v1/appStoreVersionLocalizations/{id}/appScreenshotSets, POST /v1/appScreenshotSets, GET /v1/appScreenshotSets/{id}/appScreenshots, POST /v1/appScreenshotSets/{id}/appScreenshots, DELETE /v1/appScreenshots/{id}.
    • The section and Manage button stay available in every case, including live-only. The sheet is read-only when the version is not editable: New Set, Upload Image, and per-screenshot Delete are hidden.

    BUTTON AND SECTION GUIDE

    Info — Opens this workflow guide.
    Refresh — Reloads App Info, version localizations, and related sections.
    Create New Version — Creates a new version from a live version. Shown only in the live-only case.
    Attach selected build — Attaches the chosen valid build.
    Replace build — Replaces the attached build when editable.
    Delete Pending Version — Deletes a draft or rejected pending version.
    Add Localization — Creates a version localization. Hidden when read-only.
    Edit — Edits app or version-localization metadata. Hidden when read-only.
    Screenshots (section) — Shows screenshot thumbnails per version and locale with image counts.
    Manage — Opens the screenshots sheet for one locale. Read-only when not editable.
    Live Version Localizations — Read-only localizations for the live version in the BOTH case.
    Save release settings — Saves release type, date, and copyright.
    Start / Pause / Resume / Complete — Controls phased release.
    Release This Version — Releases an approved manual version.
    Submit for Review — Sends the attached App Store version for review.
    Cancel Submission — Cancels a review submission when permitted.
    Export Compliance — Shows encryption and export declarations.

    ACCESS AND SAFETY

    • Store metadata, screenshots, version creation, build attachment, release settings, phased release, and review submission require an App Manager or Admin API key.
    • TestFlight-only keys can read builds and manage TestFlight release notes but cannot change App Store records.
    • Only Draft, Rejected, Developer Rejected, Metadata Rejected, and Invalid Binary versions are editable. All other states are read-only.
    • When no editable pending version exists (live-only, no pending version, or a locked pending version), Edit and Add Localization are hidden, and the Screenshots sheet is read-only. Release Settings, Phased Release, and Delete Pending Version are hidden or disabled in the same states.
    • Only one pending version may exist. Release, finish, or delete it before creating another version.
    • Confirm destructive actions such as Delete Pending Version, Release This Version, Complete phased release, Delete screenshots, and Cancel Submission.
    """
}

struct AppStoreUploadGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = AppStoreUploadGuide.text

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("App Store Upload Guide", systemImage: "info.circle")
                    .font(.sectionHeader)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(AppTheme.windowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
    }
}

struct AppStoreVersionReleaseSettingsEditor: View {
    let version: AppStoreVersionsModel
    @ObservedObject var reviewsViewModel: ReviewsViewModel
    @State private var releaseType: AppStoreVersionReleaseType
    @State private var earliestReleaseDate: Date
    @State private var copyright: String

    init(version: AppStoreVersionsModel, reviewsViewModel: ReviewsViewModel) {
        self.version = version
        self.reviewsViewModel = reviewsViewModel
        _releaseType = State(initialValue: AppStoreVersionReleaseType(rawValue: version.releaseType ?? "") ?? .afterApproval)
        let formatter = ISO8601DateFormatter()
        let parsedDate = version.earliestReleaseDate.flatMap(formatter.date(from:))
        _earliestReleaseDate = State(initialValue: parsedDate ?? Date())
        _copyright = State(initialValue: version.copyright ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Release type", selection: $releaseType) {
                ForEach(AppStoreVersionReleaseType.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            TextField("Copyright", text: $copyright)
                .textFieldStyle(.roundedBorder)
            if releaseType == .scheduled {
                DatePicker("Release no earlier than", selection: $earliestReleaseDate)
                    .datePickerStyle(.compact)
            }
            HStack {
                Spacer()
                Button("Save release settings") {
                    Task {
                        let result = await reviewsViewModel.saveReleaseSettings(
                            versionId: version.id,
                            releaseType: releaseType,
                            earliestReleaseDate: releaseType == .scheduled ? earliestReleaseDate : nil,
                            copyright: copyright)
                        if case .success = result { return }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(reviewsViewModel.savingReleaseSettingsVersionId == version.id)
            }
            if reviewsViewModel.savingReleaseSettingsVersionId == version.id {
                ProgressView().controlSize(.small)
            }
            if let error = reviewsViewModel.releaseSettingsError {
                Text(error)
                    .font(.appCaption)
                    .foregroundColor(.red)
            }
        }
        .padding(10)
        .background(AppTheme.windowBackground)
        .cornerRadius(6)
    }
}

struct NewVersionLocalizationView: View {
    let versionId: String
    @ObservedObject var viewModel: DetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var locale = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Version Localization")
                .font(.sectionHeader)
                .fontWeight(.semibold)
            TextField("Locale (for example, en-US)", text: $locale)
                .textFieldStyle(.roundedBorder)
            if let error = viewModel.createVersionLocalizationError {
                Text(error)
                    .font(.appCaption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button {
                    Task {
                        if await viewModel.createVersionLocalization(versionId: versionId, locale: locale) {
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.creatingVersionLocalization {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Add Localization")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.creatingVersionLocalization || locale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
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
    let isEditable: Bool
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
                } else if isEditable && !isEditing {
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
            if isEditing && isEditable {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Name (2–30 characters)", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.appBody)
                        .disabled(isSaving)
                    TextField("Subtitle (up to 30 characters)", text: $subtitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.appBody)
                        .disabled(isSaving)
                    TextField("Privacy Policy URL", text: $privacyPolicyUrl)
                        .textFieldStyle(.roundedBorder)
                        .font(.appBody)
                        .disabled(isSaving)
                    TextField("Privacy Choices URL", text: $privacyChoicesUrl)
                        .textFieldStyle(.roundedBorder)
                        .font(.appBody)
                        .disabled(isSaving)
                    // Blank draft over a saved value clears that field.
                    Text("Blank a field to clear it. Edits apply only while the app info is in an editable state.")
                        .font(.appCaption2)
                        .foregroundColor(.secondary)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.appCaption)
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
                .background(AppTheme.windowBackground)
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
    let isEditable: Bool
    @State private var isEditing = false
    @State private var showingScreenshots = false
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
                        .font(.appBody)
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
                    Button("Screenshots") {
                        showingScreenshots = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Manage screenshots for \(localization.locale ?? "locale")")
                    .sheet(isPresented: $showingScreenshots) {
                        ScreenshotsSheet(
                            localizationId: localization.id,
                            locale: localization.locale ?? "Locale",
                            viewModel: viewModel,
                            isEditable: isEditable
                        )
                    }
                    if isEditable {
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
                        .accessibilityLabel("Edit \(localization.locale ?? "locale")")
                    }
                }
            }
            if isEditing && isEditable {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description (up to \(VersionLocalizationLimits.descriptionMaxLength) characters)")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $descriptionText)
                        .font(.appBody)
                        .frame(minHeight: 80, maxHeight: 160)
                        .border(AppTheme.border, width: 1)
                        .disabled(isSaving)
                    TextField("Keywords, comma-separated (up to \(VersionLocalizationLimits.keywordsMaxLength) characters)", text: $keywords)
                        .textFieldStyle(.roundedBorder)
                        .font(.appBody)
                        .disabled(isSaving)
                    Text("Promotional Text (up to \(VersionLocalizationLimits.promotionalTextMaxLength) characters)")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $promotionalText)
                        .font(.appBody)
                        .frame(minHeight: 44, maxHeight: 90)
                        .border(AppTheme.border, width: 1)
                        .disabled(isSaving)
                    Text("What's New (up to \(VersionLocalizationLimits.whatsNewMaxLength) characters)")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $whatsNew)
                        .font(.appBody)
                        .frame(minHeight: 60, maxHeight: 140)
                        .border(AppTheme.border, width: 1)
                        .disabled(isSaving)
                    TextField("Marketing URL (http(s))", text: $marketingUrl)
                        .textFieldStyle(.roundedBorder)
                        .font(.appBody)
                        .disabled(isSaving)
                    TextField("Support URL (http(s))", text: $supportUrl)
                        .textFieldStyle(.roundedBorder)
                        .font(.appBody)
                        .disabled(isSaving)
                    // Blank draft over a saved value clears that field.
                    Text("Blank a field to clear it. Saving needs an API key with the App Manager role or higher.")
                        .font(.appCaption2)
                        .foregroundColor(.secondary)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.appCaption)
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
                .background(AppTheme.windowBackground)
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
                .font(.subheader)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.secondaryBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.border, lineWidth: 1)
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
                    .font(.appCaption)
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
    AppInfoView(
        viewModel: DetailViewModel(sidebarViewModel: SideBarViewModel()),
        reviewsViewModel: ReviewsViewModel(),
        selectedApp: nil
    )
}
