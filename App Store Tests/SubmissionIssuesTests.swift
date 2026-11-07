import XCTest
@testable import Shipyard

@MainActor
final class SubmissionIssuesTests: XCTestCase {
    private let app = "ui-test-app"
    private let version = "ui-test-version-primary"
    private func failure(_ body: String, status: Int = 422) -> SubmissionFailure {
        SubmissionFailure(status: status, data: Data(body.utf8))
    }
    func testSingleTopLevelPreservesAllFields() throws {
        let f = failure("{\"errors\":[\(SubmissionTestServer.error(field: "name", detail: "Apple’s exact detail."))]}")
        let issue = try XCTUnwrap(f.issues.first)
        XCTAssertEqual(issue.status, "422"); XCTAssertEqual(issue.code, "ENTITY_ERROR.ATTRIBUTE.REQUIRED")
        XCTAssertEqual(issue.title, "Validation failed"); XCTAssertEqual(issue.detail, "Apple’s exact detail.")
        XCTAssertEqual(issue.pointer, "/data/attributes/name"); XCTAssertTrue(issue.resourcePaths.isEmpty)
        XCTAssertEqual(issue.friendlyTitle, "Missing required field: Name")
    }
    func testNestedAssociatedErrorsAreFirstAndAllSolutionsAppear() {
        let f = SubmissionFailure(status: 409, data: SubmissionTestServer.nested)
        XCTAssertEqual(f.issues.count, 8)
        XCTAssertEqual(f.issues.last?.code, "STATE_ERROR.ENTITY_STATE_INVALID")
        XCTAssertTrue(f.issues.last?.hasAssociatedErrors == true)
        let solutions = f.issues.compactMap(\.solution)
        for solution in [
            "Open App Information → Age Ratings and answer the Social Media question.",
            "Complete and save the Age Rating questionnaire.",
            "Complete What’s New, description, keywords, URLs, and required localizations.",
            "Add review contact information and any required demo credentials.",
            "Select an eligible processed build for this version.",
            "Answer the build’s export-compliance questions.",
            "Refresh the version because its state may have changed, then resolve any associated validation errors."
        ] { XCTAssertTrue(solutions.contains(solution), solution) }
        let social = f.issues.first { $0.field == "socialMedia" }
        XCTAssertEqual(social?.resourcePaths, ["/v1/ageRatingDeclarations/age-1"])
        XCTAssertEqual(social?.detail, "Social media answer is required.")
    }
    func testKnownFieldPointersHaveGuidanceWithoutAssociatedMetadata() {
        for (field, solution) in [
            ("socialMedia", "Open App Information → Age Ratings and answer the Social Media question."),
            ("violenceCartoonOrFantasy", "Complete and save the Age Rating questionnaire."),
            ("description", "Complete What’s New, description, keywords, URLs, and required localizations."),
            ("contactEmail", "Add review contact information and any required demo credentials."),
            ("build", "Select an eligible processed build for this version."),
            ("usesNonExemptEncryption", "Answer the build’s export-compliance questions.")
        ] {
            let f = failure("{\"errors\":[\(SubmissionTestServer.error(field: field, detail: "Original detail"))]}")
            XCTAssertEqual(f.issues.first?.solution, solution, field)
            XCTAssertEqual(f.issues.first?.detail, "Original detail")
        }
    }

