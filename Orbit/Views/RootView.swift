import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
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
            if onboardingCompleted, appModel.currentDevice != nil {
                appModel.connect()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard onboardingCompleted else { return }

            switch newPhase {
            case .active:
                appModel.appDidBecomeActive()
            case .background:
                appModel.appDidEnterBackground()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}
