//
//  SideBarView.swift
//  App Store
//
//  Created by Nayan Bhut on 02/05/24.
//

import SwiftUI

struct SideBarView: View {
    @StateObject var viewModel: SideBarViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack {
            Text("SideBar View")
            HStack {
                Menu("\(viewModel.currentTeam.getAppName())") {
                    ForEach(0..<Team.allCases.count, id: \.self) { teams in
                        Button("\(Team.allCases[teams].getAppName())", action: {
                            viewModel.currentTeam = Team.allCases[teams]
                        })
                    }
                }
                Button(action: {
                    print("Refresh Tapped")
                    viewModel.getAllApps(for: viewModel.currentTeam)
                }) {
                    Text("Refresh")
                }
            }
            .disabled(!viewModel.isAppListLoaded)
            appList()
        }
        .padding()
        .onAppear {
            viewModel.getAllApps(for: viewModel.currentTeam)
        }.onChange(of: viewModel.currentTeam) { oldValue, newValue in
            viewModel.isAppListLoaded = false
            viewModel.updateTeam()
        }
    }
    
    func appList() -> some View {
        VStack {
            if viewModel.isAppListLoaded {
                List(viewModel.arrApps, id: \.id) { app in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(app.name ?? "")")
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                            Text("\(app.currentLiveVersion.1) : \(app.currentState)")
                                .foregroundColor(.red)
                                .fontWeight(.bold)
                            Text("\(app.bundleId ?? "")")
                                .foregroundStyle(
                                    getAppFontStyle(isSelectedApp: app.isSelected))
                        }
                        .padding(.leading, 10)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .border(app.isSelected ? Color.green : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.setSelectedAppAndGetVersions(app: app) // Select app and call api to get Builds
                    }
                }
            } else {
                SpinnerView()
            }
            Spacer()
        }
    }
    
    private func getAppFontStyle(isSelectedApp: Bool) -> any ShapeStyle {
        let colors: [Color] = isSelectedApp ? [.red] : [.blue]
        
        return LinearGradient(
            colors: colors,
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

#Preview {
    SideBarView(viewModel: SideBarViewModel())
}