    func testRecursionPreservesFullResourcePathChain() {
        let f = failure("""
        {"errors":[{"code":"OUTER","detail":"outer","meta":{"associatedErrors":{"/v1/appStoreVersions/version-1":[{"code":"INNER","detail":"inner","meta":{"associatedErrors":{"/v1/ageRatingDeclarations/age-1":[\(SubmissionTestServer.error(field: "socialMedia", detail: "leaf"))]}}}]}}}]}
        """)
        XCTAssertEqual(f.issues.map(\.detail), ["leaf", "inner", "outer"])
        XCTAssertEqual(f.issues.first?.resourcePaths, ["/v1/appStoreVersions/version-1", "/v1/ageRatingDeclarations/age-1"])
    }
    func testMultipleMissingFieldsAndUnknownPointersRemainVisible() {
        let f = failure("{\"errors\":[\(SubmissionTestServer.error(field: "futureField", detail: "Unknown field")),\(SubmissionTestServer.error(field: "otherField", detail: "Another missing field"))]}")
        XCTAssertEqual(f.issues.count, 2)
        XCTAssertEqual(f.issues.first?.pointer, "/data/attributes/futureField")
        XCTAssertNil(f.issues.first?.solution)
        XCTAssertEqual(f.issues.last?.field, "otherField")
    }
    func testUnknownCodeNeverInventsSolutionAndPreservesUnicode() {
        let f = failure("{\"errors\":[\(SubmissionTestServer.error(code: "FUTURE.UNKNOWN", field: "encryption", detail: "Original Ω detail"))]}")
        XCTAssertNil(f.issues.first?.solution)
        XCTAssertEqual(f.issues.first?.detail, "Original Ω detail")
        XCTAssertTrue(f.technicalDetails.contains("/data/attributes/encryption"))
        XCTAssertTrue(f.technicalDetails.contains("FUTURE.UNKNOWN"))
    }
    func testDeduplicationKeepsDifferentResourcesAndRawErrors() {
        let error = SubmissionTestServer.error(field: "description", detail: "Missing")
        let f = failure("{\"errors\":[\(error),\(error),{\"code\":\"PARENT\",\"meta\":{\"associatedErrors\":{\"/v1/appStoreVersionLocalizations/a\":[\(error),\(error)],\"/v1/appStoreVersionLocalizations/b\":[\(error)]}}}]}")
        XCTAssertEqual(f.issues.count, 4)
        XCTAssertEqual(f.payload?["errors"]?.array.count, 3) // Original duplicates remain in technical data.
    }
    func testMalformedAndMissingMetaDoNotDiscardErrors() {
        for meta in ["", ",\"meta\":null", ",\"meta\":\"broken\"", ",\"meta\":[1]", ",\"meta\":{\"associatedErrors\":17}"] {
            let f = failure("{\"errors\":[{\"code\":\"UNKNOWN\",\"detail\":\"Keep me\"\(meta)}]}")
            XCTAssertEqual(f.issues.count, 1); XCTAssertEqual(f.issues[0].detail, "Keep me")
        }
    }
    func testMalformedBodyRetainedForTechnicalDetails() {
        for body in ["not JSON", "{}", "{\"errors\":[]}"] {
            let f = failure(body)
            XCTAssertFalse(f.issues.isEmpty); XCTAssertEqual(f.rawBody, body)
        }
    }
    func testHTTPStatusGuidanceAndAPIClientPreservation() throws {
        for (status, text) in [(401, "Check whether the API key was revoked and verify the Key ID, Issuer ID, and private key."),
                               (403, "The selected API key lacks permission. Submission normally requires App Manager or broader access."),
                               (409, "Refresh the version because its state may have changed, then resolve any associated validation errors.")] {
            let data = Data("{\"errors\":[{\"detail\":\"Apple original\",\"code\":\"OTHER\"}]}".utf8)
            let apiError = APIClient.apiError(statusCode: status, data: data, response: nil)
            XCTAssertEqual(apiError.statusCode, status)
            guard case .structured(let f) = apiError else { return XCTFail("Must retain structured errors") }
            XCTAssertEqual(f.issues.first?.solution, text); XCTAssertEqual(f.issues.first?.detail, "Apple original")
        }
    }
    func testStateErrorWithoutAssociatedErrorsExplainsState() {
        let f = failure("{\"errors\":[{\"code\":\"STATE_ERROR.ENTITY_STATE_INVALID\",\"detail\":\"This resource cannot be reviewed\"}]}", status: 409)
        XCTAssertTrue(f.issues[0].solution?.contains("current state does not permit") == true)
    }
    func testRateLimitSupportsSecondsHTTPDateAndMissingMalformedHeader() throws {
        let now = Date(timeIntervalSince1970: 0)
        for (header, seconds) in [("120", 120.0), ("Thu, 01 Jan 1970 00:02:00 GMT", 120), ("invalid", 60), ("-5", 60)] {
            let f = SubmissionFailure(status: 429, data: nil, retryAfter: header, now: now)
            XCTAssertEqual(f.retryNotBefore, now.addingTimeInterval(seconds)); XCTAssertEqual(f.retryAfter, header)
        }
        XCTAssertEqual(SubmissionFailure(status: 429, data: nil, now: now).retryNotBefore, now.addingTimeInterval(60))
        let response = try XCTUnwrap(HTTPURLResponse(url: URL(string: "https://example.invalid")!, statusCode: 429, httpVersion: nil, headerFields: ["retry-after": "120"]))
        guard case .structured(let f) = APIClient.apiError(statusCode: 429, data: nil, response: response) else { return XCTFail() }
        XCTAssertEqual(f.retryAfter, "120"); XCTAssertTrue(f.technicalDetails.contains("120"))
    }
    func testRetryCannotBypassRefreshAndReusesKnownDraft() async {
        let server = SubmissionTestServer(.retryReady)
        let coordinator = SubmissionCoordinator(request: { try await server.request($0) })
        let submitted = await coordinator.submit(app: app, version: version)
        XCTAssertFalse(submitted); XCTAssertNotNil(coordinator.failure)
        let count = server.methods.count
        let unsafeRetry = await coordinator.submit(app: app, version: version)
        XCTAssertFalse(unsafeRetry); XCTAssertEqual(server.methods.count, count)
        await coordinator.refresh(app: app, version: version, requiresWhatsNew: true)
        XCTAssertTrue(coordinator.validated, coordinator.validationMessage ?? "")
        XCTAssertTrue(server.methods.dropFirst(count).allSatisfy { $0.httpMethod.0 == "GET" })
        let success = await coordinator.submit(app: app, version: version)
        XCTAssertTrue(success); XCTAssertEqual(server.submissions, 1)
        XCTAssertEqual(server.methods.filter { $0.httpMethod.0 == "POST" }.count, 2)
    }
    func testRefreshFailureAndUnknownRequiredFieldKeepRetryDisabled() async {
        for mode in [SubmissionTestServer.Mode.refreshFails, .unknownPointer] {
            let server = SubmissionTestServer(mode)
            let coordinator = SubmissionCoordinator(request: { try await server.request($0) })
            _ = await coordinator.submit(app: app, version: version)
            await coordinator.refresh(app: app, version: version, requiresWhatsNew: false)
            XCTAssertFalse(coordinator.validated); XCTAssertFalse(coordinator.canRetry(at: Date()))
            let writes = server.methods.filter { $0.httpMethod.0 != "GET" }.count
            _ = await coordinator.submit(app: app, version: version)
            XCTAssertEqual(server.methods.filter { $0.httpMethod.0 != "GET" }.count, writes)
        }
    }
    func testRateLimitBlocksRefreshAndWritesUntilDeadlineAndRevalidation() async {
        var clock = Date()
        let server = SubmissionTestServer(.rateLimited)
        let coordinator = SubmissionCoordinator(request: { try await server.request($0) }, now: { clock })
        _ = await coordinator.submit(app: app, version: version)
        let count = server.methods.count
        await coordinator.refresh(app: app, version: version, requiresWhatsNew: false)
        _ = await coordinator.submit(app: app, version: version)
        XCTAssertEqual(server.methods.count, count)
        clock = Date().addingTimeInterval(121)
        XCTAssertFalse(coordinator.canRetry(at: clock)) // elapsed delay alone never arms retry
        await coordinator.refresh(app: app, version: version, requiresWhatsNew: false)
        XCTAssertTrue(coordinator.canRetry(at: clock), coordinator.validationMessage ?? "")
        let success = await coordinator.submit(app: app, version: version)
        XCTAssertTrue(success); XCTAssertEqual(server.submissions, 1)
    }
    func testRefreshRechecksBuildEligibilityAndRequiredMetadata() async {
        for missing in ["build", "metadata", "review", "ageRating", "state"] {
            let server = SubmissionTestServer(.retryReady)
            let coordinator = SubmissionCoordinator(request: { method in
                if case .get(let name, _, let path) = method {
                    if missing == "build", name == .getVersionBuilds { return Data("{\"data\":{\"attributes\":{\"processingState\":\"PROCESSING\"}}}".utf8) }
                    if missing == "metadata", path.hasSuffix("appStoreVersionLocalizations") { return Data("{\"data\":[]}".utf8) }
                    if missing == "review", path.hasSuffix("appStoreReviewDetail") { return Data("{\"data\":{\"attributes\":{}}}".utf8) }
                    if missing == "ageRating", name == .ageRatingDeclarations { return Data("{\"data\":{\"attributes\":{\"socialMedia\":null}}}".utf8) }
                    if missing == "state", name == .getAppStoreVersions, path == self.version {
                        return Data(String(decoding: SubmissionTestServer.version, as: UTF8.self).replacingOccurrences(of: "PREPARE_FOR_SUBMISSION", with: "WAITING_FOR_REVIEW").utf8)
                    }
                }
                return try await server.request(method)
            })
            _ = await coordinator.submit(app: app, version: version)
            await coordinator.refresh(app: app, version: version, requiresWhatsNew: true)
            XCTAssertFalse(coordinator.validated, missing); XCTAssertNotNil(coordinator.validationMessage)
        }
    }
    func testUncertainCreateNeverCreatesDuplicateAfterRefresh() async {
        var writes = 0
        let server = SubmissionTestServer(.retryReady)
        let coordinator = SubmissionCoordinator(request: { method in
            if case .post(name: .getReviewSubmissions, _, _, _) = method { writes += 1; throw URLError(.timedOut) }
            if case .get(name: .getAllApps, _, _) = method { return Data("{\"data\":[]}".utf8) }
            return try await server.request(method)
        })
        _ = await coordinator.submit(app: app, version: version)
        await coordinator.refresh(app: app, version: version, requiresWhatsNew: false)
        XCTAssertFalse(coordinator.validated)
        _ = await coordinator.submit(app: app, version: version)
        XCTAssertEqual(writes, 1)
    }
    func testResetDuringRefreshCannotArmAnotherApp() async {
        let server = SubmissionTestServer(.retryReady)
        let coordinator = SubmissionCoordinator(request: { try await server.request($0) })
        _ = await coordinator.submit(app: app, version: version)
        server.holdRefresh = { coordinator.reset() }
        await coordinator.refresh(app: app, version: version, requiresWhatsNew: false)
        XCTAssertFalse(coordinator.validated); XCTAssertNil(coordinator.failure)
        XCTAssertFalse(coordinator.matches(app: app, version: version))
    }
    func testTimedOutLinkIsReconciledWithoutAnotherItemOrDraft() async {
        let server = SubmissionTestServer(.retryReady)
        server.failFirst = false
        var links = 0
        let coordinator = SubmissionCoordinator(request: { method in
            if case .post(name: .reviewSubmissionItems, _, _, _) = method {
                links += 1; throw URLError(.timedOut)
            }
            return try await server.request(method)
        })
        _ = await coordinator.submit(app: app, version: version)
        await coordinator.refresh(app: app, version: version, requiresWhatsNew: false)
        XCTAssertTrue(coordinator.validated, coordinator.validationMessage ?? "")
        let success = await coordinator.submit(app: app, version: version)
        XCTAssertTrue(success); XCTAssertEqual(links, 1); XCTAssertEqual(server.submissions, 1)
    }

