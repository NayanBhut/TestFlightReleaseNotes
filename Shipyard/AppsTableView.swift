//
//  AppsTableView.swift
//  App Store
//
//  Apps table from the apps-list-light Figma frame: toolbar (title + total
//  pill, Filter Apps search, Status/Sort menus, refresh) over an Icon /
//  App Name / Bundle ID / Apple ID / State / Platform table. Row tap opens
//  the app's builds. The numeric Apple ID is not exposed by the App Store
//  Connect API, so that column renders a dash.
//

import SwiftUI

struct AppsTableView: View {
    @ObservedObject var sidebarVM: SideBarViewModel
    var onOpenApp: (AppsData) -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            table
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShipyardTheme.tableBackground)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Apps")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                ShipyardCountPill(text: totalText)
            }

            Spacer()

            ShipyardSearchField(prompt: "Filter Apps", text: $sidebarVM.searchText)

            Menu {
                ForEach(AppConfigs.AppStateFilter.allCases, id: \.self) { state in
                    Button {
                        sidebarVM.selectedStateFilter = state
                    } label: {
                        HStack {
                            Text(state.displayName)
                            if sidebarVM.selectedStateFilter == state {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                ShipyardMenuLabel(text: "Status: \(sidebarVM.selectedStateFilter.displayName)")
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Filter by status")

            Menu {
                ForEach(AppConfigs.SortOption.allCases, id: \.self) { option in
                    Button {
                        sidebarVM.selectedSortOption = option
                    } label: {
                        HStack {
                            Text(option.displayName)
                            if sidebarVM.selectedSortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                ShipyardMenuLabel(text: "Sort: \(sidebarVM.selectedSortOption.displayName)")
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Sort apps")

            Button {
                sidebarVM.retryApps()
            } label: {
                ShipyardIcon(name: "ShipyardRefresh", size: 12)
                    .padding(6)
                    .background(LaunchTheme.field)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(LaunchTheme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(sidebarVM.isAppsLoading)
            .accessibilityLabel("Refresh apps")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(LaunchTheme.page)
    }

    private var totalText: String {
        if let total = sidebarVM.appMeta?.paging.total {
            return "\(total) Total"
        }
        return "\(sidebarVM.filteredApps.count) Total"
    }

    // MARK: - Table

    @ViewBuilder
    private var table: some View {
        switch sidebarVM.appsState {
        case .idle, .loading:
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                Text("Loading apps…")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.body)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            ErrorRetryView(
                title: "Couldn't Load Apps",
                message: message,
                retryTitle: "Retry",
                onRetry: { sidebarVM.retryApps() }
            )
        default:
            if sidebarVM.filteredApps.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        headerRow
                        ForEach(sidebarVM.filteredApps, id: \.id) { app in
                            appRow(app)
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
            if !sidebarVM.searchText.isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
                Text("No Matching Apps")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                Button("Clear Search") {
                    sidebarVM.clearSearch()
                }
                .buttonStyle(.bordered)
            } else {
                Text("No Apps Found")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                Text("No apps are available for this team")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.body)
                Button("Refresh") {
                    sidebarVM.retryApps()
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Text("Icon").frame(width: 40, alignment: .leading)
            Text("App Name").frame(width: 180, alignment: .leading)
            Text("Bundle ID").frame(width: 220, alignment: .leading)
            Text("Apple ID").frame(width: 120, alignment: .leading)
            Text("State").frame(width: 200, alignment: .leading)
            Text("Platform").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(ShipyardTheme.body)
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(ShipyardTheme.tableHeader)
    }

    private func appRow(_ app: AppsData) -> some View {
        let name = app.name ?? "Unknown App"
        return Button {
            onOpenApp(app)
        } label: {
            HStack(spacing: 12) {
                appIconTile(app)
                    .frame(width: 40, alignment: .leading)

                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                    .lineLimit(1)
                    .frame(width: 180, alignment: .leading)

                Text(app.bundleId ?? "—")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(ShipyardTheme.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 220, alignment: .leading)

                Text("—")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(ShipyardTheme.tertiary)
                    .frame(width: 120, alignment: .leading)

                HStack(spacing: 6) {
                    Circle()
                        .fill(app.currentState.stateColor)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(app.currentState.isEmpty ? "—" : app.currentState)
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.title)
                        .lineLimit(1)
                }
                .frame(width: 200, alignment: .leading)

                HStack(spacing: 4) {
                    ForEach(appPlatforms(app), id: \.self) { platform in
                        Text(platform)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(ShipyardTheme.body)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ShipyardTheme.tableHeader)
                            .cornerRadius(4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), \(app.currentState)")
        .accessibilityHint("Opens this app's builds")
    }

    /// Real artwork via the shared disk/memory-cached loader (2x pixels);
    /// letter tile fallback when the app carries no icon template.
    @ViewBuilder
    private func appIconTile(_ app: AppsData) -> some View {
        if let url = shipyardAppIconURL(template: app.iconURL, size: 48) {
            CachedAppIcon(url: url, size: 24)
        } else {
            Text(String((app.name ?? "?").prefix(1)).uppercased())
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(shipyardTileColor(for: app.id))
                )
                .accessibilityHidden(true)
        }
    }

    /// Platforms from the app's store versions (the apps endpoint carries
    /// no per-app platform list).
    private func appPlatforms(_ app: AppsData) -> [String] {
        Array(Set(app.appStoreVersions.compactMap(\.platform).map(shipyardPlatformDisplay))).sorted()
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if let nextCursor = sidebarVM.appMeta?.paging.nextCursor {
            HStack {
                Spacer()
                if sidebarVM.paginationFailed {
                    Button("Couldn't load more — Retry") {
                        sidebarVM.loadMoreApps(cursor: nextCursor)
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
                            sidebarVM.loadMoreApps(cursor: nextCursor)
                        }
                }
                Spacer()
            }
        }
    }
}
