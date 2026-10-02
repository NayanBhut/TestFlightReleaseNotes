//
//  LaunchTheme.swift
//  App Store
//
//  Exact Figma palette for the Shipyard Launch Assistant flow
//  (first-launch-light / first-launch-dark / add-team-credentials-light /
//  add-team-validate-light). Every color is adaptive: the light variant
//  matches the *-light frames, the dark variant matches first-launch-dark,
//  so views never need colorScheme branches.
//

import SwiftUI
import AppKit

enum LaunchTheme {
    /// Builds a Color that resolves `light` in light mode and `dark` in
    /// dark mode, mirroring the AppTheme helper.
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }))
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(red: r, green: g, blue: b, alpha: a)
    }

    // MARK: - Surfaces

    /// Window / sheet background: #F6F6F6 light, #1A1A1A dark.
    static let page = adaptive(light: rgb(0.965, 0.965, 0.965), dark: rgb(0.102, 0.102, 0.102))

    /// Card background: white light, #161616 dark.
    static let card = adaptive(light: rgb(1.0, 1.0, 1.0), dark: rgb(0.086, 0.086, 0.086))

    /// Text-field / secondary-button fill: white light, #1C1C1E dark.
    static let field = adaptive(light: rgb(1.0, 1.0, 1.0), dark: rgb(0.11, 0.11, 0.118))

    /// Footer band: #EAEAEB light, #222224 dark.
    static let footer = adaptive(light: rgb(0.918, 0.918, 0.922), dark: rgb(0.133, 0.133, 0.141))

    /// Hairlines: #D2D2D7 light, #333333 dark.
    static let border = adaptive(light: rgb(0.824, 0.824, 0.843), dark: rgb(0.2, 0.2, 0.2))

    // MARK: - Text

    /// Headings: #1E1E1E light, #F5F5F7 dark.
    static let title = adaptive(light: rgb(0.118, 0.118, 0.118), dark: rgb(0.961, 0.961, 0.969))

    /// Body copy: #6D6D72 light, #8E8E93 dark.
    static let body = adaptive(light: rgb(0.427, 0.427, 0.447), dark: rgb(0.557, 0.557, 0.576))

    // MARK: - Accent

    /// Primary blue: #007AFF light, #0A84FF dark.
    static let accent = adaptive(light: rgb(0.0, 0.478, 1.0), dark: rgb(0.039, 0.518, 1.0))

    /// Step-progress track: #E5E5EA light, #38383A dark.
    static let track = adaptive(light: rgb(0.898, 0.898, 0.918), dark: rgb(0.22, 0.22, 0.227))

    // MARK: - Validation banner

    /// Success wash: rgba(52,199,89,0.08) in both modes.
    static let successBackground = Color(red: 0.204, green: 0.78, blue: 0.349).opacity(0.08)

    /// Success hairline: rgba(52,199,89,0.2) in both modes.
    static let successBorder = Color(red: 0.204, green: 0.78, blue: 0.349).opacity(0.2)

    /// Success icon/title tick: #34C759 in both modes.
    static let success = Color(red: 0.204, green: 0.781, blue: 0.349)
}
