//
//  SharedActionSheets.swift
//  App Store
//
//  Module 12 (Monitoring & Shared Actions), Flows 12C/12D: shared save,
//  download and bulk destructive-action sheets plus the local operation
//  ledger. All destructive requests are independent, scoped and
//  non-atomic — there is no rollback and confirmed success is never
//  retried.
//
//  API contract notes (M12-H):
//  - PATCH /v1/appStoreVersionLocalizations/{id} carries description +
//    keywords in one resource request (not a multi-resource transaction).
//    On timeout, GET the same ID and compare both fields before retrying.
//    Discard Local never undoes an Apple write.
//  - GET /v1/certificates/{id} → certificateContent and GET
//    /v1/profiles/{id} → profileContent are authenticated retrievals;
//    retrieval, parsing and disk-write failures are separate stages.
//    .cer holds public certificate bytes (never a private key / .p12);
//    profiles write .mobileprovision (.provisionprofile for Mac only).
//  - DELETE /v1/certificates/{id} revokes; DELETE /v1/profiles/{id}
//    deletes. Replacement profiles use POST /v1/profiles, never PATCH.
//  - Endpoint IDs come from response.id; certificate serials and profile
//    UUIDs are distinct values. Copy actions move bundle-identifier strings
//    (com.acme.orbit), never JSON:API resource IDs.
//  - A received error is not an unconfirmed outcome; connection loss needs
//    GET reconciliation first. A 404/missing resource never proves our
//    request revoked it.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Bulk operation ledger

/// Per-item outcome of an independent bulk request. Rows stay independent:
/// one confirmed success never blocks or implies anything about the rest.
enum BulkItemOutcome: Equatable {
    /// 204 No Content (DELETE) or a completed local write.
    case confirmed(String)
    /// The connection ended mid-request — Apple may have accepted it.
    /// Never presented as failed/unchanged; retry stays locked until the
    /// ledger is reconciled via GET.
    case unknown(String)
    /// A received error (403, validation, …). Retry only after its cause
    /// is fixed — never a hot retry of a forbidden write.
    case denied(String)

    var isConfirmed: Bool {
        if case .confirmed = self { return true }
        return false
    }

    var detail: String {
        switch self {
        case .confirmed(let message), .unknown(let message), .denied(let message):
            return message
        }
    }
}

/// One selected row plus its independent outcome.
struct BulkLedgerItem: Identifiable {
    let id: String
    /// Human label, e.g. "Serial 89926084 · Distribution".
    let label: String
    /// Secondary line, e.g. "ID: <returned Distribution ID>".
    let sublabel: String
    var outcome: BulkItemOutcome?
}

/// Classifies a failure message into the ledger's three buckets.
enum BulkOutcomeClassification {
    static func classify(message: String) -> BulkItemOutcome {
        let lower = message.lowercased()
        if lower.contains("offline")
            || lower.contains("connection lost")
            || lower.contains("network connection")
            || lower.contains("timed out")
            || lower.contains("cancelled")
            || lower.contains("canceled") {
            return .unknown(message)
        }
        return .denied(message)
    }
}

// MARK: - Flow 12C · Save changes before leaving (Figma 114-10950)

/// Dirty-draft guard: description/keywords map to this locale's version
/// metadata. Save & Continue navigates only after a confirmed save;
/// multiple resources/locales are never a transaction.
struct UnsavedChangesSheet: View {
    var changedFields: [(field: String, locale: String)]
    var onCancel: () -> Void
    var onDiscard: () -> Void
    var onSaveAndContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Save changes before leaving?")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            warningBanner(
                title: "Orbit version metadata has local edits",
                body: "Description/keywords map to this locale’s version metadata. Save & Continue navigates only after confirmed save; multiple resources/locales are not a transaction."
            )
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Changed field").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Locale").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(ShipyardTheme.tableHeader)
                ForEach(changedFields, id: \.field) { change in
                    HStack(spacing: 12) {
                        Text(change.field).frame(maxWidth: .infinity, alignment: .leading)
                        Text(change.locale).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(LaunchTheme.border, lineWidth: 1))
            .cornerRadius(6)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Discard Changes", action: onDiscard)
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Save & Continue", action: onSaveAndContinue)
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 560)
    }
}

// MARK: - Flow 12C · Save outcome unconfirmed (Figma 114-10980)

