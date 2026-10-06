import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage(AppSettings.Keys.onboardingCompleted) private var onboardingCompleted = false

    var body: some View {
        Group {
            if !onboardingCompleted {
                OnboardingFlowView()
            } else if appModel.currentDevice == nil {
                DiscoveryView()
            } else {
                RemoteView()
            }
        }
        .background(Color.orbitBackground.ignoresSafeArea())
        .task {
            if onboardingCompleted, appModel.currentDevice != nil { appModel.connect() }
        }
    }
}
