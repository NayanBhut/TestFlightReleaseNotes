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
        VStack(alignment: .leading) {
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
                        .frame(height: 100)
                        .padding(.vertical, 5)
                        .border(Color.white)
                        .background(Color.white)
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
                .padding(.horizontal)
        }
        .modifier(TestModifier())
    }
}

struct TestModifier: ViewModifier {
    func body(content: Self.Content) -> some View {
        content
            .padding(.vertical, 15)
            .background(Color.gray)
            .cornerRadius(10)
    }
}
