//
//  ReleaseStatusViews.swift
//  App Store
//
//  Read-only status screens for the App Store Versions workspace:
//  05 Waiting for Review, 06 In Review, 07 Pending Developer Release,
//  09/09A Ready for Distribution (live + paused phased rollout),
//  R1/R2 rejection threads, and a generic locked-state view for the
//  remaining Apple-held states. Submitted data comes from
//  ReviewsViewModel; anything without API coverage renders as an
//  explicit App Store Connect handoff, never mock data.
//

import SwiftUI

// MARK: - Shared blocks

/// "Submitted summary" card shared by 05/06/07.
struct SubmittedSummaryCard: View {
    var version: AppStoreVersionsModel
    @ObservedObject var reviewsVM: ReviewsViewModel

    private var submittedDate: String {
        releaseDateTimeDisplay(
            reviewsVM.latestSubmission(for: version)?.submittedDate)
    }

    private var phasedText: String {
        if let release = reviewsVM.phasedRelease,
           reviewsVM.phasedVersionId == version.id {
            return phasedReleaseDisplay(state: release.phasedReleaseState)
        }
        return "Disabled"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Submitted summary")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
            ReleaseSummaryCard(rows: [
                (label: "Version / Build",
                 value: "\(version.versionString ?? "—") / #\(version.build?.version ?? "—")"),
                (label: "Uploaded", value: releaseDateTimeDisplay(version.build?.uploadedDate)),
                (label: "Submitted", value: submittedDate),
                (label: "Release type", value: humanizedReleaseType(version.releaseType)),
                (label: "Phased release", value: phasedText),
            ])
        }
    }
}

/// "What's New · {locale}" bullet card (05/06/07) or published notes (09).
struct WhatsNewCard: View {
    /// Title without the locale suffix. The card appends the locale it
    /// actually renders, so the heading can't contradict the body — the
    /// previous per-call-site `localizations.first?.locale` titles picked
    /// a different locale than the body on 4 of 5 screens (BUG_SWEEP #20).
    var titlePrefix: String
    var localizations: [AppStoreVersionLocalizationsModel]
    var primaryLocale: String?

    private var localization: AppStoreVersionLocalizationsModel? {
        localizations.first { $0.locale == primaryLocale } ?? localizations.first
    }

    private var resolvedTitle: String {
        guard let locale = localization?.locale else { return titlePrefix }
        return "\(titlePrefix) · \(ReleasePrepareView.localeDisplay(locale))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(resolvedTitle)
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
            if let text = localization?.whatsNew, !text.isEmpty {
                Text(bulleted(text))
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(ShipyardTheme.tableBackground)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(LaunchTheme.border, lineWidth: 1)
                    )
            } else {
                Text("No release notes yet.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.tertiary)
            }
        }
    }

    private func bulleted(_ text: String) -> String {
        text.split(separator: "\n")
            .map { "• \($0.trimmingCharacters(in: .whitespaces))" }
            .joined(separator: "\n")
    }
}

struct SubmittedMetadataCard: View {
    @ObservedObject var detailVM: DetailViewModel
    var localizations: [AppStoreVersionLocalizationsModel]
    var primaryLocale: String?

    @State private var selectedLocalizationId: String?

    private var sortedLocalizations: [AppStoreVersionLocalizationsModel] {
        localizations.sorted { lhs, rhs in
            if lhs.locale == primaryLocale { return true }
            if rhs.locale == primaryLocale { return false }
            return (lhs.locale ?? "") < (rhs.locale ?? "")
        }
    }

    private var localizationKey: String {
        sortedLocalizations.map(\.id).joined(separator: "|")
    }

    private var selectedLocalization: AppStoreVersionLocalizationsModel? {
        if let selectedLocalizationId,
           let selected = sortedLocalizations.first(where: { $0.id == selectedLocalizationId }) {
            return selected
        }
        return sortedLocalizations.first { $0.locale == primaryLocale } ?? sortedLocalizations.first
    }

