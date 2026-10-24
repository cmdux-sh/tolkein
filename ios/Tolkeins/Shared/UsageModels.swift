import Foundation

struct UsageSnapshot: Codable, Equatable {
    var schemaVersion: Int
    var generatedAt: Date
    var services: [UsageService]
}

struct UsageService: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var plan: String?
    var windows: [UsageWindow]
    var pace: UsagePace?
    var credits: UsageCredits?
    var renewsOn: String?
    var price: PlanPrice?
    var source: String
    var fetchedAt: Date
    var error: UsageProblem?
}

struct UsageWindow: Codable, Equatable, Identifiable {
    var label: String
    var usedPercent: Double
    var resetsAt: Date?
    var windowMinutes: Int?

    var id: String { label }
}

struct UsagePace: Codable, Equatable {
    var primary: PaceSide?
    var secondary: PaceSide?
}

struct PaceSide: Codable, Equatable {
    var stage: String?
    var willLastToReset: Bool?
    var expectedUsedPercent: Double?
    var deltaPercent: Double?
    var summary: String?
    var etaSeconds: Double?
}

struct UsageCredits: Codable, Equatable {
    var remaining: Double
    var currencyCode: String?
}

struct PlanPrice: Codable, Equatable {
    var amount: Double
    var currency: String
    var interval: String
}

struct UsageProblem: Codable, Equatable {
    var message: String
    var kind: String
}

enum SnapshotCoding {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = parseISO8601(value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected an ISO-8601 timestamp."
                )
            }
            return date
        }
        return decoder
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatISO8601(date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

func parseISO8601(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: value) {
        return date
    }
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value)
}

func formatISO8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
}