/// Connection lost after the request: Apple may have accepted it, the
/// draft is preserved, the server outcome is unknown. Refresh (GET the
/// same localization and compare both fields) is primary; Retry stays
/// locked until reconciliation. Discard affects local edits only.
struct SaveOutcomeUnconfirmedSheet: View {
    var isReconciled: Bool
    var onCancel: () -> Void
    var onDiscardLocalEdits: () -> Void
    var onRefreshSavedValues: () -> Void
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Save outcome unconfirmed")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            warningBanner(
                title: "Outcome unknown · connection lost after request",
                body: "Apple may have accepted the interrupted request. Description and keywords remain in the local draft; the server outcome is unknown."
            )
            VStack(alignment: .leading, spacing: 12) {
                Text("Reconciliation status")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                Text("Refresh this version localization and compare both fields before retrying. Discard affects only local edits — not any Apple write. Cancel returns to the editor with the draft.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Discard Local Edits", action: onDiscardLocalEdits)
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Refresh Saved Values", action: onRefreshSavedValues)
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button("Retry · locked", action: onRetry)
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(!isReconciled)
                    .help(isReconciled ? "Retry the save" : "Refresh saved values first — retry unlocks after reconciliation")
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 560)
    }
}

// MARK: - Flow 12D · Download selected signing files (Figma 114-11005)

struct SigningDownloadRow: Identifiable {
    let id: String
    let rowLabel: String
    let outputName: String
}

/// Authenticated GET retrieves public certificate material and profile
/// content; local writes produce .cer / .mobileprovision (.provisionprofile
/// for macOS). No private key or .p12 is ever exported.
struct DownloadSigningFilesSheet: View {
    var rows: [SigningDownloadRow]
    var destination: String
    var onChooseDestination: () -> Void
    var onCancel: () -> Void
    var onDownload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Download selected signing files")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            VStack(alignment: .leading, spacing: 12) {
                Text("Download scope")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                Text("Authenticated GET retrieves public certificate material and profile content; local writes produce .cer / .mobileprovision (.provisionprofile for macOS). No private key or .p12 is exported.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
                labeledField(label: "Selected resources", value: "\(rows.count) files")
                VStack(alignment: .leading, spacing: 5) {
                    Text("Destination")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.title)
                    Button(action: onChooseDestination) {
                        HStack {
                            Text(destination)
                                .font(.system(size: 13))
                                .foregroundColor(ShipyardTheme.title)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text("⌄").foregroundColor(ShipyardTheme.body)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(LaunchTheme.field)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(LaunchTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Selected row").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Output").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(ShipyardTheme.tableHeader)
                ForEach(rows) { row in
                    HStack(spacing: 12) {
                        Text(row.rowLabel).frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.outputName).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(LaunchTheme.border, lineWidth: 1))
            .cornerRadius(6)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Download \(rows.count) Files", action: onDownload)
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(rows.isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 560)
    }

    private func labeledField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(ShipyardTheme.title)
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(ShipyardTheme.body)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ShipyardTheme.readOnlyField)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(LaunchTheme.border, lineWidth: 1))
        }
    }
}

// MARK: - Flow 12D · Revoke N certificates (Figma 114-11047)

/// Type-to-confirm revocation sheet. Each certificate DELETE is independent
/// and irreversible on success; affected profiles are refreshed afterwards
/// and recreated via POST /v1/profiles when needed — never PATCH.
struct RevokeCertificatesSheet: View {
    var certificates: [(serial: String, type: String, affectedProfiles: [String])]
    var confirmationText: String
    @Binding var typedConfirmation: String
    var onCancel: () -> Void
    var onRevoke: () -> Void

    private var isConfirmed: Bool {
        typedConfirmation.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            == confirmationText.uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Revoke \(certificates.count) selected certificates?")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            warningBanner(
                title: "Irreversible · \(affectedProfileCount) profiles affected",
                body: "Each certificate DELETE is independent and irreversible on success. Check team-key privileges, type and ownership. Recreate affected profiles with compatible replacements; installed-app effects vary by distribution."
            )
            VStack(alignment: .leading, spacing: 12) {
                Text("Confirm selected rows")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Type \(confirmationText)")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.title)
                    TextField("", text: $typedConfirmation)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                }
            }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Selected certificate").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Affected profile").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(ShipyardTheme.tableHeader)
                ForEach(certificates, id: \.serial) { cert in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(cert.serial) · \(cert.type)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(cert.affectedProfiles.joined(separator: "\n"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(LaunchTheme.border, lineWidth: 1))
            .cornerRadius(6)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Revoke \(certificates.count) Certificates", action: onRevoke)
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .tint(ShipyardTheme.danger)
                    .disabled(!isConfirmed)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 560)
    }

    private var affectedProfileCount: Int {
        Set(certificates.flatMap(\.affectedProfiles)).count
    }
}

