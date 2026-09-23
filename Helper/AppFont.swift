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
    static var appBody: Font { .system(size: 16, weight: .regular, design: .rounded) }
    static var bodyMedium: Font { .system(size: 16, weight: .medium, design: .rounded) }
    static var appCaption: Font { .system(size: 13, weight: .regular, design: .rounded) }
    static var captionMedium: Font { .system(size: 13, weight: .medium, design: .rounded) }
    static var appCaption2: Font { .system(size: 11, weight: .regular, design: .rounded) }
    static var label: Font { .system(size: 14, weight: .medium, design: .rounded) }
    static var button: Font { .system(size: 14, weight: .semibold, design: .rounded) }
    static var monospaced: Font { .system(.body, design: .monospaced) }
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