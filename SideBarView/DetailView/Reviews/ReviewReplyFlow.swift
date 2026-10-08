//
//  ReviewReplyFlow.swift
//  App Store
//
//  Module 11 (Customer Reviews) reply flow: the edit-draft editor
//  (114:10344), submit confirmation (114:10444), the C11-S sending,
//  C11-P published, C11-E validation-error and C11-R read-only states,
//  the unconfirmed-outcome view (114:10569), the delete confirmation
//  (114:10663) and the DELETE-accepted view (114:10689).
//
//  API contract notes (C11-H implementation contract, Apple OpenAPI 4.5):
//  - POST /v1/customerReviewResponses creates or overwrites the developer
//    response (attributes.responseBody + relationships.review). 201 returns
//    the response resource — use that returned record and state. No PATCH
//    and no delete-first. Response state is only PENDING_PUBLISH or
//    PUBLISHED; "Sending" is a local operation, never an Apple enum.
//  - lastModifiedDate records modification, not publication. Responses may
//    take up to 24h to appear — guidance, not a deadline guarantee.
//  - DELETE /v1/customerReviewResponses/{id} returns 204 with no body and
//    removes the reply only, never the review or rating. Storefront
//    deletion can lag: refresh before showing verified absence. A missing
//    relationship or generic 404 never proves absence on its own.
//  - Drafts are local (exact character count shown; no verified maximum —
//    never impose one). Replies are public: no credentials or private data.
//  - Writes need Account Holder / Admin / Customer Support. The configured
//    key role is not role introspection and authorizes no future write.
//

import SwiftUI

// MARK: - Editor mode

/// In-editor reply state. Sending/published/error/read-only/delete
/// branches are independent alternatives, never a sequential chain.
enum ReviewReplyMode: Equatable {
    case editing
    case sending
    case pending
    case published
    case unconfirmed
    case validationError
    case readOnly
    case deleteAccepted
}

// MARK: - Review reply editor (114:10344 + state branches)

/// Full review-detail editor. Shows the selected customer review, the
/// last fetched PUBLISHED snapshot, and the local draft with its exact
/// character count — then the branch matching the reply lifecycle.
struct ReviewReplyEditorView: View {
    let reviewId: String
    let app: AppsData
    @ObservedObject var reviewsVM: ReviewsViewModel
    /// Stale-cache guard (114:14026): editing stays disabled until a
    /// refresh succeeds.
    var isStale: Bool = false
    /// Delete-accepted view offers "Return to Inbox"; nil falls back to Back.
    var onReturnToInbox: (() -> Void)? = nil
    var onBack: () -> Void

    @State private var draft: String = ""
    @State private var draftSavedAt: Date? = nil
    @State private var mode: ReviewReplyMode = .editing
    @State private var showSubmitConfirm = false
    @State private var showDeleteConfirm = false
    @State private var explicitError: String? = nil
    @State private var reconciled = false
    @State private var verifiedAbsenceNote: String? = nil
    @State private var bootDone = false

    private var accountKey: String? {
        CredentialStorage.shared.selectedTeam?.key
    }

    private var review: CustomerReviewModel? {
        reviewsVM.reviewRows.first(where: { $0.id == reviewId })
    }

    private var liveResponse: CustomerReviewResponseModel? {
        review?.response
    }

