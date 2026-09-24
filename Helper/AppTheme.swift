//
//  AppTheme.swift
//  App Store
//
//  Created by Nayan Bhut on 22/09/26.
//

import SwiftUI
import AppKit

/// App-wide theme. Every background/surface/text color is *adaptive*: a
/// single dynamic `NSColor` provider resolves to the light variant under
/// `.aqua` and the dark variant under `.darkAqua`, so views never need
/// `colorScheme` branches. Fixed RGB values here previously rendered
/// light-mode backgrounds under dark-mode (white) text — unreadable.
enum AppTheme {
    /// Builds a Color that resolves `light` in light mode and `dark` in
    /// dark mode. `bestMatch` (instead of a raw name check) also covers
    /// vibrant/high-contrast appearances.
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }))
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(red: r, green: g, blue: b, alpha: a)
    }

    // MARK: - Accent
    static let accent = adaptive(light: rgb(0.392, 0.4, 0.941), dark: rgb(0.561, 0.569, 0.988))

    // MARK: - Background
    static let primaryBackground = adaptive(light: rgb(0.949, 0.961, 0.992), dark: rgb(0.13, 0.14, 0.18))
    static let secondaryBackground = adaptive(light: rgb(0.898, 0.914, 0.953), dark: rgb(0.17, 0.18, 0.23))
    static let tertiaryBackground = adaptive(light: rgb(0.847, 0.867, 0.922), dark: rgb(0.215, 0.225, 0.28))
    static let windowBackground = adaptive(light: rgb(0.925, 0.937, 0.969), dark: rgb(0.11, 0.115, 0.15))
    static let textBackgroundColor = adaptive(light: rgb(1.0, 1.0, 1.0), dark: rgb(0.22, 0.22, 0.24))

    // MARK: - Surface
    static let cardBackground = adaptive(light: rgb(1.0, 1.0, 1.0), dark: rgb(0.185, 0.19, 0.225))
    static let separator = adaptive(light: rgb(0.8, 0.816, 0.867), dark: rgb(0.32, 0.33, 0.38))
    static let border = adaptive(light: rgb(0.851, 0.867, 0.914), dark: rgb(0.30, 0.31, 0.36))

    // MARK: - Text
    static let primaryText = adaptive(light: rgb(0.176, 0.184, 0.231), dark: rgb(0.93, 0.93, 0.95))
    static let secondaryText = adaptive(light: rgb(0.447, 0.463, 0.541), dark: rgb(0.66, 0.67, 0.72))
    static let tertiaryText = adaptive(light: rgb(0.6, 0.62, 0.702), dark: rgb(0.52, 0.53, 0.58))

    // MARK: - State Colors (saturated modern palette, legible on both modes)
    static let readyForSale = adaptive(light: rgb(0, 0.420, 0.286), dark: rgb(0.353, 0.820, 0.608))
    static let inReview = adaptive(light: rgb(0.263, 0.220, 0.792), dark: rgb(0.647, 0.706, 0.988))
    static let processing = adaptive(light: rgb(0.427, 0.157, 0.851), dark: rgb(0.769, 0.655, 1.0))
    static let rejected = adaptive(light: rgb(0.706, 0.137, 0.184), dark: rgb(1.0, 0.541, 0.580))
    static let pending = adaptive(light: rgb(0.549, 0.294, 0), dark: rgb(0.984, 0.749, 0.141))
    static let waiting = adaptive(light: rgb(0.463, 0.337, 0), dark: rgb(0.957, 0.827, 0.369))
    static let accepted = readyForSale
    static let metadataRejected = rejected
    static let developerRejected = adaptive(light: rgb(0.294, 0.333, 0.388), dark: rgb(0.706, 0.729, 0.784))
    static let removed = developerRejected
    static let compliance = adaptive(light: rgb(0.012, 0.388, 0.490), dark: rgb(0.404, 0.835, 0.949))

    // MARK: - Interactive
    static let hoverOverlay = adaptive(light: rgb(0, 0, 0, 0.04), dark: rgb(1, 1, 1, 0.07))
    static let selectedOverlay = Color(red: 0.392, green: 0.4, blue: 0.941).opacity(0.08)
    static let selectedBorder = Color(red: 0.392, green: 0.4, blue: 0.941).opacity(0.25)
    static let shadow = adaptive(light: rgb(0, 0, 0, 0.06), dark: rgb(0, 0, 0, 0.45))
    static let overlay = Color.black.opacity(0.5)

    // MARK: - Chart / Data
    static let positive = readyForSale
    static let negative = rejected
    static let neutral = tertiaryText
}

