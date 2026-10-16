#if DEBUG
import AppKit
import Foundation
import SwiftUI

/// Every request stays in memory, including simulated price writes.
@MainActor
final class PricingSampleServer {
    var requests: [APIMethod] = []
    var postedDay: String?
    var postedPoint: String?
    var api: PricingAPI { PricingAPI { method, _ in try self.respond(method) } }

    func respond(_ method: APIMethod) throws -> Data {
        requests.append(method)
        if case .post(.appPriceSchedules, let body, _, _) = method {
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let prices = json?["included"] as? [[String: Any]]
            let new = prices?.first { ($0["id"] as? String) == "${new-price}" }
            postedDay = (new?["attributes"] as? [String: Any])?["startDate"] as? String
            let relationships = new?["relationships"] as? [String: Any]
            postedPoint = ((relationships?["appPricePoint"] as? [String: Any])?["data"] as? [String: String])?["id"]
        }
        func resource(_ type: String, _ id: String, _ attrs: [String: Any] = [:], _ refs: [String: [String: String]] = [:]) -> [String: Any] {
            ["type": type, "id": id, "attributes": attrs, "relationships": refs.mapValues { ["data": $0] }]
        }
        let territories = [resource("territories", "USA", ["currency": "USD"]),
                           resource("territories", "CAN", ["currency": "CAD"]),
                           resource("territories", "GBR", ["currency": "GBP"])]
        let points = [("usd099", "0.99", "0.69", "USA"), ("usd199", "1.99", "1.39", "USA"),
                      ("usd299", "2.99", "2.09", "USA"), ("cad299", "2.99", "2.09", "CAN"),
                      ("gbp149", "1.49", "1.04", "GBR")].map {
            resource("appPricePoints", $0.0, ["customerPrice": $0.1, "proceeds": $0.2], ["territory": ["type": "territories", "id": $0.3]])
        }
        var doc: [String: Any]
        if method.apiPath.hasSuffix("/appPriceSchedule") || method.httpMethod.0 == "POST" {
            doc = ["data": resource("appPriceSchedules", "sample-schedule", [:], ["baseTerritory": ["type": "territories", "id": "USA"]]), "included": territories]
        } else if method.apiPath.hasSuffix("/appAvailabilityV2") {
            doc = ["data": resource("appAvailabilities", "sample-availability", ["availableInNewTerritories": false])]
        } else if method.apiPath.hasSuffix("/manualPrices") {
            var rows = [resource("appPrices", "base-price", ["manual": true, "startDate": NSNull(), "endDate": postedDay as Any? ?? NSNull()],
                ["territory": ["type": "territories", "id": "USA"], "appPricePoint": ["type": "appPricePoints", "id": "usd199"]]),
                resource("appPrices", "canada-override", ["manual": true],
                ["territory": ["type": "territories", "id": "CAN"], "appPricePoint": ["type": "appPricePoints", "id": "cad299"]])]
            if let postedDay, let postedPoint {
                rows.append(resource("appPrices", "scheduled-price", ["manual": true, "startDate": postedDay],
                    ["territory": ["type": "territories", "id": "USA"], "appPricePoint": ["type": "appPricePoints", "id": postedPoint]]))
            }
            doc = ["data": rows, "included": territories + points]
        } else if method.apiPath.hasSuffix("/automaticPrices") {
            doc = ["data": [resource("appPrices", "uk-automatic", ["manual": false],
                ["territory": ["type": "territories", "id": "GBR"], "appPricePoint": ["type": "appPricePoints", "id": "gbp149"]])], "included": territories + points]
        } else if method.apiPath.hasSuffix("/appPricePoints") {
            doc = ["data": points.filter { ($0["id"] as? String)?.hasPrefix("usd") == true }, "included": territories]
        } else if method.apiPath.hasSuffix("/territoryAvailabilities") {
            doc = ["data": [resource("territoryAvailabilities", "usa-availability", ["available": true, "preOrderEnabled": false, "contentStatuses": ["AVAILABLE"]], ["territory": ["type": "territories", "id": "USA"]]),
                resource("territoryAvailabilities", "japan-availability", ["available": false, "preOrderEnabled": false, "contentStatuses": ["MISSING_RATING"]], ["territory": ["type": "territories", "id": "JPN"]])], "included": territories]
        } else { throw URLError(.badURL) }
        return try JSONSerialization.data(withJSONObject: doc)
    }
}

