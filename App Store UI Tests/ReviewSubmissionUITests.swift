import XCTest

@MainActor
final class ReviewSubmissionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    func testSubmitKeepsProgressVisibleThroughReadyUntilWaiting() {
        launch("draft")

        let submit = button("review.submit")
        XCTAssertTrue(submit.waitForExistence(timeout: 3))
        XCTAssertTrue(submit.isEnabled)
        submit.click()

        let confirm = button("review.submit.confirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.click()

        let progress = element("review.sync.progress")
        XCTAssertTrue(progress.waitForExistence(timeout: 3))

        XCTAssertTrue(element("review.ready.card").waitForExistence(timeout: 3))
        XCTAssertTrue(progress.exists, "The loader must remain visible while Apple reports READY_FOR_REVIEW.")

        XCTAssertTrue(element("review.waiting.card").waitForExistence(timeout: 4))
        XCTAssertTrue(progress.waitForNonExistence(timeout: 2))
    }

    func testReadyAndWaitingAreRenderedAsDifferentStates() {
        launch("ready")
        XCTAssertTrue(element("review.ready.card").waitForExistence(timeout: 3))
        XCTAssertFalse(element("review.waiting.card").exists)

        app.terminate()
        launch("waiting")
        XCTAssertTrue(element("review.waiting.card").waitForExistence(timeout: 3))
        XCTAssertFalse(element("review.ready.card").exists)
    }

    func testDelayedSyncCanRetryAndReachWaiting() {
        launch("delayed")

        let retry = button("review.sync.retry")
        XCTAssertTrue(retry.waitForExistence(timeout: 3))
        XCTAssertTrue(button("review.sync.dismiss").exists)
        retry.click()

        XCTAssertTrue(element("review.sync.progress").waitForExistence(timeout: 2))
        XCTAssertTrue(element("review.waiting.card").waitForExistence(timeout: 3))
    }

    func testDelayedSyncCanBeDismissedWithoutTrappingActions() {
        launch("delayed")

        let dismiss = button("review.sync.dismiss")
        XCTAssertTrue(dismiss.waitForExistence(timeout: 3))
        dismiss.click()

        let submit = button("review.submit")
        XCTAssertTrue(submit.waitForExistence(timeout: 2))
        XCTAssertTrue(submit.isEnabled)
    }

    func testCancellationReturnsVersionToDraft() {
        launch("ready")

        let cancel = button("review.cancel")
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.click()

        let confirm = button("review.cancel.confirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.click()

        XCTAssertTrue(element("review.status.PREPARE_FOR_SUBMISSION").waitForExistence(timeout: 3))
        XCTAssertTrue(button("review.submit").waitForExistence(timeout: 2))
    }

    func testUnrelatedSubmissionCannotCancelCurrentVersion() {
        launch("unrelatedSubmission")

        XCTAssertTrue(element("review.waiting.card").waitForExistence(timeout: 3))
        XCTAssertFalse(button("review.cancel").exists)
        XCTAssertTrue(button("review.expedite").exists)
    }

    func testStaleVersionRecoveryUnlocksSubmit() {
        launch("staleVersionRecovery")

        XCTAssertTrue(element("review.sync.progress").waitForExistence(timeout: 2))
        let submit = button("review.submit")
        XCTAssertTrue(submit.waitForExistence(timeout: 3))
        XCTAssertTrue(submit.isEnabled)
    }

    private func launch(_ scenario: String) {
        app = XCUIApplication()
        app.launchArguments = [
            "--review-ui-test-scenario", scenario,
            "-ApplePersistenceIgnoreState", "YES"
        ]
        app.launch()
        XCTAssertTrue(element("review.test.host").waitForExistence(timeout: 5))
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
