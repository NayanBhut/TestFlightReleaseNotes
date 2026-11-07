import SwiftUI
import AppKit

struct SubmissionIssuesSheet: View {
    @ObservedObject var coordinator: SubmissionCoordinator
    var refresh: () async -> Void
    var retry: () async -> Void
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Submission Issues")
                .font(.system(size: 18)).foregroundStyle(ShipyardTheme.title)
                .accessibilityIdentifier("submission.issues.title")
            Text("Resolve the issues below, save your changes, then refresh this version before retrying.")
                .font(.system(size: 12)).foregroundStyle(ShipyardTheme.body)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let failure = coordinator.failure {
                        ForEach(Array(failure.issues.enumerated()), id: \.element.id) { index, issue in
                            issueCard(issue, index: index)
                        }
                    }
                    if let failure = coordinator.refreshFailure {
                        Text("Refresh Issues").font(.system(size: 13, weight: .semibold))
                        ForEach(Array(failure.issues.enumerated()), id: \.element.id) { index, issue in
                            issueCard(issue, index: index + 1000)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 220, maxHeight: 380)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 12) {
                    if let failure = coordinator.rateLimitFailure, let deadline = failure.retryNotBefore {
                        let remaining = max(0, ceil(deadline.timeIntervalSince(context.date)))
                        let seconds = Int(min(86_400, remaining))
                        Text("Retry-After: \(failure.retryAfter ?? "not supplied (60-second local backoff)") · \(seconds > 0 ? "Wait \(remaining > 86_400 ? "at least " : "")\(seconds) seconds" : "Delay elapsed")")
                            .font(.system(size: 12)).foregroundStyle(ShipyardTheme.body)
                            .accessibilityIdentifier("submission.retryAfter")
                    }
                    if let message = coordinator.validationMessage {
                        Text(message).font(.system(size: 12)).foregroundStyle(ShipyardTheme.body)
                            .accessibilityIdentifier("submission.validation")
                    }
                    HStack {
                        Button("Copy technical details") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(coordinator.technicalDetails, forType: .string)
                        }.buttonStyle(.launchSecondary).accessibilityIdentifier("submission.copy")
                        Spacer()
                        Button("Dismiss", action: dismiss)
                            .buttonStyle(.launchSecondary).disabled(coordinator.busy || coordinator.refreshing)
                            .accessibilityIdentifier("submission.dismiss")
                        Button(coordinator.refreshing ? "Refreshing…" : "Refresh Version") {
                            Task { await refresh() }
                        }.buttonStyle(.launchSecondary)
                            .disabled(coordinator.busy || coordinator.refreshing || coordinator.isCoolingDown(at: context.date))
                            .accessibilityIdentifier("submission.refresh")
                        Button(coordinator.busy ? "Submitting…" : "Retry Submission") {
                            Task { await retry() }
                        }.buttonStyle(.launchPrimary)
                            .disabled(!coordinator.canRetry(at: context.date))
                            .accessibilityIdentifier("submission.retry")
                    }
                }
            }
        }
        .padding(24).frame(width: 760).background(LaunchTheme.page)
        .interactiveDismissDisabled(coordinator.busy || coordinator.refreshing)
        .onDisappear { coordinator.invalidateValidation() }
    }

    private func issueCard(_ issue: SubmissionIssue, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(issue.friendlyTitle).font(.system(size: 13, weight: .semibold)).foregroundStyle(ShipyardTheme.title)
            if let detail = issue.detail { Text(detail).font(.system(size: 12)).textSelection(.enabled) }
            if !issue.affectedResource.isEmpty {
                Text("Affected field/resource: \(issue.affectedResource)")
                    .font(.system(size: 11)).textSelection(.enabled)
            }
            if let solution = issue.solution {
                Text(solution).font(.system(size: 12)).foregroundStyle(ShipyardTheme.body)
            }
            SubmissionTechnicalDetails(issue: issue, index: index)
        }
        .foregroundStyle(ShipyardTheme.body)
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(ShipyardTheme.body.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SubmissionTechnicalDetails: View {
    let issue: SubmissionIssue
    let index: Int
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                expanded.toggle()
            } label: {
                Label("Technical details", systemImage: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("submission.technical.\(index)")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Status: \(issue.status ?? "not supplied")")
                    Text("Code: \(issue.code ?? "not supplied")")
                    if let title = issue.title { Text("Apple title: \(title)") }
                    if let pointer = issue.pointer { Text("Source pointer: \(pointer)") }
                    ForEach(Array(issue.resourcePaths.enumerated()), id: \.offset) { _, path in Text("Resource: \(path)") }
                }.font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            }
        }
    }
}
