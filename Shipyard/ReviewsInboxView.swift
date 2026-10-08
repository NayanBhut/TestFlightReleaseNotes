//
//  ReviewsInboxView.swift
//  App Store
//
//  Module 11 (Customer Reviews) cross-app inbox (114:10235): a local
//  aggregate over all accessible apps — App / Customer review / Rating /
//  Territory-date / Action — with per-app pagination provenance and
//  fetch failures tracked locally. This inbox is not a global Apple
//  endpoint (C11-H): each app is fetched with the same per-app query
//  (sort=-createdDate, include=response, limit 50), cursors stay scoped
//  to the app+query that issued them, and text/date/reply filters apply
//  locally. Opening a review jumps to the app's detail Reviews tab.
//

import SwiftUI

// MARK: - Inbox loader

/// One inbox row keeps its app provenance (the version association comes
/// from the query context — it is not a review response attribute).
struct InboxReviewRow: Identifiable {
    let id: String
    let appId: String
    let appName: String
    let review: CustomerReviewModel
}

@MainActor
final class ReviewsInboxLoader: ObservableObject {
    @Published private(set) var rows: [InboxReviewRow] = []
    @Published private(set) var perAppErrors: [String: String] = [:]
    @Published private(set) var loadedAppIds: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastSync: Date? = nil

    private var loadTask: Task<Void, Never>? = nil

    /// First page per accessible app. Bounded (one page each) with partial
    /// coverage surfaced — never a claim of global completeness.
    func load(apps: [AppsData]) {
        loadTask?.cancel()
        rows = []
        perAppErrors = [:]
        loadedAppIds = []
        guard !apps.isEmpty else { return }
        isLoading = true
        loadTask = Task { [weak self] in
            guard let self else { return }
            for app in apps {
                guard !Task.isCancelled else { break }
                do {
                    let page = try await ReviewsViewModel.fetchReviewListPage(appId: app.id)
                    guard !Task.isCancelled else { break }
                    rows += page.reviews.map {
                        InboxReviewRow(id: $0.id, appId: app.id, appName: app.name ?? "App", review: $0)
                    }
                    loadedAppIds.insert(app.id)
                } catch {
                    guard !Task.isCancelled else { break }
                    perAppErrors[app.id] = (error as? APIError)?.details ?? error.localizedDescription
                }
            }
            lastSync = Date()
            isLoading = false
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }
}

// MARK: - Inbox view (114:10235)

struct ReviewsInboxView: View {
    var apps: [AppsData]
    var onOpenReview: (AppsData, String) -> Void

    @StateObject private var loader = ReviewsInboxLoader()
    @State private var appFilter: String? = nil
    @State private var ratingFilter: Int = 0
    @State private var territoryFilter: String? = nil
    @State private var dateFilter: ReviewDateFilter = .all
    @State private var sortOption: ReviewSortOption = .newest
    @State private var replyFilter: ReviewReplyFilter = .all
    @State private var highlightedId: String? = nil

    private var visibleRows: [InboxReviewRow] {
        var result = loader.rows
        if let appFilter {
            result = result.filter { $0.appId == appFilter }
        }
        if ratingFilter > 0 {
            result = result.filter { ($0.review.rating ?? 0) == ratingFilter }
        }
        if let territory = territoryFilter {
            result = result.filter { $0.review.territory == territory }
        }
        if let days = dateFilter.days {
            let cutoff = Date().addingTimeInterval(TimeInterval(-days * 24 * 3600))
            result = result.filter {
                guard let raw = $0.review.createdDate,
                      let date = ReviewsViewModel.reviewDate(raw) else { return false }
                return date >= cutoff
            }
        }
        switch replyFilter {
        case .unanswered:
            result = result.filter { $0.review.response == nil }
        case .pending:
            result = result.filter { $0.review.response?.state == "PENDING_PUBLISH" }
        case .published:
            result = result.filter { $0.review.response?.state == "PUBLISHED" }
        case .all:
            break
        }
        switch sortOption {
        case .newest:
            result.sort { ($0.review.createdDate ?? "") > ($1.review.createdDate ?? "") }
        case .oldest:
            result.sort { ($0.review.createdDate ?? "") < ($1.review.createdDate ?? "") }
        case .highestRated:
            result.sort { ($0.review.rating ?? 0) > ($1.review.rating ?? 0) }
        case .lowestRated:
            result.sort { ($0.review.rating ?? 0) < ($1.review.rating ?? 0) }
        }
        return result
    }

