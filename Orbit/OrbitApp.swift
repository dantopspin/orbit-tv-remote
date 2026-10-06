import SwiftUI

@main
struct OrbitApp: App {
    @StateObject private var appModel = AppModel()
    @AppStorage(AppSettings.Keys.darkMode) private var darkMode = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .preferredColorScheme(darkMode ? .dark : .light)
        }
    }
}
