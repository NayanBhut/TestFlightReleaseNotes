//
//  SideBarView.swift
//  App Store
//
//  Created by Nayan Bhut on 02/05/24.
//

import SwiftUI
import AppKit

struct SideBarView: View {
    @StateObject var viewModel: SideBarViewModel
    @StateObject private var resourcesViewModel = ResourcesViewModel()
    @ObservedObject private var credentialStorage = CredentialStorage.shared
    @Binding var isAddNewTeam: Bool
    @Binding var isNewAccountAdded: Bool
    @State var showTeams = false
    @AppStorage(UserDefaultsKeys.showExtendedInfo) private var showExtendedInfo = true
    @EnvironmentObject var appCommands: AppCommandStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack {
                    Text("Apps")
                        .font(.sectionHeader)
                        .fontWeight(.semibold)

                    Spacer()

                    // Batch C: show/hide App Info, Reviews and Resources.
                    Button(action: {
                        showExtendedInfo.toggle()
                    }) {
                        Image(systemName: showExtendedInfo ? "eye.fill" : "eye.slash")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .help(showExtendedInfo
                          ? "Hide App Info, Reviews and Resources"
                          : "Show App Info, Reviews and Resources")
                    .accessibilityLabel(showExtendedInfo ? "Hide extended info" : "Show extended info")

                    Button(action: {
                        isAddNewTeam = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                    }
                    .buttonStyle(.plain)
                    .help("Add Team")

                      Button(action: {
                          viewModel.retryApps()
                      }) {
                          Image(systemName: "arrow.clockwise")
                              .font(.system(size: 16))
                              .rotationEffect(.degrees(viewModel.isAppsLoading ? 360 : 0))
                              .animation(
                                  viewModel.isAppsLoading
                                      ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                                      : .default,
                                  value: viewModel.isAppsLoading
                              )
                      }
                     .buttonStyle(.plain)
                     .disabled(viewModel.isAppsLoading)
                     .help("Refresh (Cmd+R)")
                     .accessibilityLabel("Refresh Apps")

                     Button(action: {
                         AppAppearance.toggle()
                     }) {
                         Image(systemName: colorScheme == .dark ? "sun.max.fill" : "moon.fill")
                             .font(.system(size: 16))
                     }
                     .buttonStyle(.plain)
                     .help("Toggle Dark Mode (⌘D)")
                     .accessibilityLabel("Toggle Dark Mode")

                     Button(action: {
                         appCommands.showPalette.toggle()
                     }) {
                         Image(systemName: "magnifyingglass")
                             .font(.system(size: 16))
                     }
                     .buttonStyle(.plain)
                     .help("Command Palette (⌘K)")
                     .accessibilityLabel("Command Palette")
                 }

                teamSelector()

                // Search field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.appCaption)
                        .accessibilityHidden(true)

                    TextField("Search apps...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .font(.appBody)

                    if !viewModel.searchText.isEmpty {
                        Button {
                            viewModel.clearSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.appCaption)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                        .help("Clear search")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.textBackgroundColor)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.border, lineWidth: 1)
                )

                // State filter and sort side by side
                HStack(spacing: 8) {
                    stateFilterDropdown()
                    sortToggle()
                }

                HStack {
                    Spacer()

                    if let total = viewModel.appMeta?.paging.total {
                        Text("\(total) apps")
                            .font(.appCaption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
            .background(AppTheme.secondaryBackground)

            Divider()

            // Apps list
            appList()

            // Batch C2: team-scoped Resources below apps (like AppDab's
            // Resources group), gated by the extended-info flag.
            if showExtendedInfo {
                Divider()
                ResourcesSectionView(
                    viewModel: resourcesViewModel,
                    apps: viewModel.appsState.loadedValue ?? []
                )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .onAppear {
            // CredentialStorage.init already restored the default team; this
            // extra attempt covers mid-session edge cases (keychain wiped
            // externally). Login state derives from the published team list —
            // there is no flag left to reconcile here.
            if CredentialStorage.shared.selectedTeam == nil {
                CredentialStorage.shared.restoreDefaultTeam()
            }
            viewModel.getiOSApps()
        }
        // A newly added team (first or subsequent) selects itself in
        // saveLoginState; refresh the list for it. Launch is covered by
        // onAppear, deletions by deleteTeam.
        .onChange(of: isNewAccountAdded) { oldValue, newValue in
            if newValue {
                viewModel.getiOSApps()
            }
        }
        .onChange(of: viewModel.isTeamChanged) { oldValue, newValue in
            if newValue {
                viewModel.updateTeam()
                resourcesViewModel.resetForTeamSwitch()
                viewModel.isTeamChanged = false
            }
        }
    }

    /// Removes a team: wipes everything on logout (last team), or resets
    /// onto the restored team when the active one was deleted. Deleting a
    /// background team needs no refresh.
    private func deleteTeam(_ team: String) {
        let wasSelected = CredentialStorage.shared.selectedTeam?.key == team
        CredentialStorage.shared.deleteCredential(for: team)
        // deleteCredential refreshed the published list, so the observed
        // cache already reflects the deletion. NavigationManager.isLoggedIn
        // derives from the same list — nothing to signal manually.
        if credentialStorage.teams.isEmpty {
            viewModel.clearOnLogout()
            resourcesViewModel.resetForTeamSwitch()
        } else if wasSelected {
            CredentialStorage.shared.restoreDefaultTeam()
            viewModel.updateTeam()
            resourcesViewModel.resetForTeamSwitch()
        }
    }

    @ViewBuilder private func teamSelector() -> some View {
        VStack(spacing: 8) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTeams.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "person.2.fill")
                        .font(.appCaption)
                        .foregroundColor(.secondary)

                    Text(CredentialStorage.shared.selectedTeam?.key ?? "No Team")
                        .font(.appBody)
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: showTeams ? "chevron.up" : "chevron.down")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.textBackgroundColor)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if showTeams {
                VStack(spacing: 4) {
                    ForEach(credentialStorage.teams, id: \.self) { team in
                        HStack {
                            Text(team)
                                .font(.appBody)
                                .foregroundColor(.primary)

                            Spacer()

                            // Plain Image, not a Button: a Button here fires
                            // ALONGSIDE the row's onTapGesture, re-selecting
                            // the team being deleted and refetching its apps.
                            // The high-priority gesture wins over the row
                            // gesture, so delete never selects.
                            Image(systemName: "trash")
                                .font(.appCaption)
                                .foregroundColor(.red)
                                .padding(6)
                                .contentShape(Rectangle())
                                .highPriorityGesture(
                                    TapGesture().onEnded {
                                        deleteTeam(team)
                                    }
                                )
                                .focusable(true)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel("Remove \(team)")
                                // Gesture-only views aren't reliably activatable
                                // via VoiceOver/keyboard — wire the default action.
                                .accessibilityAction(.default) { deleteTeam(team) }
                                .help("Remove team")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AppTheme.textBackgroundColor)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            CredentialStorage.shared.changeTeam = team
                            viewModel.isTeamChanged = true
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showTeams = false
                            }
                        }
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.windowBackground)
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }

    private func stateFilterDropdown() -> some View {
        Menu {
            ForEach(AppConfigs.AppStateFilter.allCases, id: \.self) { state in
                Button(action: {
                    viewModel.selectedStateFilter = state
                }) {
                    HStack {
                        Text(state.displayName)
                        if viewModel.selectedStateFilter == state {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.appCaption)
                Text("Filter: \(viewModel.selectedStateFilter.displayName)")
                    .font(.appCaption)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.textBackgroundColor)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
    }

    private func sortToggle() -> some View {
        Menu {
            ForEach(AppConfigs.SortOption.allCases, id: \.self) { option in
                Button(action: {
                    viewModel.selectedSortOption = option
                }) {
                    HStack {
                        Text(option.displayName)
                        if viewModel.selectedSortOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.appCaption)
                Text("Sort: \(viewModel.selectedSortOption.displayName)")
                    .font(.appCaption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.textBackgroundColor)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder private func appList() -> some View {
        switch viewModel.appsState {
        case .idle, .loading:
            VStack(spacing: 16) {
                Spacer()
                ProgressView()
                    .scaleEffect(1.2)
                Text("Loading apps...")
                    .font(.appBody)
                    .foregroundColor(.secondary)
                Spacer()
            }
        case .loaded:
            VStack(spacing: 0) {
                if viewModel.filteredApps.isEmpty {
                    noMatchesView
                } else {
                    List(viewModel.filteredApps, id: \.id) { app in
                        AppRowView(app: app, isSelected: app.isSelected)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.setSelectedAppAndGetVersions(app: app)
                            }
                            .onAppear {
                                // Lazy List renders only visible rows, so this
                                // fires when the last row scrolls into view
                                // (or while the list is shorter than the
                                // viewport) — pages load on demand instead of
                                // auto-chaining the whole catalog.
                                if app.id == viewModel.filteredApps.last?.id,
                                   let nextCursor = viewModel.appMeta?.paging.nextCursor {
                                    viewModel.loadMoreApps(cursor: nextCursor)
                                }
                            }
                    }
                    .listStyle(.sidebar)

                    if let nextCursor = viewModel.appMeta?.paging.nextCursor {
                        VStack {
                            Divider()
                            if viewModel.paginationFailed {
                                Button("Couldn't load more — Retry") {
                                    viewModel.loadMoreApps(cursor: nextCursor)
                                }
                                .buttonStyle(.plain)
                                .font(.appCaption)
                                .foregroundColor(.red)
                                .padding(.vertical, 4)
                            } else {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        case .empty:
            if !viewModel.searchText.isEmpty {
                // A server-side search with no hits: same feedback as local
                // no-matches instead of the generic "team has no apps" UI.
                noMatchesView
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "app.dashed")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                        .emptyStateIconAppear()
                    // Branch the copy: with no teams at all, "no apps for
                    // this team" is misleading — the real problem is that
                    // no team exists yet.
                    if credentialStorage.teams.isEmpty {
                        Text("No Teams Yet")
                            .font(.subheader)
                            .fontWeight(.medium)
                        Text("Add a team to load its apps")
                            .font(.appBody)
                            .foregroundColor(.secondary)
                        Button("Add Team") {
                            isAddNewTeam = true
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.vertical, 4)
                    } else {
                        Text("No Apps Found")
                            .font(.subheader)
                            .fontWeight(.medium)
                        Text("No iOS apps are available for this team")
                            .font(.appBody)
                            .foregroundColor(.secondary)
                    }
                    Button("Refresh") {
                        viewModel.retryApps()
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding()
            }
        case .error(let message):
            ErrorRetryView(
                title: "Couldn't Load Apps",
                message: message,
                retryTitle: "Retry",
                onRetry: { viewModel.retryApps() },
                extraButton: credentialStorage.teams.isEmpty
                    ? (title: "Add Team", action: { isAddNewTeam = true })
                    : nil
            )
        }
    }

    /// Feedback shown when loaded apps exist but nothing matches the search.
    private var noMatchesView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No Matching Apps")
                .font(.subheader)
                .fontWeight(.medium)
            Text("No apps match the current search")
                .font(.appBody)
                .foregroundColor(.secondary)
            Button("Clear Search") {
                viewModel.clearSearch()
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

struct AppRowView: View {
    let app: AppsData
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            appIconView

            // Selection indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(isSelected ? AppTheme.accent : Color.clear)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name ?? "Unknown App")
                    .font(.subheader)
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    Text(app.currentLiveVersion.1)
                        .font(.appCaption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.appCaption)
                        .foregroundColor(.secondary)

                    Text(app.currentState)
                        .font(.appCaption)
                        .fontWeight(.medium)
                        .foregroundColor(getStateColor(app.currentState))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(getStateColor(app.currentState).opacity(0.15))
                        .cornerRadius(4)
                }

                Text(app.bundleId ?? "")
                    .font(.appCaption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 16))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? AppTheme.accent.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? AppTheme.accent.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        // Fade the selection highlight instead of blinking it in/out.
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    @ViewBuilder
    private var appIconView: some View {
        let iconSize: CGFloat = 32
        // Always request 2x pixels: Apple's CDN serves arbitrary sizes, the
        // extra resolution is harmless on 1x displays, and it avoids reading
        // window/screen state during view construction.
        let pixelSize = Int(iconSize * 2)
        if let url = resolvedIconURL(template: app.iconURL, size: pixelSize) {
            // Disk + memory cached: AsyncImage re-downloaded on every
            // scroll/launch because the CDN's cache headers revalidate.
            CachedAppIcon(url: url, size: iconSize)
        } else {
            placeholderIcon(size: iconSize)
        }
    }

    private func placeholderIcon(size: CGFloat) -> some View {
        Image(systemName: "app.fill")
            .font(.system(size: size - 4, weight: .medium))
            .foregroundColor(.gray)
            .frame(width: size, height: size)
    }

    /// Resolves an App Store Connect icon template URL (e.g.
    /// `{w}x{h}bb.{f}`) to a concrete size and format.
    private func resolvedIconURL(template: String?, size: Int) -> URL? {
        guard var template = template, !template.isEmpty else { return nil }
        template = template.replacingOccurrences(of: "{w}x{h}bb", with: "\(size)x\(size)bb")
        template = template.replacingOccurrences(of: "{w}x{h}", with: "\(size)x\(size)")
        template = template.replacingOccurrences(of: "{w}", with: "\(size)")
        template = template.replacingOccurrences(of: "{h}", with: "\(size)")
        template = template.replacingOccurrences(of: "{f}", with: "png")
        return URL(string: template)
    }

    private func getStateColor(_ state: String) -> Color {
        switch state.uppercased() {
        case "READY_FOR_SALE":
            return .green
        case "PENDING_DEVELOPER_RELEASE", "PENDING_CONTRACT", "PENDING_APPLE_RELEASE":
            return .orange
        case "IN_REVIEW":
            return .blue
        case "WAITING_FOR_REVIEW":
            return .yellow
        case "REJECTED":
            return .red
        case "PROCESSING_FOR_APP_STORE":
            return .purple
        case "ACCEPTED", "READY_FOR_REVIEW":
            return .mint
        case "METADATA_REJECTED", "INVALID_BINARY":
            return .red.opacity(0.7)
        case "DEVELOPER_REJECTED", "DEVELOPER_REMOVED_FROM_SALE", "REMOVED_FROM_SALE":
            return .gray
        case "WAITING_FOR_EXPORT_COMPLIANCE":
            return .cyan
        default:
            return .secondary
        }
    }
}

#Preview {
    SideBarView(viewModel: SideBarViewModel(), isAddNewTeam: .constant(false), isNewAccountAdded: .constant(false))
}
