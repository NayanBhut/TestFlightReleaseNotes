import Foundation
import Combine

@MainActor
struct PricingAPI {
    var perform: (APIMethod, APIVersion) async throws -> Data
    static let live = Self { method, version in
        guard let request = APIClient.shared.getRequest(api: method, apiVersion: version) else {
            throw URLError(.userAuthenticationRequired)
        }
        return try await APIClient.shared.callAPI(with: request)
    }
}

enum PricingList: String, CaseIterable {
    case manual = "manualPrices", automatic = "automaticPrices"
    case availability = "territoryAvailabilities", points = "appPricePoints"
    var resourceType: String {
        switch self {
        case .manual, .automatic: return "appPrices"
        case .availability: return "territoryAvailabilities"
        case .points: return "appPricePoints"
        }
    }
}

@MainActor
final class PricingViewModel: ObservableObject {
    struct Page {
        var resources: [PricingResource] = []
        var included: [String: PricingResource] = [:]
        var nextCursor: String?
        var total: Int?
        var loaded = false
        var loading = false
        var error: String?
    }
    enum Section: String, CaseIterable { case prices = "Prices", availability = "Availability" }
    struct PendingChange: Equatable { let pointID: String; let day: String }

    @Published var section = Section.prices
    @Published var priceMode = PricingList.manual
    @Published var search = ""
    @Published private(set) var schedule: PricingResource?
    @Published private(set) var baseCurrency: String?
    @Published private(set) var availability: PricingResource?
    @Published private(set) var scheduleError: String?
    @Published private(set) var availabilityError: String?
    @Published private(set) var pages: [PricingList: Page] = [:]
    @Published private(set) var saving = false
    @Published private(set) var saveError: String?
    @Published private(set) var message: String?
    @Published private(set) var pendingChange: PendingChange?
    @Published private(set) var needsReload = false
    private(set) var appID: String?
    private var contextID: Int?
    private var epoch = UUID()
    private var tasks: [String: Task<Void, Never>] = [:]
    @Published private var headersLoading: Set<String> = []
    @Published private var headersLoaded: Set<String> = []
    private let api: PricingAPI
    private let now: () -> Date

    init(api: PricingAPI = .live, now: @escaping () -> Date = Date.init) { self.api = api; self.now = now }