@MainActor
extension BetaFeedbackAPI {
    static var sample: Self {
        Self(perform: { method in
            if method.apiPath.hasSuffix("/crashLog") {
                return Data(#"{"data":{"type":"betaCrashLogs","id":"sample-log","attributes":{"logText":"Incident Identifier: SAMPLE-123\nProcess: Northstar\nException Type: EXC_BAD_ACCESS\nThread 0 Crashed:\n0 Northstar  JourneyView.update() + 28"}}}"#.utf8)
            }
            let kind: BetaFeedbackKind = method.apiPath.hasSuffix(BetaFeedbackKind.crashes.rawValue) ? .crashes : .screenshots
            let row: [String: Any] = [
                "type": kind.rawValue, "id": kind == .crashes ? "sample-crash" : "sample-screenshot",
                "attributes": [
                    "createdDate": "2026-10-15T10:30:00Z",
                    "comment": kind == .crashes ? "The app closed when I opened my saved journey." : "The route summary is clipped on the smaller display. I attached a screenshot.",
                    "deviceModel": "iPhone 16", "osVersion": "iOS 26.0", "appPlatform": "IOS",
                    "locale": "en-US", "batteryPercentage": 82,
                    "screenshots": kind == .screenshots ? [["url": "https://example.invalid/tester-screenshot.png", "width": 390, "height": 600, "expirationDate": "2099-01-01T00:00:00Z"]] : []
                ],
                "relationships": ["build": ["data": ["type": "builds", "id": "sample-build"]],
                                  "tester": ["data": ["type": "betaTesters", "id": "sample-tester"]]]
            ]
            return try JSONSerialization.data(withJSONObject: ["data": [row], "links": ["self": "https://example.invalid"],
                "included": [["type": "builds", "id": "sample-build", "attributes": ["version": "42"]],
                             ["type": "betaTesters", "id": "sample-tester", "attributes": ["firstName": "Alex", "lastName": "Morgan", "email": "alex@example.invalid"]]]])
        }, screenshot: { _ in
            let image = NSImage(size: NSSize(width: 390, height: 600))
            image.lockFocus()
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 390, height: 600)).fill()
            ("Northstar\n\nMorning walk\n\nRoute summary\n\n4.2 km · 52 minutes\n\nA quiet walk by the river." as NSString).draw(
                in: NSRect(x: 28, y: 60, width: 340, height: 480),
                withAttributes: [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.labelColor])
            image.unlockFocus()
            guard let data = image.tiffRepresentation else { throw URLError(.cannotDecodeContentData) }
            return data
        })
    }
}

/// Process-wide safety boundary for review-submission UI tests. Test mode
/// requires an explicit environment marker in addition to a valid scenario,
/// so a missing or misspelled scenario fails closed instead of launching the
/// credential-backed production app.
enum ReviewSubmissionUITestSafety {
    static let environmentKey = "SHIPYARD_REVIEW_UI_TESTS"
    static let enabledValue = "1"
    static let scenarioArgument = "--review-ui-test-scenario"
    static let blockedRequestMessage = "App Store Connect requests are disabled during review UI tests."

    static var isEnabled: Bool {
        isEnabled(in: ProcessInfo.processInfo.environment)
    }

    static func isEnabled(in environment: [String: String]) -> Bool {
        environment[environmentKey] == enabledValue
    }

