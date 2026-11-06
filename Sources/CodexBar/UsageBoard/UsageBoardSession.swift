import AppKit
import CodexBarCore
import Observation

@MainActor
@Observable
final class UsageBoardSession {
    var providers: [UsageBoardProvider] = []
    var selectionID: String?
    var isRefreshing = false
    /// True while the first provider snapshot is still being built off the click path.
    var isShowingSkeleton = false
    var providerCommands: [UsageBoardCommand] = []
    var icon: @MainActor (String) -> NSImage? = { _ in nil }
    var onCommand: @MainActor (UsageBoardCommand.Action) -> Void = { _ in }
    var onSelectionChange: @MainActor (String?) -> Void = { _ in }

    var selectedProvider: UsageBoardProvider? {
        guard let selectionID else { return nil }
        return self.providers.first { $0.id == selectionID }
    }

    func select(_ id: String?) {
        guard self.selectionID != id else { return }
        self.selectionID = id
        self.onSelectionChange(id)
    }

    func selectAdjacent(_ offset: Int) {
        let ids: [String?] = [nil] + self.providers.map(\.id)
        let current = ids.firstIndex { $0 == self.selectionID } ?? 0
        let next = min(max(0, current + offset), ids.count - 1)
        self.select(ids[next])
    }

    func replaceProviders(_ providers: [UsageBoardProvider], isRefreshing: Bool) {
        let selectionStillExists = self.selectionID == nil
            || providers.contains { $0.id == self.selectionID }
        self.providers = providers
        self.isRefreshing = isRefreshing
        self.isShowingSkeleton = false
        if !selectionStillExists {
            self.selectionID = nil
            self.onSelectionChange(nil)
        }
    }
}
