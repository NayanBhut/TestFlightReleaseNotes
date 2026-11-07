import XCTest

@MainActor
final class ReviewSubmissionUITests: XCTestCase {
    private let interactionTimeout: TimeInterval = 6
    private let launchTimeout: TimeInterval = 8
    private var app: XCUIApplication!

    func testAppsListUsesLiveAndUpcomingAppStoreVersions() {
        app = XCUIApplication()
        app.launchEnvironment["SHIPYARD_SCREENSHOT_MODE"] = "1"
        app.launchArguments = ["--sample-data-screen", "apps", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(element("screenshot.ready.apps").waitForExistence(timeout: launchTimeout))
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Northstar,")).firstMatch
        XCTAssertTrue(row.exists)
        XCTAssertTrue(row.label.contains("Live 3.8.1"), row.label)
        XCTAssertTrue(row.label.contains("Next 3.8.2 · Waiting for Review"), row.label)
        XCTAssertFalse(row.label.contains("3.9.0"), "The TestFlight version must not supply App Store details")
        let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        capture.name = "apps-app-store-versions"
        capture.lifetime = .keepAlways
        add(capture)
    }

    func testReviewsEmptyControlsAndDraftWithdrawalConfirmation() {
        app = XCUIApplication()
        app.launchEnvironment["SHIPYARD_SCREENSHOT_MODE"] = "1"
        app.launchArguments = ["--sample-data-screen", "reviewsEmpty", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(element("screenshot.ready.reviewsEmpty").waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(app.textFields["reviews.search"].isEnabled)
        for id in ["rating", "territory", "date", "sort", "reply"] {
            let filter = element("reviews.filter.\(id)")
            XCTAssertTrue(filter.exists)
            XCTAssertFalse(filter.isEnabled)
            XCTAssertGreaterThanOrEqual(filter.frame.height, 28)
        }
        let count = element("reviews.count")
        XCTAssertTrue(((count.value as? String) ?? count.label).contains("0 of 0"))
        XCTAssertEqual(app.buttons.matching(identifier: "reviews.refresh").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "reviews.open-listing").count, 1)
        let draft = button("reviews.submission.cancel.sample-draft")
        XCTAssertTrue(draft.exists)
        XCTAssertEqual(draft.label, "Discard Draft")
        let waiting = button("reviews.submission.cancel.sample-waiting")
        XCTAssertEqual(waiting.label, "Withdraw")
        draft.click()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "value CONTAINS %@", "unsubmitted review draft")).firstMatch
            .waitForExistence(timeout: interactionTimeout))
        button("Keep Submission").click()
        XCTAssertTrue(draft.isEnabled, "Dismissing confirmation must preserve the draft")
        let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        capture.name = "reviews-empty-and-submissions"
        capture.lifetime = .keepAlways
        add(capture)
    }

    func testReviewsSearchRecoveryKeepsPaginationAndFiltersAvailable() {
        app = XCUIApplication()
        app.launchEnvironment["SHIPYARD_SCREENSHOT_MODE"] = "1"
        app.launchArguments = ["--sample-data-screen", "reviews", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(element("screenshot.ready.reviews").waitForExistence(timeout: launchTimeout))
        let search = app.textFields["reviews.search"]
        let rating = element("reviews.filter.rating")
        XCTAssertTrue(search.isEnabled)
        XCTAssertGreaterThan(search.frame.width, 600)
        XCTAssertLessThan(search.frame.maxY, rating.frame.minY)
        search.click()
        search.typeText("zzzz-no-matching-review")
        XCTAssertTrue(app.staticTexts["No matching reviews"].waitForExistence(timeout: interactionTimeout))
        XCTAssertTrue(rating.isEnabled, "Filters must stay usable when matches are zero but loaded reviews exist")
        XCTAssertTrue(button("reviews.load-more").exists, "Pagination must remain available when filters hide loaded rows")
        XCTAssertTrue(button("reviews.search.clear").exists)
        button("reviews.search.clear").click()
        XCTAssertTrue(app.staticTexts["No matching reviews"].waitForNonExistence(timeout: interactionTimeout))
        let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        capture.name = "reviews-loaded-and-filters"
        capture.lifetime = .keepAlways
        add(capture)
    }

    func testWaitingAppInfoShowsReviewStatusAndDisablesMetadataEdits() {
        app = XCUIApplication()
        app.launchEnvironment["SHIPYARD_SCREENSHOT_MODE"] = "1"
        app.launchArguments = ["--sample-data-screen", "appInfoWaiting", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        let status = app.staticTexts["app-info.read-only-status"]
        XCTAssertTrue(status.waitForExistence(timeout: launchTimeout))
        let message = (status.value as? String) ?? status.label
        XCTAssertTrue(message.contains("Waiting for Review"), message)
        XCTAssertFalse(message.contains("live"), message)
        XCTAssertFalse(app.textFields["App Name"].firstMatch.isEnabled)
        XCTAssertFalse(app.textViews.firstMatch.isEnabled)
        XCTAssertFalse(button("Save metadata changes").isEnabled)
        XCTAssertFalse(button("Remove en-US localization").isEnabled)
        app.buttons["App Store Versions"].firstMatch.click()
        XCTAssertTrue(button("review.view-info").waitForExistence(timeout: interactionTimeout))
    }

    func testEmptyBetaGroupsAndCreateFirstGroup() {
        app = XCUIApplication()
        app.launchEnvironment["SHIPYARD_SCREENSHOT_MODE"] = "1"
        app.launchArguments = ["--sample-data-screen", "groups", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(element("screenshot.ready.groups").waitForExistence(timeout: launchTimeout))
        let create = button("beta-groups.create-empty")
        XCTAssertTrue(create.waitForExistence(timeout: interactionTimeout))
        XCTAssertFalse(element("beta-groups.loading").exists, "An empty response must stop the spinner")
        XCTAssertTrue(create.isEnabled)
        create.click()
        let confirm = button("beta-groups.confirm-create")
        XCTAssertTrue(confirm.waitForExistence(timeout: interactionTimeout))
        XCTAssertFalse(confirm.isEnabled, "A group requires a name")
        app.windows.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: interactionTimeout))
        button("beta-groups.new").click()
        let name = app.textFields["beta-groups.name"]
        XCTAssertTrue(name.waitForExistence(timeout: interactionTimeout))
        app.radioButtons["Internal"].click()
        name.click()
        name.typeText("Early Access")
        XCTAssertTrue(confirm.isEnabled)
        confirm.click()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: interactionTimeout))
        XCTAssertTrue(app.staticTexts["Early Access"].firstMatch.waitForExistence(timeout: interactionTimeout))
        XCTAssertTrue(app.staticTexts["INTERNAL"].exists)
        XCTAssertFalse(create.exists)
        XCTAssertFalse(element("beta-groups.loading").exists)
        XCTAssertTrue(button("beta-groups.new").isEnabled, "New groups must remain available once a group exists")
        let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        capture.name = "beta-group-created"
        capture.lifetime = .keepAlways
        add(capture)
    }

    func testPricingAndAvailabilityWithReviewedSamplePriceChange() {
        app = XCUIApplication()
        app.launchEnvironment["SHIPYARD_SCREENSHOT_MODE"] = "1"
        app.launchArguments = ["--sample-data-screen", "pricing", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(element("screenshot.ready.pricing").waitForExistence(timeout: launchTimeout))
        let schedule = button("pricing.schedule")
        XCTAssertTrue(schedule.waitForExistence(timeout: interactionTimeout))
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: schedule)
        waitForExpectations(timeout: interactionTimeout)
        let prices = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        prices.name = "pricing-manual-prices"; prices.lifetime = .keepAlways; add(prices)

        app.radioButtons["Availability"].click()
        XCTAssertTrue(element("pricing.availability-table").waitForExistence(timeout: interactionTimeout))
        XCTAssertTrue(app.staticTexts["Missing Rating"].waitForExistence(timeout: interactionTimeout))
        let availability = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        availability.name = "pricing-territory-availability"; availability.lifetime = .keepAlways; add(availability)

        app.radioButtons["Prices"].click()
        schedule.click()
        let review = button("pricing.review-change")
        XCTAssertTrue(review.waitForExistence(timeout: interactionTimeout))
        XCTAssertFalse(review.isEnabled, "Opening the editor must never schedule a price")
        let point = app.popUpButtons["pricing.new-price"]
        XCTAssertTrue(point.waitForExistence(timeout: interactionTimeout))
        point.click()
        let amount = app.menuItems["USD 2.99"]
        XCTAssertTrue(amount.waitForExistence(timeout: interactionTimeout))
        amount.click()
        XCTAssertTrue(review.isEnabled)
        let editor = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        editor.name = "pricing-schedule-editor"; editor.lifetime = .keepAlways; add(editor)
        review.click()
        let confirm = button("pricing.confirm-change")
        XCTAssertTrue(confirm.waitForExistence(timeout: interactionTimeout))
        confirm.click()
        XCTAssertTrue(review.waitForNonExistence(timeout: interactionTimeout))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "value CONTAINS %@", "Price change confirmed")).firstMatch
            .waitForExistence(timeout: interactionTimeout))
        XCTAssertFalse(schedule.isEnabled, "A future base-price schedule must be managed in the portal")
    }

    func testTestFlightFeedbackScreenshotsCrashLogsAndSearch() {
        app = XCUIApplication()
        app.launchEnvironment["SHIPYARD_SCREENSHOT_MODE"] = "1"
        app.launchArguments = ["--sample-data-screen", "feedback", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(element("screenshot.ready.feedback").waitForExistence(timeout: launchTimeout))
        let screenshotsSegment = app.radioButtons["Screenshots"]
        let crashesSegment = app.radioButtons["Crashes"]
        XCTAssertTrue(screenshotsSegment.waitForExistence(timeout: interactionTimeout))
        XCTAssertEqual(screenshotsSegment.frame.midY, crashesSegment.frame.midY, accuracy: 1)
        XCTAssertLessThan(screenshotsSegment.frame.height, 30, "Segment labels must stay on one line")
        XCTAssertEqual(screenshotsSegment.frame.midY, app.textFields["feedback.search"].frame.midY, accuracy: 3)
        XCTAssertEqual(screenshotsSegment.frame.midY, element("feedback.filters").frame.midY, accuracy: 3)
        XCTAssertLessThan(app.buttons["TestFlight Feedback"].firstMatch.frame.height, 30,
                          "The app navigation tab must stay on one line")
        let row = element("feedback.row.sample-screenshot")
        XCTAssertTrue(row.waitForExistence(timeout: interactionTimeout))
        row.click()
        XCTAssertTrue(button("feedback.screenshot").waitForExistence(timeout: interactionTimeout))
        XCTAssertTrue(element("feedback.note").exists)
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "testflight-screenshot-feedback"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        button("feedback.screenshot").click()
        let done = app.windows.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: interactionTimeout))
        done.click()

        let crashes = app.descendants(matching: .any).matching(identifier: "Crashes").firstMatch
        XCTAssertTrue(crashes.waitForExistence(timeout: interactionTimeout))
        crashes.click()
        let crash = element("feedback.row.sample-crash")
        XCTAssertTrue(crash.waitForExistence(timeout: interactionTimeout))
        crash.click()
        XCTAssertTrue(element("feedback.crash-log").waitForExistence(timeout: interactionTimeout))
        XCTAssertTrue(button("feedback.copy-log").isEnabled)
        let log = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        log.name = "testflight-crash-feedback"
        log.lifetime = .keepAlways
        add(log)

        let search = app.textFields["feedback.search"]
        search.click()
        search.typeText("does-not-match")
        XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: interactionTimeout))
        app.windows.buttons["Clear Filters"].firstMatch.click()
        XCTAssertTrue(crash.waitForExistence(timeout: interactionTimeout))
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    func testAgeRatingEditorPreservesDraftUntilDiscarded() {
        app = XCUIApplication()
        app.launchEnvironment["SHIPYARD_SCREENSHOT_MODE"] = "1"
        app.launchArguments = ["--sample-data-screen", "ageRatings", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(element("screenshot.ready.ageRatings").waitForExistence(timeout: launchTimeout))
        let edit = button("app-info.age-ratings")
        XCTAssertTrue(edit.waitForExistence(timeout: interactionTimeout))
        for _ in 0..<6 where !edit.isHittable {
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -400)
        }
        XCTAssertTrue(edit.isHittable)
        edit.click()
        let save = button("age-ratings.save")
        XCTAssertTrue(save.waitForExistence(timeout: interactionTimeout))
        XCTAssertFalse(save.isEnabled, "Opening saved answers must not create changes.")

        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "age-rating-questionnaire"
        attachment.lifetime = .keepAlways
        add(attachment)

        let controls = app.popUpButtons["age-ratings.answer.parentalControls"]
        XCTAssertTrue(controls.waitForExistence(timeout: interactionTimeout))
        controls.click()
        app.menuItems["No"].click()
        XCTAssertTrue(save.isEnabled)
        app.windows.buttons["Cancel"].firstMatch.click()
        let keep = app.windows.buttons["Keep Editing"].firstMatch
        XCTAssertTrue(keep.waitForExistence(timeout: interactionTimeout))
        keep.click()
        XCTAssertTrue(save.isEnabled, "Keep Editing must retain the draft.")
        app.windows.buttons["Cancel"].firstMatch.click()
        app.windows.buttons["Discard Changes"].firstMatch.click()
        XCTAssertTrue(save.waitForNonExistence(timeout: interactionTimeout))
    }

    func testCaptureAppStoreScreenshots() throws {
        let screens = ["apps", "builds", "appInfo", "reviews", "release"]
        for (index, screen) in screens.enumerated() {
            app?.terminate()
            app = XCUIApplication()
            app.launchEnvironment["SHIPYARD_SCREENSHOT_MODE"] = "1"
            app.launchArguments = [
                "--sample-data-screen", screen,
                "-ApplePersistenceIgnoreState", "YES"
            ]
            app.launch()

            XCTAssertTrue(
                element("screenshot.ready.\(screen)").waitForExistence(timeout: launchTimeout),
                "Sample-data screen \(screen) did not become ready.")
            let window = app.windows.firstMatch
            XCTAssertTrue(window.waitForExistence(timeout: launchTimeout))
            let number = String(format: "%02d", index + 1)
            let attachment = XCTAttachment(screenshot: window.screenshot())
            attachment.name = "\(number)-\(screen).png"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
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

    func testEveryAppStoreLifecycleStateUsesSyntheticFixture() {
        let fixtures: [(scenario: String, state: String, actions: [String], absent: [String])] = [
            ("draft", "PREPARE_FOR_SUBMISSION", ["review.submit"], []),
            ("ready", "READY_FOR_REVIEW", ["review.cancel"], []),
            ("waiting", "WAITING_FOR_REVIEW", ["review.cancel", "review.expedite"], []),
            ("inReview", "IN_REVIEW", ["review.message-app-review"], ["review.cancel", "review.submit"]),
            ("pendingDeveloperRelease", "PENDING_DEVELOPER_RELEASE", ["review.release"], ["review.submit"]),
            ("pendingAppleRelease", "PENDING_APPLE_RELEASE", ["review.manage-schedule"], ["review.release"]),
            ("processingForDistribution", "PROCESSING_FOR_DISTRIBUTION", [], ["review.submit", "review.release"]),
            ("readyForSale", "READY_FOR_SALE", ["review.remove-from-sale"], ["review.submit"]),
            ("readyForDistribution", "READY_FOR_DISTRIBUTION", ["review.remove-from-sale", "review.phased.pause"], ["review.submit"]),
            ("rejected", "REJECTED", ["review.submit"], []),
            ("metadataRejected", "METADATA_REJECTED", ["review.submit"], []),
            ("invalidBinary", "INVALID_BINARY", ["review.submit"], []),
            ("developerRejected", "DEVELOPER_REJECTED", ["review.submit"], []),
            ("removedFromSale", "REMOVED_FROM_SALE", ["review.manage-availability"], ["review.remove-from-sale"]),
            ("developerRemovedFromSale", "DEVELOPER_REMOVED_FROM_SALE", ["review.manage-availability"], ["review.remove-from-sale"]),
            ("replacedWithNewVersion", "REPLACED_WITH_NEW_VERSION", [], ["review.submit", "review.remove-from-sale"]),
        ]

        for fixture in fixtures {
            XCTContext.runActivity(named: fixture.state) { _ in
                app?.terminate()
                launch(fixture.scenario)
                XCTAssertTrue(
                    element("review.status.\(fixture.state)").waitForExistence(timeout: interactionTimeout),
                    "Missing state fixture for \(fixture.state).")
                for identifier in fixture.actions {
                    XCTAssertTrue(
                        button(identifier).waitForExistence(timeout: interactionTimeout),
                        "Missing \(identifier) for \(fixture.state).")
                }
                for identifier in fixture.absent {
                    XCTAssertFalse(
                        button(identifier).exists,
                        "Unsafe action \(identifier) is visible for \(fixture.state).")
                }
            }
        }
    }

    func testReleaseAndPhasedChangesStayInsideFixture() {
        launch("pendingDeveloperRelease")
        button("review.release").click()
        let confirmRelease = button("review.release.confirm")
        XCTAssertTrue(confirmRelease.waitForExistence(timeout: interactionTimeout))
        confirmRelease.click()
        XCTAssertTrue(element("review.status.PROCESSING_FOR_DISTRIBUTION")
            .waitForExistence(timeout: interactionTimeout))

        app.terminate()
        launch("readyForDistribution")
        let pause = button("review.phased.pause")
        XCTAssertTrue(pause.waitForExistence(timeout: interactionTimeout))
        XCTAssertTrue(pause.isEnabled)
        pause.click()

        let resume = button("review.phased.resume")
        XCTAssertTrue(resume.waitUntilEnabled(timeout: interactionTimeout))
        resume.click()
        XCTAssertTrue(pause.waitUntilEnabled(timeout: interactionTimeout))
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

    func waitUntilEnabled(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND enabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
