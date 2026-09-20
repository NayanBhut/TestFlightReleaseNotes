//
//  ResourcesView.swift
//  App Store
//
//  Batch C2: team-scoped Resources section in the sidebar (like AppDab's
//  Resources group), shown below the apps list when the extended-info flag
//  is on. Tapping a kind opens a sheet with the read-only list. Create /
//  revoke is a follow-up.
//

import SwiftUI

/// Sidebar section listing the five team-scoped resource kinds.
struct ResourcesSectionView: View {
    @ObservedObject var viewModel: ResourcesViewModel
    @State private var isExpanded = false
    @State private var selectedKind: ResourcesViewModel.Kind?

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 2) {
                ForEach(ResourcesViewModel.Kind.allCases) { kind in
                    Button {
                        selectedKind = kind
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: kind.systemImage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 16)
                            Text(kind.displayName)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(kind.displayName)")
                }
            }
            .padding(.top, 2)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Resources")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("Team-wide")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(item: $selectedKind) { kind in
            ResourceListContentView(kind: kind, viewModel: viewModel)
        }
    }
}

/// Read-only list for a single resource kind, with cursor pagination.
struct ResourceListContentView: View {
    let kind: ResourcesViewModel.Kind
    @ObservedObject var viewModel: ResourcesViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 480, minHeight: 420)
        .onAppear {
            viewModel.load(kind)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label(kind.displayName, systemImage: kind.systemImage)
                .font(.title3)
                .fontWeight(.semibold)
            Spacer()
            if let total = viewModel.totals[kind] {
                Text("\(total) total")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Button(action: { viewModel.retry(kind) }) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Refresh \(kind.displayName)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch listState.state {
        case .idle, .loading:
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                    .scaleEffect(1.1)
                Text("Loading \(kind.displayName.lowercased())...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        case .empty:
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: kind.systemImage)
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("No \(kind.displayName.lowercased()) found")
                    .font(.headline)
                Text(kind.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        case .error(let message):
            ErrorRetryView(
                title: "Couldn't Load \(kind.displayName)",
                message: message,
                retryTitle: "Retry"
            ) {
                viewModel.retry(kind)
            }
        case .loaded:
            ScrollView {
                VStack(spacing: 0) {
                    rows
                    paginationFooter
                }
                .padding(12)
            }
        }
    }

    @ViewBuilder private var rows: some View {
        switch kind {
        case .devices:
            ForEach(viewModel.devicesState.loadedValue ?? [], id: \.id) { device in
                DeviceRow(device: device)
            }
        case .certificates:
            ForEach(viewModel.certificatesState.loadedValue ?? [], id: \.id) { certificate in
                CertificateRow(certificate: certificate)
            }
        case .bundleIds:
            ForEach(viewModel.bundleIdsState.loadedValue ?? [], id: \.id) { bundleId in
                BundleIdRow(bundleId: bundleId)
            }
        case .profiles:
            ForEach(viewModel.profilesState.loadedValue ?? [], id: \.id) { profile in
                ProfileRow(profile: profile)
            }
        case .users:
            ForEach(viewModel.usersState.loadedValue ?? [], id: \.id) { user in
                UserRow(user: user)
            }
        }
    }

    /// Type-erased access to the kind's ViewState for the switch above.
    private var listState: ViewStateListState {
        switch kind {
        case .devices: return ViewStateListState(viewModel.devicesState)
        case .certificates: return ViewStateListState(viewModel.certificatesState)
        case .bundleIds: return ViewStateListState(viewModel.bundleIdsState)
        case .profiles: return ViewStateListState(viewModel.profilesState)
        case .users: return ViewStateListState(viewModel.usersState)
        }
    }

    @ViewBuilder private var paginationFooter: some View {
        if let nextCursor = viewModel.nextCursors[kind] {
            HStack {
                Spacer()
                if viewModel.paginationFailedKinds.contains(kind) {
                    Button("Couldn't load more — Retry") {
                        viewModel.loadMore(kind, cursor: nextCursor)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button("Load more") {
                        viewModel.loadMore(kind, cursor: nextCursor)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }
}

/// Minimal type-erased ViewState for the shared list shell — enough to
/// drive idle/loading/empty/error/loaded rendering without duplicating the
/// switch per kind.
struct ViewStateListState {
    enum State {
        case idle
        case loading
        case empty
        case loaded
        case error(String)
    }

    let state: State

    init<T>(_ viewState: ViewState<T>) {
        switch viewState {
        case .idle: state = .idle
        case .loading: state = .loading
        case .empty: state = .empty
        case .error(let message): state = .error(message)
        case .loaded: state = .loaded
        }
    }
}

// MARK: - Rows

private struct DeviceRow: View {
    let device: DeviceModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "iphone")
                .font(.caption)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.name ?? "Unknown device")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    StateChip(text: device.status ?? "")
                }
                Text(device.model ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(device.udid ?? "")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(device.deviceClass ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(device.platform ?? "")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

private struct CertificateRow: View {
    let certificate: CertificateModel

    private static let expiryParser = ISO8601DateFormatter()
    /// App Store Connect returns fractional seconds on some endpoints;
    /// the plain parser silently fails on those, so try it as a fallback.
    private static let expiryParserFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private var isExpired: Bool {
        guard let date = certificate.expirationDate else { return false }
        let parsed = Self.expiryParserFractional.date(from: date) ?? Self.expiryParser.date(from: date)
        return parsed.map { $0 < Date() } ?? false
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.caption)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(certificate.displayName ?? certificate.name ?? "Unknown certificate")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if certificate.activated == true {
                        StateChip(text: "ACTIVE")
                    }
                }
                Text("Serial: \(certificate.serialNumber ?? "—")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                Text("Expires: \(certificate.expirationDate ?? "—")")
                    .font(.caption2)
                    .foregroundColor(isExpired ? .red : .secondary)
            }
            Spacer()
            Text(certificate.certificateType ?? "")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

private struct BundleIdRow: View {
    let bundleId: BundleIdModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.caption)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(bundleId.name ?? "Unknown identifier")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(bundleId.identifier ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Text(bundleId.platform ?? "")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

private struct ProfileRow: View {
    let profile: ProfileModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.text.rectangle")
                .font(.caption)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile.name ?? "Unknown profile")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    StateChip(text: profile.profileState ?? "")
                }
                Text("UUID: \(profile.uuid ?? "—")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Expires: \(profile.expirationDate ?? "—")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(profile.profileType ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(profile.platform ?? "")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

private struct UserRow: View {
    let user: UserModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle")
                .font(.caption)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.username ?? "Unknown user")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .textSelection(.enabled)
                Text("\(user.firstName ?? "") \(user.lastName ?? "")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    ForEach(user.roles ?? [], id: \.self) { role in
                        Text(role)
                            .font(.system(size: 9, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(4)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if user.allAppsVisible == true {
                    Text("All apps")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if user.provisioningAllowed == true {
                    Text("Provisioning")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

#Preview {
    ResourcesSectionView(viewModel: ResourcesViewModel())
        .frame(width: 240)
}
