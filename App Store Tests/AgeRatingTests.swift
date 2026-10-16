import XCTest
@testable import Shipyard

final class AgeRatingTests: XCTestCase {
    private let response = Data(#"{"data":{"type":"ageRatingDeclarations","id":"rating-1","attributes":{"parentalControls":true,"advertising":false,"ageAssurance":true,"healthOrWellnessTopics":true,"socialMedia":false,"socialMediaAgeRestricted":false,"kidsAgeBand":"SIX_TO_EIGHT","ageRatingOverrideV2":"THIRTEEN_PLUS","koreaAgeRatingOverride":"NONE","developerAgeRatingInfoUrl":"https://example.com/ratings","profanityOrCrudeHumor":"INFREQUENT_OR_MILD"}}}"#.utf8)

    private func declaration() throws -> AgeRatingDeclarationModel {
        try getDecoder().decode(AgeRatingDeclarationModel.self, from: response)
    }

    func testModernAnswersAndLegacyFrequencyDecodeWithoutCreatingEdits() throws {
        let saved = try declaration()
        XCTAssertEqual(saved.parentalControls, true)
        XCTAssertEqual(saved.advertising, false)
        XCTAssertEqual(saved.ageAssurance, true)
        XCTAssertEqual(saved.healthOrWellnessTopics, true)
        XCTAssertEqual(saved.socialMediaAgeRestricted, false)
        XCTAssertEqual(saved.kidsAgeBand, "SIX_TO_EIGHT")
        XCTAssertNil(saved.gambling)
        let draft = AgeRatingDraft(saved)
        XCTAssertEqual(draft.answers["profanityOrCrudeHumor"], .text("INFREQUENT"))
        XCTAssertNil(draft.answers["gambling"])
        XCTAssertTrue(draft.changes.isEmpty)
    }

    func testPatchOmitsUntouchedAnswersAndEncodesFalseAsBoolean() throws {
        var draft = AgeRatingDraft(try declaration())
        draft.answers["parentalControls"] = .bool(false)
        let encoded = try JSONEncoder().encode(AgeRatingUpdateRequest(id: "rating-1", changes: draft.changes))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let data = try XCTUnwrap(json["data"] as? [String: Any])
        let attributes = try XCTUnwrap(data["attributes"] as? [String: Any])
        XCTAssertEqual(data["type"] as? String, "ageRatingDeclarations")
        XCTAssertEqual(data["id"] as? String, "rating-1")
        XCTAssertEqual(Set(attributes.keys), ["parentalControls"])
        XCTAssertEqual(attributes["parentalControls"] as? Bool, false)
        XCTAssertNil(attributes["gambling"])
        XCTAssertNil(attributes["ageRatingOverride"])
    }

    func testExplicitRemovalEncodesNull() throws {
        var draft = AgeRatingDraft(try declaration())
        draft.answers.removeValue(forKey: "developerAgeRatingInfoUrl")
        let encoded = try JSONEncoder().encode(AgeRatingUpdateRequest(id: "rating-1", changes: draft.changes))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let data = try XCTUnwrap(json["data"] as? [String: Any])
        let attributes = try XCTUnwrap(data["attributes"] as? [String: Any])
        XCTAssertTrue(attributes["developerAgeRatingInfoUrl"] is NSNull)
        XCTAssertEqual(attributes.count, 1)
    }

    func testReconcileKeepsUnsavedEditsAndAcceptsOtherServerChanges() throws {
        let saved = try declaration()
        var draft = AgeRatingDraft(saved)
        draft.answers["parentalControls"] = .bool(false)
        var refreshed = saved
        refreshed.advertising = true
        draft.reconcile(refreshed)
        XCTAssertEqual(draft.answers["advertising"], .bool(true))
        XCTAssertEqual(draft.changes, ["parentalControls": .bool(false)])
        refreshed.parentalControls = false
        draft.reconcile(refreshed)
        XCTAssertTrue(draft.changes.isEmpty, "A committed PATCH with a lost response must not be sent again.")
    }

    func testFutureEnumIsPreservedUntilTheUserChangesIt() throws {
        var saved = try declaration()
        saved.ageRatingOverrideV2 = "FUTURE_RATING"
        var draft = AgeRatingDraft(saved)
        draft.answers["advertising"] = .bool(true)
        XCTAssertNil(draft.changes["ageRatingOverrideV2"])
        XCTAssertNil(draft.validationMessage(wasMadeForKids: false))
    }

    func testValidationRejectsInvalidFrequencyURLAndRemovingApprovedKidsCategory() throws {
        let saved = try declaration()
        var draft = AgeRatingDraft(saved)
        draft.answers["contests"] = .text("SOMETIMES")
        XCTAssertNotNil(draft.validationMessage(wasMadeForKids: false))
        draft = AgeRatingDraft(saved)
        draft.answers["developerAgeRatingInfoUrl"] = .text("file:///tmp/ratings")
        XCTAssertNotNil(draft.validationMessage(wasMadeForKids: false))
        draft = AgeRatingDraft(saved)
        draft.answers.removeValue(forKey: "kidsAgeBand")
        XCTAssertNotNil(draft.validationMessage(wasMadeForKids: true))
        XCTAssertNil(draft.validationMessage(wasMadeForKids: false))
    }

    func testKoreaOverrideRequiresItsClassificationNumber() throws {
        var draft = AgeRatingDraft(try declaration())
        draft.answers["koreaAgeRatingOverride"] = .text("FIFTEEN_PLUS")
        XCTAssertNotNil(draft.validationMessage(wasMadeForKids: false))
        draft.answers["gracRatingClassificationNumber"] = .text("TEST-RCN")
        XCTAssertNil(draft.validationMessage(wasMadeForKids: false))
    }

    func testEditableAppInfoIsChosenAheadOfLiveAndHistoricalRecords() {
        var live = AppInfoModel(id: "live", appInfoLocalizations: [])
        live.state = "ACCEPTED"
        var pending = AppInfoModel(id: "pending", appInfoLocalizations: [])
        pending.state = "PREPARE_FOR_SUBMISSION"
        XCTAssertEqual(AgeRatingEditingSupport.preferredInfo(in: [live, pending])?.id, "pending")
        for state in ["ACCEPTED", "IN_REVIEW", "WAITING_FOR_REVIEW", "PENDING_RELEASE", "REPLACED_WITH_NEW_INFO", "FUTURE_STATE"] {
            live.state = state
            XCTAssertFalse(AgeRatingEditingSupport.isEditable(live), state)
        }
    }

    func testEndpointPathsMatchAppleRelatedReadAndPatchRoutes() {
        XCTAssertEqual(APIName.appInfos.rawValue + APIMethod.get(name: .appInfos, path: "info-1/ageRatingDeclaration").apiPath,
                       "/appInfos/info-1/ageRatingDeclaration")
        let patch = APIMethod.patch(name: .ageRatingDeclarations, body: Data(), path: "rating-1")
        XCTAssertEqual(APIName.ageRatingDeclarations.rawValue + patch.apiPath, "/ageRatingDeclarations/rating-1")
        XCTAssertEqual(patch.httpMethod.0, "PATCH")
    }

    @MainActor private func viewModel() throws -> DetailViewModel {
        let vm = DetailViewModel(sidebarViewModel: SideBarViewModel(), readsStoredTeam: false)
        var info = AppInfoModel(id: "info-1", appInfoLocalizations: [])
        info.state = "PREPARE_FOR_SUBMISSION"
        info.ageRatingDeclaration = try declaration()
        vm.configureForScreenshotSample(app: AppsData(id: "app-1", appStoreVersions: []), versions: [],
            selectedVersion: PreReleaseVersionsModel(id: "version-1"), builds: [],
            appInfo: [info], versionLocalizations: [])
        return vm
    }

    @MainActor func testSaveUpdatesTheMatchingDeclaration() async throws {
        let vm = try viewModel()
        var sent: APIMethod?
        let updatedResponse = Data(String(decoding: response, as: UTF8.self)
            .replacingOccurrences(of: "\"advertising\":false", with: "\"advertising\":true").utf8)
        vm.ageRatingAPI = AgeRatingAPI { method in sent = method; return updatedResponse }
        let result = await vm.saveAgeRating(appId: "app-1", infoId: "info-1", declarationId: "rating-1",
            generation: vm.ageRatingContextGeneration, changes: ["advertising": .bool(true)])
        guard case .success = result else { return XCTFail("Expected confirmed save") }
        XCTAssertEqual(sent?.httpMethod.0, "PATCH")
        XCTAssertEqual(vm.appInfoState.loadedValue?.first?.ageRatingDeclaration?.advertising, true)
        XCTAssertTrue(vm.busyAgeRatingDeclarationIds.isEmpty)
    }

    @MainActor func testPermissionFailureKeepsSavedAnswersAndNamesRequiredAccess() async throws {
        let vm = try viewModel()
        vm.ageRatingAPI = AgeRatingAPI { _ in throw APIError.httpError(statusCode: 403) }
        let result = await vm.saveAgeRating(appId: "app-1", infoId: "info-1", declarationId: "rating-1",
            generation: vm.ageRatingContextGeneration, changes: ["advertising": .bool(true)])
        guard case .failure(let message, let needsReload) = result else { return XCTFail("Expected permission failure") }
        XCTAssertTrue(message.contains("broader permissions"))
        XCTAssertFalse(needsReload)
        XCTAssertEqual(vm.appInfoState.loadedValue?.first?.ageRatingDeclaration?.advertising, false)
    }

    @MainActor func testUncertainSaveRequiresReloadAndFailedReloadDoesNotReplaceAnswers() async throws {
        let vm = try viewModel()
        vm.ageRatingAPI = AgeRatingAPI { _ in throw URLError(.networkConnectionLost) }
        let result = await vm.saveAgeRating(appId: "app-1", infoId: "info-1", declarationId: "rating-1",
            generation: vm.ageRatingContextGeneration, changes: ["advertising": .bool(true)])
        guard case .failure(_, let needsReload) = result else { return XCTFail("Expected uncertain outcome") }
        XCTAssertTrue(needsReload)
        let reload = await vm.reloadAgeRating(appId: "app-1", infoId: "info-1", declarationId: "rating-1",
            generation: vm.ageRatingContextGeneration)
        guard case .failure = reload else { return XCTFail("Expected failed reload") }
        XCTAssertEqual(vm.appInfoState.loadedValue?.first?.ageRatingDeclaration?.advertising, false)
    }

    @MainActor func testLateSaveCannotUpdateAppAfterSwitchingAwayAndBack() async throws {
        let vm = try viewModel()
        let generation = vm.ageRatingContextGeneration
        let started = expectation(description: "Request started")
        var continuation: CheckedContinuation<Data, Error>?
        vm.ageRatingAPI = AgeRatingAPI { _ in
            try await withCheckedThrowingContinuation {
                continuation = $0
                started.fulfill()
            }
        }
        let task = Task {
            await vm.saveAgeRating(appId: "app-1", infoId: "info-1", declarationId: "rating-1",
                generation: generation, changes: ["advertising": .bool(true)])
        }
        await fulfillment(of: [started], timeout: 2)
        vm.activateAppForDetail(AppsData(id: "app-2", appStoreVersions: []))
        vm.activateAppForDetail(AppsData(id: "app-1", appStoreVersions: []))
        continuation?.resume(returning: response)
        let result = await task.value
        guard case .ignored = result else { return XCTFail("Expected stale save to be ignored") }
        XCTAssertEqual(vm.appInfoState, .idle)
        XCTAssertTrue(vm.busyAgeRatingDeclarationIds.isEmpty)
    }
}
