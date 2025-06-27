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
    @EnvironmentObject var navigationManager: NavigationManager
    @Binding var isAddNewTeam: Bool
    @Binding var isNewAccountAdded: Bool
    @State var showTeams = false
    
    var body: some View {
        VStack {
            HStack {
                Text("SideBar View")

                Button(action: {
                    isAddNewTeam = true
                }) {
                    Text("Add Team")
                }
            }
            
            HStack(alignment: .top) {
                VStack {
                    Button(action: {
                        print("Refresh Tapped")
                        showTeams.toggle()
                    }) {
                        HStack {
                            Spacer()
                                .frame(width: 5)
                            Text(CredentialStorage.shared.selectedTeam?.key ?? "")
                            Spacer()
                            Image(systemName: "chevron.down")
                                .foregroundStyle(.blue)
                            
                        }
                    }
                    if showTeams {
                        VStack(spacing: 5) {
                            ForEach(CredentialStorage.shared.getTeams, id: \.self) { team in
                                HStack {
                                    Spacer()
                                        .frame(width: 5)
                                    Text(team)
                                        .background(Color.white)
                                        .cornerRadius(10)
                                        .padding(.leading, 5)
                                    Spacer()
                                    
                                    Button(action: {
                                        CredentialStorage.shared.deleteCredential(for: team)
                                        if CredentialStorage.shared.getTeams.count == 0 {
                                            navigationManager.isLoggedIn = false
                                        } else {
                                            CredentialStorage.shared.setDefaultTeam()
                                            viewModel.getiOSApps()
                                        }
                                    }) {
                                        Text("Remove")
                                            .foregroundStyle(Color.black)
                                            .padding(.trailing, 5)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                                    .padding(.trailing, 5)
                                    
                                }
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    CredentialStorage.shared.changeTeam = team
                                    viewModel.isTeamChanged = true
                                    showTeams = false
                                }
                            }
                        }
                        .background(Color.white)
                        .foregroundStyle(Color.black)
                        .cornerRadius(10)
                        .transition(.move(edge: .top))
                        .animation(.easeInOut(duration: 4), value: showTeams)
                    }
                }
                
                Button(action: {
                    print("Refresh Tapped")
                    viewModel.getiOSApps()
                }) {
                    Text("Refresh")
                }
            }
            .disabled(!viewModel.isAppListLoaded)
            appList()
        }
        .padding()
        .onAppear {
            if CredentialStorage.shared.selectedTeam == nil {
                if CredentialStorage.shared.setDefaultTeam() {
                    navigationManager.isLoggedIn = false
                }
            }
            viewModel.getiOSApps()
        }
        .onChange(of: isNewAccountAdded) { oldValue, newValue in
            if newValue {
                viewModel.getiOSApps()
            }
        }
        .onChange(of: viewModel.isTeamChanged) { oldValue, newValue in
            if newValue {
                viewModel.isAppListLoaded = false
                viewModel.updateTeam()
                viewModel.isTeamChanged = false
            }
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
                Spacer()
                if viewModel.appMeta?.paging.nextCursor != nil {
                    Button(action: {
                        viewModel.getiOSApps(nextPage: viewModel.appMeta?.paging.nextCursor)
                    }) {
                        Text("Load More Apps")
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
    SideBarView(viewModel: SideBarViewModel(), isAddNewTeam: .constant(false), isNewAccountAdded: .constant(false))
}
