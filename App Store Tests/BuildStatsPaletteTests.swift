//
//  BuildStatsPaletteTests.swift
//  App Store Tests
//
//  World-class pass: status-strip counting, command-palette matching, and
//  staggered entrance timing. Pure logic, no API key or keychain needed.
//

import XCTest
@testable import App_Store

final class BuildStatsPaletteTests: XCTestCase {
    // MARK: - BuildStats

    func testEmptyBuildsProduceZeroStats() {
        XCTAssertEqual(BuildStats.compute([]), BuildStats())
    }

    func testStatusBuckets() {
        let stats = BuildStats.compute([
            BuildStatusInput(processingState: "VALID", expired: false),
            BuildStatusInput(processingState: "VALID", expired: false),
            BuildStatusInput(processingState: "PROCESSING", expired: false),
            BuildStatusInput(processingState: "FAILED", expired: false),
            BuildStatusInput(processingState: "INVALID", expired: false),
        ])
        XCTAssertEqual(stats.valid, 2)
        XCTAssertEqual(stats.processing, 1)
        XCTAssertEqual(stats.failed, 2)
        XCTAssertEqual(stats.expired, 0)
        XCTAssertEqual(stats.total, 5)
    }

    func testExpiredWinsOverProcessingState() {
        // Mirrors BuildDisplayHelper.buildStatus: EXPIRED overrides everything.
        let stats = BuildStats.compute([
            BuildStatusInput(processingState: "PROCESSING", expired: true),
            BuildStatusInput(processingState: "FAILED", expired: true),
            BuildStatusInput(processingState: "VALID", expired: true),
        ])
        XCTAssertEqual(stats.expired, 3)
        XCTAssertEqual(stats.processing, 0)
        XCTAssertEqual(stats.failed, 0)
        XCTAssertEqual(stats.valid, 0)
    }

    func testUnknownOrMissingStateCountsAsValid() {
        let stats = BuildStats.compute([
            BuildStatusInput(processingState: "SOMETHING_NEW", expired: false),
            BuildStatusInput(processingState: nil, expired: false),
        ])
        XCTAssertEqual(stats.valid, 2)
        XCTAssertEqual(stats.total, 2)
    }

    // MARK: - Command palette matching

    func testBlankQueryMatchesEverything() {
        XCTAssertTrue(CommandPalette.matches(title: "Refresh Apps", subtitle: "Reload", query: ""))
        XCTAssertTrue(CommandPalette.matches(title: "Refresh Apps", subtitle: "Reload", query: "   "))
    }

    func testTitleMatchIsCaseInsensitive() {
        XCTAssertTrue(CommandPalette.matches(title: "Toggle Dark Mode", subtitle: "Switch", query: "dark"))
        XCTAssertTrue(CommandPalette.matches(title: "Toggle Dark Mode", subtitle: "Switch", query: "DARK"))
        XCTAssertTrue(CommandPalette.matches(title: "Toggle Dark Mode", subtitle: "Switch", query: "  Toggle  "))
    }

    func testSubtitleMatch() {
        XCTAssertTrue(CommandPalette.matches(title: "Refresh Apps", subtitle: "Reload the app list", query: "reload"))
    }

    func testNoMatch() {
        XCTAssertFalse(CommandPalette.matches(title: "Refresh Apps", subtitle: "Reload the app list", query: "export"))
    }

    // MARK: - Stagger timing

    func testStaggerDelayStepsAndCaps() {
        XCTAssertEqual(BuildListAnimation.staggerDelay(forRow: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(BuildListAnimation.staggerDelay(forRow: 1), 0.05, accuracy: 1e-9)
        XCTAssertEqual(BuildListAnimation.staggerDelay(forRow: 4), 0.2, accuracy: 1e-9)
        // Capped so long lists don't cascade.
        XCTAssertEqual(BuildListAnimation.staggerDelay(forRow: 10), 0.5, accuracy: 1e-9)
        XCTAssertEqual(BuildListAnimation.staggerDelay(forRow: 100), 0.5, accuracy: 1e-9)
    }

    func testStaggerDelayNeverNegative() {
        XCTAssertGreaterThanOrEqual(BuildListAnimation.staggerDelay(forRow: -3), 0)
    }
}