// MARK: - Color Extension
extension Color {
    static var appPrimary: Color { AppTheme.accent }
    static var appBackground: Color { AppTheme.primaryBackground }
    static var appSecondaryBackground: Color { AppTheme.secondaryBackground }
    static var appCardBackground: Color { AppTheme.cardBackground }
    static var appText: Color { AppTheme.primaryText }
    static var appSecondaryText: Color { AppTheme.secondaryText }
}

// MARK: - System Color Overrides
extension NSColor {
    private static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil, dynamicProvider: { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light })
    }

    static var appPrimaryBackground: NSColor {
        adaptive(light: NSColor(red: 0.949, green: 0.961, blue: 0.992, alpha: 1.0),
                 dark: NSColor(red: 0.13, green: 0.14, blue: 0.18, alpha: 1.0))
    }
    static var appSecondaryBackground: NSColor {
        adaptive(light: NSColor(red: 0.898, green: 0.914, blue: 0.953, alpha: 1.0),
                 dark: NSColor(red: 0.17, green: 0.18, blue: 0.23, alpha: 1.0))
    }
    static var appCardBackground: NSColor {
        adaptive(light: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
                 dark: NSColor(red: 0.185, green: 0.19, blue: 0.225, alpha: 1.0))
    }
    static var appWindowBackground: NSColor {
        adaptive(light: NSColor(red: 0.925, green: 0.937, blue: 0.969, alpha: 1.0),
                 dark: NSColor(red: 0.11, green: 0.115, blue: 0.15, alpha: 1.0))
    }
}

// MARK: - State Color Mapping
extension String {
    var stateColor: Color {
        let upper = uppercased()
        switch upper {
        case "READY_FOR_SALE", "ACCEPTED", "READY_FOR_REVIEW", "COMPLETE", "APPROVED", "ENABLED", "ACTIVE", "VALID":
            return AppTheme.readyForSale
        case "PENDING_DEVELOPER_RELEASE", "PENDING_CONTRACT", "PENDING_APPLE_RELEASE", "CANCELING", "COMPLETING", "WAITING_FOR_REVIEW":
            return AppTheme.pending
        case "IN_REVIEW":
            return AppTheme.inReview
        case "PROCESSING_FOR_APP_STORE":
            return AppTheme.processing
        case "REJECTED", "INVALID_BINARY", "UNRESOLVED_ISSUES", "INVALID":
            return AppTheme.rejected
        case "METADATA_REJECTED", "DEVELOPER_REJECTED", "DEVELOPER_REMOVED_FROM_SALE", "REMOVED_FROM_SALE":
            return AppTheme.developerRejected
        case "WAITING_FOR_EXPORT_COMPLIANCE":
            return AppTheme.compliance
        default:
            return AppTheme.secondaryText
        }
    }
}

// MARK: - View Extensions
extension View {
    func appShadow(radius: CGFloat = 8, x: CGFloat = 0, y: CGFloat = 4) -> some View {
        shadow(color: AppTheme.shadow, radius: radius, x: x, y: y)
    }
}

// MARK: - State Color Mapping
#Preview("AppTheme / Light") {
    VStack(spacing: 16) {
        Text("Accent").foregroundColor(AppTheme.accent)
        Text("Primary BG").background(AppTheme.primaryBackground)
        Text("Card").background(AppTheme.cardBackground)
        HStack {
            StateChip(text: "READY_FOR_SALE")
            StateChip(text: "IN_REVIEW")
            StateChip(text: "CANCELING")
            StateChip(text: "REJECTED")
            StateChip(text: "UNKNOWN")
        }
    }
    .padding()
    .background(AppTheme.primaryBackground)
}

#Preview("AppTheme / Dark") {
    VStack(spacing: 16) {
        Text("Accent").foregroundColor(AppTheme.accent)
        Text("Primary BG").background(AppTheme.primaryBackground)
        Text("Card").background(AppTheme.cardBackground)
        HStack {
            StateChip(text: "READY_FOR_SALE")
            StateChip(text: "IN_REVIEW")
            StateChip(text: "CANCELING")
            StateChip(text: "REJECTED")
            StateChip(text: "UNKNOWN")
        }
    }
    .padding()
    .background(AppTheme.primaryBackground)
    .preferredColorScheme(.dark)
}