// MARK: - Flow 12D · Delete N profiles (Figma 114-11091)

/// Type-to-confirm profile deletion. Each profile DELETE is independent;
/// downloaded copies are not removed automatically; certificates, bundle
/// IDs and devices remain. No batch rollback.
struct DeleteProfilesSheet: View {
    var profiles: [(name: String, type: String, dependency: String)]
    var confirmationText: String
    @Binding var typedConfirmation: String
    var onCancel: () -> Void
    var onDelete: () -> Void

    private var isConfirmed: Bool {
        typedConfirmation.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            == confirmationText.uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Delete \(profiles.count) selected profiles?")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            warningBanner(
                title: "Profile deletion cannot be undone",
                body: "Each profile DELETE is independent. Downloaded copies are not removed automatically. Certificates, bundle IDs and devices remain. Confirm per-item outcomes; no batch rollback."
            )
            VStack(alignment: .leading, spacing: 12) {
                Text("Confirm selection")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Type \(confirmationText)")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.title)
                    TextField("", text: $typedConfirmation)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                }
            }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Selected profile").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Type").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Dependency retained").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(ShipyardTheme.tableHeader)
                ForEach(profiles, id: \.name) { profile in
                    HStack(spacing: 12) {
                        Text(profile.name).frame(maxWidth: .infinity, alignment: .leading)
                        Text(profile.type).frame(maxWidth: .infinity, alignment: .leading)
                        Text(profile.dependency)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(LaunchTheme.border, lineWidth: 1))
            .cornerRadius(6)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Delete \(profiles.count) Profiles", action: onDelete)
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .tint(ShipyardTheme.danger)
                    .disabled(!isConfirmed)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 560)
    }
}

// MARK: - Bulk revocation results (Figma 114-11131 + M12-U 195-2509)

/// Shared result ledger for independent bulk DELETEs. Covers both the
/// confirmed-204 + denied-403 partial result and the M12-U unconfirmed
/// variant (1 confirmed + 1 unknown): confirmed rows are never retried,
/// unknown rows stay locked until Refresh / Reconcile runs, denied rows
/// need their cause (403 access) resolved first. Serial numbers shown are
/// display values — requests always used the retained response.id values.
struct BulkRevocationResultSheet: View {
    var title: String
    var bannerTitle: String
    var bannerBody: String
    /// Subject noun for the item column + confirmed verb, e.g. the
    /// certificate sheet passes the defaults while the profile sheet
    /// passes ("Profile", "Deleted").
    var itemNoun: String = "Certificate"
    var confirmedVerb: String = "Revoked"
    @Binding var items: [BulkLedgerItem]
    var isReconciled: Bool
    var onExport: () -> Void
    var onRefreshReconcile: () -> Void
    var onRetryUnknown: () -> Void
    var onDone: () -> Void

    private var confirmedCount: Int {
        items.filter { $0.outcome?.isConfirmed == true }.count
    }

    private var unknownItems: [BulkLedgerItem] {
        items.filter { if case .unknown = $0.outcome { return true }; return false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            warningBanner(title: bannerTitle, body: bannerBody)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(itemNoun).frame(maxWidth: .infinity, alignment: .leading)
                    Text("Result").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Next action").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(ShipyardTheme.tableHeader)
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading) {
                            Text(item.label)
                            Text(item.sublabel)
                                .font(.system(size: 11))
                                .foregroundColor(ShipyardTheme.body)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        outcomeText(item.outcome)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(nextAction(item.outcome))
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(LaunchTheme.border, lineWidth: 1))
            .cornerRadius(6)
            Text("\(items.count) selected · \(confirmedCount) confirmed · local ledger, not Apple audit history")
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
            HStack {
                Spacer()
                Button("Export Local Results…", action: onExport)
                    .buttonStyle(.bordered).controlSize(.small)
                Button(unknownItems.isEmpty ? "Retry Denied · locked" : "Retry Unknown · locked", action: onRetryUnknown)
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(!isReconciled || unknownItems.isEmpty)
                    .help(isReconciled ? "Retry the unconfirmed requests" : "Refresh / Reconcile first — retry stays locked until safe")
                Button("Refresh / Reconcile", action: onRefreshReconcile)
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button("Done", action: onDone)
                    .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 640)
    }

