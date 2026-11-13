import SwiftUI

@main
struct SpotterNotesApp: App {
    @StateObject private var model = NotesModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NotesRootView(model: model, store: model.store, sync: model.sync)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: model.activate()
            case .background: model.suspend()
            default: break
            }
        }
    }
}
