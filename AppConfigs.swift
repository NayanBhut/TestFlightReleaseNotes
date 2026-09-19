//
//  AppConfigs.swift
//  App Store
//
//  Created by Nayan Bhut on 04/08/24.
//

import Foundation

enum AppConfigs {
    static var appListLimit: Int = 10
    static var versionLimit: Int = 10
    static var buildLimit: Int = 5
    
    static var appListSort: SortOption = .nameDescending
    static var filterName: String = ""
    static var filterState: AppStateFilter = .all
    
    enum SortOption: String, CaseIterable {
        case nameAscending = "nameAscending"
        case nameDescending = "nameDescending"
        case stateAscending = "stateAscending"
        case stateDescending = "stateDescending"
        
        var queryValue: String {
            switch self {
            case .nameAscending: return "name"
            case .nameDescending: return "-name"
            case .stateAscending: return "state"
            case .stateDescending: return "-state"
            }
        }
        
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
        case all = "All"
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
        
        var apiValue: String? {
            switch self {
            case .all: return nil
            case .accepted: return "ACCEPTED"
            case .developerRejected: return "DEVELOPER_REJECTED"
            case .developerRemovedFromSale: return "DEVELOPER_REMOVED_FROM_SALE"
            case .inReview: return "IN_REVIEW"
            case .invalidBinary: return "INVALID_BINARY"
            case .metadataRejected: return "METADATA_REJECTED"
            case .notApplicable: return "NOT_APPLICABLE"
            case .pendingAppleRelease: return "PENDING_APPLE_RELEASE"
            case .pendingContract: return "PENDING_CONTRACT"
            case .pendingDeveloperRelease: return "PENDING_DEVELOPER_RELEASE"
            case .preorderReadyForSale: return "PREORDER_READY_FOR_SALE"
            case .prepareForSubmission: return "PREPARE_FOR_SUBMISSION"
            case .processingForAppStore: return "PROCESSING_FOR_APP_STORE"
            case .readyForReview: return "READY_FOR_REVIEW"
            case .readyForSale: return "READY_FOR_SALE"
            case .rejected: return "REJECTED"
            case .removedFromSale: return "REMOVED_FROM_SALE"
            case .waitingForExportCompliance: return "WAITING_FOR_EXPORT_COMPLIANCE"
            case .waitingForReview: return "WAITING_FOR_REVIEW"
            }
        }
    }
}
