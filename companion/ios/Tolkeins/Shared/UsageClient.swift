import Foundation

enum UsageClientError: LocalizedError {
    case invalidURL
    case missingToken
    case unauthorized
    case notFound
    case server(Int)
    case network(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Enter the https address of your Worker, with no path."
        case .missingToken:
            "Enter the phone read token."
        case .unauthorized:
            "The worker rejected this token. Use the phone read token, not the write token."
        case .notFound:
            "The worker is up and has not received a snapshot yet."
        case .server(let code):
            "The worker returned status \(code)."
        case .network(let message):
            "Couldn't reach the worker. \(message)"
        case .decoding:
            "The worker returned usage the app could not read."
        }
    }
}

enum UsageClient {
    static func canonicalize(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty
        else {
            throw UsageClientError.invalidURL
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch path {
        case "", "v1", "v1/usage", "v1/snapshot", "v1/history":
            components.path = ""
        default:
            throw UsageClientError.invalidURL
        }
        components.scheme = "https"
        components.query = nil
        components.fragment = nil
        guard var text = components.string else { throw UsageClientError.invalidURL }
        if text.hasSuffix("/") { text.removeLast() }
        return text
    }

    static func fetchUsage(baseURL: String, token: String) async throws -> UsageSnapshot {
        let canonical = try canonicalize(baseURL)
        guard let url = URL(string: canonical + "/v1/usage") else { throw UsageClientError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as UsageClientError {
            throw error
        } catch {
            throw UsageClientError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw UsageClientError.decoding }
        switch http.statusCode {
        case 200..<300:
            break
        case 401:
            throw UsageClientError.unauthorized
        case 404:
            throw UsageClientError.notFound
        default:
            throw UsageClientError.server(http.statusCode)
        }
        do {
            return try SnapshotCoding.decoder().decode(UsageSnapshot.self, from: data)
        } catch {
            throw UsageClientError.decoding
        }
    }
}
