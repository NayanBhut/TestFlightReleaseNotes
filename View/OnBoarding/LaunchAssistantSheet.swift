//
//  LaunchAssistantSheet.swift
//  App Store
//
//  Shipyard Launch Assistant: the stepped Add Team flow from the
//  add-team-credentials-light (Step 2 of 5) and add-team-validate-light
//  (Step 4 of 5) Figma frames. Steps 1 and 5 are not designed yet, so the
//  sheet opens directly at Step 2. All credential logic (JWT signing,
//  .p8 import, app-list verification, Keychain save) is the existing
//  OnBoardingViewModel — this file is presentation only.
//

import SwiftUI
import UniformTypeIdentifiers

/// Modal wizard that collects App Store Connect credentials and verifies
/// them before saving the team. Presented by ContentView over a dimmed
/// overlay; dismissal is via Back (first step), Cancel, or completion.
struct LaunchAssistantSheet: View {
    @StateObject var viewModel = OnBoardingViewModel()
    @Binding var isShowing: Bool
    @Binding var isLoggedIn: Bool

    @State private var step: LaunchStep = .credentials
    /// Guards the validation request so it fires once per visit to the
    /// validation step (re-entering via Back resets it).
    @State private var didAttemptVerification = false

    enum LaunchStep: Int {
        case credentials = 2
        case privateKey = 3
        case validation = 4

        var title: String {
            switch self {
            case .credentials: return "Add API Key Credentials"
            case .privateKey: return "Add Private Key"
            case .validation: return "Validation"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            LaunchTheme.border.frame(height: 1)

            stepBody
                .padding(24)

            progressDots
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

            footer
        }
        .frame(width: 480)
        .background(LaunchTheme.page)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(LaunchTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 12)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(step.title)
                .font(.subheader)
                .foregroundColor(LaunchTheme.title)

            Spacer()

            Text("Step \(step.rawValue) of 5")
                .font(.appCaption2)
                .foregroundColor(LaunchTheme.body)
        }
        .padding(20)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .credentials:
            credentialsBody
        case .privateKey:
            privateKeyBody
        case .validation:
            validationBody
                .onAppear(perform: runVerificationIfNeeded)
        }
    }

    private var credentialsBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Enter your App Store Connect API key information. These credentials can be obtained from users and access in App Store Connect.")
                .font(.appCaption)
                .foregroundColor(LaunchTheme.body)
                .lineSpacing(2)

            LaunchField(label: "Team Name", text: $viewModel.teamName, prompt: "Acme iOS")
            LaunchField(label: "Issuer ID", text: $viewModel.issuerID, prompt: "e.g. 572465ad-5091-4c0f-9275-xxxx", isMonospaced: true)
            LaunchField(label: "Key ID", text: $viewModel.keyId, prompt: "e.g. 2X88A7D9XX", isMonospaced: true)

            if viewModel.isDuplicateTeam {
                duplicateWarning
            }
        }
    }

    private var privateKeyBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add the .p8 private key you downloaded when the API key was created. Select the file, or paste the key contents directly.")
                .font(.appCaption)
                .foregroundColor(LaunchTheme.body)
                .lineSpacing(2)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Private Key (.p8)")
                        .font(.appCaption)
                        .foregroundColor(LaunchTheme.title)

                    Spacer()

                    Button(action: {
                        viewModel.getPrivateKey(filePath: viewModel.showOpenPanel())
                    }) {
                        Label("Select File", systemImage: "doc.badge.plus")
                            .font(.appCaption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Text("Remove header/footer when pasting")
                    .font(.appCaption2)
                    .foregroundColor(LaunchTheme.body)

                TextEditor(text: $viewModel.privateKey)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(height: 120)
                    .padding(8)
                    .background(LaunchTheme.field)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(LaunchTheme.border, lineWidth: 1)
                    )
                    .scrollContentBackground(.hidden)
            }

            if viewModel.isDuplicateTeam {
                duplicateWarning
            }

            if let errorMessage = viewModel.errorMessage {
                inlineError(errorMessage)
            }
        }
    }

    private var validationBody: some View {
        VStack(spacing: 24) {
            if viewModel.isShowSpinner {
                HStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.regular)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Verifying Credentials")
                            .font(.label)
                            .foregroundColor(LaunchTheme.title)
                        Text("Contacting App Store Connect…")
                            .font(.appCaption2)
                            .foregroundColor(LaunchTheme.body)
                    }
                    Spacer()
                }
                .padding(16)
                .background(LaunchTheme.field)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(LaunchTheme.border, lineWidth: 1)
                )
            } else if let appCount = viewModel.verifiedAppCount {
                HStack(spacing: 16) {
                    Image("LaunchCheckCircle")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Credentials Verified")
                            .font(.label)
                            .foregroundColor(LaunchTheme.title)
                        Text("Apps found: \(appCount)")
                            .font(.appCaption2)
                            .foregroundColor(LaunchTheme.body)
                    }
                    Spacer()
                }
                .padding(16)
                .background(LaunchTheme.successBackground)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(LaunchTheme.successBorder, lineWidth: 1)
                )
            } else if let errorMessage = viewModel.errorMessage {
                inlineError(errorMessage)
            }

            HStack(alignment: .top, spacing: 12) {
                Image("LaunchShieldAlert")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text("Security Note: Credentials and private keys are stored securely in your macOS Keychain and never leave your Mac.")
                    .font(.appCaption2)
                    .foregroundColor(LaunchTheme.body)
                    .lineSpacing(2)
                Spacer(minLength: 0)
            }
        }
    }

    private var duplicateWarning: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppTheme.pending)
            Text("A team with this name already exists")
                .font(.appCaption2)
                .foregroundColor(AppTheme.pending)
        }
        .accessibilityElement(children: .combine)
    }

    private func inlineError(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppTheme.negative)
            Text(message)
                .font(.appCaption2)
                .foregroundColor(AppTheme.negative)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Progress

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index <= step.rawValue ? LaunchTheme.accent : LaunchTheme.track)
                    .frame(width: 20, height: 4)
            }
            Spacer(minLength: 0)
        }
        .accessibilityLabel("Step \(step.rawValue) of 5")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Back", action: goBack)
                .buttonStyle(.launchSecondary)

            Spacer()

            Button("Cancel") {
                isShowing = false
            }
            .buttonStyle(.launchSecondary)

            primaryButton
        }
        .padding(16)
        .background(LaunchTheme.footer)
        .overlay(
            LaunchTheme.border.frame(height: 1),
            alignment: .top
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: 12,
                bottomTrailingRadius: 12, topTrailingRadius: 0
            )
        )
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .credentials:
            Button("Continue") {
                step = .privateKey
            }
            .buttonStyle(.launchPrimary)
            .disabled(!viewModel.credentialsValid)
            .keyboardShortcut(.defaultAction)
        case .privateKey:
            Button("Continue") {
                didAttemptVerification = false
                step = .validation
            }
            .buttonStyle(.launchPrimary)
            .disabled(!viewModel.isContinueEnabled || viewModel.isShowSpinner)
            .keyboardShortcut(.defaultAction)
        case .validation:
            if viewModel.verifiedAppCount != nil {
                Button("Add Team") {
                    if viewModel.saveLoginState() {
                        isLoggedIn = true
                        isShowing = false
                    }
                }
                .buttonStyle(.launchPrimary)
                .disabled(viewModel.isShowSpinner)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Try Again", action: retryVerification)
                    .buttonStyle(.launchPrimary)
                    .disabled(viewModel.isShowSpinner)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Navigation

    private func goBack() {
        switch step {
        case .credentials:
            // No Step 1 design yet — Back returns to the starting page.
            isShowing = false
        case .privateKey:
            step = .credentials
        case .validation:
            didAttemptVerification = false
            step = .privateKey
        }
    }

    private func runVerificationIfNeeded() {
        guard !didAttemptVerification else { return }
        didAttemptVerification = true
        retryVerification()
    }

    private func retryVerification() {
        viewModel.getAllApps(completion: { _ in })
    }
}

