//
//  BetaModels.swift
//  App Store
//
//  Created by Nayan Bhut for Phase 4: TestFlight Groups/Testers.
//

import Foundation
import JSONAPI

@ResourceWrapper(type: "betaGroups")
struct BetaGroupModel: Equatable {
    static func == (lhs: BetaGroupModel, rhs: BetaGroupModel) -> Bool {
        return lhs.id == rhs.id
    }

    var id: String

    @ResourceAttribute var name: String?
    @ResourceAttribute var createdDate: String?
    @ResourceAttribute var isInternalGroup: Bool?
    @ResourceAttribute var hasAccessToAllBuilds: Bool?
    @ResourceAttribute var publicLinkEnabled: Bool?
    @ResourceAttribute var publicLinkId: String?
    @ResourceAttribute var publicLinkLimitEnabled: Bool?
    @ResourceAttribute var publicLinkLimit: Int?
    @ResourceAttribute var autoNotifyEnabled: Bool?
    @ResourceRelationship var betaTesters: [BetaTesterModel]
    @ResourceRelationship var builds: [BuildsModel]

    var isSelected = false
}

@ResourceWrapper(type: "betaTesters")
struct BetaTesterModel: Equatable {
    static func == (lhs: BetaTesterModel, rhs: BetaTesterModel) -> Bool {
        return lhs.id == rhs.id
    }

    var id: String

    @ResourceAttribute var firstName: String?
    @ResourceAttribute var lastName: String?
    @ResourceAttribute var email: String?
    @ResourceAttribute var inviteType: String?

    var displayName: String {
        let first = firstName ?? ""
        let last = lastName ?? ""
        let full = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? (email ?? "Unknown tester") : full
    }
}

@ResourceWrapper(type: "buildBetaDetails")
struct BuildBetaDetailModel: Equatable {
    var id: String

    @ResourceAttribute var autoNotifyEnabled: Bool?
    @ResourceAttribute var internalBuildState: String?
    @ResourceAttribute var externalBuildState: String?
}

@ResourceWrapper(type: "betaAppReviewSubmissions")
struct BetaAppReviewSubmissionModel: Equatable {
    var id: String

    @ResourceAttribute var betaReviewState: String?
    @ResourceAttribute var submittedDate: String?
}

typealias BetaGroupsDocument = CompoundDocument<[BetaGroupModel], Meta>
typealias BetaTestersDocument = CompoundDocument<[BetaTesterModel], Meta>

// MARK: - Email validation

enum EmailValidator {
    static func isValid(_ email: String) -> Bool {
        let regex = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return email.range(of: regex, options: .regularExpression) != nil
    }
}

// MARK: - Relationship linkage bodies

enum BetaRelationshipBody {
    static func linkageData(type: String, ids: [String]) -> Data? {
        let linkage = ids.map { ["type": type, "id": $0] }
        return try? JSONSerialization.data(withJSONObject: ["data": linkage], options: [])
    }

    static func testerLinkage(ids: [String]) -> Data? {
        linkageData(type: "betaTesters", ids: ids)
    }

    static func buildLinkage(ids: [String]) -> Data? {
        linkageData(type: "builds", ids: ids)
    }
}

// MARK: - Beta tester creation body

/// POST /v1/betaTesters — email (required), firstName, lastName + betaGroups/builds.
/// (`/betaTesterInvitations` has no attributes; it only re-invites existing testers.)
enum BetaTesterInvitationBody {
    static func invite(email: String,
                       firstName: String? = nil,
                       lastName: String? = nil,
                       betaGroupId: String? = nil,
                       buildIds: [String] = []) -> Data? {
        var attributes: [String: Any] = ["email": email]
        if let firstName, !firstName.isEmpty { attributes["firstName"] = firstName }
        if let lastName, !lastName.isEmpty { attributes["lastName"] = lastName }

        var relationships: [String: Any] = [:]
        if let betaGroupId {
            relationships["betaGroups"] = ["data": [["type": "betaGroups", "id": betaGroupId]]]
        }
        if !buildIds.isEmpty {
            relationships["builds"] = ["data": buildIds.map { ["type": "builds", "id": $0] }]
        }

        var resource: [String: Any] = [
            "type": "betaTesters",
            "attributes": attributes
        ]
        if !relationships.isEmpty {
            resource["relationships"] = relationships
        }
        return try? JSONSerialization.data(withJSONObject: ["data": resource], options: [])
    }
}

// MARK: - Beta review submission body

/// POST /v1/betaAppReviewSubmissions with build linkage.
enum BetaReviewSubmissionBody {
    static func submit(buildId: String) -> Data? {
        let body: [String: Any] = [
            "data": [
                "type": "betaAppReviewSubmissions",
                "relationships": [
                    "build": ["data": ["type": "builds", "id": buildId]]
                ]
            ]
        ]
        return try? JSONSerialization.data(withJSONObject: body, options: [])
    }
}
