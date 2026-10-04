//
//  UsersTableView.swift
//  App Store
//
//  Users & permissions from the Figma invite-users frames: Members /
//  Pending scope toggle, member rows with tap-to-edit detail, pending
//  invitations with inspector + resend/cancel, Account Holder protection,
//  empty state, and the stale-cache error state (editing disabled until
//  refresh succeeds).
//

import SwiftUI

struct UsersTableView: View {
    @ObservedObject var viewModel: ResourcesViewModel
    var apps: [AppsData] = []

    private enum Scope {
        case members
        case pending
    }

    @State private var scope = Scope.members
    @State private var showInviteDetail = false
    @State private var selectedUser: UserModel?
    @State private var selectedInvitation: UserInvitationModel?
    @State private var resendTarget: UserInvitationModel?
    @State private var cancelTarget: UserInvitationModel?
    @State private var removeTarget: UserModel?
    @State private var bannerError: String?

    private var users: [UserModel] { viewModel.filteredUsers }
    private var invitations: [UserInvitationModel] { viewModel.pendingInvitationsByRecency }

    /// Editing is disabled while showing a stale cache (Figma 114-13286).
    private var staleMembers: Bool {
        if case .error = viewModel.usersState {
            return !viewModel.lastLoadedUsers.isEmpty
        }
        return false
    }

    private var stalePending: Bool {
        if case .error = viewModel.invitationsState {
            return !viewModel.lastLoadedInvitations.isEmpty
        }
        return false
    }

    private var staleRows: [UserModel] {
        viewModel.lastLoadedUsers.filter { matchesSearch([$0.username, $0.firstName, $0.lastName]) }
    }

    private var staleInvitations: [UserInvitationModel] {
        viewModel.lastLoadedInvitations.filter { matchesSearch([$0.email, $0.firstName, $0.lastName]) }
    }

    private func matchesSearch(_ fields: [String?]) -> Bool {
        let query = viewModel.searchText(for: .users).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return fields.contains { $0?.localizedStandardContains(query) == true }
    }

