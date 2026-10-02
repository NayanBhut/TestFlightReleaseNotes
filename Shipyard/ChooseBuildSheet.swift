//
//  ChooseBuildSheet.swift
//  App Store
//
//  Figma 02 — Choose Build · Modal (76:33033): build table with
//  processing / version-mismatch rows rendered as unavailable, a
//  contextual processing alert, and Cancel / Choose Build actions.
//  Selection reuses ReviewsViewModel.selectBuild so the existing
//  attach pipeline (attachSelectedBuild) stays the single writer.
//

import SwiftUI

/// Modal build picker for one pending App Store version. Only VALID,
/// non-expired builds whose marketing version matches are selectable —
/// everything else renders its reason in the Selection column.
struct ChooseBuildSheet: View {
    var version: AppStoreVersionsModel
    var appName: String?
    @ObservedObject var reviewsVM: ReviewsViewModel
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var attaching = false

    private var versionString: String { version.versionString ?? "" }
    private var platform: String { version.platform ?? "" }

    private var candidates: [BuildsModel] {
        reviewsVM.candidateBuildsState.loadedValue ?? []
    }

    private var processingBuild: BuildsModel? {
        candidates.first {
            $0.processingState == "PROCESSING"
                && $0.preReleaseVersion?.version == versionString
        }
    }

    private var availableBuild: BuildsModel? {
        candidates.first {
            ReviewsViewModel.isEligibleBuild(
                $0, versionString: versionString, platform: platform)
        }
    }

    private var selectedBuild: BuildsModel? {
        guard let id = reviewsVM.selectedBuildId else { return nil }
        return candidates.first { $0.id == id }
            ?? reviewsVM.eligibleBuildsState.loadedValue?.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose Build")
                    .font(.system(size: 18))
                    .foregroundColor(ShipyardTheme.title)
                Text("Select a processed build for \(appName ?? "this app") version \(versionString).")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
            }

            buildTable

            if let processing = processingBuild {
                processingAlert(processing)
            }

