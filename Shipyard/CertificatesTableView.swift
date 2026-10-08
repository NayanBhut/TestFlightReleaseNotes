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
    @EnvironmentObject private var toastCenter: ShipyardToastCenter
    @State private var showCreateForm = false
    @State private var revoking: CertificateModel?
    @State private var detailCertificate: CertificateModel?
    @State private var bannerError: String?

    /// Module 12 bulk selection (Flow 12D): independent per-row DELETE /
    /// download over exactly the checked rows — never the whole list.
    @State private var selection: Set<String> = []
    @State private var showBulkDownload = false
    @State private var showBulkRevoke = false
    @State private var revokeConfirmation = ""
    @State private var ledger: [BulkLedgerItem] = []
    @State private var showBulkResult = false
    @State private var bulkReconciled = false
    @State private var downloadResults: [SigningFileResult] = []
    @State private var showDownloadResult = false
    @State private var isBulkWorking = false

    private var certificates: [CertificateModel] { viewModel.filteredCertificates }

    private var selectedCertificates: [CertificateModel] {
        certificates.filter { selection.contains($0.id) }
    }

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
            viewModel.load(.certificates)
        }
        .sheet(isPresented: $showCreateForm) {
            CreateCertificateForm(viewModel: viewModel) {
                showCreateForm = false
            }
        }
        .sheet(isPresented: Binding(
            get: { detailCertificate != nil },
            set: { if !$0 { detailCertificate = nil } }
        )) {
            if let certificate = detailCertificate {
                CertificateDetailSheet(certificate: certificate, viewModel: viewModel) {
                    detailCertificate = nil
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { revoking != nil },
            set: { if !$0 { revoking = nil } }
        )) {
            if let certificate = revoking {
                RevokeCertificateDialog(
                    certificateName: certificate.displayName ?? certificate.name ?? "certificate",
                    onCancel: { revoking = nil },
                    onRevoke: {
                        let target = certificate
                        revoking = nil
                        Task { @MainActor in
                            let result = await viewModel.revokeCertificate(id: target.id)
                            if case .success = result {
                                toastCenter.show("Certificate revoked", variant: .success)
                            }
                            if case .failure(let message) = result {
                                bannerError = message
                                toastCenter.show("Couldn't revoke certificate", detail: message, variant: .error)
                            }
                        }
                    }
                )
            }
        }
        // MARK: - Module 12 bulk sheets (Flow 12D)
        .sheet(isPresented: $showBulkDownload) {
            DownloadSigningFilesSheet(
                rows: selectedCertificates.map {
                    SigningDownloadRow(
                        id: $0.id,
                        rowLabel: "\(certificateTypeDisplayName($0.certificateType)) · \($0.serialNumber ?? "—")",
                        outputName: bulkCertificateFileName($0) + ".cer"
                    )
                },
                destination: "~/Downloads/Shipyard/Signing",
                onChooseDestination: {},
                onCancel: { showBulkDownload = false },
                onDownload: {
                    showBulkDownload = false
                    runBulkDownload()
                }
            )
        }
        .sheet(isPresented: $showBulkRevoke) {
            RevokeCertificatesSheet(
                certificates: selectedCertificates.map {
                    (serial: $0.serialNumber ?? "—",
                     type: certificateTypeDisplayName($0.certificateType),
                     affectedProfiles: affectedProfiles(for: $0.id))
                },
                confirmationText: "REVOKE \(selectedCertificates.count)",
                typedConfirmation: $revokeConfirmation,
                onCancel: { showBulkRevoke = false },
                onRevoke: {
                    showBulkRevoke = false
                    runBulkRevoke()
                }
            )
        }
        .sheet(isPresented: $showBulkResult) {
            BulkRevocationResultSheet(
                title: "Bulk revocation · partial result",
                bannerTitle: bulkBannerTitle,
                bannerBody: "Independent DELETE requests, not a signing operation. Do not repeat confirmed success. Resolve 403 access before retry; reconcile any unknown outcome first.",
                items: $ledger,
                isReconciled: bulkReconciled,
                onExport: exportLedger,
                onRefreshReconcile: {
                    viewModel.load(.certificates)
                    viewModel.load(.profiles)
                    bulkReconciled = true
                },
                onRetryUnknown: runBulkRetryUnknown,
                onDone: {
                    showBulkResult = false
                    selection = []
                }
            )
        }
        .sheet(isPresented: $showDownloadResult) {
            SigningDownloadResultSheet(
                results: downloadResults,
                destinationNote: "Original selected folder · per-file save panels",
                canRetryLocalWrite: downloadResults.contains { if case .failed = $0.writeResult { return true }; return false },
                onChooseWritableFolder: {},
                onExport: exportDownloadLedger,
                onRetryLocalWrite: retryFailedDownloads,
                onDone: {
                    showDownloadResult = false
                    selection = []
                }
            )
        }
    }

    // MARK: - Module 12 bulk execution

    private func bulkCertificateFileName(_ certificate: CertificateModel) -> String {
        let raw = certificate.displayName ?? certificate.name ?? "download"
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty ? "download" : trimmed).replacingOccurrences(of: "/", with: "-")
    }

    /// Profiles whose hydrated certificate links include this certificate.
    /// The list fetch does not always hydrate the relationship, so an empty
    /// result honestly means "refresh actual dependencies" — never "none".
    private func affectedProfiles(for certificateId: String) -> [String] {
        let profiles: [ProfileModel]
        if case .loaded(let loaded) = viewModel.profilesState {
            profiles = loaded
        } else {
            profiles = []
        }
        let matches = profiles.filter { $0.certificates.contains(where: { $0.id == certificateId }) }
        if matches.isEmpty {
            return ["Refresh actual dependencies"]
        }
        return matches.map { $0.name ?? "Untitled profile" }
    }

    private var bulkBannerTitle: String {
        let confirmed = ledger.filter { $0.outcome?.isConfirmed == true }.count
        let unknown = ledger.filter { if case .unknown = $0.outcome { return true }; return false }.count
        if unknown > 0 {
            return "\(confirmed) revocation confirmed · \(unknown) outcome unknown"
        }
        return "\(confirmed) revocation confirmed · \(ledger.count - confirmed) denied"
    }

    /// Sequential independent DELETEs. A 204 drops the row locally (the VM
    /// does that); every other outcome stays in the ledger with its guard.
    private func runBulkRevoke() {
        let targets = selectedCertificates
        guard !targets.isEmpty else { return }
        isBulkWorking = true
        bulkReconciled = false
        ledger = targets.map {
            BulkLedgerItem(
                id: $0.id,
                label: "Serial \($0.serialNumber ?? "—") · \(certificateTypeDisplayName($0.certificateType))",
                sublabel: "ID: \($0.id)",
                outcome: nil
            )
        }
        showBulkResult = true
        Task { @MainActor in
            for target in targets {
                let result = await viewModel.revokeCertificate(id: target.id)
                if let index = ledger.firstIndex(where: { $0.id == target.id }) {
                    switch result {
                    case .success:
                        ledger[index].outcome = .confirmed("DELETE 204 · no response body")
                    case .failure(let message):
                        ledger[index].outcome = BulkOutcomeClassification.classify(message: message)
                    case .ignored:
                        ledger[index].outcome = .unknown("Request ignored — reconcile before retry")
                    }
                }
            }
            isBulkWorking = false
            if ledger.allSatisfy({ $0.outcome?.isConfirmed == true }) {
                selection = []
                toastCenter.show("Certificates revoked", detail: "\(ledger.count) confirmed", variant: .success)
            }
        }
    }

    /// Retries only the unknown rows after Refresh / Reconcile unlocked
    /// them. Confirmed rows are never touched again.
    private func runBulkRetryUnknown() {
        let unknownIds = Set(ledger.filter { if case .unknown = $0.outcome { return true }; return false }.map(\.id))
        guard !unknownIds.isEmpty else { return }
        Task { @MainActor in
            for id in unknownIds {
                let result = await viewModel.revokeCertificate(id: id)
                if let index = ledger.firstIndex(where: { $0.id == id }) {
                    switch result {
                    case .success:
                        ledger[index].outcome = .confirmed("DELETE 204 · no response body")
                    case .failure(let message):
                        ledger[index].outcome = BulkOutcomeClassification.classify(message: message)
                    case .ignored:
                        break
                    }
                }
            }
        }
    }

    private func exportLedger() {
        LocalResultsExport.saveLedger(
            filename: "bulk-revocation-results.txt",
            lines: LocalResultsExport.lines(
                title: "Bulk revocation · partial result",
                scope: "Certificates",
                when: Date(),
                rows: ledger.map { ($0.label, $0.outcome?.detail ?? "No result") }
            )
        )
    }

    /// Sequential authenticated downloads (one save panel per file, same
    /// as the single-download path). Fetch and write stages stay separate
    /// in the result ledger.
    private func runBulkDownload() {
        let targets = selectedCertificates
        guard !targets.isEmpty else { return }
        downloadResults = targets.map {
            SigningFileResult(
                id: $0.id,
                outputName: bulkCertificateFileName($0) + ".cer",
                material: "Public certificate material",
                fetchStage: "Authenticated GET certificate",
                writeResult: nil
            )
        }
        showDownloadResult = true
        Task { @MainActor in
            for target in targets {
                let result = await viewModel.downloadCertificate(target)
                if let index = downloadResults.firstIndex(where: { $0.id == target.id }) {
                    switch result {
                    case .success:
                        downloadResults[index].writeResult = .saved
                    case .failure(let message):
                        downloadResults[index].writeResult = .failed(message)
                    case .ignored:
                        downloadResults[index].writeResult = .failed("Save panel cancelled — no file written")
                    }
                }
            }
        }
    }

    /// Retries only failed local writes; completed files are never
    /// re-downloaded.
    private func retryFailedDownloads() {
        let failedIds = Set(downloadResults.filter { if case .failed = $0.writeResult { return true }; return false }.map(\.id))
        let targets = selectedCertificates.filter { failedIds.contains($0.id) }
        Task { @MainActor in
            for target in targets {
                let result = await viewModel.downloadCertificate(target)
                if let index = downloadResults.firstIndex(where: { $0.id == target.id }) {
                    switch result {
                    case .success:
                        downloadResults[index].writeResult = .saved
                    case .failure(let message):
                        downloadResults[index].writeResult = .failed(message)
                    case .ignored:
                        break
                    }
                }
            }
        }
    }

    private func exportDownloadLedger() {
        LocalResultsExport.saveLedger(
            filename: "signing-download-results.txt",
            lines: LocalResultsExport.lines(
                title: "Signing downloads · local result",
                scope: "Certificates",
                when: Date(),
                rows: downloadResults.map { ($0.outputName, writeOutcomeText($0.writeResult)) }
            )
        )
    }

    private func writeOutcomeText(_ result: WriteStageResult?) -> String {
        switch result {
        case .saved: return "Saved locally"
        case .failed(let message): return "Local save failed — \(message)"
        case .none: return "Not attempted"
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
                if !selection.isEmpty {
                    Text("\(selection.count) selected")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.accent)
                    Button("Download") { showBulkDownload = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Revoke…") {
                        revokeConfirmation = ""
                        showBulkRevoke = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button("Clear") { selection = [] }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
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
        let hasSearch = viewModel.hasActiveSearch(for: .certificates)
        return VStack(spacing: 12) {
            Spacer()
            Text(hasSearch ? "No Matching Certificates" : "No Certificates")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            Text(hasSearch
                 ? "Try a different name, serial number, type, or platform."
                 : "Create a certificate to sign development and distribution builds")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
            if !hasSearch {
                Button("Create Certificate") {
                    showCreateForm = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Button {
                let visible = Set(certificates.map(\.id))
                selection = selection.isSuperset(of: visible) ? selection.subtracting(visible) : selection.union(visible)
            } label: {
                Image(systemName: certificates.allSatisfy { selection.contains($0.id) } && !certificates.isEmpty
                      ? "checkmark.square.fill" : "square")
                    .foregroundColor(ShipyardTheme.body)
            }
            .buttonStyle(.plain)
            .frame(width: 28, alignment: .leading)
            .accessibilityLabel("Select all certificates")
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
            Button {
                if selection.contains(certificate.id) {
                    selection.remove(certificate.id)
                } else {
                    selection.insert(certificate.id)
                }
            } label: {
                Image(systemName: selection.contains(certificate.id) ? "checkmark.square.fill" : "square")
                    .foregroundColor(selection.contains(certificate.id) ? ShipyardTheme.accent : ShipyardTheme.body)
            }
            .buttonStyle(.plain)
            .frame(width: 28, alignment: .leading)
            .accessibilityLabel("Select \(certificate.displayName ?? certificate.name ?? "certificate")")
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
                Circle()
                    .fill(status.color)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(status.text)
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.title)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .contentShape(Rectangle())
        .onTapGesture {
            detailCertificate = certificate
        }
        .contextMenu {
            Button("Open Details") {
                detailCertificate = certificate
            }
            .accessibilityLabel("Open details for \(certificate.displayName ?? certificate.name ?? "certificate")")
            Button("Download") {
                Task { @MainActor in
                    let result = await viewModel.downloadCertificate(certificate)
                    if case .success = result {
                        toastCenter.show("Certificate downloaded", variant: .success)
                    }
                    if case .failure(let message) = result {
                        bannerError = message
                        toastCenter.show("Couldn't download certificate", detail: message, variant: .error)
                    }
                }
            }
            .accessibilityLabel("Download \(certificate.displayName ?? certificate.name ?? "certificate")")
            Button("Revoke") {
                revoking = certificate
            }
            .accessibilityLabel("Revoke \(certificate.displayName ?? certificate.name ?? "certificate")")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(certificate.displayName ?? certificate.name ?? "certificate"), \(status.text). Open details")
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

// MARK: - Detail

private struct CertificateDetailSheet: View {
    let certificate: CertificateModel
    @ObservedObject var viewModel: ResourcesViewModel
    var onClose: () -> Void

    @EnvironmentObject private var toastCenter: ShipyardToastCenter
    @State private var detail: CertificateModel?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var currentCertificate: CertificateModel { detail ?? certificate }
    private var title: String {
        currentCertificate.displayName ?? currentCertificate.name ?? "Certificate"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Certificate Details")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    Text(title)
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                        .lineLimit(1)
                }
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.75)
                        Text("Loading latest certificate details…")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                    }
                }

                if let errorMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppTheme.negative)
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.negative)
                    }
                    Button("Retry") {
                        loadDetail()
                    }
                    .controlSize(.small)
                }

                detailRow("Name", currentCertificate.name)
                detailRow("Display Name", currentCertificate.displayName)
                detailRow("Type", certificateTypeDisplayName(currentCertificate.certificateType))
                detailRow("Platform", currentCertificate.platform)
                detailRow("Serial Number", currentCertificate.serialNumber, monospaced: true)
                detailRow("Expiration Date", certificateExpiryDisplay(currentCertificate.expirationDate))
                detailRow("Status", certificateStatus(currentCertificate).text)
                detailRow("Activated", activatedText(currentCertificate.activated))
                detailRow("Certificate ID", currentCertificate.id, monospaced: true)
                detailRow("Certificate Content", certificateContentText)
            }
            .padding(20)

            Divider()

            HStack {
                Text("Content is fetched with the detail endpoint; Download still asks where to save the .cer file.")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                Spacer()
                Button("Download .cer") {
                    Task { @MainActor in
                        let result = await viewModel.downloadCertificate(currentCertificate)
                        if case .success = result {
                            toastCenter.show("Certificate downloaded", variant: .success)
                        }
                        if case .failure(let message) = result {
                            errorMessage = message
                            toastCenter.show("Couldn't download certificate", detail: message, variant: .error)
                        }
                    }
                }
                .controlSize(.small)
            }
            .padding(20)
        }
        .frame(width: 620)
        .background(LaunchTheme.page)
        .task {
            await fetchDetail()
        }
    }

    private var certificateContentText: String {
        guard let content = detail?.certificateContent else {
            return detail == nil ? "Loading…" : "Not returned"
        }
        return content.isEmpty ? "Not returned" : "Available (\(content.count) base64 characters)"
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String?, monospaced: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(ShipyardTheme.body)
                .frame(width: 140, alignment: .leading)
            Text(value?.isEmpty == false ? value! : "—")
                .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 12))
                .foregroundColor(ShipyardTheme.title)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func activatedText(_ activated: Bool?) -> String {
        guard let activated else { return "Unknown" }
        return activated ? "Yes" : "No"
    }

    private func loadDetail() {
        Task { await fetchDetail() }
    }

    @MainActor
    private func fetchDetail() async {
        isLoading = true
        errorMessage = nil
        let result = await viewModel.fetchCertificateDetail(id: certificate.id)
        isLoading = false
        switch result {
        case .value(let model):
            detail = model
        case .failure(let message):
            errorMessage = message
            toastCenter.show("Couldn't load certificate details", detail: message, variant: .error)
        case .ignored:
            break
        }
    }
}

