//
//  NavigationManager.swift
//  App Store
//
//  Created by Nayan Bhut on 16/05/25.
//

import SwiftUI
import Combine

/// Login state is DERIVED from the keychain: CredentialStorage's published
/// team list is the single source of truth. There is no persisted
/// "isLoggedIn" flag anymore — a wiped keychain can never leave a stale
/// logged-in state behind, and adding/removing the last team flips this
/// automatically.
class NavigationManager: ObservableObject {
    @Published private(set) var isLoggedIn: Bool = !CredentialStorage.shared.teams.isEmpty

    private var teamsCancellable: AnyCancellable?

    init() {
        // Re-derive whenever the team list changes. Delivered on main so
        // the @Published mutation stays co-ordinated with view updates.
        teamsCancellable = CredentialStorage.shared.$teams
            .receive(on: DispatchQueue.main)
            .map { !$0.isEmpty }
            .sink { [weak self] loggedIn in
                guard let self, self.isLoggedIn != loggedIn else { return }
                self.isLoggedIn = loggedIn
            }
        // One-time cleanup: earlier versions persisted this flag; the
        // keychain is now the only source of truth.
        UserDefaults.standard.removeObject(forKey: "isLoggedIn")
    }
}

// MARK: - Unified view state
//
// A single generic state machine per list.

enum ViewState<T> {
    case idle
    case loading
    case loaded(T)
    case empty
    case error(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var loadedValue: T? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var errorMessage: String? {
        if case .error(let message) = self { return message }
        return nil
    }
}

extension ViewState: Equatable where T: Equatable {
    static func == (lhs: ViewState<T>, rhs: ViewState<T>) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.empty, .empty):
            return true
        case (.loaded(let a), .loaded(let b)):
            return a == b
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

struct UserDefaultsKeys {
    /// Batch C flag: one switch that shows/hides the App Info tab, the
    /// Reviews tab and the Resources sidebar section. Read via @AppStorage
    /// so every view observes UserDefaults and stays in sync.
    static let showExtendedInfo = "showExtendedInfo"
}

// MARK: - Shared error + Retry view
//
// Used by sidebar (apps), versions, and builds states so airplane-mode
// failures always surface with a Retry action.

struct ErrorRetryView: View {
    let title: String
    let message: String
    let retryTitle: String
    let onRetry: () -> Void
    /// An optional secondary action shown between the retry button and
    /// the bottom spacer (e.g. "Add Team") so it sits next to Retry
    /// instead of being orphaned at the bottom. One optional value so
    /// the button is either fully configured or absent.
    var extraButton: (title: String, action: () -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(title)
                .font(.subheader)
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(retryTitle, action: onRetry)
                .buttonStyle(.borderedProminent)
            if let extraButton {
                Button(extraButton.title, action: extraButton.action)
                    .buttonStyle(.bordered)
                    .padding(.vertical, 2)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}
