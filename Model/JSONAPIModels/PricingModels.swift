import Foundation

// Sparse JSON:API projections verified against Apple's OpenAPI 4.5.1.
struct PricingResource: Decodable, Equatable, Identifiable {
    let type: String
    let id: String
    var attributes: Attributes?
    let relationships: [String: Relationship]?

    struct Attributes: Codable, Equatable {
        var currency: String?
        var customerPrice: String?
        var proceeds: String?
        var manual: Bool?
        var startDate: String?
        var endDate: String?
        var availableInNewTerritories: Bool?
        var available: Bool?
        var releaseDate: String?
        var preOrderEnabled: Bool?
        var preOrderPublishDate: String?
        var contentStatuses: [String]?
    }
    struct Relationship: Decodable, Equatable {
        let data: Reference?
        private enum CodingKeys: CodingKey { case data }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Only to-one relationships are consumed. Other relationships
            // may be links-only or arrays, and need no projection here.
            data = try? container.decode(Reference.self, forKey: .data)
        }
    }
    struct Reference: Codable, Equatable { let type: String; let id: String }

    func relatedID(_ name: String, type: String) -> String? {
        guard let reference = relationships?[name]?.data, reference.type == type else { return nil }
        return reference.id
    }
}

struct PricingDocument<Payload: Decodable>: Decodable {
    let data: Payload?
    let included: [PricingResource]?
    let meta: Meta?
    let links: Links?
    struct Meta: Decodable {
        let paging: Paging?
        struct Paging: Decodable { let nextCursor: String?; let total: Int? }
    }
    struct Links: Decodable { let next: String? }
    var nextCursor: String? {
        meta?.paging?.nextCursor ?? links?.next.flatMap { URLComponents(string: $0) }?
            .queryItems?.first(where: { $0.name == "cursor" })?.value
    }
    var includedByID: [String: PricingResource] {
        Dictionary((included ?? []).map { ("\($0.type):\($0.id)", $0) }, uniquingKeysWith: { first, _ in first })
    }
}

struct AppPriceRow: Identifiable, Equatable {
    let id: String
    let territoryID: String?
    let currency: String?
    let pointID: String?
    let customerPrice: String?
    let proceeds: String?
    let startDate: String?
    let endDate: String?

    init(_ resource: PricingResource, included: [String: PricingResource]) {
        id = resource.id
        territoryID = resource.relatedID("territory", type: "territories")
        pointID = resource.relatedID("appPricePoint", type: "appPricePoints")
        let point = pointID.flatMap { included["appPricePoints:\($0)"] }
        customerPrice = point?.attributes?.customerPrice
        proceeds = point?.attributes?.proceeds
        currency = territoryID.flatMap { included["territories:\($0)"]?.attributes?.currency }
        startDate = resource.attributes?.startDate
        endDate = resource.attributes?.endDate
    }
    var territory: String { PricingDisplay.territory(territoryID) }
    var price: String { PricingDisplay.price(customerPrice, currency: currency) }
    var developerProceeds: String { PricingDisplay.price(proceeds, currency: currency) }
    func phase(on day: String) -> String {
        if let endDate, endDate <= day { return "Past" }
        if let startDate, startDate > day { return "Scheduled" }
        return "Current"
    }
}

enum PricingDisplay {
    static func territory(_ id: String?) -> String {
        guard let id else { return "Unknown territory" }
        guard let name = Locale.current.localizedString(forRegionCode: id), name != id else { return id }
        return "\(name) (\(id))"
    }
    static func price(_ value: String?, currency: String?) -> String {
        guard let value else { return "Unavailable" }
        return [currency, value].compactMap { $0 }.joined(separator: " ")
    }
    static func validAmount(_ value: String?) -> Bool {
        guard let value, value.range(of: "^[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) != nil,
              let amount = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else { return false }
        return !amount.isNaN && amount >= 0
    }
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static func validDay(_ day: String) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return day.count == 10 && formatter.date(from: day).map { self.day($0) == day } == true
    }
}

