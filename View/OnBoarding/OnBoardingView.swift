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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add the Team Details. Tap Outside to close.")
                .padding(.horizontal)
                .padding(.bottom, 10)
                .font(.headline)
            OnBoardingField(title: "Team Name", text: $viewModel.teamName)
            OnBoardingField(title: "Issuer ID", text: $viewModel.issuerID)
            OnBoardingField(title: "Private Key ID", text: $viewModel.keyId)
            
            VStack(alignment: .leading) {
                HStack {
                    Text("Team p8 Key (Add key without space and remove top private key when copy paste)")
                        .padding(.horizontal)
                    Button(action: {
                        viewModel.getPrivateKey(filePath: viewModel.showOpenPanel())
                    }) {
                        Text("Select File")
                    }
                }
                .padding(.trailing, 16)
                VStack {
                    TextEditor(text: $viewModel.privateKey)
                        .cornerRadius(10)
                        .frame(height: 100)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white, lineWidth: 1)
                                .fill(Color.black.opacity(0.8))
                        )
                        .padding()
                }
            }
            .modifier(TestModifier())
            
            HStack {
                Spacer()
                Button(action: {
                    viewModel.getAllApps(completion: { isSuccess in
                        if isSuccess {
                            print("User Logged In")
                            isLoggedIn = true
                            viewModel.saveLoginState(isLoggedIn: true)
                        } else {
                            print("Invalid Auth")
                        }
                    })
                }) {
                    HStack {
                    Text("Continue")
                        
                    }
                }
                if viewModel.isShowSpinner {
                    SpinnerView()
                }
                Spacer()
            }
            .padding(.vertical, 15)
        }
        .frame(width: 500)
        .padding()
        .padding(.vertical, 20)
        .background(Color.black.opacity(0.8))
    }
}

#Preview {
    OnBoardingView(isLoggedIn: .constant(false))
}

struct OnBoardingField: View {
    var title: String
    @Binding var text: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .padding(.horizontal)
            TextField(title, text: $text)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white, lineWidth: 1)
                        .fill(Color.black.opacity(0.8))
                )
                .foregroundStyle(.white)
                .padding(.horizontal)
                
        }
        .modifier(TestModifier())
    }
}

struct TestModifier: ViewModifier {
    func body(content: Self.Content) -> some View {
        content
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.8))
            .cornerRadius(10)
    }
}