    private var appInfoLocalizations: [AppInfoLocalizationModel] {
        detailVM.appInfoState.loadedValue?.flatMap(\.appInfoLocalizations) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Submitted App Store metadata")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.title)
                Spacer(minLength: 0)
                if sortedLocalizations.count > 1 {
                    Menu {
                        ForEach(sortedLocalizations, id: \.id) { localization in
                            Button(ReleasePrepareView.localeDisplay(localization.locale)) {
                                selectedLocalizationId = localization.id
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Localization: \(ReleasePrepareView.localeDisplay(selectedLocalization?.locale))")
                                .font(.system(size: 11))
                                .foregroundColor(ShipyardTheme.body)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(ShipyardTheme.tertiary)
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
                    .accessibilityLabel("Select submitted metadata localization")
                }
                if detailVM.appInfoState.isLoading {
                    ProgressView().controlSize(.mini)
                }
            }

            if sortedLocalizations.isEmpty {
                Text("Loading submitted metadata…")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
            } else if let selectedLocalization {
                VersionLocalizationSubmittedCard(
                    detailVM: detailVM,
                    localization: selectedLocalization,
                    appInfoLocalization: appInfoLocalization(for: selectedLocalization.locale))
            }
        }
        .onAppear {
            detailVM.loadAppInfo()
            seedSelectionIfNeeded()
            loadSelectedScreenshots()
        }
        .onChange(of: localizationKey) {
            seedSelectionIfNeeded()
            loadSelectedScreenshots()
        }
        .onChange(of: selectedLocalizationId) {
            loadSelectedScreenshots()
        }
    }

    private func seedSelectionIfNeeded() {
        if let selectedLocalizationId,
           sortedLocalizations.contains(where: { $0.id == selectedLocalizationId }) {
            return
        }
        selectedLocalizationId = selectedLocalization?.id
    }

    private func loadSelectedScreenshots() {
        guard let id = selectedLocalization?.id else { return }
        detailVM.loadLocalizationScreenshotPreview(localizationId: id)
    }

    private func appInfoLocalization(for locale: String?) -> AppInfoLocalizationModel? {
        appInfoLocalizations.first { $0.locale == locale }
            ?? appInfoLocalizations.first { $0.locale == primaryLocale }
            ?? appInfoLocalizations.first
    }
}

private struct VersionLocalizationSubmittedCard: View {
    @ObservedObject var detailVM: DetailViewModel
    var localization: AppStoreVersionLocalizationsModel
    var appInfoLocalization: AppInfoLocalizationModel?

    private var localeTitle: String {
        ReleasePrepareView.localeDisplay(localization.locale)
    }

    private var localeTextDirection: LayoutDirection {
        BetaLocalizationLocales.isRightToLeft(localization.locale) ? .rightToLeft : .leftToRight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("General Information")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    SubmittedMetadataField(
                        label: "App Name",
                        value: appInfoLocalization?.name,
                        limit: 30,
                        direction: localeTextDirection)
                    SubmittedMetadataField(
                        label: "Subtitle",
                        value: appInfoLocalization?.subtitle,
                        limit: 30,
                        direction: localeTextDirection)
                    SubmittedMetadataField(
                        label: "Privacy Policy URL",
                        value: appInfoLocalization?.privacyPolicyUrl,
                        isURL: true)
                    SubmittedMetadataField(
                        label: "Support URL",
                        value: localization.supportUrl,
                        isURL: true)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 20) {
                    Text("Localization (\(localeTitle))")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    SubmittedMetadataField(
                        label: "Description",
                        value: localization.descriptionData,
                        limit: 4000,
                        multiline: true,
                        direction: localeTextDirection)
                    SubmittedMetadataField(
                        label: "Keywords",
                        value: localization.keywords,
                        limit: 100,
                        direction: localeTextDirection)
                    SubmittedMetadataField(
                        label: "Promotional Text",
                        value: localization.promotionalText,
                        limit: 170,
                        direction: localeTextDirection)
                    SubmittedMetadataField(
                        label: "Marketing URL",
                        value: localization.marketingUrl,
                        isURL: true)
                    SubmittedMetadataField(
                        label: "What’s New",
                        value: localization.whatsNew,
                        multiline: true,
                        direction: localeTextDirection)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            ScreenshotPreviewStrip(
                state: detailVM.localizationScreenshotPreviews[localization.id],
                localizationId: localization.id)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ShipyardTheme.tableBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(LaunchTheme.border, lineWidth: 1)
        )
        .onAppear {
            detailVM.loadLocalizationScreenshotPreview(localizationId: localization.id)
        }
    }
}

