import SwiftUI
import AppKit

struct BetaFeedbackView: View {
    let appID: String
    let contextID: Int
    @StateObject private var model: BetaFeedbackViewModel

    init(appID: String, contextID: Int, api: BetaFeedbackAPI = .live) {
        self.appID = appID
        self.contextID = contextID
        _model = StateObject(wrappedValue: BetaFeedbackViewModel(api: api))
    }

    private var loadID: String { "\(appID):\(contextID):\(model.kind.rawValue)" }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            if let error = model.page.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error + (model.page.items.isEmpty ? "" : " Previously loaded feedback is still shown."))
                    Spacer()
                    Button("Retry") { Task { await model.load(refresh: true) } }
                        .disabled(model.page.isLoading)
                }
                .font(.system(size: 12))
                .padding(12)
                .background(Color.orange.opacity(0.1))
            }
            HSplitView {
                feedbackList.frame(minWidth: 250, idealWidth: 310, maxWidth: 390)
                Group {
                    if let selected = model.selected {
                        BetaFeedbackDetail(item: selected, logState: model.logState, api: model.api,
                            refresh: { Task { await model.load(refresh: true) } },
                            retryLog: { Task { await model.loadLog() } })
                    } else {
                        placeholder("Select feedback", detail: "Choose a submission to see the tester’s note and attachments.")
                    }
                }
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Text("\(model.filteredItems.count) shown · \(model.page.items.count) loaded" +
                     (model.page.total.map { " of \($0)" } ?? ""))
                Text("Filters search loaded feedback.").foregroundStyle(.secondary)
                Spacer()
                if model.page.isLoading { ProgressView().controlSize(.small) }
                if model.page.nextCursor != nil {
                    Button(model.page.error == nil ? "Load More" : "Retry Load More") {
                        Task { await model.load(more: true) }
                    }
                    .disabled(model.page.isLoading)
                    .accessibilityIdentifier("feedback.load-more")
                }
            }
            .font(.system(size: 11))
            .padding(12)
        }
        .font(.system(size: 13))
        .task(id: loadID) {
            model.activate(appID: appID, contextID: contextID)
            await model.load()
        }
        .task(id: model.selectedID) { await model.loadLog() }
        .onChange(of: model.filteredItems.map(\.id)) { _, visibleIDs in
            if let selected = model.selectedID, !visibleIDs.contains(selected) { model.select(nil) }
        }
        .onDisappear { model.cancel() }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("Feedback type", selection: Binding(get: { model.kind }, set: { model.switchKind($0) })) {
                ForEach(BetaFeedbackKind.allCases) { kind in
                    Text(kind.title).lineLimit(1).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("feedback.kind")

            TextField("Search notes, testers, builds…", text: $model.search)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120, maxWidth: .infinity)
                .accessibilityIdentifier("feedback.search")

            Menu {
                Picker("Build", selection: $model.buildFilter) {
                    Text("All builds").tag("")
                    ForEach(model.builds, id: \.id) { Text($0.label).tag($0.id) }
                }
                Picker("Platform", selection: $model.platformFilter) {
                    Text("All platforms").tag("")
                    ForEach(model.platforms, id: \.self) { platform in
                        Text(AppStoreVersionPlatform(rawValue: platform)?.displayName ?? platform).tag(platform)
                    }
                }
                if !model.buildFilter.isEmpty || !model.platformFilter.isEmpty {
                    Divider()
                    Button("Clear Filters") { model.buildFilter = ""; model.platformFilter = "" }
                }
            } label: {
                Label("Filters", systemImage: "line.3.horizontal.decrease")
                    .foregroundStyle(model.buildFilter.isEmpty && model.platformFilter.isEmpty
                        ? ShipyardTheme.body : ShipyardTheme.accent)
            }
            .fixedSize()
            .help("Filter loaded feedback by build and platform")
            .accessibilityIdentifier("feedback.filters")

            Button { Task { await model.load(refresh: true) } } label: {
                Label("Refresh Feedback", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .disabled(model.page.isLoading)
            .help("Refresh feedback")
            .accessibilityIdentifier("feedback.refresh")
        }
        .font(.system(size: 13))
        .controlSize(.small)
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(LaunchTheme.page)
    }

    private var feedbackList: some View {
        Group {
            if model.page.isLoading && model.page.items.isEmpty {
                VStack(spacing: 12) { ProgressView(); Text("Loading feedback…") }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.page.items.isEmpty {
                placeholder(model.page.error == nil ? "No \(model.kind.title.lowercased()) yet" : "Couldn’t load feedback",
                            detail: "Tester submissions for this app will appear here. Use Refresh to check again.")
            } else if model.filteredItems.isEmpty {
                VStack(spacing: 12) {
                    placeholder("No matches", detail: "Try another search or load more feedback.")
                    Button("Clear Filters") { model.clearFilters() }.padding(.bottom, 24)
                }
            } else {
                List(selection: Binding(get: { model.selectedID }, set: { model.select($0) })) {
                    ForEach(model.filteredItems) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.note).font(.system(size: 13, weight: .medium)).lineLimit(2)
                            Text(item.tester).lineLimit(1)
                            Text([item.buildLabel, item.attributes.deviceModel].compactMap { $0 }.joined(separator: " · "))
                                .foregroundStyle(.secondary).lineLimit(1)
                            if let date = item.createdDate {
                                Text(date, format: .dateTime.month().day().hour().minute()).foregroundStyle(.secondary)
                            }
                        }
                        .font(.system(size: 11))
                        .padding(.vertical, 8)
                        .tag(item.id)
                        .accessibilityIdentifier("feedback.row.\(item.submissionID)")
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(ShipyardTheme.tableBackground)
            }
        }
        .accessibilityIdentifier("feedback.list")
    }

    private func placeholder(_ title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BetaFeedbackDetail: View {
    let item: BetaFeedbackItem
    let logState: BetaFeedbackViewModel.LogState
    let api: BetaFeedbackAPI
    let refresh: () -> Void
    let retryLog: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(item.tester).font(.system(size: 18, weight: .semibold))
                Text(item.note).textSelection(.enabled).accessibilityIdentifier("feedback.note")
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    detail("Email", item.email)
                    detail("Submitted", item.createdDate?.formatted(date: .abbreviated, time: .shortened))
                    detail("Build", item.buildLabel)
                    detail("Device", item.attributes.deviceModel)
                    detail("OS", item.attributes.osVersion)
                    detail("App platform", item.attributes.appPlatform)
                    detail("Device platform", item.attributes.devicePlatform)
                    detail("Locale", item.attributes.locale)
                    detail("Time zone", item.attributes.timeZone)
                    detail("Architecture", item.attributes.architecture)
                    detail("Connection", item.attributes.connectionType)
                    detail("Apple Watch", item.attributes.pairedAppleWatch)
                    detail("App uptime", item.attributes.appUptimeInMilliseconds.map { "\($0 / 1000) seconds" })
                    detail("Battery", item.attributes.batteryPercentage.map { "\($0)%" })
                    detail("Disk available", item.attributes.diskBytesAvailable.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) })
                    detail("Disk total", item.attributes.diskBytesTotal.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) })
                    detail("Screen", screenSize)
                    detail("Bundle ID", item.attributes.buildBundleId)
                }
                Divider()
                if item.kind == .screenshots {
                    Text("Screenshots").font(.system(size: 13, weight: .semibold))
                    if let images = item.attributes.screenshots, !images.isEmpty {
                        ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                            BetaFeedbackImage(attachment: image, api: api, refresh: refresh)
                        }
                    } else {
                        Text("No screenshots attached.").foregroundStyle(.secondary)
                    }
                } else { crashLog }
            }
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }.id(item.id)
    }

    private var screenSize: String? {
        guard let w = item.attributes.screenWidthInPoints, let h = item.attributes.screenHeightInPoints else { return nil }
        return "\(w) × \(h) points"
    }
    @ViewBuilder private func detail(_ name: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            GridRow {
                Text(name).foregroundStyle(.secondary)
                Text(value).textSelection(.enabled)
            }
        }
    }
    private var crashLog: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Crash Log").font(.system(size: 13, weight: .semibold))
                Spacer()
                if case .loaded(let text?) = logState, !text.isEmpty {
                    Button("Copy Log") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }.accessibilityIdentifier("feedback.copy-log")
                }
            }
            switch logState {
            case .idle, .loading: ProgressView("Loading crash log…").controlSize(.small)
            case .loaded(let text):
                if let text, !text.isEmpty {
                    ScrollView(.horizontal) {
                        Text(text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            .accessibilityIdentifier("feedback.crash-log")
                    }
                } else { Text("No crash log is available for this submission.").foregroundStyle(.secondary) }
            case .failed(let message):
                Text(message).foregroundStyle(.secondary)
                Button("Retry Crash Log", action: retryLog)
            }
        }
    }
}

