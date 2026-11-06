import Foundation
import Observation
import WidgetKit

@MainActor
@Observable
final class UsageModel {
    var snapshot: UsageSnapshot?
    var isLoading = false
    var statusMessage: String?
    var workerURL = ""
    var hasToken = false

    var isReady: Bool {
        !workerURL.isEmpty && hasToken
    }

    func refresh() async {
        workerURL = AppSettings.workerURL
        hasToken = ((try? SecretStore.loadToken()) ?? nil)?.isEmpty == false
        if snapshot == nil {
            snapshot = SnapshotStore.load()
        }
        guard isReady, let token = try? SecretStore.loadToken(), !token.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await UsageClient.fetchUsage(baseURL: workerURL, token: token)
            snapshot = fresh
            try? SnapshotStore.save(fresh)
            statusMessage = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch let error as UsageClientError {
            statusMessage = error.errorDescription
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func save(url: String, token: String) throws {
        let canonical = try UsageClient.canonicalize(url)
        if !token.isEmpty {
            try SecretStore.saveToken(token)
            hasToken = true
        } else if !hasToken {
            throw UsageClientError.missingToken
        }
        AppSettings.workerURL = canonical
        workerURL = canonical
        statusMessage = nil
        WidgetCenter.shared.reloadAllTimelines()
    }

    func clearToken() throws {
        try SecretStore.deleteToken()
        hasToken = false
        WidgetCenter.shared.reloadAllTimelines()
    }

    func testConnection(url: String, token: String) async -> String {
        do {
            let canonical = try UsageClient.canonicalize(url)
            let resolved = token.isEmpty ? try SecretStore.loadToken() : token
            guard let resolved, !resolved.isEmpty else { throw UsageClientError.missingToken }
            let snapshot = try await UsageClient.fetchUsage(baseURL: canonical, token: resolved)
            let count = snapshot.services.count
            let noun = count == 1 ? "service" : "services"
            return "Connected. \(count) \(noun)."
        } catch let error as UsageClientError {
            return error.errorDescription ?? "Couldn't connect."
        } catch let error as KeychainError {
            return error.errorDescription ?? "Couldn't read the saved token."
        } catch {
            return error.localizedDescription
        }
    }
}
