//
//  UserPermissionViews.swift
//  App Store
//
//  Users & permissions flow from the Figma invite-users frames: shared
//  role checkboxes, app-access picker, permission summary table, the
//  Choose-Selected-Apps sheet (Invite + Edit), the user detail/edit view
//  (incl. protected Account Holder), and the resend / cancel-invitation /
//  remove-user sheets. API contracts (spec-verified):
//  - POST /v1/userInvitations: email/first/last/roles required,
//    allAppsVisible + provisioningAllowed + visibleApps linkage optional.
//  - PATCH /v1/users/{id}: roles + allAppsVisible + provisioningAllowed
//    + visibleApps linkage (all optional, absent keys omitted).
//  - No resend endpoint: resend = DELETE invite → re-POST identical.
//  - No invitation sent-date: pending list sorts by expirationDate.
//  Writes need an Admin key; a TestFlight-only key 403s.
//

import SwiftUI

// MARK: - Display helpers

/// "Sarah Connor", falling back to username.
func teamMemberDisplayName(_ user: UserModel) -> String {
    let full = [user.firstName, user.lastName]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    if !full.isEmpty { return full }
    return user.username ?? "Unknown user"
}

/// "Jane Doe", falling back to email.
func inviteeDisplayName(_ invitation: UserInvitationModel) -> String {
    let full = [invitation.firstName, invitation.lastName]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    if !full.isEmpty { return full }
    return invitation.email ?? "Invited user"
}

/// Raw role values → display names, unknown values pass through verbatim.
func roleDisplayNames(_ roles: [String]?) -> [String] {
    (roles ?? []).map { UserRoleOption(rawValue: $0)?.displayName ?? $0 }
}

/// "Developer", "Developer +2", or "—" for table cells.
func rolesSummary(_ roles: [String]?) -> String {
    let names = roleDisplayNames(roles)
    if names.isEmpty { return "—" }
    if names.count == 1 { return names[0] }
    return "\(names[0]) +\(names.count - 1)"
}

private nonisolated(unsafe) let userDateParser: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private nonisolated(unsafe) let userDateParserPlain: ISO8601DateFormatter = {
    ISO8601DateFormatter()
}()

/// ISO-8601 → "Oct 2, 2026" for the pending list Sent column. The API
/// carries expirationDate but no sent-date; recency sorts on this.
func shortDateString(_ iso8601: String?) -> String {
    guard let raw = iso8601, !raw.isEmpty else { return "—" }
    let date = userDateParser.date(from: raw) ?? userDateParserPlain.date(from: raw)
    guard let date else { return "—" }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
}

func userVisibleAppNames(_ user: UserModel) -> [String] {
    user.visibleApps.map { $0.name ?? $0.bundleId ?? $0.id }
}

/// "Developer · Orbit, Atlas · provisioning allowed" — resend/cancel recaps.
func invitationGrantSummary(_ invitation: UserInvitationModel) -> String {
    var parts: [String] = [rolesSummary(invitation.roles)]
    let names = invitation.visibleApps.map { $0.name ?? $0.bundleId ?? $0.id }
    if invitation.allAppsVisible ?? true {
        parts.append("All apps")
    } else {
        parts.append(names.isEmpty ? "Selected apps" : names.joined(separator: ", "))
    }
    parts.append(invitation.provisioningAllowed == true ? "provisioning allowed" : "no provisioning")
    return parts.joined(separator: " · ")
}

// MARK: - Role checkboxes (Figma 114-4499 / 114-4278)

