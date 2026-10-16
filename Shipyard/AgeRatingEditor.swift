import SwiftUI

private struct AgeRatingEditorTarget: Identifiable {
    let appId: String
    let infoId: String
    let declaration: AgeRatingDeclarationModel
    let generation: Int
    var id: String { infoId }
}

struct AgeRatingsSection: View {
    @ObservedObject var detailVM: DetailViewModel
    let app: AppsData
    @State private var target: AgeRatingEditorTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Age Ratings")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            Text("Answer Apple's questionnaire about your app's content and capabilities. These settings are shared across platforms and localizations.")
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
            sectionContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $target) { target in
            AgeRatingEditor(detailVM: detailVM, app: app, target: target)
        }
        .onChange(of: detailVM.ageRatingContextGeneration) { _, _ in target = nil }
    }

    @ViewBuilder private var sectionContent: some View {
        switch detailVM.appInfoState {
        case .idle, .loading:
            ProgressView("Loading age ratings…")
                .controlSize(.small)
                .font(.system(size: 12))
        case .error(let message):
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.danger)
            Button("Retry Age Ratings") { detailVM.retryAppInfos() }
                .buttonStyle(.launchSecondary)
        case .empty:
            unavailable
        case .loaded(let infos):
            if let info = AgeRatingEditingSupport.preferredInfo(in: infos),
               let declaration = info.ageRatingDeclaration {
                HStack {
                    Text("\(AgeRatingQuestion.answers(from: declaration).count) saved answers · \(info.state?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Unknown state")")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                    Spacer()
                    Button(AgeRatingEditingSupport.isEditable(info) ? "Edit Age Ratings" : "View Age Ratings") {
                        target = AgeRatingEditorTarget(appId: app.id, infoId: info.id,
                                                       declaration: declaration,
                                                       generation: detailVM.ageRatingContextGeneration)
                    }
                    .buttonStyle(.launchSecondary)
                    .accessibilityIdentifier("app-info.age-ratings")
                }
            } else {
                unavailable
            }
        }
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No age-rating questionnaire is available for this app information. Set up the app information in App Store Connect, then refresh.")
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
            Button("Refresh Age Ratings") { detailVM.retryAppInfos() }
                .buttonStyle(.launchSecondary)
        }
    }
}

private struct AgeRatingEditor: View {
    @ObservedObject var detailVM: DetailViewModel
    let app: AppsData
    let target: AgeRatingEditorTarget
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toastCenter: ShipyardToastCenter
    @State private var draft: AgeRatingDraft
    @State private var isWorking = false
    @State private var needsReload = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var showDiscard = false
    @State private var operationTask: Task<Void, Never>?

    init(detailVM: DetailViewModel, app: AppsData, target: AgeRatingEditorTarget) {
        self.detailVM = detailVM
        self.app = app
        self.target = target
        _draft = State(initialValue: AgeRatingDraft(target.declaration))
    }