    static func scenarioValue(in arguments: [String]) -> String? {
        guard let flagIndex = arguments.firstIndex(of: scenarioArgument),
              arguments.indices.contains(flagIndex + 1) else { return nil }
        let value = arguments[flagIndex + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

/// Debug-only launch boundary for App Store marketing screenshots. A valid
/// screen plus the explicit environment marker are both required, so a typo
/// cannot fall through to the credential-backed production root.
enum AppStoreScreenshotSafety {
    static let environmentKey = "SHIPYARD_SCREENSHOT_MODE"
    static let enabledValue = "1"
    static let screenArgument = "--sample-data-screen"
    static let blockedRequestMessage = "App Store Connect requests are disabled while capturing sample-data screenshots."

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[environmentKey] == enabledValue
    }

    static func screenValue(in arguments: [String]) -> String? {
        guard let flagIndex = arguments.firstIndex(of: screenArgument),
              arguments.indices.contains(flagIndex + 1) else { return nil }
        let value = arguments[flagIndex + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

enum AppStoreScreenshotScreen: String, CaseIterable {
    case apps
    case builds
    case appInfo
    case ageRatings
    case feedback
    case pricing
    case reviews
    case release

    static var current: Self? {
        guard AppStoreScreenshotSafety.isEnabled else { return nil }
        return AppStoreScreenshotSafety.screenValue(in: ProcessInfo.processInfo.arguments)
            .flatMap(Self.init(rawValue:))
    }

    var appTab: AppDetailView.AppTab {
        switch self {
        case .apps, .builds: return .builds
        case .appInfo, .ageRatings: return .appInfo
        case .feedback: return .feedback
        case .pricing: return .pricing
        case .reviews: return .reviews
        case .release: return .release
        }
    }
}

/// Last-resort process boundary for hermetic review UI tests. Registering a
/// URLProtocol keeps every HTTP(S) URLSession request inside the app process;
/// APIClient still rejects its requests earlier with a domain-specific error.
final class ReviewSubmissionUITestNetworkBlocker: URLProtocol {
    static func installIfNeeded() {
        guard ReviewSubmissionUITestSafety.isEnabled || AppStoreScreenshotSafety.isEnabled else { return }
        _ = URLProtocol.registerClass(Self.self)
    }

    static func shouldBlock(
        _ request: URLRequest,
        environment: [String: String]
    ) -> Bool {
        let fixtureMode = ReviewSubmissionUITestSafety.isEnabled(in: environment)
            || environment[AppStoreScreenshotSafety.environmentKey] == AppStoreScreenshotSafety.enabledValue
        guard fixtureMode,
              let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    override class func canInit(with request: URLRequest) -> Bool {
        shouldBlock(request, environment: ProcessInfo.processInfo.environment)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let error = NSError(
            domain: "ReviewSubmissionUITestNetworkBlocker",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: ReviewSubmissionUITestSafety.blockedRequestMessage])
        client?.urlProtocol(self, didFailWithError: error)
    }

    override func stopLoading() {}
}

/// Launch-only fixtures for the XCUITest target. The host renders the real
/// release screen while keeping App Store Connect and Keychain completely out
/// of the test process.
enum ReviewSubmissionUITestScenario: String {
    case draft
    case ready
    case waiting
    case inReview
    case pendingDeveloperRelease
    case pendingAppleRelease
    case processingForDistribution
    case readyForSale
    case readyForDistribution
    case rejected
    case metadataRejected
    case invalidBinary
    case developerRejected
    case removedFromSale
    case developerRemovedFromSale
    case replacedWithNewVersion
    case delayed
    case unrelatedSubmission
    case staleVersionRecovery

    static var current: Self? {
        guard ReviewSubmissionUITestSafety.isEnabled else { return nil }
        return scenario(in: ProcessInfo.processInfo.arguments)
    }

    static func scenario(in arguments: [String]) -> Self? {
        ReviewSubmissionUITestSafety.scenarioValue(in: arguments).flatMap(Self.init(rawValue:))
    }

    var versionState: String {
        switch self {
        case .draft, .delayed, .staleVersionRecovery:
            return "PREPARE_FOR_SUBMISSION"
        case .ready: return "READY_FOR_REVIEW"
        case .waiting, .unrelatedSubmission: return "WAITING_FOR_REVIEW"
        case .inReview: return "IN_REVIEW"
        case .pendingDeveloperRelease: return "PENDING_DEVELOPER_RELEASE"
        case .pendingAppleRelease: return "PENDING_APPLE_RELEASE"
        case .processingForDistribution: return "PROCESSING_FOR_DISTRIBUTION"
        case .readyForSale: return "READY_FOR_SALE"
        case .readyForDistribution: return "READY_FOR_DISTRIBUTION"
        case .rejected: return "REJECTED"
        case .metadataRejected: return "METADATA_REJECTED"
        case .invalidBinary: return "INVALID_BINARY"
        case .developerRejected: return "DEVELOPER_REJECTED"
        case .removedFromSale: return "REMOVED_FROM_SALE"
        case .developerRemovedFromSale: return "DEVELOPER_REMOVED_FROM_SALE"
        case .replacedWithNewVersion: return "REPLACED_WITH_NEW_VERSION"
        }
    }

    /// A matching submission supplies deterministic history for every
    /// post-submit screen. Draft-only scenarios intentionally have none.
    var submissionState: String? {
        switch self {
        case .draft, .delayed, .staleVersionRecovery:
            return nil
        case .ready:
            return "READY_FOR_REVIEW"
        case .waiting, .unrelatedSubmission:
            return "WAITING_FOR_REVIEW"
        case .inReview:
            return "IN_REVIEW"
        default:
            return "COMPLETE"
        }
    }
}

struct ReviewSubmissionUITestConfigurationErrorView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 32))
                .foregroundStyle(ShipyardTheme.danger)
            Text("Review UI Test Configuration Error")
                .font(.headline)
            Text("A valid review-submission scenario is required. Production credentials and App Store Connect access remain disabled.")
                .multilineTextAlignment(.center)
                .foregroundStyle(ShipyardTheme.body)
                .frame(maxWidth: 460)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShipyardTheme.tableBackground)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("review.test.configuration-error")
    }
}