private struct SubmittedMetadataField: View {
    var label: String
    var value: String?
    var limit: Int?
    var multiline = false
    var isURL = false
    var direction: LayoutDirection = .leftToRight

    private var rawValue: String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var displayValue: String {
        rawValue.isEmpty ? "—" : rawValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
                Spacer()
                if let limit {
                    Text("\(rawValue.count) / \(limit)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(ShipyardTheme.body)
                }
            }

            if multiline {
                ScrollView {
                    Text(displayValue)
                        .font(.system(size: 13))
                        .foregroundColor(rawValue.isEmpty ? ShipyardTheme.tertiary : ShipyardTheme.title)
                        .textSelection(.enabled)
                        .environment(\.layoutDirection, isURL ? .leftToRight : direction)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(height: label == "Description" ? 110 : 84)
                .background(LaunchTheme.field)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(LaunchTheme.border, lineWidth: 1)
                )
            } else {
                Text(displayValue)
                    .font(.system(size: 13))
                    .foregroundColor(rawValue.isEmpty ? ShipyardTheme.tertiary : ShipyardTheme.title)
                    .textSelection(.enabled)
                    .environment(\.layoutDirection, isURL ? .leftToRight : direction)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(LaunchTheme.field)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(LaunchTheme.border, lineWidth: 1)
                    )
            }
        }
    }
}

private struct ScreenshotPreviewStrip: View {
    var state: ViewState<[AppScreenshotModel]>?
    var localizationId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SCREENSHOTS")
                .font(.system(size: 10))
                .foregroundColor(ShipyardTheme.tertiary)
            switch state {
            case .some(.loaded(let screenshots)) where !screenshots.isEmpty:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(screenshots, id: \.id) { screenshot in
                            ScreenshotThumbnail(screenshot: screenshot)
                        }
                    }
                }
            case .some(.empty):
                Text("No screenshots uploaded for this locale.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.tertiary)
            case .some(.error(let message)):
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.danger)
            default:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text("Loading screenshots…")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                }
            }
        }
    }
}

private struct ScreenshotThumbnail: View {
    var screenshot: AppScreenshotModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AsyncImage(url: screenshotThumbnailURL(screenshot.imageAsset?.templateUrl, maxDimension: 180)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                case .failure:
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LaunchTheme.page)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundColor(ShipyardTheme.body)
                        }
                default:
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LaunchTheme.page)
                        .overlay { ProgressView().controlSize(.mini) }
                }
            }
            .frame(width: 120, height: 120)
            .cornerRadius(6)
            Text(screenshot.fileName ?? "Screenshot")
                .font(.system(size: 10))
                .foregroundColor(ShipyardTheme.body)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)
        }
    }
}