private struct BetaFeedbackImage: View {
    let attachment: BetaFeedbackScreenshot
    let api: BetaFeedbackAPI
    let refresh: () -> Void
    @State private var image: NSImage?
    @State private var failed = false
    @State private var attempt = 0
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if attachment.isExpired() {
                Text("This screenshot link has expired.").foregroundStyle(.secondary)
                Button("Refresh Feedback for New Links", action: refresh)
            } else if let image {
                Button { expanded = true } label: {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 350)
                }.buttonStyle(.plain)
                    .accessibilityLabel("Enlarge tester screenshot")
                    .accessibilityIdentifier("feedback.screenshot")
            } else if failed || attachment.secureURL == nil {
                Text("Screenshot unavailable. Refresh feedback if the link has expired.").foregroundStyle(.secondary)
                HStack {
                    Button("Retry Image") { attempt += 1 }.disabled(attachment.secureURL == nil)
                    Button("Refresh Feedback", action: refresh)
                }
            } else { ProgressView("Loading screenshot…").controlSize(.small) }
        }
        .task(id: "\(attachment.id):\(attempt)") {
            image = nil
            failed = false
            guard !attachment.isExpired(), let url = attachment.secureURL else { return }
            do {
                let data = try await api.screenshot(url)
                try Task.checkCancellation()
                guard let decoded = NSImage(data: data) else { throw URLError(.cannotDecodeContentData) }
                image = decoded
            } catch { if !Task.isCancelled { failed = true } }
        }
        .sheet(isPresented: $expanded) {
            VStack {
                if let image { Image(nsImage: image).resizable().scaledToFit() }
                Button("Done") { expanded = false }.keyboardShortcut(.cancelAction)
            }.padding(20).frame(minWidth: 600, minHeight: 500)
        }
    }
}
