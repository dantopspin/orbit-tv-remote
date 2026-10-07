import SwiftUI
import UIKit

struct DiscoveryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSettings.Keys.tvSetupDeferred) private var tvSetupDeferred = true

    private let showsCloseButton: Bool

    @State private var showManualAddress = false
    @State private var showPro = false
    @State private var manualAddress = ""
    @State private var showStillLooking = false
    @State private var selectingDeviceID: String?

    init(showsCloseButton: Bool = false) {
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Find Your TV")
                        .font(.largeTitle.bold())

                    Text(
                        "Make sure your TV is on and connected to the same Wi-Fi as your iPhone."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
                .padding(.top, 24)
                .padding(.horizontal, 28)

                if appModel.discovery.isSearching {
                    ProgressView(
                        showStillLooking
                        ? "Still looking…"
                        : "Finding TVs…"
                    )
                    .padding(.top, 16)
                }

                if appModel.discovery.devices.isEmpty,
                   !appModel.discovery.isSearching {
                    ContentUnavailableView {
                        Label("No TVs found yet", systemImage: "tv")
                    } description: {
                        Text(
                            appModel.discovery.automaticSearchLimited
                            ? "Orbit couldn’t complete the search. If you tapped Don’t Allow earlier, turn on Local Network for Orbit in iPhone Settings, then return and scan again."
                            : (
                                appModel.discovery.lastError ??
                                "Make sure the TV is on and using the same Wi-Fi as this iPhone, then scan again."
                            )
                        )
                    } actions: {
                        Button("Scan Again") {
                            appModel.discovery.startScan()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.primary)

                        if appModel.discovery.automaticSearchLimited ||
                            appModel.localNetworkAccessLikelyDenied {
                            Button("Open iPhone Settings") {
                                guard let url = URL(
                                    string:
                                        UIApplication.openSettingsURLString
                                ) else {
                                    return
                                }
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                } else {
                    List(appModel.discovery.devices) { device in
                        Button {
                            guard selectingDeviceID == nil else {
                                return
                            }

                            selectingDeviceID = device.id

                            Task {
                                let accepted =
                                    await appModel.prepareSelection(
                                        device
                                    )

                                selectingDeviceID = nil

                                if accepted {
                                    dismiss()
                                } else {
                                    showPro = true
                                }
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "tv")

                                VStack(
                                    alignment: .leading,
                                    spacing: 3
                                ) {
                                    Text(device.name)
                                        .font(.headline)

                                    Text(device.platform.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if selectingDeviceID == device.id {
                                    ProgressView()
                                } else {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                        .disabled(
                            selectingDeviceID != nil &&
                            selectingDeviceID != device.id
                        )
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }

                Spacer()

                VStack(spacing: 6) {
                    Button("Can’t find your TV?") {
                        showManualAddress = true
                    }
                    .foregroundStyle(.primary)
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)

                    if appModel.currentDevice == nil {
                        Button("Later") {
                            tvSetupDeferred = true
                            dismiss()
                        }
                        .foregroundStyle(.secondary)
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                    }
                }
                .padding(.bottom, 16)
            }
            .background(Color.orbitBackground)
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(
                        placement: .cancellationAction
                    ) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                }
            }
            .task {
                appModel.discovery.startScan()
            }
            .task(id: appModel.discovery.isSearching) {
                showStillLooking = false

                guard appModel.discovery.isSearching else {
                    return
                }

                try? await Task.sleep(
                    nanoseconds: 2_000_000_000
                )

                guard !Task.isCancelled,
                      appModel.discovery.isSearching else {
                    return
                }

                showStillLooking = true
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active,
                      appModel.discovery.devices.isEmpty,
                      !appModel.discovery.isSearching else {
                    return
                }

                appModel.discovery.startScan()
            }
            .onChange(of: appModel.currentDevice?.id) {
                oldValue,
                newValue in

                guard showsCloseButton,
                      oldValue != newValue,
                      newValue != nil else {
                    return
                }

                dismiss()
            }
            .sheet(isPresented: $showPro) {
                PremiumView()
            }
            .sheet(isPresented: $showManualAddress) {
                manualConnectionSheet
            }
        }
    }

    private var manualConnectionSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section("TV address") {
                        TextField(
                            "e.g. 192.168.1.24",
                            text: $manualAddress
                        )
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Text(
                            "This is the number your TV uses on your home Wi-Fi."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                        if appModel.discovery.isSearching {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Checking this TV…")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let error = appModel.discovery.lastError {
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        TVAddressHelpRow(
                            brand: "Samsung",
                            path:
                                "Settings → Connection or General → Network → Network Status → IP Settings"
                        )

                        TVAddressHelpRow(
                            brand: "LG",
                            path:
                                "Settings → Network → Wi-Fi Connection → your Wi-Fi network"
                        )

                        TVAddressHelpRow(
                            brand: "Google TV",
                            path:
                                "Settings → Network & Internet → your Wi-Fi network"
                        )
                    } header: {
                        Text("Where to find it")
                    } footer: {
                        Text(
                            "Menu names can vary slightly by TV model."
                        )
                    }
                }

                Button("Connect") {
                    Task {
                        if let device =
                            await appModel.discovery
                                .addManualTV(
                                    host: manualAddress
                                ) {
                            if await appModel.prepareSelection(
                                device
                            ) {
                                showManualAddress = false
                                dismiss()
                            } else {
                                showManualAddress = false
                                showPro = true
                            }
                        }
                    }
                }
                .buttonStyle(OrbitPrimaryButtonStyle())
                .disabled(
                    appModel.discovery.isSearching ||
                    manualAddress
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .isEmpty
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .navigationTitle("Enter TV Address")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Cancel") {
                        showManualAddress = false
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}

private struct TVAddressHelpRow: View {
    let brand: String
    let path: String

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 4
        ) {
            Text(brand)
                .font(.headline)

            Text(path)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct DevicesView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAddTV = false
    @State private var showPremium = false
    @State private var showRooms = false

    var body: some View {
        NavigationStack {
            List {
                Section("Your TVs") {
                    ForEach(appModel.deviceStore.availableDevices) { device in
                        Button {
                            if appModel.activate(device) {
                                dismiss()
                            } else {
                                showPremium = true
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "tv")

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                    Text(device.roomName ?? device.platform.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if appModel.deviceStore.selectedDeviceID == device.id {
                                    Image(systemName: "checkmark.circle.fill")
                                } else if !appModel.canUse(device) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "lock.fill")
                                        Text("Pro")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section {
                    Button {
                        // Free users must be able to find their existing TV
                        // again after DHCP/IP changes. The one-TV rule is
                        // enforced when a candidate is identified/selected,
                        // not at the entrance to discovery.
                        showAddTV = true
                    } label: {
                        Label("Add or Find TV", systemImage: "plus")
                    }

                    Button {
                        if appModel.purchases.isPremium {
                            showRooms = true
                        } else {
                            showPremium = true
                        }
                    } label: {
                        HStack {
                            Label("Rooms", systemImage: "house")
                            Spacer()
                            if !appModel.purchases.isPremium {
                                Text("Pro")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !appModel.purchases.isPremium {
                    Section {
                        Text("Free includes one TV and every essential remote control. Orbit Pro adds multiple TVs, rooms, customization, and favorites.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showAddTV) {
                DiscoveryView(showsCloseButton: true)
            }
            .sheet(isPresented: $showPremium) {
                PremiumView()
            }
            .sheet(isPresented: $showRooms) {
                RoomAssignmentsView()
            }
        }
    }
}

private struct RoomAssignmentsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var editingDeviceID: String?
    @State private var roomName = ""
    @State private var showRoomEditor = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(
                        appModel.deviceStore.availableDevices
                    ) { device in
                        Button {
                            editingDeviceID = device.id
                            roomName = device.roomName ?? ""
                            showRoomEditor = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "tv")

                                VStack(
                                    alignment: .leading,
                                    spacing: 2
                                ) {
                                    Text(device.name)

                                    Text(
                                        device.roomName ??
                                        "No room assigned"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } footer: {
                    Text("Room names stay on this iPhone and make it easier to tell your TVs apart.")
                }
            }
            .navigationTitle("Rooms")
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert(
                "Assign Room",
                isPresented: $showRoomEditor
            ) {
                TextField(
                    "Living Room",
                    text: $roomName
                )

                Button("Clear") {
                    if let editingDeviceID {
                        appModel.deviceStore.setRoomName(
                            for: editingDeviceID,
                            to: nil
                        )
                    }
                }

                Button("Save") {
                    if let editingDeviceID {
                        appModel.deviceStore.setRoomName(
                            for: editingDeviceID,
                            to: roomName
                        )
                    }
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Give this TV a room name.")
            }
        }
    }
}
