//
//  ReleaseTabView.swift
//  App Store
//
//  Figma App Store Versions workspace (76:31086 missing-items,
//  76:33999 complete): version heading + feature tabs, an editable
//  submission form (version string, per-locale What's New, build picker,
//  release type, phased release), a read-only App Review panel (contact
//  details have no API surface — managed in App Store Connect), a general
//  information inspector, and an action bar with a missing-items summary,
//  Save, and Submit for Review. All writes reuse ReviewsViewModel.
//

import SwiftUI

/// Submission workspace for one app's App Store versions.
struct ReleaseTabView: View {
    var app: AppsData
    @ObservedObject var reviewsVM: ReviewsViewModel
    var onOpenAppInfo: () -> Void
    var onOpenBuilds: () -> Void

    @Environment(\.openURL) private var openURL

    private enum FeatureTab: Hashable {
        case overview, allVersions, resolution, builds
    }

    @State private var featureTab: FeatureTab = .overview
    @State private var shownVersionId: String?
    @State private var draftVersionString = ""
    @State private var draftWhatsNew = ""
    @State private var draftLocaleId: String?
    @State private var draftReleaseType = AppStoreVersionReleaseType.manual
    @State private var draftReleaseDate = Date()
    @State private var syncedVersionId: String?
    @State private var saving = false
    @State private var saveError: String?
    @State private var showSubmitConfirm = false
    @State private var showChooseBuild = false

    // MARK: - Version selection

    private var allVersions: [AppStoreVersionsModel] {
        let loaded = reviewsVM.appStoreVersionsState.loadedValue ?? []
        let platform = shownVersion?.platform
            ?? reviewsVM.displayedAppStoreVersion?.platform
        let filtered = platform.map { p in loaded.filter { $0.platform == p } } ?? loaded
        return filtered.sorted {
            ($0.versionString ?? "").localizedStandardCompare($1.versionString ?? "") == .orderedDescending
        }
    }

    private var shownVersion: AppStoreVersionsModel? {
        if let id = shownVersionId,
           let found = allVersions.first(where: { $0.id == id }) {
            return found
        }
        return reviewsVM.displayedAppStoreVersion
    }

    private var shownState: String? {
        guard let version = shownVersion else { return nil }
        return version.appStoreState ?? version.appVersionState
    }

