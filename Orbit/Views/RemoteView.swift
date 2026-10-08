import SwiftUI
import UIKit

struct DPadView: View {
    let onCommand: (RemoteCommand, Bool) -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size * 0.34

            ZStack {
                Circle()
                    .fill(Color.orbitSurface)
                    .overlay(
                        Circle()
                            .stroke(
                                Color.primary.opacity(0.09),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(
                        color: Color.black.opacity(0.08),
                        radius: 14,
                        x: 0,
                        y: 6
                    )

                Circle()
                    .fill(Color.primary.opacity(0.035))
                    .frame(
                        width: size * 0.39,
                        height: size * 0.39
                    )

                DirectionButton(systemName: "chevron.up", command: .up, onCommand: onCommand)
                    .offset(y: -radius)
                DirectionButton(systemName: "chevron.down", command: .down, onCommand: onCommand)
                    .offset(y: radius)
                DirectionButton(systemName: "chevron.left", command: .left, onCommand: onCommand)
                    .offset(x: -radius)
                DirectionButton(systemName: "chevron.right", command: .right, onCommand: onCommand)
                    .offset(x: radius)

                Button {
                    onCommand(.select, false)
                } label: {
                    Text("OK")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: size * 0.32, height: size * 0.32)
                        .background(
                            Circle()
                                .fill(Color.orbitSurfaceRaised)
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    Color.primary.opacity(0.11),
                                    lineWidth: 0.9
                                )
                        )
                        .shadow(
                            color: Color.black.opacity(0.08),
                            radius: 6,
                            x: 0,
                            y: 3
                        )
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
    let onCommand: (RemoteCommand, Bool) -> Void

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
        RepeatableRemoteButton(
            action: { isRepeat in
                onCommand(command, isRepeat)
            }
        ) {
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

private struct RepeatableRemoteButton<Label: View>: View {
    let action: (Bool) -> Void
    @ViewBuilder let label: () -> Label

    @State private var repeatTask: Task<Void, Never>?
    @State private var didRepeat = false

    var body: some View {
        Button {
            guard !didRepeat else { return }
            action(false)
        } label: {
            label()
        }
        .onLongPressGesture(
            minimumDuration: 0.34,
            maximumDistance: 44
        ) {
            didRepeat = true
            beginRepeating()
        } onPressingChanged: { isPressing in
            if !isPressing {
                endRepeating()
            }
        }
        .onDisappear {
            repeatTask?.cancel()
            repeatTask = nil
        }
    }

    private func beginRepeating() {
        repeatTask?.cancel()

        repeatTask = Task { @MainActor in
            action(true)

            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: 120_000_000
                )

                guard !Task.isCancelled else {
                    return
                }

                action(true)
            }
        }
    }

    private func endRepeating() {
        repeatTask?.cancel()
        repeatTask = nil

        guard didRepeat else { return }

        // Keep suppression alive through the Button release callback so a
        // long press does not generate an extra discrete tap on release.
        Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: 80_000_000
            )
            didRepeat = false
        }
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
            .background(
                Circle()
                    .fill(
                        destructivePower
                        ? Color.orbitPower
                        : Color.orbitSurface
                    )
            )
            .overlay(
                Circle()
                    .stroke(
                        destructivePower
                        ? Color.white.opacity(0.18)
                        : Color.primary.opacity(0.08),
                        lineWidth: 0.8
                    )
            )
            .shadow(
                color:
                    destructivePower
                    ? Color.orbitPower.opacity(0.22)
                    : Color.black.opacity(0.06),
                radius: destructivePower ? 10 : 7,
                x: 0,
                y: destructivePower ? 4 : 3
            )
        }
        .buttonStyle(OrbitPressStyle(cornerRadius: 29))
        .accessibilityLabel(label ?? (destructivePower ? "Power" : "Remote control"))
    }
}