// MARK: - Fields

/// Single wizard field: 13pt label over a bordered input. Issuer ID and
/// Key ID use a monospaced face to match the Figma placeholders.
struct LaunchField: View {
    let label: String
    @Binding var text: String
    let prompt: String
    var isMonospaced: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.appCaption)
                .foregroundColor(LaunchTheme.title)

            TextField(prompt, text: $text)
                .font(isMonospaced ? .system(size: 13, design: .monospaced) : .appCaption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(LaunchTheme.field)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(LaunchTheme.border, lineWidth: 1)
                )
        }
    }
}

// MARK: - Button styles

extension ButtonStyle where Self == LaunchPrimaryButtonStyle {
    static var launchPrimary: LaunchPrimaryButtonStyle { LaunchPrimaryButtonStyle() }
}

extension ButtonStyle where Self == LaunchSecondaryButtonStyle {
    static var launchSecondary: LaunchSecondaryButtonStyle { LaunchSecondaryButtonStyle() }
}

extension ButtonStyle where Self == LaunchDestructiveButtonStyle {
    static var launchDestructive: LaunchDestructiveButtonStyle { LaunchDestructiveButtonStyle() }
}

/// Solid blue primary action (Continue / Add Team), per Figma.
struct LaunchPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appCaption)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(isEnabled ? LaunchTheme.accent : LaunchTheme.track)
            .cornerRadius(6)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

/// Bordered secondary action (Back / Cancel), per Figma.
struct LaunchSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appCaption)
            .foregroundColor(LaunchTheme.title)
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(LaunchTheme.field)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(LaunchTheme.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

/// Solid red destructive action (Remove from Review / Remove from Sale).
struct LaunchDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appCaption)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(isEnabled ? ShipyardTheme.danger : LaunchTheme.track)
            .cornerRadius(6)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

#Preview("LaunchAssistant / Credentials") {
    LaunchAssistantSheet(isShowing: .constant(true), isLoggedIn: .constant(false))
        .padding(40)
}

#Preview("LaunchAssistant / Dark") {
    LaunchAssistantSheet(isShowing: .constant(true), isLoggedIn: .constant(false))
        .padding(40)
        .preferredColorScheme(.dark)
}
