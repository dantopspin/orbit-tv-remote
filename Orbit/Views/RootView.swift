import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSettings.Keys.onboardingCompleted) private var onboardingCompleted = false
    @AppStorage(AppSettings.Keys.tvSetupDeferred) private var tvSetupDeferred = true

    var body: some View {
        Group {
            if !onboardingCompleted {
                OnboardingFlowView()
            } else if appModel.currentDevice == nil {
                if tvSetupDeferred {
                    NoTVHomeView()
                } else {
                    DiscoveryView()
                }
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


private struct NoTVHomeView: View {
    @State private var showDiscovery = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer()

                OrbitMark(size: 96)

                VStack(spacing: 8) {
                    Text("No TV connected")
                        .font(.title2.bold())

                    Text(
                        "Set up when you’re near your TV. Orbit works with Samsung, LG, and Google TV on the same Wi-Fi."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                }

                Button("Set Up My TV") {
                    showDiscovery = true
                }
                .buttonStyle(OrbitPrimaryButtonStyle())
                .padding(.horizontal, 28)

                Button("Settings") {
                    showSettings = true
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(minHeight: 44)

                Spacer()
            }
            .padding(.vertical, 24)
            .navigationTitle("Orbit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .topBarTrailing
                ) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showDiscovery) {
                DiscoveryView(showsCloseButton: true)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
        .background(Color.orbitBackground.ignoresSafeArea())
    }
}
