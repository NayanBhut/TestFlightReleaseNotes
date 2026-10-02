//
//  MonitoringView.swift
//  App Store
//
//  Processing-builds monitoring section: live rows from
//  BuildProcessingMonitor (the same source as the menu-bar monitor).
//  There is no Figma screen for this section, so rows follow the builds
//  table pattern.
//

import SwiftUI

struct MonitoringView: View {
    @ObservedObject var monitor: BuildProcessingMonitor
    @State private var isChecking = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShipyardTheme.tableBackground)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("Processing Builds")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            ShipyardCountPill(text: "\(monitor.processingBuilds.count)")
            Spacer()
            if isChecking {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Button("Check Now") {
                    Task {
                        isChecking = true
                        defer { isChecking = false }
                        await monitor.pollNow()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(LaunchTheme.page)
    }

    @ViewBuilder
    private var content: some View {
        if monitor.processingBuilds.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                ShipyardIcon(name: "ShipyardMonitorX", size: 32)
                Text("No Processing Builds")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                Text("New uploads appear here while Apple processes them")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.body)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    headerRow
                    ForEach(monitor.processingBuilds) { build in
                        HStack(spacing: 12) {
                            Text(build.appName.isEmpty ? "Unknown App" : build.appName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(ShipyardTheme.title)
                                .lineLimit(1)
                                .frame(width: 220, alignment: .leading)
                            Text(build.marketingVersion.map { "v\($0)" } ?? "—")
                                .font(.system(size: 12))
                                .foregroundColor(ShipyardTheme.body)
                                .frame(width: 100, alignment: .leading)
                            Text(build.buildNumber.isEmpty ? "—" : "#\(build.buildNumber)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(ShipyardTheme.title)
                                .frame(width: 100, alignment: .leading)
                            Text(build.uploadedDate ?? "—")
                                .font(.system(size: 12))
                                .foregroundColor(ShipyardTheme.body)
                                .frame(width: 180, alignment: .leading)
                            HStack(spacing: 6) {
                                ShipyardIcon(name: "ShipyardBuildX")
                                Text("Processing…")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(ShipyardTheme.accent)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        ShipyardTheme.rowDivider.frame(height: 1)
                    }
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Text("App").frame(width: 220, alignment: .leading)
            Text("Version").frame(width: 100, alignment: .leading)
            Text("Build").frame(width: 100, alignment: .leading)
            Text("Uploaded").frame(width: 180, alignment: .leading)
            Text("State").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(ShipyardTheme.body)
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(ShipyardTheme.tableHeader)
    }
}