/// Multi-select role checkboxes with the one-line remit under each.
/// ACCOUNT_HOLDER is excluded (grantableCases) — it renders read-only.
struct RoleCheckboxList: View {
    @Binding var roles: Set<UserRoleOption>
    var disabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(UserRoleOption.grantableCases, id: \.self) { option in
                Toggle(isOn: Binding(
                    get: { roles.contains(option) },
                    set: { checked in
                        if checked { roles.insert(option) }
                        else { roles.remove(option) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.displayName)
                            .font(.system(size: 13))
                            .foregroundColor(ShipyardTheme.title)
                        Text(option.description)
                            .font(.system(size: 11))
                            .foregroundColor(ShipyardTheme.body)
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(disabled)
                .padding(.vertical, 4)
                .accessibilityLabel("\(option.displayName) role")
            }
        }
    }
}

// MARK: - App access picker

/// All-apps / selected-apps radios + team-wide provisioning checkbox.
/// The selected-apps recap + Choose Apps… opener come from the caller so
/// Invite and Edit share the layout with different state.
struct AppAccessPicker: View {
    @Binding var allAppsVisible: Bool
    @Binding var provisioningAllowed: Bool
    /// e.g. "Orbit and Atlas only." — shown under Selected Apps.
    var selectedSummary: String
    var onChooseApps: () -> Void
    var disabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("", selection: $allAppsVisible) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("All Apps (including new apps)")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                    Text("Access automatically includes future apps.")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                }
                .tag(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Selected Apps")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                    Text(selectedSummary)
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                }
                .tag(false)
            }
            .pickerStyle(.radioGroup)
            .disabled(disabled)
            .labelsHidden()

            if !allAppsVisible {
                Button("Choose Apps…") { onChooseApps() }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                    .disabled(disabled)
                    .padding(.leading, 22)
                    .accessibilityLabel("Choose apps")
            }

            Toggle(isOn: $provisioningAllowed) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Access to Certificates, Identifiers & Profiles")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                    Text("Provisioning access is team-wide, not limited to selected apps.")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                }
            }
            .toggleStyle(.checkbox)
            .disabled(disabled)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Permission summary table

/// Two-column Setting/Value table from the invite + edit summaries.
struct PermissionSummaryTable: View {
    var title: String
    var keyHeader: String
    var valueHeader: String
    var rows: [(key: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(keyHeader)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(valueHeader)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(ShipyardTheme.tableHeader)
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 12) {
                        Text(row.key)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.value)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(minHeight: 38, alignment: .leading)
                    .background(index % 2 == 0 ? ShipyardTheme.tableBackground : LaunchTheme.page)
                    if index < rows.count - 1 {
                        ShipyardTheme.rowDivider.frame(height: 1)
                    }
                }
            }
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(ShipyardTheme.rowDivider, lineWidth: 1)
            )
        }
    }
}

// MARK: - Choose Selected Apps sheet (Figma 114-4433)

/// Shared app-scope chooser for Invite and Edit. Search filters by name
/// or bundle ID; the footer counts the live selection.
struct ChooseAppsSheet: View {
    var apps: [AppsData]
    @Binding var selectedIds: Set<String>
    var onDone: () -> Void
    @State private var search = ""

    private var filtered: [AppsData] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return apps }
        return apps.filter {
            ($0.name ?? "").localizedStandardContains(query)
                || ($0.bundleId ?? "").localizedStandardContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose selected apps")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(ShipyardTheme.title)
                Text("Reusable in Invite User and Edit User · \(selectedIds.count) of \(apps.count) selected")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("App scope")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                Text("New apps will not be granted automatically. Provisioning access, when enabled, remains a separate team-wide permission.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Search apps", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filtered, id: \.id) { app in
                            Toggle(isOn: Binding(
                                get: { selectedIds.contains(app.id) },
                                set: { checked in
                                    if checked { selectedIds.insert(app.id) }
                                    else { selectedIds.remove(app.id) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name ?? app.id)
                                        .font(.system(size: 13))
                                        .foregroundColor(ShipyardTheme.title)
                                    Text(app.bundleId ?? "")
                                        .font(.system(size: 11))
                                        .foregroundColor(ShipyardTheme.body)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .padding(.vertical, 4)
                        }
                        if filtered.isEmpty {
                            Text(apps.isEmpty
                                 ? "No apps loaded — apps appear here once the Apps table loads."
                                 : "No apps match this search.")
                                .font(.system(size: 12))
                                .foregroundColor(ShipyardTheme.body)
                                .padding(.vertical, 8)
                        }
                    }
                }
                .frame(minHeight: 200, maxHeight: 340)
            }

            HStack {
                Spacer()
                Button("Cancel") { onDone() }
                    .buttonStyle(.launchSecondary)
                Button("Use \(selectedIds.count) Selected App\(selectedIds.count == 1 ? "" : "s")") {
                    onDone()
                }
                .buttonStyle(.launchPrimary)
                .disabled(selectedIds.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 480, idealWidth: 560, maxWidth: 640)
    }
}

// MARK: - User detail / edit (Figma 114-4278, 114-4857)