    private func outcomeText(_ outcome: BulkItemOutcome?) -> some View {
        let (text, color): (String, Color) = {
            switch outcome {
            case .confirmed(let detail): return ("\(confirmedVerb) · \(detail)", ShipyardTheme.title)
            case .unknown(let detail): return ("Unknown · \(detail)", ShipyardTheme.warningBorder)
            case .denied(let detail): return ("Failed · \(detail)", ShipyardTheme.danger)
            case .none: return ("No result", ShipyardTheme.body)
            }
        }()
        return Text(text).foregroundColor(color)
    }

    private func nextAction(_ outcome: BulkItemOutcome?) -> String {
        switch outcome {
        case .confirmed: return "Irreversible · never retry"
        case .unknown: return isReconciled ? "Reconciled · safe to retry" : "Reconcile first · Retry Unknown locked"
        case .denied: return "Resolve access · no hot retry"
        case .none: return "—"
        }
    }
}

// MARK: - M12-D · Signing download results (Figma 195-2632)

struct SigningFileResult: Identifiable {
    let id: String
    let outputName: String
    let material: String
    let fetchStage: String
    /// nil while the write stage has not run.
    var writeResult: WriteStageResult?
}

enum WriteStageResult: Equatable {
    case saved
    case failed(String)
}

/// Partial local result: every authenticated fetch completed; the local
/// file write is a separate stage. Retry reuses already-retrieved content
/// while valid and never re-downloads completed files. Export Local Results
/// records only these selected files — never a server audit.
struct SigningDownloadResultSheet: View {
    var results: [SigningFileResult]
    var destinationNote: String
    var canRetryLocalWrite: Bool
    var onChooseWritableFolder: () -> Void
    var onExport: () -> Void
    var onRetryLocalWrite: () -> Void
    var onDone: () -> Void

    private var savedCount: Int {
        results.filter { $0.writeResult == .saved }.count
    }

    private var failedCount: Int {
        results.filter { if case .failed = $0.writeResult { return true }; return false }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Signing downloads · partial local result")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            warningBanner(
                title: "\(savedCount) files saved · \(failedCount) local save failed",
                body: "All authenticated resource fetches completed. Failures below are local disk problems, not Apple API errors. Completed certificate files will not be downloaded again."
            )
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Selected output").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Authenticated resource fetch").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Local write result").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Next action").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 11))
                .foregroundColor(ShipyardTheme.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(ShipyardTheme.tableHeader)
                ForEach(results) { result in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading) {
                            Text(result.outputName)
                            Text(result.material)
                                .font(.system(size: 11))
                                .foregroundColor(ShipyardTheme.body)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(result.fetchStage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        writeText(result.writeResult)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(nextAction(result.writeResult))
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.title)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(LaunchTheme.border, lineWidth: 1))
            .cornerRadius(6)
            VStack(alignment: .leading, spacing: 8) {
                Text("Save the remaining files")
                    .font(.system(size: 13))
                    .foregroundColor(ShipyardTheme.title)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(destinationNote)
                            .font(.system(size: 12))
                            .foregroundColor(ShipyardTheme.title)
                        Text("Choose and validate a writable folder to enable Retry Local Write.")
                            .font(.system(size: 11))
                            .foregroundColor(ShipyardTheme.body)
                    }
                    Spacer()
                    Button("Choose Writable Folder…", action: onChooseWritableFolder)
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
                .padding(12)
                .background(ShipyardTheme.sidebarBackground)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(LaunchTheme.border, lineWidth: 1))
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Retry only the local write")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                    Text("Use the already retrieved content while it remains valid. Validate format and destination before writing. Keep fetch, parsing and write failures separate; never re-download completed files as part of this retry.")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Public material, authenticated retrieval")
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                    Text("The .cer files contain public certificate bytes — not a private key or .p12. Profiles are .mobileprovision files. No API private-key export or installation is performed. Decode and parse according to the actual valid returned content.")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.body)
                }
            }
            HStack {
                Spacer()
                Button("Export Local Results…", action: onExport)
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Done", action: onDone)
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Retry Local Write · locked", action: onRetryLocalWrite)
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(!canRetryLocalWrite)
                    .help(canRetryLocalWrite ? "Retry the local write with already-retrieved content" : "Choose a writable folder first")
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 720)
    }

    private func writeText(_ result: WriteStageResult?) -> some View {
        switch result {
        case .saved:
            return Text("Saved locally").foregroundColor(Color(red: 0.141, green: 0.541, blue: 0.239))
        case .failed(let message):
            return Text("Local save failed\n\(message)").foregroundColor(ShipyardTheme.warningBorder)
        case .none:
            return Text("Not attempted").foregroundColor(ShipyardTheme.body)
        }
    }

    private func nextAction(_ result: WriteStageResult?) -> String {
        switch result {
        case .saved: return "Complete · no re-download"
        case .failed: return "Choose writable folder\nThen retry local write only"
        case .none: return "—"
        }
    }
}

