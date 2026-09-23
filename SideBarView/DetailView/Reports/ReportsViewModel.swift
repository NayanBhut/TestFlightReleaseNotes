//
//  ReportsViewModel.swift
//  App Store
//
//  Batch J (F3): sales + finance report downloads. Both endpoints return
//  application/a-gzip (raw bytes, NOT JSON:API) — data goes straight to
//  disk, never through the JSONAPI decoder. filter[vendorNumber] is
//  required in practice; it is persisted per team because the API never
//  returns it (the user copies it from App Store Connect > Payments).
//

import SwiftUI
import OSLog
import AppKit
import UniformTypeIdentifiers

private let reportsLogger = Logger(subsystem: "com.appstore.release-notes", category: "Reports")

@MainActor
final class ReportsViewModel: ObservableObject {
    enum Kind: String, CaseIterable, Identifiable {
        case sales = "Sales"
        case finance = "Finance"
        var id: String { rawValue }
    }

    /// Spec-verified enums (sales reportType/frequency, finance reportType).
    static let salesReportTypes = ["SALES", "PRE_ORDER", "NEWSSTAND"]
    static let salesSubTypes = ["SUMMARY", "DETAILED", "SUMMARY_INSTALL_TYPE", "SUMMARY_TERRITORY", "SUMMARY_CHANNEL"]
    static let frequencies = ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"]
    static let financeReportType = "FINANCIAL"

    enum State: Equatable {
        case idle
        case downloading
        case saved(URL)
        case failed(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.downloading, .downloading):
                return true
            case (.saved(let a), .saved(let b)):
                return a == b
            case (.failed(let a), .failed(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    @Published var kind: Kind = .sales
    @Published var vendorNumber: String = ""
    @Published var salesReportType = salesReportTypes[0]
    @Published var salesSubType = salesSubTypes[0]
    @Published var frequency = frequencies[0]
    /// Finance only; "ZZ" = worldwide (Apple's documented default region).
    @Published var regionCode = "ZZ"
    @Published var reportDate = Date()
    @Published private(set) var state: State = .idle

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var vendorKey: String {
        "vendorNumber_\(CredentialStorage.shared.selectedTeam?.key ?? "default")"
    }

    func loadVendorNumber() {
        vendorNumber = UserDefaults.standard.string(forKey: vendorKey) ?? ""
    }

    func reset() {
        state = .idle
        loadVendorNumber()
    }

    /// Downloads the report and asks where to save it. The vendor number
    /// is persisted per team on every attempt (even failed ones — a typo'd
    /// number that 400s is still what the user typed).
    func download() async {
        let vendor = vendorNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vendor.isEmpty else {
            state = .failed("Enter your vendor number first (App Store Connect > Payments and Financial Reports).")
            return
        }
        UserDefaults.standard.set(vendor, forKey: vendorKey)
        state = .downloading

        let dateString = Self.dateFormatter.string(from: reportDate)
        let queryParams: [String: String]
        let apiName: APIName
        let filePrefix: String
        switch kind {
        case .sales:
            apiName = .salesReports
            filePrefix = "sales"
            queryParams = [
                "filter[vendorNumber]": vendor,
                "filter[reportType]": salesReportType,
                "filter[reportSubType]": salesSubType,
                "filter[frequency]": frequency,
                "filter[reportDate]": dateString,
                "filter[version]": "1_0",
            ]
        case .finance:
            apiName = .financeReports
            filePrefix = "finance"
            var params = [
                "filter[vendorNumber]": vendor,
                "filter[reportType]": Self.financeReportType,
                "filter[reportDate]": dateString,
            ]
            let region = regionCode.trimmingCharacters(in: .whitespacesAndNewlines)
            if !region.isEmpty {
                params["filter[regionCode]"] = region
            }
            queryParams = params
        }

        guard let request = APIClient.shared.getRequest(
            api: .get(name: apiName, queryParams: queryParams),
            apiVersion: .v1) else {
            state = .failed("No team selected. Add a team to download reports.")
            return
        }

        do {
            let data = try await APIClient.shared.callAPI(with: request)
            guard !Task.isCancelled else { return }
            guard !data.isEmpty else {
                state = .failed("The report came back empty — the date may have no data yet.")
                return
            }
            saveDownloaded(data: data, filePrefix: filePrefix, dateString: dateString)
        } catch {
            guard !Task.isCancelled else { return }
            reportsLogger.error("Report download failed: \(error.localizedDescription)")
            if let apiError = error as? APIError, apiError.statusCode == 403 {
                state = .failed("\(apiError.details) — reports need an API key with Finance access.")
            } else if let apiError = error as? APIError {
                state = .failed(apiError.details)
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func saveDownloaded(data: Data, filePrefix: String, dateString: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(filePrefix)-\(dateString).txt.gz"
        panel.canCreateDirectories = true
        if let gzType = UTType(filenameExtension: "gz") {
            panel.allowedContentTypes = [gzType]
        }
        guard panel.runModal() == .OK, let url = panel.url else {
            // User cancelled the save dialog — back to idle, bytes dropped.
            state = .idle
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            state = .saved(url)
        } catch {
            state = .failed("Couldn't write the file: \(error.localizedDescription)")
        }
    }
}
