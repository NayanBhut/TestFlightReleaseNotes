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
                    AppRowView(app: app, isSelected: app.isSelected)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.setSelectedAppAndGetVersions(app: app)
                        }
                }
                .listStyle(.sidebar)
                
                if viewModel.appMeta?.paging.nextCursor != nil {
                    Button("Load More Apps") {
                        viewModel.getiOSApps(nextPage: viewModel.appMeta?.paging.nextCursor)
                    }
                    .buttonStyle(.bordered)
                    .padding(.vertical, 8)
                }
            } else {
                SpinnerView()
            }
            Spacer()
        }
    }
}

struct AppRowView: View {
    let app: AppsData
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(isSelected ? Color.accentColor : Color.clear)
                .frame(width: 3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name ?? "Unknown App")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    Text(app.currentLiveVersion.1)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(app.currentState)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(getStateColor(app.currentState))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(getStateColor(app.currentState).opacity(0.15))
                        .cornerRadius(4)
                }
                
                Text(app.bundleId ?? "")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 16))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
    
    private func getStateColor(_ state: String) -> Color {
        switch state.uppercased() {
        case "READY_FOR_SALE", "READY FOR SALE":
            return .green
        case "PENDING_DEVELOPER_RELEASE", "PENDING DEVELOPER RELEASE":
            return .orange
        case "IN_REVIEW", "IN REVIEW":
            return .blue
        case "WAITING_FOR_REVIEW", "WAITING FOR REVIEW":
            return .yellow
        case "REJECTED":
            return .red
        default:
            return .secondary
        }
    }
}

#Preview {
    SideBarView(viewModel: SideBarViewModel(), isAddNewTeam: .constant(false), isNewAccountAdded: .constant(false))
}