struct AppStoreScreenshotConfigurationErrorView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 32))
                .foregroundStyle(ShipyardTheme.danger)
            Text("Screenshot Configuration Error")
                .font(.headline)
            Text("Choose a valid sample-data screen. Production credentials and App Store Connect access remain disabled.")
                .multilineTextAlignment(.center)
                .foregroundStyle(ShipyardTheme.body)
                .frame(maxWidth: 460)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShipyardTheme.tableBackground)
        .accessibilityIdentifier("screenshot.configuration-error")
    }
}

@MainActor
struct ReviewSubmissionUITestHost: View {
    let app: AppsData

    @StateObject private var sidebarVM: SideBarViewModel
    @StateObject private var detailVM: DetailViewModel
    @StateObject private var reviewsVM: ReviewsViewModel
    @StateObject private var section = ReleaseSectionState()
    @StateObject private var toastCenter = ShipyardToastCenter()

    init(scenario: ReviewSubmissionUITestScenario) {
        let sidebarVM = SideBarViewModel()
        let detailVM = DetailViewModel(sidebarViewModel: sidebarVM, readsStoredTeam: false)
        let reviewsVM = ReviewsViewModel()

        let app = Self.fixtureApp()
        reviewsVM.configureForUITesting(scenario: scenario, app: app)

        self.app = app
        _sidebarVM = StateObject(wrappedValue: sidebarVM)
        _detailVM = StateObject(wrappedValue: detailVM)
        _reviewsVM = StateObject(wrappedValue: reviewsVM)
    }

    var body: some View {
        ReleaseTabView(
            app: app,
            detailVM: detailVM,
            reviewsVM: reviewsVM,
            section: section,
            onOpenAppInfo: {},
            onOpenBuilds: {})
        .environmentObject(toastCenter)
        // External App Store Connect / expedite links are inert in tests so
        // a future tap cannot hand off networking to the user's browser.
        .environment(\.openURL, OpenURLAction { _ in .discarded })
        .frame(minWidth: 1_080, minHeight: 720)
    }

    private static func fixtureApp() -> AppsData {
        var app = AppsData(
            id: "ui-test-app",
            name: "Shipyard UI Test App",
            appStoreVersions: [],
            appStoreIcon: nil)
        app.bundleId = "com.shipyard.uitests.reviewsubmission"
        app.primaryLocale = "en-US"
        return app
    }
}

@MainActor
struct AppStoreScreenshotHost: View {
    let screen: AppStoreScreenshotScreen
    let app: AppsData

    @StateObject private var sidebarVM: SideBarViewModel
    @StateObject private var detailVM: DetailViewModel
    @StateObject private var reviewsVM: ReviewsViewModel
    @StateObject private var betaVM = BetaViewModel()
    @StateObject private var toastCenter = ShipyardToastCenter()
    @State private var tab: AppDetailView.AppTab
    @State private var isReady = false

