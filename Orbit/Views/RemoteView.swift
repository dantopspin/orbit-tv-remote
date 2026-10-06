import SwiftUI
import UIKit

struct DPadView: View {
    let onCommand: (RemoteCommand) -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size * 0.34

            ZStack {
                Circle()
                    .fill(Color.orbitSurface)
                    .overlay(Circle().stroke(Color.orbitSeparator, lineWidth: 0.5))

                DirectionButton(systemName: "chevron.up", command: .up, onCommand: onCommand)
                    .offset(y: -radius)
                DirectionButton(systemName: "chevron.down", command: .down, onCommand: onCommand)
                    .offset(y: radius)
                DirectionButton(systemName: "chevron.left", command: .left, onCommand: onCommand)
                    .offset(x: -radius)
                DirectionButton(systemName: "chevron.right", command: .right, onCommand: onCommand)
                    .offset(x: radius)

                Button {
                    onCommand(.select)
                } label: {
                    Text("OK")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: size * 0.32, height: size * 0.32)
                        .background(Circle().fill(Color(uiColor: .systemBackground)))
                        .overlay(Circle().stroke(Color.orbitSeparator, lineWidth: 0.6))
                }
                .buttonStyle(OrbitPressStyle(cornerRadius: size))
                .accessibilityLabel("OK")
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct DirectionButton: View {
    let systemName: String
    let command: RemoteCommand
    let onCommand: (RemoteCommand) -> Void

    private var accessibilityName: String {
        switch command {
        case .up: return "Up"
        case .down: return "Down"
        case .left: return "Left"
        case .right: return "Right"
        default: return "Direction"
        }
    }

    var body: some View {
        Button {
            onCommand(command)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(OrbitPressStyle(cornerRadius: 28))
        .foregroundStyle(.primary)
        .accessibilityLabel(accessibilityName)
    }
}

struct RoundRemoteButton: View {
    let systemName: String
    var label: String? = nil
    var destructivePower = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .semibold))

                if let label {
                    Text(label)
                        .font(.caption2)
                }
            }
            .foregroundStyle(destructivePower ? Color.white : Color.primary)
            .frame(width: 58, height: 58)
            .background(Circle().fill(destructivePower ? Color.orbitPower : Color.orbitSurface))
            .overlay(
                Circle().stroke(
                    destructivePower ? Color.clear : Color.orbitSeparator,
                    lineWidth: 0.5
                )
            )
        }
        .buttonStyle(OrbitPressStyle(cornerRadius: 29))
        .accessibilityLabel(label ?? (destructivePower ? "Power" : "Remote control"))
    }
}

struct VolumePill: View {
    let onCommand: (RemoteCommand) -> Void

    var body: some View {
        HStack(spacing: 0) {
            SegmentButton(systemName: "minus", accessibilityLabel: "Volume Down", action: { onCommand(.volumeDown) })
            SegmentButton(systemName: "speaker.slash.fill", accessibilityLabel: "Mute", action: { onCommand(.mute) })
            SegmentButton(systemName: "plus", accessibilityLabel: "Volume Up", action: { onCommand(.volumeUp) })
        }
        .frame(height: 54)
        .background(Capsule().fill(Color.orbitSurface))
        .overlay(Capsule().stroke(Color.orbitSeparator, lineWidth: 0.5))
    }
}

private struct SegmentButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(OrbitPressStyle(cornerRadius: 24))
        .foregroundStyle(.primary)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct PlaybackRow: View {
    let onCommand: (RemoteCommand) -> Void

    var body: some View {
        HStack(spacing: 10) {
            mini("backward.fill", "Rewind", .rewind)
            mini("play.fill", "Play", .play)
            mini("pause.fill", "Pause", .pause)
            mini("forward.fill", "Fast Forward", .fastForward)
        }
    }

    private func mini(_ icon: String, _ accessibilityLabel: String, _ command: RemoteCommand) -> some View {
        Button {
            onCommand(command)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Capsule().fill(Color.orbitSurface))
                .overlay(Capsule().stroke(Color.orbitSeparator, lineWidth: 0.5))
        }
        .buttonStyle(OrbitPressStyle(cornerRadius: 23))
        .foregroundStyle(.primary)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct TouchpadView: View {
    let onCommand: (RemoteCommand) -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .fill(Color.orbitSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(Color.orbitSeparator, lineWidth: 0.5)
            )
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "hand.draw")
                        .font(.system(size: 28, weight: .light))
                    Text("Swipe to navigate")
                        .font(.subheadline.weight(.medium))
                    Text("Tap to select")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .onTapGesture {
                onCommand(.select)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height

                        guard max(abs(dx), abs(dy)) > 24 else { return }

                        if abs(dx) > abs(dy) {
                            onCommand(dx > 0 ? .right : .left)
                        } else {
                            onCommand(dy > 0 ? .down : .up)
                        }
                    }
            )
            .accessibilityLabel("TV touchpad")
            .accessibilityHint("Swipe to navigate. Double tap to select.")
            .accessibilityAction(named: "Up") { onCommand(.up) }
            .accessibilityAction(named: "Down") { onCommand(.down) }
            .accessibilityAction(named: "Left") { onCommand(.left) }
            .accessibilityAction(named: "Right") { onCommand(.right) }
            .accessibilityAction(named: "Select") { onCommand(.select) }
    }
}