    private var availableTerritories: [String] {
        Array(Set(loader.rows.compactMap(\.review.territory))).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Customer reviews · all accessible apps")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(ShipyardTheme.title)
                        Text("Local cross-app aggregate · Filter verified unanswered separately from PENDING_PUBLISH, PUBLISHED and unknown.")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                    }
                    filterRow
                    if !loader.perAppErrors.isEmpty {
                        perAppErrorsBanner
                    }
                    inboxTable
                }
                .padding(24)
            }
            actionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShipyardTheme.tableBackground)
        .onAppear {
            loader.load(apps: apps)
        }
        .onChange(of: apps.map(\.id)) { _, _ in
            loader.load(apps: apps)
        }
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            Menu {
                Button("All apps") { appFilter = nil }
                ForEach(apps, id: \.id) { app in
                    Button(app.name ?? app.id) { appFilter = app.id }
                }
            } label: {
                ShipyardMenuLabel(text: "App: \(apps.first(where: { $0.id == appFilter })?.name ?? "All")")
            }
            .menuStyle(.borderlessButton)
            Menu {
                Button("All ratings") { ratingFilter = 0 }
                ForEach(AppConfigs.ratingOptions.filter { $0 > 0 }, id: \.self) { value in
                    Button("\(value) ★") { ratingFilter = value }
                }
            } label: {
                ShipyardMenuLabel(text: ratingFilter == 0 ? "Rating: All" : "Rating: \(ratingFilter) ★")
            }
            .menuStyle(.borderlessButton)
            Menu {
                Button("All territories") { territoryFilter = nil }
                ForEach(availableTerritories, id: \.self) { territory in
                    Button(territory) { territoryFilter = territory }
                }
            } label: {
                ShipyardMenuLabel(text: "Territory: \(territoryFilter ?? "All")")
            }
            .menuStyle(.borderlessButton)
            Menu {
                ForEach(ReviewDateFilter.allCases, id: \.self) { option in
                    Button(option.rawValue) { dateFilter = option }
                }
            } label: {
                ShipyardMenuLabel(text: dateFilter.displayName)
            }
            .menuStyle(.borderlessButton)
            Menu {
                ForEach(ReviewSortOption.allCases, id: \.self) { option in
                    Button(option.rawValue) { sortOption = option }
                }
            } label: {
                ShipyardMenuLabel(text: sortOption.displayName)
            }
            .menuStyle(.borderlessButton)
            Menu {
                ForEach(ReviewReplyFilter.allCases, id: \.self) { option in
                    Button(option.rawValue) { replyFilter = option }
                }
            } label: {
                ShipyardMenuLabel(text: replyFilter.displayName)
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var perAppErrorsBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Some apps failed to load")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.warningBorder)
            ForEach(loader.perAppErrors.sorted(by: { $0.key < $1.key }), id: \.key) { appId, message in
                Text("\(apps.first(where: { $0.id == appId })?.name ?? appId): \(message)")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
            }
            Text("Partial coverage remains visible; failures are tracked per app.")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ShipyardTheme.warningSurface)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ShipyardTheme.warningBorder, lineWidth: 0.5))
    }

    private var inboxTable: some View {
        VStack(spacing: 0) {
            if loader.isLoading && loader.rows.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Loading reviews across \(apps.count) apps… first page per app.")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                }
                .padding(16)
            } else if visibleRows.isEmpty {
                Text(loader.rows.isEmpty ? "No reviews loaded for these apps." : "No rows match the current filters.")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.body)
                    .padding(16)
            } else {
                HStack(spacing: 12) {
                    Text("App").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Customer review").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Rating").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Territory / date").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Action").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(ShipyardTheme.body)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(ShipyardTheme.tableHeader)
                ForEach(visibleRows) { row in
                    Button {
                        highlightedId = row.id
                        if let app = apps.first(where: { $0.id == row.appId }) {
                            onOpenReview(app, row.id)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text(row.appName)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(row.review.title?.isEmpty == false ? row.review.title! : String((row.review.body ?? "").prefix(40)))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(row.review.rating.map { "\($0) star\($0 == 1 ? "" : "s")" } ?? "—")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(row.review.territory ?? "—") · \(row.review.createdDate.map(reviewDisplayDate) ?? "—")")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(inboxActionText(row.review))
                                .foregroundColor(ShipyardTheme.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.title)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 38)
                        .background(highlightedId == row.id ? ShipyardTheme.selectedRow : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    ShipyardTheme.rowDivider.frame(height: 1)
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(LaunchTheme.border, lineWidth: 1))
        .cornerRadius(6)
    }

    private func inboxActionText(_ review: CustomerReviewModel) -> String {
        switch review.response?.state {
        case "PUBLISHED":
            return "PUBLISHED · edit →"
        case "PENDING_PUBLISH":
            return "PENDING · open →"
        default:
            return "Reply →"
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Text(actionBarStatus)
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
            Spacer()
            Button("Open Selected Review") {
                if let row = visibleRows.first(where: { $0.id == highlightedId }) ?? visibleRows.first,
                   let app = apps.first(where: { $0.id == row.appId }) {
                    highlightedId = row.id
                    onOpenReview(app, row.id)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(visibleRows.isEmpty)
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(ShipyardTheme.sidebarBackground)
        .overlay(ShipyardTheme.rowDivider.frame(height: 1), alignment: .top)
    }

    private var actionBarStatus: String {
        var parts: [String] = []
        if loader.isLoading {
            parts.append("Loading…")
        } else if let sync = loader.lastSync {
            parts.append("Last synced \(reviewDateTime(sync))")
        }
        parts.append("\(loader.loadedAppIds.count) of \(apps.count) apps loaded · first page each · partial coverage")
        if !loader.perAppErrors.isEmpty {
            parts.append("\(loader.perAppErrors.count) failed")
        }
        return parts.joined(separator: " · ")
    }
}