struct VolumePill: View {
    let onCommand: (RemoteCommand, Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            SegmentButton(
                systemName: "minus",
                accessibilityLabel: "Volume Down",
                repeats: true,
                action: { isRepeat in
                    onCommand(.volumeDown, isRepeat)
                }
            )
            SegmentButton(
                systemName: "speaker.slash.fill",
                accessibilityLabel: "Mute",
                repeats: false,
                action: { _ in
                    onCommand(.mute, false)
                }
            )
            SegmentButton(
                systemName: "plus",
                accessibilityLabel: "Volume Up",
                repeats: true,
                action: { isRepeat in
                    onCommand(.volumeUp, isRepeat)
                }
            )
        }
        .frame(height: 54)
        .background(
            Capsule()
                .fill(Color.orbitSurface)
        )
        .overlay(
            Capsule()
                .stroke(
                    Color.primary.opacity(0.08),
                    lineWidth: 0.8
                )
        )
        .overlay {
            GeometryReader { proxy in
                let third =
                    proxy.size.width / 3

                Path { path in
                    path.move(
                        to: CGPoint(
                            x: third,
                            y: 12
                        )
                    )
                    path.addLine(
                        to: CGPoint(
                            x: third,
                            y: proxy.size.height - 12
                        )
                    )
                    path.move(
                        to: CGPoint(
                            x: third * 2,
                            y: 12
                        )
                    )
                    path.addLine(
                        to: CGPoint(
                            x: third * 2,
                            y: proxy.size.height - 12
                        )
                    )
                }
                .stroke(
                    Color.orbitSeparator,
                    lineWidth: 0.5
                )
            }
            .allowsHitTesting(false)
        }
        .shadow(
            color: Color.black.opacity(0.05),
            radius: 7,
            x: 0,
            y: 3
        )
    }
}

private struct SegmentButton: View {
    let systemName: String
    let accessibilityLabel: String
    let repeats: Bool
    let action: (Bool) -> Void

    var body: some View {
        Group {
            if repeats {
                RepeatableRemoteButton(
                    action: action
                ) {
                    segmentLabel
                }
            } else {
                Button {
                    action(false)
                } label: {
                    segmentLabel
                }
            }
        }
        .buttonStyle(OrbitPressStyle(cornerRadius: 24))
        .foregroundStyle(.primary)
        .accessibilityLabel(accessibilityLabel)
    }

    private var segmentLabel: some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
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
                .frame(minHeight: 46)
                .background(
                    Capsule()
                        .fill(Color.orbitSurface)
                )
                .overlay(
                    Capsule()
                        .stroke(
                            Color.primary.opacity(0.08),
                            lineWidth: 0.8
                        )
                )
                .shadow(
                    color: Color.black.opacity(0.05),
                    radius: 6,
                    x: 0,
                    y: 3
                )
        }
        .buttonStyle(OrbitPressStyle(cornerRadius: 23))
        .foregroundStyle(.primary)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct TouchpadView: View {
    let onCommand: (RemoteCommand) -> Void

    var body: some View {
        touchpadSurface
            .contentShape(
                RoundedRectangle(
                    cornerRadius: 34,
                    style: .continuous
                )
            )
            .onTapGesture {
                onCommand(.select)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .onEnded(handleDrag)
            )
            .accessibilityLabel("TV touchpad")
            .accessibilityHint(
                "Swipe to navigate. Double tap to select."
            )
            .accessibilityAction(named: "Up") {
                onCommand(.up)
            }
            .accessibilityAction(named: "Down") {
                onCommand(.down)
            }
            .accessibilityAction(named: "Left") {
                onCommand(.left)
            }
            .accessibilityAction(named: "Right") {
                onCommand(.right)
            }
            .accessibilityAction(named: "Select") {
                onCommand(.select)
            }
    }

    private var touchpadSurface: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: 34,
                style: .continuous
            )
            .fill(Color.orbitSurface)
            .overlay(
                RoundedRectangle(
                    cornerRadius: 34,
                    style: .continuous
                )
                .stroke(
                    Color.primary.opacity(0.08),
                    lineWidth: 0.8
                )
            )
            .shadow(
                color: Color.black.opacity(0.06),
                radius: 12,
                x: 0,
                y: 5
            )

            VStack(spacing: 10) {
                touchTarget

                Text("Swipe to navigate")
                    .font(
                        .subheadline.weight(.semibold)
                    )

                Text("Tap to select")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var touchTarget: some View {
        ZStack {
            Circle()
                .fill(
                    Color.primary.opacity(0.045)
                )

            Circle()
                .stroke(
                    Color.primary.opacity(0.08),
                    lineWidth: 0.8
                )

            Image(systemName: "hand.draw")
                .font(
                    .system(
                        size: 26,
                        weight: .light
                    )
                )
        }
        .frame(
            width: 70,
            height: 70
        )
    }

    private func handleDrag(
        _ value: DragGesture.Value
    ) {
        let dx = value.translation.width
        let dy = value.translation.height

        guard max(abs(dx), abs(dy)) > 24 else {
            return
        }

        if abs(dx) > abs(dy) {
            onCommand(
                dx > 0
                ? .right
                : .left
            )
        } else {
            onCommand(
                dy > 0
                ? .down
                : .up
            )
        }
    }
}

