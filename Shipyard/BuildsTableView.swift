//
//  BuildsTableView.swift
//  App Store
//
//  Builds table from the builds-list-light Figma frame: toolbar (app builds
//  title + version picker, Filter Status, refresh) over a Build / Version /
//  Uploaded / Processing State / Expiration / Actions table. Manage opens
//  the build-detail bridge sheet (owned by the shell).
//

import SwiftUI

struct BuildsTableView: View {
    @ObservedObject var sidebarVM: SideBarViewModel
    @ObservedObject var detailVM: DetailViewModel
    /// Opens the Figma build-detail screen for the tapped build.
    var onManage: (BuildsModel) -> Void
    /// Returns to the apps table.
    var onBack: () -> Void

    @State private var statusFilter: String?

    private var builds: [BuildsModel] { detailVM.arrBuilds }

    private var visibleBuilds: [BuildsModel] {
        guard let statusFilter else { return builds }
        return builds.filter { $0.processingState == statusFilter }
    }

    private var statuses: [String] {
        Array(Set(builds.compactMap(\.processingState))).sorted()
    }

    private var selectedApp: AppsData? {
        detailVM.selectedApp ?? sidebarVM.selectedApp
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            table
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShipyardTheme.tableBackground)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Apps")
                        .font(.system(size: 12))
                }
                .foregroundColor(ShipyardTheme.body)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to apps")

            HStack(spacing: 8) {
                Text("\(selectedApp?.name ?? "Builds") Builds")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                    .lineLimit(1)
                Menu {
                    ForEach(detailVM.arrVersions, id: \.id) { version in
                        Button("v\(version.version ?? "")") {
                            detailVM.setSelectedVersionAndGetBuilds(selectedVersion: version)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("v\(detailVM.selectedVersion?.version ?? "")")
                            .font(.system(size: 11))
                            .foregroundColor(ShipyardTheme.body)
                        ShipyardIcon(name: "ShipyardChevron", size: 10)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(6)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Select version")
            }

            Spacer()

            Menu {
                Button("All") { statusFilter = nil }
                ForEach(statuses, id: \.self) { status in
                    Button(buildStateDisplayName(status)) {
                        statusFilter = status
                    }
                }
            } label: {
                ShipyardMenuLabel(text: statusFilter.map { "Status: \(buildStateDisplayName($0))" } ?? "Filter Status")
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Filter by processing state")

            Button {
                detailVM.retryBuilds()
            } label: {
                ShipyardIcon(name: "ShipyardRefresh", size: 12)
                    .padding(6)
                    .background(LaunchTheme.field)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(LaunchTheme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh builds")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(LaunchTheme.page)
    }

    // MARK: - Table

    @ViewBuilder
    private var table: some View {
        if selectedApp == nil {
            VStack(spacing: 12) {
                Spacer()
                Text("No App Selected")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                Text("Pick an app from Apps to see its builds")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.body)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if detailVM.arrVersions.isEmpty {
            // Versions haven't produced rows: mirror the versions state
            // instead of spinning on an idle builds list.
            switch detailVM.versionsState {
            case .idle, .loading:
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text("Loading versions…")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.body)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                VStack(spacing: 12) {
                    Spacer()
                    Text("No Versions")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    Text("This app has no pre-release versions")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.body)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let message):
                ErrorRetryView(
                    title: "Couldn't Load Versions",
                    message: message,
                    retryTitle: "Retry",
                    onRetry: { detailVM.retryVersions() }
                )
            default:
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text("Loading builds…")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.body)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            switch detailVM.buildsState {
            case .idle, .loading:
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text("Loading builds…")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.body)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let message):
                ErrorRetryView(
                    title: "Couldn't Load Builds",
                    message: message,
                    retryTitle: "Retry",
                    onRetry: { detailVM.retryBuilds() }
                )
            default:
                if visibleBuilds.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Text("No Builds")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ShipyardTheme.title)
                        Text(statusFilter == nil
                             ? "This version has no builds yet"
                             : "No builds match the current filter")
                            .font(.system(size: 13))
                            .foregroundColor(ShipyardTheme.body)
                        if statusFilter != nil {
                            Button("Clear Filter") {
                                statusFilter = nil
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            headerRow
                            ForEach(visibleBuilds, id: \.id) { build in
                                buildRow(build)
                                ShipyardTheme.rowDivider.frame(height: 1)
                            }
                            paginationFooter
                        }
                    }
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Text("Build").frame(width: 80, alignment: .leading)
            Text("Version").frame(width: 80, alignment: .leading)
            Text("Uploaded").frame(width: 180, alignment: .leading)
            Text("Processing State").frame(width: 240, alignment: .leading)
            Text("Expiration").frame(width: 120, alignment: .leading)
            Text("Actions").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(ShipyardTheme.body)
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(ShipyardTheme.tableHeader)
    }

    private func buildRow(_ build: BuildsModel) -> some View {
        HStack(spacing: 12) {
            Text("#\(build.version ?? "")")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(ShipyardTheme.title)
                .frame(width: 80, alignment: .leading)

            Text(build.preReleaseVersion?.version ?? "—")
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
                .frame(width: 80, alignment: .leading)

            Text(buildUploadedDisplay(build.uploadedDate))
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
                .frame(width: 180, alignment: .leading)

            buildStateCell(build)
                .frame(width: 240, alignment: .leading)

            Text(buildExpirationDisplay(build))
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
                .frame(width: 120, alignment: .leading)

            HStack {
                Text("Manage")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.title)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(LaunchTheme.field)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(LaunchTheme.border, lineWidth: 1)
                    )
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .contentShape(Rectangle())
        .onTapGesture {
            onManage(build)
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onManage(build)
        }
        .accessibilityLabel("Build \(build.version ?? ""), \(buildStateDisplayName(build.processingState ?? ""))")
    }

    @ViewBuilder
    private func buildStateCell(_ build: BuildsModel) -> some View {
        let state = build.processingState ?? ""
        if state == "PROCESSING" {
            HStack(spacing: 6) {
                ShipyardIcon(name: "ShipyardBuildX")
                Text("Processing…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ShipyardTheme.accent)
            }
        } else if state == "VALID" {
            HStack(spacing: 6) {
                ShipyardIcon(name: "ShipyardBuildOk")
                Text("Ready to Test")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
            }
        } else if state == "FAILED" || state == "INVALID" {
            HStack(spacing: 6) {
                ShipyardIcon(name: "ShipyardBuildX")
                Text(buildStateDisplayName(state))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ShipyardTheme.danger)
            }
        } else if build.expired == true {
            HStack(spacing: 6) {
                ShipyardIcon(name: "ShipyardAlarm")
                Text("Expired")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
            }
        } else {
            HStack(spacing: 6) {
                Text(buildStateDisplayName(state))
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
            }
        }
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if let nextCursor = detailVM.nextPageCursor,
           let version = detailVM.selectedVersion {
            HStack {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                    .padding(.vertical, 8)
                    .onAppear {
                        detailVM.setSelectedVersionAndGetBuilds(selectedVersion: version, cursor: nextCursor)
                    }
                Spacer()
            }
        }
    }
}

// MARK: - Display helpers

/// Shared with beta group builds (same module).
func buildStateDisplayName(_ state: String) -> String {
    switch state {
    case "PROCESSING": return "Processing"
    case "VALID": return "Ready to Test"
    case "FAILED": return "Failed"
    case "INVALID": return "Invalid"
    case "EXPIRED": return "Expired"
    default: return state
    }
}

private let buildDateParsers: [DateFormatter] = {
    let fractional = DateFormatter()
    fractional.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
    fractional.locale = Locale(identifier: "en_US_POSIX")
    let plain = DateFormatter()
    plain.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
    plain.locale = Locale(identifier: "en_US_POSIX")
    return [fractional, plain]
}()

/// Shared with the build inspector (same module).
func buildUploadDate(_ raw: String?) -> Date? {
    guard let raw, !raw.isEmpty else { return nil }
    if let date = sharedISOFormatter.date(from: raw) { return date }
    for formatter in buildDateParsers {
        if let date = formatter.date(from: raw) { return date }
    }
    return nil
}

/// "Today, 10:24 AM" / "Yesterday, 4:32 PM" / "Sep 22, 2026".
private func buildUploadedDisplay(_ raw: String?) -> String {
    guard let date = buildUploadDate(raw) else { return "—" }
    let time = DateFormatter()
    time.dateFormat = "h:mm a"
    let day = DateFormatter()
    day.dateFormat = "MMM d, yyyy"
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "Today, \(time.string(from: date))" }
    if calendar.isDateInYesterday(date) { return "Yesterday, \(time.string(from: date))" }
    return day.string(from: date)
}

/// TestFlight builds expire 90 days after upload (the API carries no
/// expiration field on builds).
/// Shared with beta group builds (same module).
func buildExpirationDisplay(_ build: BuildsModel) -> String {
    if build.expired == true { return "Expired" }
    guard let uploaded = buildUploadDate(build.uploadedDate),
          let expiry = Calendar.current.date(byAdding: .day, value: 90, to: uploaded) else { return "—" }
    let day = DateFormatter()
    day.dateFormat = "MMM d, yyyy"
    return day.string(from: expiry)
}