struct RemoteView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage(AppSettings.Keys.keepScreenAwake) private var keepScreenAwake = true

    @State private var mode: RemoteControlMode = .dpad
    @State private var showMore = false
    @State private var showKeyboard = false
    @State private var showAppsInputs = false
    @State private var appsInputsInitialSelection = 0

    var body: some View {
        GeometryReader { proxy in
            let dpadSize = min(proxy.size.width * 0.58, 232)

            VStack(spacing: 14) {
                header

                if let message = appModel.connectionMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                }

                HStack {
                    if appModel.currentCapabilities.contains(.power) {
                        RoundRemoteButton(
                            systemName: "power",
                            destructivePower: true
                        ) {
                            appModel.send(.power)
                        }
                    }

                    Spacer()

                    if appModel.currentCapabilities.contains(.inputSelection) &&
                        shouldShowInput {
                        Button {
                            appsInputsInitialSelection = 1
                            showAppsInputs = true
                        } label: {
                            Text("Input")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 72, height: 46)
                                .background(Capsule().fill(Color.orbitSurface))
                        }
                        .buttonStyle(OrbitPressStyle(cornerRadius: 23))
                        .foregroundStyle(.primary)
                    }
                }

                if appModel.currentCapabilities.contains(.touchpad) {
                    Picker("Remote mode", selection: $mode) {
                        ForEach(RemoteControlMode.allCases, id: \.self) {
                            Text($0.title).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _, newValue in
                        Haptics.shared.selection()

                        if appModel.purchases.isPremium {
                            appModel.customization.setDefaultMode(newValue)
                        }
                    }
                }

                Group {
                    if mode == .touchpad &&
                        appModel.currentCapabilities.contains(.touchpad) {
                        TouchpadView(onCommand: appModel.send)
                    } else {
                        DPadView(onCommand: appModel.send)
                    }
                }
                .frame(width: dpadSize, height: dpadSize)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.16), value: mode)

                HStack(spacing: 14) {
                    Button {
                        appModel.send(.back)
                    } label: {
                        Label("Back", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Capsule().fill(Color.orbitSurface))
                    }

                    Button {
                        appModel.send(.home)
                    } label: {
                        Label("Home", systemImage: "house.fill")
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Capsule().fill(Color.orbitSurface))
                    }
                }
                .buttonStyle(OrbitPressStyle(cornerRadius: 23))
                .foregroundStyle(.primary)

                if appModel.currentCapabilities.contains(.volume) ||
                    appModel.currentCapabilities.contains(.mute) {
                    VolumePill(onCommand: appModel.send)
                }

                if appModel.currentCapabilities.contains(.playback) &&
                    shouldShowPlayback {
                    PlaybackRow(onCommand: appModel.send)
                }

                if (appModel.currentCapabilities.contains(.keyboard) && shouldShowKeyboard) ||
                    (appModel.currentCapabilities.contains(.appLaunching) && shouldShowApps) {
                    HStack(spacing: 12) {
                        if appModel.currentCapabilities.contains(.keyboard) &&
                            shouldShowKeyboard {
                            Button {
                                showKeyboard = true
                            } label: {
                                Label("Keyboard", systemImage: "keyboard")
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                            }
                        }

                        if appModel.currentCapabilities.contains(.appLaunching) &&
                            shouldShowApps {
                            Button {
                                appsInputsInitialSelection = 0
                                showAppsInputs = true
                            } label: {
                                Label("Apps", systemImage: "square.grid.2x2")
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                            }
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .background(Capsule().fill(Color.orbitSurface))
                    .clipShape(Capsule())
                    .buttonStyle(OrbitPressStyle(cornerRadius: 22))
                    .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color.orbitBackground.ignoresSafeArea())
        .sheet(isPresented: $showMore) {
            MoreMenuSheet()
        }
        .sheet(isPresented: $showKeyboard) {
            KeyboardSheet()
        }
        .sheet(isPresented: $showAppsInputs) {
            AppsInputsView(initialSelection: appsInputsInitialSelection)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
            mode = preferredMode
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: keepScreenAwake) { _, value in
            UIApplication.shared.isIdleTimerDisabled = value
        }
    }

    private var preferredMode: RemoteControlMode {
        guard appModel.purchases.isPremium else { return .dpad }

        let preferred = appModel.customization.preferences.defaultMode
        if preferred == .touchpad &&
            !appModel.currentCapabilities.contains(.touchpad) {
            return .dpad
        }

        return preferred
    }

    private var shouldShowInput: Bool {
        !appModel.purchases.isPremium ||
        appModel.customization.preferences.showInput
    }

    private var shouldShowPlayback: Bool {
        !appModel.purchases.isPremium ||
        appModel.customization.preferences.showPlayback
    }

    private var shouldShowKeyboard: Bool {
        !appModel.purchases.isPremium ||
        appModel.customization.preferences.showKeyboard
    }

    private var shouldShowApps: Bool {
        !appModel.purchases.isPremium ||
        appModel.customization.preferences.showApps
    }

    private var header: some View {
        HStack(alignment: .top) {
            Spacer()
                .frame(width: 44)

            Spacer()

            VStack(spacing: 3) {
                Text(appModel.currentDevice?.name ?? "TV")
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Circle()
                        .fill(
                            appModel.connectionState == .connected
                            ? Color.primary
                            : Color.secondary.opacity(0.35)
                        )
                        .frame(width: 6, height: 6)

                    Text(appModel.connectionState.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                showMore = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.orbitSurface))
            }
            .buttonStyle(OrbitPressStyle(cornerRadius: 22))
            .foregroundStyle(.primary)
            .accessibilityLabel("More")
        }
    }
}

