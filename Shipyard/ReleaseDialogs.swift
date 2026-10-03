//
//  ReleaseDialogs.swift
//  App Store
//
//  Figma confirmation dialogs for the release flow: 04 Submit for Review,
//  08 Release This Version, C1 Remove from Review, plus the New Version
//  sheet (N1/N2 entry → 01 draft). Presented via .sheet like the other
//  Figma modals; Cancel always returns to the origin screen.
//

import SwiftUI

// MARK: - 04 Submit for Review

/// "Submit version X for review?" with the submission summary and the
/// Waiting-for-Review expectation. Confirm runs the submit pipeline.
struct SubmitReviewDialog: View {
    var appId: String
    var appName: String
    var version: AppStoreVersionsModel
    var phasedState: String?
    @ObservedObject var reviewsVM: ReviewsViewModel
    var onSubmitted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var submitting = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Submit version \(version.versionString ?? "") for review?")
                    .font(.system(size: 18))
                    .foregroundColor(ShipyardTheme.title)
                Text("Confirm the information you’re sending to App Review.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
            }
            ReleaseSummaryCard(rows: [
                (label: "App", value: appName),
                (label: "Version", value: version.versionString ?? "—"),
                (label: "Build", value: "#\(version.build?.version ?? "—")"),
                (label: "Release type", value: humanizedReleaseType(version.releaseType)),
                (label: "Phased release", value: phasedReleaseDisplay(state: phasedState)),
            ])
            ReleaseAlert(
                style: .info,
                title: "After submission",
                detail: "The version moves to Waiting for Review. Estimated review: 24–48 hours.")
            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.danger)
            }
            HStack {
                Spacer(minLength: 0)
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.launchSecondary)
                Button {
                    Task {
                        submitting = true
                        error = nil
                        defer { submitting = false }
                        if await reviewsVM.submitForReview(appId: appId, versionId: version.id) {
                            onSubmitted()
                            dismiss()
                        } else {
                            error = reviewsVM.writeError ?? "Submission failed. Try again."
                        }
                    }
                } label: {
                    if submitting {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(minWidth: 110)
                    } else {
                        Text("Submit for Review")
                            .frame(minWidth: 110)
                    }
                }
                .buttonStyle(.launchPrimary)
                .disabled(submitting)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(LaunchTheme.page)
    }
}

// MARK: - 08 Release This Version

/// "Release version X?" for the manual-release branch. Confirm sends
/// the release request → 09 Ready for Distribution.
struct ReleaseVersionDialog: View {
    var appName: String
    var version: AppStoreVersionsModel
    var phasedState: String?
    @ObservedObject var reviewsVM: ReviewsViewModel
    var onReleased: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var releasing = false
    @State private var error: String?

    private var phasedInfo: (title: String, detail: String) {
        if (phasedState ?? "").uppercased() == "ACTIVE" {
            return ("Phased release will start",
                    "Automatic updates begin at 1% of users and increase over 7 days. Availability may take up to 24 hours.")
        }
        return ("Version will release",
                "The approved update becomes available on the App Store. Availability may take up to 24 hours.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Release version \(version.versionString ?? "")?")
                    .font(.system(size: 18))
                    .foregroundColor(ShipyardTheme.title)
                Text("Your approved update will become available on the App Store.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
            }
            ReleaseSummaryCard(rows: [
                (label: "App", value: appName),
                (label: "Version", value: version.versionString ?? "—"),
                (label: "Build", value: "#\(version.build?.version ?? "—")"),
                (label: "Release type", value: humanizedReleaseType(version.releaseType)),
                (label: "Phased release", value: phasedReleaseDisplay(state: phasedState)),
            ])
            ReleaseAlert(style: .info, title: phasedInfo.title, detail: phasedInfo.detail)
            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.danger)
            }
            HStack {
                Spacer(minLength: 0)
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.launchSecondary)
                Button {
                    Task {
                        releasing = true
                        error = nil
                        defer { releasing = false }
                        if await reviewsVM.releaseVersion(versionId: version.id) {
                            onReleased()
                            dismiss()
                        } else {
                            error = reviewsVM.releaseSettingsError ?? "Release failed. Try again."
                        }
                    }
                } label: {
                    if releasing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(minWidth: 130)
                    } else {
                        Text("Release This Version")
                            .frame(minWidth: 130)
                    }
                }
                .buttonStyle(.launchPrimary)
                .disabled(releasing)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(LaunchTheme.page)
    }
}

