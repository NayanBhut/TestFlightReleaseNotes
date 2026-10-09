import XCTest

@MainActor
final class ReviewSubmissionUITests: XCTestCase {
    private let interactionTimeout: TimeInterval = 6
    private let launchTimeout: TimeInterval = 8
    private var app: XCUIApplication!

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    func testSubmitKeepsProgressVisibleThroughReadyUntilWaiting() {
        launch("draft")

        let submit = button("review.submit")
        XCTAssertTrue(submit.waitForExistence(timeout: interactionTimeout))
        XCTAssertTrue(submit.isEnabled)
        submit.click()

        let confirm = button("review.submit.confirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: interactionTimeout))
        confirm.click()

        let progress = element("review.sync.progress")
        XCTAssertTrue(progress.waitForExistence(timeout: interactionTimeout))

        XCTAssertTrue(element("review.ready.card").waitForExistence(timeout: interactionTimeout))
        XCTAssertTrue(progress.exists, "The loader must remain visible while Apple reports READY_FOR_REVIEW.")

        XCTAssertTrue(element("review.waiting.card").waitForExistence(timeout: interactionTimeout))
        XCTAssertTrue(progress.waitForNonExistence(timeout: interactionTimeout))
    }

    func testReadyAndWaitingAreRenderedAsDifferentStates() {
        launch("ready")
        XCTAssertTrue(element("review.ready.card").waitForExistence(timeout: interactionTimeout))
        XCTAssertFalse(element("review.waiting.card").exists)

        app.terminate()
        launch("waiting")
        XCTAssertTrue(element("review.waiting.card").waitForExistence(timeout: interactionTimeout))
        XCTAssertFalse(element("review.ready.card").exists)
    }

    func testDelayedSyncCanRetryAndReachWaiting() {
        launch("delayed")

        let retry = button("review.sync.retry")
        XCTAssertTrue(retry.waitForExistence(timeout: interactionTimeout))
        XCTAssertTrue(button("review.sync.dismiss").exists)
        retry.click()

        XCTAssertTrue(element("review.sync.progress").waitForExistence(timeout: interactionTimeout))
        XCTAssertTrue(element("review.waiting.card").waitForExistence(timeout: interactionTimeout))
    }

    func testDelayedSyncCanBeDismissedWithoutTrappingActions() {
        launch("delayed")

        let dismiss = button("review.sync.dismiss")
        XCTAssertTrue(dismiss.waitForExistence(timeout: interactionTimeout))
        dismiss.click()

        let submit = button("review.submit")
        XCTAssertTrue(submit.waitForExistence(timeout: interactionTimeout))
        XCTAssertTrue(submit.isEnabled)
    }

    func testCancellationReturnsVersionToDraft() {
        launch("ready")

        let cancel = button("review.cancel")
        XCTAssertTrue(cancel.waitForExistence(timeout: interactionTimeout))
        cancel.click()

        let confirm = button("review.cancel.confirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: interactionTimeout))
        confirm.click()

        XCTAssertTrue(element("review.status.PREPARE_FOR_SUBMISSION").waitForExistence(timeout: interactionTimeout))
        XCTAssertTrue(button("review.submit").waitForExistence(timeout: interactionTimeout))
    }

    func testUnrelatedSubmissionCannotCancelCurrentVersion() {
        launch("unrelatedSubmission")

        XCTAssertTrue(element("review.waiting.card").waitForExistence(timeout: interactionTimeout))
        XCTAssertFalse(button("review.cancel").exists)
        XCTAssertTrue(button("review.expedite").exists)
    }

    func testStaleVersionRecoveryUnlocksSubmit() {
        launch("staleVersionRecovery")

        XCTAssertTrue(element("review.sync.progress").waitForExistence(timeout: interactionTimeout))
        let submit = button("review.submit")
        XCTAssertTrue(submit.waitForExistence(timeout: interactionTimeout))
        XCTAssertTrue(submit.isEnabled)
    }

    func testInvalidScenarioFailsClosedBeforeProductionLoads() {
        app = XCUIApplication()
        app.launchEnvironment["SHIPYARD_REVIEW_UI_TESTS"] = "1"
        app.launchArguments = [
            "--review-ui-test-scenario", "invalid-scenario",
            "-ApplePersistenceIgnoreState", "YES"
        ]
        app.launch()

        XCTAssertTrue(
            element("review.test.configuration-error").waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(button("review.submit").exists)
    }

    private func launch(_ scenario: String) {
        app = XCUIApplication()
        app.launchEnvironment["SHIPYARD_REVIEW_UI_TESTS"] = "1"
        app.launchArguments = [
            "--review-ui-test-scenario", scenario,
            "-ApplePersistenceIgnoreState", "YES"
        ]
        app.launch()
        XCTAssertTrue(
            button("review.version.ui-test-version-primary").waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(
            app.staticTexts["Shipyard UI Test App"].waitForExistence(timeout: launchTimeout),
            "Review UI tests must render the synthetic app fixture, never a real app.")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func button(_ identifier: String) -> XCUIElement {
        app.buttons.matching(identifier: identifier).firstMatch
    }
}

private extension XCUIElement {
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
