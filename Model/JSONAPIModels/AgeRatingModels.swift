import Foundation

/// Verified against Apple's OpenAPI 4.5.1. Missing answers stay missing;
/// `clear` is used only for an explicit removal in a sparse PATCH.
enum AgeRatingAnswer: Equatable, Encodable, Sendable {
    case bool(Bool)
    case text(String)
    case clear

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value): try container.encode(value)
        case .text(let value): try container.encode(value)
        case .clear: try container.encodeNil()
        }
    }

    var selection: String {
        switch self {
        case .bool(let value): return value ? "true" : "false"
        case .text(let value): return value
        case .clear: return ""
        }
    }
}

struct AgeRatingQuestion: Identifiable, Sendable {
    enum Group: String, CaseIterable, Sendable {
        case controls = "In-app controls and capabilities"
        case content = "Content and themes"
        case medical = "Medical and wellness"
        case violence = "Violence"
        case sexual = "Sexual content and nudity"
        case chance = "Chance-based activities"
        case additional = "Additional information"
    }

    enum Kind: Sendable {
        case boolean
        case frequency
        case choice([(value: String, title: String)])
        case text
        case url
    }

    let id: String
    let title: String
    let group: Group
    let kind: Kind
    private let read: @Sendable (AgeRatingDeclarationModel) -> AgeRatingAnswer?

    private static func boolean(_ id: String, _ title: String, _ group: Group,
                                _ value: @escaping @Sendable (AgeRatingDeclarationModel) -> Bool?) -> Self {
        Self(id: id, title: title, group: group, kind: .boolean,
             read: { value($0).map(AgeRatingAnswer.bool) })
    }

    private static func string(_ id: String, _ title: String, _ group: Group,
                               _ value: @escaping @Sendable (AgeRatingDeclarationModel) -> String?,
                               kind: Kind = .frequency) -> Self {
        Self(id: id, title: title, group: group, kind: kind, read: { model in
            value(model).map { value in
                // Display legacy frequency answers using Apple's current terms.
                // The baseline uses the same mapping, so this never creates an edit.
                if case .frequency = kind {
                    switch value {
                    case "INFREQUENT_OR_MILD": return .text("INFREQUENT")
                    case "FREQUENT_OR_INTENSE": return .text("FREQUENT")
                    default: break
                    }
                }
                return .text(value)
            }
        })
    }

    static let all: [Self] = [
        .boolean("parentalControls", "Parental controls", .controls, { $0.parentalControls }),
        .boolean("ageAssurance", "Age assurance", .controls, { $0.ageAssurance }),
        .boolean("unrestrictedWebAccess", "Unrestricted web access", .controls, { $0.unrestrictedWebAccess }),
        .boolean("userGeneratedContent", "User-generated content", .controls, { $0.userGeneratedContent }),
        .boolean("messagingAndChat", "Messaging and chat", .controls, { $0.messagingAndChat }),
        .boolean("advertising", "Advertising", .controls, { $0.advertising }),
        .boolean("socialMedia", "Social media", .controls, { $0.socialMedia }),
        .boolean("socialMediaAgeRestricted", "Age-restricted social media", .controls, { $0.socialMediaAgeRestricted }),
        .string("profanityOrCrudeHumor", "Profanity or crude humor", .content, { $0.profanityOrCrudeHumor }),
        .string("horrorOrFearThemes", "Horror or fear themes", .content, { $0.horrorOrFearThemes }),
        .string("matureOrSuggestiveThemes", "Mature or suggestive themes", .content, { $0.matureOrSuggestiveThemes }),
        .string("alcoholTobaccoOrDrugUseOrReferences", "Alcohol, tobacco, or drug use or references", .content, { $0.alcoholTobaccoOrDrugUseOrReferences }),
        .string("medicalOrTreatmentInformation", "Medical or treatment information", .medical, { $0.medicalOrTreatmentInformation }),
        .boolean("healthOrWellnessTopics", "Health or wellness topics", .medical, { $0.healthOrWellnessTopics }),
        .string("violenceCartoonOrFantasy", "Cartoon or fantasy violence", .violence, { $0.violenceCartoonOrFantasy }),
        .string("violenceRealistic", "Realistic violence", .violence, { $0.violenceRealistic }),
        .string("violenceRealisticProlongedGraphicOrSadistic", "Prolonged graphic or sadistic realistic violence", .violence, { $0.violenceRealisticProlongedGraphicOrSadistic }),
        .string("gunsOrOtherWeapons", "Guns or other weapons", .violence, { $0.gunsOrOtherWeapons }),
        .string("sexualContentOrNudity", "Sexual content or nudity", .sexual, { $0.sexualContentOrNudity }),
        .string("sexualContentGraphicAndNudity", "Graphic sexual content and nudity", .sexual, { $0.sexualContentGraphicAndNudity }),
        .string("gamblingSimulated", "Simulated gambling", .chance, { $0.gamblingSimulated }),
        .string("contests", "Contests", .chance, { $0.contests }),
        .boolean("gambling", "Gambling", .chance, { $0.gambling }),
        .boolean("lootBox", "Loot boxes", .chance, { $0.lootBox }),
        .string("kidsAgeBand", "Made for Kids age range", .additional, { $0.kidsAgeBand },
                kind: .choice([("FIVE_AND_UNDER", "5 and under"), ("SIX_TO_EIGHT", "6–8"), ("NINE_TO_ELEVEN", "9–11")])),
        .string("ageRatingOverrideV2", "Higher age-rating override", .additional, { $0.ageRatingOverrideV2 },
                kind: .choice([("NONE", "No override"), ("NINE_PLUS", "9+"), ("THIRTEEN_PLUS", "13+"), ("SIXTEEN_PLUS", "16+"), ("EIGHTEEN_PLUS", "18+"), ("UNRATED", "Unrated")])),
        .string("developerAgeRatingInfoUrl", "Age-rating information URL", .additional, { $0.developerAgeRatingInfoUrl }, kind: .url),
        .string("koreaAgeRatingOverride", "Republic of Korea rating override", .additional, { $0.koreaAgeRatingOverride },
                kind: .choice([("NONE", "No override"), ("ALL", "All ages"), ("TWELVE_PLUS", "12+"), ("FIFTEEN_PLUS", "15+"), ("NINETEEN_PLUS", "19+")])),
        .string("gracRatingClassificationNumber", "GRAC Rating Classification Number", .additional, { $0.gracRatingClassificationNumber }, kind: .text)
    ]

