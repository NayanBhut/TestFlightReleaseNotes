//
//  OnBoardingView.swift
//  App Store
//
//  Created by Nayan Bhut on 16/05/25.
//

import SwiftUI

struct OnBoardingView: View {
    // @StateObject (not @ObservedObject): the view owns this object, so a
    // parent re-creating the view struct must not wipe the partially
    // entered form (team name, issuer ID, private key).
    @StateObject var viewModel = OnBoardingViewModel()
    @EnvironmentObject var navigationManager: NavigationManager
    @Binding var isLoggedIn: Bool
    @Binding var isShowing: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with close button
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add Team Details")
                        .font(.sectionHeader)
                        .fontWeight(.semibold)

                    Text("Enter your App Store Connect API credentials")
                        .font(.appBody)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    isShowing = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        // Semantic sizing so the symbol follows Dynamic
                        // Type / accessibility settings, not a fixed size.
                        .imageScale(.large)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
                .accessibilityLabel("Close")
            }

            // Form fields
            OnBoardingField(title: "Team Name", text: $viewModel.teamName, isRequired: true)
            OnBoardingField(title: "Issuer ID", text: $viewModel.issuerID, isRequired: true)
            OnBoardingField(title: "Private Key ID", text: $viewModel.keyId, isRequired: true)

            // Private key section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Private Key (.p8) (Add key without space and remove top private key when copy paste)")
                        .font(.appBody)
                        .fontWeight(.medium)

                    Text("*")
                        .foregroundColor(AppTheme.negative)

                    Spacer()

                    Button(action: {
                        viewModel.getPrivateKey(filePath: viewModel.showOpenPanel())
                    }) {
                        Label("Select File", systemImage: "doc.badge.plus")
                            .font(.appCaption)
                    }
                    .buttonStyle(.bordered)
                }

                Text("Remove header/footer when pasting")
                    .font(.appCaption)
                    .foregroundColor(.secondary)

                TextEditor(text: $viewModel.privateKey)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 100)
                    .padding(8)
                    .background(AppTheme.textBackgroundColor)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
                    .scrollContentBackground(.hidden)
            }

            // Duplicate team name warning — a duplicate would silently
            // overwrite the existing Keychain entry.
            if viewModel.isFormValid && viewModel.isDuplicateTeam {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AppTheme.pending)
                    Text("A team with this name already exists")
                        .font(.appCaption)
                        .foregroundColor(AppTheme.pending)
                }
                .padding(.vertical, 2)
            }

            // Error message
            if let errorMessage = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AppTheme.pending)
                    Text(errorMessage)
                        .font(.appCaption)
                        .foregroundColor(AppTheme.pending)
                }
                .padding(.vertical, 4)
            }

            // Action buttons
            HStack {
                Spacer()

                if viewModel.isShowSpinner {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing, 8)
                }

                Button("Continue") {
                    viewModel.getAllApps(completion: { isSuccess in
                        if isSuccess, viewModel.saveLoginState() {
                            isLoggedIn = true
                        }
                    })
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isContinueEnabled || viewModel.isShowSpinner)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(width: 450)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.windowBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.accent.opacity(0.22), lineWidth: 1)
                )
        )
        .appShadow(radius: 30, y: 15)
        .padding(20)
//        .interactiveDismissDisabled(true)
    }
}

#Preview {
    OnBoardingView(isLoggedIn: .constant(false), isShowing: .constant(true))
        .environmentObject(NavigationManager())
}

struct OnBoardingField: View {
    let title: String
    @Binding var text: String
    let isRequired: Bool

    init(title: String, text: Binding<String>, isRequired: Bool = false) {
        self.title = title
        self._text = text
        self.isRequired = isRequired
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.appBody)
                    .fontWeight(.medium)

                if isRequired {
                    Text("*")
                        .foregroundColor(AppTheme.negative)
                }
            }

            TextField(title, text: $text)
                .textFieldStyle(.plain)
                .padding(8)
                .background(AppTheme.textBackgroundColor)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        }
    }
}
