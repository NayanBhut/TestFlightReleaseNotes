//
//  AppConfigs.swift
//  App Store
//
//  Created by Nayan Bhut on 04/08/24.
//

import Foundation

enum AppConfigs {
    static let appListLimit: Int = 10
    static let versionLimit: Int = 10
    static let buildLimit: Int = 5
    /// Batch C: page size for customer reviews and review submissions.
    static let reviewLimit: Int = 50
    /// Batch C: page size for team-scoped resources (devices, certificates,
    /// bundle IDs, profiles, users).
    static let resourceLimit: Int = 50

    enum SortOption: String, CaseIterable {
        case nameAscending = "nameAscending"
        case nameDescending = "nameDescending"
        case stateAscending = "stateAscending"
        case stateDescending = "stateDescending"

        // Sorting is applied locally over the loaded pages; the apps endpoint
        // can't sort by state, and mixing a server sort with a cursor issued
        // under a different sort would silently skip rows.

        var displayName: String {
            switch self {
            case .nameAscending: return "Name (A-Z)"
            case .nameDescending: return "Name (Z-A)"
            case .stateAscending: return "State (A-Z)"
            case .stateDescending: return "State (Z-A)"
            }
        }
    }

    enum AppStateFilter: String, CaseIterable {
        case all = "all"
        case accepted = "ACCEPTED"
        case developerRejected = "DEVELOPER_REJECTED"
        case developerRemovedFromSale = "DEVELOPER_REMOVED_FROM_SALE"
        case inReview = "IN_REVIEW"
        case invalidBinary = "INVALID_BINARY"
        case metadataRejected = "METADATA_REJECTED"
        case notApplicable = "NOT_APPLICABLE"
        case pendingAppleRelease = "PENDING_APPLE_RELEASE"
        case pendingContract = "PENDING_CONTRACT"
        case pendingDeveloperRelease = "PENDING_DEVELOPER_RELEASE"
        case preorderReadyForSale = "PREORDER_READY_FOR_SALE"
        case prepareForSubmission = "PREPARE_FOR_SUBMISSION"
        case processingForAppStore = "PROCESSING_FOR_APP_STORE"
        case readyForReview = "READY_FOR_REVIEW"
        case readyForSale = "READY_FOR_SALE"
        case rejected = "REJECTED"
        case removedFromSale = "REMOVED_FROM_SALE"
        case waitingForExportCompliance = "WAITING_FOR_EXPORT_COMPLIANCE"
        case waitingForReview = "WAITING_FOR_REVIEW"

        /// The App Store Connect API value; nil means "no filter".
        var apiValue: String? {
            self == .all ? nil : rawValue
        }

        /// Human-readable label for menus, e.g. "Waiting for Export Compliance".
        /// `.capitalized` (not `.localizedCapitalized`) keeps capitalization stable
        /// across locales — these are English API enum values.
        var displayName: String {
            guard self != .all else { return "All States" }
            return rawValue
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
                .replacingOccurrences(of: " For ", with: " for ")
        }
    }

    /// Rating filter values for the Reviews tab (0 = All ratings).
    static let ratingOptions: [Int] = [0, 1, 2, 3, 4, 5]

    /// State filter for customer reviews in the Reviews tab.
    enum ReviewStateFilter: String, CaseIterable {
        case all = "All"
        case replied = "Replied"
        case unreplied = "Unreplied"

        var displayName: String {
            switch self {
            case .all: return "All States"
            case .replied: return "Replied"
            case .unreplied: return "Unreplied"
            }
        }
    }
}
