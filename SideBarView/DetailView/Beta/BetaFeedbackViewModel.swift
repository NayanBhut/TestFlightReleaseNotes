import Foundation
import Combine

@MainActor
struct BetaFeedbackAPI {
    var perform: (APIMethod) async throws -> Data
    var screenshot: (URL) async throws -> Data

    static let live = Self(perform: { method in
        guard let request = APIClient.shared.getRequest(api: method) else { throw URLError(.userAuthenticationRequired) }
        return try await APIClient.shared.callAPI(with: request)
    }, screenshot: { url in
        #if DEBUG
        guard !ReviewSubmissionUITestSafety.isEnabled, !AppStoreScreenshotSafety.isEnabled else {
            throw URLError(.notConnectedToInternet)
        }
        #endif
        // Signed attachment URLs use their own authorization. Never attach the API JWT,
        // cookies, or persistent cache to a tester screenshot download.
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    })

    static func listMethod(appID: String, kind: BetaFeedbackKind, cursor: String?) -> APIMethod {
        var query = ["sort": "-createdDate", "include": "build,tester",
                     "fields[builds]": "version", "fields[betaTesters]": "firstName,lastName,email",
                     "limit": String(AppConfigs.feedbackLimit)]
        if let cursor { query["cursor"] = cursor }
        return .get(name: .getAllApps, queryParams: query, path: "\(appID)/\(kind.rawValue)")
    }
}

@MainActor
final class BetaFeedbackViewModel: ObservableObject {
    struct PageState {
        var items: [BetaFeedbackItem] = []
        var nextCursor: String?
        var total: Int?
        var hasLoaded = false
        var isLoading = false
        var error: String?
    }
    enum LogState: Equatable {
        case idle, loading, loaded(String?), failed(String)
    }

    @Published private(set) var pages: [BetaFeedbackKind: PageState] = [:]
    @Published private(set) var kind = BetaFeedbackKind.screenshots
    @Published private(set) var selectedID: String?
    @Published private(set) var logState = LogState.idle
    @Published var search = ""
    @Published var buildFilter = ""
    @Published var platformFilter = ""
    let api: BetaFeedbackAPI
    private var appID: String?
    private var contextID: Int?
    private var generation = UUID()
    private var tokens: [BetaFeedbackKind: UUID] = [:]
    private var tasks: [BetaFeedbackKind: Task<Void, Never>] = [:]
    private var logTask: Task<Void, Never>?
    private var logToken = UUID()

    init(api: BetaFeedbackAPI = .live) { self.api = api }

    var page: PageState { pages[kind] ?? PageState() }
    var selected: BetaFeedbackItem? { page.items.first { $0.id == selectedID } }
    var filteredItems: [BetaFeedbackItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return page.items.filter { item in
            (buildFilter.isEmpty || item.buildID == buildFilter)
            && (platformFilter.isEmpty || item.platform == platformFilter)
            && (query.isEmpty || [item.note, item.tester, item.email, item.buildNumber,
                                 item.attributes.deviceModel, item.attributes.osVersion]
                .compactMap { $0 }.joined(separator: " ").localizedCaseInsensitiveContains(query))
        }
    }
    var builds: [(id: String, label: String)] {
        var seen = Set<String>()
        return page.items.compactMap { item in
            guard let id = item.buildID, seen.insert(id).inserted else { return nil }
            return (id, item.buildLabel)
        }
    }
    var platforms: [String] { Set(page.items.map(\.platform)).sorted() }

    func activate(appID: String, contextID: Int) {
        guard self.appID != appID || self.contextID != contextID else { return }
        cancel()
        self.appID = appID
        self.contextID = contextID
        pages = [:]
        select(nil)
        clearFilters()
    }

    func switchKind(_ kind: BetaFeedbackKind) {
        guard self.kind != kind else { return }
        select(nil)
        self.kind = kind
        clearFilters()
    }

    func clearFilters() { search = ""; buildFilter = ""; platformFilter = "" }

    func select(_ id: String?) {
        logTask?.cancel()
        logToken = UUID()
        selectedID = id
        logState = .idle
    }

    func cancel() {
        generation = UUID()
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        logTask?.cancel()
        logToken = UUID()
        logState = .idle
        for key in Array(pages.keys) { pages[key]?.isLoading = false }
    }

    func load(refresh: Bool = false, more: Bool = false) async {
        guard let appID else { return }
        let kind = kind
        let state = pages[kind] ?? PageState()
        guard !state.isLoading, refresh || more || !state.hasLoaded else { return }
        guard !more || state.nextCursor != nil else { return }
        let cursor = more ? state.nextCursor : nil
        let epoch = generation
        let token = UUID()
        tokens[kind] = token
        pages[kind, default: PageState()].isLoading = true
        pages[kind]?.error = nil
        if !more { select(nil) }
        let task = Task { [weak self, api] in
            do {
                try Task.checkCancellation()
                let data = try await api.perform(BetaFeedbackAPI.listMethod(appID: appID, kind: kind, cursor: cursor))
                try Task.checkCancellation()
                let result = try BetaFeedbackPage.decode(data, kind: kind)
                guard let self, self.generation == epoch, self.tokens[kind] == token else { return }
                var seen = Set<String>()
                let items = (more ? (self.pages[kind]?.items ?? []) : []) + result.items
                self.pages[kind] = PageState(items: items.filter { seen.insert($0.id).inserted },
                    nextCursor: result.nextCursor == cursor ? nil : result.nextCursor,
                    total: result.total ?? (more ? state.total : nil), hasLoaded: true)
            } catch {
                guard let self, self.generation == epoch, self.tokens[kind] == token else { return }
                self.pages[kind]?.isLoading = false
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                self.pages[kind]?.error = FriendlyErrorMessage.message(for: error, requiring: .testFlightFeedback)
            }
        }
        tasks[kind] = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    func loadLog() async {
        guard let item = selected, item.kind == .crashes else { return }
        logTask?.cancel()
        let token = UUID()
        logToken = token
        let epoch = generation
        logState = .loading
        let task = Task { [weak self, api] in
            do {
                try Task.checkCancellation()
                let data = try await api.perform(.get(name: .betaFeedbackCrashSubmissions,
                    queryParams: ["fields[betaCrashLogs]": "logText"], path: "\(item.submissionID)/crashLog"))
                try Task.checkCancellation()
                let text = try BetaFeedbackCrashLogDocument.text(from: data)
                guard let self, self.generation == epoch, self.logToken == token,
                      self.selectedID == item.id else { return }
                self.logState = .loaded(text)
            } catch {
                guard let self, self.generation == epoch, self.logToken == token,
                      self.selectedID == item.id, !Task.isCancelled else { return }
                self.logState = .failed(FriendlyErrorMessage.message(for: error, requiring: .testFlightFeedback))
            }
        }
        logTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }
}