private struct RemoteViewportHeightModifier: ViewModifier {
    let fillsAvailableHeight: Bool
    let availableHeight: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if fillsAvailableHeight {
            content.frame(
                height: availableHeight,
                alignment: .top
            )
        } else {
            content.frame(
                minHeight: availableHeight,
                alignment: .top
            )
        }
    }
}

struct RemoteView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(AppSettings.Keys.keepScreenAwake) private var keepScreenAwake = true

    @State private var mode: RemoteControlMode = .dpad
    @State private var showMore = false
    @State private var showKeyboard = false
    @State private var showAppsInputs = false
    @State private var showFindTV = false
    @State private var appsInputsInitialSelection = 0

    var body: some View {
        GeometryReader { proxy in
            let isCompactHeight =
                proxy.size.height < 720

            let heightProgress = min(
                max(
                    (proxy.size.height - 720) / 220,
                    0
                ),
                1
            )

            let dpadSize = min(
                proxy.size.width *
                    (0.58 + 0.04 * heightProgress),
                isCompactHeight
                ? 176
                : 224 + 28 * heightProgress
            )

            let verticalSpacing: CGFloat =
                isCompactHeight ? 8 : 12

            let fillsAvailableHeight =
                !dynamicTypeSize.isAccessibilitySize &&
                appModel.connectionState == .connected

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    header

                    Spacer(
                        minLength: verticalSpacing
                    )

                if let message = appModel.connectionMessage {
                    VStack(spacing: 10) {
                        if appModel.shouldShowTVApprovalHint {
                            HStack(spacing: 12) {
                                Image(systemName: "tv")
                                    .font(.title3)

                                Text(message)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(
                                    cornerRadius: 16,
                                    style: .continuous
                                )
                                .fill(Color.orbitSurface)
                            )
                            .overlay(
                                RoundedRectangle(
                                    cornerRadius: 16,
                                    style: .continuous
                                )
                                .stroke(
                                    Color.orbitSeparator,
                                    lineWidth: 0.5
                                )
                            )
                        } else {
                            Text(message)
                                .font(.subheadline)
                                .foregroundStyle(
                                    appModel.connectionState ==
                                        .unavailable
                                    ? Color.primary
                                    : Color.secondary
                                )
                                .multilineTextAlignment(.center)
                                .lineLimit(
                                    appModel.connectionState == .unavailable ||
                                    dynamicTypeSize.isAccessibilitySize
                                    ? nil
                                    : 4
                                )
                                .frame(maxWidth: .infinity)
                        }

                        if appModel.connectionState == .unavailable {
                            VStack(spacing: 8) {
                                Button("Reconnect") {
                                    appModel.connect()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.primary)
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: 44
                                )

                                HStack(spacing: 16) {
                                    Button("Find TV Again") {
                                        showFindTV = true
                                    }

                                    if appModel.localNetworkAccessLikelyDenied {
                                        Button("iPhone Settings") {
                                            if let url = URL(
                                                string:
                                                    UIApplication.openSettingsURLString
                                            ) {
                                                UIApplication.shared.open(url)
                                            }
                                        }
                                    }
                                }
                                .font(.subheadline.weight(.semibold))
                                .buttonStyle(.plain)
                                .frame(minHeight: 44)
                            }
                        }
                    }
                    .transition(.opacity)
                }

                Spacer(
                    minLength: verticalSpacing
                )

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
                                .frame(
                                    minWidth: 72,
                                    minHeight: 46
                                )
                                .padding(
                                    .horizontal,
                                    dynamicTypeSize.isAccessibilitySize
                                    ? 8
                                    : 0
                                )
                                .background(
                                    Capsule()
                                        .fill(Color.orbitSurface)
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            Color.primary.opacity(0.08),
                                            lineWidth: 0.8
                                        )
                                )
                                .shadow(
                                    color: Color.black.opacity(0.05),
                                    radius: 6,
                                    x: 0,
                                    y: 3
                                )
                        }
                        .buttonStyle(OrbitPressStyle(cornerRadius: 23))
                        .foregroundStyle(.primary)
                    }
                }

                Spacer(
                    minLength: verticalSpacing
                )

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

                Spacer(
                    minLength: verticalSpacing
                )

                Group {
                    if mode == .touchpad &&
                        appModel.currentCapabilities.contains(.touchpad) {
                        TouchpadView(
                            onCommand: {
                                appModel.send($0)
                            }
                        )
                    } else {
                        DPadView(
                            onCommand: {
                                command,
                                isRepeat in

                                appModel.send(
                                    command,
                                    isRepeat: isRepeat
                                )
                            }
                        )
                    }
                }
                .frame(width: dpadSize, height: dpadSize)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.16), value: mode)

                Spacer(
                    minLength: verticalSpacing
                )

                VStack(
                    spacing: verticalSpacing
                ) {
                    HStack(spacing: 14) {
                    Button {
                        appModel.send(.back)
                    } label: {
                        Label("Back", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 46)
                            .background(
                                Capsule()
                                    .fill(Color.orbitSurface)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        Color.primary.opacity(0.08),
                                        lineWidth: 0.8
                                    )
                            )
                            .shadow(
                                color: Color.black.opacity(0.05),
                                radius: 6,
                                x: 0,
                                y: 3
                            )
                    }

                    Button {
                        appModel.send(.home)
                    } label: {
                        Label("Home", systemImage: "house.fill")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 46)
                            .background(
                                Capsule()
                                    .fill(Color.orbitSurface)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        Color.primary.opacity(0.08),
                                        lineWidth: 0.8
                                    )
                            )
                            .shadow(
                                color: Color.black.opacity(0.05),
                                radius: 6,
                                x: 0,
                                y: 3
                            )
                    }
                }
                .buttonStyle(OrbitPressStyle(cornerRadius: 23))
                .foregroundStyle(.primary)

                if appModel.currentCapabilities.contains(.volume) ||
                    appModel.currentCapabilities.contains(.mute) {
                    VolumePill(
                        onCommand: {
                            command,
                            isRepeat in

                            appModel.send(
                                command,
                                isRepeat: isRepeat
                            )
                        }
                    )
                }

                if appModel.currentCapabilities.contains(.playback) &&
                    shouldShowPlayback {
                    PlaybackRow(
                        onCommand: {
                            appModel.send($0)
                        }
                    )
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
                                    .frame(minHeight: 44)
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
                                    .frame(minHeight: 44)
                            }
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .background(
                        Capsule()
                            .fill(Color.orbitSurface)
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                Color.primary.opacity(0.08),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(
                        color: Color.black.opacity(0.05),
                        radius: 6,
                        x: 0,
                        y: 3
                    )
                    .clipShape(Capsule())
                    .buttonStyle(OrbitPressStyle(cornerRadius: 22))
                    .foregroundStyle(.primary)
                }
                }
            }
                .padding(.horizontal, 22)
                .padding(.top, isCompactHeight ? 4 : 8)
                .padding(
                    .bottom,
                    dynamicTypeSize.isAccessibilitySize
                    ? 24
                    : (isCompactHeight ? 8 : 14)
                )
                .frame(
                    maxWidth: .infinity
                )
                .modifier(
                    RemoteViewportHeightModifier(
                        fillsAvailableHeight:
                            fillsAvailableHeight,
                        availableHeight:
                            proxy.size.height
                    )
                )
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(
                .basedOnSize
            )
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
        .sheet(isPresented: $showFindTV) {
            DiscoveryView(showsCloseButton: true)
        }
        .sheet(isPresented: pairingPresented) {
            TVPairingSheet()
        }
        .sheet(
            isPresented: Binding(
                get: {
                    appModel.proGateRequested
                },
                set: { presented in
                    if !presented {
                        appModel.dismissProGate()
                    }
                }
            )
        ) {
            PremiumView()
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

    private var pairingPresented: Binding<Bool> {
        Binding(
            get: {
                appModel.requiresPairing
            },
            set: { presented in
                if !presented,
                   appModel.requiresPairing {
                    appModel.cancelPairing()
                }
            }
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "tv")
                .font(
                    .system(
                        size: 15,
                        weight: .semibold
                    )
                )
                .frame(
                    width: 38,
                    height: 38
                )
                .background(
                    Circle()
                        .fill(Color.orbitSurface)
                )
                .overlay(
                    Circle()
                        .stroke(
                            Color.primary.opacity(0.08),
                            lineWidth: 0.8
                        )
                )
                .shadow(
                    color: Color.black.opacity(0.05),
                    radius: 6,
                    x: 0,
                    y: 3
                )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    appModel.currentDevice?.name
                    ?? "TV"
                )
                .font(.headline)
                .lineLimit(
                    dynamicTypeSize.isAccessibilitySize
                    ? 2
                    : 1
                )

                HStack(spacing: 6) {
                    Circle()
                        .fill(
                            appModel.connectionState ==
                                .connected
                            ? Color.primary
                            : Color.secondary.opacity(
                                0.35
                            )
                        )
                        .frame(
                            width: 6,
                            height: 6
                        )

                    Text(
                        appModel.connectionState.label
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Button {
                showMore = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.headline)
                    .frame(
                        width: 44,
                        height: 44
                    )
                    .background(
                        Circle()
                            .fill(Color.orbitSurface)
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                Color.primary.opacity(
                                    0.08
                                ),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(
                        color: Color.black.opacity(0.05),
                        radius: 6,
                        x: 0,
                        y: 3
                    )
            }
            .buttonStyle(
                OrbitPressStyle(cornerRadius: 22)
            )
            .foregroundStyle(.primary)
            .accessibilityLabel("Menu")
        }
    }
}

