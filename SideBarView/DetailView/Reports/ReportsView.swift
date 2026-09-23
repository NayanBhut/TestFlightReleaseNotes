//
//  ReportsView.swift
//  App Store
//
//  Batch J (F3): sales + finance report downloads. Form (vendor number,
//  report kind, filters, date) on the left, result state on the right.
//

import SwiftUI
import AppKit

struct ReportsView: View {
    @ObservedObject var reportsViewModel: ReportsViewModel
    var selectedApp: AppsData?

    var body: some View {
        Group {
            if selectedApp != nil {
                VStack(spacing: 0) {
                    header
                    Divider()
                    ScrollView {
                        HStack(alignment: .top, spacing: 16) {
                            formCard
                            resultCard
                        }
                        .padding(20)
                    }
                }
                .onAppear {
                    reportsViewModel.reset()
                }
            } else {
                EmptyStateView(icon: "chart.bar.doc.horizontal", title: "No App Selected",
                               subtitle: "Select an app from the sidebar to download reports")
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Reports")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Text("Sales & Finance (gzip)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var formCard: some View {
        InfoCard(title: "Report", systemImage: "doc.badge.gearshape") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Kind", selection: $reportsViewModel.kind) {
                    ForEach(ReportsViewModel.Kind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Report kind")

                labeled("Vendor Number") {
                    TextField("e.g. 12345678", text: $reportsViewModel.vendorNumber)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }
                Text("Find it in App Store Connect > Payments and Financial Reports.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if reportsViewModel.kind == .sales {
                    labeled("Report Type") {
                        Picker("Report Type", selection: $reportsViewModel.salesReportType) {
                            ForEach(ReportsViewModel.salesReportTypes, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                    labeled("Subtype") {
                        Picker("Subtype", selection: $reportsViewModel.salesSubType) {
                            ForEach(ReportsViewModel.salesSubTypes, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                    labeled("Frequency") {
                        Picker("Frequency", selection: $reportsViewModel.frequency) {
                            ForEach(ReportsViewModel.frequencies, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                } else {
                    labeled("Region Code") {
                        TextField("ZZ = worldwide", text: $reportsViewModel.regionCode)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .frame(maxWidth: 140)
                    }
                }

                labeled("Report Date") {
                    DatePicker("", selection: $reportsViewModel.reportDate, displayedComponents: .date)
                        .labelsHidden()
                }

                Button {
                    Task { await reportsViewModel.download() }
                } label: {
                    if case .downloading = reportsViewModel.state {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Download", systemImage: "arrow.down.circle")
                            .font(.caption)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled({
                    if case .downloading = reportsViewModel.state { return true }
                    return false
                }())
            }
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            content()
        }
    }

    private var resultCard: some View {
        InfoCard(title: "Result", systemImage: "tray.and.arrow.down") {
            switch reportsViewModel.state {
            case .idle:
                Text("Choose a report and press Download.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .downloading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Downloading…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case .saved(let url):
                VStack(alignment: .leading, spacing: 8) {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .textSelection(.enabled)
                    Text(url.deletingLastPathComponent().path)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        Task { await reportsViewModel.download() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
}

#Preview {
    ReportsView(reportsViewModel: ReportsViewModel(), selectedApp: nil)
}
