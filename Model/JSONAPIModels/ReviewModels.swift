//
//  ReviewModels.swift
//  App Store
//
//  Batch C3: Customer reviews + review submissions (read-only).
//  - GET /v1/apps/{id}/customerReviews?include=response&sort=-createdDate
//  - GET /v1/reviewSubmissions?filter[app]={id}
//

import Foundation
import JSONAPI

@ResourceWrapper(type: "customerReviews")
struct CustomerReviewModel: Equatable {
    static func == (lhs: CustomerReviewModel, rhs: CustomerReviewModel) -> Bool {
        return lhs.id == rhs.id
    }

    var id: String

    @ResourceAttribute var rating: Int?
    @ResourceAttribute var title: String?
    @ResourceAttribute var body: String?
    @ResourceAttribute var reviewerNickname: String?
    @ResourceAttribute var createdDate: String?
    /// ISO territory code (e.g. USA).
    @ResourceAttribute var territory: String?
    /// Included via include=response; nil when the review has no reply.
    @ResourceRelationship var response: CustomerReviewResponseModel?
}

@ResourceWrapper(type: "customerReviewResponses")
struct CustomerReviewResponseModel: Equatable {
    static func == (lhs: CustomerReviewResponseModel, rhs: CustomerReviewResponseModel) -> Bool {
        return lhs.id == rhs.id
    }

    var id: String

    @ResourceAttribute var responseBody: String?
    @ResourceAttribute var lastModifiedDate: String?
    @ResourceAttribute var state: String?
}

@ResourceWrapper(type: "reviewSubmissions")
struct ReviewSubmissionModel: Equatable {
    static func == (lhs: ReviewSubmissionModel, rhs: ReviewSubmissionModel) -> Bool {
        return lhs.id == rhs.id
    }

    var id: String

    @ResourceAttribute var platform: String?
    /// READY_FOR_REVIEW, WAITING_FOR_REVIEW, IN_REVIEW, UNRESOLVED_ISSUES,
    /// CANCELING, COMPLETING, COMPLETE.
    @ResourceAttribute var state: String?
    @ResourceAttribute var submittedDate: String?
    /// Included via include=appStoreVersion; nil when not requested.
    @ResourceRelationship var appStoreVersion: AppStoreVersionsModel?
    /// Included via include=submittedByActor (verified against a recorded
    /// GET /v1/reviewSubmissions/{id} response); nil when not requested.
    @ResourceRelationship var submittedByActor: ActorModel?
}

typealias CustomerReviewsDocument = CompoundDocument<[CustomerReviewModel], Meta>
typealias ReviewSubmissionsDocument = CompoundDocument<[ReviewSubmissionModel], Meta>

// MARK: - POST /v1/reviewSubmissions (submit for review)

/// Verified against spec v4.3.1: only `relationships.app` is required;
/// `attributes.platform` is optional (server defaults from the app).
struct ReviewSubmissionCreateRequest: Codable {
    let data: ReviewSubmissionCreateData
}

struct ReviewSubmissionCreateData: Codable {
    let type: String = "reviewSubmissions"
    let attributes: ReviewSubmissionCreateAttributes?
    let relationships: ReviewSubmissionAppLinkage
}

struct ReviewSubmissionCreateAttributes: Codable {
    let platform: String?
}

struct ReviewSubmissionAppLinkage: Codable {
    let app: ReviewSubmissionAppRef
}

struct ReviewSubmissionAppRef: Codable {
    let data: ReviewSubmissionAppRefData
}

struct ReviewSubmissionAppRefData: Codable {
    let type: String = "apps"
    let id: String
}

// MARK: - PATCH /v1/reviewSubmissions/{id} (submit / cancel flags)

/// Verified against spec v4.3.1: `submitted: true` submits a
/// READY_FOR_REVIEW submission; `canceled: true` cancels it. There is NO
/// DELETE on this collection — cancel is a PATCH, not a delete.
struct ReviewSubmissionUpdateRequest: Codable {
    let data: ReviewSubmissionUpdateData
}

struct ReviewSubmissionUpdateData: Codable {
    let type: String = "reviewSubmissions"
    let id: String
    let attributes: ReviewSubmissionUpdateAttributes
}

struct ReviewSubmissionUpdateAttributes: Codable {
    let submitted: Bool?
    let canceled: Bool?
}

// MARK: - Phased releases

/// Verified against spec v4.3.1. PhasedReleaseState: INACTIVE, ACTIVE,
/// PAUSED, COMPLETE. No GET collection exists — state is read via
/// GET /v1/appStoreVersions/{id}/appStoreVersionPhasedRelease (404 = none).
@ResourceWrapper(type: "appStoreVersionPhasedReleases")
struct PhasedReleaseModel: Equatable {
    static func == (lhs: PhasedReleaseModel, rhs: PhasedReleaseModel) -> Bool {
        return lhs.id == rhs.id
    }

    var id: String

    @ResourceAttribute var phasedReleaseState: String?
}

/// POST body: only the appStoreVersion linkage is required (server
/// defaults the release to INACTIVE; PATCH ACTIVE starts it).
struct PhasedReleaseCreateRequest: Codable {
    let data: PhasedReleaseCreateData
}

struct PhasedReleaseCreateData: Codable {
    let type: String = "appStoreVersionPhasedReleases"
    let relationships: PhasedReleaseVersionLinkage
}

struct PhasedReleaseVersionLinkage: Codable {
    let appStoreVersion: PhasedReleaseVersionRef
}

struct PhasedReleaseVersionRef: Codable {
    let data: PhasedReleaseVersionRefData
}

struct PhasedReleaseVersionRefData: Codable {
    let type: String = "appStoreVersions"
    let id: String
}

/// PATCH body: state transitions only (ACTIVE = start/resume,
/// PAUSED = pause, COMPLETE = finish).
struct PhasedReleaseUpdateRequest: Codable {
    let data: PhasedReleaseUpdateData
}

struct PhasedReleaseUpdateData: Codable {
    let type: String = "appStoreVersionPhasedReleases"
    let id: String
    let attributes: PhasedReleaseUpdateAttributes
}

struct PhasedReleaseUpdateAttributes: Codable {
    let phasedReleaseState: String
}

/// Actors (type "actors") — verified against a recorded
/// GET /v1/reviewSubmissions/{id}?include=submittedByActor response:
/// attributes apiKeyId/actorType/userEmail/userFirstName/userLastName
/// (all null for APPLE actors).
@ResourceWrapper(type: "actors")
struct ActorModel: Equatable {
    static func == (lhs: ActorModel, rhs: ActorModel) -> Bool {
        return lhs.id == rhs.id
    }

    var id: String

    @ResourceAttribute var actorType: String?
    @ResourceAttribute var apiKeyId: String?
    @ResourceAttribute var userEmail: String?
    @ResourceAttribute var userFirstName: String?
    @ResourceAttribute var userLastName: String?

    /// "First Last"; falls back to email, then "Unknown" (names are
    /// null for APPLE and API-key actors), so PII only shows when no
    /// name exists. Mirrors BetaTesterModel.displayName.
    var displayName: String {
        let first = userFirstName ?? ""
        let last = userLastName ?? ""
        let full = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? (userEmail ?? "Unknown") : full
    }
}
