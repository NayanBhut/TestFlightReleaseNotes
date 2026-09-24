//
//  AppThemeAppearanceTests.swift
//  App Store Tests
//
//  Locks the light-mode fix: every theme background/surface/text color must
//  resolve differently (and in the right direction) under light vs dark
//  appearances. Pure color math, no windows needed.
//

import XCTest
import AppKit
import SwiftUI
@testable import App_Store

final class AppThemeAppearanceTests: XCTestCase {
    /// Resolves a theme Color to sRGB components under the given appearance.
    /// AppKit has no `resolvedColor(with:)` (that's iOS) — resolution happens
    /// by making the appearance current and reading back the CGColor.
    private func resolvedComponents(of color: Color, dark: Bool) -> [CGFloat] {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        // Converting color spaces forces the dynamic provider to resolve
        // against the current appearance.
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(color).usingColorSpace(.sRGB)
        }
        guard let rgb = resolved else { return [] }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a]
    }

    private func brightness(_ components: [CGFloat]) -> CGFloat {
        (components[0] + components[1] + components[2]) / 3
    }

    private func assertColor(
        _ actual: Color,
        equals expected: Color,
        dark: Bool,
        state: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            resolvedComponents(of: actual, dark: dark),
            resolvedComponents(of: expected, dark: dark),
            state,
            file: file,
            line: line
        )
    }

    func testBackgroundsAreDarkerInDarkMode() {
        for color in [
            AppTheme.primaryBackground,
            AppTheme.secondaryBackground,
            AppTheme.tertiaryBackground,
            AppTheme.windowBackground,
            AppTheme.cardBackground,
            AppTheme.textBackgroundColor,
        ] as [Color] {
            let light = resolvedComponents(of: color, dark: false)
            let dark = resolvedComponents(of: color, dark: true)
            XCTAssertEqual(light.count, 4)
            XCTAssertEqual(dark.count, 4)
            XCTAssertLessThan(brightness(dark), brightness(light), "background must darken in dark mode")
        }
    }

    func testTextIsLighterInDarkMode() {
        for color in [AppTheme.primaryText, AppTheme.secondaryText] as [Color] {
            let light = resolvedComponents(of: color, dark: false)
            let dark = resolvedComponents(of: color, dark: true)
            XCTAssertEqual(light.count, 4)
            XCTAssertEqual(dark.count, 4)
            XCTAssertGreaterThan(brightness(dark), brightness(light), "text must lighten in dark mode")
        }
        // Tertiary text is de-emphasized (dimmer) in both modes by design —
        // it only needs to adapt, not lighten.
        XCTAssertNotEqual(
            resolvedComponents(of: AppTheme.tertiaryText, dark: false),
            resolvedComponents(of: AppTheme.tertiaryText, dark: true)
        )
    }

    func testChromeAdapts() {
        // Separators, borders, accent, and shadows must not resolve
        // identically across modes (identical values = the old fixed-RGB bug).
        for color in [AppTheme.separator, AppTheme.border, AppTheme.accent, AppTheme.shadow] as [Color] {
            XCTAssertNotEqual(
                resolvedComponents(of: color, dark: false),
                resolvedComponents(of: color, dark: true)
            )
        }
    }

    func testStateColorsAdapt() {
        let colors = [
            AppTheme.readyForSale,
            AppTheme.inReview,
            AppTheme.processing,
            AppTheme.rejected,
            AppTheme.pending,
            AppTheme.waiting,
            AppTheme.developerRejected,
            AppTheme.compliance,
        ] as [Color]
        for color in colors {
            XCTAssertNotEqual(
                resolvedComponents(of: color, dark: false),
                resolvedComponents(of: color, dark: true)
            )
        }
    }

    func testStateColorMapping() {
        let mappings: [([String], Color)] = [
            (["READY_FOR_SALE", "ACCEPTED", "READY_FOR_REVIEW", "COMPLETE", "APPROVED", "ENABLED", "ACTIVE", "VALID"], AppTheme.readyForSale),
            (["PENDING_DEVELOPER_RELEASE", "PENDING_CONTRACT", "PENDING_APPLE_RELEASE", "CANCELING", "COMPLETING", "WAITING_FOR_REVIEW"], AppTheme.pending),
            (["IN_REVIEW"], AppTheme.inReview),
            (["REJECTED", "INVALID_BINARY", "UNRESOLVED_ISSUES", "INVALID"], AppTheme.rejected),
            (["UNKNOWN"], AppTheme.secondaryText),
        ]

        for dark in [false, true] {
            for (states, expected) in mappings {
                for state in states {
                    assertColor(state.stateColor, equals: expected, dark: dark, state: state)
                }
            }
        }
    }
}
