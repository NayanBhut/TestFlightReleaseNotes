//
//  AppFont.swift
//  App Store
//
//  Created by Nayan Bhut on 22/09/26.
//

import SwiftUI
import AppKit

/// App-wide type ramp. Every font is anchored to a `Font.TextStyle` via
/// `Font.custom(_:size:relativeTo:)` so it tracks the user's accessibility
/// text-size setting; at the default size the point sizes are unchanged,
/// so existing call sites keep their named fonts (:appBody, :caption, ...)
/// and their current look. The rounded face is resolved from the *system*
/// font descriptor (`.rounded` design) — never a downloadable PostScript
/// name — so it works on every stock macOS install without bundling fonts.
enum AppFont {
    static var appTitle: Font { dynamic(size: 28, weight: .bold, relativeTo: .title) }
    static var appLargeTitle: Font { dynamic(size: 24, weight: .bold, relativeTo: .title2) }
    static var sectionHeader: Font { dynamic(size: 20, weight: .semibold, relativeTo: .title3) }
    static var subheader: Font { dynamic(size: 17, weight: .semibold, relativeTo: .headline) }
    static var appBody: Font { dynamic(size: 16, weight: .regular, relativeTo: .body) }
    static var bodyMedium: Font { dynamic(size: 16, weight: .medium, relativeTo: .body) }
    static var appCaption: Font { dynamic(size: 13, weight: .regular, relativeTo: .caption) }
    static var captionMedium: Font { dynamic(size: 13, weight: .medium, relativeTo: .caption) }
    static var appCaption2: Font { dynamic(size: 11, weight: .regular, relativeTo: .caption2) }
    static var label: Font { dynamic(size: 14, weight: .medium, relativeTo: .subheadline) }
    static var button: Font { dynamic(size: 14, weight: .semibold, relativeTo: .subheadline) }
    static var monospaced: Font { .system(.body, design: .monospaced) }

    /// Resolves the system rounded face for the given weight and anchors it
    /// to a text style so it scales with Dynamic Type. The descriptor-based
    /// route uses the system's built-in rounded design (available on all
    /// supported macOS) rather than a downloadable PostScript name that may
    /// be absent on stock installs. The resolved font's PostScript name is
    /// fed to `Font.custom(_:size:relativeTo:)` so accessibility text-size
    /// scaling stays in effect.
    private static func dynamic(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) -> Font {
        let descriptor = NSFontDescriptor
            .preferredFontDescriptor(forTextStyle: nsTextStyle(style))
            .withDesign(.rounded)?
            .addingAttributes([
                .traits: [NSFontDescriptor.TraitKey.weight: nsFontWeight(weight)]
            ])
        guard let descriptor,
              let resolved = NSFont(descriptor: descriptor, size: size) else {
            return .system(size: size, weight: weight, design: .rounded)
        }
        return .custom(resolved.fontName, size: size, relativeTo: style)
    }

    private static func nsFontWeight(_ weight: Font.Weight) -> NSFont.Weight {
        switch weight {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        default: return .regular
        }
    }

    private static func nsTextStyle(_ style: Font.TextStyle) -> NSFont.TextStyle {
        switch style {
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .body: return .body
        case .subheadline: return .subheadline
        case .caption: return .caption1
        case .caption2: return .caption2
        default: return .body
        }
    }
}

extension Font {
    static var appTitle: Font { AppFont.appTitle }
    static var appLargeTitle: Font { AppFont.appLargeTitle }
    static var sectionHeader: Font { AppFont.sectionHeader }
    static var subheader: Font { AppFont.subheader }
    static var appBody: Font { AppFont.appBody }
    static var bodyMedium: Font { AppFont.bodyMedium }
    static var appCaption: Font { AppFont.appCaption }
    static var captionMedium: Font { AppFont.captionMedium }
    static var appCaption2: Font { AppFont.appCaption2 }
    static var label: Font { AppFont.label }
    static var button: Font { AppFont.button }
    static var monospaced: Font { AppFont.monospaced }
}

#Preview("AppFont") {
    VStack(spacing: 12) {
        Text("Title").font(.appTitle)
        Text("Section Header").font(.sectionHeader)
        Text("Subheader").font(.subheader)
        Text("Body").font(.appBody)
        Text("Caption").font(.appCaption)
        Text("Caption2").font(.appCaption2)
        Text("Monospaced").font(.monospaced)
    }
    .padding()
    .background(AppTheme.primaryBackground)
}