/// Edit roles, app scope and provisioning for a team member. Save is
/// enabled only with changes (Revert restores the snapshot); the Account
/// Holder renders read-only with the protected banner — ownership
/// transfer is an Apple-supported process outside this API.
struct UserDetailView: View {
    @ObservedObject var viewModel: ResourcesViewModel
    var user: UserModel
    var apps: [AppsData] = []
    var onBack: () -> Void
    var onRemoved: () -> Void

    @State private var roles: Set<UserRoleOption>
    @State private var allAppsVisible: Bool
    @State private var provisioningAllowed: Bool
    @State private var selectedAppIds: Set<String>
    @State private var snapshot: Snapshot
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showChooseApps = false
    @State private var showRemove = false

    private struct Snapshot: Equatable {
        var roles: Set<UserRoleOption>
        var allAppsVisible: Bool
        var provisioningAllowed: Bool
        var selectedAppIds: Set<String>
    }

    init(viewModel: ResourcesViewModel, user: UserModel, apps: [AppsData] = [],
         onBack: @escaping () -> Void, onRemoved: @escaping () -> Void) {
        self.viewModel = viewModel
        self.user = user
        self.apps = apps
        self.onBack = onBack
        self.onRemoved = onRemoved
        let initialRoles = Set((user.roles ?? []).compactMap(UserRoleOption.init(rawValue:)))
        let initialAllApps = user.allAppsVisible ?? true
        let initialProvisioning = user.provisioningAllowed ?? false
        let initialIds = Set(user.visibleApps.map(\.id))
        _roles = State(initialValue: initialRoles)
        _allAppsVisible = State(initialValue: initialAllApps)
        _provisioningAllowed = State(initialValue: initialProvisioning)
        _selectedAppIds = State(initialValue: initialIds)
        _snapshot = State(initialValue: Snapshot(
            roles: initialRoles, allAppsVisible: initialAllApps,
            provisioningAllowed: initialProvisioning, selectedAppIds: initialIds))
    }

    private var isAccountHolder: Bool {
        (user.roles ?? []).contains(UserRoleOption.ACCOUNT_HOLDER.rawValue)
    }

    private var isDirty: Bool {
        roles != snapshot.roles
            || allAppsVisible != snapshot.allAppsVisible
            || provisioningAllowed != snapshot.provisioningAllowed
            || selectedAppIds != snapshot.selectedAppIds
    }

    private var selectedSummary: String {
        let names = apps
            .filter { selectedAppIds.contains($0.id) }
            .map { $0.name ?? $0.bundleId ?? $0.id }
        if names.isEmpty { return "No apps picked yet." }
        return names.joined(separator: " and ") + " only."
    }