/// "App Review information" read-only block. Real contact data when the
/// review-details record loaded; otherwise the web-only handoff line.
struct ReviewInfoBlock: View {
    @ObservedObject var reviewsVM: ReviewsViewModel
    var versionId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("App Review information")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
            if reviewsVM.reviewDetailsVersionId == versionId,
               let details = reviewsVM.reviewDetailsState.loadedValue {
                Text(contactLine(details))
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
                Text("Sign-in required: \(details.demoAccountRequired == true ? "Yes" : "No"). \((details.notes ?? "").isEmpty ? "" : "Review notes: \(details.notes ?? "")")")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
            } else {
                Text("Review contact details are managed in App Store Connect.")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
            }
        }
    }

    private func contactLine(_ details: AppStoreReviewDetailsModel) -> String {
        let name = [details.contactFirstName, details.contactLastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return [name, details.contactPhone, details.contactEmail]
            .map { $0 ?? "" }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

// MARK: - 05 Ready / Waiting for Review

struct WaitingVersionView: View {
    var version: AppStoreVersionsModel
    @ObservedObject var detailVM: DetailViewModel
    var localizations: [AppStoreVersionLocalizationsModel]
    var primaryLocale: String?
    @ObservedObject var reviewsVM: ReviewsViewModel

    private var isReadyForReview: Bool {
        (version.appStoreState ?? version.appVersionState) == "READY_FOR_REVIEW"
    }

    private var alertTitle: String {
        isReadyForReview ? "Ready for Review" : "Waiting for Review"
    }

    private var alertDetail: String {
        if isReadyForReview {
            return "Added to a draft submission. App Store Connect has not confirmed sending it to Apple yet."
        }
        return "Submitted \(releaseDayDisplay(reviewsVM.latestSubmission(for: version)?.submittedDate)). Estimated review: 24–48 hours."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ReleaseAlert(
                style: .warning,
                title: alertTitle,
                detail: alertDetail)
                .accessibilityIdentifier(isReadyForReview ? "review.ready.card" : "review.waiting.card")
            SubmittedSummaryCard(version: version, reviewsVM: reviewsVM)
            SubmittedMetadataCard(detailVM: detailVM, localizations: localizations, primaryLocale: primaryLocale)
            ReviewInfoBlock(reviewsVM: reviewsVM, versionId: version.id)
        }
    }
}

// MARK: - 06 In Review

struct InReviewVersionView: View {
    var version: AppStoreVersionsModel
    @ObservedObject var detailVM: DetailViewModel
    var localizations: [AppStoreVersionLocalizationsModel]
    var primaryLocale: String?
    @ObservedObject var reviewsVM: ReviewsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ReleaseAlert(
                style: .info,
                title: "Apple is reviewing your app",
                detail: "Version \(version.versionString ?? "") and Build #\(version.build?.version ?? "—") are being reviewed. Submitted information is read-only.")
            Text("Submitted ✓ → Waiting ✓ → In Review → Approval")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.accent)
            SubmittedSummaryCard(version: version, reviewsVM: reviewsVM)
            SubmittedMetadataCard(detailVM: detailVM, localizations: localizations, primaryLocale: primaryLocale)
            ReviewInfoBlock(reviewsVM: reviewsVM, versionId: version.id)
        }
    }
}

// MARK: - 07 Pending Developer Release

struct PendingReleaseVersionView: View {
    var version: AppStoreVersionsModel
    @ObservedObject var detailVM: DetailViewModel
    var localizations: [AppStoreVersionLocalizationsModel]
    var primaryLocale: String?
    @ObservedObject var reviewsVM: ReviewsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ReleaseAlert(
                style: .success,
                title: "Your app is approved",
                detail: "\(version.versionString.map { "Version \($0) is ready to release. " } ?? "")You chose to manually release this version.")
            SubmittedSummaryCard(version: version, reviewsVM: reviewsVM)
            SubmittedMetadataCard(detailVM: detailVM, localizations: localizations, primaryLocale: primaryLocale)
            ReviewInfoBlock(reviewsVM: reviewsVM, versionId: version.id)
        }
    }
}

// MARK: - 09/09A Ready for Distribution

struct LiveVersionView: View {
    var version: AppStoreVersionsModel
    @ObservedObject var detailVM: DetailViewModel
    var localizations: [AppStoreVersionLocalizationsModel]
    var primaryLocale: String?
    @ObservedObject var reviewsVM: ReviewsViewModel
    var removedFromSale: Bool

