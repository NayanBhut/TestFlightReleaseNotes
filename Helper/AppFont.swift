//
//  AppFont.swift
//  App Store
//
//  Created by Nayan Bhut on 22/09/26.
//

import SwiftUI

enum AppFont {
    static var appTitle: Font { .system(size: 28, weight: .bold, design: .rounded) }
    static var appLargeTitle: Font { .system(size: 24, weight: .bold, design: .rounded) }
    static var sectionHeader: Font { .system(size: 20, weight: .semibold, design: .rounded) }
    static var subheader: Font { .system(size: 17, weight: .semibold, design: .rounded) }
    static var body: Font { .system(size: 16, weight: .regular, design: .rounded) }
    static var bodyMedium: Font { .system(size: 16, weight: .medium, design: .rounded) }
    static var caption: Font { .system(size: 13, weight: .regular, design: .rounded) }
    static var captionMedium: Font { .system(size: 13, weight: .medium, design: .rounded) }
    static var caption2: Font { .system(size: 11, weight: .regular, design: .rounded) }
    static var label: Font { .system(size: 14, weight: .medium, design: .rounded) }
    static var button: Font { .system(size: 14, weight: .semibold, design: .rounded) }
    static var monospaced: Font { .system(.body, design: .monospaced) }
    static var monospacedMedium: Font { .system(.body, design: .monospaced).weight(.medium) }
}

extension Font {
    static var appTitle: Font { AppFont.appTitle }
    static var appLargeTitle: Font { AppFont.appLargeTitle }
    static var sectionHeader: Font { AppFont.sectionHeader }
    static var subheader: Font { AppFont.subheader }
    static var body: Font { AppFont.body }
    static var bodyMedium: Font { AppFont.bodyMedium }
    static var caption: Font { AppFont.caption }
    static var captionMedium: Font { AppFont.captionMedium }
    static var caption2: Font { AppFont.caption2 }
    static var label: Font { AppFont.label }
    static var button: Font { AppFont.button }
    static var monospaced: Font { AppFont.monospaced }
}

struct AppFontMetrics {
    @ScaledMetric var titleSize: CGFloat = 28
    @ScaledMetric var headerSize: CGFloat = 20
    @ScaledMetric var bodySize: CGFloat = 16
    @ScaledMetric var captionSize: CGFloat = 13
}

enum AppFontStyle {
    case title, largeTitle, sectionHeader, subheader, body, bodyMedium, caption, captionMedium, caption2, label, button, monospaced

    var font: Font {
        switch self {
        case .title: return .appTitle
        case .largeTitle: return .appLargeTitle
        case .sectionHeader: return .sectionHeader
        case .subheader: return .subheader
        case .body: return .body
        case .bodyMedium: return .bodyMedium
        case .caption: return .caption
        case .captionMedium: return .captionMedium
        case .caption2: return .caption2
        case .label: return .label
        case .button: return .button
        case .monospaced: return .monospaced
        }
    }
}

#Preview("AppFont") {
    VStack(spacing: 12) {
        Text("Title").font(.appTitle)
        Text("Section Header").font(.sectionHeader)
        Text("Subheader").font(.subheader)
        Text("Body").font(.body)
        Text("Caption").font(.caption)
        Text("Caption2").font(.caption2)
        Text("Monospaced").font(.monospaced)
    }
    .padding()
    .background(Color(red: 0.949, green: 0.961, blue: 0.992, opacity: 1.0))
}