// MARK: - Display helpers

private struct CertificateStatus {
    let color: Color
    let text: String
}

/// Active (usable), Expiring Soon (<30 days), Expired, or Revoked
/// (deactivated). The API carries no revoked flag — a deactivated,
/// unexpired certificate reads as revoked. Dots match the Profiles
/// table: green usable, amber expiring, red dead.
private func certificateStatus(_ certificate: CertificateModel) -> CertificateStatus {
    if certificate.activated == false {
        return CertificateStatus(color: ShipyardTheme.danger, text: "Revoked")
    }
    guard let expiry = sharedCertificateExpiryDate(certificate.expirationDate) else {
        return CertificateStatus(color: ShipyardTheme.success, text: "Active")
    }
    if expiry < Date() {
        return CertificateStatus(color: ShipyardTheme.danger, text: "Expired")
    }
    if let soon = Calendar.current.date(byAdding: .day, value: 30, to: Date()), expiry < soon {
        return CertificateStatus(color: ShipyardTheme.warning, text: "Expiring Soon")
    }
    return CertificateStatus(color: ShipyardTheme.success, text: "Active")
}

/// "Sep 28, 2026"; unparseable values pass through untouched.
/// Shared with the profile wizard (same module).
func certificateExpiryDisplay(_ raw: String?) -> String {
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
/// Shared with the profile wizard (same module).
func certificateTypeDisplayName(_ raw: String?) -> String {
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