    var body: some View {
        if let selectedUser {
            UserDetailView(
                viewModel: viewModel,
                user: selectedUser,
                apps: apps,
                onBack: { self.selectedUser = nil },
                onRemoved: { self.selectedUser = nil })
        } else if showInviteDetail {
            InviteUserDetailView(
                viewModel: viewModel,
                apps: apps,
                onBack: { showInviteDetail = false },
                onSent: {
                    // The new invite lands in the pending list — show it.
                    showInviteDetail = false
                    scope = .pending
                })
        } else {
            VStack(spacing: 0) {
                toolbar
                Divider()
                scopePicker
                Divider()
                if let bannerError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppTheme.negative)
                        Text(bannerError)
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.negative)
                        Spacer()
                        Button {
                            self.bannerError = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss error")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    Divider()
                }
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ShipyardTheme.tableBackground)
            .onAppear {
                viewModel.load(.users)
                viewModel.loadInvitations()
            }
            .sheet(item: $resendTarget) { invitation in
                ResendInvitationSheet(viewModel: viewModel, invitation: invitation) {
                    resendTarget = nil
                }
            }
            .sheet(item: $cancelTarget) { invitation in
                CancelInvitationSheet(viewModel: viewModel, invitation: invitation) {
                    cancelTarget = nil
                }
            }
            .sheet(item: $removeTarget) { user in
                RemoveUserSheet(
                    user: user,
                    appNames: userVisibleAppNames(user),
                    viewModel: viewModel) {
                        removeTarget = nil
                    }
            }
        }
    }

    // MARK: - Toolbar + scope

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Users")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                ShipyardCountPill(text: totalText)
            }

            Spacer()

            ShipyardSearchField(prompt: "Search Users", text: viewModel.searchBinding(for: .users))

            Button("Invite User") {
                showInviteDetail = true
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(ShipyardTheme.accent)
            .cornerRadius(6)
            .buttonStyle(.plain)
            .disabled(staleMembers || stalePending)
            .accessibilityLabel("Invite a user")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(LaunchTheme.page)
    }

    private var scopePicker: some View {
        HStack(spacing: 12) {
            Picker("", selection: $scope) {
                Text("Members").tag(Scope.members)
                Text("Pending (\(pendingCountText))").tag(Scope.pending)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
        }
        .padding(.trailing, 16)
        .padding(.vertical, 4)
    }

    private var pendingCountText: String {
        "\(viewModel.invitationsState.loadedValue?.count ?? viewModel.lastLoadedInvitations.count)"
    }

    private var totalText: String {
        switch scope {
        case .members:
            if let total = viewModel.totals[.users] {
                return "\(total) Total"
            }
            return "\(viewModel.loadedCount(for: .users)) Total"
        case .pending:
            return "\(invitations.count) Pending"
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch scope {
        case .members:
            membersContent
        case .pending:
            pendingContent
        }
    }

    // MARK: - Members (Figma 114-4278 lane, 114-13209, 114-13286)

    @ViewBuilder
    private var membersContent: some View {
        switch viewModel.usersState {
        case .idle, .loading:
            loadingView(text: "Loading users…")
        case .error(let message):
            if staleMembers {
                staleMembersView(message: message)
            } else {
                ErrorRetryView(
                    title: "Couldn't Load Users",
                    message: message,
                    retryTitle: "Retry",
                    onRetry: { viewModel.retry(.users) })
            }
        default:
            if users.isEmpty {
                if viewModel.hasActiveSearch(for: .users) {
                    noMembersMatchState
                } else {
                    usersEmptyState
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        membersHeaderRow
                        ForEach(users, id: \.id) { user in
                            userRow(user, editingDisabled: false)
                            ShipyardTheme.rowDivider.frame(height: 1)
                        }
                        paginationFooter
                    }
                }
            }
        }
    }

    /// Figma 114-13286: stale cache stays visible, editing disabled.
    private func staleMembersView(message: String) -> some View {
        VStack(spacing: 0) {
            DeviceStatusBanner(
                variant: .error,
                title: "Unable to refresh users",
                message: "\(message) Cached data\(staleStamp) is retained below and marked stale.")
                .padding(16)
            ScrollView {
                LazyVStack(spacing: 0) {
                    membersHeaderRow
                    ForEach(staleRows, id: \.id) { user in
                        userRow(user, editingDisabled: true)
                        ShipyardTheme.rowDivider.frame(height: 1)
                    }
                }
            }
            Divider()
            HStack(spacing: 12) {
                Text("Cached snapshot · stale · editing disabled until refresh succeeds")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                Spacer()
                Button("Retry Refresh") { viewModel.retry(.users) }
                    .buttonStyle(.launchPrimary)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
        }
    }

    private var staleStamp: String {
        if let stamp = viewModel.lastSyncText(for: .users) {
            return " (\(stamp.lowercased()))"
        }
        return ""
    }

    /// Figma 114-13209: no members beyond the protected Account Holder.
    private var usersEmptyState: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Users · empty")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(ShipyardTheme.title)
                    Text("Members except Account Holder")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                    DeviceStatusBanner(
                        variant: .info,
                        title: "No additional team members yet",
                        message: "The Account Holder remains protected. No other members are shown in this scope.")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Get started")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ShipyardTheme.title)
                        Text("Invite Your First Team Member… opens the invitation flow.")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack(spacing: 12) {
                Text(viewModel.lastSyncText(for: .users) ?? "Not synced yet")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                Spacer()
                Button("Invite Your First Team Member…") {
                    showInviteDetail = true
                }
                .buttonStyle(.launchPrimary)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
        }
    }

    private var noMembersMatchState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("No matching members")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            Text("No team members match this search.")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadingView(text: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var membersHeaderRow: some View {
        HStack(spacing: 12) {
            Text("Name").frame(width: 180, alignment: .leading)
            Text("Email").frame(width: 240, alignment: .leading)
            Text("Role").frame(width: 160, alignment: .leading)
            Text("Status").frame(width: 120, alignment: .leading)
            Text("Apps Access").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(ShipyardTheme.body)
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(ShipyardTheme.tableHeader)
    }

    private func userRow(_ user: UserModel, editingDisabled: Bool) -> some View {
        HStack(spacing: 12) {
            Text(teamMemberDisplayName(user))
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 180, alignment: .leading)

            Text(user.username ?? "—")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(ShipyardTheme.body)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 240, alignment: .leading)

            Text(rolesSummary(user.roles))
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
                .lineLimit(1)
                .frame(width: 160, alignment: .leading)

            HStack(spacing: 6) {
                Circle()
                    .fill(ShipyardTheme.success)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text("Active")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.title)
            }
            .frame(width: 120, alignment: .leading)

            Text(ResourcesViewModel.appScopeLabel(
                allAppsVisible: user.allAppsVisible,
                visibleAppNames: userVisibleAppNames(user)))
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .contentShape(Rectangle())
        .onTapGesture {
            if !editingDisabled { selectedUser = user }
        }
        .contextMenu {
            if !editingDisabled {
                Button("Edit") { selectedUser = user }
                Button("Remove") { removeTarget = user }
                    .accessibilityLabel("Remove \(teamMemberDisplayName(user))")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(teamMemberDisplayName(user)), \(rolesSummary(user.roles))")
    }

    // MARK: - Pending (Figma 114-4654)

    @ViewBuilder
    private var pendingContent: some View {
        switch viewModel.invitationsState {
        case .idle, .loading:
            loadingView(text: "Loading invitations…")
        case .error(let message):
            if stalePending {
                stalePendingView(message: message)
            } else {
                ErrorRetryView(
                    title: "Couldn't Load Invitations",
                    message: message,
                    retryTitle: "Retry",
                    onRetry: { viewModel.loadInvitations() })
            }
        default:
            if invitations.isEmpty {
                noPendingState
            } else {
                pendingSplitView(rows: invitations, editingDisabled: false)
            }
        }
    }

    private func stalePendingView(message: String) -> some View {
        VStack(spacing: 0) {
            DeviceStatusBanner(
                variant: .error,
                title: "Unable to refresh invitations",
                message: "\(message) Cached data\(staleStamp) is retained below and marked stale.")
                .padding(16)
            pendingSplitView(rows: staleInvitations, editingDisabled: true)
            Divider()
            HStack(spacing: 12) {
                Text("Cached snapshot · stale · editing disabled until refresh succeeds")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                Spacer()
                Button("Retry Refresh") { viewModel.loadInvitations() }
                    .buttonStyle(.launchPrimary)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
        }
    }

    private var noPendingState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("No Pending Invitations")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            Text("New invitations appear here until accepted.")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
            Button("Invite User") {
                showInviteDetail = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pendingSplitView(rows: [UserInvitationModel], editingDisabled: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text("Status: Pending")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.title)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(LaunchTheme.page)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(LaunchTheme.border, lineWidth: 1))
                        Text("Sort: Date sent ↓")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(LaunchTheme.page)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(LaunchTheme.border, lineWidth: 1))
                            .accessibilityLabel("Sorted by date sent, newest first")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            pendingHeaderRow
                            ForEach(rows, id: \.id) { invitation in
                                invitationRow(invitation, editingDisabled: editingDisabled)
                                ShipyardTheme.rowDivider.frame(height: 1)
                            }
                        }
                    }
                }
                Divider()
                invitationInspector(editingDisabled: editingDisabled)
                    .frame(width: 300)
                    .background(LaunchTheme.page)
            }
            Divider()
            HStack(spacing: 12) {
                Text(viewModel.lastSyncText(for: .users) ?? "Not synced yet")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                Spacer()
                Button("Cancel Invitation…") {
                    if let selectedInvitation { cancelTarget = selectedInvitation }
                }
                .buttonStyle(.launchSecondary)
                .disabled(editingDisabled || selectedInvitation == nil)
                Button("Resend Invitation…") {
                    if let selectedInvitation { resendTarget = selectedInvitation }
                }
                .buttonStyle(.launchPrimary)
                .disabled(editingDisabled || selectedInvitation == nil)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
        }
    }

    private var pendingHeaderRow: some View {
        HStack(spacing: 12) {
            Text("User").frame(width: 150, alignment: .leading)
            Text("Role").frame(width: 130, alignment: .leading)
            Text("App scope").frame(width: 150, alignment: .leading)
            Text("Sent").frame(width: 100, alignment: .leading)
            Text("Actions").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(ShipyardTheme.body)
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(ShipyardTheme.tableHeader)
    }

    private func invitationRow(_ invitation: UserInvitationModel, editingDisabled: Bool) -> some View {
        let isSelected = selectedInvitation?.id == invitation.id
        return HStack(spacing: 12) {
            Text(inviteeDisplayName(invitation))
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)

            Text(rolesSummary(invitation.roles))
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
                .lineLimit(1)
                .frame(width: 130, alignment: .leading)

            Text(ResourcesViewModel.appScopeLabel(
                allAppsVisible: invitation.allAppsVisible,
                visibleAppNames: invitation.visibleApps.map { $0.name ?? $0.bundleId ?? $0.id }))
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)

            Text(shortDateString(invitation.expirationDate))
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
                .frame(width: 100, alignment: .leading)

            HStack(spacing: 12) {
                Button("Resend") { resendTarget = invitation }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                    .disabled(editingDisabled)
                Button("Cancel") { cancelTarget = invitation }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                    .disabled(editingDisabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(isSelected ? ShipyardTheme.selectedRow : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedInvitation = invitation
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(inviteeDisplayName(invitation)), invited")
    }

    private func invitationInspector(editingDisabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SELECTED INVITATION")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            Text("Pending users have not yet received the intended access. Resend does not change roles.")
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
                .fixedSize(horizontal: false, vertical: true)
            if let selectedInvitation {
                inspectorField(label: "Email", value: selectedInvitation.email ?? "—")
                inspectorField(label: "Status", value: "Pending · not accepted")
                inspectorField(label: "Grant", value: invitationGrantSummary(selectedInvitation))
                if editingDisabled {
                    Text("Editing disabled until refresh succeeds.")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                }
            } else {
                Text("Select an invitation to inspect it.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
            }
            Spacer()
        }
        .padding(16)
    }

    private func inspectorField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.title)
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ShipyardTheme.tableBackground)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(LaunchTheme.border, lineWidth: 1))
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var paginationFooter: some View {
        if let nextCursor = viewModel.nextCursors[.users] {
            HStack {
                Spacer()
                if viewModel.paginationFailedKinds.contains(.users) {
                    Button("Couldn't load more — Retry") {
                        viewModel.loadMore(.users, cursor: nextCursor)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.danger)
                    .padding(.vertical, 8)
                } else {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.vertical, 8)
                        .onAppear {
                            if !viewModel.isPaginatingKinds.contains(.users) {
                                viewModel.loadMore(.users, cursor: nextCursor)
                            }
                        }
                }
                Spacer()
            }
        }
    }
}
