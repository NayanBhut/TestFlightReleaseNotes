//
//  UsersTableView.swift
//  App Store
//
//  Users table from the users-light Figma frame: toolbar (title + total
//  pill, search, Invite User) over a Name / Email / Role / Status / Apps
//  Access table. Pending invitations render inline with an Invited status.
//  Invite/remove/resend reuse the shared view-model writes; role editing
//  stays in the legacy sheet for now.
//

import SwiftUI

struct UsersTableView: View {
    @ObservedObject var viewModel: ResourcesViewModel
    var apps: [AppsData] = []
    @State private var showInviteForm = false
    @State private var removingUser: UserModel?
    @State private var bannerError: String?

    private var users: [UserModel] { viewModel.filteredUsers }
    private var invitations: [UserInvitationModel] { viewModel.filteredInvitations }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
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
            table
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShipyardTheme.tableBackground)
        .onAppear {
            viewModel.load(.users)
            viewModel.loadInvitations()
        }
        .sheet(isPresented: $showInviteForm) {
            InviteUserForm(viewModel: viewModel, apps: apps) {
                showInviteForm = false
            }
        }
        .confirmationDialog(
            "Remove this user from the team? They lose access immediately.",
            isPresented: Binding(
                get: { removingUser != nil },
                set: { if !$0 { removingUser = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove User", role: .destructive) {
                guard let user = removingUser else { return }
                Task { @MainActor in
                    if case .failure(let message) = await viewModel.removeUser(id: user.id) {
                        bannerError = message
                    }
                    removingUser = nil
                }
            }
            Button("Cancel", role: .cancel) {
                removingUser = nil
            }
        }
    }

    // MARK: - Toolbar

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
                showInviteForm.toggle()
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(ShipyardTheme.accent)
            .cornerRadius(6)
            .buttonStyle(.plain)
            .accessibilityLabel("Invite a user")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(LaunchTheme.page)
    }

    private var totalText: String {
        if let total = viewModel.totals[.users] {
            return "\(total) Total"
        }
        return "\(viewModel.loadedCount(for: .users)) Total"
    }

    // MARK: - Table

    @ViewBuilder
    private var table: some View {
        switch viewModel.usersState {
        case .idle, .loading:
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                Text("Loading users…")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.body)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            ErrorRetryView(
                title: "Couldn't Load Users",
                message: message,
                retryTitle: "Retry",
                onRetry: { viewModel.retry(.users) }
            )
        default:
            if users.isEmpty && invitations.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        headerRow
                        ForEach(invitations, id: \.id) { invitation in
                            invitationRow(invitation)
                            ShipyardTheme.rowDivider.frame(height: 1)
                        }
                        ForEach(users, id: \.id) { user in
                            userRow(user)
                            ShipyardTheme.rowDivider.frame(height: 1)
                        }
                        paginationFooter
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("No Users")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            Text("Invite people to collaborate on this team")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
            Button("Invite User") {
                showInviteForm = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerRow: some View {
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

    private func userRow(_ user: UserModel) -> some View {
        HStack(spacing: 12) {
            Text(userDisplayName(user))
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

            Text(userRolesDisplay(user.roles))
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

            Text(userAppsAccess(user))
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Remove") {
                removingUser = user
            }
            .accessibilityLabel("Remove \(userDisplayName(user))")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(userDisplayName(user)), \(userRolesDisplay(user.roles))")
    }

    private func invitationRow(_ invitation: UserInvitationModel) -> some View {
        let name = [invitation.firstName, invitation.lastName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return HStack(spacing: 12) {
            Text(name.isEmpty ? (invitation.email ?? "Invited user") : name)
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
                .lineLimit(1)
                .frame(width: 180, alignment: .leading)

            Text(invitation.email ?? "—")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(ShipyardTheme.body)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 240, alignment: .leading)

            Text(userRolesDisplay(invitation.roles))
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
                .lineLimit(1)
                .frame(width: 160, alignment: .leading)

            HStack(spacing: 6) {
                Circle()
                    .fill(ShipyardTheme.warning)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text("Invited")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.title)
            }
            .frame(width: 120, alignment: .leading)

            Text("—")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Resend Invitation") {
                Task { @MainActor in
                    if case .failure(let message) = await viewModel.resendInvitation(
                        email: invitation.email ?? "",
                        firstName: invitation.firstName ?? "",
                        lastName: invitation.lastName ?? "",
                        roles: invitation.roles ?? [],
                        allAppsVisible: invitation.allAppsVisible ?? false,
                        provisioningAllowed: invitation.provisioningAllowed ?? false) {
                        bannerError = message
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(invitation.email ?? "invited user"), invited")
    }

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

// MARK: - Display helpers

private func userDisplayName(_ user: UserModel) -> String {
    let full = [user.firstName, user.lastName]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    if !full.isEmpty { return full }
    return user.username ?? "Unknown user"
}

private func userRolesDisplay(_ roles: [String]?) -> String {
    guard let roles, !roles.isEmpty else { return "—" }
    let display = roles.map { role in
        UserRoleOption(rawValue: role)?.displayName ?? role
    }
    if display.count == 1 { return display[0] }
    return "\(display[0]) +\(display.count - 1)"
}

/// The API carries visibility but no per-user app count, so access reads
/// "All Apps" or "Limited" rather than Figma's counts.
private func userAppsAccess(_ user: UserModel) -> String {
    user.allAppsVisible == true ? "All Apps" : "Limited"
}