    private var isDirty: Bool { !draft.changes.isEmpty }
    private var wasMadeForKids: Bool { app.isOrEverWasMadeForKids == true }
    private var canEdit: Bool {
        guard detailVM.selectedApp?.id == target.appId,
              detailVM.ageRatingContextGeneration == target.generation,
              let info = detailVM.appInfoState.loadedValue?.first(where: { $0.id == target.infoId }),
              info.ageRatingDeclaration?.id == target.declaration.id else { return false }
        return AgeRatingEditingSupport.isEditable(info)
    }
    private var validationMessage: String? { draft.validationMessage(wasMadeForKids: wasMadeForKids) }
    private var isBusy: Bool { isWorking || detailVM.busyAgeRatingDeclarationIds.contains(target.declaration.id) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Age Ratings")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    Text(app.name ?? "App")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                }
                Spacer()
                Button("Cancel") {
                    if isDirty { showDiscard = true } else { dismiss() }
                }
                .buttonStyle(.launchSecondary)
                .keyboardShortcut(.cancelAction)
                .disabled(isBusy)
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(canEdit
                         ? "Review the saved answers and change the ones that apply to your app. Apple calculates the resulting ratings. Unanswered questions stay unanswered until you select an answer."
                         : "These answers are read-only in the current app information state. Refresh App Info when an editable app information record is available.")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                    ForEach(AgeRatingQuestion.Group.allCases, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(group.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(ShipyardTheme.title)
                            ForEach(AgeRatingQuestion.all.filter { $0.group == group }) { question in
                                questionRow(question)
                                    .disabled(!canEdit || isBusy)
                            }
                            if group == .additional {
                                Text("Once Apple approves an app as Made for Kids, that selection cannot be removed. A Republic of Korea override requires its official GRAC classification number.")
                                    .font(.system(size: 11))
                                    .foregroundColor(ShipyardTheme.body)
                                Link("Age-rating instructions and definitions", destination: URL(string: "https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating")!)
                                    .font(.system(size: 11))
                            }
                        }
                    }
                }
                .padding(20)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let message = errorMessage ?? validationMessage {
                    Text(message)
                        .foregroundColor(ShipyardTheme.danger)
                }
                if needsReload {
                    Text("The save outcome is unconfirmed. Reload saved answers before saving again; your local edits will be kept.")
                        .foregroundColor(ShipyardTheme.body)
                }
                if let statusMessage {
                    Text(statusMessage).foregroundColor(ShipyardTheme.body)
                }
                HStack {
                    Button("Reload Saved Answers") { runOperation(reload: true) }
                        .buttonStyle(.launchSecondary)
                        .disabled(isBusy)
                    Spacer()
                    if isBusy { ProgressView().controlSize(.small) }
                    Button("Save Age Ratings") { runOperation(reload: false) }
                        .buttonStyle(.launchPrimary)
                        .disabled(!canEdit || !isDirty || isBusy || needsReload || validationMessage != nil)
                        .accessibilityIdentifier("age-ratings.save")
                }
            }
            .font(.system(size: 12))
            .padding(20)
        }
        .frame(width: 720, height: 680)
        .background(ShipyardTheme.tableBackground)
        .interactiveDismissDisabled(isDirty || isBusy)
        .confirmationDialog("Discard age-rating changes?", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
        .onChange(of: detailVM.ageRatingContextGeneration) { _, _ in dismiss() }
        .onDisappear { operationTask?.cancel() }
    }

    private func questionRow(_ question: AgeRatingQuestion) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(question.title)
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Group {
                switch question.kind {
                case .boolean:
                    answerPicker(question, options: [("true", "Yes"), ("false", "No")])
                case .frequency:
                    answerPicker(question, options: [("NONE", "None"), ("INFREQUENT", "Infrequent"), ("FREQUENT", "Frequent")])
                case .choice(let options):
                    answerPicker(question, options: options)
                case .text, .url:
                    TextField("Optional", text: Binding(
                        get: { draft.answers[question.id]?.selection ?? "" },
                        set: { value in
                            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            draft.answers[question.id] = trimmed.isEmpty ? nil : .text(trimmed)
                            errorMessage = nil
                            statusMessage = nil
                        }))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .accessibilityLabel(question.title)
                }
            }
            .frame(width: 240)
        }
    }

    private func answerPicker(_ question: AgeRatingQuestion, options: [(value: String, title: String)]) -> some View {
        let current = draft.answers[question.id]?.selection ?? ""
        return Picker(question.title, selection: Binding(
            get: { draft.answers[question.id]?.selection ?? "" },
            set: { value in
                if value.isEmpty { draft.answers.removeValue(forKey: question.id) }
                else if case .boolean = question.kind { draft.answers[question.id] = .bool(value == "true") }
                else { draft.answers[question.id] = .text(value) }
                if question.id == "koreaAgeRatingOverride", value == "NONE" {
                    draft.answers.removeValue(forKey: "gracRatingClassificationNumber")
                }
                errorMessage = nil
                statusMessage = nil
            })) {
                Text(question.id == "kidsAgeBand" && !wasMadeForKids ? "Not Made for Kids" : "Not answered")
                    .tag("")
                    .disabled(question.id != "kidsAgeBand" || wasMadeForKids)
                if !current.isEmpty, !options.contains(where: { $0.value == current }) {
                    // Preserve a future server enum without forcing a different answer.
                    Text("Saved: \(current)").tag(current)
                }
                ForEach(options, id: \.value) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .labelsHidden()
            .accessibilityLabel(question.title)
            .accessibilityIdentifier("age-ratings.answer.\(question.id)")
            .font(.system(size: 12))
    }

    private func runOperation(reload: Bool) {
        guard !isBusy else { return }
        isWorking = true
        errorMessage = nil
        statusMessage = nil
        let changes = draft.changes
        operationTask = Task {
            let result: AgeRatingOperationResult
            if reload {
                result = await detailVM.reloadAgeRating(appId: target.appId, infoId: target.infoId,
                    declarationId: target.declaration.id, generation: target.generation)
            } else {
                result = await detailVM.saveAgeRating(appId: target.appId, infoId: target.infoId,
                    declarationId: target.declaration.id, generation: target.generation, changes: changes)
            }
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let declaration):
                if reload {
                    draft.reconcile(declaration)
                    needsReload = false
                    statusMessage = isDirty ? "Saved answers reloaded. Review your changes before saving." : "Your answers match the saved questionnaire."
                } else {
                    toastCenter.show("Age ratings saved", detail: app.name ?? "App", variant: .success)
                    dismiss()
                }
            case .failure(let message, let mustReload):
                errorMessage = message
                needsReload = needsReload || mustReload
            case .ignored:
                errorMessage = "This app information changed or another request is active. Close the editor and reopen Age Ratings."
            }
            isWorking = false
        }
    }
}