    init(screen: AppStoreScreenshotScreen) {
        let fixtures = ScreenshotFixtures()
        let sidebarVM = SideBarViewModel()
        let detailVM = DetailViewModel(sidebarViewModel: sidebarVM, readsStoredTeam: false)
        let reviewsVM = ReviewsViewModel()

        var sampleAppInfo = fixtures.appInfo
        if screen == .ageRatings, !sampleAppInfo.isEmpty {
            sampleAppInfo[0].state = "PREPARE_FOR_SUBMISSION"
            var declaration = AgeRatingDeclarationModel(id: "sample-age-rating")
            declaration.parentalControls = true
            declaration.advertising = false
            declaration.profanityOrCrudeHumor = "NONE"
            sampleAppInfo[0].ageRatingDeclaration = declaration
        }

        sidebarVM.configureForScreenshotSample(
            apps: fixtures.apps,
            selectedApp: fixtures.primaryApp,
            versions: fixtures.preReleaseVersions)
        detailVM.configureForScreenshotSample(
            app: fixtures.primaryApp,
            versions: fixtures.preReleaseVersions,
            selectedVersion: fixtures.preReleaseVersions[0],
            builds: fixtures.builds,
            appInfo: sampleAppInfo,
            versionLocalizations: fixtures.versionLocalizations)
        reviewsVM.configureForScreenshotSample(
            app: fixtures.primaryApp,
            reviews: fixtures.reviews,
            version: fixtures.appStoreVersion)

        self.screen = screen
        self.app = fixtures.primaryApp
        _sidebarVM = StateObject(wrappedValue: sidebarVM)
        _detailVM = StateObject(wrappedValue: detailVM)
        _reviewsVM = StateObject(wrappedValue: reviewsVM)
        _tab = State(initialValue: screen.appTab)
    }

    var body: some View {
        HStack(spacing: 0) {
            screenshotSidebar
                .frame(width: 238)
            ShipyardTheme.rowDivider.frame(width: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1_280, minHeight: 800)
        .background(ShipyardTheme.tableBackground)
        .environmentObject(toastCenter)
        .environment(\.openURL, OpenURLAction { _ in .discarded })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(isReady
            ? "screenshot.ready.\(screen.rawValue)"
            : "screenshot.preparing")
        .onAppear {
            DispatchQueue.main.async {
                prepareScreenshotWindow()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if screen == .apps {
            AppsTableView(sidebarVM: sidebarVM, onOpenApp: { _ in })
        } else {
            AppDetailView(
                app: app,
                sidebarVM: sidebarVM,
                detailVM: detailVM,
                reviewsVM: reviewsVM,
                betaVM: betaVM,
                onBack: {},
                onManage: { _ in },
                tab: $tab,
                feedbackAPI: .sample,
                pricingAPI: PricingSampleServer().api)
        }
    }

    private var screenshotSidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(ShipyardTheme.accent)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Northstar Studio")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ShipyardTheme.title)
                    Text("Sample workspace")
                        .font(.system(size: 10))
                        .foregroundStyle(ShipyardTheme.body)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ShipyardTheme.body)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sidebarRow(.apps, selected: true)
                    VStack(alignment: .leading, spacing: 4) {
                        sidebarHeader("MONITORING")
                        sidebarRow(.monitoring, selected: false)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        sidebarHeader("TEAM RESOURCES")
                        sidebarRow(.devices, selected: false)
                        sidebarRow(.certificates, selected: false)
                        sidebarRow(.identifiers, selected: false)
                        sidebarRow(.bundleIDs, selected: false)
                        sidebarRow(.profiles, selected: false)
                        sidebarRow(.users, selected: false)
                    }
                }
                .padding(8)
            }
            Spacer(minLength: 0)
            Divider()
            HStack {
                Label("Settings", systemImage: "gearshape")
                Spacer()
                Label("Help", systemImage: "questionmark.circle")
            }
            .font(.system(size: 11))
            .foregroundStyle(ShipyardTheme.body)
            .padding(.horizontal, 14)
            .frame(height: 44)
        }
        .background(ShipyardTheme.sidebarBackground)
    }

    private func sidebarHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(ShipyardTheme.tertiary)
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
    }

    private func sidebarRow(_ section: ShipyardSection, selected: Bool) -> some View {
        sampleRow(section.title, icon: section.iconName, selected: selected, isAsset: true)
    }

    private func sampleRow(_ title: String, icon: String, selected: Bool, isAsset: Bool = false) -> some View {
        HStack(spacing: 10) {
            Group {
                if isAsset {
                    ShipyardIcon(name: icon, size: 14)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                }
            }
            .frame(width: 18)
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
            Spacer()
        }
        .foregroundStyle(selected ? ShipyardTheme.accent : ShipyardTheme.title)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(selected ? ShipyardTheme.accent.opacity(0.12) : .clear)
        .cornerRadius(7)
    }

    private func prepareScreenshotWindow() {
        guard let window = NSApp.keyWindow
            ?? NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) }) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                prepareScreenshotWindow()
            }
            return
        }

        var frame = window.frame
        frame.size = NSSize(width: 1_440, height: 900)
        if let visibleFrame = window.screen?.visibleFrame {
            frame.origin.x = visibleFrame.midX - (frame.width / 2)
            frame.origin.y = visibleFrame.midY - (frame.height / 2)
        }
        window.setFrame(frame, display: true)
        // Let the resized window and asset-backed sidebar icons finish one
        // render pass before XCTest captures it. Without this delay, a fresh
        // launch can occasionally produce an empty sidebar in one image.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isReady = true
        }
    }
}

