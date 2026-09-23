//
//  AppCommandStore.swift
//  App Store
//
//  Created by Nayan Bhut on 22/09/26.
//

import SwiftUI
import Combine

final class AppCommandStore: ObservableObject {
    @Published var showPalette = false

    let refreshRequested = PassthroughSubject<Void, Never>()
    let toggleDarkModeRequested = PassthroughSubject<Void, Never>()
    let clearSearchRequested = PassthroughSubject<Void, Never>()

    func requestRefresh() { refreshRequested.send() }
    func requestToggleDarkMode() { toggleDarkModeRequested.send() }
    func requestClearSearch() { clearSearchRequested.send() }
}

struct CommandPalette: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var hoveredId: String?
    @State private var selectionIndex = 0
    @FocusState private var searchFocused: Bool
    @ObservedObject var commands: AppCommandStore

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 18))
                    .symbolEffect(.pulse, isActive: query.trimmingCharacters(in: .whitespaces).isEmpty)

                TextField("Search commands...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.appBody)
                    .focused($searchFocused)
                    .onChange(of: query) { _, _ in
                        selectionIndex = 0
                    }

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
                    ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                        Button(action: {
                            command.action()
                            dismiss()
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: command.icon)
                                    .foregroundColor(.secondary)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(command.title)
                                        .font(.appBody)
                                        .foregroundColor(.primary)
                                    Text(command.subtitle)
                                        .font(.appCaption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if let shortcut = command.shortcut {
                                    Text(shortcut)
                                        .font(.appCaption)
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
                                    .fill(
                                        selectionIndex == index
                                            ? AppTheme.selectedOverlay
                                            : (hoveredId == command.id ? AppTheme.hoverOverlay : AppTheme.cardBackground)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectionIndex == index ? AppTheme.selectedBorder : Color.clear, lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(hoveredId == command.id ? 1.02 : 1.0)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                hoveredId = hovering ? command.id : nil
                            }
                        }
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: 300)

            if filteredCommands.isEmpty && !query.isEmpty {
                Text("No commands found")
                    .font(.appCaption)
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
        .onAppear {
            searchFocused = true
            selectionIndex = 0
        }
        .onKeyPress(.upArrow) {
            if !filteredCommands.isEmpty {
                selectionIndex = max(0, selectionIndex - 1)
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if !filteredCommands.isEmpty {
                selectionIndex = min(filteredCommands.count - 1, selectionIndex + 1)
            }
            return .handled
        }
        .onKeyPress(.return) {
            if filteredCommands.indices.contains(selectionIndex) {
                filteredCommands[selectionIndex].action()
                dismiss()
            }
            return .handled
        }
    }

    private var filteredCommands: [PaletteCommand] {
        allCommands.filter { Self.matches(title: $0.title, subtitle: $0.subtitle, query: query) }
    }

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