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
/// and their current look. Falls back to a fixed-size system font if the
/// rounded SF family isn't available.
enum AppFont {
    /// The mesh-rounded SF Pro Rounded family ships on all supported macOS.
    private static let roundedCapable = NSFont(name: "SFProRounded-Regular", size: 13) != nil

    static var appTitle: Font { dynamic(size: 28, weight: .bold, design: .rounded, relativeTo: .title) }
    static var appLargeTitle: Font { dynamic(size: 24, weight: .bold, design: .rounded, relativeTo: .title2) }
    static var sectionHeader: Font { dynamic(size: 20, weight: .semibold, design: .rounded, relativeTo: .title3) }
    static var subheader: Font { dynamic(size: 17, weight: .semibold, design: .rounded, relativeTo: .headline) }
    static var appBody: Font { dynamic(size: 16, weight: .regular, design: .rounded, relativeTo: .body) }
    static var bodyMedium: Font { dynamic(size: 16, weight: .medium, design: .rounded, relativeTo: .body) }
    static var appCaption: Font { dynamic(size: 13, weight: .regular, design: .rounded, relativeTo: .caption) }
    static var captionMedium: Font { dynamic(size: 13, weight: .medium, design: .rounded, relativeTo: .caption) }
    static var appCaption2: Font { dynamic(size: 11, weight: .regular, design: .rounded, relativeTo: .caption2) }
    static var label: Font { dynamic(size: 14, weight: .medium, design: .rounded, relativeTo: .subheadline) }
    static var button: Font { dynamic(size: 14, weight: .semibold, design: .rounded, relativeTo: .subheadline) }
    static var monospaced: Font { .system(.body, design: .monospaced) }

    /// Rounded SF font scoped to the given weight, relative to a text
    /// style so it scales with Dynamic Type. Falls back to the fixed-size
    /// system font when the family isn't present.
    private static func dynamic(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo style: Font.TextStyle) -> Font {
        guard roundedCapable, let name = postScriptName(weight: weight, design: design) else {
            return .system(size: size, weight: weight, design: design)
        }
        return .custom(name, size: size, relativeTo: style)
    }

    private static func postScriptName(weight: Font.Weight, design: Font.Design) -> String? {
        let base: String
        switch design {
        case .rounded: base = "SFProRounded"
        case .monospaced: base = "SFMono"
        default: base = "SFPro"
        }
        let suffix: String
        switch weight {
        case .regular: suffix = "Regular"
        case .medium: suffix = "Medium"
        case .semibold: suffix = "Semibold"
        case .bold: suffix = "Bold"
        default: return nil
        }
        return base + "-" + suffix
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