    func testAlreadySubmittedDraftKeepsRetryBlocked() async {
        let server = SubmissionTestServer(.retryReady)
        let coordinator = SubmissionCoordinator(request: { method in
            if case .get(name: .getReviewSubmissions, _, "draft-1") = method {
                return Data("{\"data\":{\"attributes\":{\"state\":\"WAITING_FOR_REVIEW\"}}}".utf8)
            }
            return try await server.request(method)
        })
        _ = await coordinator.submit(app: app, version: version)
        await coordinator.refresh(app: app, version: version, requiresWhatsNew: false)
        XCTAssertFalse(coordinator.canRetry(at: Date()))
        XCTAssertTrue(coordinator.validationMessage?.contains("already submitted") == true)
        let count = server.methods.count
        _ = await coordinator.submit(app: app, version: version)
        XCTAssertEqual(server.methods.count, count)
    }

    func testTopLevelMetadataPointersValidateAgainstTheirFreshResources() async {
        let server = SubmissionTestServer(.retryReady)
        server.failFirst = false
        var attempt = 0
        let coordinator = SubmissionCoordinator(request: { method in
            if case .patch(name: .getReviewSubmissions, _, _, _) = method {
                attempt += 1
                if attempt == 1 {
                    let errors = ["description", "contactEmail", "usesNonExemptEncryption"].map {
                        SubmissionTestServer.error(field: $0, detail: "Required field")
                    }.joined(separator: ",")
                    throw APIError.structured(SubmissionFailure(status: 422, data: Data("{\"errors\":[\(errors)]}".utf8)))
                }
            }
            return try await server.request(method)
        })
        _ = await coordinator.submit(app: app, version: version)
        await coordinator.refresh(app: app, version: version, requiresWhatsNew: false)
        XCTAssertTrue(coordinator.validated, coordinator.validationMessage ?? "")
    }