// MARK: - Copy bundle identifiers (Figma 114-11227)

/// Copies bundle-identifier strings (com.acme.orbit), never JSON:API
/// resource IDs. Endpoint requests always use returned response.id values;
/// no secrets are copied.
struct CopyBundleIdentifiersSheet: View {
    var selectedIdentifiers: [String]
    var filteredCount: Int
    @Binding var copyFilteredList: Bool
    @Binding var clipboardFormat: BundleIdentifierClipboardFormat
    var onCancel: () -> Void
    var onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Copy bundle identifier strings")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(ShipyardTheme.title)
            VStack(alignment: .leading, spacing: 12) {
                Text("Copy scope")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ShipyardTheme.title)
                Text((copyFilteredList ? [] : selectedIdentifiers).joined(separator: "\n"))
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
                Text("These are identifier strings, not JSON:API resource IDs. Endpoint requests use returned resource.id values; no secrets are copied.")
                    .font(.system(size: 12))
                    .foregroundColor(ShipyardTheme.body)
                scopeRow(
                    title: "Selected rows",
                    subtitle: "\(selectedIdentifiers.count) bundle identifiers",
                    selected: !copyFilteredList
                ) { copyFilteredList = false }
                scopeRow(
                    title: "Current filtered list",
                    subtitle: "\(filteredCount) visible identifiers",
                    selected: copyFilteredList
                ) { copyFilteredList = true }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Clipboard format")
                        .font(.system(size: 12))
                        .foregroundColor(ShipyardTheme.title)
                    Menu {
                        ForEach(BundleIdentifierClipboardFormat.allCases, id: \.self) { format in
                            Button(format.displayName) { clipboardFormat = format }
                        }
                    } label: {
                        HStack {
                            Text(clipboardFormat.displayName)
                                .font(.system(size: 13))
                                .foregroundColor(ShipyardTheme.title)
                            Spacer()
                            Text("⌄").foregroundColor(ShipyardTheme.body)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(LaunchTheme.field)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(LaunchTheme.border, lineWidth: 1))
                    }
                    .menuStyle(.borderlessButton)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Copy \(copyFilteredList ? filteredCount : selectedIdentifiers.count) Identifiers", action: onCopy)
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            if !selectedIdentifiers.isEmpty { copyFilteredList = false }
        }
    }

    private func scopeRow(title: String, subtitle: String, selected: Bool, onSelect: @escaping () -> Void) -> some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: selected ? "circle.inset.filled" : "circle")
                    .foregroundColor(selected ? ShipyardTheme.accent : ShipyardTheme.body)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundColor(ShipyardTheme.title)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(ShipyardTheme.body)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

enum BundleIdentifierClipboardFormat: CaseIterable, Hashable {
    case onePerLine
    case commaSeparated

    var displayName: String {
        switch self {
        case .onePerLine: return "One identifier per line"
        case .commaSeparated: return "Comma-separated"
        }
    }

    func render(_ identifiers: [String]) -> String {
        switch self {
        case .onePerLine: return identifiers.joined(separator: "\n")
        case .commaSeparated: return identifiers.joined(separator: ", ")
        }
    }
}

// MARK: - Local results export (app-owned, never a server audit)

/// Writes a ledger-only export of the selected files/outcomes. Records the
/// local operation — it makes no claim about other resources and is never
/// presented as an Apple audit receipt.
enum LocalResultsExport {
    static func saveLedger(filename: String, lines: [String]) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.canCreateDirectories = true
        if let fileType = UTType(filenameExtension: "txt") {
            panel.allowedContentTypes = [fileType]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let body = lines.joined(separator: "\n")
        try? body.write(to: url, atomically: true, encoding: .utf8)
    }

    static func lines(
        title: String,
        scope: String,
        when: Date,
        rows: [(label: String, outcome: String)]
    ) -> [String] {
        var lines = [title, scope, "Local operation ledger — not Apple audit history"]
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        lines.append("Recorded \(formatter.string(from: when))")
        lines.append("")
        for row in rows {
            lines.append("\(row.label) — \(row.outcome)")
        }
        return lines
    }
}
