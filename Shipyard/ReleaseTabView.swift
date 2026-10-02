//
//  ReleaseTabView.swift
//  App Store
//
//  Phase 1 of the submission flow: read-only release status plus a
//  readiness checklist over the pending/live appStoreVersion, with the
//  existing submit-for-review write wired behind a confirmation. All
//  version state comes from ReviewsViewModel's App Info pipeline —
//  nothing here fetches or decodes versions itself.
//

import SwiftUI

/// Read-only release readiness for one app. Screenshots and the age
/// rating questionnaire have no API surface, so they render as manual
/// handoff rows linking out to App Store Connect instead of checks.
struct ReleaseTabView: View {
    var app: AppsData
    @ObservedObject var reviewsVM: ReviewsViewModel
    var onOpenAppInfo: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var showSubmitConfirm = false

    private var version: AppStoreVersionsModel? {
        reviewsVM.displayedAppStoreVersion
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error = reviewsVM.appStoreVersionsError {
                    errorBanner(error) {
                        reviewsVM.retryAppStoreVersions()
                    }
                }
                if let error = reviewsVM.writeError {
                    errorBanner(error) {
                        reviewsVM.writeError = nil
                    }
                }
                switch reviewsVM.appStoreVersionsState {
                case .loading, .idle:
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                        Spacer()
                    }
                    .padding(.top, 40)
                case .error(let message):
                    VStack(spacing: 8) {
                        Text(message.isEmpty ? "Couldn't load versions" : message)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ShipyardTheme.title)
                        Button("Retry") {
                            reviewsVM.retryAppStoreVersions()
                        }
                        .buttonStyle(.launchSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                case .loaded:
                    if let version {
                        statusCard(version)
                        checklistCard(version)
                        submitCard(version)
                        manualStepsCard
                    } else {
                        emptyState
                    }
                case .empty:
                    emptyState
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShipyardTheme.tableBackground)
        .onAppear {
            reviewsVM.load(app: app)
        }
    }

    // MARK: - Status

