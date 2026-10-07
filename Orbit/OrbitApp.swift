import SwiftUI

@main
struct OrbitApp: App {
    @State private var appModel = AppModel()
    @AppStorage(AppSettings.Keys.darkMode) private var darkMode = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .preferredColorScheme(darkMode ? .dark : nil)
        }
    }
}
