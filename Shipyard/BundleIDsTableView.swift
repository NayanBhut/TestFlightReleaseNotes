//
//  BundleIDsTableView.swift
//  App Store
//
//  Bundle IDs table in the Figma table language (no Figma screen exists for
//  this kind — columns follow the API model): toolbar (title + total pill,
//  search, New Bundle ID) over a Name / Identifier / Platform / Seed ID
//  table. Rename/delete run from the row context menu; creation reuses the
//  shared CreateBundleIdForm.
//

import SwiftUI

struct BundleIDsTableView: View {
    @ObservedObject var viewModel: ResourcesViewModel
    @State private var showCreateForm = false
    @State private var renaming: BundleIdModel?
    @State private var renameText = ""
    @State private var isRenaming = false
    @State private var deleting: BundleIdModel?
    @State private var bannerError: String?

    private var bundleIds: [BundleIdModel] { viewModel.filteredBundleIds }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let renaming {
                renameRow(renaming)
                Divider()
            }
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
            viewModel.load(.bundleIds)
        }
        .sheet(isPresented: $showCreateForm) {
            CreateBundleIdForm(viewModel: viewModel) {
                showCreateForm = false
            }
        }
        .confirmationDialog(
            "Delete this bundle ID? Apps and profiles using it break.",
            isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Bundle ID", role: .destructive) {
                guard let bundleId = deleting else { return }
                Task { @MainActor in
                    if case .failure(let message) = await viewModel.deleteBundleId(id: bundleId.id) {
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
                Text("Bundle IDs")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                ShipyardCountPill(text: totalText)
            }

            Spacer()

            ShipyardSearchField(prompt: "Search Bundle IDs", text: viewModel.searchBinding(for: .bundleIds))

            Button("New Bundle ID") {
                showCreateForm.toggle()
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(ShipyardTheme.accent)
            .cornerRadius(6)
            .buttonStyle(.plain)
            .accessibilityLabel("Register a bundle ID")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(LaunchTheme.page)
    }

    private var totalText: String {
        if let total = viewModel.totals[.bundleIds] {
            return "\(total) Total"
        }
        return "\(viewModel.loadedCount(for: .bundleIds)) Total"
    }

    // MARK: - Rename

    private func renameRow(_ bundleId: BundleIdModel) -> some View {
        HStack(spacing: 8) {
            Text("Rename “\(bundleId.name ?? bundleId.identifier ?? bundleId.id)”")
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
                .lineLimit(1)
            TextField("New name", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .frame(maxWidth: 280)
                .disabled(isRenaming)
            if isRenaming {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Button("Save") {
                    Task { @MainActor in
                        isRenaming = true
                        defer { isRenaming = false }
                        if case .failure(let message) = await viewModel.renameBundleId(bundleId, newName: renameText) {
                            bannerError = message
                        } else {
                            renaming = nil
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel") {
                    renaming = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRenaming)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(LaunchTheme.field)
    }

    // MARK: - Table

    @ViewBuilder
    private var table: some View {
        switch viewModel.bundleIdsState {
        case .idle, .loading:
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                Text("Loading bundle IDs…")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.body)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            ErrorRetryView(
                title: "Couldn't Load Bundle IDs",
                message: message,
                retryTitle: "Retry",
                onRetry: { viewModel.retry(.bundleIds) }
            )
        default:
            if bundleIds.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        headerRow
                        ForEach(bundleIds, id: \.id) { bundleId in
                            bundleRow(bundleId)
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
            Text("No Bundle IDs")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            Text("Register a bundle ID to tie apps, certificates and profiles together")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
            Button("New Bundle ID") {
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
            Text("Identifier").frame(width: 280, alignment: .leading)
            Text("Platform").frame(width: 120, alignment: .leading)
            Text("Seed ID").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(ShipyardTheme.body)
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(ShipyardTheme.tableHeader)
    }

    private func bundleRow(_ bundleId: BundleIdModel) -> some View {
        HStack(spacing: 12) {
            Text(bundleId.name ?? "Unknown bundle ID")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 240, alignment: .leading)

            Text(bundleId.identifier ?? "—")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(ShipyardTheme.body)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 280, alignment: .leading)

            Text(bundlePlatformDisplay(bundleId.platform))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(ShipyardTheme.body)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.12))
                .cornerRadius(4)
                .frame(width: 120, alignment: .leading)

            Text(bundleId.seedId ?? "—")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(ShipyardTheme.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Rename") {
                renameText = bundleId.name ?? ""
                renaming = bundleId
            }
            Button("Delete", role: .destructive) {
                deleting = bundleId
            }
            .accessibilityLabel("Delete \(bundleId.name ?? bundleId.identifier ?? "bundle ID")")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bundleId.name ?? "bundle ID"), \(bundleId.identifier ?? "")")
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if let nextCursor = viewModel.nextCursors[.bundleIds] {
            HStack {
                Spacer()
                if viewModel.paginationFailedKinds.contains(.bundleIds) {
                    Button("Couldn't load more — Retry") {
                        viewModel.loadMore(.bundleIds, cursor: nextCursor)
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
                            if !viewModel.isPaginatingKinds.contains(.bundleIds) {
                                viewModel.loadMore(.bundleIds, cursor: nextCursor)
                            }
                        }
                }
                Spacer()
            }
        }
    }
}

private func bundlePlatformDisplay(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else { return "—" }
    if let option = BundleIdPlatformOption(rawValue: raw) {
        return option.displayName
    }
    return shipyardPlatformDisplay(raw)
}
