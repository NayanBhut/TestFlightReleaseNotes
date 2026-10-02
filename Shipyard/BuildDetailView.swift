//
//  BuildDetailView.swift
//  App Store
//
//  Build detail from the build-detail-light Figma frame: toolbar (version —
//  build + state pill, App Store Connect, Assign to Group, Expire Build),
//  Release Notes / Compliance / Groups tabs, and the BUILD METADATA
//  inspector. Release-notes editing, compliance, groups and expiry reuse
//  the existing DetailViewModel / BetaViewModel writes. The API exposes no
//  file size or SDK on builds, so the inspector omits those Figma rows.
//

import SwiftUI

struct BuildDetailView: View {
    /// Identity snapshot; live values always re-read from detailVM by id
    /// so saves/expiry refresh the screen.
    let build: BuildsModel
    @ObservedObject var detailVM: DetailViewModel
    @ObservedObject var betaVM: BetaViewModel
    var app: AppsData?
    /// Returns to the builds table. The Figma toolbar carries no back
    /// control, but the pushed screen needs a way out.
    var onBack: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var tab: DetailTab = .notes
    @State private var showExpireConfirm = false
    @State private var pendingAssignGroup: BetaGroupModel?

    enum DetailTab: String, CaseIterable {
        case notes = "Release Notes"
        case compliance = "Compliance"
        case groups = "Groups"
    }

    private var liveBuild: BuildsModel {
        detailVM.arrBuilds.first(where: { $0.id == build.id }) ?? build
    }

