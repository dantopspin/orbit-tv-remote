import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSettings.Keys.onboardingCompleted) private var onboardingCompleted = false
    @AppStorage(AppSettings.Keys.tvSetupDeferred) private var tvSetupDeferred = true

    var body: some View {
        #if DEBUG
        if let screen = visualValidationScreen {
            VisualValidationHost(screen: screen)
        } else {
            productionContent
        }
        #else
        productionContent
        #endif
    }

    private var productionContent: some View {
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

    #if DEBUG
    private var visualValidationScreen: String? {
        let arguments = ProcessInfo.processInfo.arguments

        guard let index = arguments.firstIndex(
            of: "-orbitVisualQA"
        ),
        arguments.indices.contains(index + 1) else {
            return nil
        }

        return arguments[index + 1]
    }
    #endif
}

#if DEBUG
private struct VisualValidationHost: View {
    @Environment(AppModel.self) private var appModel

    let screen: String

    var body: some View {
        Group {
            switch screen {
            case "onboarding":
                OnboardingFlowView()

            case "no-tv":
                NoTVHomeView()

            case "discovery":
                DiscoveryView()

            case "remote":
                RemoteView()

            case "paywall":
                PremiumView()

            case "settings":
                SettingsView()

            case "keyboard":
                KeyboardSheet()

            case "pairing":
                TVPairingSheet()

            case "apps":
                AppsInputsView()

            case "devices":
                DevicesView()

            default:
                OnboardingFlowView()
            }
        }
        .task {
            seedValidationStateIfNeeded()
        }
    }

    private func seedValidationStateIfNeeded() {
        let fullCapabilities: Set<TVCapability> = [
            .directionalNavigation,
            .touchpad,
            .keyboard,
            .power,
            .volume,
            .mute,
            .inputSelection,
            .appLaunching,
            .playback
        ]

        if screen == "remote" ||
            screen == "pairing" ||
            screen == "devices" {
            let primary = TVDevice(
                id: "qa-samsung-living-room",
                name: "Living Room TV",
                platform: .samsung,
                host: "192.0.2.10",
                roomName: "Living Room",
                capabilities: fullCapabilities
            )

            let secondary = TVDevice(
                id: "qa-lg-bedroom",
                name: "Bedroom TV",
                platform: .lgWebOS,
                host: "192.0.2.11",
                roomName: "Bedroom",
                capabilities: fullCapabilities
            )

            appModel.deviceStore.addOrUpdate(primary)
            appModel.deviceStore.addOrUpdate(secondary)
            appModel.deviceStore.select(primary)
            UserDefaults.standard.set(
                primary.id,
                forKey: AppSettings.Keys.freeDeviceID
            )
            appModel.currentCapabilities = fullCapabilities
            appModel.connectionState = .connected
            appModel.lastControlError = nil
        }

        if screen == "pairing" {
            appModel.pairingRequirement = .pin(
                length: 6,
                message:
                    "Enter the code shown on your TV."
            )
            appModel.connectionState = .connecting
        }
    }
}
#endif


private struct NoTVHomeView: View {
    @State private var showDiscovery = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.orbitSurface)
                        .overlay(
                            Circle()
                                .stroke(
                                    Color.primary.opacity(0.08),
                                    lineWidth: 0.8
                                )
                        )
                        .shadow(
                            color: Color.black.opacity(0.06),
                            radius: 14,
                            x: 0,
                            y: 6
                        )

                    OrbitMark(size: 82)
                }
                .frame(
                    width: 132,
                    height: 132
                )

                VStack(spacing: 8) {
                    Text("No TV connected")
                        .font(.title2.bold())

                    Text(
                        "Set up when you’re near your TV. Orbit supports Samsung Tizen, LG webOS, and Google TV / Android TV on the same Wi-Fi."
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
                            .font(.headline)
                            .frame(
                                width: 40,
                                height: 40
                            )
                            .background(
                                Circle()
                                    .fill(
                                        Color.orbitSurface
                                    )
                            )
                            .overlay(
                                Circle()
                                    .stroke(
                                        Color.primary
                                            .opacity(0.08),
                                        lineWidth: 0.8
                                    )
                            )
                            .shadow(
                                color: Color.black
                                    .opacity(0.05),
                                radius: 6,
                                x: 0,
                                y: 3
                            )
                    }
                    .buttonStyle(
                        OrbitPressStyle(
                            cornerRadius: 20
                        )
                    )
                    .foregroundStyle(.primary)
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
