//
//  ReleasePrepareView.swift
//  App Store
//
//  Figma 01/03/C2 — the editable submission form: version string,
//  per-locale What's New, build card, release type, phased release,
//  and the App Review contact panel. Review contact/demo/notes are
//  real API fields (appStoreReviewDetails); drafts live in the shell
//  and arrive here as bindings so the action bar can save them.
//

import SwiftUI
import AppKit

struct ReleasePrepareView: View {
    var app: AppsData
    var version: AppStoreVersionsModel
    @ObservedObject var reviewsVM: ReviewsViewModel
    var localizations: [AppStoreVersionLocalizationsModel]
    var requiresWhatsNew: Bool
    var reviewDetails: AppStoreReviewDetailsModel?
    var missingItems: [String]
    var missingDetail: String
    var canEdit: Bool
    @EnvironmentObject private var toastCenter: ShipyardToastCenter
    @Binding var draftVersionString: String
    @Binding var draftWhatsNew: String
    @Binding var draftLocaleId: String?
    @Binding var draftReleaseType: AppStoreVersionReleaseType
    @Binding var draftReleaseDate: Date
    @Binding var draftFirstName: String
    @Binding var draftLastName: String
    @Binding var draftPhone: String
    @Binding var draftEmail: String
    @Binding var draftDemoRequired: Bool
    @Binding var draftDemoUser: String
    @Binding var draftDemoPass: String
    @Binding var draftNotes: String
    @Binding var showChooseBuild: Bool
    var onOpenAppInfo: () -> Void

    @Environment(\.openURL) private var openURL

    /// Unsaved What's New held while the user confirms a locale switch —
    /// switching used to silently discard typed text (BUG_SWEEP #19).
    @State private var pendingWhatsNew: String?
    /// Locale the Picker asked for but that is NOT applied yet. Nothing is
    /// committed until the user answers the confirmation.
    @State private var pendingLocaleSwitch: String?
    /// Set by `commitLocaleSwitch` so the `draftLocaleId` observer knows
    /// the change was ours and must not re-seed from the server.
    @State private var didCommitLocaleSwitch = false

    var body: some View {
        TopPinnedScrollView {
            HStack(alignment: .top, spacing: 20) {
                versionAndReleaseColumn
                reviewInformationColumn
            }
            .padding(24)
        }
    }

    // MARK: - Version and release

    private var versionAndReleaseColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Version *")
            fieldBox(disabled: !canEdit) {
                TextField("2.4.0", text: $draftVersionString)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .disabled(!canEdit)
            }

            whatsNewField

            Text("Build *")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
                .padding(.top, 8)
            buildSelectorCard