    private var summaryRows: [(key: String, value: String)] {
        let scope = allAppsVisible
            ? "All apps" : ResourcesViewModel.appScopeLabel(
                allAppsVisible: false,
                visibleAppNames: apps.filter { selectedAppIds.contains($0.id) }
                    .map { $0.name ?? $0.bundleId ?? $0.id })
        return [
            (scope, rolesSummary(roles.map(\.rawValue))),
            ("Other apps", allAppsVisible ? "Included — all apps" : "No app-specific access"),
            ("Signing resources", provisioningAllowed ? "Team-wide provisioning enabled" : "No provisioning access"),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Button(action: onBack) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Users")
                                        .font(.system(size: 13))
                                }
                                .foregroundColor(ShipyardTheme.accent)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Back to users")
                        }
                        Text("Edit \(teamMemberDisplayName(user))")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(ShipyardTheme.title)
                        Text("\(user.username ?? "") · Active · roles and app access")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                    }

                    if isAccountHolder {
                        DeviceStatusBanner(
                            variant: .warning,
                            title: "Account Holder is protected",
                            message: "The Account Holder cannot be removed from this user-management flow. Ownership transfer and account changes must be handled through Apple’s supported process.")
                    }

                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Roles")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(ShipyardTheme.title)
                            if isAccountHolder {
                                Text(UserRoleOption.ACCOUNT_HOLDER.displayName)
                                    .font(.system(size: 13))
                                    .foregroundColor(ShipyardTheme.body)
                                Text(UserRoleOption.ACCOUNT_HOLDER.description)
                                    .font(.system(size: 11))
                                    .foregroundColor(ShipyardTheme.body)
                            } else {
                                RoleCheckboxList(roles: $roles, disabled: isSaving)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("App and provisioning access")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(ShipyardTheme.title)
                            Text(isAccountHolder
                                 ? "The Account Holder has full team access."
                                 : "A Developer with provisioning access can manage signing resources across the team.")
                                .font(.system(size: 12))
                                .foregroundColor(ShipyardTheme.body)
                                .fixedSize(horizontal: false, vertical: true)
                            AppAccessPicker(
                                allAppsVisible: $allAppsVisible,
                                provisioningAllowed: $provisioningAllowed,
                                selectedSummary: selectedSummary,
                                onChooseApps: { showChooseApps = true },
                                disabled: isSaving || isAccountHolder)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !isAccountHolder {
                        PermissionSummaryTable(
                            title: "Permission summary",
                            keyHeader: "Resource", valueHeader: "Effective access",
                            rows: summaryRows)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.negative)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
            }

            Divider()
            HStack(spacing: 12) {
                Text(viewModel.lastSyncText(for: .users) ?? "Not synced yet")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                Spacer()
                if !isAccountHolder {
                    Button("Remove User…") { showRemove = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.danger)
                        .disabled(isSaving)
                        .accessibilityLabel("Remove \(teamMemberDisplayName(user))")
                    Button("Revert") {
                        roles = snapshot.roles
                        allAppsVisible = snapshot.allAppsVisible
                        provisioningAllowed = snapshot.provisioningAllowed
                        selectedAppIds = snapshot.selectedAppIds
                        errorMessage = nil
                    }
                    .buttonStyle(.launchSecondary)
                    .disabled(isSaving || !isDirty)
                    if isSaving {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Button("Save User") {
                            Task { @MainActor in await runSave() }
                        }
                        .buttonStyle(.launchPrimary)
                        .disabled(!isDirty)
                    }
                } else {
                    Text("Remove User")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(LaunchTheme.page)
                        .cornerRadius(6)
                        .accessibilityLabel("Remove User, disabled for Account Holder")
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 56)
            .background(LaunchTheme.page)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShipyardTheme.tableBackground)
        .sheet(isPresented: $showChooseApps) {
            ChooseAppsSheet(apps: apps, selectedIds: $selectedAppIds) {
                showChooseApps = false
            }
        }
        .sheet(isPresented: $showRemove) {
            RemoveUserSheet(
                user: user,
                appNames: apps.filter { selectedAppIds.contains($0.id) }
                    .map { $0.name ?? $0.bundleId ?? $0.id },
                viewModel: viewModel) {
                    showRemove = false
                    onRemoved()
                }
        }
    }

    private func runSave() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        let result = await viewModel.updateUser(
            user,
            roles: roles,
            allAppsVisible: allAppsVisible,
            provisioningAllowed: provisioningAllowed,
            visibleAppIds: allAppsVisible ? [] : selectedAppIds.sorted())
        switch result {
        case .success:
            snapshot = Snapshot(
                roles: roles, allAppsVisible: allAppsVisible,
                provisioningAllowed: provisioningAllowed, selectedAppIds: selectedAppIds)
        case .failure(let message):
            errorMessage = message
        case .ignored:
            break
        }
    }
}

// MARK: - Resend invitation sheet (Figma 114-4760)

/// Confirm re-sending a pending invitation. Resend changes nothing —
/// the invite is deleted and re-created with identical details.
struct ResendInvitationSheet: View {
    @ObservedObject var viewModel: ResourcesViewModel
    var invitation: UserInvitationModel
    var onDone: () -> Void
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Resend \(inviteeDisplayName(invitation))’s invitation?")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(ShipyardTheme.title)

            VStack(alignment: .leading, spacing: 8) {
                Text("Recipient and access")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                Text("Send a new invitation email. Pending status remains until the user accepts.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
                    .fixedSize(horizontal: false, vertical: true)
                readOnlyField(label: "Email", value: invitation.email ?? "—")
                readOnlyField(label: "Role / apps", value: invitationGrantSummary(invitation))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { onDone() }
                    .buttonStyle(.launchSecondary)
                    .disabled(isSaving)
                if isSaving {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button("Resend Invitation") {
                        Task { @MainActor in
                            isSaving = true
                            defer { isSaving = false }
                            errorMessage = nil
                            switch await viewModel.resendInvitation(invitation) {
                            case .success: onDone()
                            case .failure(let message): errorMessage = message
                            case .ignored: break
                            }
                        }
                    }
                    .buttonStyle(.launchPrimary)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 440, idealWidth: 520, maxWidth: 600)
    }
}

// MARK: - Cancel invitation sheet (Figma 114-4788)

/// Confirm revoking a pending invitation (DELETE /v1/userInvitations/{id}).
/// Withdrawing pending access removes no active user account.
struct CancelInvitationSheet: View {
    @ObservedObject var viewModel: ResourcesViewModel
    var invitation: UserInvitationModel
    var onDone: () -> Void
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cancel \(inviteeDisplayName(invitation))’s invitation?")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(ShipyardTheme.title)