            Text(selectedFooter)
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)

            HStack {
                Spacer(minLength: 0)
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.launchSecondary)
                Button {
                    Task {
                        attaching = true
                        defer { attaching = false }
                        if await reviewsVM.attachSelectedBuild() {
                            onDone()
                            dismiss()
                        }
                    }
                } label: {
                    if attaching {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(minWidth: 76)
                    } else {
                        Text("Choose Build")
                            .frame(minWidth: 76)
                    }
                }
                .buttonStyle(.launchPrimary)
                .disabled(selectedBuild == nil || attaching)
            }
        }
        .padding(24)
        .frame(width: 680)
        .background(LaunchTheme.page)
        .onAppear {
            reviewsVM.loadCandidateBuilds(for: version)
            if let attached = version.build,
               reviewsVM.selectedBuildId == nil,
               ReviewsViewModel.isEligibleBuild(
                attached, versionString: versionString, platform: platform) {
                reviewsVM.selectBuild(attached)
            }
        }
    }

    // MARK: - Table

    private var buildTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Build ↓")
                    .frame(width: 68, alignment: .leading)
                Text("Version")
                    .frame(width: 68, alignment: .leading)
                Text("Uploaded")
                    .frame(width: 162, alignment: .leading)
                Text("Status")
                    .frame(width: 134, alignment: .leading)
                Text("Selection")
            }
            .font(.system(size: 11))
            .foregroundColor(ShipyardTheme.body)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(ShipyardTheme.tableHeader)

            switch reviewsVM.candidateBuildsState {
            case .loading, .idle:
                HStack {
                    Spacer(minLength: 0)
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 24)
            case .error(let message):
                VStack(spacing: 8) {
                    Text(message.isEmpty ? "Couldn't load builds" : message)
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.title)
                    Button("Retry") {
                        reviewsVM.loadCandidateBuilds(for: version)
                    }
                    .buttonStyle(.launchSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            case .loaded:
                if candidates.isEmpty {
                    Text("No builds uploaded for this platform yet.")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    ForEach(candidates, id: \.id) { build in
                        buildRow(build)
                    }
                }
            case .empty:
                Text("No builds uploaded for this platform yet.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
        }
        .background(ShipyardTheme.tableBackground)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(LaunchTheme.border, lineWidth: 1)
        )
    }

    private func buildRow(_ build: BuildsModel) -> some View {
        let eligible = ReviewsViewModel.isEligibleBuild(
            build, versionString: versionString, platform: platform)
        let selected = reviewsVM.selectedBuildId == build.id
        return HStack(spacing: 12) {
            Text("#\(build.version ?? "")")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(ShipyardTheme.title)
                .frame(width: 68, alignment: .leading)
            Text(build.preReleaseVersion?.version ?? "—")
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.title)
                .frame(width: 68, alignment: .leading)
            Text(candidateUploadedDisplay(build.uploadedDate))
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
                .frame(width: 162, alignment: .leading)
            statusBadge(build)
                .frame(width: 134, alignment: .leading)
            selectionCell(build, eligible: eligible, selected: selected)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(selected ? ShipyardTheme.tableHeader : ShipyardTheme.tableBackground)
        .overlay(
            ShipyardTheme.rowDivider.frame(height: 1),
            alignment: .bottom
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if eligible { reviewsVM.selectBuild(build) }
        }
    }

    private func statusBadge(_ build: BuildsModel) -> some View {
        let state = build.processingState ?? ""
        let dot: Color = state == "PROCESSING"
            ? ShipyardTheme.accent
            : state == "VALID" ? ShipyardTheme.success : ShipyardTheme.danger
        return HStack(spacing: 5) {
            Circle()
                .fill(dot)
                .frame(width: 6, height: 6)
            Text(buildStateDisplayName(state))
                .font(.system(size: 10))
                .foregroundColor(ShipyardTheme.title)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
            state == "PROCESSING"
                ? ShipyardTheme.accent.opacity(0.12)
                : ShipyardTheme.tableHeader
        )
        .cornerRadius(10)
    }

    @ViewBuilder
    private func selectionCell(_ build: BuildsModel, eligible: Bool, selected: Bool) -> some View {
        if selected {
            HStack(spacing: 4) {
                RadioDot(selected: true, color: ShipyardTheme.accent)
                Text("Selected")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.accent)
            }
        } else if build.processingState == "PROCESSING" {
            Text("Unavailable")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.tertiary)
        } else if build.preReleaseVersion?.version != versionString {
            Text("Version mismatch")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.tertiary)
        } else if !eligible {
            Text("Unavailable")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.tertiary)
        }
    }

    // MARK: - Alert + footer

    private func processingAlert(_ processing: BuildsModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Build #\(processing.version ?? "") is still processing")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
            Text(processingAlertDetail(processing))
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(ShipyardTheme.accent.opacity(0.12))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ShipyardTheme.accent, lineWidth: 1)
        )
    }

    private func processingAlertDetail(_ processing: BuildsModel) -> String {
        if let available = availableBuild, available.id != processing.id {
            return "It cannot be selected until processing completes. Build #\(available.version ?? "") is available for this version."
        }
        return "It cannot be selected until processing completes. No eligible build is available yet."
    }

    private var selectedFooter: String {
        guard let selected = selectedBuild else { return "No build selected." }
        return "Selected: \(selected.preReleaseVersion?.version ?? versionString) (#\(selected.version ?? "")) · \(buildStateDisplayName(selected.processingState ?? ""))"
    }

    /// Figma Uploaded column: "Sep 30, 10:24 AM" for this year, "Sep 22, 2026" older.
    private func candidateUploadedDisplay(_ raw: String?) -> String {
        guard let date = buildUploadDate(raw) else { return "—" }
        let calendar = Calendar.current
        let time = DateFormatter()
        time.dateFormat = "h:mm a"
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            let day = DateFormatter()
            day.dateFormat = "MMM d"
            return "\(day.string(from: date)), \(time.string(from: date))"
        }
        let day = DateFormatter()
        day.dateFormat = "MMM d, yyyy"
        return day.string(from: date)
    }
}

/// Radio indicator drawn from primitives (a control affordance, not an
/// icon asset): outer ring with a filled dot when selected.
struct RadioDot: View {
    var selected: Bool
    var color: Color = ShipyardTheme.title

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(selected ? color : ShipyardTheme.tertiary, lineWidth: 1.5)
                .frame(width: 14, height: 14)
                .background(Circle().fill(LaunchTheme.page))
            if selected {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }
        }
    }
}