    func testRateLimitedRefreshPreservesOriginalSubmissionIssues() async {
        let server = SubmissionTestServer(.retryReady)
        let coordinator = SubmissionCoordinator(request: { method in
            if case .get = method {
                throw APIError.structured(SubmissionFailure(status: 429, data: nil, retryAfter: "120"))
            }
            return try await server.request(method)
        })
        _ = await coordinator.submit(app: app, version: version)
        await coordinator.refresh(app: app, version: version, requiresWhatsNew: false)
        XCTAssertEqual(coordinator.failure?.issues.first?.field, "socialMedia")
        XCTAssertEqual(coordinator.refreshFailure?.httpStatus, 429)
        XCTAssertTrue(coordinator.isCoolingDown(at: Date()))
        XCTAssertTrue(coordinator.technicalDetails.contains("Social media answer is required."))
        XCTAssertTrue(coordinator.technicalDetails.contains("Retry-After: 120"))
        XCTAssertFalse(coordinator.canRetry(at: Date()))
    }

    func testResourceReadRejectsExternalOrAmbiguousPaths() {
        for path in ["https://evil.invalid/v1/builds/a", "/v1/builds/a?token=x", "/v1/builds/../apps", "/v2/builds/a", "/v1/unknown/a", "/v1/builds/a%2Fb"] {
            XCTAssertNil(SubmissionCoordinator.resourceRead(path), path)
        }
        XCTAssertNotNil(SubmissionCoordinator.resourceRead("/v1/ageRatingDeclarations/age-1"))
        let json = SubmissionJSON.object(["a/b": .object(["~value": .bool(false)])])
        XCTAssertEqual(json.at(pointer: "/a~1b/~0value"), .bool(false))
        XCTAssertTrue(json.at(pointer: "/a~1b/~0value")?.isPresent == true)
    }
}