            DeviceStatusBanner(
                variant: .warning,
                title: "Pending access will be withdrawn",
                message: "\(invitation.email ?? "This address") will no longer be able to accept this invitation. No active user account is removed. A new invitation can be sent later.")

            VStack(alignment: .leading, spacing: 8) {
                Text("Invitation")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                Text("Result: invitation removed from Pending list; return to Users.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
                readOnlyField(label: "Grant", value: invitationGrantSummary(invitation))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Keep Invitation") { onDone() }
                    .buttonStyle(.launchSecondary)
                    .disabled(isSaving)
                if isSaving {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button("Cancel Invitation") {
                        Task { @MainActor in
                            isSaving = true
                            defer { isSaving = false }
                            errorMessage = nil
                            switch await viewModel.revokeInvitation(id: invitation.id) {
                            case .success: onDone()
                            case .failure(let message): errorMessage = message
                            case .ignored: break
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(ShipyardTheme.danger)
                    .cornerRadius(6)
                    .accessibilityLabel("Cancel invitation")
                }
            }
        }
        .padding(24)
        .frame(minWidth: 440, idealWidth: 520, maxWidth: 600)
    }
}

// MARK: - Remove user sheet (Figma 114-4816)

/// Confirm removing a team member (DELETE /v1/users/{id}). Type-to-confirm
/// guards the destructive action; existing team resources are untouched.
struct RemoveUserSheet: View {
    var user: UserModel
    var appNames: [String] = []
    @ObservedObject var viewModel: ResourcesViewModel
    var onDone: () -> Void
    @State private var confirmation = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var email: String { user.username ?? "" }

    private var confirmed: Bool {
        !email.isEmpty
            && confirmation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == email.lowercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Remove \(teamMemberDisplayName(user)) from the team?")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(ShipyardTheme.title)

            DeviceStatusBanner(
                variant: .warning,
                title: "App and provisioning access will be removed",
                message: "\(teamMemberDisplayName(user)) loses \(rolesSummary(user.roles)) access to \(appNames.isEmpty ? "assigned apps" : appNames.joined(separator: " and ")) and team-wide provisioning access. This does not delete the apps, certificates, or profiles they created.")

            VStack(alignment: .leading, spacing: 8) {
                Text("Confirmation")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                Text("Result returns to Users with “\(teamMemberDisplayName(user)) removed”. Re-invitation is required to grant access again.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Type email to confirm")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
                TextField(email, text: $confirmation)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .disabled(isSaving)
            }

            PermissionSummaryTable(
                title: "",
                keyHeader: "Access", valueHeader: "Impact",
                rows: [
                    (appNames.isEmpty ? "Apps" : appNames.joined(separator: " / "),
                     "Cannot manage these apps"),
                    ("Certificates, Identifiers & Profiles", "No further provisioning access"),
                    ("Existing team resources", "Remain in the team"),
                ])

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { onDone() }
                    .buttonStyle(.launchSecondary)
                    .disabled(isSaving)
                if isSaving {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button("Remove User") {
                        Task { @MainActor in
                            isSaving = true
                            defer { isSaving = false }
                            errorMessage = nil
                            switch await viewModel.removeUser(id: user.id) {
                            case .success: onDone()
                            case .failure(let message): errorMessage = message
                            case .ignored: break
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(confirmed ? ShipyardTheme.danger : ShipyardTheme.body.opacity(0.4))
                    .cornerRadius(6)
                    .disabled(!confirmed)
                    .accessibilityLabel("Remove user")
                }
            }
        }
        .padding(24)
        .frame(minWidth: 480, idealWidth: 560, maxWidth: 640)
    }
}

// MARK: - Shared bits

/// Disabled-look read-only field from the resend/cancel recaps.
private func readOnlyField(label: String, value: String) -> some View {
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
            .background(LaunchTheme.page)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(LaunchTheme.border, lineWidth: 1)
            )
    }
}
