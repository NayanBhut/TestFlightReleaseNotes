//
//  BuildDisplayHelperTests.swift
//  App Store Tests
//
//  Batch I (I8): build status mapping + upload-date formatting. Pure logic,
//  no API key or keychain needed.
//

import XCTest
@testable import App_Store

final class BuildDisplayHelperTests: XCTestCase {
    func testExpiredOverridesProcessingState() {
        let (text, _) = BuildDisplayHelper.buildStatus(processingState: "VALID", isExpired: true)
        XCTAssertEqual(text, "EXPIRED")
    }

    func testProcessingStates() {
        XCTAssertEqual(BuildDisplayHelper.buildStatus(processingState: "PROCESSING", isExpired: false).0, "PROCESSING")
        XCTAssertEqual(BuildDisplayHelper.buildStatus(processingState: "FAILED", isExpired: false).0, "FAILED")
        XCTAssertEqual(BuildDisplayHelper.buildStatus(processingState: "INVALID", isExpired: false).0, "INVALID")
        XCTAssertEqual(BuildDisplayHelper.buildStatus(processingState: "VALID", isExpired: false).0, "VALID")
    }

    func testUnknownProcessingStateIsEmpty() {
        let (text, _) = BuildDisplayHelper.buildStatus(processingState: "SOMETHING_NEW", isExpired: false)
        XCTAssertEqual(text, "")
    }

    func testUploadedDateNilAndEmpty() {
        XCTAssertNil(BuildDisplayHelper.uploadedDate(from: nil))
        XCTAssertNil(BuildDisplayHelper.uploadedDate(from: ""))
        XCTAssertNil(BuildDisplayHelper.uploadedDate(from: "not-a-date"))
        XCTAssertEqual(BuildDisplayHelper.formattedUploadedDate(nil), "")
        XCTAssertEqual(BuildDisplayHelper.formattedUploadedDate("not-a-date"), "")
        XCTAssertNil(BuildDisplayHelper.relativeUploadedTime(nil))
        XCTAssertNil(BuildDisplayHelper.relativeUploadedTime("not-a-date"))
    }

    func testValidUploadedDateFormats() {
        // ISO-8601 as returned by App Store Connect.
        let input = "2025-09-18T10:30:00Z"
        XCTAssertNotNil(BuildDisplayHelper.uploadedDate(from: input))
        XCTAssertFalse(BuildDisplayHelper.formattedUploadedDate(input).isEmpty)
        XCTAssertNotNil(BuildDisplayHelper.relativeUploadedTime(input))
    }
}