    private func statusCard(_ version: AppStoreVersionsModel) -> some View {
        let state = version.appStoreState ?? version.appVersionState
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Version \(version.versionString ?? "—")")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                statusPill(state)
                Spacer()
                Button("Refresh") {
                    reviewsVM.load(appId: app.id, force: true)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.accent)
            }
            HStack(spacing: 16) {
                statusMeta(
                    label: "BUILD",
                    value: version.build?.version ?? "None attached")
                statusMeta(
                    label: "PLATFORM",
                    value: version.platform ?? "—")
                statusMeta(
                    label: "RELEASE",
                    value: humanizedReleaseType(version.releaseType))
            }
        }
        .padding(16)
        .background(LaunchTheme.page)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(LaunchTheme.border, lineWidth: 1)
        )
    }

    private func statusPill(_ state: String?) -> some View {
        Text(getStatusLabel(appStoreState: state))
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(ShipyardTheme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(ShipyardTheme.accent.opacity(0.12))
            .cornerRadius(10)
    }

    private func statusMeta(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(ShipyardTheme.body)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(ShipyardTheme.title)
        }
    }

    private func humanizedReleaseType(_ raw: String?) -> String {
        switch raw {
        case AppStoreVersionReleaseType.manual.rawValue: return "Manual hold"
        case AppStoreVersionReleaseType.afterApproval.rawValue: return "Automatic"
        case AppStoreVersionReleaseType.scheduled.rawValue: return "Scheduled"
        default: return "—"
        }
    }

    // MARK: - Checklist

    private enum CheckStatus {
        case pass, warn, fail
    }

    private struct CheckRow: Identifiable {
        let id = UUID()
        let status: CheckStatus
        let title: String
        let detail: String
    }

    private func checks(for version: AppStoreVersionsModel) -> [CheckRow] {
        var rows: [CheckRow] = []

        if let build = version.build {
            if build.expired == true {
                rows.append(CheckRow(
                    status: .fail,
                    title: "Build expired",
                    detail: "Build \(build.version ?? "—") is expired — attach a fresh build in App Info."))
            } else if build.processingState == "VALID" {
                rows.append(CheckRow(
                    status: .pass,
                    title: "Build attached",
                    detail: "Build \(build.version ?? "—") is valid."))
            } else {
                rows.append(CheckRow(
                    status: .warn,
                    title: "Build state: \(build.processingState ?? "unknown")",
                    detail: "Apple must finish processing before review."))
            }
        } else {
            rows.append(CheckRow(
                status: .fail,
                title: "No build attached",
                detail: "Pick an eligible build in App Info."))
        }

        let localizations = version.appStoreVersionLocalizations
        if localizations.isEmpty {
            rows.append(CheckRow(
                status: .fail,
                title: "No version localizations",
                detail: "Add at least one locale in App Info."))
        } else {
            let incomplete = localizations.compactMap { loc -> String? in
                var missing: [String] = []
                if (loc.descriptionData ?? "").isEmpty { missing.append("description") }
                if (loc.keywords ?? "").isEmpty { missing.append("keywords") }
                guard !missing.isEmpty else { return nil }
                return "\(loc.locale ?? "?"): \(missing.joined(separator: ", "))"
            }
            if incomplete.isEmpty {
                let names = localizations.compactMap { $0.locale }.joined(separator: ", ")
                rows.append(CheckRow(
                    status: .pass,
                    title: "Metadata complete (\(localizations.count))",
                    detail: names))
            } else {
                rows.append(CheckRow(
                    status: .warn,
                    title: "Metadata gaps",
                    detail: incomplete.joined(separator: "; ")))
            }
        }

        if (version.copyright ?? "").isEmpty {
            rows.append(CheckRow(
                status: .warn,
                title: "Copyright missing",
                detail: "Set it on the version in App Info."))
        } else {
            rows.append(CheckRow(
                status: .pass,
                title: "Copyright set",
                detail: version.copyright ?? ""))
        }

        return rows
    }

    private func checklistCard(_ version: AppStoreVersionsModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("READINESS")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ShipyardTheme.body)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            ForEach(checks(for: version)) { row in
                HStack(alignment: .top, spacing: 8) {
                    checkIcon(row.status)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(ShipyardTheme.title)
                        Text(row.detail)
                            .font(.system(size: 11))
                            .foregroundColor(ShipyardTheme.body)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            Button("Open App Info to fix") {
                onOpenAppInfo()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(ShipyardTheme.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(LaunchTheme.page)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(LaunchTheme.border, lineWidth: 1)
        )
    }

    private func checkIcon(_ status: CheckStatus) -> some View {
        switch status {
        case .pass:
            return AnyView(ShipyardIcon(name: "ShipyardCheckSm", size: 12))
        case .warn:
            return AnyView(
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.orange))
        case .fail:
            return AnyView(
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.danger))
        }
    }

    // MARK: - Submit

    private func submitCard(_ version: AppStoreVersionsModel) -> some View {
        let state = version.appStoreState ?? version.appVersionState
        return VStack(alignment: .leading, spacing: 8) {
            Text("SUBMIT")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ShipyardTheme.body)
            if reviewsVM.canSubmitForReview,
               reviewsVM.submissionVersion?.id == version.id {
                Text("Apple checks the version when you submit — missing screenshots or age rating reject it there, not here.")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                HStack {
                    if reviewsVM.submittingReview {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Button("Submit for Review") {
                            showSubmitConfirm = true
                        }
                        .buttonStyle(.launchPrimary)
                    }
                    Spacer(minLength: 0)
                }
            } else if isVersionEditable(appStoreState: state), version.build == nil {
                Text("Attach a build in App Info before submitting.")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
            } else {
                Text("Version is \(getStatusLabel(appStoreState: state).lowercased()) — metadata is locked while Apple has it.")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
            }
        }
        .padding(16)
        .background(LaunchTheme.page)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(LaunchTheme.border, lineWidth: 1)
        )
        .confirmationDialog(
            "Submit version \(version.versionString ?? "") (build \(version.build?.version ?? "—")) to App Review? Metadata locks while it's in review.",
            isPresented: $showSubmitConfirm,
            titleVisibility: .visible
        ) {
            Button("Submit for Review") {
                Task {
                    if await reviewsVM.submitForReview(appId: app.id, versionId: version.id) {
                        reviewsVM.load(appId: app.id, force: true)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Manual steps

    private var manualStepsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MANUAL STEPS (NO API)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ShipyardTheme.body)
            manualRow(
                title: "Screenshots & previews",
                detail: "Upload per-device screenshots in App Store Connect.")
            manualRow(
                title: "Age rating questionnaire",
                detail: "Answer it on the version page in App Store Connect.")
            manualRow(
                title: "Agreements & pricing",
                detail: "Paid apps need signed agreements and a price tier.")
        }
        .padding(16)
        .background(LaunchTheme.page)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(LaunchTheme.border, lineWidth: 1)
        )
    }

    private func manualRow(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.up.right.circle")
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
            }
            Spacer(minLength: 0)
            Button("Open") {
                if let url = URL(string: "https://appstoreconnect.apple.com/apps/\(app.id)") {
                    openURL(url)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(ShipyardTheme.accent)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Shared bits

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No App Store version yet")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            Text("Create one in App Info, then come back to check readiness and submit.")
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
            Button("Open App Info") {
                onOpenAppInfo()
            }
            .buttonStyle(.launchSecondary)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func errorBanner(_ message: String, onDismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppTheme.negative)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.negative)
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(LaunchTheme.page)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(LaunchTheme.border, lineWidth: 1)
        )
    }
}