    private var isWriteDisabled: Bool {
        isStale || mode == .sending
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                backRow
                heading
                switch mode {
                case .editing:
                    editingBody
                case .sending:
                    sendingBody
                case .pending:
                    pendingBody
                case .published:
                    publishedBody
                case .unconfirmed:
                    unconfirmedBody
                case .validationError:
                    validationErrorBody
                case .readOnly:
                    readOnlyBody
                case .deleteAccepted:
                    deleteAcceptedBody
                }
            }
            .padding(24)
        }
        .background(ShipyardTheme.tableBackground)
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .onAppear(perform: boot)
        .sheet(isPresented: $showSubmitConfirm) {
            SubmitResponseSheet(
                appName: app.name ?? "App",
                review: review,
                draft: draft,
                onCancel: { showSubmitConfirm = false },
                onSubmit: {
                    showSubmitConfirm = false
                    Task { await send() }
                }
            )
        }
        .sheet(isPresented: $showDeleteConfirm) {
            DeleteResponseSheet(
                appName: app.name ?? "App",
                review: review,
                onCancel: { showDeleteConfirm = false },
                onDelete: {
                    showDeleteConfirm = false
                    Task { await deleteReply() }
                }
            )
        }
    }

    private func boot() {
        guard !bootDone else { return }
        bootDone = true
        if let saved = ReviewDraftStore.load(account: accountKey, appId: app.id, reviewId: reviewId) {
            draft = saved.text
            draftSavedAt = saved.saved
        }
        if reviewsVM.deleteAcceptedReviewIds.contains(reviewId) {
            mode = .deleteAccepted
        } else if case .pending = replyState {
            mode = .pending
        } else if case .published = replyState {
            mode = .published
        }
    }

    private enum ReplyPresence {
        case none
        case pending
        case published
    }

    private var replyState: ReplyPresence {
        switch liveResponse?.state {
        case "PENDING_PUBLISH": return .pending
        case "PUBLISHED": return .published
        default:
            // A successful fetch with no response is verified absence;
            // anything else (no fetch yet) is treated as none here and the
            // snapshot card says so explicitly.
            return .none
        }
    }

    // MARK: Chrome

    private var backRow: some View {
        Button(action: onBack) {
            Text("‹ Reviews")
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to reviews")
    }

    @ViewBuilder
    private var heading: some View {
        switch mode {
        case .sending:
            reviewHeading(
                title: "Sending developer response · \(app.name ?? "App")",
                subtitle: "The edited reply is being sent to Apple. Sending is a local operation, not an Apple response state."
            )
        case .pending:
            reviewHeading(
                title: "Customer response · pending publication",
                subtitle: nil
            )
        case .published:
            reviewHeading(
                title: "Customer response · published",
                subtitle: nil
            )
        case .unconfirmed:
            reviewHeading(title: "Reply outcome unconfirmed", subtitle: nil)
        case .validationError:
            reviewHeading(
                title: "Developer response · validation rejected",
                subtitle: "Illustrative validation-error scenario: Apple explicitly rejected an empty responseBody. This is not a timeout or an unknown network outcome."
            )
        case .readOnly:
            reviewHeading(
                title: "Customer reviews · read-only access",
                subtitle: "Illustrative current request: 403 / insufficient write access. Reviews and developer responses can still be read with this connection."
            )
        case .deleteAccepted:
            reviewHeading(title: "Delete request accepted · refresh pending", subtitle: nil)
        case .editing:
            reviewHeading(
                title: "Edit customer reply · \(app.name ?? "App")",
                subtitle: "Edit the developer response for this review. Save Draft keeps the reply local; Submit Response sends the edited reply to Apple and overwrites the existing response."
            )
        }
    }

    private func reviewHeading(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
            }
        }
    }

    // MARK: Shared pieces

    private var reviewContextColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selected customer review")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            if let review {
                VStack(alignment: .leading, spacing: 0) {
                    Text(reviewIdentityLine(review, appName: app.name))
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                    if let title = review.title, !title.isEmpty {
                        Text("“\(title)”")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                    }
                    if let body = review.body, !body.isEmpty {
                        Text("“\(body)”")
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.body)
                    }
                    Text("— \(review.reviewerNickname ?? "Anonymous")")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                }
                Text("\(CredentialStorage.shared.selectedTeam?.key ?? "Team") · Apple ID \(app.id)")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
            }
        }
    }

    private var lastFetchedSnapshotCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Last fetched PUBLISHED reply")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                Spacer()
                Text("cached snapshot")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.tertiary)
            }
            VStack(alignment: .leading, spacing: 8) {
                if let body = lastPublishedBody {
                    Text(body)
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                    Text("PUBLISHED · \(lastModifiedText) · fetched \(lastCheckedText). Not a fresh confirmation of current server state.")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                } else {
                    Text("No published reply in the last fetched snapshot.")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                    Text("Verified absence only counts on a successful fetch — a missing relationship or generic 404 never proves it alone.")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                }
            }
            .padding(12)
            .background(LaunchTheme.card)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(LaunchTheme.border, lineWidth: 1))
        }
    }

    private var lastPublishedBody: String? {
        liveResponse?.state == "PUBLISHED" ? liveResponse?.responseBody : snapshotPublishedBody
    }

    /// The snapshot card prefers the live PUBLISHED reply; the Figma
    /// illustrative snapshot text is the fallback when the fetched reply
    /// is absent or pending.
    private var snapshotPublishedBody: String? { nil }

    private var lastModifiedText: String {
        if let raw = liveResponse?.lastModifiedDate {
            return "lastModifiedDate \(reviewDisplayDate(raw))"
        }
        return "lastModifiedDate unknown"
    }

    private var lastCheckedText: String {
        if let date = reviewsVM.responseLastChecked[reviewId] {
            return "checked \(reviewDateTime(date))"
        }
        return "not yet checked"
    }

    private func draftField(editable: Bool, errorBorder: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Public reply\(editable ? "" : " · local draft")")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
                Spacer()
                // Exact character count only — no verified numeric maximum
                // exists, so none is imposed (C11-H).
                Text("\(draft.count) characters")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.tertiary)
            }
            TextEditor(text: $draft)
                .font(.system(size: 13))
                .frame(minHeight: 96)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(LaunchTheme.field)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(errorBorder ? ShipyardTheme.dangerBorder : LaunchTheme.border, lineWidth: 1)
                )
                .disabled(!editable)
            if errorBorder {
                Text("Enter a response before resubmitting. Field: attributes.responseBody.")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.danger)
            }
        }
    }

    private var publicReplyNote: some View {
        Text("This is a public reply. Do not send credentials or private tester data.")
            .font(.system(size: 11))
            .foregroundColor(ShipyardTheme.body)
    }

    // MARK: Bodies

    private var editingBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            if isStale {
                staleEditingBanner
            }
            if let note = verifiedAbsenceNote {
                infoBanner(title: "Response deleted · verified", body: note)
            }
            HStack(alignment: .top, spacing: 24) {
                reviewContextColumn.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Developer response · edited draft")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    Text("Save Draft is local. Submit overwrites this review’s response through POST; visibility of the previous storefront reply is not guaranteed.")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                    draftField(editable: !isWriteDisabled)
                    if let saved = draftSavedAt {
                        Text("Draft saved \(reviewDateTime(saved)) · kept locally for this account, app and review.")
                            .font(.system(size: 11))
                            .foregroundColor(ShipyardTheme.body)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            lastFetchedSnapshotTable
        }
    }

    private var staleEditingBanner: some View {
        warningBanner(
            title: "Cached snapshot · stale",
            body: "Editing is disabled until a refresh succeeds. The rows below are the last fetched snapshot, not current server state."
        )
    }

    private var lastFetchedSnapshotTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Last fetched PUBLISHED snapshot").frame(maxWidth: .infinity, alignment: .leading)
                Text("Status").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 11))
            .foregroundColor(ShipyardTheme.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(ShipyardTheme.tableHeader)
            HStack(spacing: 12) {
                Text(liveResponse?.responseBody.map { "“\($0)”" } ?? "—")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(liveResponse.map { "\($0.state ?? "—") · lastModifiedDate \($0.lastModifiedDate.map(reviewDisplayDate) ?? "unknown")" } ?? "No response")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 12))
            .foregroundColor(ShipyardTheme.title)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(LaunchTheme.border, lineWidth: 1))
        .cornerRadius(6)
    }

    private var sendingBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            infoBanner(
                title: "Sending… · awaiting the POST result",
                body: "Keep the draft and review available. Closing this window does not cancel a write Apple has already accepted. Do not submit or delete again while this operation is unresolved."
            )
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 24) {
                    reviewContextColumn
                    lastFetchedSnapshotCard
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Developer response · sending edited draft")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                    Text("Draft editing is temporarily locked for this attempt. Your saved local draft is separate from the response Apple may return.")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                    draftField(editable: false)
                    publicReplyNote
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            outcomeHandlingTable
        }
    }

    private var outcomeHandlingTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Outcome handling").frame(maxWidth: .infinity, alignment: .leading)
                Text("Next destination").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 11))
            .foregroundColor(ShipyardTheme.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(ShipyardTheme.tableHeader)
            outcomeRow("201 · response resource returned", "Use returned PENDING_PUBLISH or PUBLISHED; not automatic storefront success.")
            outcomeRow("Timeout / connection lost", "Outcome unconfirmed · reconcile before retrying.")
            outcomeRow("Explicit Apple error received", "Show the actual returned cause; correct it before another write.")
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(LaunchTheme.border, lineWidth: 1))
        .cornerRadius(6)
    }

    private func outcomeRow(_ left: String, _ right: String) -> some View {
        HStack(spacing: 12) {
            Text(left).frame(maxWidth: .infinity, alignment: .leading)
            Text(right).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12))
        .foregroundColor(ShipyardTheme.title)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var pendingBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            infoBanner(
                title: "Apple response state: PENDING_PUBLISH",
                body: "Apple returned a response awaiting publication. Do not resend the same draft. Refresh for PUBLISHED; previous storefront reply visibility is not guaranteed."
            )
            HStack(alignment: .top, spacing: 24) {
                reviewContextColumn.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Submitted response")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    Text(liveResponse?.responseBody ?? "—")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Reply state").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Time").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(ShipyardTheme.tableHeader)
                HStack(spacing: 12) {
                    Text("Response lastModifiedDate").frame(maxWidth: .infinity, alignment: .leading)
                    Text(lastModifiedText).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.title)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                HStack(spacing: 12) {
                    Text("Publication").frame(maxWidth: .infinity, alignment: .leading)
                    Text("PENDING_PUBLISH").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.title)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(LaunchTheme.border, lineWidth: 1))
            .cornerRadius(6)
        }
    }

    private var publishedBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            successBanner(
                title: "Current Apple response state: PUBLISHED",
                body: "A fresh GET returned PUBLISHED for the response matching this review. Storefront caches may still take time to update; this is not confirmation of every storefront."
            )
            HStack(alignment: .top, spacing: 24) {
                reviewContextColumn.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Developer response · returned edited reply")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                    Text(liveResponse?.responseBody ?? "—")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                    Text("Source: fresh response GET · linked to the selected customer review. This is the returned response, not the local draft.")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 0) {
                publishedPropertyRow("state", "PUBLISHED")
                publishedPropertyRow("lastModifiedDate · modification time", "\(liveResponse?.lastModifiedDate.map(reviewDisplayDate) ?? "unknown") — not a publication timestamp")
                publishedPropertyRow("Checked locally · fresh GET", lastCheckedText)
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(LaunchTheme.border, lineWidth: 1))
            .cornerRadius(6)
            Text("Apple Help says responses may take up to 24 hours to appear. This is guidance, not a deadline guarantee. Refresh to check the actual response state.")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
        }
    }

    private func publishedPropertyRow(_ left: String, _ right: String) -> some View {
        HStack(spacing: 12) {
            Text(left).frame(maxWidth: .infinity, alignment: .leading)
            Text(right).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12))
        .foregroundColor(ShipyardTheme.title)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var unconfirmedBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            warningBanner(
                title: "Reply outcome unconfirmed",
                body: "The connection ended during sending; Apple may have accepted the request. Refresh the review and response before retrying. Preserve this local draft. The same guard applies to uncertain deletion."
            )
            HStack(alignment: .top, spacing: 24) {
                reviewContextColumn.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Reply outcome reconciliation")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Last confirmed response snapshot")
                                .font(.system(size: 11))
                                .foregroundColor(ShipyardTheme.body)
                            Spacer()
                            Text("stale / unknown")
                                .font(.system(size: 11))
                                .foregroundColor(ShipyardTheme.tertiary)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(lastPublishedBody ?? "No confirmed reply snapshot.")
                                .font(.system(size: 13))
                                .foregroundColor(ShipyardTheme.title)
                            Text("Last fetched PUBLISHED reply from before this attempt — not confirmation of the current response.")
                                .font(.system(size: 11))
                                .foregroundColor(ShipyardTheme.body)
                        }
                        .padding(12)
                        .background(Color.white)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(LaunchTheme.border, lineWidth: 1))
                    }
                    draftField(editable: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var validationErrorBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            dangerBanner(
                title: "Apple validation error received · correct the public reply",
                body: explicitError ?? "An explicit error response was received for this POST. Correct the actual returned cause before resubmitting. Network failures are different: an ambiguous write must be reconciled before retrying."
            )
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 24) {
                    reviewContextColumn
                    lastFetchedSnapshotCard
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Correct developer response")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                    Text("The draft below is empty. The previously fetched published reply remains visible as a snapshot, not a guarantee of current storefront visibility.")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                    draftField(editable: !isWriteDisabled, errorBorder: draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Returned Apple error · generic display slot")
                            .font(.system(size: 11))
                            .foregroundColor(ShipyardTheme.title)
                        Text("Display the received title/detail here. Exact code and resource ID are intentionally not fabricated for this illustrative scenario.")
                            .font(.system(size: 11))
                            .foregroundColor(ShipyardTheme.body)
                    }
                    .padding(12)
                    .background(ShipyardTheme.sidebarBackground)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(LaunchTheme.border, lineWidth: 1))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Correction guardrail").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Required behavior").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(ShipyardTheme.tableHeader)
                outcomeRow("Before retry", "Non-empty corrected response + authenticated write access.")
                outcomeRow("Edit / resubmit", "POST creates or overwrites the existing response. No PATCH; no delete-first.")
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(LaunchTheme.border, lineWidth: 1))
            .cornerRadius(6)
            publicReplyNote
        }
    }

    private var readOnlyBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            infoBanner(
                title: "Replies are not permitted by the current request",
                body: "The write request returned 403 / insufficient access. The configured credential is \(CredentialStorage.shared.selectedTeam?.key ?? "this team"); that label is configuration, not introspection of the effective role or a promise of future authorization."
            )
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 24) {
                    reviewContextColumn
                    lastFetchedSnapshotCard
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Developer response · local draft only")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                    Text("You can edit and save this draft locally. Posting, replacement, and deletion require Account Holder, Admin, or Customer Support; App Manager alone is not sufficient.")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                    draftField(editable: !isStale)
                    Text("A future submitted reply will be public. Do not include credentials or private tester data.")
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 0) {
                accessRow("Configured credential", "\(CredentialStorage.shared.selectedTeam?.key ?? "Team") · App Manager (configured, not an effective-role lookup)")
                accessRow("Read review and response", "Permitted for the current accessible resources.")
                accessRow("Post / edit / delete response", "Disabled · authenticate account and resource write access before enabling.")
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(LaunchTheme.border, lineWidth: 1))
            .cornerRadius(6)
            HStack(spacing: 12) {
                Text("Switch connection without discarding drafts. Manage account access outside Shipyard; a key role string alone cannot authorize a future write.")
                    .font(.system(size: 11))
                    .foregroundColor(ShipyardTheme.body)
                Spacer()
                teamSwitchMenu
                Button("Manage Access ↗") {
                    if let url = URL(string: "https://appstoreconnect.apple.com/access/users") {
                        ASCLink.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func accessRow(_ left: String, _ right: String) -> some View {
        HStack(spacing: 12) {
            Text(left).frame(maxWidth: .infinity, alignment: .leading)
            Text(right).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12))
        .foregroundColor(ShipyardTheme.title)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var teamSwitchMenu: some View {
        Menu {
            ForEach(CredentialStorage.shared.teams, id: \.self) { team in
                Button(team) {
                    // Drafts are keyed by account, so switching preserves
                    // this review's draft under the previous account.
                    CredentialStorage.shared.changeTeam = team
                }
            }
        } label: {
            Text("Switch Connection…")
                .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var deleteAcceptedBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            successBanner(
                title: "Apple accepted DELETE · storefront update not yet verified",
                body: "A successful DELETE returns 204 with no response body. The customer review remains. Refresh the review/response before showing verified absence; storefront changes may lag."
            )
            HStack(alignment: .top, spacing: 24) {
                reviewContextColumn.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Response state")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    Text("Local operation status, not an Apple response enum. No DELETION_PENDING state exists. Keep only explicitly saved drafts; do not infer absence from an omitted relationship or any 404.")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Action bar

    @ViewBuilder
    private var actionBar: some View {
        switch mode {
        case .editing:
            HStack(spacing: 12) {
                actionBarStatus("Requires Account Holder, Admin, or Customer Support role to post, edit, or delete.")
                Spacer()
                Button("Revert to Latest Fetched") { revertToFetched() }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(isWriteDisabled)
                Button("Save Draft") { saveDraft() }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Submit Response…") { showSubmitConfirm = true }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(isWriteDisabled || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 24)
            .frame(height: 56)
            .background(ShipyardTheme.sidebarBackground)
        case .sending:
            HStack(spacing: 12) {
                actionBarStatus("Local draft persisted separately · Duplicate POST and Delete are disabled while this request is in flight.")
                Spacer()
                Button("Save Local Draft") { saveDraft() }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Delete Reply…") {}
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(true)
                Button("Sending…") {}
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(true)
            }
            .padding(.horizontal, 24)
            .frame(height: 56)
            .background(ShipyardTheme.sidebarBackground)
        case .pending, .published:
            HStack(spacing: 12) {
                actionBarStatus(mode == .pending
                    ? "Response checked \(lastCheckedText) · not a publication timestamp"
                    : "Response checked \(lastCheckedText) · local check time")
                Spacer()
                if mode == .pending {
                    Button("Open Existing Review") { onBack() }
                        .buttonStyle(.bordered).controlSize(.small)
                } else {
                    Button("Edit Reply…") { mode = .editing }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(isWriteDisabled)
                    Button("Delete Reply…") { showDeleteConfirm = true }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(isWriteDisabled)
                }
                Button("Refresh Reply Status") { Task { await refreshStatus() } }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            .padding(.horizontal, 24)
            .frame(height: 56)
            .background(ShipyardTheme.sidebarBackground)
        case .unconfirmed:
            HStack(spacing: 12) {
                actionBarStatus("Last confirmed response snapshot stale · current draft retained locally")
                Spacer()
                Button("Keep Draft") { mode = .editing }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Retry Send · locked") { Task { await send() } }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(!reconciled)
                    .help(reconciled ? "Retry the send" : "Refresh Reply Status first — retry unlocks after reconciliation")
                Button("Refresh Reply Status") { Task { await refreshStatus() } }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.horizontal, 24)
            .frame(height: 56)
            .background(ShipyardTheme.sidebarBackground)
        case .validationError:
            HStack(spacing: 12) {
                actionBarStatus("Empty draft retained locally · last confirmed snapshot preserved · Resubmit stays disabled until the response is corrected and write access is confirmed.")
                Spacer()
                Button("Save Local Draft") { saveDraft() }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Refresh Reply Status") { Task { await refreshStatus() } }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Resubmit Response…") {
                    if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        explicitError = "Enter a response before resubmitting. Field: attributes.responseBody."
                    } else {
                        showSubmitConfirm = true
                    }
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 24)
            .frame(height: 56)
            .background(ShipyardTheme.sidebarBackground)
        case .readOnly:
            HStack(spacing: 12) {
                actionBarStatus("Local draft stays available · Preserve drafts by account, app, and review when changing credentials or app context.")
                Spacer()
                Button("Save Local Draft") { saveDraft() }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Edit Reply…") {}
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(true)
                Button("Delete Reply…") {}
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(true)
                Button("Submit Response…") {}
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(true)
            }
            .padding(.horizontal, 24)
            .frame(height: 56)
            .background(ShipyardTheme.sidebarBackground)
        case .deleteAccepted:
            HStack(spacing: 12) {
                actionBarStatus("Delete acknowledgement received · latest response state awaiting reconciliation")
                Spacer()
                Button("Return to Inbox") {
                    if let onReturnToInbox {
                        onReturnToInbox()
                    } else {
                        onBack()
                    }
                }
                .buttonStyle(.bordered).controlSize(.small)
                Button("Refresh Reply Status") { Task { await refreshStatus() } }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            .padding(.horizontal, 24)
            .frame(height: 56)
            .background(ShipyardTheme.sidebarBackground)
        }
    }

    private func actionBarStatus(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(ShipyardTheme.body)
    }

    // MARK: Actions

    private func saveDraft() {
        ReviewDraftStore.save(draft, account: accountKey, appId: app.id, reviewId: reviewId)
        draftSavedAt = Date()
    }

    private func revertToFetched() {
        draft = liveResponse?.responseBody ?? ""
        draftSavedAt = nil
    }

    private func send() async {
        mode = .sending
        reconciled = false
        switch await reviewsVM.sendResponse(reviewId: reviewId, responseBody: draft) {
        case .sent(let state, _):
            ReviewDraftStore.clear(account: accountKey, appId: app.id, reviewId: reviewId)
            draftSavedAt = nil
            mode = state == "PUBLISHED" ? .published : .pending
        case .validationError(let message):
            explicitError = message
            mode = .validationError
        case .forbidden:
            mode = .readOnly
        case .connectionLost:
            mode = .unconfirmed
        case .ignored:
            mode = .editing
        }
    }

    private func refreshStatus() async {
        switch await reviewsVM.refreshResponse(reviewId: reviewId) {
        case .updated(let state):
            reconciled = true
            if reviewsVM.deleteAcceptedReviewIds.contains(reviewId) {
                // A response is still present after an accepted DELETE:
                // storefront lag — stay on the accepted view.
                return
            }
            if state == "PUBLISHED" {
                mode = .published
            } else {
                mode = .pending
            }
        case .unanswered:
            reconciled = true
            if reviewsVM.deleteAcceptedReviewIds.contains(reviewId) {
                // Verified absence after DELETE — back to a clean editor.
                verifiedAbsenceNote = "Refresh verified the reply is gone. The customer review remains."
                mode = .editing
            } else {
                mode = .editing
            }
        case .unknown:
            // Fetch failed: still unknown, retry stays locked.
            if mode != .unconfirmed {
                explicitError = "Couldn't refresh the reply status. Check the connection and try again."
                mode = .validationError
            }
        }
    }

    private func deleteReply() async {
        guard let responseId = liveResponse?.id else { return }
        switch await reviewsVM.deleteResponse(reviewId: reviewId, responseId: responseId) {
        case .deleted:
            mode = .deleteAccepted
        case .explicitError(let message):
            explicitError = message
            mode = .validationError
        case .forbidden:
            mode = .readOnly
        case .connectionLost:
            // Uncertain deletion takes the same unconfirmed guard.
            mode = .unconfirmed
        case .ignored:
            break
        }
    }
}

// MARK: - Submit confirmation (114:10444)

/// POST creates or overwrites the developer reply. Publication is not
/// immediate; the reply will be public — no private information.
struct SubmitResponseSheet: View {
    var appName: String
    var review: CustomerReviewModel?
    var draft: String
    var onCancel: () -> Void
    var onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Submit edited customer response?")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            infoBanner(title: "This reply will be public", body: "POST creates or overwrites the developer response. Publication is not immediate. Avoid private information; no delete-first step is needed.")
            if let review {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Selected customer review")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    Text(reviewIdentityBlock(review, appName: appName))
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Response preview")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    Text(draft)
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Submit Response", action: onSubmit)
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 560)
    }
}

// MARK: - Delete confirmation (114:10663)

/// Deletes the developer reply only. The customer rating and review
/// remain; deletion cannot be undone; storefront changes may lag.
struct DeleteResponseSheet: View {
    var appName: String
    var review: CustomerReviewModel?
    var onCancel: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Delete published customer response?")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            warningBanner(
                title: "Only the developer reply is removed",
                body: "The customer rating and review remain. Deletion cannot be undone; write a new response later if needed. Apple may take time to reflect the change."
            )
            if let review {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Selected customer review")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    Text(reviewIdentityBlock(review, appName: appName))
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Published developer response")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ShipyardTheme.title)
                    Text("“\(review.response?.responseBody ?? "—")”")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Delete Response", action: onDelete)
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .tint(ShipyardTheme.danger)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 560)
    }
}

// MARK: - Shared review pieces

/// "Orbit · 2 stars · United States · Oct 3, 2026" one-liner.
func reviewIdentityLine(_ review: CustomerReviewModel, appName: String?) -> String {
    var parts: [String] = []
    if let appName, !appName.isEmpty { parts.append(appName) }
    if let rating = review.rating { parts.append("\(rating) star\(rating == 1 ? "" : "s")") }
    if let territory = review.territory, !territory.isEmpty { parts.append(territory) }
    if let raw = review.createdDate { parts.append(reviewDisplayDate(raw)) }
    return parts.joined(separator: " · ")
}

func reviewIdentityBlock(_ review: CustomerReviewModel, appName: String?) -> String {
    var lines = [reviewIdentityLine(review, appName: appName)]
    if let title = review.title, !title.isEmpty {
        lines.append("“\(title)”")
    } else if let body = review.body, !body.isEmpty {
        lines.append("“\(body)”")
    }
    lines.append("— \(review.reviewerNickname ?? "Anonymous")")
    return lines.joined(separator: "\n")
}

func reviewDisplayDate(_ raw: String) -> String {
    guard let date = ReviewsViewModel.reviewDate(raw) else { return raw }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter.string(from: date)
}

func reviewDateTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

/// Star glyphs "★★☆☆☆" for compact table cells.
func reviewStarsText(_ rating: Int?) -> String {
    let value = min(max(rating ?? 0, 0), 5)
    return String(repeating: "★", count: value) + String(repeating: "☆", count: 5 - value)
}

func infoBanner(title: String, body: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
        Text("ⓘ")
            .font(.system(size: 16))
            .foregroundColor(ShipyardTheme.accent)
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.accent)
            Text(body)
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
        }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(ShipyardTheme.infoSurface)
    .cornerRadius(8)
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ShipyardTheme.infoBorder, lineWidth: 0.5))
}

func successBanner(title: String, body: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
        Text("✓")
            .font(.system(size: 16))
            .foregroundColor(Color(red: 0.141, green: 0.541, blue: 0.239))
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(red: 0.141, green: 0.541, blue: 0.239))
            Text(body)
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
        }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(ShipyardTheme.successSurface)
    .cornerRadius(8)
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ShipyardTheme.successBorder, lineWidth: 0.5))
}

func dangerBanner(title: String, body: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
        Text("⚠")
            .font(.system(size: 16))
            .foregroundColor(ShipyardTheme.dangerBorder)
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShipyardTheme.dangerBorder)
            Text(body)
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.body)
        }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(ShipyardTheme.dangerSurface)
    .cornerRadius(8)
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ShipyardTheme.dangerBorder, lineWidth: 0.5))
}
