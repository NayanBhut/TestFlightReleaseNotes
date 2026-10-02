//
//  CertificatesTableView.swift
//  App Store
//
//  Certificates table from the certificates-light Figma frame: toolbar
//  (title + total pill, search, Create Certificate) over a Name / Type /
//  Serial Number / Expiration Date / Status table. Revocation runs from the
//  row context menu with a confirmation (destructive); creation reuses the
//  shared CreateCertificateForm.
//

import SwiftUI

struct CertificatesTableView: View {
    @ObservedObject var viewModel: ResourcesViewModel
    @State private var showCreateForm = false
    @State private var revoking: CertificateModel?
    @State private var bannerError: String?

    private var certificates: [CertificateModel] { viewModel.filteredCertificates }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if showCreateForm {
                CreateCertificateForm(viewModel: viewModel) {
                    showCreateForm = false
                }
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
            viewModel.load(.certificates)
        }
        .confirmationDialog(
            "Revoke this certificate? Provisioning profiles using it stop working.",
            isPresented: Binding(
                get: { revoking != nil },
                set: { if !$0 { revoking = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Revoke Certificate", role: .destructive) {
                guard let certificate = revoking else { return }
                Task { @MainActor in
                    if case .failure(let message) = await viewModel.revokeCertificate(id: certificate.id) {
                        bannerError = message
                    }
                    revoking = nil
                }
            }
            Button("Cancel", role: .cancel) {
                revoking = nil
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Certificates")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                ShipyardCountPill(text: totalText)
            }

            Spacer()

            ShipyardSearchField(prompt: "Search Certificates", text: viewModel.searchBinding(for: .certificates))

            Button("Create Certificate") {
                showCreateForm.toggle()
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(ShipyardTheme.accent)
            .cornerRadius(6)
            .buttonStyle(.plain)
            .accessibilityLabel("Create a certificate")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(LaunchTheme.page)
    }

    private var totalText: String {
        if let total = viewModel.totals[.certificates] {
            return "\(total) Total"
        }
        return "\(viewModel.loadedCount(for: .certificates)) Total"
    }

    // MARK: - Table

    @ViewBuilder
    private var table: some View {
        switch viewModel.certificatesState {
        case .idle, .loading:
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                Text("Loading certificates…")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.body)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            ErrorRetryView(
                title: "Couldn't Load Certificates",
                message: message,
                retryTitle: "Retry",
                onRetry: { viewModel.retry(.certificates) }
            )
        default:
            if certificates.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        headerRow
                        ForEach(certificates, id: \.id) { certificate in
                            certificateRow(certificate)
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
            Text("No Certificates")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            Text("Create a certificate to sign development and distribution builds")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
            Button("Create Certificate") {
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
            Text("Type").frame(width: 180, alignment: .leading)
            Text("Serial Number").frame(width: 140, alignment: .leading)
            Text("Expiration Date").frame(width: 160, alignment: .leading)
            Text("Status").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(ShipyardTheme.body)
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(ShipyardTheme.tableHeader)
    }

    private func certificateRow(_ certificate: CertificateModel) -> some View {
        let status = certificateStatus(certificate)
        return HStack(spacing: 12) {
            Text(certificate.displayName ?? certificate.name ?? "Unknown certificate")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 240, alignment: .leading)

            Text(certificateTypeDisplayName(certificate.certificateType))
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.title)
                .lineLimit(1)
                .frame(width: 180, alignment: .leading)

            Text(certificate.serialNumber ?? "—")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(ShipyardTheme.body)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)

            Text(certificateExpiryDisplay(certificate.expirationDate))
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
                .frame(width: 160, alignment: .leading)

            HStack(spacing: 6) {
                ShipyardIcon(name: status.iconName)
                Text(status.text)
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.title)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Revoke") {
                revoking = certificate
            }
            .accessibilityLabel("Revoke \(certificate.displayName ?? certificate.name ?? "certificate")")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(certificate.displayName ?? certificate.name ?? "certificate"), \(status.text)")
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if let nextCursor = viewModel.nextCursors[.certificates] {
            HStack {
                Spacer()
                if viewModel.paginationFailedKinds.contains(.certificates) {
                    Button("Couldn't load more — Retry") {
                        viewModel.loadMore(.certificates, cursor: nextCursor)
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
                            if !viewModel.isPaginatingKinds.contains(.certificates) {
                                viewModel.loadMore(.certificates, cursor: nextCursor)
                            }
                        }
                }
                Spacer()
            }
        }
    }
}

// MARK: - Display helpers

private struct CertificateStatus {
    let iconName: String
    let text: String
}

/// Active (usable), Expiring Soon (<30 days), Expired, or Revoked
/// (deactivated). The API carries no revoked flag — a deactivated,
/// unexpired certificate reads as revoked.
private func certificateStatus(_ certificate: CertificateModel) -> CertificateStatus {
    if certificate.activated == false {
        return CertificateStatus(iconName: "ShipyardCertMinus", text: "Revoked")
    }
    guard let expiry = sharedCertificateExpiryDate(certificate.expirationDate) else {
        return CertificateStatus(iconName: "ShipyardCertOk", text: "Active")
    }
    if expiry < Date() {
        return CertificateStatus(iconName: "ShipyardCertX", text: "Expired")
    }
    if let soon = Calendar.current.date(byAdding: .day, value: 30, to: Date()), expiry < soon {
        return CertificateStatus(iconName: "ShipyardCertWarn", text: "Expiring Soon")
    }
    return CertificateStatus(iconName: "ShipyardCertOk", text: "Active")
}

/// "Sep 28, 2026"; unparseable values pass through untouched.
private func certificateExpiryDisplay(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else { return "—" }
    if let date = sharedCertificateExpiryDate(raw) {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    return raw
}

private let sharedCertificateExpiryFractional: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
}()

private let sharedCertificateExpiryPlain: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
}()

private func sharedCertificateExpiryDate(_ raw: String?) -> Date? {
    guard let raw, !raw.isEmpty else { return nil }
    return sharedCertificateExpiryFractional.date(from: raw)
        ?? sharedCertificateExpiryPlain.date(from: raw)
}

/// Full type names ("IOS_DEVELOPMENT" → "iOS Development"); unknown codes
/// are prettified with the same iOS/ID/NFC fixes as the picker.
private func certificateTypeDisplayName(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else { return "—" }
    if let option = CertificateTypeOption(rawValue: raw) {
        return option.displayName
    }
    return raw
        .replacingOccurrences(of: "_", with: " ")
        .capitalized
        .replacingOccurrences(of: "Ios", with: "iOS")
        .replacingOccurrences(of: "Id ", with: "ID ")
        .replacingOccurrences(of: "Nfc", with: "NFC")
        .replacingOccurrences(of: "Mac ", with: "Mac ")
}
