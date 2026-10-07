//
//  BetaGroupsView.swift
//  App Store
//
//  Beta groups from the beta-groups-light Figma frame: groups column
//  (kind icon + name + tester count) beside the group detail (title +
//  kind pill, tester/auto-notify stats, Testers/Builds/Settings tabs).
//  All reads and writes go through BetaViewModel. Tester invite status is
//  inferred from inviteType and activity is not exposed by the API, so
//  those cells are marked accordingly instead of fabricated.
//

import SwiftUI

struct BetaGroupsView: View {
    @ObservedObject var betaVM: BetaViewModel
    var app: AppsData?
    /// Build in context (assign-to-group target, auto-notify subject).
    var build: BuildsModel
    @EnvironmentObject private var toastCenter: ShipyardToastCenter

    @State private var tab: GroupTab = .testers
    @State private var showInviteSheet = false
    @State private var removingTester: BetaTesterModel?
    @State private var deletingTester: BetaTesterModel?
    @State private var showDeleteGroupConfirm = false
    @State private var showAssignConfirm = false

    enum GroupTab: String, CaseIterable {
        case testers = "Testers"
        case builds = "Builds"
        case settings = "Settings"
    }

    private var selectedGroup: BetaGroupModel? {
        betaVM.selectedGroup
            ?? betaVM.groups.first(where: { $0.id == betaVM.selectedGroup?.id })
    }

