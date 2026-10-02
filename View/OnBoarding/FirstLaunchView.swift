//
//  FirstLaunchView.swift
//  App Store
//
//  Starting page: the "No Teams Connected" empty state from the
//  first-launch-light / first-launch-dark Figma frames. Shown in the detail
//  area when no team has been added yet. The hero tile is a Figma-exported
//  PNG (LaunchHeroTile, with a dark appearance variant) — never an SF Symbol
//  redraw.
//

import SwiftUI

/// Empty state shown before the first team is connected. The primary button
/// opens the Launch Assistant; the link opens Apple's API-key documentation.
struct FirstLaunchView: View {
    /// Opens the Add Team flow. Injected by the parent (ContentView owns the
    /// overlay); previews omit it and the button still renders.
    var onAddKey: (() -> Void)? = nil

    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack {
            Spacer(minLength: 40)
            card
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LaunchTheme.page)
    }

    private var card: some View {
        VStack(spacing: 24) {
            Image("LaunchHeroTile")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("No Teams Connected")
                    .font(.sectionHeader)
                    .foregroundColor(LaunchTheme.title)
                    .multilineTextAlignment(.center)

                Text("Add an App Store Connect API key to securely connect Shipyard to your Apple Developer account and start managing App and TestFlight lifecycles.")
                    .font(.appCaption)
                    .foregroundColor(LaunchTheme.body)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            VStack(spacing: 12) {
                Button(action: { onAddKey?() }) {
                    Text("Add App Store Connect API Key")
                        .font(.appCaption)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(LaunchTheme.accent)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add App Store Connect API Key")

                Button("Learn how API keys are stored securely on your Mac") {
                    if let url = URL(string: "https://developer.apple.com/documentation/appstoreconnectapi/creating_api_keys_for_app_store_connect_api") {
                        openURL(url)
                    }
                }
                .font(.appCaption2)
                .foregroundColor(LaunchTheme.accent)
                .underline()
                .buttonStyle(.plain)
            }
        }
        .padding(32)
        .frame(width: 480)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(LaunchTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(LaunchTheme.border, lineWidth: 1)
        )
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.25 : 0.15),
            radius: 12, x: 0, y: 12
        )
    }
}

#Preview("FirstLaunch / Light") {
    FirstLaunchView()
        .frame(width: 800, height: 600)
}

#Preview("FirstLaunch / Dark") {
    FirstLaunchView()
        .frame(width: 800, height: 600)
        .preferredColorScheme(.dark)
}
