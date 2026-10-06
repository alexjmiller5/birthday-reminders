import SwiftUI

@main
struct BirthdaysApp: App {
  @State private var model = BirthdayModel()
  @Environment(\.scenePhase) private var scenePhase
  var body: some Scene {
    WindowGroup {
      BirthdayListView(model: model)
        .tint(Color(red: 0.38, green: 0.28, blue: 0.70))
        .task { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
          if phase == .active { Task { await model.refresh() } }
        }
    }
  }
}
