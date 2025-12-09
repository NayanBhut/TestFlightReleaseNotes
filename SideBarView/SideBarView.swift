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
        VStack(spacing: 0) {
            // Header section
            VStack(spacing: 12) {
                HStack {
                    Text("Apps")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button(action: {
                        isAddNewTeam = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                    }
                    .buttonStyle(.plain)
                    .help("Add Team")
                }
                
                // Team selector
                teamSelector()
                
                // Refresh button
                HStack {
                    Button(action: {
                        viewModel.getiOSApps()
                    }) {
                        Label("Refresh Apps", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.isAppListLoaded)
                    
                    Spacer()
                    
                    if let total = viewModel.appMeta?.paging.total {
                        Text("\(total) apps")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Apps list
            appList()
        }
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
    
    @ViewBuilder private func teamSelector() -> some View {
        VStack(spacing: 8) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTeams.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(CredentialStorage.shared.selectedTeam?.key ?? "No Team")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: showTeams ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            
            if showTeams {
                VStack(spacing: 4) {
                    ForEach(CredentialStorage.shared.getTeams, id: \.self) { team in
                        HStack {
                            Text(team)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Button(action: {
                                CredentialStorage.shared.deleteCredential(for: team)
                                if CredentialStorage.shared.getTeams.isEmpty {
                                    navigationManager.isLoggedIn = false
                                } else {
                                    CredentialStorage.shared.setDefaultTeam()
                                    viewModel.getiOSApps()
                                }
                            }) {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Remove team")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            CredentialStorage.shared.changeTeam = team
                            viewModel.isTeamChanged = true
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showTeams = false
                            }
                        }
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }
    
    @ViewBuilder private func appList() -> some View {
        if viewModel.isAppListLoaded {
            VStack(spacing: 0) {
                List(viewModel.arrApps, id: \.id) { app in
                    AppRowView(app: app, isSelected: app.isSelected)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.setSelectedAppAndGetVersions(app: app)
                        }
                }
                .listStyle(.sidebar)
                
                if viewModel.appMeta?.paging.nextCursor != nil {
                    VStack {
                        Divider()
                        Button("Load More Apps") {
                            viewModel.getiOSApps(nextPage: viewModel.appMeta?.paging.nextCursor)
                        }
                        .buttonStyle(.bordered)
                        .padding(.vertical, 12)
                    }
                }
            }
        } else {
            VStack(spacing: 16) {
                Spacer()
                ProgressView()
                    .scaleEffect(1.2)
                Text("Loading apps...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
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
