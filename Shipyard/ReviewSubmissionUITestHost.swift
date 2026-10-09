#if DEBUG
import Foundation
import SwiftUI

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

/// Last-resort process boundary for hermetic review UI tests. Registering a
/// URLProtocol keeps every HTTP(S) URLSession request inside the app process;
/// APIClient still rejects its requests earlier with a domain-specific error.
final class ReviewSubmissionUITestNetworkBlocker: URLProtocol {
    static func installIfNeeded() {
        guard ReviewSubmissionUITestSafety.isEnabled else { return }
        _ = URLProtocol.registerClass(Self.self)
    }

    static func shouldBlock(
        _ request: URLRequest,
        environment: [String: String]
    ) -> Bool {
        guard ReviewSubmissionUITestSafety.isEnabled(in: environment),
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
#endif