    static func answers(from model: AgeRatingDeclarationModel) -> [String: AgeRatingAnswer] {
        Dictionary(uniqueKeysWithValues: all.compactMap { question in
            question.read(model).map { (question.id, $0) }
        })
    }
}

struct AgeRatingDraft {
    private(set) var baseline: [String: AgeRatingAnswer]
    var answers: [String: AgeRatingAnswer]

    init(_ declaration: AgeRatingDeclarationModel) {
        baseline = AgeRatingQuestion.answers(from: declaration)
        answers = baseline
    }

    var changes: [String: AgeRatingAnswer] {
        Dictionary(uniqueKeysWithValues: AgeRatingQuestion.all.compactMap { question in
            let answer = answers[question.id]
            guard answer != baseline[question.id] else { return nil }
            return (question.id, answer ?? .clear)
        })
    }

    /// Rebase local edits on a confirmed GET. This also reconciles a PATCH
    /// whose response was lost: already-saved edits stop being dirty.
    mutating func reconcile(_ declaration: AgeRatingDeclarationModel) {
        let edits = changes
        baseline = AgeRatingQuestion.answers(from: declaration)
        answers = baseline
        for (key, value) in edits {
            if value == .clear { answers.removeValue(forKey: key) }
            else { answers[key] = value }
        }
    }

    func validationMessage(wasMadeForKids: Bool) -> String? {
        Self.validationMessage(changes: changes, savedAnswers: baseline, wasMadeForKids: wasMadeForKids)
    }

    static func validationMessage(changes: [String: AgeRatingAnswer], savedAnswers: [String: AgeRatingAnswer],
                                  wasMadeForKids: Bool) -> String? {
        for (key, answer) in changes {
            guard let question = AgeRatingQuestion.all.first(where: { $0.id == key }) else {
                return "This age-rating question is not supported. Reload saved answers."
            }
            let valid: Bool
            switch (question.kind, answer) {
            case (.boolean, .bool): valid = true
            case (.frequency, .text(let value)): valid = ["NONE", "INFREQUENT", "FREQUENT"].contains(value)
            case (.choice(let options), .text(let value)): valid = options.contains { $0.value == value }
            case (.choice, .clear): valid = key == "kidsAgeBand" && !wasMadeForKids
            case (.text, .text), (.url, .text), (.text, .clear), (.url, .clear): valid = true
            default: valid = false
            }
            guard valid else { return "Choose a valid answer for \(question.title)." }
            if key == "developerAgeRatingInfoUrl", case .text(let value) = answer {
                guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      url.host?.isEmpty == false else { return "Enter a valid http(s) age-rating information URL." }
            }
        }
        if changes["koreaAgeRatingOverride"] != nil || changes["gracRatingClassificationNumber"] != nil {
            var effective = savedAnswers
            for (key, value) in changes { effective[key] = value == .clear ? nil : value }
            let override = effective["koreaAgeRatingOverride"]?.selection ?? "NONE"
            let number = effective["gracRatingClassificationNumber"]?.selection.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if (override != "NONE") != !number.isEmpty {
                return "Provide the Republic of Korea rating and its GRAC classification number together, or clear both."
            }
        }
        return nil
    }
}

struct AgeRatingUpdateRequest: Encodable {
    struct Body: Encodable {
        let type = "ageRatingDeclarations"
        let id: String
        let attributes: [String: AgeRatingAnswer]
    }
    let data: Body

    init(id: String, changes: [String: AgeRatingAnswer]) {
        data = Body(id: id, attributes: changes)
    }
}

enum AgeRatingEditingSupport {
    static func isEditable(_ info: AppInfoModel) -> Bool {
        ["PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "DEVELOPER_REJECTED", "REJECTED"].contains(info.state ?? "")
    }

    static func preferredInfo(in infos: [AppInfoModel]) -> AppInfoModel? {
        // Never take an arbitrary live record ahead of a pending editable one.
        infos.first(where: { $0.state == "PREPARE_FOR_SUBMISSION" })
            ?? infos.first(where: isEditable)
            ?? infos.first(where: { ["IN_REVIEW", "WAITING_FOR_REVIEW", "PENDING_RELEASE"].contains($0.state ?? "") })
            ?? infos.first(where: { ["ACCEPTED", "READY_FOR_DISTRIBUTION"].contains($0.state ?? "") })
    }
}
