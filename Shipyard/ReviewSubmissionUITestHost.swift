#if DEBUG
import SwiftUI

/// Launch-only fixtures for the XCUITest target. The host renders the real
/// release screen while keeping App Store Connect and Keychain completely out
/// of the test process.
enum ReviewSubmissionUITestScenario: String {
    case draft
    case ready
    case waiting
    case delayed
    case unrelatedSubmission
    case staleVersionRecovery

    static var current: Self? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--review-ui-test-scenario"),
              arguments.indices.contains(flagIndex + 1) else { return nil }
        return Self(rawValue: arguments[flagIndex + 1])
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
        .frame(minWidth: 1_080, minHeight: 720)
        .accessibilityIdentifier("review.test.host")
    }

    private static func fixtureApp() -> AppsData {
        var app = AppsData(
            id: "ui-test-app",
            name: "Under Armour Me",
            appStoreVersions: [],
            appStoreIcon: nil)
        app.bundleId = "com.example.underarmourme"
        app.primaryLocale = "en-US"
        return app
    }
}
#endif
