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
    @State private var inviteUserSearch = ""
    @State private var pickedTeamUserId: String?
    @State private var pickedTeamUserEmail = ""
    @State private var buildIdForActions = ""
    @State private var testerPendingRemoval: BetaTesterModel?
    // Batch I (I5): group CRUD state.
    @State private var showCreateGroupSheet = false
    @State private var newGroupName = ""
    @State private var newGroupPublicLink = false
    @State private var newGroupLimitText = ""
    @State private var isCreatingGroup = false
    @State private var isRenamingGroup = false
    @State private var draftGroupName = ""
    @State private var showDeleteGroupConfirm = false
    @State private var testerPendingDeletion: BetaTesterModel?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if selectedApp == nil {
                EmptyStateView(icon: "person.3", title: "No App Selected",
                               subtitle: "Select an app from the sidebar to view its TestFlight groups")
            } else if !betaViewModel.isGroupsLoaded && betaViewModel.viewState == .betaGroupsLoading {
                LoadingStateView(text: "Loading beta groups...")
            } else if betaViewModel.groups.isEmpty {
                EmptyStateView(icon: "person.3", title: "No Beta Groups",
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
        .sheet(isPresented: $showCreateGroupSheet) {
            createGroupSheet
        }
        .onChange(of: selectedApp?.id) { _, _ in
            Task { await refreshGroupsIfStale() }
        }
        .onAppear {
            Task { await refreshGroupsIfStale() }
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
                    Task { await betaViewModel.removeTesterFromGroup(tester) }
                }
                testerPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { testerPendingRemoval = nil }
        }
        .confirmationDialog(
            "Delete \(testerPendingDeletion?.displayName ?? "this tester") from the team? They will lose access to all TestFlight groups.",
            isPresented: Binding(
                get: { testerPendingDeletion != nil },
                set: { if !$0 { testerPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete from Team", role: .destructive) {
                if let tester = testerPendingDeletion {
                    Task { await betaViewModel.deleteTester(tester) }
                }
                testerPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { testerPendingDeletion = nil }
        }
    }

    /// Staleness lives in the view model so switching tabs (which destroys
    /// this view's @State) doesn't cause a redundant refetch on return.
    private func refreshGroupsIfStale(force: Bool = false) async {
        guard let app = selectedApp else { return }
        if !force {
            if betaViewModel.viewState == .betaGroupsLoading { return }
            if betaViewModel.isGroupsLoaded, betaViewModel.currentAppId == app.id { return }
        }
        await betaViewModel.fetchBetaGroups(app: app)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Beta Groups")
                .font(.sectionHeader)
                .fontWeight(.semibold)
            Spacer()
            if !betaViewModel.groups.isEmpty {
                Text("\(betaViewModel.groups.count) groups")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
            }
            if let truncation = betaViewModel.groupsTruncationMessage {
                Text(truncation)
                    .font(.appCaption2)
                    .foregroundColor(.secondary)
            }
            Button(action: { Task { await refreshGroupsIfStale(force: true) } }) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.appCaption)
            }
            .buttonStyle(.bordered)
            .disabled(selectedApp == nil || betaViewModel.viewState == .betaGroupsLoading)
            // Batch I (I5): group create opens a sheet; writes need an
            // Admin key, failures surface via the existing TestFlight alert.
            Button(action: {
                newGroupName = ""
                newGroupPublicLink = false
                newGroupLimitText = ""
                showCreateGroupSheet = true
            }) {
                Label("New Group", systemImage: "plus")
                    .font(.appCaption)
            }
            .buttonStyle(.bordered)
            .disabled(selectedApp == nil || betaViewModel.viewState == .betaGroupsLoading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(AppTheme.secondaryBackground)
    }

    // MARK: - Groups List

    private var groupsList: some View {
        List(betaViewModel.groups, id: \.id) { group in
            // Row highlighting derives from the view model's selection —
            // no duplicated isSelected flag on the decoded model.
            let isSelected = betaViewModel.selectedGroup?.id == group.id
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? AppTheme.accent : Color.clear)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name ?? "Unnamed group")
                        .font(.subheader)
                    HStack(spacing: 6) {
                        Text(group.isInternalGroup == true ? "Internal" : "External")
                            .font(.appCaption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((group.isInternalGroup == true ? Color.blue : AppTheme.readyForSale).opacity(0.15))
                            .foregroundColor(group.isInternalGroup == true ? .blue : .green)
                            .cornerRadius(4)
                        if group.publicLinkEnabled == true {
                            Text("Public link")
                                .font(.appCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Text("\(group.betaTesters.count) testers • \(group.builds.count) builds")
                        .font(.appCaption2)
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
                .fill(isSelected ? AppTheme.accent.opacity(0.1) : Color.clear))
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
                // Group title with rename/delete (Batch I, I5).
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if isRenamingGroup {
                            TextField("Group name", text: $draftGroupName)
                                .textFieldStyle(.roundedBorder)
                                .font(.subheader)
                                .disabled(betaViewModel.updatingGroupId != nil)
                            Button("Cancel") {
                                isRenamingGroup = false
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(betaViewModel.updatingGroupId != nil)
                            if betaViewModel.updatingGroupId != nil {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Button("Save") {
                                    Task {
                                        if await betaViewModel.renameGroup(group, newName: draftGroupName) {
                                            isRenamingGroup = false
                                        }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(draftGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        } else {
                            Text(group.name ?? "Unnamed group")
                                .font(.subheader)
                                .fontWeight(.semibold)
                            Spacer()
                            if betaViewModel.updatingGroupId == group.id {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Button("Rename") {
                                    draftGroupName = group.name ?? ""
                                    isRenamingGroup = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(betaViewModel.updatingGroupId != nil)
                                Button("Delete", role: .destructive) {
                                    showDeleteGroupConfirm = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(betaViewModel.updatingGroupId != nil)
                                .alert("Delete this beta group?", isPresented: $showDeleteGroupConfirm) {
                                    Button("Cancel", role: .cancel) {}
                                    Button("Delete", role: .destructive) {
                                        Task { await betaViewModel.deleteGroup(group) }
                                    }
                                } message: {
                                    Text("Testers keep team access but lose this group's builds. This cannot be undone.")
                                }
                            }
                        }
                    }
                    Text(groupDetailSubtitle(group))
                        .font(.appCaption)
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
            EmptyStateView(icon: "person.2", title: "No Group Selected",
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
                    .font(.subheader)
                Spacer()
                if betaViewModel.viewState == .betaTestersLoading {
                    ProgressView().scaleEffect(0.7)
                }
                Button(action: {
                    inviteEmail = ""
                    inviteFirstName = ""
                    inviteLastName = ""
                    inviteUserSearch = ""
                    pickedTeamUserId = nil
                    pickedTeamUserEmail = ""
                    showInviteSheet = true
                }) {
                    Label("Invite tester", systemImage: "plus")
                        .font(.appCaption)
                }
                .buttonStyle(.borderedProminent)
                .disabled(betaViewModel.selectedGroup == nil)
            }

            searchBar

            searchResultView

            if let truncation = betaViewModel.testersTruncationMessage {
                Text(truncation)
                    .font(.appCaption2)
                    .foregroundColor(.secondary)
            }

            if !betaViewModel.isTestersLoaded && betaViewModel.viewState == .betaTestersLoading {
                LoadingStateView(text: "Loading testers...")
            } else if betaViewModel.testers.isEmpty {
                Text("No testers in this group yet. Invite one to get started.")
                    .font(.appBody)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                List(betaViewModel.testers, id: \.id) { tester in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tester.displayName).font(.appBody).fontWeight(.medium)
                            Text(tester.email ?? "")
                                .font(.appCaption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if let inviteType = tester.inviteType {
                            Text(inviteType)
                                .font(.appCaption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.secondaryText.opacity(0.15))
                                .cornerRadius(4)
                        }
                        if betaViewModel.updatingTesterId == tester.id {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            // Trash = remove from this group; the circled
                            // trash deletes the tester from the team
                            // entirely (DELETE /v1/betaTesters/{id}).
                            Button(role: .destructive) {
                                testerPendingRemoval = tester
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.red)
                            .accessibilityLabel("Remove \(tester.displayName) from group")
                            .help("Remove from group")
                            Button(role: .destructive) {
                                testerPendingDeletion = tester
                            } label: {
                                Image(systemName: "trash.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.red)
                            .accessibilityLabel("Delete \(tester.displayName) from team")
                            .help("Delete from team")
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
                .onSubmit { Task { await betaViewModel.searchTesterByEmail() } }
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
                Button("Search") { Task { await betaViewModel.searchTesterByEmail() } }
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
                            .font(.appBody)
                            .fontWeight(.medium)
                        Text("\(result.email ?? "") is already an invited tester of this app.")
                            .font(.appCaption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    let inGroup = betaViewModel.testers.contains { $0.id == result.id }
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(inGroup ? "In this group" : "Not in this group")
                            .font(.appCaption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background((inGroup ? AppTheme.readyForSale : AppTheme.pending).opacity(0.15))
                            .foregroundColor(inGroup ? .green : .orange)
                            .cornerRadius(4)
                        if !inGroup {
                            Button("Add to this group") {
                                Task { await betaViewModel.addTestersToGroup(testerIds: [result.id]) }
                            }
                            .buttonStyle(.bordered)
                            .disabled(betaViewModel.selectedGroup == nil)
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.readyForSale.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.readyForSale.opacity(0.3), lineWidth: 1))
            } else if !betaViewModel.isSearching {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.orange)
                    Text("\(betaViewModel.searchText) is not invited to this app.")
                        .font(.appBody)
                    Spacer()
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.pending.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.pending.opacity(0.3), lineWidth: 1))
            }
        }
    }

    // MARK: - Group Create (Batch I, I5)

    /// POST /v1/betaGroups — name plus optional public-link settings.
    /// Stays open on failure (createGroup returns false); the TestFlight
    /// alert surfaces the error.
    private var createGroupSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Beta Group")
                .font(.subheader)
            TextField("Group name (required)", text: $newGroupName)
                .textFieldStyle(.roundedBorder)
                .disabled(isCreatingGroup)
            Toggle("Enable public link", isOn: $newGroupPublicLink)
                .disabled(isCreatingGroup)
            TextField("Public link limit (optional, number of testers)", text: $newGroupLimitText)
                .textFieldStyle(.roundedBorder)
                .disabled(isCreatingGroup || !newGroupPublicLink)
            if newGroupPublicLink {
                Text("Leave the limit empty for an unlimited public link.")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
            }
            if let limitError = groupLimitError {
                Text(limitError)
                    .font(.appCaption)
                    .foregroundColor(.red)
            }
            Text("Test on a throwaway group first. Needs an API key with the Admin role.")
                .font(.appCaption)
                .foregroundColor(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { showCreateGroupSheet = false }
                    .buttonStyle(.plain)
                    .disabled(isCreatingGroup)
                if isCreatingGroup {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button("Create Group") {
                        Task {
                            isCreatingGroup = true
                            defer { isCreatingGroup = false }
                            if await betaViewModel.createGroup(
                                name: newGroupName,
                                publicLinkEnabled: newGroupPublicLink,
                                publicLinkLimit: groupLimit
                            ) {
                                showCreateGroupSheet = false
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCreateGroup)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    /// Parsed limit: nil when empty (unlimited) or unparsable (blocks
    /// create — a typo must never silently create an unlimited group).
    private var groupLimit: Int? {
        let trimmed = newGroupLimitText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }

    private var groupLimitError: String? {
        let trimmed = newGroupLimitText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard newGroupPublicLink, !trimmed.isEmpty else { return nil }
        guard let value = groupLimit else {
            return "The public link limit must be a whole number (e.g. 100)."
        }
        if value <= 0 {
            return "The public link limit must be greater than zero."
        }
        return nil
    }

    private var canCreateGroup: Bool {
        newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? false : groupLimitError == nil
    }

    private var inviteSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Invite Beta Tester")
                .font(.subheader)
            // Team picker: search + tap fills the fields below (manual
            // entry still works for people outside the team).
            TextField("Search team members…", text: $inviteUserSearch)
                .textFieldStyle(.roundedBorder)
            if betaViewModel.isTeamUsersLoading && betaViewModel.teamUsers.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading team…")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                }
            } else if let teamError = betaViewModel.teamUsersError, betaViewModel.teamUsers.isEmpty {
                Text(teamError)
                    .font(.appCaption)
                    .foregroundColor(.secondary)
            } else {
                let matches = betaViewModel.matchingTeamUsers(query: inviteUserSearch)
                if !matches.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(matches, id: \.id) { user in
                                Button {
                                    inviteEmail = user.username ?? ""
                                    inviteFirstName = user.firstName ?? ""
                                    inviteLastName = user.lastName ?? ""
                                    pickedTeamUserId = user.id
                                    pickedTeamUserEmail = user.username ?? ""
                                } label: {
                                    HStack(spacing: 8) {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text("\(user.firstName ?? "") \(user.lastName ?? "")".trimmingCharacters(in: .whitespaces).isEmpty ? (user.username ?? "Unknown user") : "\(user.firstName ?? "") \(user.lastName ?? "")")
                                                .font(.appBody)
                                                .foregroundColor(.primary)
                                            Text(user.username ?? "")
                                                .font(.appCaption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if pickedTeamUserId == user.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(RoundedRectangle(cornerRadius: 6)
                                        .fill(pickedTeamUserId == user.id ? AppTheme.accent.opacity(0.12) : Color.clear))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Invite \(user.username ?? "user")")
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                } else if !inviteUserSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("No team member matches — type the email below to invite someone new.")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                }
            }
            TextField("Email (required)", text: $inviteEmail)
                .textFieldStyle(.roundedBorder)
                .onChange(of: inviteEmail) { _, newEmail in
                    // Manual edits after picking unpick (the checkmark
                    // tracks the picked address, not free text).
                    if newEmail != pickedTeamUserEmail {
                        pickedTeamUserId = nil
                    }
                }
            HStack {
                TextField("First name", text: $inviteFirstName)
                    .textFieldStyle(.roundedBorder)
                TextField("Last name", text: $inviteLastName)
                    .textFieldStyle(.roundedBorder)
            }
            if let group = betaViewModel.selectedGroup {
                Text("Will be invited to “\(group.name ?? "group")”.")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { showInviteSheet = false }
                    .buttonStyle(.plain)
                Button("Send Invite") {
                    Task {
                        await betaViewModel.inviteTester(
                            email: inviteEmail,
                            firstName: inviteFirstName.isEmpty ? nil : inviteFirstName,
                            lastName: inviteLastName.isEmpty ? nil : inviteLastName
                        )
                    }
                    showInviteSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(!EmailValidator.isValid(EmailValidator.normalized(inviteEmail)))
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { betaViewModel.loadTeamUsers() }
    }

    // MARK: - Builds & Review

    private func buildsSection(group: BetaGroupModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Builds & External Review")
                .font(.subheader)
                .padding(.top, 8)

            if builds.isEmpty {
                Text("Select a version with builds to assign or submit for review.")
                    .font(.appBody)
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
                        Task {
                            // Independent requests: run them concurrently
                            // instead of serially to halve perceived latency.
                            async let detail: Void = betaViewModel.fetchBuildBetaDetail(buildId: newId)
                            async let review: Void = betaViewModel.fetchReviewStatus(buildId: newId)
                            _ = await (detail, review)
                        }
                    }

                    Button("Assign to group") {
                        if let build = builds.first(where: { $0.id == buildIdForActions }) {
                            Task { await betaViewModel.assignBuildToGroup(build: build) }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(buildIdForActions.isEmpty ||
                              betaViewModel.updatingBuildId == buildIdForActions ||
                              betaViewModel.viewState == .betaAssignmentUpdating)
                }

                if buildIdForActions.isEmpty {
                    Text("Select a build to view auto-notify and external review options.")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                } else {
                    buildReviewCard(buildId: buildIdForActions)
                }
            }

            if !group.builds.isEmpty {
                Text("Builds in group: \(group.builds.count)")
                    .font(.appCaption)
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
                    .font(.appBody)
                Spacer()
                if isBusy {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Toggle("", isOn: Binding(
                        get: { betaViewModel.autoNotifyState(for: buildId) },
                        set: { newValue in Task { await betaViewModel.setAutoNotify(buildId: buildId, enabled: newValue) } }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }
            Text("When on, new builds are automatically sent to this group.")
                .font(.appCaption)
                .foregroundColor(.secondary)

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("External review status")
                        .font(.appBody)
                    if let reviewState {
                        Text(reviewStatusLabel(reviewState))
                            .font(.appCaption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(reviewStatusColor(reviewState).opacity(0.15))
                            .foregroundColor(reviewStatusColor(reviewState))
                            .cornerRadius(4)
                    } else {
                        Text("Not checked yet")
                            .font(.appCaption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("Check status") {
                    Task { await betaViewModel.fetchReviewStatus(buildId: buildId) }
                }
                .buttonStyle(.bordered)
                Button("Submit for external review") {
                    Task { await betaViewModel.submitForExternalReview(buildId: buildId) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(reviewState == "WAITING_FOR_REVIEW" || reviewState == "IN_REVIEW" ||
                          betaViewModel.reviewLoadingBuildId == buildId)
            }
            if let internalState = detail?.internalBuildState {
                Text("Internal: \(internalState)  •  External: \(detail?.externalBuildState ?? "-")")
                    .font(.appCaption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.secondaryBackground))
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
}

#Preview {
    BetaGroupView(betaViewModel: BetaViewModel(), selectedApp: nil, builds: [])
}