    var body: some View {
        HStack(spacing: 0) {
            groupsColumn
                .frame(width: 280)

            ShipyardTheme.rowDivider
                .frame(width: 1)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShipyardTheme.tableBackground)
        .onAppear {
            Task { await refreshIfStale() }
        }
        .onChange(of: betaVM.groups) { _, groups in
            if betaVM.selectedGroup == nil, let first = groups.first {
                betaVM.selectGroup(first)
                Task { await betaVM.loadAllTesters(groupId: first.id) }
            }
        }
        .confirmationDialog(
            "Remove \(removingTester?.displayName ?? "this tester") from this group?",
            isPresented: Binding(
                get: { removingTester != nil },
                set: { if !$0 { removingTester = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let tester = removingTester {
                    Task { await runTesterRemoval(tester) }
                }
                removingTester = nil
            }
            Button("Cancel", role: .cancel) { removingTester = nil }
        }
        .confirmationDialog(
            "Delete \(deletingTester?.displayName ?? "this tester") from the team? They lose access to all TestFlight groups.",
            isPresented: Binding(
                get: { deletingTester != nil },
                set: { if !$0 { deletingTester = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete from Team", role: .destructive) {
                if let tester = deletingTester {
                    Task { await runTesterDelete(tester) }
                }
                deletingTester = nil
            }
            Button("Cancel", role: .cancel) { deletingTester = nil }
        }
        .confirmationDialog(
            "Delete this beta group? Its testers lose access to its builds.",
            isPresented: $showDeleteGroupConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Group", role: .destructive) {
                if let group = selectedGroup {
                    Task { await runGroupDelete(group) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func refreshIfStale() async {
        guard let app else { return }
        if betaVM.isGroupsLoaded, betaVM.currentAppId == app.id { return }
        await betaVM.fetchBetaGroups(app: app)
    }

    private func runTesterRemoval(_ tester: BetaTesterModel) async {
        betaVM.clearError()
        await betaVM.removeTesterFromGroup(tester)
        if betaVM.hasError, let message = betaVM.errorMessage {
            toastCenter.show("Couldn't remove tester", detail: message, variant: .error)
        } else {
            toastCenter.show("Tester removed from group", detail: tester.displayName, variant: .success)
        }
    }

    private func runTesterDelete(_ tester: BetaTesterModel) async {
        betaVM.clearError()
        await betaVM.deleteTester(tester)
        if betaVM.hasError, let message = betaVM.errorMessage {
            toastCenter.show("Couldn't delete tester", detail: message, variant: .error)
        } else {
            toastCenter.show("Tester deleted", detail: tester.displayName, variant: .success)
        }
    }

    private func runGroupDelete(_ group: BetaGroupModel) async {
        betaVM.clearError()
        await betaVM.deleteGroup(group)
        if betaVM.hasError, let message = betaVM.errorMessage {
            toastCenter.show("Couldn't delete beta group", detail: message, variant: .error)
        } else {
            toastCenter.show("Beta group deleted", detail: group.name, variant: .success)
        }
    }

    private func runAssignBuild(to group: BetaGroupModel) async {
        betaVM.clearError()
        await betaVM.assignBuildToGroup(build: build)
        if let message = betaVM.errorMessage, betaVM.hasError {
            let assigned = message.localizedCaseInsensitiveContains("assigned")
            toastCenter.show(
                assigned ? "Build assigned" : "Couldn't assign build",
                detail: message,
                variant: assigned ? .success : .error)
        } else {
            toastCenter.show("Build assigned", detail: group.name, variant: .success)
        }
    }

    private func runAutoNotify(buildId: String, enabled: Bool) async {
        betaVM.clearError()
        await betaVM.setAutoNotify(buildId: buildId, enabled: enabled)
        if betaVM.hasError, let message = betaVM.errorMessage {
            toastCenter.show("Couldn't update auto-notify", detail: message, variant: .error)
        } else {
            toastCenter.show(enabled ? "Auto-notify enabled" : "Auto-notify disabled", variant: .success)
        }
    }

    // MARK: - Groups column

    private var groupsColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("BETA GROUPS")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(ShipyardTheme.body)
                .padding(.horizontal, 10)
                .padding(.top, 12)

            if betaVM.groups.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .padding(.top, 20)
            } else {
                ForEach(betaVM.groups, id: \.id) { group in
                    groupRow(group)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(ShipyardTheme.sidebarBackground)
    }

    private func groupRow(_ group: BetaGroupModel) -> some View {
        let isSelected = group.id == selectedGroup?.id
        let kind = betaGroupKind(group)
        return Button {
            betaVM.selectGroup(group)
            Task { await betaVM.loadAllTesters(groupId: group.id) }
        } label: {
            HStack(spacing: 8) {
                ShipyardIcon(name: kind.iconName)
                Text(group.name ?? "Unnamed group")
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(ShipyardTheme.title)
                    .lineLimit(1)
                Spacer()
                Text(testerCountText(group, isSelected: isSelected))
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? ShipyardTheme.selectedRow : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .accessibilityLabel("\(group.name ?? "group"), \(testerCountText(group, isSelected: isSelected)) testers")
    }

    private func testerCountText(_ group: BetaGroupModel, isSelected: Bool) -> String {
        if isSelected { return "\(betaVM.testers.count)" }
        if !group.betaTesters.isEmpty { return "\(group.betaTesters.count)" }
        return "–"
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let group = selectedGroup {
            VStack(alignment: .leading, spacing: 20) {
                detailHeader(group)

                Picker("", selection: $tab) {
                    ForEach(GroupTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                .accessibilityLabel("Group sections")

                switch tab {
                case .testers:
                    testersTab(group)
                case .builds:
                    buildsTab(group)
                case .settings:
                    settingsTab(group)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        } else {
            VStack(spacing: 12) {
                Spacer()
                Text("No Beta Groups")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                Text("Create a group in App Store Connect to manage testers")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.body)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func detailHeader(_ group: BetaGroupModel) -> some View {
        let kind = betaGroupKind(group)
        // Pending-aware, not raw: betaDetails[..] flickers back to Off
        // while a toggle's re-fetch is in flight (BUG_SWEEP #14b).
        let autoNotify = betaVM.autoNotifyState(for: build.id)
        return HStack(spacing: 12) {
            Text(group.name ?? "Unnamed group")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            Text(kind.pillText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(ShipyardTheme.body)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(ShipyardTheme.tableHeader)
                .cornerRadius(10)

            Spacer()

            Text("\(betaVM.testers.count) Testers Assigned")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
            Text(autoNotify ? "Auto-Notify: On" : "Auto-Notify: Off")
                .font(.system(size: 13))
                .foregroundColor(autoNotify ? ShipyardTheme.success : ShipyardTheme.body)
        }
        .onAppear {
            Task { await betaVM.fetchBuildBetaDetail(buildId: build.id) }
        }
    }

    // MARK: - Testers tab

    private func testersTab(_ group: BetaGroupModel) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Spacer()
                if betaVM.hasError, let message = betaVM.errorMessage {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.negative)
                        .lineLimit(2)
                }
                Button("Add Testers") {
                    betaVM.clearError()
                    showInviteSheet = true
                }
                .buttonStyle(.launchPrimary)
            }
            .padding(.bottom, 12)
            .sheet(isPresented: $showInviteSheet) {
                InviteTesterSheet(betaVM: betaVM) {
                    showInviteSheet = false
                }
            }

            headerRow([("Name", 180), ("Email", 220), ("Status", 120), ("Last Activity", nil)])

            if let truncation = betaVM.testersTruncationMessage {
                // Cursor drain in flight (or capped): say what's on screen.
                Text(truncation)
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }

            if betaVM.testers.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No Testers")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    Text("Invite testers by email to fill this group")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(betaVM.testers, id: \.id) { tester in
                            testerRow(tester)
                            ShipyardTheme.rowDivider.frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private func testerRow(_ tester: BetaTesterModel) -> some View {
        let status = testerStatus(tester)
        return HStack(spacing: 12) {
            Text(tester.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
                .lineLimit(1)
                .frame(width: 180, alignment: .leading)

            Text(tester.email ?? "—")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(ShipyardTheme.body)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 220, alignment: .leading)

            HStack(spacing: 6) {
                Circle()
                    .fill(status.color)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(status.text)
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
            }
            .frame(width: 120, alignment: .leading)

            Text("—")
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Remove from Group") {
                removingTester = tester
            }
            Button("Delete from Team", role: .destructive) {
                deletingTester = tester
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tester.displayName), \(status.text)")
    }

    // MARK: - Builds tab

    private func buildsTab(_ group: BetaGroupModel) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(group.builds.contains(where: { $0.id == build.id }) ? "Assigned ✓" : "Assign This Build") {
                    showAssignConfirm = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(group.builds.contains(where: { $0.id == build.id })
                    || betaVM.updatingBuildId == build.id)
            }
            .padding(.bottom, 12)
            .confirmationDialog(
                "Assign Build \(build.version ?? "") to “\(group.name ?? "this group")”? External groups may trigger Apple review.",
                isPresented: $showAssignConfirm,
                titleVisibility: .visible
            ) {
                Button("Assign Build") {
                    betaVM.selectGroup(group)
                    Task {
                        await runAssignBuild(to: group)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }

            headerRow([("Build", 100), ("Version", 100), ("State", 200), ("Expires", nil)])

            if group.builds.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No Builds Assigned")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(group.builds, id: \.id) { assigned in
                            HStack(spacing: 12) {
                                Text("#\(assigned.version ?? "")")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(ShipyardTheme.title)
                                    .frame(width: 100, alignment: .leading)
                                Text(assigned.preReleaseVersion?.version ?? "—")
                                    .font(.system(size: 12))
                                    .foregroundColor(ShipyardTheme.body)
                                    .frame(width: 100, alignment: .leading)
                                Text(buildStateDisplayName(assigned.processingState ?? ""))
                                    .font(.system(size: 12))
                                    .foregroundColor(ShipyardTheme.title)
                                    .frame(width: 200, alignment: .leading)
                                Text(buildExpirationDisplay(assigned))
                                    .font(.system(size: 12))
                                    .foregroundColor(ShipyardTheme.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 34)
                            ShipyardTheme.rowDivider.frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Settings tab

    private func settingsTab(_ group: BetaGroupModel) -> some View {
        // Same pending-aware source as detailHeader — the raw value flips
        // back to Off while the toggle's re-fetch is in flight (BUG_SWEEP #14b).
        let autoNotify = betaVM.autoNotifyState(for: build.id)
        return VStack(alignment: .leading, spacing: 16) {
            Toggle("Auto-notify testers for Build \(build.version ?? "")", isOn: Binding(
                get: { autoNotify },
                set: { enabled in
                    Task {
                        await runAutoNotify(buildId: build.id, enabled: enabled)
                    }
                }
            ))
            .font(.system(size: 13))

            Divider()

            settingsRow("Group Type", betaGroupKind(group).pillText.capitalized)
            settingsRow("Testers", "\(betaVM.testers.count)")
            settingsRow("Public Link", group.publicLinkEnabled == true ? "Enabled" : "Off")
            settingsRow("All Builds", group.hasAccessToAllBuilds == true ? "Yes" : "No")

            Divider()

            Button("Delete Group", role: .destructive) {
                showDeleteGroupConfirm = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer(minLength: 0)
        }
    }

    private func settingsRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
                .frame(width: 160, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Shared

    /// Fixed-width header band; a nil width means flex.
    private func headerRow(_ columns: [(String, CGFloat?)]) -> some View {
        HStack(spacing: 12) {
            ForEach(columns.indices, id: \.self) { index in
                let (title, width) = columns[index]
                if let width {
                    Text(title)
                        .frame(width: width, alignment: .leading)
                } else {
                    Text(title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(ShipyardTheme.body)
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(ShipyardTheme.tableHeader)
    }
}

// MARK: - Display helpers

private struct BetaGroupKind {
    let iconName: String
    let pillText: String
}

private func betaGroupKind(_ group: BetaGroupModel) -> BetaGroupKind {
    if group.isInternalGroup == true {
        return BetaGroupKind(iconName: "ShipyardUsers", pillText: "INTERNAL")
    }
    if group.publicLinkEnabled == true {
        return BetaGroupKind(iconName: "ShipyardLink", pillText: "PUBLIC")
    }
    return BetaGroupKind(iconName: "ShipyardGlobe", pillText: "EXTERNAL")
}

private struct TesterStatus {
    let color: Color
    let text: String
}

/// inviteType is the only per-tester signal the API exposes — EMAIL means
/// the tester was invited by email and hasn't necessarily accepted, so it
/// reads as Invited; anything else (or nothing) reads as Active.
private func testerStatus(_ tester: BetaTesterModel) -> TesterStatus {
    if tester.inviteType?.uppercased() == "EMAIL" {
        return TesterStatus(color: ShipyardTheme.warning, text: "Invited")
    }
    return TesterStatus(color: ShipyardTheme.success, text: "Active")
}
