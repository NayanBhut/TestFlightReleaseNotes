//
//  ShipyardTheme.swift
//  App Store
//
//  Shared palette and chrome for the Shipyard shell (sidebar + tables),
//  taken from the *-light Figma frames with dark variants. Table type uses
//  the system face at Figma's exact sizes — the rounded AppFont ramp has no
//  10/11/12 steps, and the tables need Figma's metrics.
//

import SwiftUI
import AppKit

enum ShipyardTheme {
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }))
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(red: r, green: g, blue: b, alpha: a)
    }

    // MARK: - Surfaces

    /// Sidebar + inspector background: #EAEAEB light, #1C1C1E dark.
    static let sidebarBackground = adaptive(light: rgb(0.918, 0.918, 0.922), dark: rgb(0.11, 0.11, 0.118))

    /// Table header band: #EDEDED light, #2C2C2E dark.
    static let tableHeader = adaptive(light: rgb(0.929, 0.929, 0.929), dark: rgb(0.173, 0.173, 0.18))

    /// Selected nav row / table row: #D3D3D5 light, #3A3A3C dark.
    static let selectedRow = adaptive(light: rgb(0.827, 0.827, 0.835), dark: rgb(0.227, 0.227, 0.235))

    /// Table content background: white light, #1E1E20 dark.
    static let tableBackground = adaptive(light: rgb(1.0, 1.0, 1.0), dark: rgb(0.118, 0.118, 0.125))

    /// Hairlines under table rows: #E5E5EA light, #38383A dark.
    static let rowDivider = adaptive(light: rgb(0.898, 0.898, 0.918), dark: rgb(0.22, 0.22, 0.227))

    // MARK: - Text

    /// Table headings / strong labels: #1E1E1E light, #F5F5F7 dark.
    static let title = adaptive(light: rgb(0.118, 0.118, 0.118), dark: rgb(0.961, 0.961, 0.969))

    /// Secondary copy: #6D6D72 light, #8E8E93 dark.
    static let body = adaptive(light: rgb(0.427, 0.427, 0.447), dark: rgb(0.557, 0.557, 0.576))

    /// Tertiary copy (Apple-ID column): #8E8E93 in both modes.
    static let tertiary = Color(red: 0.557, green: 0.557, blue: 0.576)

    // MARK: - Accent + status

    /// Primary actions + links: #007AFF light, #0A84FF dark.
    static let accent = adaptive(light: rgb(0.0, 0.478, 1.0), dark: rgb(0.039, 0.518, 1.0))

    /// Destructive text: #FF3B30 light, #FF453A dark.
    static let danger = adaptive(light: rgb(1.0, 0.231, 0.188), dark: rgb(1.0, 0.271, 0.227))

    /// Success dots / ticks: #34C759 in both modes.
    static let success = Color(red: 0.204, green: 0.781, blue: 0.349)

    /// Warning dots: amber in both modes.
    static let warning = Color(red: 1.0, green: 0.624, blue: 0.043)

    // MARK: - Status-message surfaces (Figma detail/sheet banners)

    /// Backing fill for the info banner (Figma #E5F1FF) and its border
    /// (#007AFF). Dark values are hand-picked equivalents — the Figma file
    /// only specifies the light ramp.
    static let infoSurface = adaptive(light: rgb(0.898, 0.945, 1.0), dark: rgb(0.09, 0.145, 0.239))
    static let infoBorder = accent

    /// Warning banner fill (#FFF8E1) / border (#A66A00).
    static let warningSurface = adaptive(light: rgb(1.0, 0.973, 0.882), dark: rgb(0.243, 0.192, 0.055))
    static let warningBorder = Color(red: 0.651, green: 0.416, blue: 0.0)

    /// Destructive banner fill (#FFECEB) / border (#D92D24).
    static let dangerSurface = adaptive(light: rgb(1.0, 0.925, 0.922), dark: rgb(0.271, 0.114, 0.106))
    static let dangerBorder = Color(red: 0.851, green: 0.176, blue: 0.141)

    /// Success banner fill (#EAF7EE) / border (#248A3D).
    static let successSurface = adaptive(light: rgb(0.918, 0.969, 0.933), dark: rgb(0.086, 0.204, 0.129))
    static let successBorder = Color(red: 0.141, green: 0.541, blue: 0.239)

    /// Read-only field fill (#F0F0F2) — Identifier / Platform inputs on
    /// the Bundle ID detail are disabled, not editable.
    static let readOnlyField = adaptive(light: rgb(0.941, 0.941, 0.949), dark: rgb(0.165, 0.165, 0.173))
}