struct KeyboardSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                TextField("Type on your TV…", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit {
                        send()
                    }

                Text("Orbit sends text over your local network to the active TV input field.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Keyboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        send()
                    }
                    .disabled(text.isEmpty)
                }
            }
            .task {
                try? await Task.sleep(nanoseconds: 280_000_000)
                focused = true
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func send() {
        let value = text
        guard !value.isEmpty else { return }

        Task {
            do {
                try await appModel.send(text: value)
                text = ""
                Haptics.shared.tap()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct AppsInputsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var selection: Int

    init(initialSelection: Int = 0) {
        _selection = State(initialValue: initialSelection)
    }
    @State private var apps: [TVApp] = []
    @State private var inputs: [TVInput] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Type", selection: $selection) {
                    Text("Apps").tag(0)
                    Text("Inputs").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                if isLoading {
                    ProgressView()
                        .frame(maxHeight: .infinity)
                } else if selection == 0 {
                    List(apps) { app in
                        Button(app.name) {
                            Task {
                                await appModel.launch(app)
                                dismiss()
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .listStyle(.plain)
                } else {
                    List(inputs) { input in
                        Button(input.name) {
                            Task {
                                await appModel.select(input)
                                dismiss()
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Apps & Inputs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .task {
                async let loadedApps = appModel.apps()
                async let loadedInputs = appModel.inputs()

                apps = await loadedApps
                inputs = await loadedInputs
                isLoading = false
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct MoreMenuSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var showDevices = false
    @State private var showSettings = false
    @State private var rename = ""
    @State private var showRename = false
    @State private var showForgetConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        appModel.connect()
                        dismiss()
                    } label: {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                    }

                    Button {
                        showDevices = true
                    } label: {
                        Label("Switch TV", systemImage: "tv")
                    }

                    Button {
                        rename = appModel.currentDevice?.name ?? ""
                        showRename = true
                    } label: {
                        Label("Rename TV", systemImage: "pencil")
                    }

                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }

                Section {
                    Button {
                        showForgetConfirmation = true
                    } label: {
                        Label("Forget This TV", systemImage: "trash")
                    }
                }
            }
            .foregroundStyle(.primary)
            .navigationTitle(appModel.currentDevice?.name ?? "TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showDevices) {
                DevicesView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .alert("Rename TV", isPresented: $showRename) {
                TextField("TV name", text: $rename)
                Button("Cancel", role: .cancel) {}

                Button("Save") {
                    if var device = appModel.currentDevice {
                        device.name = rename.trimmingCharacters(in: .whitespacesAndNewlines)
                        appModel.deviceStore.addOrUpdate(device)
                        appModel.refreshSelection()
                    }
                }
            }
            .confirmationDialog(
                "Forget this TV?",
                isPresented: $showForgetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Forget TV", role: .destructive) {
                    appModel.forgetCurrentDevice()
                    dismiss()
                }

                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
    }
}
