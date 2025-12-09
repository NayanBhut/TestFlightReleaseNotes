//
//  OnBoardingView.swift
//  App Store
//
//  Created by Nayan Bhut on 16/05/25.
//

import SwiftUI

struct OnBoardingView: View {
    @ObservedObject var viewModel = OnBoardingViewModel()
    @EnvironmentObject var navigationManager: NavigationManager
    @Binding var isLoggedIn: Bool
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Add Team Details")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Enter your App Store Connect API credentials")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 8)
            
            // Form fields
            OnBoardingField(title: "Team Name", text: $viewModel.teamName, isRequired: true)
            OnBoardingField(title: "Issuer ID", text: $viewModel.issuerID, isRequired: true)
            OnBoardingField(title: "Private Key ID", text: $viewModel.keyId, isRequired: true)
            
            // Private key section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Private Key (.p8) (Add key without space and remove top private key when copy paste)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("*")
                        .foregroundColor(.red)
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.getPrivateKey(filePath: viewModel.showOpenPanel())
                    }) {
                        Label("Select File", systemImage: "doc.badge.plus")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                
                Text("Remove header/footer when pasting")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $viewModel.privateKey)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 100)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .scrollContentBackground(.hidden)
            }
            
            // Error message
            if let errorMessage = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.orange)
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
                        if isSuccess {
                            isLoggedIn = true
                            viewModel.saveLoginState(isLoggedIn: true)
                        }
                    })
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isFormValid || viewModel.isShowSpinner)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(width: 450)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .shadow(color: .black.opacity(0.15), radius: 30, x: 0, y: 15)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        .padding(20)
//        .interactiveDismissDisabled(true)
    }
}

#Preview {
    OnBoardingView(isLoggedIn: .constant(false))
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
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if isRequired {
                    Text("*")
                        .foregroundColor(.red)
                }
            }
            
            TextField(title, text: $text)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
    }
}
