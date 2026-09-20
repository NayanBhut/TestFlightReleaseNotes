//
//  SideBarView.swift
//  App Store
//
//  Created by Nayan Bhut on 02/05/24.
//

import SwiftUI

struct SideBarView: View {
    @StateObject var viewModel: SideBarViewModel
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var navigationManager: NavigationManager
    @Binding var isAddNewTeam: Bool
    @Binding var isNewAccountAdded: Bool
    @State var showTeams = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack {
                    Text("Apps")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()

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
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(viewModel.isAppsLoading)
                    .help("Refresh (Cmd+R)")
                }

                teamSelector()

                // Search field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.caption)

                    TextField("Search apps...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .font(.subheadline)

                    if !viewModel.searchText.isEmpty {
                        Button {
                            viewModel.clearSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Clear search")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
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
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Apps list
            appList()
        }
        .onAppear {
            if CredentialStorage.shared.selectedTeam == nil {
                // restoreDefaultTeam() returns true on SUCCESS (a team was
                // restored) — log out only when nothing could be restored.
                if !CredentialStorage.shared.restoreDefaultTeam() {
                    navigationManager.isLoggedIn = false
                }
            }
            viewModel.getiOSApps()
        }
        .onChange(of: isNewAccountAdded) { oldValue, newValue in
            if newValue {
                viewModel.getiOSApps()
            }
        }
        .onChange(of: viewModel.isTeamChanged) { oldValue, newValue in
            if newValue {
                viewModel.updateTeam()
                viewModel.isTeamChanged = false
            }
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
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(CredentialStorage.shared.selectedTeam?.key ?? "No Team")
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: showTeams ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if showTeams {
                VStack(spacing: 4) {
                    ForEach(CredentialStorage.shared.getTeams, id: \.self) { team in
                        HStack {
                            Text(team)
                                .font(.subheadline)
                                .foregroundColor(.primary)

                            Spacer()

                            Button(action: {
                                CredentialStorage.shared.deleteCredential(for: team)
                                if CredentialStorage.shared.getTeams.isEmpty {
                                    navigationManager.isLoggedIn = false
                                } else {
                                    CredentialStorage.shared.restoreDefaultTeam()
                                    viewModel.getiOSApps()
                                }
                            }) {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Remove team")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .textBackgroundColor))
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
                        .fill(Color(nsColor: .windowBackgroundColor))
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
                    .font(.caption)
                Text("Filter: \(viewModel.selectedStateFilter.displayName)")
                    .font(.caption)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
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
                    .font(.caption)
                Text("Sort")
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
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
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
        case .loaded:
            VStack(spacing: 0) {
                if viewModel.filteredApps.isEmpty {
                    // Loaded apps exist but none match the current search.
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No Matching Apps")
                            .font(.title3)
                            .fontWeight(.medium)
                        Text("No apps match the current search")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button("Clear Search") {
                            viewModel.clearSearch()
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    List(viewModel.filteredApps, id: \.id) { app in
                        AppRowView(app: app, isSelected: app.isSelected)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.setSelectedAppAndGetVersions(app: app)
                            }
                    }
                    .listStyle(.sidebar)

                    if let nextCursor = viewModel.appMeta?.paging.nextCursor {
                        VStack {
                            Divider()
                            ProgressView()
                                .scaleEffect(0.8)
                                .onAppear {
                                    // The VM guards against duplicate
                                    // concurrent page fetches.
                                    viewModel.loadMoreApps(cursor: nextCursor)
                                }
                        }
                    }
                }
            }
        case .empty:
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "app.dashed")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("No Apps Found")
                    .font(.title3)
                    .fontWeight(.medium)
                Text("No iOS apps are available for this team")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Button("Refresh") {
                    viewModel.retryApps()
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .padding()
        case .error(let message):
            ErrorRetryView(
                title: "Couldn't Load Apps",
                message: message,
                retryTitle: "Retry"
            ) {
                viewModel.retryApps()
            }
        }
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
                .fill(isSelected ? Color.accentColor : Color.clear)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name ?? "Unknown App")
                    .font(.headline)
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    Text(app.currentLiveVersion.1)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(app.currentState)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(getStateColor(app.currentState))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(getStateColor(app.currentState).opacity(0.15))
                        .cornerRadius(4)
                }

                Text(app.bundleId ?? "")
                    .font(.caption2)
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
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var appIconView: some View {
        let iconSize: CGFloat = 32
        if let url = resolvedIconURL(template: app.iconURL, size: Int(iconSize)) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize, height: iconSize)
                        .cornerRadius(6)
                case .failure:
                    placeholderIcon(size: iconSize)
                case .empty:
                    ProgressView()
                        .frame(width: iconSize, height: iconSize)
                }
            }
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
