//
//  AppAppearance.swift
//  App Store
//
//  Created by Nayan Bhut on 22/09/26.
//

import SwiftUI
import AppKit

enum AppAppearance {
    private static let key = "appAppearanceOverride"

    static var isDarkMode: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// Toggles between light and dark, persisting the choice so it
    /// survives relaunch. Uses `bestMatch` (not raw name comparison)
    /// so high-contrast dark variants resolve correctly.
    static func toggle() {
        if isDarkMode {
            NSApp.appearance = NSAppearance(named: .aqua)
            UserDefaults.standard.set("light", forKey: key)
        } else {
            NSApp.appearance = NSAppearance(named: .darkAqua)
            UserDefaults.standard.set("dark", forKey: key)
        }
    }

    /// Restores the persisted appearance override at launch. Call
    /// from `.task` on the root view. No-op if no override is stored
    /// (follows system appearance).
    static func applyStored() {
        guard let stored = UserDefaults.standard.string(forKey: key) else { return }
        switch stored {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }
}