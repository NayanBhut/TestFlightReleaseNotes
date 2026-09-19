//
//  BetaGroupView.swift
//  App Store
//
//  Created by Nayan Bhut for Phase 4: TestFlight Groups/Testers.
//

import SwiftUI

struct BetaGroupView: View {
    @ObservedObject var betaViewModel: BetaViewModel
    var selectedApp: AppsData?
    var builds: [BuildsModel] = []
    var selectedVersionString: String = ""

    @State private var showInviteSheet = false
    @State private var inviteEmail = ""
    @State private var inviteFirstName = ""
    @State private var inviteLastName = ""
    @State private var buildIdForActions = ""
    @State private var testerPendingRemoval: BetaTesterModel?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if selectedApp == nil {
                emptyState(icon: "person.3", title: "No App Selected",
                           subtitle: "Select an app from the sidebar to view its TestFlight groups")
            } else if !betaViewModel.isGroupsLoaded && betaViewModel.viewState == .betaGroupsLoading {
                loadingState(text: "Loading beta groups...")
            } else if betaViewModel.groups.isEmpty {
                emptyState(icon: "person.3", title: "No Beta Groups",
                           subtitle: "This app has no TestFlight groups yet")
            } else {
                HSplitView {
                    groupsList
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                    groupDetail
                        .frame(minWidth: 320, maxWidth: .infinity)
                }
            }
        }
        .alert("TestFlight", isPresented: $betaViewModel.hasError) {
            Button("OK") { betaViewModel.clearError() }
        } message: {
            Text(betaViewModel.errorMessage ?? "Something went wrong.")
        }
        .sheet(isPresented: $showInviteSheet) {
            inviteSheet
        }
        .onChange(of: selectedApp?.id) { _, _ in
            refreshGroupsIfStale()
        }
        .onAppear {
            refreshGroupsIfStale()
        }
        .confirmationDialog(
            "Remove \(testerPendingRemoval?.displayName ?? "this tester") from this group?",
            isPresented: Binding(
                get: { testerPendingRemoval != nil },
                set: { if !$0 { testerPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let tester = testerPendingRemoval {
                    betaViewModel.removeTesterFromGroup(tester)
                }
                testerPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { testerPendingRemoval = nil }
        }
    }

    /// Staleness lives in the view model so switching tabs (which destroys
    /// this view's @State) doesn't cause a redundant refetch on return.
    private func refreshGroupsIfStale(force: Bool = false) {
        guard let app = selectedApp else { return }
        if !force {
            if betaViewModel.viewState == .betaGroupsLoading { return }
            if betaViewModel.isGroupsLoaded, betaViewModel.currentAppId == app.id { return }
        }
        betaViewModel.fetchBetaGroups(app: app)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Beta Groups")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            if !betaViewModel.groups.isEmpty {
                Text("\(betaViewModel.groups.count) groups")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let truncation = betaViewModel.groupsTruncationMessage {
                Text(truncation)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Button(action: { refreshGroupsIfStale(force: true) }) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .disabled(selectedApp == nil || betaViewModel.viewState == .betaGroupsLoading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Groups List

    private var groupsList: some View {
        List(betaViewModel.groups, id: \.id) { group in
            // Row highlighting derives from the view model's selection —
            // no duplicated isSelected flag on the decoded model.
            let isSelected = betaViewModel.selectedGroup?.id == group.id
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name ?? "Unnamed group")
                        .font(.headline)
                    HStack(spacing: 6) {
                        Text(group.isInternalGroup == true ? "Internal" : "External")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((group.isInternalGroup == true ? Color.blue : Color.green).opacity(0.15))
                            .foregroundColor(group.isInternalGroup == true ? .blue : .green)
                            .cornerRadius(4)
                        if group.publicLinkEnabled == true {
                            Text("Public link")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Text("\(group.betaTesters.count) testers • \(group.builds.count) builds")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear))
            .contentShape(Rectangle())
            .onTapGesture { betaViewModel.selectGroup(group) }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Group Detail

    @ViewBuilder
    private var groupDetail: some View {
        if let group = betaViewModel.selectedGroup {
            VStack(alignment: .leading, spacing: 0) {
                // Group title
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name ?? "Unnamed group")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(groupDetailSubtitle(group))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                Divider()

                TabView {
                    testersSection
                        .tabItem { Label("Testers", systemImage: "person.2") }
                    buildsSection(group: group)
                        .tabItem { Label("Builds & Review", systemImage: "paperplane") }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        } else {
            emptyState(icon: "person.2", title: "No Group Selected",
                       subtitle: "Select a group on the left to view its testers and builds")
        }
    }

    private func groupDetailSubtitle(_ group: BetaGroupModel) -> String {
        var parts: [String] = []
        parts.append(group.isInternalGroup == true ? "Internal group" : "External group")
        if group.hasAccessToAllBuilds == true { parts.append("all builds") }
        if group.autoNotifyEnabled == true { parts.append("auto-notify on") }
        return parts.joined(separator: " • ")
    }

    // MARK: - Testers

    private var testersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Testers")
                    .font(.headline)
                Spacer()
                if betaViewModel.viewState == .betaTestersLoading {
                    ProgressView().scaleEffect(0.7)
                }
                Button(action: {
                    inviteEmail = ""
                    inviteFirstName = ""
                    inviteLastName = ""
                    showInviteSheet = true
                }) {
                    Label("Invite tester", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .disabled(betaViewModel.selectedGroup == nil)
            }

            searchBar

            searchResultView

            if let truncation = betaViewModel.testersTruncationMessage {
                Text(truncation)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !betaViewModel.isTestersLoaded && betaViewModel.viewState == .betaTestersLoading {
                loadingState(text: "Loading testers...")
            } else if betaViewModel.testers.isEmpty {
                Text("No testers in this group yet. Invite one to get started.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                List(betaViewModel.testers, id: \.id) { tester in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tester.displayName).font(.subheadline).fontWeight(.medium)
                            Text(tester.email ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if let inviteType = tester.inviteType {
                            Text(inviteType)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(4)
                        }
                        if betaViewModel.updatingTesterId == tester.id {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Button(role: .destructive) {
                                testerPendingRemoval = tester
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.red)
                            .accessibilityLabel("Remove \(tester.displayName) from group")
                            .help("Remove from group")
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 160)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Email Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Check if email is invited…", text: $betaViewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { betaViewModel.searchTesterByEmail() }
            if !betaViewModel.searchText.isEmpty {
                Button(action: {
                    betaViewModel.searchText = ""
                    betaViewModel.hasSearched = false
                    betaViewModel.searchResult = nil
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .help("Clear search")
            }
            if betaViewModel.isSearching {
                ProgressView().scaleEffect(0.7)
            } else {
                Button("Search") { betaViewModel.searchTesterByEmail() }
                    .buttonStyle(.bordered)
                    .disabled(!EmailValidator.isValid(EmailValidator.normalized(betaViewModel.searchText)))
            }
        }
    }

    @ViewBuilder private var searchResultView: some View {
        if betaViewModel.hasSearched {
            if let result = betaViewModel.searchResult {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("\(result.email ?? "") is already an invited tester of this app.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    let inGroup = betaViewModel.testers.contains { $0.id == result.id }
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(inGroup ? "In this group" : "Not in this group")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background((inGroup ? Color.green : Color.orange).opacity(0.15))
                            .foregroundColor(inGroup ? .green : .orange)
                            .cornerRadius(4)
                        if !inGroup {
                            Button("Add to this group") {
                                betaViewModel.addTestersToGroup(testerIds: [result.id])
                            }
                            .buttonStyle(.bordered)
                            .disabled(betaViewModel.selectedGroup == nil)
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.3), lineWidth: 1))
            } else if !betaViewModel.isSearching {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.orange)
                    Text("\(betaViewModel.searchText) is not invited to this app.")
                        .font(.subheadline)
                    Spacer()
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1))
            }
        }
    }

    private var inviteSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Invite Beta Tester")
                .font(.headline)
            TextField("Email (required)", text: $inviteEmail)
                .textFieldStyle(.roundedBorder)
            HStack {
                TextField("First name", text: $inviteFirstName)
                    .textFieldStyle(.roundedBorder)
                TextField("Last name", text: $inviteLastName)
                    .textFieldStyle(.roundedBorder)
            }
            if let group = betaViewModel.selectedGroup {
                Text("Will be invited to “\(group.name ?? "group")”.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { showInviteSheet = false }
                    .buttonStyle(.plain)
                Button("Send Invite") {
                    betaViewModel.inviteTester(email: inviteEmail,
                                               firstName: inviteFirstName.isEmpty ? nil : inviteFirstName,
                                               lastName: inviteLastName.isEmpty ? nil : inviteLastName)
                    showInviteSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(!EmailValidator.isValid(EmailValidator.normalized(inviteEmail)))
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    // MARK: - Builds & Review

    private func buildsSection(group: BetaGroupModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Builds & External Review")
                .font(.headline)
                .padding(.top, 8)

            if builds.isEmpty {
                Text("Select a version with builds to assign or submit for review.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                HStack {
                    Picker("Build", selection: $buildIdForActions) {
                        Text("Select build").tag("")
                        ForEach(builds, id: \.id) { build in
                            Text("\(selectedVersionString)(\(build.version ?? "?"))").tag(build.id)
                        }
                    }
                    .frame(maxWidth: 260)
                    .onChange(of: builds) { _, newBuilds in
                        if !newBuilds.contains(where: { $0.id == buildIdForActions }) {
                            buildIdForActions = ""
                        }
                    }
                    .onChange(of: buildIdForActions) { _, newId in
                        guard !newId.isEmpty else { return }
                        betaViewModel.fetchBuildBetaDetail(buildId: newId)
                        betaViewModel.fetchReviewStatus(buildId: newId)
                    }

                    Button("Assign to group") {
                        if let build = builds.first(where: { $0.id == buildIdForActions }) {
                            betaViewModel.assignBuildToGroup(build: build)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(buildIdForActions.isEmpty ||
                              betaViewModel.updatingBuildId == buildIdForActions ||
                              betaViewModel.viewState == .betaAssignmentUpdating)
                }

                if buildIdForActions.isEmpty {
                    Text("Select a build to view auto-notify and external review options.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    buildReviewCard(buildId: buildIdForActions)
                }
            }

            if !group.builds.isEmpty {
                Text("Builds in group: \(group.builds.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func buildReviewCard(buildId: String) -> some View {
        let detail = betaViewModel.betaDetails[buildId]
        let reviewState = betaViewModel.reviewStates[buildId]
        let isBusy = betaViewModel.updatingBuildId == buildId ||
            betaViewModel.reviewLoadingBuildId == buildId ||
            betaViewModel.viewState == .betaDetailUpdating

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Auto-notify testers")
                    .font(.subheadline)
                Spacer()
                if isBusy {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Toggle("", isOn: Binding(
                        get: { betaViewModel.autoNotifyState(for: buildId) },
                        set: { betaViewModel.setAutoNotify(buildId: buildId, enabled: $0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }
            Text("When on, new builds are automatically sent to this group.")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("External review status")
                        .font(.subheadline)
                    if let reviewState {
                        Text(reviewStatusLabel(reviewState))
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(reviewStatusColor(reviewState).opacity(0.15))
                            .foregroundColor(reviewStatusColor(reviewState))
                            .cornerRadius(4)
                    } else {
                        Text("Not checked yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("Check status") {
                    betaViewModel.fetchReviewStatus(buildId: buildId)
                }
                .buttonStyle(.bordered)
                Button("Submit for external review") {
                    betaViewModel.submitForExternalReview(buildId: buildId)
                }
                .buttonStyle(.borderedProminent)
                .disabled(reviewState == "WAITING_FOR_REVIEW" || reviewState == "IN_REVIEW" ||
                          betaViewModel.reviewLoadingBuildId == buildId)
            }
            if let internalState = detail?.internalBuildState {
                Text("Internal: \(internalState)  •  External: \(detail?.externalBuildState ?? "-")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func reviewStatusLabel(_ state: String) -> String {
        switch state {
        case "NO_SUBMISSION": return "NOT SUBMITTED"
        case "WAITING_FOR_REVIEW": return "WAITING FOR REVIEW"
        case "IN_REVIEW": return "IN REVIEW"
        case "APPROVED": return "APPROVED"
        case "REJECTED": return "REJECTED"
        default: return state
        }
    }

    private func reviewStatusColor(_ state: String) -> Color {
        switch state {
        case "APPROVED": return .green
        case "REJECTED": return .red
        case "IN_REVIEW": return .blue
        case "WAITING_FOR_REVIEW": return .orange
        case "NO_SUBMISSION": return .secondary
        default: return .secondary
        }
    }

    // MARK: - Shared States

    private func loadingState(text: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView().scaleEffect(1.1)
            Text(text).font(.subheadline).foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text(title).font(.title3).fontWeight(.medium)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    BetaGroupView(betaViewModel: BetaViewModel(), selectedApp: nil, builds: [])
}