    /// Editable only when the shown version is the VM-selected pending
    /// version — every write guards on selectedAppStoreVersionId.
    private var canEditShown: Bool {
        guard let version = shownVersion,
              isVersionEditable(appStoreState: shownState),
              reviewsVM.displayedAppStoreVersion?.id == version.id,
              reviewsVM.selectedAppStoreVersionId == version.id else { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            switch reviewsVM.appStoreVersionsState {
            case .loading, .idle:
                loadingView
            case .error(let message):
                loadErrorView(message)
            case .loaded:
                if shownVersion != nil {
                    versionHeading
                    featureTabs
                    Divider()
                    HStack(alignment: .top, spacing: 0) {
                        featureContent
                        inspector
                    }
                    Divider()
                    actionBar
                } else {
                    emptyState
                }
            case .empty:
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShipyardTheme.tableBackground)
        .onAppear {
            reviewsVM.load(app: app)
            if shownVersionId == nil {
                shownVersionId = reviewsVM.displayedAppStoreVersion?.id
            }
            syncDrafts()
            loadPhased()
        }
        .onChange(of: shownVersion?.id) {
            syncDrafts()
            loadPhased()
        }
        .sheet(isPresented: $showChooseBuild) {
            if let version = shownVersion {
                ChooseBuildSheet(version: version, appName: app.name, reviewsVM: reviewsVM) {
                    syncedVersionId = nil
                    syncDrafts()
                }
            }
        }
    }

    // MARK: - Heading + tabs

    private var versionHeading: some View {
        HStack(spacing: 12) {
            Text("Version \(shownVersion?.versionString ?? "—")")
                .font(.system(size: 18))
                .foregroundColor(ShipyardTheme.title)
            statusBadge(shownState)
            Spacer(minLength: 0)
            Button("‹ All Versions") {
                featureTab = .allVersions
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(ShipyardTheme.body)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func statusBadge(_ state: String?) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(ShipyardTheme.body)
                .frame(width: 6, height: 6)
            Text(getStatusLabel(appStoreState: state))
                .font(.system(size: 10))
                .foregroundColor(ShipyardTheme.title)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(ShipyardTheme.tableHeader)
        .cornerRadius(10)
    }

    private var featureTabs: some View {
        HStack(spacing: 16) {
            featureTabButton(.overview, label: "Overview")
            featureTabButton(.allVersions, label: "All Versions")
            featureTabButton(.resolution, label: "Resolution Center")
            featureTabButton(.builds, label: "Builds")
            Text("│")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.tertiary)
            ForEach(allVersions, id: \.id) { version in
                let selected = version.id == shownVersion?.id
                Button(version.versionString ?? "—") {
                    showVersion(version)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? ShipyardTheme.accent : ShipyardTheme.body)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private func featureTabButton(_ tab: FeatureTab, label: String) -> some View {
        Button(label) {
            featureTab = tab
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: featureTab == tab ? .semibold : .regular))
        .foregroundColor(featureTab == tab ? ShipyardTheme.accent : ShipyardTheme.body)
    }

    private func showVersion(_ version: AppStoreVersionsModel) {
        if Self.isPendingVersion(version) {
            reviewsVM.selectAppStoreVersion(version)
        }
        shownVersionId = version.id
        featureTab = .overview
        syncDrafts()
        loadPhased()
    }

    private static func isPendingVersion(_ version: AppStoreVersionsModel) -> Bool {
        ReviewsViewModel.isPendingApprovalVersion(version)
    }

    @ViewBuilder
    private var featureContent: some View {
        switch featureTab {
        case .overview:
            overviewForm
        case .allVersions:
            allVersionsList
        case .resolution:
            resolutionCenter
        case .builds:
            versionBuilds
        }
    }

    // MARK: - Overview form

    private var overviewForm: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 20) {
                versionAndReleaseColumn
                reviewInformationColumn
            }
            .padding(24)
        }
    }

    private var versionAndReleaseColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Version *")
            fieldBox(disabled: !canEditShown) {
                TextField("2.4.0", text: $draftVersionString)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .disabled(!canEditShown)
            }

            whatsNewField

            Text("Build *")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
                .padding(.top, 8)
            buildSelectorCard

            Text("Version release")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
                .padding(.top, 8)
            releaseTypeOptions
            if draftReleaseType == .scheduled {
                DatePicker(
                    "Release date",
                    selection: $draftReleaseDate,
                    displayedComponents: .date
                )
                .font(.system(size: 12))
                .disabled(!canEditShown)
            }

            phasedReleaseRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var whatsNewField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                fieldLabel("What’s New * · \(localeDisplay(draftLocale?.locale))")
                Spacer(minLength: 0)
                if localizations.count > 1 {
                    Picker("", selection: $draftLocaleId) {
                        ForEach(localizations, id: \.id) { loc in
                            Text(localeDisplay(loc.locale))
                                .tag(Optional(loc.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.system(size: 11))
                    .frame(maxWidth: 160)
                }
            }
            fieldBox(disabled: !canEditShown, minHeight: 76) {
                TextEditor(text: $draftWhatsNew)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .disabled(!canEditShown)
                    .frame(minHeight: 60)
            }
            .overlay(alignment: .bottomTrailing) {
                Text("\(draftWhatsNew.count) / 4000")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
        }
        .onChange(of: draftLocaleId) { _, _ in
            if let loc = draftLocale {
                draftWhatsNew = loc.whatsNew ?? ""
            }
        }
    }

    private var localizations: [AppStoreVersionLocalizationsModel] {
        shownVersion?.appStoreVersionLocalizations ?? []
    }

    private var draftLocale: AppStoreVersionLocalizationsModel? {
        if let id = draftLocaleId {
            return localizations.first { $0.id == id }
        }
        return localizations.first
    }

    private var buildSelectorCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let build = shownVersion?.build {
                    Text("\(shownVersion?.versionString ?? "") · Build #\(build.version ?? "")")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                } else {
                    Text("No build selected")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                }
                Spacer(minLength: 0)
                if canEditShown {
                    Button("Choose Build") {
                        showChooseBuild = true
                    }
                    .buttonStyle(.launchSecondary)
                    .controlSize(.small)
                }
            }
            if let build = shownVersion?.build {
                Text("Uploaded \(buildDetailUploadedDisplay(build.uploadedDate))")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                buildStateBadge(build)
            } else {
                Text("Choose a processed build for version \(shownVersion?.versionString ?? "").")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
            }
            if let error = reviewsVM.attachBuildError, canEditShown {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.danger)
            }
        }
        .padding(10)
        .background(ShipyardTheme.tableBackground)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(LaunchTheme.border, lineWidth: 1)
        )
    }

    private func buildStateBadge(_ build: BuildsModel) -> some View {
        let state = build.processingState ?? ""
        return HStack(spacing: 5) {
            Circle()
                .fill(state == "VALID" ? ShipyardTheme.success : ShipyardTheme.accent)
                .frame(width: 6, height: 6)
            Text(buildStateDisplayName(state))
                .font(.system(size: 10))
                .foregroundColor(ShipyardTheme.title)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(ShipyardTheme.tableHeader)
        .cornerRadius(10)
    }

    private var releaseTypeOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            releaseOption(.manual, label: "Manually release")
            releaseOption(.afterApproval, label: "Automatically release after approval")
            releaseOption(.scheduled, label: "Automatically release on a specific date")
        }
        .disabled(!canEditShown)
    }

    private func releaseOption(_ type: AppStoreVersionReleaseType, label: String) -> some View {
        Button {
            draftReleaseType = type
        } label: {
            HStack(spacing: 8) {
                RadioDot(selected: draftReleaseType == type, color: ShipyardTheme.accent)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var phasedReleaseRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Phased release")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.title)
                Text(phasedReleaseSubtitle)
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
            }
            Spacer(minLength: 0)
            if reviewsVM.phasedLoading {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Toggle("", isOn: phasedBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!canEditShown || reviewsVM.phasedActionInFlight)
            }
        }
        .padding(.top, 4)
    }

    private var phasedReleaseSubtitle: String {
        if let release = reviewsVM.phasedRelease,
           reviewsVM.phasedVersionId == shownVersion?.id {
            return "State: \(release.phasedReleaseState ?? "unknown") — roll out this update over 7 days."
        }
        return "Roll out this update over 7 days."
    }

    private var phasedBinding: Binding<Bool> {
        Binding(
            get: {
                reviewsVM.phasedVersionId == shownVersion?.id
                    && (reviewsVM.phasedRelease?.phasedReleaseState ?? "") == "ACTIVE"
            },
            set: { on in
                guard let version = shownVersion else { return }
                Task {
                    if on {
                        if reviewsVM.phasedRelease == nil {
                            await reviewsVM.startPhasedRelease(versionId: version.id)
                        } else {
                            await reviewsVM.setPhasedReleaseState("ACTIVE")
                        }
                    } else {
                        await reviewsVM.setPhasedReleaseState("PAUSED")
                    }
                }
            }
        )
    }

    // MARK: - Review information (read-only: no API)

    private var reviewInformationColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Review information")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
            reviewDisabledField(label: "Contact name *", prompt: "Managed in App Store Connect")
            reviewDisabledField(label: "Phone *", prompt: "Managed in App Store Connect")
            reviewDisabledField(label: "Email *", prompt: "Managed in App Store Connect")
            HStack(spacing: 12) {
                Text("Sign-in required")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.title)
                Spacer(minLength: 0)
                Toggle("", isOn: .constant(false))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("Notes for App Review")
                fieldBox(disabled: true, minHeight: 76) {
                    Text("Managed in App Store Connect")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.tertiary)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                }
            }
            Text("Review contact details have no App Store Connect API — they can only be edited on the web.")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
            Button("Open in App Store Connect") {
                if let url = URL(string: "https://appstoreconnect.apple.com/apps/\(app.id)") {
                    openURL(url)
                }
            }
            .buttonStyle(.launchSecondary)
            .controlSize(.small)

            statusAlert

            Text(releaseTypeHelper)
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
            Button("Manage shared metadata in App Info ›") {
                onOpenAppInfo()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(ShipyardTheme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reviewDisabledField(label: String, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel(label)
            fieldBox(disabled: true) {
                Text(prompt)
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Status alert + action bar

    private var missingItems: [String] {
        guard let version = shownVersion, canEditShown else { return [] }
        var items: [String] = []
        if localizations.isEmpty
            || localizations.contains(where: { ($0.whatsNew ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            items.append("What’s New")
        }
        if version.build == nil {
            items.append("build")
        }
        if draftReleaseType == .scheduled && version.earliestReleaseDate == nil {
            items.append("release date")
        }
        return items
    }

    private var statusAlert: some View {
        let missing = missingItems
        return VStack(alignment: .leading, spacing: 4) {
            Text(missing.isEmpty ? "Ready to submit" : "\(missing.count) required item\(missing.count == 1 ? "" : "s") missing")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
            Text(missing.isEmpty
                ? "Version, release notes, build, and review contact are complete."
                : "Add \(missing.joined(separator: ", ")).")
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(ShipyardTheme.tableBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(LaunchTheme.border, lineWidth: 1)
        )
    }

    private var releaseTypeHelper: String {
        switch draftReleaseType {
        case .manual:
            return "After approval, the version waits for you to release it."
        case .afterApproval:
            return "After approval, the version releases to the App Store automatically."
        case .scheduled:
            return "After approval, the version releases on the scheduled date."
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("GENERAL INFORMATION")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
            inspectorRow(label: "APP NAME", value: app.name ?? "—")
            inspectorRow(label: "APPLE ID", value: app.id)
            inspectorRow(label: "SKU", value: app.sku ?? "—")
            inspectorRow(label: "PRIMARY LOCALE", value: localeDisplay(app.primaryLocale))
            ShipyardTheme.rowDivider.frame(height: 1)
            Text("VERSION HISTORY")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
            Text(getStatusLabel(appStoreState: shownState))
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.title)
            Text("Prepare → Waiting → In Review → Pending → Ready")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
            Button("View \(app.name ?? "App") Builds ›") {
                onOpenBuilds()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(ShipyardTheme.accent)
            Button("Edit App Info ›") {
                onOpenAppInfo()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(ShipyardTheme.accent)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 224)
        .background(ShipyardTheme.sidebarBackground)
        .overlay(
            ShipyardTheme.rowDivider.frame(width: 1),
            alignment: .leading
        )
    }

    private func inspectorRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(ShipyardTheme.tertiary)
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.title)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Text(actionBarText)
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let error = saveError ?? reviewsVM.releaseSettingsError, canEditShown {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.danger)
            }
            if saving {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Button("Save") {
                    save()
                }
                .buttonStyle(.launchSecondary)
                .disabled(!canEditShown || !isDirty)
            }
            if reviewsVM.submittingReview {
                ProgressView()
                    .scaleEffect(0.7)
            } else if canSubmit {
                Button("Submit for Review") {
                    showSubmitConfirm = true
                }
                .buttonStyle(.launchPrimary)
            } else {
                Button("Submit for Review") {
                    showSubmitConfirm = true
                }
                .buttonStyle(.launchSecondary)
                .disabled(true)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(ShipyardTheme.tableBackground)
        .confirmationDialog(
            "Submit version \(shownVersion?.versionString ?? "") (build \(shownVersion?.build?.version ?? "—")) to App Review? Metadata locks while it's in review.",
            isPresented: $showSubmitConfirm,
            titleVisibility: .visible
        ) {
            Button("Submit for Review") {
                Task {
                    if let version = shownVersion,
                       await reviewsVM.submitForReview(appId: app.id, versionId: version.id) {
                        reviewsVM.load(appId: app.id, force: true)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var actionBarText: String {
        guard shownVersion != nil else { return "" }
        if !canEditShown {
            return "Version is \(getStatusLabel(appStoreState: shownState).lowercased()) — metadata is locked while Apple has it."
        }
        let missing = missingItems
        if missing.isEmpty {
            return "All required fields complete · Submit → Waiting for Review"
        }
        return "Missing: \(missing.joined(separator: ", "))."
    }

    private var canSubmit: Bool {
        guard canEditShown, missingItems.isEmpty else { return false }
        return reviewsVM.canSubmitForReview
            && reviewsVM.submissionVersion?.id == shownVersion?.id
    }

    // MARK: - All versions / resolution / builds

    private var allVersionsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(allVersions, id: \.id) { version in
                    let state = version.appStoreState ?? version.appVersionState
                    Button {
                        showVersion(version)
                    } label: {
                        HStack(spacing: 12) {
                            Text("Version \(version.versionString ?? "—")")
                                .font(.system(size: 13))
                                .foregroundColor(ShipyardTheme.title)
                            statusBadge(state)
                            Spacer(minLength: 0)
                            if version.id == shownVersion?.id {
                                Text("Current")
                                    .font(.system(size: 11))
                                    .foregroundColor(ShipyardTheme.accent)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                        .background(ShipyardTheme.rowDivider)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var resolutionCenter: some View {
        ContentUnavailableView(
            "Resolution Center",
            systemImage: "envelope",
            description: Text("Rejection messages from App Review have no App Store Connect API — read and reply to them in App Store Connect.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var versionBuilds: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Builds for version \(shownVersion?.versionString ?? "—")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                if let build = shownVersion?.build {
                    HStack(spacing: 8) {
                        Text("#\(build.version ?? "")")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(ShipyardTheme.title)
                        buildStateBadge(build)
                        Spacer(minLength: 0)
                        Text("Attached")
                            .font(.system(size: 11))
                            .foregroundColor(ShipyardTheme.body)
                    }
                    .padding(10)
                    .background(ShipyardTheme.tableBackground)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(LaunchTheme.border, lineWidth: 1)
                    )
                }
                if canEditShown {
                    Button("Choose a different build") {
                        showChooseBuild = true
                    }
                    .buttonStyle(.launchSecondary)
                    .controlSize(.small)
                }
                Button("Open Builds tab") {
                    onOpenBuilds()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(ShipyardTheme.accent)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Drafts + save

    private var isDirty: Bool {
        guard let version = shownVersion else { return false }
        if draftVersionString != (version.versionString ?? "") { return true }
        if draftReleaseType.rawValue != (version.releaseType ?? "") { return true }
        if draftReleaseType == .scheduled { return true }
        if let loc = draftLocale, draftWhatsNew != (loc.whatsNew ?? "") { return true }
        return false
    }

    private func syncDrafts() {
        guard let version = shownVersion, syncedVersionId != version.id else { return }
        syncedVersionId = version.id
        saveError = nil
        draftVersionString = version.versionString ?? ""
        let locs = version.appStoreVersionLocalizations
        let preferred = locs.first { $0.locale == app.primaryLocale } ?? locs.first
        draftLocaleId = preferred?.id
        draftWhatsNew = preferred?.whatsNew ?? ""
        draftReleaseType = AppStoreVersionReleaseType(rawValue: version.releaseType ?? "") ?? .manual
        if let raw = version.earliestReleaseDate,
           let date = ISO8601DateFormatter().date(from: raw) {
            draftReleaseDate = date
        } else {
            draftReleaseDate = Date()
        }
    }

    private func loadPhased() {
        guard let version = shownVersion, canEditShown else { return }
        Task {
            await reviewsVM.loadPhasedRelease(versionId: version.id)
        }
    }

    private func save() {
        guard let version = shownVersion, canEditShown else { return }
        saving = true
        saveError = nil
        Task {
            var ok = true
            let versionDirty = draftVersionString != (version.versionString ?? "")
            let releaseDirty = draftReleaseType.rawValue != (version.releaseType ?? "")
                || draftReleaseType == .scheduled
            if versionDirty || releaseDirty {
                let result = await reviewsVM.saveReleaseSettings(
                    versionId: version.id,
                    releaseType: draftReleaseType,
                    earliestReleaseDate: draftReleaseType == .scheduled ? draftReleaseDate : nil,
                    versionString: versionDirty ? draftVersionString : nil)
                if case .failure(let message) = result {
                    saveError = message
                    ok = false
                }
            }
            if ok, let locId = draftLocaleId ?? draftLocale?.id,
               let loc = localizations.first(where: { $0.id == locId }),
               draftWhatsNew != (loc.whatsNew ?? "") {
                if await reviewsVM.saveVersionWhatsNew(
                    versionId: version.id,
                    localizationId: locId,
                    whatsNew: draftWhatsNew) == false {
                    saveError = reviewsVM.releaseSettingsError ?? "Couldn't save What's New."
                    ok = false
                }
            }
            saving = false
            if ok {
                syncedVersionId = nil
                syncDrafts()
            }
        }
    }

    // MARK: - Shared bits

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(ShipyardTheme.title)
    }

    private func fieldBox<Content: View>(disabled: Bool, minHeight: CGFloat = 28, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .background(disabled ? ShipyardTheme.tableHeader : LaunchTheme.field)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(LaunchTheme.border, lineWidth: 1)
            )
    }

    private var loadingView: some View {
        HStack {
            Spacer(minLength: 0)
            ProgressView()
                .scaleEffect(0.8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadErrorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text(message.isEmpty ? "Couldn't load versions" : message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            Button("Retry") {
                reviewsVM.retryAppStoreVersions()
            }
            .buttonStyle(.launchSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No App Store version yet")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            Text("Create one in App Info, then come back to prepare it for review.")
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
            Button("Open App Info") {
                onOpenAppInfo()
            }
            .buttonStyle(.launchSecondary)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func localeDisplay(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        switch raw {
        case "en-US": return "English (U.S.)"
        case "en-GB": return "English (U.K.)"
        case "en-AU": return "English (Australia)"
        case "en-CA": return "English (Canada)"
        case "fr-FR": return "French"
        case "de-DE": return "German"
        case "es-ES": return "Spanish (Spain)"
        case "es-MX": return "Spanish (Mexico)"
        case "it": return "Italian"
        case "ja": return "Japanese"
        case "ko": return "Korean"
        case "pt-BR": return "Portuguese (Brazil)"
        case "pt-PT": return "Portuguese (Portugal)"
        case "ru": return "Russian"
        case "zh-Hans": return "Chinese (Simplified)"
        case "zh-Hant": return "Chinese (Traditional)"
        default: return raw
        }
    }

    private func buildDetailUploadedDisplay(_ raw: String?) -> String {
        guard let date = buildUploadDate(raw) else { return "—" }
        let day = DateFormatter()
        day.dateFormat = "MMM d, yyyy"
        let time = DateFormatter()
        time.dateFormat = "h:mm a"
        return "\(day.string(from: date)) at \(time.string(from: date))"
    }
}
