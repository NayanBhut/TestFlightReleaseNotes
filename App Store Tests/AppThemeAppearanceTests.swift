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
}