struct PriceScheduleChangeRequest: Encodable {
    let data: Schedule
    let included: [Price]
    struct Link: Encodable { let data: PricingResource.Reference }
    struct ManyLink: Encodable { let data: [PricingResource.Reference] }
    struct Schedule: Encodable {
        let type = "appPriceSchedules"
        let relationships: Relationships
        struct Relationships: Encodable {
            let app: Link
            let baseTerritory: Link
            let manualPrices: ManyLink
        }
    }
    struct Price: Encodable {
        let type = "appPrices"
        let id: String
        let attributes: Attributes
        let relationships: Relationships
        struct Attributes: Encodable {
            let startDate: String?
            let endDate: String?
            enum CodingKeys: CodingKey { case startDate, endDate }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                if let startDate { try container.encode(startDate, forKey: .startDate) }
                else { try container.encodeNil(forKey: .startDate) }
                if let endDate { try container.encode(endDate, forKey: .endDate) }
                else { try container.encodeNil(forKey: .endDate) }
            }
        }
        struct Relationships: Encodable { let appPricePoint: Link }
    }

    static func make(appID: String, baseTerritory: String, prices: [AppPriceRow],
                     newPointID: String, startDate: String, today: String) throws -> Self {
        guard PricingDisplay.validDay(startDate), startDate > today, !newPointID.isEmpty,
              let current = editableBasePrice(prices, baseTerritory: baseTerritory, today: today),
              current.pointID != newPointID else { throw PricingError.invalidSchedule }
        var included: [Price] = try prices.enumerated().map { index, row in
            guard let point = row.pointID else { throw PricingError.invalidSchedule }
            return Price(id: "${existing-\(index)}",
                attributes: .init(startDate: row.startDate, endDate: row.id == current.id ? startDate : row.endDate),
                relationships: .init(appPricePoint: .init(data: .init(type: "appPricePoints", id: point))))
        }
        included.append(Price(id: "${new-price}", attributes: .init(startDate: startDate, endDate: nil),
            relationships: .init(appPricePoint: .init(data: .init(type: "appPricePoints", id: newPointID)))))
        return Self(data: Schedule(relationships: .init(
            app: .init(data: .init(type: "apps", id: appID)),
            baseTerritory: .init(data: .init(type: "territories", id: baseTerritory)),
            manualPrices: .init(data: included.map { .init(type: "appPrices", id: $0.id) }))), included: included)
    }

    /// Date boundaries are inclusive start / exclusive end. Preserve every
    /// other territory and historical entry; defer complex base schedules.
    static func editableBasePrice(_ prices: [AppPriceRow], baseTerritory: String, today: String) -> AppPriceRow? {
        guard !prices.isEmpty, prices.allSatisfy({ row in
            if let start = row.startDate, let end = row.endDate, start >= end { return false }
            return row.territoryID?.isEmpty == false && row.pointID?.isEmpty == false
                && row.startDate.map(PricingDisplay.validDay) != false
                && row.endDate.map(PricingDisplay.validDay) != false
        }) else { return nil }
        let base = prices.filter { $0.territoryID == baseTerritory }
        guard !base.contains(where: { ($0.startDate ?? "") > today }) else { return nil }
        let current = base.filter { ($0.startDate ?? "") <= today && ($0.endDate ?? "9999-12-31") > today }
        guard current.count == 1, current[0].endDate == nil else { return nil }
        return current[0]
    }
}

enum PricingError: LocalizedError {
    case invalidSchedule, changedSchedule, invalidResponse
    var errorDescription: String? {
        switch self {
        case .invalidSchedule: return "This schedule needs to be managed in App Store Connect. Refresh and check the selected price and date."
        case .changedSchedule: return "The pricing schedule changed while you were editing. Refresh and review it before trying again."
        case .invalidResponse: return "Apple returned incomplete pricing information. Refresh and try again."
        }
    }
}