    @Environment(\.openURL) private var openURL
    @State private var showCompleteConfirm = false

    private var phased: PhasedReleaseModel? {
        reviewsVM.phasedVersionId == version.id ? reviewsVM.phasedRelease : nil
    }

    private var day: Int { phased?.currentDayNumber ?? 1 }
    private var percent: Int { ReleaseComponents.phasedPercent(day: day) }
    private var isPaused: Bool { (phased?.phasedReleaseState ?? "") == "PAUSED" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if removedFromSale {
                ReleaseAlert(
                    style: .neutral,
                    title: "Not for sale",
                    detail: "Version \(version.versionString ?? "") was removed from sale. Availability is managed in App Store Connect.")
            } else {
                ReleaseAlert(
                    style: .success,
                    title: "Version \(version.versionString ?? "") is live on the App Store",
                    detail: "Build #\(version.build?.version ?? "—") · Available in all selected territories.")
            }
            if phased != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Phased release")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                    HStack {
                        Text("Day \(day) of 7 · \(percent)% of users")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(ShipyardTheme.title)
                        Spacer(minLength: 0)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(isPaused ? ShipyardTheme.warning : ShipyardTheme.success)
                                .frame(width: 6, height: 6)
                            Text(isPaused ? "Paused" : "Active")
                                .font(.system(size: 10))
                                .foregroundColor(ShipyardTheme.title)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(ShipyardTheme.tableHeader)
                        .cornerRadius(10)
                    }
                    PhasedProgressBar(day: day)
                    Text(isPaused
                        ? "Automatic updates stay at \(percent)% until you resume."
                        : "Automatic updates advance daily. Users can download the update manually at any time.")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                    HStack(spacing: 8) {
                        Button("Pause") {
                            Task { await reviewsVM.setPhasedReleaseState("PAUSED") }
                        }
                        .buttonStyle(.launchSecondary)
                        .controlSize(.small)
                        .disabled(isPaused || reviewsVM.phasedActionInFlight)
                        .accessibilityIdentifier("review.phased.pause")
                        Button("Resume") {
                            Task { await reviewsVM.setPhasedReleaseState("ACTIVE") }
                        }
                        .buttonStyle(.launchSecondary)
                        .controlSize(.small)
                        .disabled(!isPaused || reviewsVM.phasedActionInFlight)
                        .accessibilityIdentifier("review.phased.resume")
                        Button("Release to All Users") {
                            showCompleteConfirm = true
                        }
                        .buttonStyle(.launchPrimary)
                        .controlSize(.small)
                        .disabled(reviewsVM.phasedActionInFlight)
                        .accessibilityIdentifier("review.phased.complete")
                        .confirmationDialog(
                            "End the phased rollout? All remaining users receive the update immediately.",
                            isPresented: $showCompleteConfirm,
                            titleVisibility: .visible
                        ) {
                            Button("Release to All Users") {
                                Task { await reviewsVM.setPhasedReleaseState("COMPLETE") }
                            }
                            Button("Cancel", role: .cancel) {}
                        }
                    }
                    if let error = reviewsVM.writeError {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(ShipyardTheme.danger)
                    }
                }
                .padding(12)
                .background(ShipyardTheme.tableBackground)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(LaunchTheme.border, lineWidth: 1)
                )
            }
            SubmittedMetadataCard(detailVM: detailVM, localizations: localizations, primaryLocale: primaryLocale)
            Text("Manual release · Phased release \(phased == nil ? "disabled" : (isPaused ? "paused" : "enabled"))")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.tertiary)
        }
    }
}

// MARK: - R1/R2 Rejection threads

/// Resolution Center conversation for a rejected version. The thread has
/// no API surface, so it renders the rejection context with a disabled
/// composer and an App Store Connect handoff instead of mock messages.
struct RejectedThreadView: View {
    enum Kind {
        case binary, metadata
    }

    var version: AppStoreVersionsModel
    var kind: Kind
    var appId: String