            Text("Version release")
                .font(.system(size: 13, weight: .semibold))
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
                .disabled(!canEdit)
            }

            phasedReleaseRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var whatsNewField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                fieldLabel("\(requiresWhatsNew ? "What’s New *" : "What’s New") · \(Self.localeDisplay(draftLocale?.locale))")
                Spacer(minLength: 0)
                if requiresWhatsNew && localizations.count > 1 {
                    Picker("", selection: Binding<String?>(
                        get: { draftLocaleId },
                        set: { newId in
                            guard newId != draftLocaleId else { return }
                            let oldLocale = localizations.first(where: { $0.id == draftLocaleId })
                            let isDirty = oldLocale.map { draftWhatsNew != ($0.whatsNew ?? "") }
                            if isDirty == true, let target = newId {
                                // Don't switch yet — hold the target and the
                                // unsaved text until the user answers the
                                // confirmation.
                                pendingWhatsNew = draftWhatsNew
                                pendingLocaleSwitch = target
                            } else {
                                commitLocaleSwitch(to: newId, carrying: nil)
                            }
                        })) {
                        ForEach(localizations, id: \.id) { loc in
                            Text(Self.localeDisplay(loc.locale))
                                .tag(Optional(loc.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.system(size: 11))
                    .frame(maxWidth: 160)
                }
            }
            .onChange(of: draftLocaleId) { _, newId in
                // A switch we performed already seeded draftWhatsNew with
                // either the carried draft or the new locale's text.
                if didCommitLocaleSwitch {
                    didCommitLocaleSwitch = false
                    return
                }
                draftWhatsNew = localizations.first(where: { $0.id == newId })?.whatsNew ?? ""
            }
            .alert("Discard unsaved changes?",
                   isPresented: Binding(
                    get: { pendingLocaleSwitch != nil },
                    set: { if !$0 {
                        pendingLocaleSwitch = nil
                        pendingWhatsNew = nil
                    }}
                   )) {
                Button("Discard", role: .destructive) {
                    guard let target = pendingLocaleSwitch else { return }
                    // Take the new locale's stored text; the unsaved draft
                    // is what the user chose to throw away.
                    commitLocaleSwitch(to: target, carrying: nil)
                }
                Button("Keep", role: .cancel) {
                    // Stay on the current locale with the text intact.
                    pendingLocaleSwitch = nil
                    pendingWhatsNew = nil
                }
            } message: {
                Text("Switching locales would discard your unsaved What's New text.")
            }
            fieldBox(disabled: !canEdit || localizations.isEmpty || !requiresWhatsNew, minHeight: 76) {
                if !requiresWhatsNew || localizations.isEmpty {
                    Text(!requiresWhatsNew ? "What’s New is only needed for app updates after the first App Store release." : localesPlaceholder)
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.tertiary)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                } else {
                    TextEditor(text: $draftWhatsNew)
                        .font(.system(size: 13))
                        .environment(\.layoutDirection, draftLocaleTextDirection)
                        .scrollContentBackground(.hidden)
                        .disabled(!canEdit || !requiresWhatsNew)
                        .frame(minHeight: 60)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if requiresWhatsNew {
                    Text("\(draftWhatsNew.count) / 4000")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
            }
            if case .error(let message) = reviewsVM.versionLocalizationsState {
                HStack(spacing: 8) {
                    Text(message.isEmpty ? "Couldn't load locales." : message)
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.danger)
                    Button("Retry") {
                        reviewsVM.loadVersionLocalizations(versionId: version.id)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ShipyardTheme.accent)
                }
            }
        }
    }

    private var draftLocale: AppStoreVersionLocalizationsModel? {
        if let id = draftLocaleId {
            return localizations.first { $0.id == id }
        }
        return localizations.first
    }

    private var draftLocaleTextDirection: LayoutDirection {
        BetaLocalizationLocales.isRightToLeft(draftLocale?.locale) ? .rightToLeft : .leftToRight
    }

    /// Single place where a locale switch is applied. `carrying` is the
    /// unsaved text to keep in the editor (nil = load the target locale's
    /// stored text). Setting `draftLocaleId` and the editor text together
    /// keeps them consistent; the flag stops the `onChange` observer from
    /// overwriting what we just seeded.
    private func commitLocaleSwitch(to id: String?, carrying text: String?) {
        didCommitLocaleSwitch = (id != draftLocaleId)
        draftLocaleId = id
        draftWhatsNew = text
            ?? localizations.first(where: { $0.id == id })?.whatsNew
            ?? ""
        pendingWhatsNew = nil
        pendingLocaleSwitch = nil
    }

    private var localesPlaceholder: String {
        if case .loading = reviewsVM.versionLocalizationsState {
            return "Loading locales…"
        }
        return "Add a locale in App Info first."
    }

    private var buildSelectorCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let build = version.build {
                    Text("\(version.versionString ?? "") · Build #\(build.version ?? "")")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                } else {
                    Text("No build selected")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                }
                Spacer(minLength: 0)
                if canEdit {
                    Button("Choose Build") {
                        showChooseBuild = true
                    }
                    .buttonStyle(.launchSecondary)
                    .controlSize(.small)
                }
            }
            if let build = version.build {
                Text("Uploaded \(buildDetailUploadedDisplay(build.uploadedDate))")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                buildStateBadge(build)
            } else {
                Text("Choose a processed build for version \(version.versionString ?? "").")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
            }
            if let error = reviewsVM.attachBuildError, canEdit {
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
        .disabled(!canEdit)
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
                    .font(.system(size: 13, weight: .semibold))
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
                    .accessibilityLabel("Phased release")
                    .disabled(!canEdit || reviewsVM.phasedActionInFlight)
            }
        }
        .padding(.top, 4)
    }

    private var phasedReleaseSubtitle: String {
        if let release = reviewsVM.phasedRelease,
           reviewsVM.phasedVersionId == version.id {
            return "State: \(release.phasedReleaseState ?? "unknown") — roll out this update over 7 days."
        }
        return "Roll out this update over 7 days."
    }

    private var phasedBinding: Binding<Bool> {
        Binding(
            get: {
                reviewsVM.phasedVersionId == version.id
                    && (reviewsVM.phasedRelease?.phasedReleaseState ?? "") == "ACTIVE"
            },
            set: { on in
                Task {
                    let success: Bool
                    if on {
                        if reviewsVM.phasedRelease == nil {
                            success = await reviewsVM.startPhasedRelease(versionId: version.id)
                        } else {
                            success = await reviewsVM.setPhasedReleaseState("ACTIVE")
                        }
                    } else {
                        success = await reviewsVM.setPhasedReleaseState("PAUSED")
                    }
                    if success {
                        toastCenter.show(on ? "Phased release enabled" : "Phased release paused", variant: .success)
                    } else if let message = reviewsVM.writeError {
                        toastCenter.show("Couldn't update phased release", detail: message, variant: .error)
                    }
                }
            }
        )
    }

    // MARK: - Review information (live API fields)

    private var reviewInformationColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Review information")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            reviewField(label: "First name *", text: $draftFirstName, prompt: "Sarah")
            reviewField(label: "Last name *", text: $draftLastName, prompt: "Connor")
            reviewField(label: "Phone *", text: $draftPhone, prompt: "+1 (415) 555-0128")
            reviewField(label: "Email *", text: $draftEmail, prompt: "review@example.com")
            HStack(spacing: 12) {
                Text("Sign-in required")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.title)
                Spacer(minLength: 0)
                Toggle("", isOn: $draftDemoRequired)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Sign-in required")
                    .disabled(!canEdit)
            }
            if draftDemoRequired {
                reviewField(label: "Demo username *", text: $draftDemoUser, prompt: "reviewer@example.com")
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Demo password *")
                    fieldBox(disabled: !canEdit) {
                        SecureField("Required for App Review sign-in", text: $draftDemoPass)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .disabled(!canEdit)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("Notes for App Review")
                fieldBox(disabled: !canEdit, minHeight: 76) {
                    TextEditor(text: $draftNotes)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .disabled(!canEdit)
                        .frame(minHeight: 60)
                }
                .overlay(alignment: .bottomTrailing) {
                    Text("\(draftNotes.count) / 4000")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
            }
            if let error = reviewsVM.releaseSettingsError, canEdit {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.danger)
            }
            if case .error(let message) = reviewsVM.reviewDetailsState {
                HStack(spacing: 8) {
                    Text(message.isEmpty ? "Couldn't load review contact." : message)
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.danger)
                    Button("Retry") {
                        reviewsVM.loadReviewDetails(versionId: version.id)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ShipyardTheme.accent)
                }
            }

            ReleaseAlert(
                style: .neutral,
                title: missingItems.isEmpty ? "Ready to submit" : "\(missingItems.count) required item\(missingItems.count == 1 ? "" : "s") missing",
                detail: missingItems.isEmpty
                    ? "Version, release notes, build, and review contact are complete."
                    : missingDetail)

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

    private func reviewField(label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel(label)
            fieldBox(disabled: !canEdit) {
                TextField(prompt, text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .disabled(!canEdit)
            }
        }
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

    // MARK: - Shared bits

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
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

    static func localeDisplay(_ raw: String?) -> String {
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
