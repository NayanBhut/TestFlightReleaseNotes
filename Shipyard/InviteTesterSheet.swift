//
//  InviteTesterSheet.swift
//  App Store
//
//  Invite-tester sheet from the invite-tester-sheet-light Figma frame:
//  email, optional names, and multi-group assignment checkboxes over
//  Cancel / Send Invitation. One POST assigns every checked group.
//

import SwiftUI

struct InviteTesterSheet: View {
    @ObservedObject var betaVM: BetaViewModel
    var onDone: () -> Void

    @State private var email = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var checkedGroupIds: Set<String> = []
    @State private var isSending = false

    private var canSend: Bool {
        EmailValidator.isValid(email.trimmingCharacters(in: .whitespacesAndNewlines))
            && !checkedGroupIds.isEmpty
            && !isSending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Invite Tester")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(ShipyardTheme.title)
                Text("Invite an external tester to join beta testing.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
            }

            VStack(alignment: .leading, spacing: 12) {
                sheetField(label: "EMAIL ADDRESS", text: $email, prompt: "tester@acme.com")

                HStack(spacing: 12) {
                    sheetField(label: "FIRST NAME (OPTIONAL)", text: $firstName, prompt: "Jane")
                    sheetField(label: "LAST NAME (OPTIONAL)", text: $lastName, prompt: "Doe")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("GROUP ASSIGNMENTS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ShipyardTheme.body)
                    if betaVM.groups.isEmpty {
                        Text("No beta groups yet — create one first.")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                    } else {
                        ForEach(betaVM.groups, id: \.id) { group in
                            Toggle(group.name ?? "Unnamed group", isOn: Binding(
                                get: { checkedGroupIds.contains(group.id) },
                                set: { checked in
                                    if checked { checkedGroupIds.insert(group.id) }
                                    else { checkedGroupIds.remove(group.id) }
                                }
                            ))
                            .font(.system(size: 13))
                            .toggleStyle(.checkbox)
                            .disabled(isSending)
                        }
                    }
                }
                .padding(.top, 6)
            }

            if betaVM.hasError, let message = betaVM.errorMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { onDone() }
                    .buttonStyle(.launchSecondary)
                    .disabled(isSending)
                if isSending {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button("Send Invitation") {
                        Task<Void, Never> { @MainActor in
                            isSending = true
                            defer { isSending = false }
                            betaVM.clearError()
                            await betaVM.inviteTesterToGroups(
                                email: email,
                                firstName: firstName.isEmpty ? nil : firstName,
                                lastName: lastName.isEmpty ? nil : lastName,
                                groupIds: Array(checkedGroupIds)
                            )
                            if !betaVM.hasError {
                                onDone()
                            }
                        }
                    }
                    .buttonStyle(.launchPrimary)
                    .disabled(!canSend)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear {
            // Pre-check the current group so single-group invites are one tap.
            if let selected = betaVM.selectedGroup {
                checkedGroupIds = [selected.id]
            }
        }
    }

    private func sheetField(label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(ShipyardTheme.body)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(LaunchTheme.field)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(LaunchTheme.border, lineWidth: 1)
                )
                .disabled(isSending)
        }
    }
}
