//
//  ProfilesTableView.swift
//  App Store
//
//  Profiles table in the Figma table language (no Figma screen exists for
//  this kind — columns follow the API model): toolbar (title + total pill,
//  search, New Profile) over a Name / Type / Platform / State / Expiration
//  table. Deletion runs from the row context menu with a confirmation;
//  creation reuses the shared CreateProfileForm.
//

import SwiftUI

struct ProfilesTableView: View {
    @ObservedObject var viewModel: ResourcesViewModel
    @State private var showCreateForm = false
    @State private var deleting: ProfileModel?
    @State private var bannerError: String?

    private var profiles: [ProfileModel] { viewModel.filteredProfiles }

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
            viewModel.load(.profiles)
        }
        .sheet(isPresented: $showCreateForm) {
            CreateProfileForm(viewModel: viewModel) {
                showCreateForm = false
            }
        }
        .confirmationDialog(
            "Delete this provisioning profile? Builds signed with it stop installing.",
            isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Profile", role: .destructive) {
                guard let profile = deleting else { return }
                Task { @MainActor in
                    if case .failure(let message) = await viewModel.deleteProfile(id: profile.id) {
                        bannerError = message
                    }
                    deleting = nil
                }
            }
            Button("Cancel", role: .cancel) {
                deleting = nil
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Profiles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                ShipyardCountPill(text: totalText)
            }

            Spacer()

            ShipyardSearchField(prompt: "Search Profiles", text: viewModel.searchBinding(for: .profiles))

            Button("New Profile") {
                showCreateForm.toggle()
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(ShipyardTheme.accent)
            .cornerRadius(6)
            .buttonStyle(.plain)
            .accessibilityLabel("Create a provisioning profile")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(LaunchTheme.page)
    }

    private var totalText: String {
        if let total = viewModel.totals[.profiles] {
            return "\(total) Total"
        }
        return "\(viewModel.loadedCount(for: .profiles)) Total"
    }

    // MARK: - Table

    @ViewBuilder
    private var table: some View {
        switch viewModel.profilesState {
        case .idle, .loading:
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                Text("Loading profiles…")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.body)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            ErrorRetryView(
                title: "Couldn't Load Profiles",
                message: message,
                retryTitle: "Retry",
                onRetry: { viewModel.retry(.profiles) }
            )
        default:
            if profiles.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        headerRow
                        ForEach(profiles, id: \.id) { profile in
                            profileRow(profile)
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
            Text("No Profiles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            Text("Create a profile to bind a bundle ID, certificates and devices")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
            Button("New Profile") {
                showCreateForm = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Text("Name").frame(width: 240, alignment: .leading)
            Text("Type").frame(width: 200, alignment: .leading)
            Text("Platform").frame(width: 120, alignment: .leading)
            Text("State").frame(width: 140, alignment: .leading)
            Text("Expiration").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(ShipyardTheme.body)
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(ShipyardTheme.tableHeader)
    }

    private func profileRow(_ profile: ProfileModel) -> some View {
        let state = profileStateDisplay(profile.profileState)
        return HStack(spacing: 12) {
            Text(profile.name ?? "Unknown profile")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 240, alignment: .leading)

            Text(profileTypeDisplay(profile.profileType))
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
                .lineLimit(1)
                .frame(width: 200, alignment: .leading)

            Text(shipyardPlatformDisplay(profile.platform ?? ""))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(ShipyardTheme.body)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.12))
                .cornerRadius(4)
                .frame(width: 120, alignment: .leading)

            HStack(spacing: 6) {
                Circle()
                    .fill(state.color)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(state.text)
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.title)
            }
            .frame(width: 140, alignment: .leading)

            Text(profileExpiryDisplay(profile.expirationDate))
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Delete", role: .destructive) {
                deleting = profile
            }
            .accessibilityLabel("Delete \(profile.name ?? "profile")")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.name ?? "profile"), \(state.text)")
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if let nextCursor = viewModel.nextCursors[.profiles] {
            HStack {
                Spacer()
                if viewModel.paginationFailedKinds.contains(.profiles) {
                    Button("Couldn't load more — Retry") {
                        viewModel.loadMore(.profiles, cursor: nextCursor)
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
                            if !viewModel.isPaginatingKinds.contains(.profiles) {
                                viewModel.loadMore(.profiles, cursor: nextCursor)
                            }
                        }
                }
                Spacer()
            }
        }
    }
}

// MARK: - Display helpers

private struct ProfileStateDisplay {
    let color: Color
    let text: String
}

private func profileStateDisplay(_ raw: String?) -> ProfileStateDisplay {
    switch raw {
    case "ACTIVE":
        return ProfileStateDisplay(color: ShipyardTheme.success, text: "Active")
    case "PROCESSING":
        return ProfileStateDisplay(color: ShipyardTheme.warning, text: "Processing")
    case "INVALID":
        return ProfileStateDisplay(color: ShipyardTheme.danger, text: "Invalid")
    case nil:
        return ProfileStateDisplay(color: ShipyardTheme.body, text: "—")
    default:
        return ProfileStateDisplay(color: ShipyardTheme.body, text: raw ?? "—")
    }
}

/// "IOS_APP_DEVELOPMENT" → "iOS App Development" via the picker's own
/// display name; unknown codes pass through prettified.
private func profileTypeDisplay(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else { return "—" }
    if let option = ProfileTypeOption(rawValue: raw) {
        return option.displayName
    }
    return raw
        .replacingOccurrences(of: "_", with: " ")
        .capitalized
        .replacingOccurrences(of: "Ios", with: "iOS")
        .replacingOccurrences(of: "Tvos", with: "tvOS")
}

/// "Sep 28, 2026"; unparseable values pass through untouched.
private func profileExpiryDisplay(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else { return "—" }
    if let date = sharedProfileDate(raw) {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    return raw
}

private func sharedProfileDate(_ raw: String) -> Date? {
    if let date = ISO8601DateFormatter().date(from: raw) { return date }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.date(from: raw)
}
