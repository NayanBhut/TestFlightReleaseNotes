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
            reviewsVM.latestSubmission(forPlatform: version.platform)?.submittedDate)
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
    var title: String
    var localizations: [AppStoreVersionLocalizationsModel]
    var primaryLocale: String?

    private var localization: AppStoreVersionLocalizationsModel? {
        localizations.first { $0.locale == primaryLocale } ?? localizations.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
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

// MARK: - 05 Waiting for Review

struct WaitingVersionView: View {
    var version: AppStoreVersionsModel
    var localizations: [AppStoreVersionLocalizationsModel]
    var primaryLocale: String?
    @ObservedObject var reviewsVM: ReviewsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ReleaseAlert(
                style: .warning,
                title: "Waiting for Review",
                detail: "Submitted \(releaseDayDisplay(reviewsVM.latestSubmission(forPlatform: version.platform)?.submittedDate)). Estimated review: 24–48 hours.")
            SubmittedSummaryCard(version: version, reviewsVM: reviewsVM)
            WhatsNewCard(
                title: "What’s New · \(ReleasePrepareView.localeDisplay(localizations.first?.locale))",
                localizations: localizations,
                primaryLocale: primaryLocale)
            ReviewInfoBlock(reviewsVM: reviewsVM, versionId: version.id)
        }
    }
}

// MARK: - 06 In Review

struct InReviewVersionView: View {
    var version: AppStoreVersionsModel
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
            WhatsNewCard(
                title: "What’s New · \(ReleasePrepareView.localeDisplay(localizations.first?.locale))",
                localizations: localizations,
                primaryLocale: primaryLocale)
            ReviewInfoBlock(reviewsVM: reviewsVM, versionId: version.id)
        }
    }
}

// MARK: - 07 Pending Developer Release

struct PendingReleaseVersionView: View {
    var version: AppStoreVersionsModel
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
            WhatsNewCard(
                title: "What’s New · \(ReleasePrepareView.localeDisplay(localizations.first?.locale))",
                localizations: localizations,
                primaryLocale: primaryLocale)
            ReviewInfoBlock(reviewsVM: reviewsVM, versionId: version.id)
        }
    }
}

// MARK: - 09/09A Ready for Distribution

struct LiveVersionView: View {
    var version: AppStoreVersionsModel
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
                        Button("Resume") {
                            Task { await reviewsVM.setPhasedReleaseState("ACTIVE") }
                        }
                        .buttonStyle(.launchSecondary)
                        .controlSize(.small)
                        .disabled(!isPaused || reviewsVM.phasedActionInFlight)
                        Button("Release to All Users") {
                            showCompleteConfirm = true
                        }
                        .buttonStyle(.launchPrimary)
                        .controlSize(.small)
                        .disabled(reviewsVM.phasedActionInFlight)
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
            WhatsNewCard(
                title: "Published release notes · \(ReleasePrepareView.localeDisplay(localizations.first?.locale))",
                localizations: localizations,
                primaryLocale: primaryLocale)
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
            WhatsNewCard(
                title: "What’s New · \(ReleasePrepareView.localeDisplay(localizations.first?.locale))",
                localizations: localizations,
                primaryLocale: primaryLocale)
        }
    }
}
