//
//  AppAppearance.swift
//  App Store
//
//  Created by Nayan Bhut on 22/09/26.
//

import SwiftUI
import AppKit

enum AppAppearance {
    static var isDarkMode: Bool {
        NSApp.effectiveAppearance.name == .darkAqua
    }

    static func toggle() {
        if isDarkMode {
            NSApp.appearance = NSAppearance(named: .aqua)
        } else {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
