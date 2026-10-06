import SwiftUI
import UIKit

struct DiscoveryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var showManualAddress = false
    @State private var showPro = false
    @State private var manualAddress = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Find Your TV")
                        .font(.largeTitle.bold())

                    Text("Make sure your TV is on and connected to the same Wi-Fi network as your iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)
                .padding(.horizontal, 28)

                if appModel.discovery.isSearching {
                    ProgressView("Finding TVs…")
                        .padding(.top, 16)
                }

                if appModel.discovery.devices.isEmpty, !appModel.discovery.isSearching {
                    ContentUnavailableView {
                        Label("No TVs found", systemImage: "tv")
                    } description: {
                        Text(
                            appModel.discovery.lastError ??
                            "Make sure Local Network access is enabled. You can also connect directly using your TV’s local IP address."
                        )
                    } actions: {
                        Button("Scan Again") {
                            appModel.discovery.startScan()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.primary)

                        Button("Open Settings") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                                return
                            }
                            UIApplication.shared.open(url)
                        }
                    }
                } else {
                    List(appModel.discovery.devices) { device in
                        Button {
                            if appModel.select(device) {
                                dismiss()
                            } else {
                                showPro = true
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "tv")

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(device.name)
                                        .font(.headline)

                                    Text(device.platform.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }

                Spacer()

                Button("Can’t find your TV?") {
                    showManualAddress = true
                }
                .foregroundStyle(.primary)
                .font(.subheadline.weight(.semibold))
                .padding(.bottom, 16)
            }
            .background(Color.orbitBackground)
            .task {
                appModel.discovery.startScan()
            }
            .sheet(isPresented: $showPro) {
                PremiumView()
            }
            .sheet(isPresented: $showManualAddress) {
                NavigationStack {
                    Form {
                        Section("Manual connection") {
                            TextField("TV IP address", text: $manualAddress)
                                .keyboardType(.numbersAndPunctuation)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            if appModel.discovery.isSearching {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("Identifying TV…")
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let error = appModel.discovery.lastError {
                                Text(error)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .navigationTitle("Connect by IP")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showManualAddress = false
                            }
                        }

                        ToolbarItem(placement: .confirmationAction) {
                            Button("Connect") {
                                Task {
                                    if let device = await appModel.discovery.addManualTV(host: manualAddress) {
                                        if appModel.select(device) {
                                            showManualAddress = false
                                            dismiss()
                                        } else {
                                            showManualAddress = false
                                            showPro = true
                                        }
                                    }
                                }
                            }
                            .disabled(
                                appModel.discovery.isSearching ||
                                manualAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
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
                        if appModel.purchases.isPremium ||
                            appModel.deviceStore.availableDevices.isEmpty {
                            showAddTV = true
                        } else {
                            showPremium = true
                        }
                    } label: {
                        Label("Add TV", systemImage: "plus")
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
                DiscoveryView()
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
