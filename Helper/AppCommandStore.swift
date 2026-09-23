//
//  AppCommandStore.swift
//  App Store
//
//  Created by Nayan Bhut on 22/09/26.
//

import SwiftUI

class AppCommandStore: ObservableObject {
     @Published var showPalette = false
     @Published var refreshRequested = false
     @Published var toggleDarkModeRequested = false
     @Published var clearSearchRequested = false

     func requestRefresh() { refreshRequested = true }
     func requestToggleDarkMode() { toggleDarkModeRequested = true }
     func requestClearSearch() { clearSearchRequested = true }
}

struct CommandPalette: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @ObservedObject var commands: AppCommandStore
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 18))
                    .symbolEffect(.pulse, isActive: true)

                TextField("Search commands...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.body)

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppTheme.textBackgroundColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppTheme.border, lineWidth: 1)
            )

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredCommands, id: \.id) { command in
                        Button(action: {
                            command.action()
                            dismiss()
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: command.icon)
                                    .foregroundColor(.secondary)
                                    .frame(width: 24)
                                    .animation(.easeInOut(duration: 0.2), value: command.id)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(command.title)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Text(command.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if let shortcut = command.shortcut {
                                    Text(shortcut)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AppTheme.secondaryBackground)
                                        .cornerRadius(4)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(AppTheme.cardBackground)
                            )
                            .contentShape(Rectangle())
                        }
                         .buttonStyle(.plain)
                         .scaleEffect(isHovered ? 1.02 : 1.0)
                         .animation(.easeInOut(duration: 0.15), value: isHovered)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isHovered = hovering
                            }
                        }
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: 300)

            if filteredCommands.isEmpty && !query.isEmpty {
                Text("No commands found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .frame(width: 440)
        .padding()
        .background(AppTheme.windowBackground)
        .cornerRadius(16)
        .shadow(radius: 20)
        .transition(.asymmetric(insertion: .scale.combined(with: .opacity).animation(.spring(duration: 0.3, bounce: 0.3)), removal: .opacity.animation(.easeIn(duration: 0.15))))
        .onAppear {
            appeared = true
            withAnimation(.spring(duration: 0.3, bounce: 0.3)) {
            }
        }
        .onDisappear {
            appeared = false
        }
        .scaleEffect(appeared ? 1.0 : 0.95)
        .opacity(appeared ? 1.0 : 0.0)
    }

    @State private var isHovered = false

    private var filteredCommands: [PaletteCommand] {
        allCommands.filter { Self.matches(title: $0.title, subtitle: $0.subtitle, query: query) }
    }

    /// Pure command matcher, extracted for tests. Empty/blank queries
    /// match everything; matching is case-insensitive over title+subtitle.
    static func matches(title: String, subtitle: String, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty
            || title.localizedCaseInsensitiveContains(trimmed)
            || subtitle.localizedCaseInsensitiveContains(trimmed)
    }

     private var allCommands: [PaletteCommand] {
         [
             PaletteCommand(id: "refresh", title: "Refresh Apps", subtitle: "Reload the app list", icon: "arrow.clockwise", shortcut: "⌘R", action: { commands.requestRefresh() }),
             PaletteCommand(id: "dark-mode", title: "Toggle Dark Mode", subtitle: "Switch between light and dark appearance", icon: "moon.fill", shortcut: "⌘D", action: { commands.requestToggleDarkMode() }),
             PaletteCommand(id: "clear-search", title: "Clear Search", subtitle: "Clear the sidebar search", icon: "xmark.circle", shortcut: nil, action: { commands.requestClearSearch() }),
         ]
     }
 }

struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let shortcut: String?
    let action: () -> Void
}
