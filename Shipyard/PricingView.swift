import SwiftUI

struct PricingView: View {
    let appID: String
    let contextID: Int
    @ObservedObject var model: PricingViewModel
    @Environment(\.openURL) private var openURL
    @State private var showEditor = false

    private var contextKey: String { "\(appID):\(contextID)" }
    private var pageKey: String { "\(contextKey):\(model.currentList.rawValue):\(model.parentID ?? "none")" }
    private var headerError: String? { model.section == .prices ? model.scheduleError : model.availabilityError }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack {
                if model.section == .prices {
                    Text("Base territory: \(PricingDisplay.territory(model.baseTerritory))")
                    Spacer()
                    if let reason = model.editBlockReason { Text(reason).foregroundStyle(.secondary) }
                } else {
                    Text("New territories: " + (model.availability?.attributes?.availableInNewTerritories.map { $0 ? "Included automatically" : "Not included automatically" } ?? "Unknown"))
                    Spacer()
                    Text("Manage availability changes in App Store Connect.").foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11))
            .padding(.horizontal, 16).padding(.vertical, 10)
            if let message = model.message { banner(message) }
            if let error = headerError ?? model.page.error { banner(error, retry: true) }
            if model.parentID == nil {
                if model.loadingCurrentHeader {
                    ProgressView("Loading pricing and availability…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    placeholder(headerError == nil ? (model.section == .prices ? "No pricing schedule" : "No availability information") : "Couldn’t load \(model.section.rawValue.lowercased())",
                                detail: "Refresh to check again, or manage this app in App Store Connect.")
                }
            } else if model.page.loading && !model.page.loaded {
                ProgressView("Loading \(model.section.rawValue.lowercased())…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.page.resources.isEmpty {
                placeholder("No \(model.section == .prices ? "prices" : "territories") found", detail: "Refresh to check again, or open App Store Connect to manage this app.")
            } else if model.section == .prices {
                if model.priceRows.isEmpty { noMatches } else { pricesTable }
            } else {
                if model.territoryRows.isEmpty { noMatches } else { availabilityTable }
            }
            Divider()
            HStack {
                Text("\(model.page.resources.count) loaded" + (model.page.total.map { " of \($0)" } ?? ""))
                Text("Search applies to loaded rows.").foregroundStyle(.secondary)
                Spacer()
                if model.page.loading { ProgressView().controlSize(.small) }
                if model.page.nextCursor != nil {
                    Button(model.page.error == nil ? "Load More" : "Retry Load More") {
                        Task { await model.loadPage(model.currentList, more: true) }
                    }.disabled(model.page.loading || model.saving)
                }
            }.font(.system(size: 11)).padding(12)
        }
        .font(.system(size: 13))
        .background(ShipyardTheme.tableBackground)
        .task(id: contextKey) { model.activate(appID: appID, contextID: contextID); await model.load() }
        .task(id: pageKey) { await model.loadPage(model.currentList) }
        .onChange(of: model.currentList) { _, _ in model.search = "" }
        .onDisappear { model.cancel() }
        .sheet(isPresented: $showEditor) {
            PriceChangeEditor(model: model) { showEditor = false }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Pricing section", selection: $model.section) {
                ForEach(PricingViewModel.Section.allCases, id: \.self) { Text($0.rawValue).lineLimit(1).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 200).fixedSize(horizontal: true, vertical: false)
            TextField("Search territories, prices, status…", text: $model.search)
                .textFieldStyle(.roundedBorder).frame(minWidth: 120)
                .accessibilityIdentifier("pricing.search")
            if model.section == .prices {
                Picker("Price source", selection: $model.priceMode) {
                    Text("Manual prices").tag(PricingList.manual)
                    Text("Automatic prices").tag(PricingList.automatic)
                }.labelsHidden().fixedSize()
                    .accessibilityIdentifier("pricing.source")
                Button { showEditor = true } label: {
                    Label("Schedule Price Change", systemImage: "calendar.badge.plus").labelStyle(.iconOnly)
                }
                    .disabled(model.editBlockReason != nil)
                    .help(model.editBlockReason ?? "Schedule a future base-territory price change")
                    .fixedSize()
                    .accessibilityIdentifier("pricing.schedule")
            }
            Menu {
                Button("Open in App Store Connect") {
                    if let url = URL(string: "https://appstoreconnect.apple.com/apps/\(appID)") { openURL(url) }
                }
            } label: { Image(systemName: "ellipsis.circle") }
                .fixedSize().accessibilityLabel("More pricing actions")
            Button { Task { await model.load(refresh: true) } } label: {
                Label("Refresh Pricing", systemImage: "arrow.clockwise").labelStyle(.iconOnly)
            }.disabled(model.saving).accessibilityIdentifier("pricing.refresh")
        }
        .controlSize(.small).padding(.horizontal, 16).frame(height: 52)
        .background(LaunchTheme.page)
    }

    private var pricesTable: some View {
        Table(model.priceRows) {
            TableColumn("Territory") { Text($0.territory) }.width(min: 160, ideal: 240)
            TableColumn("Customer price") { Text($0.price) }.width(min: 110, ideal: 130)
            TableColumn("Proceeds") { Text($0.developerProceeds) }.width(min: 100, ideal: 120)
            TableColumn("Starts") { Text($0.startDate ?? "No start date") }.width(min: 100, ideal: 110)
            TableColumn("Ends") { Text($0.endDate ?? "Ongoing") }.width(min: 100, ideal: 110)
            TableColumn("Period") { Text($0.phase(on: model.today)) }.width(min: 75, ideal: 90)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .accessibilityIdentifier("pricing.prices-table")
    }
    private var availabilityTable: some View {
        Table(model.territoryRows) {
            TableColumn("Territory") { Text(PricingDisplay.territory($0.relatedID("territory", type: "territories"))) }.width(min: 160, ideal: 230)
            TableColumn("Availability") { Text($0.attributes?.available.map { $0 ? "Selected" : "Not selected" } ?? "Unknown") }.width(min: 95, ideal: 110)
            TableColumn("Pre-order") { Text($0.attributes?.preOrderEnabled.map { $0 ? "Enabled" : "Not enabled" } ?? "Unknown") }.width(min: 90, ideal: 110)
            TableColumn("Release date") { Text($0.attributes?.releaseDate ?? "Not set") }.width(min: 95, ideal: 110)
            TableColumn("Status") { row in
                Text((row.attributes?.contentStatuses ?? []).map { $0.replacingOccurrences(of: "_", with: " ").capitalized }.joined(separator: ", "))
                    .help((row.attributes?.contentStatuses ?? []).joined(separator: ", "))
            }.width(min: 180, ideal: 260)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .accessibilityIdentifier("pricing.availability-table")
    }
    private func placeholder(_ title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var noMatches: some View {
        VStack {
            placeholder("No matches", detail: "Try another search or load more rows.")
            Button("Clear Search") { model.search = "" }.padding(.bottom, 20)
        }
    }
    private func banner(_ text: String, retry: Bool = false) -> some View {
        HStack {
            Text(text).textSelection(.enabled)
            Spacer()
            if retry {
                Button("Retry") {
                    Task {
                        if headerError != nil { await model.load(refresh: true) }
                        else { await model.loadPage(model.currentList, more: model.page.nextCursor != nil, retry: true) }
                    }
                }.disabled(model.saving || model.page.loading)
            }
        }.font(.system(size: 12)).padding(12).background(ShipyardTheme.accent.opacity(0.08))
    }
}

private struct PriceChangeEditor: View {
    @ObservedObject var model: PricingViewModel
    let close: () -> Void
    @State private var pointID = ""
    @State private var search = ""
    @State private var day = Date()
    @State private var confirming = false

    private var point: PricingResource? { model.pointRows.first { $0.id == pointID } }
    private var amount: String { PricingDisplay.price(point?.attributes?.customerPrice, currency: model.baseCurrency) }
    private var canReview: Bool {
        model.editBlockReason == nil && point != nil && pointID != model.currentBasePrice?.pointID
            && PricingDisplay.validAmount(point?.attributes?.customerPrice)
            && point?.relatedID("territory", type: "territories") == model.baseTerritory
            && PricingDisplay.day(day) > model.today
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Schedule Price Change").font(.system(size: 18, weight: .semibold))
            Text("Base territory: \(PricingDisplay.territory(model.baseTerritory))")
            Text("Current customer price: \(model.currentBasePrice?.price ?? "Unavailable")").foregroundStyle(.secondary)
            TextField("Search loaded price amounts…", text: $search).textFieldStyle(.roundedBorder)
                .disabled(model.saving)
            Picker("New customer price", selection: $pointID) {
                Text("Choose a price…").tag("")
                ForEach(model.pointRows.filter { $0.id == pointID || search.isEmpty || ($0.attributes?.customerPrice ?? "").contains(search) }) { point in
                    Text(PricingDisplay.price(point.attributes?.customerPrice, currency: model.baseCurrency)).tag(point.id)
                }
            }.accessibilityIdentifier("pricing.new-price").disabled(model.saving)
            HStack {
                Text("\(model.pointRows.count) price points loaded").foregroundStyle(.secondary)
                Spacer()
                if model.pages[.points]?.loading == true { ProgressView().controlSize(.small) }
                if model.pages[.points]?.nextCursor != nil {
                    Button("Load More Prices") { Task { await model.loadPage(.points, more: true) } }
                        .disabled(model.saving || model.pages[.points]?.loading == true)
                }
            }
            if let error = model.pages[.points]?.error {
                Text(error).foregroundStyle(.red)
                Button("Retry Prices") { Task { await model.loadPage(.points, more: model.pages[.points]?.nextCursor != nil, retry: true) } }
                    .disabled(model.saving || model.pages[.points]?.loading == true)
            }
            DatePicker("Effective date", selection: $day, in: model.tomorrow..., displayedComponents: .date)
                .accessibilityIdentifier("pricing.effective-date")
                .disabled(model.saving)
            Text("Existing manual prices in other territories and past entries are preserved. Apple determines automatically calculated prices for other territories.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if let error = model.saveError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if let reason = model.editBlockReason, !model.saving {
                Text(reason).foregroundStyle(.secondary)
                if model.needsReload || model.pendingChange != nil {
                    Button("Refresh Pricing") { Task { await model.load(refresh: true); await model.loadPage(.manual) } }
                }
            }
            HStack {
                Button("Cancel", action: close).keyboardShortcut(.cancelAction).disabled(model.saving)
                Spacer()
                if model.saving { ProgressView().controlSize(.small) }
                Button("Review Change") { confirming = true }
                    .buttonStyle(.launchPrimary).disabled(!canReview)
                    .accessibilityIdentifier("pricing.review-change")
            }
        }
        .font(.system(size: 13)).padding(24).frame(width: 550)
        .interactiveDismissDisabled(model.saving)
        .task { day = model.tomorrow; await model.loadPage(.points) }
        .confirmationDialog("Schedule this price change?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Schedule Price Change") {
                Task {
                    if await model.scheduleChange(pointID: pointID, day: PricingDisplay.day(day)) {
                        close()
                        await model.load(refresh: true)
                        await model.loadPage(.manual)
                    }
                }
            }.accessibilityIdentifier("pricing.confirm-change")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Change \(PricingDisplay.territory(model.baseTerritory)) from \(model.currentBasePrice?.price ?? "the current price") to \(amount), starting \(PricingDisplay.day(day)) and continuing until changed. Other manual prices are kept; automatic prices may change.")
        }
    }
}