    @Environment(\.openURL) private var openURL
    @State private var replyText = ""

    private var rejectionCopy: (title: String, detail: String) {
        switch kind {
        case .binary:
            return ("Binary rejected",
                    "Build #\(version.build?.version ?? "—") was rejected during review. Fix the issue, upload a new build, and resubmit version \(version.versionString ?? "").")
        case .metadata:
            return ("Metadata rejected",
                    "Update the metadata in App Info. Version \(version.versionString ?? "") can keep Build #\(version.build?.version ?? "—") — no new binary is required.")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ReleaseAlert(style: .danger, title: rejectionCopy.title, detail: rejectionCopy.detail)
            VStack(alignment: .leading, spacing: 10) {
                Text("Resolution Center")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.title)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Conversations with App Review live in App Store Connect — the API doesn’t expose rejection messages or replies.")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                    Button("Open Resolution Center") {
                        if let url = URL(string: "https://appstoreconnect.apple.com/apps/\(appId)") {
                            openURL(url)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ShipyardTheme.accent)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ShipyardTheme.tableBackground)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(LaunchTheme.border, lineWidth: 1)
                )
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Reply to App Review")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
                TextEditor(text: $replyText)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .disabled(true)
                    .frame(minHeight: 60)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ShipyardTheme.tableHeader)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(LaunchTheme.border, lineWidth: 1)
                    )
                HStack(spacing: 8) {
                    Button("Reply") {}
                        .buttonStyle(.launchPrimary)
                        .controlSize(.small)
                        .disabled(true)
                    Button("Appeal") {}
                        .buttonStyle(.launchSecondary)
                        .controlSize(.small)
                        .disabled(true)
                }
            }
        }
    }
}

// MARK: - Generic locked state

/// Read-only view for Apple-held states without a dedicated screen
/// (automatic/scheduled pending release, processing, export compliance,
/// contracts, historical versions).
struct LockedVersionView: View {
    var version: AppStoreVersionsModel
    @ObservedObject var detailVM: DetailViewModel
    var localizations: [AppStoreVersionLocalizationsModel]
    var primaryLocale: String?
    @ObservedObject var reviewsVM: ReviewsViewModel

    private var copy: (title: String, detail: String) {
        let state = version.appStoreState ?? version.appVersionState
        switch state {
        case "PENDING_APPLE_RELEASE":
            return ("Scheduled for automatic release",
                    "Version \(version.versionString ?? "") was approved and releases automatically. Submitted information is read-only.")
        case "PROCESSING_FOR_DISTRIBUTION":
            return ("Processing for distribution",
                    "Apple is preparing version \(version.versionString ?? "") for the App Store. Check back shortly.")
        case "WAITING_FOR_EXPORT_COMPLIANCE":
            return ("Export compliance under review",
                    "Version \(version.versionString ?? "") is waiting on export compliance. Submitted information is read-only.")
        case "PENDING_CONTRACT":
            return ("Pending contract",
                    "A blocking agreement, tax, or banking issue must be resolved before version \(version.versionString ?? "") can proceed.")
        case "REMOVED_FROM_SALE", "DEVELOPER_REMOVED_FROM_SALE":
            return ("Removed from sale",
                    "Version \(version.versionString ?? "") is no longer available. Availability is managed in App Store Connect.")
        case "REPLACED_WITH_NEW_VERSION":
            return ("Superseded version",
                    "Version \(version.versionString ?? "") was replaced by a newer version. This record is read-only history.")
        default:
            return (getStatusLabel(appStoreState: state),
                    "Version \(version.versionString ?? "") is with Apple. Submitted information is read-only.")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ReleaseAlert(style: .neutral, title: copy.title, detail: copy.detail)
            SubmittedSummaryCard(version: version, reviewsVM: reviewsVM)
            SubmittedMetadataCard(detailVM: detailVM, localizations: localizations, primaryLocale: primaryLocale)
        }
    }
}