@MainActor
private struct ScreenshotFixtures {
    let apps: [AppsData]
    let primaryApp: AppsData
    let preReleaseVersions: [PreReleaseVersionsModel]
    let builds: [BuildsModel]
    let appInfo: [AppInfoModel]
    let versionLocalizations: [AppStoreVersionLocalizationsModel]
    let reviews: [CustomerReviewModel]
    let appStoreVersion: AppStoreVersionsModel

    init() {
        func makeApp(_ id: String, _ name: String, _ bundleId: String, _ version: String, _ state: String) -> AppsData {
            var platformVersion = AppStoreVersionsModel(
                id: "platform-\(id)",
                appStoreVersionLocalizations: []
            )
            platformVersion.versionString = version
            platformVersion.platform = "MAC_OS"
            platformVersion.appStoreState = state
            var value = AppsData(
                id: id,
                name: name,
                appStoreVersions: [platformVersion],
                appStoreIcon: nil
            )
            value.bundleId = bundleId
            value.primaryLocale = "en-US"
            value.currentLiveVersion = ("live-\(id)", version)
            value.currentState = state
            return value
        }

        var primary = makeApp("northstar", "Northstar", "com.example.northstar", "3.8.1", "READY_FOR_SALE")
        primary.currentLiveVersion = ("northstar-live", "3.8.1")
        primaryApp = primary
        apps = [
            primary,
            makeApp("atlas", "Atlas Journal", "com.example.atlas", "2.6.0", "READY_FOR_SALE"),
            makeApp("harbor", "Harbor Weather", "com.example.harbor", "5.1.2", "PREPARE_FOR_SUBMISSION"),
            makeApp("lumen", "Lumen Tasks", "com.example.lumen", "4.4.0", "WAITING_FOR_REVIEW"),
            makeApp("orbit", "Orbit Finance", "com.example.orbit", "1.9.3", "READY_FOR_SALE"),
            makeApp("trail", "Trail Notes", "com.example.trail", "7.0.1", "PROCESSING_FOR_DISTRIBUTION")
        ]

        var version38 = PreReleaseVersionsModel(id: "sample-pre-38")
        version38.version = "3.9.0"
        version38.platform = "MAC_OS"
        version38.appStoreState = "PREPARE_FOR_SUBMISSION"
        version38.createdDate = "2026-10-06T09:20:00Z"
        version38.isSelected = true
        var version37 = PreReleaseVersionsModel(id: "sample-pre-37")
        version37.version = "3.8.1"
        version37.platform = "MAC_OS"
        version37.appStoreState = "READY_FOR_SALE"
        version37.createdDate = "2026-09-18T13:10:00Z"
        preReleaseVersions = [version38, version37]

        func makeBuild(
            _ id: String,
            _ number: String,
            _ state: String,
            _ date: String,
            version: PreReleaseVersionsModel,
            expired: Bool = false,
            note: String
        ) -> BuildsModel {
            var localization = BuildLocalizationsModel(id: "loc-\(id)")
            localization.locale = "en-US"
            localization.whatsNew = note
            var value = BuildsModel(id: id, betaBuildLocalizations: [localization])
            value.version = number
            value.uploadedDate = date
            value.processingState = state
            value.expired = expired
            value.preReleaseVersion = version
            return value
        }
        builds = [
            makeBuild("build-482", "482", "VALID", "2026-10-13T12:42:00Z", version: version38, note: "Improved launch speed and refined the release dashboard."),
            makeBuild("build-481", "481", "PROCESSING", "2026-10-13T09:15:00Z", version: version38, note: "Updated onboarding guidance and accessibility labels."),
            makeBuild("build-476", "476", "VALID", "2026-10-10T16:08:00Z", version: version38, note: "Fixed a sync issue when switching between teams."),
            makeBuild("build-469", "469", "FAILED", "2026-10-08T11:30:00Z", version: version38, note: "Internal QA build."),
            makeBuild("build-452", "452", "VALID", "2026-09-28T08:05:00Z", version: version38, expired: true, note: "Previous beta milestone.")
        ]

        var infoLocalization = AppInfoLocalizationModel(id: "sample-info-en")
        infoLocalization.locale = "en-US"
        infoLocalization.name = "Northstar"
        infoLocalization.subtitle = "Plan releases with confidence"
        infoLocalization.privacyPolicyUrl = "https://example.com/privacy"
        var info = AppInfoModel(id: "sample-info", appInfoLocalizations: [infoLocalization])
        info.state = "READY_FOR_SALE"
        info.appStoreAgeRating = "FOUR_PLUS"
        info.primaryCategory = AppCategoryModel(id: "PRODUCTIVITY")
        appInfo = [info]

        var versionLocalization = AppStoreVersionLocalizationsModel(id: "sample-version-en")
        versionLocalization.locale = "en-US"
        versionLocalization.descriptionData = "Northstar brings builds, TestFlight notes, App Store metadata, reviews, and release status into one focused workspace."
        versionLocalization.keywords = "release,testflight,builds,metadata,reviews"
        versionLocalization.promotionalText = "Ship confidently from one clear release workspace."
        versionLocalization.supportUrl = "https://example.com/support"
        versionLocalization.marketingUrl = "https://example.com/northstar"
        versionLocalization.whatsNew = "Faster sync, clearer permissions, and a refreshed review inbox."
        versionLocalizations = [versionLocalization]

        func makeReview(_ id: String, rating: Int, title: String, body: String, name: String, date: String, territory: String, reply: String? = nil) -> CustomerReviewModel {
            var value = CustomerReviewModel(id: id)
            value.rating = rating
            value.title = title
            value.body = body
            value.reviewerNickname = name
            value.createdDate = date
            value.territory = territory
            if let reply {
                var response = CustomerReviewResponseModel(id: "response-\(id)")
                response.responseBody = reply
                response.state = "PUBLISHED"
                response.lastModifiedDate = date
                value.response = response
            }
            return value
        }
        reviews = [
            makeReview("review-1", rating: 5, title: "Finally, a calm release day", body: "The build and metadata workflow is clear and fast.", name: "Maya R.", date: "2026-10-12T14:25:00Z", territory: "USA", reply: "Thank you — we are glad Northstar helps your team ship calmly."),
            makeReview("review-2", rating: 5, title: "Everything in one place", body: "I can check TestFlight notes and review status without switching tabs.", name: "Theo", date: "2026-10-10T08:40:00Z", territory: "GBR"),
            makeReview("review-3", rating: 4, title: "Great for small teams", body: "Permissions are much easier to understand now.", name: "Sofia P.", date: "2026-10-08T18:05:00Z", territory: "ESP", reply: "Thanks for the thoughtful feedback!"),
            makeReview("review-4", rating: 5, title: "Excellent release companion", body: "The new review inbox saves us time every week.", name: "Kenji", date: "2026-10-05T06:15:00Z", territory: "JPN"),
            makeReview("review-5", rating: 4, title: "Clean and focused", body: "Useful status details without extra clutter.", name: "Amelia", date: "2026-10-02T11:45:00Z", territory: "AUS")
        ]

        var storeVersion = AppStoreVersionsModel(id: "sample-version", appStoreVersionLocalizations: [])
        storeVersion.versionString = "3.9.0"
        storeVersion.platform = "MAC_OS"
        storeVersion.appStoreState = "PREPARE_FOR_SUBMISSION"
        storeVersion.appVersionState = "PREPARE_FOR_SUBMISSION"
        storeVersion.releaseType = "MANUAL"
        storeVersion.createdDate = "2026-10-06T09:20:00Z"
        storeVersion.copyright = "2026 Northstar Studio"
        storeVersion.build = builds[0]
        appStoreVersion = storeVersion
    }
}
#endif