    var currentList: PricingList { section == .availability ? .availability : priceMode }
    var page: Page { pages[currentList] ?? Page() }
    var baseTerritory: String? { schedule?.relatedID("baseTerritory", type: "territories") }
    var parentID: String? { currentList == .availability ? availability?.id : schedule?.id }
    var loadingCurrentHeader: Bool {
        let key = section == .prices ? "schedule" : "availability"
        let error = section == .prices ? scheduleError : availabilityError
        return headersLoading.contains(key) || (!headersLoaded.contains(key) && error == nil)
    }
    var today: String { PricingDisplay.day(now()) }
    var tomorrow: Date { Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now()))! }
    var priceRows: [AppPriceRow] {
        rows(for: priceMode).filter { row in
            search.isEmpty || [row.territory, row.price, row.phase(on: today)]
                .joined(separator: " ").localizedCaseInsensitiveContains(search)
        }
    }
    var territoryRows: [PricingResource] {
        page.resources.filter { row in
            let territory = PricingDisplay.territory(row.relatedID("territory", type: "territories"))
            return search.isEmpty || (territory + " " + (row.attributes?.contentStatuses ?? []).joined(separator: " "))
                .localizedCaseInsensitiveContains(search)
        }
    }
    var pointRows: [PricingResource] { pages[.points]?.resources ?? [] }
    var currentBasePrice: AppPriceRow? {
        guard let baseTerritory else { return nil }
        return PriceScheduleChangeRequest.editableBasePrice(rows(for: .manual), baseTerritory: baseTerritory, today: today)
    }
    var editBlockReason: String? {
        if saving { return "A price change is being sent." }
        if pendingChange != nil { return "A price change is awaiting confirmation. Refresh to check Apple’s schedule." }
        if needsReload { return "Refresh pricing before scheduling another change." }
        guard schedule != nil else { return "Set up initial pricing in App Store Connect." }
        guard let manual = pages[.manual], manual.loaded, !manual.loading, manual.error == nil,
              manual.nextCursor == nil else { return "Load all manual prices before scheduling a change." }
        guard let current = currentBasePrice, PricingDisplay.validAmount(current.customerPrice), baseCurrency != nil else {
            return "This app has an existing future or complex base-price schedule. Manage it in App Store Connect."
        }
        return nil
    }

    func rows(for list: PricingList) -> [AppPriceRow] {
        let page = pages[list] ?? Page()
        return page.resources.map { AppPriceRow($0, included: page.included) }
    }

    func activate(appID: String, contextID: Int) {
        guard self.appID != appID || self.contextID != contextID else { return }
        cancel()
        self.appID = appID; self.contextID = contextID
        clearData()
        pendingChange = nil; needsReload = false; saveError = nil; message = nil
        search = ""; section = .prices; priceMode = .manual
    }
    private func clearData() {
        schedule = nil; availability = nil; baseCurrency = nil
        scheduleError = nil; availabilityError = nil
        pages = [:]; headersLoaded = []
    }
    func cancel() {
        epoch = UUID()
        tasks.values.forEach { $0.cancel() }; tasks = [:]
        headersLoading = []; saving = false
        for key in Array(pages.keys) { pages[key]?.loading = false }
    }
    func load(refresh: Bool = false) async {
        guard !saving else { return }
        if refresh { cancel(); clearData() }
        async let prices: Void = loadHeader(isSchedule: true)
        async let territories: Void = loadHeader(isSchedule: false)
        _ = await (prices, territories)
        await loadPage(currentList)
    }

    private func loadHeader(isSchedule: Bool) async {
        guard let appID else { return }
        let key = isSchedule ? "schedule" : "availability"
        guard !headersLoaded.contains(key), headersLoading.insert(key).inserted else { return }
        let generation = epoch
        let task = Task { [weak self, api] in
            do {
                try Task.checkCancellation()
                let data = try await api.perform(.get(name: .getAllApps,
                    queryParams: isSchedule ? ["include": "baseTerritory"] : [:],
                    path: "\(appID)/\(isSchedule ? "appPriceSchedule" : "appAvailabilityV2")"), .v1)
                let doc = try JSONDecoder().decode(PricingDocument<PricingResource>.self, from: data)
                try Task.checkCancellation()
                guard let self, self.epoch == generation else { return }
                if let resource = doc.data, resource.type != (isSchedule ? "appPriceSchedules" : "appAvailabilities") {
                    throw PricingError.invalidResponse
                }
                if isSchedule {
                    self.schedule = doc.data
                    self.baseCurrency = self.baseTerritory.flatMap { doc.includedByID["territories:\($0)"]?.attributes?.currency }
                    self.scheduleError = nil
                } else { self.availability = doc.data; self.availabilityError = nil }
                self.headersLoaded.insert(key)
            } catch {
                guard let self, self.epoch == generation, !Task.isCancelled else { return }
                if (error as? APIError)?.statusCode == 404 { self.headersLoaded.insert(key) }
                else if isSchedule { self.scheduleError = Self.errorMessage(error) }
                else { self.availabilityError = Self.errorMessage(error) }
            }
            if let self, self.epoch == generation { self.headersLoading.remove(key) }
        }
        tasks[key] = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    static func listMethod(_ list: PricingList, appID: String, scheduleID: String?, availabilityID: String?,
                           baseTerritory: String?, cursor: String?) -> (APIMethod, APIVersion)? {
        var query = ["limit": String(AppConfigs.pricingLimit)]
        if let cursor { query["cursor"] = cursor }
        switch list {
        case .manual, .automatic:
            guard let scheduleID else { return nil }
            query["include"] = "appPricePoint,territory"
            return (.get(name: .appPriceSchedules, queryParams: query, path: "\(scheduleID)/\(list.rawValue)"), .v1)
        case .availability:
            guard let availabilityID else { return nil }
            query["include"] = "territory"
            return (.get(name: .appAvailabilities, queryParams: query, path: "\(availabilityID)/territoryAvailabilities"), .v2)
        case .points:
            guard let baseTerritory else { return nil }
            query["filter[territory]"] = baseTerritory
            query["include"] = "territory"
            return (.get(name: .getAllApps, queryParams: query, path: "\(appID)/appPricePoints"), .v1)
        }
    }

    func loadPage(_ list: PricingList, more: Bool = false, retry: Bool = false) async {
        guard let appID, !saving else { return }
        let state = pages[list] ?? Page()
        guard !state.loading, more || retry || !state.loaded, !more || state.nextCursor != nil,
              let (method, version) = Self.listMethod(list, appID: appID, scheduleID: schedule?.id,
                availabilityID: availability?.id, baseTerritory: baseTerritory, cursor: more ? state.nextCursor : nil) else { return }
        let generation = epoch
        pages[list, default: Page()].loading = true
        pages[list]?.error = nil
        let task = Task { [weak self, api] in
            do {
                try Task.checkCancellation()
                let data = try await api.perform(method, version)
                let doc = try JSONDecoder().decode(PricingDocument<[PricingResource]>.self, from: data)
                guard let resources = doc.data, resources.allSatisfy({ $0.type == list.resourceType }) else { throw PricingError.invalidResponse }
                try Task.checkCancellation()
                guard let self, self.epoch == generation else { return }
                var page = more ? state : Page()
                var ids = Set(page.resources.map(\.id))
                page.resources += resources.filter { ids.insert($0.id).inserted }
                page.included.merge(doc.includedByID, uniquingKeysWith: { _, new in new })
                page.nextCursor = doc.nextCursor
                page.total = doc.meta?.paging?.total ?? page.total
                page.loading = false; page.loaded = true; page.error = nil
                if more, doc.nextCursor == state.nextCursor { throw PricingError.invalidResponse }
                self.pages[list] = page
                if list == .manual, page.nextCursor == nil {
                    if let pending = self.pendingChange,
                       self.rows(for: .manual).contains(where: { $0.pointID == pending.pointID && $0.startDate == pending.day }) {
                        self.pendingChange = nil
                        self.saveError = nil
                        self.message = "Price change confirmed for \(pending.day)."
                    }
                    self.needsReload = false
                }
            } catch {
                guard let self, self.epoch == generation else { return }
                self.pages[list]?.loading = false
                if !Task.isCancelled { self.pages[list]?.error = Self.errorMessage(error) }
            }
        }
        tasks[list.rawValue] = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    func scheduleChange(pointID: String, day: String) async -> Bool {
        guard let appID, editBlockReason == nil, let baseTerritory,
              let point = pointRows.first(where: { $0.id == pointID }),
              point.relatedID("territory", type: "territories") == baseTerritory,
              PricingDisplay.validAmount(point.attributes?.customerPrice) else { return false }
        let oldRows = rows(for: .manual).sorted { $0.id < $1.id }
        let payload: Data
        do {
            payload = try JSONEncoder().encode(PriceScheduleChangeRequest.make(appID: appID,
                baseTerritory: baseTerritory, prices: oldRows, newPointID: pointID, startDate: day, today: today))
        } catch { saveError = Self.errorMessage(error); return false }
        let generation = epoch
        saving = true; saveError = nil
        let result = SaveResult()
        let task = Task { [weak self, api] in
            var posted = false
            do {
                try Task.checkCancellation()
                let scheduleData = try await api.perform(.get(name: .getAllApps, queryParams: ["include": "baseTerritory"],
                    path: "\(appID)/appPriceSchedule"), .v1)
                let fresh = try JSONDecoder().decode(PricingDocument<PricingResource>.self, from: scheduleData)
                guard let schedule = fresh.data, schedule.type == "appPriceSchedules",
                      schedule.relatedID("baseTerritory", type: "territories") == baseTerritory else { throw PricingError.changedSchedule }
                var freshRows: [AppPriceRow] = []
                var cursor: String?
                var visited = Set<String>()
                repeat {
                    try Task.checkCancellation()
                    guard let (method, version) = Self.listMethod(.manual, appID: appID, scheduleID: schedule.id,
                        availabilityID: nil, baseTerritory: baseTerritory, cursor: cursor) else { throw PricingError.invalidResponse }
                    let data = try await api.perform(method, version)
                    let doc = try JSONDecoder().decode(PricingDocument<[PricingResource]>.self, from: data)
                    guard let rows = doc.data, rows.allSatisfy({ $0.type == "appPrices" }) else { throw PricingError.invalidResponse }
                    freshRows += rows.map { AppPriceRow($0, included: doc.includedByID) }
                    cursor = doc.nextCursor
                    if let cursor, !visited.insert(cursor).inserted { throw PricingError.invalidResponse }
                } while cursor != nil
                guard freshRows.sorted(by: { $0.id < $1.id }) == oldRows else { throw PricingError.changedSchedule }
                try Task.checkCancellation()
                guard let self, self.epoch == generation else { return }
                posted = true
                self.pendingChange = PendingChange(pointID: pointID, day: day)
                self.needsReload = true
                _ = try await api.perform(.post(name: .appPriceSchedules, body: payload), .v1)
                guard !Task.isCancelled, self.epoch == generation else { return }
                self.pendingChange = PendingChange(pointID: pointID, day: day)
                self.needsReload = true
                self.message = "Price change sent. Refresh to confirm Apple’s schedule."
                result.succeeded = true
            } catch {
                guard let self, self.epoch == generation, !Task.isCancelled else { return }
                self.saveError = Self.errorMessage(error)
                if case PricingError.changedSchedule = error { self.needsReload = true }
                if posted, (error as? APIError)?.statusCode.map({ (400...499).contains($0) }) != true {
                    self.pendingChange = PendingChange(pointID: pointID, day: day)
                    self.needsReload = true
                    self.saveError = "The outcome is unconfirmed. Refresh pricing before taking another action."
                } else if posted {
                    self.pendingChange = nil
                    self.needsReload = false
                }
            }
            if let self, self.epoch == generation { self.saving = false }
        }
        tasks["write"] = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        return epoch == generation && self.appID == appID && result.succeeded
    }
    private final class SaveResult { var succeeded = false }
    private static func errorMessage(_ error: Error) -> String {
        if let error = error as? PricingError { return error.localizedDescription }
        return FriendlyErrorMessage.message(for: error, requiring: .pricing)
    }
}
