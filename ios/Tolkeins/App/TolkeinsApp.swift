import SwiftUI

@main
struct TolkeinsApp: App {
    @State private var model = UsageModel()

    var body: some Scene {
        WindowGroup {
            UsageListView(model: model)
                .task { await model.refresh() }
        }
    }
}