// MARK: - Shared chrome

/// Gray count pill ("8 Total", "2") used in toolbars and the sidebar.
struct ShipyardCountPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(ShipyardTheme.body)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.gray.opacity(0.15))
            .cornerRadius(10)
    }
}

/// 24pt bordered search field from the section toolbars.
struct ShipyardSearchField: View {
    let prompt: String
    @Binding var text: String
    var width: CGFloat = 160

    var body: some View {
        HStack(spacing: 6) {
            Image("ShipyardSearch")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 11, height: 11)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
        }
        .padding(.horizontal, 8)
        .frame(width: width, height: 24)
        .background(LaunchTheme.field)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(LaunchTheme.border, lineWidth: 1)
        )
    }
}

/// 24pt bordered toolbar menu button ("Status: All", "Platform: All").
struct ShipyardMenuLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(LaunchTheme.field)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(LaunchTheme.border, lineWidth: 1)
        )
    }
}

/// Figma-exported PNG glyph at its design size. PNGs (not SF Symbols) per
/// the project's icon rule — these are the Lucide glyphs from Figma.
struct ShipyardIcon: View {
    let name: String
    var size: CGFloat = 14
    var tint: Color? = nil

    var body: some View {
        Group {
            if let tint {
                Image(name)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(tint)
            } else {
                Image(name)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Resolves an App Store Connect icon template URL (e.g.
/// `{w}x{h}bb.{f}`) to a concrete size and format. Mirrors the proven
/// AppRowView helper so tables share the same URLs.
func shipyardAppIconURL(template: String?, size: Int) -> URL? {
    guard var template, !template.isEmpty else { return nil }
    template = template.replacingOccurrences(of: "{w}x{h}bb", with: "\(size)x\(size)bb")
    template = template.replacingOccurrences(of: "{w}x{h}", with: "\(size)x\(size)")
    template = template.replacingOccurrences(of: "{w}", with: "\(size)")
    template = template.replacingOccurrences(of: "{h}", with: "\(size)")
    template = template.replacingOccurrences(of: "{f}", with: "png")
    return URL(string: template)
}

/// Deterministic letter-tile color per app id (Figma tiles vary per app).
func shipyardTileColor(for id: String) -> Color {
    let palette: [Color] = [
        Color(red: 0.0, green: 0.478, blue: 1.0),
        Color(red: 0.2, green: 0.47, blue: 0.96),
        Color(red: 0.6, green: 0.36, blue: 0.87),
        Color(red: 0.96, green: 0.4, blue: 0.27),
        Color(red: 0.2, green: 0.78, blue: 0.45),
        Color(red: 0.96, green: 0.65, blue: 0.14),
        Color(red: 0.35, green: 0.56, blue: 0.94),
        Color(red: 0.87, green: 0.28, blue: 0.45),
    ]
    return palette[abs(id.hashValue) % palette.count]
}

/// API platform codes to Figma labels; unknown codes pass through.
func shipyardPlatformDisplay(_ raw: String) -> String {
    switch raw.uppercased() {
    case "IOS": return "iOS"
    case "MAC_OS": return "macOS"
    case "UNIVERSAL": return "Universal"
    default: return raw
    }
}
