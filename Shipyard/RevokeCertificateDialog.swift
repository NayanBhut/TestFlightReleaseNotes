//
//  RevokeCertificateDialog.swift
//  App Store
//
//  Destructive confirmation from the revoke-certificate-dialog-light Figma
//  frame: red-tinted icon tile, title + consequence copy, Cancel / Revoke.
//  Presented as a sheet from the certificates table.
//

import SwiftUI

struct RevokeCertificateDialog: View {
    var certificateName: String
    var onCancel: () -> Void
    var onRevoke: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 16) {
                Circle()
                    .fill(Color(red: 1.0, green: 0.231, blue: 0.188).opacity(0.1))
                    .frame(width: 40, height: 40)
                    .overlay(
                        ShipyardIcon(name: "ShipyardRevokeWarn", size: 20)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Revoke Certificate?")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(ShipyardTheme.title)
                    Text("Revoking this certificate cannot be undone and will immediately invalidate any active provisioning profiles that depend on it. Running apps built with these profiles will continue to work, but new installations will fail.")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.body)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.title)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(width: 100)
                    .background(LaunchTheme.field)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(LaunchTheme.border, lineWidth: 1)
                    )
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)

                Button("Revoke") { onRevoke() }
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(width: 100)
                    .background(Color(red: 1.0, green: 0.231, blue: 0.188))
                    .cornerRadius(6)
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Revoke \(certificateName)?")
    }
}