struct TVPairingSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "tv")
                        .font(.system(size: 34, weight: .medium))
                        .frame(width: 68, height: 68)
                        .background(
                            Circle()
                                .fill(Color.orbitSurface)
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    Color.primary.opacity(0.08),
                                    lineWidth: 0.8
                                )
                        )
                        .shadow(
                            color: Color.black.opacity(0.06),
                            radius: 10,
                            x: 0,
                            y: 4
                        )

                    Text("Pair with your TV")
                        .font(.title2.bold())

                    Text(pairingMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                }

                if case .pin(
                    let length,
                    _
                ) = appModel.pairingRequirement {
                    TextField(
                        String(
                            repeating: "•",
                            count: length ?? 6
                        ),
                        text: $code
                    )
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .font(
                        .system(
                            size: 26,
                            weight: .semibold,
                            design: .monospaced
                        )
                    )
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                    .orbitRaisedPanel(
                        cornerRadius: 16
                    )
                    .focused($codeFocused)
                    .onChange(of: code) { _, newValue in
                        let filtered = String(
                            newValue
                                .uppercased()
                                .filter {
                                    $0.isNumber ||
                                    ("A"..."F").contains(
                                        String($0)
                                    )
                                }
                                .prefix(length ?? 6)
                        )

                        if filtered != code {
                            code = filtered
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button(primaryButtonTitle) {
                    submit()
                }
                .buttonStyle(OrbitPrimaryButtonStyle())
                .disabled(!canSubmit || isSubmitting)
                .overlay {
                    if isSubmitting {
                        ProgressView()
                            .tint(
                                Color(uiColor: .systemBackground)
                            )
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(22)
            .background(
                Color.orbitBackground
                    .ignoresSafeArea()
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Cancel") {
                        appModel.cancelPairing()
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
            }
            .task {
                if case .pin = appModel.pairingRequirement {
                    try? await Task.sleep(
                        nanoseconds: 250_000_000
                    )
                    codeFocused = true
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isSubmitting)
    }

    private var pairingMessage: String {
        switch appModel.pairingRequirement {
        case .none:
            return "Orbit is connected."

        case .confirmation(let message):
            return message ??
                "Approve Orbit on your TV to continue."

        case .pin(_, let message):
            return message ??
                "Enter the code shown on your TV."
        }
    }

    private var primaryButtonTitle: String {
        switch appModel.pairingRequirement {
        case .confirmation:
            return "I Approved It"
        case .pin:
            return "Pair"
        case .none:
            return "Done"
        }
    }

    private var canSubmit: Bool {
        switch appModel.pairingRequirement {
        case .none:
            return false

        case .confirmation:
            return true

        case .pin(let length, _):
            return code.count == (length ?? 6)
        }
    }

    private func submit() {
        let response: TVPairingResponse

        switch appModel.pairingRequirement {
        case .none:
            dismiss()
            return

        case .confirmation:
            response = .confirmed

        case .pin:
            response = .pin(code)
        }

        isSubmitting = true
        errorMessage = nil

        Task {
            let success = await appModel.submitPairing(
                response
            )

            isSubmitting = false

            if success {
                Haptics.shared.selection()
                dismiss()
            } else {
                errorMessage =
                    appModel.lastControlError ??
                    "Pairing failed. Check the TV and try again."
            }
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
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 54)
                    .orbitRaisedPanel(
                        cornerRadius: 16
                    )
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit {
                        send()
                    }

                Text("First open a search box or text field on your TV, then type here.")
                    .font(.subheadline)
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
            .background(
                Color.orbitBackground
                    .ignoresSafeArea()
            )
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
                errorMessage =
                    "Couldn’t send that text. Make sure the TV is connected and a text field is open."
            }
        }
    }
}

struct AppsInputsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var selection: Int
    @State private var apps: [TVApp] = []
    @State private var inputs: [TVInput] = []
    @State private var isLoading = true
    @State private var showPro = false

    init(initialSelection: Int = 0) {
        _selection = State(initialValue: initialSelection)
    }

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
                    if apps.isEmpty {
                        emptyState(
                            title: "No apps available",
                            message:
                                "Make sure the TV is connected, then try again."
                        )
                    } else {
                        appsList
                    }
                } else {
                    if inputs.isEmpty {
                        emptyState(
                            title: "No inputs available",
                            message:
                                "Make sure the TV is connected, then try again."
                        )
                    } else {
                        inputsList
                    }
                }
            }
            .background(
                Color.orbitBackground
                    .ignoresSafeArea()
            )
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
                await reload()
            }
        }
        .sheet(isPresented: $showPro) {
            PremiumView()
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func emptyState(
        title: String,
        message: String
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "tv")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task {
                    await reload()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary)
        }
        .frame(maxHeight: .infinity)
    }

    @MainActor
    private func reload() async {
        isLoading = true

        async let loadedApps = appModel.apps()
        async let loadedInputs = appModel.inputs()

        apps = await loadedApps
        inputs = await loadedInputs
        isLoading = false
    }

    private var currentDeviceID: String? {
        appModel.currentDevice?.id
    }

    private var favoriteApps: [RemoteFavorite] {
        guard appModel.purchases.isPremium,
              let currentDeviceID else {
            return []
        }

        return appModel.favorites.favorites(
            for: currentDeviceID,
            kind: .app
        )
    }

    private var favoriteInputs: [RemoteFavorite] {
        guard appModel.purchases.isPremium,
              let currentDeviceID else {
            return []
        }

        return appModel.favorites.favorites(
            for: currentDeviceID,
            kind: .input
        )
    }

    private var appsList: some View {
        List {
            if !favoriteApps.isEmpty {
                Section("Favorites") {
                    ForEach(favoriteApps) { favorite in
                        Button {
                            Task {
                                await appModel.launch(
                                    TVApp(
                                        id: favorite.targetID,
                                        name: favorite.name
                                    )
                                )
                                dismiss()
                            }
                        } label: {
                            Label(favorite.name, systemImage: "star.fill")
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }

            Section(favoriteApps.isEmpty ? "Apps" : "All Apps") {
                ForEach(apps) { app in
                    HStack(spacing: 12) {
                        Button(app.name) {
                            Task {
                                await appModel.launch(app)
                                dismiss()
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if let currentDeviceID {
                            Button {
                                if appModel.purchases.isPremium {
                                    appModel.favorites.toggle(
                                        deviceID: currentDeviceID,
                                        favorite: RemoteFavorite(
                                            kind: .app,
                                            targetID: app.id,
                                            name: app.name
                                        )
                                    )
                                    Haptics.shared.selection()
                                } else {
                                    showPro = true
                                }
                            } label: {
                                Image(
                                    systemName:
                                        appModel.purchases.isPremium &&
                                        appModel.favorites.contains(
                                            deviceID: currentDeviceID,
                                            kind: .app,
                                            targetID: app.id
                                        )
                                        ? "star.fill"
                                        : "star"
                                )
                                .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                            .accessibilityLabel(
                                appModel.purchases.isPremium
                                ? (
                                    appModel.favorites.contains(
                                        deviceID: currentDeviceID,
                                        kind: .app,
                                        targetID: app.id
                                    )
                                    ? "Remove \(app.name) from favorites"
                                    : "Add \(app.name) to favorites"
                                )
                                : "Add \(app.name) to favorites with Orbit Pro"
                            )
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.orbitBackground)
    }

    private var inputsList: some View {
        List {
            if !favoriteInputs.isEmpty {
                Section("Favorites") {
                    ForEach(favoriteInputs) { favorite in
                        Button {
                            Task {
                                await appModel.select(
                                    TVInput(
                                        id: favorite.targetID,
                                        name: favorite.name
                                    )
                                )
                                dismiss()
                            }
                        } label: {
                            Label(favorite.name, systemImage: "star.fill")
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }

            Section(favoriteInputs.isEmpty ? "Inputs" : "All Inputs") {
                ForEach(inputs) { input in
                    HStack(spacing: 12) {
                        Button(input.name) {
                            Task {
                                await appModel.select(input)
                                dismiss()
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if let currentDeviceID {
                            Button {
                                if appModel.purchases.isPremium {
                                    appModel.favorites.toggle(
                                        deviceID: currentDeviceID,
                                        favorite: RemoteFavorite(
                                            kind: .input,
                                            targetID: input.id,
                                            name: input.name
                                        )
                                    )
                                    Haptics.shared.selection()
                                } else {
                                    showPro = true
                                }
                            } label: {
                                Image(
                                    systemName:
                                        appModel.purchases.isPremium &&
                                        appModel.favorites.contains(
                                            deviceID: currentDeviceID,
                                            kind: .input,
                                            targetID: input.id
                                        )
                                        ? "star.fill"
                                        : "star"
                                )
                                .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                            .accessibilityLabel(
                                appModel.purchases.isPremium
                                ? (
                                    appModel.favorites.contains(
                                        deviceID: currentDeviceID,
                                        kind: .input,
                                        targetID: input.id
                                    )
                                    ? "Remove \(input.name) from favorites"
                                    : "Add \(input.name) to favorites"
                                )
                                : "Add \(input.name) to favorites with Orbit Pro"
                            )
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.orbitBackground)
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
            .scrollContentBackground(.hidden)
            .background(Color.orbitBackground)
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
                    guard let device =
                            appModel.currentDevice else {
                        return
                    }

                    let trimmed =
                        rename.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )

                    guard !trimmed.isEmpty else {
                        return
                    }

                    appModel.deviceStore.rename(
                        device,
                        to: trimmed
                    )
                }
                .disabled(
                    rename.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
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
        .onChange(of: appModel.currentDevice?.id) {
            oldValue,
            newValue in

            guard oldValue != newValue,
                  newValue != nil else {
                return
            }

            dismiss()
        }
        .presentationDetents([.medium, .large])
    }
}
