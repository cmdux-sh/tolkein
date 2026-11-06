struct UsageBoardCommand: Identifiable {
    enum Action {
        case refresh
        case refreshProvider(String)
        case settings
        case quit
        case classicMenu
        case close
        case menu(MenuDescriptor.MenuAction)
    }

    let id: String
    let title: String
    let systemImage: String
    let action: Action
}