// MARK: - C1 Remove from Review

/// "Remove from review?" — the submission is cancelled and the version
/// returns to Prepare (C2) with everything retained.
struct CancelSubmissionDialog: View {
    var appName: String
    var version: AppStoreVersionsModel
    var phasedState: String?
    var submission: ReviewSubmissionModel?
    @ObservedObject var reviewsVM: ReviewsViewModel
    var onCancelled: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var cancelling = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Remove from review?")
                    .font(.system(size: 18))
                    .foregroundColor(ShipyardTheme.title)
                Text("The version will move back to Prepare for Submission.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
            }
            ReleaseSummaryCard(rows: [
                (label: "App", value: appName),
                (label: "Version", value: version.versionString ?? "—"),
                (label: "Build", value: "#\(version.build?.version ?? "—")"),
                (label: "Release type", value: humanizedReleaseType(version.releaseType)),
                (label: "Phased release", value: phasedReleaseDisplay(state: phasedState)),
            ])
            Text("The build, release notes, and review contact will be retained. You can edit and submit this version again.")
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.danger)
            }
            HStack {
                Spacer(minLength: 0)
                Button("Keep in Review") {
                    dismiss()
                }
                .buttonStyle(.launchSecondary)
                Button {
                    Task {
                        cancelling = true
                        error = nil
                        defer { cancelling = false }
                        guard let submission else {
                            error = "No active submission was found for this version."
                            return
                        }
                        if await reviewsVM.cancelSubmission(submission) {
                            onCancelled()
                            dismiss()
                        } else {
                            error = reviewsVM.writeError ?? "Cancellation failed. Try again."
                        }
                    }
                } label: {
                    if cancelling {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(minWidth: 130)
                    } else {
                        Text("Remove from Review")
                            .frame(minWidth: 130)
                    }
                }
                .buttonStyle(.launchDestructive)
                .disabled(cancelling)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(LaunchTheme.page)
    }
}

// MARK: - New Version

/// N1/N2 entry → 01 draft: version string, platform, and release type.
/// Copyright is optional and can be set later in the form.
struct NewVersionSheet: View {
    var appId: String
    @ObservedObject var reviewsVM: ReviewsViewModel
    var onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var versionString = ""
    @State private var platform = AppStoreVersionPlatform.iOS
    @State private var releaseType = AppStoreVersionReleaseType.manual
    @State private var creating = false

    private var platforms: [AppStoreVersionPlatform] {
        let creatable = reviewsVM.creatableAppStoreVersionPlatforms
        return creatable.isEmpty ? [.iOS] : creatable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("New Version")
                    .font(.system(size: 18))
                    .foregroundColor(ShipyardTheme.title)
                Text("Creates a Prepare for Submission draft for this app.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Version *")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
                TextField("1.0", text: $versionString)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
            }
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Platform")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.title)
                    Picker("", selection: $platform) {
                        ForEach(platforms, id: \.self) { platform in
                            Text(platform.displayName).tag(platform)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.system(size: 12))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Release")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.title)
                    Picker("", selection: $releaseType) {
                        ForEach(AppStoreVersionReleaseType.allCases, id: \.self) { type in
                            Text(humanizedReleaseType(type.rawValue)).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.system(size: 12))
                }
            }
            if let error = reviewsVM.createVersionError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.danger)
            }
            HStack {
                Spacer(minLength: 0)
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.launchSecondary)
                Button {
                    Task {
                        creating = true
                        defer { creating = false }
                        if await reviewsVM.createVersion(
                            appId: appId,
                            versionString: versionString,
                            platform: platform,
                            copyright: "",
                            releaseType: releaseType) {
                            onCreated()
                            dismiss()
                        }
                    }
                } label: {
                    if creating {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(minWidth: 110)
                    } else {
                        Text("Create Version")
                            .frame(minWidth: 110)
                    }
                }
                .buttonStyle(.launchPrimary)
                .disabled(creating || versionString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(LaunchTheme.page)
        .onAppear {
            if let first = platforms.first {
                platform = first
            }
        }
    }
}