    private var buildId: String { build.id }
    private var versionString: String {
        liveBuild.preReleaseVersion?.version ?? detailVM.selectedVersion?.version ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                main
                inspector
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShipyardTheme.tableBackground)
        .onAppear {
            if let app {
                Task { await betaVM.fetchBetaGroups(app: app) }
            }
            if case .idle = detailVM.exportComplianceState {
                detailVM.retryExportCompliance()
            }
        }
        .confirmationDialog(
            "Expire this build? Testers lose access immediately.",
            isPresented: $showExpireConfirm,
            titleVisibility: .visible
        ) {
            Button("Expire Build", role: .destructive) {
                detailVM.expireBuild(buildId: buildId)
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Assign Build \(liveBuild.version ?? "") to “\(pendingAssignGroup?.name ?? "this group")”? External groups may trigger Apple review.",
            isPresented: Binding(
                get: { pendingAssignGroup != nil },
                set: { if !$0 { pendingAssignGroup = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Assign Build") {
                if let group = pendingAssignGroup {
                    betaVM.selectGroup(group)
                    Task {
                        await betaVM.assignBuildToGroup(build: liveBuild)
                    }
                }
                pendingAssignGroup = nil
            }
            Button("Cancel", role: .cancel) {
                pendingAssignGroup = nil
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Builds")
                        .font(.system(size: 12))
                }
                .foregroundColor(ShipyardTheme.body)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to builds")

            HStack(spacing: 8) {
                Text("Version \(versionString.isEmpty ? "—" : versionString) — Build \(liveBuild.version ?? "")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                    .lineLimit(1)
                statePill
            }

            Spacer()

            Button {
                if let url = URL(string: "https://appstoreconnect.apple.com/apps") {
                    openURL(url)
                }
            } label: {
                HStack(spacing: 6) {
                    ShipyardIcon(name: "ShipyardArrowUpRight", size: 12)
                    Text("App Store Connect")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(ShipyardTheme.accent)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open App Store Connect")

            Menu {
                ForEach(betaVM.groups, id: \.id) { group in
                    Button(group.name ?? "Unnamed group") {
                        pendingAssignGroup = group
                    }
                }
            } label: {
                Text("Assign to Group")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.title)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(LaunchTheme.field)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(LaunchTheme.border, lineWidth: 1)
                    )
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Assign build to a beta group")

            Button("Expire Build") {
                showExpireConfirm = true
            }
            .font(.system(size: 11))
            .foregroundColor(ShipyardTheme.danger)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(LaunchTheme.field)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(LaunchTheme.border, lineWidth: 1)
            )
            .buttonStyle(.plain)
            .disabled(liveBuild.expired == true || detailVM.expireTogglingBuildId == buildId)
            .accessibilityLabel("Expire this build")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(LaunchTheme.page)
    }

    private var statePill: some View {
        let state = liveBuild.processingState ?? ""
        return Text(state.isEmpty ? "—" : state)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(state == "VALID" ? ShipyardTheme.accent : ShipyardTheme.body)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(state == "VALID" ? ShipyardTheme.accent.opacity(0.12) : Color.gray.opacity(0.12))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(state == "VALID" ? ShipyardTheme.accent.opacity(0.5) : Color.clear, lineWidth: 0.5)
            )
    }

    // MARK: - Main

    private var main: some View {
        VStack(alignment: .leading, spacing: 20) {
            Picker("", selection: $tab) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            .accessibilityLabel("Build sections")

            switch tab {
            case .notes:
                // Figma testflight-notes screen: locale browser + editor.
                ReleaseNotesView(detailVM: detailVM, buildId: buildId)
            case .compliance:
                complianceTab
            case .groups:
                BetaGroupsView(betaVM: betaVM, app: app, build: liveBuild)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Compliance tab

    @ViewBuilder
    private var complianceTab: some View {
        switch detailVM.exportComplianceState {
        case .idle, .loading:
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.top, 40)
        case .error(let message):
            ErrorRetryView(
                title: "Couldn't Load Compliance",
                message: message,
                retryTitle: "Retry",
                onRetry: { detailVM.retryExportCompliance() }
            )
        default:
            if let declaration = detailVM.exportComplianceState.loadedValue?.first {
                VStack(alignment: .leading, spacing: 12) {
                    complianceRow("Uses Encryption", declaration.usesEncryption.map { $0 ? "Yes" : "No" } ?? "—")
                    complianceRow("Exempt", declaration.exempt.map { $0 ? "Yes" : "No" } ?? "—")
                    complianceRow("Proprietary Cryptography", declaration.containsProprietaryCryptography.map { $0 ? "Yes" : "No" } ?? "—")
                    complianceRow("Third-Party Cryptography", declaration.containsThirdPartyCryptography.map { $0 ? "Yes" : "No" } ?? "—")
                    complianceRow("French Store", declaration.availableOnFrenchStore.map { $0 ? "Yes" : "No" } ?? "—")
                    complianceRow("State", declaration.appEncryptionDeclarationState ?? "—")
                }
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Text("No Compliance Declaration")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    Text("This app has no export compliance declaration")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.body)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func complianceRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
                .frame(width: 220, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Inspector

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("BUILD METADATA")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ShipyardTheme.body)

            VStack(alignment: .leading, spacing: 12) {
                inspectorRow(label: "UPLOADED", value: buildUploadedDateTime(liveBuild.uploadedDate), mono: false)
                inspectorRow(label: "BUILD ID", value: liveBuild.id, mono: true)
                inspectorRow(label: "EXPIRATION", value: buildExpirationLong(liveBuild), mono: false)
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
            Text(value)
                .font(mono ? .system(size: 11, design: .monospaced) : .system(size: 12))
                .foregroundColor(ShipyardTheme.title)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Display helpers

/// "Sep 29, 2026 at 4:32 PM"; unparseable values pass through untouched.
private func buildUploadedDateTime(_ raw: String?) -> String {
    guard let date = buildUploadDate(raw) else { return "—" }
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
    return formatter.string(from: date)
}

/// "Dec 28, 2026 (90 days)"; expired builds read "Expired".
private func buildExpirationLong(_ build: BuildsModel) -> String {
    if build.expired == true { return "Expired" }
    guard let uploaded = buildUploadDate(build.uploadedDate),
          let expiry = Calendar.current.date(byAdding: .day, value: 90, to: uploaded) else { return "—" }
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, yyyy"
    return "\(formatter.string(from: expiry)) (90 days)"
}
