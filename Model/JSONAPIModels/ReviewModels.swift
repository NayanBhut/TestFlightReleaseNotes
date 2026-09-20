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
}

typealias CustomerReviewsDocument = CompoundDocument<[CustomerReviewModel], Meta>
typealias ReviewSubmissionsDocument = CompoundDocument<[ReviewSubmissionModel], Meta>
