import SwiftUI

struct DiscoveryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var showManualAddress = false
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
                        Text("Automatic discovery is being added protocol by protocol. You can connect to a Roku by local IP in this first build.")
                    } actions: {
                        Button("Scan Again") {
                            appModel.discovery.startScan()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.primary)
                    }
                } else {
                    List(appModel.discovery.devices) { device in
                        Button {
                            appModel.select(device)
                            dismiss()
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
            .sheet(isPresented: $showManualAddress) {
                NavigationStack {
                    Form {
                        Section("Manual Roku connection") {
                            TextField("TV IP address", text: $manualAddress)
                                .keyboardType(.decimalPad)

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
                                    if let device = await appModel.discovery.addManualRoku(host: manualAddress) {
                                        appModel.select(device)
                                        showManualAddress = false
                                        dismiss()
                                    }
                                }
                            }
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

    var body: some View {
        NavigationStack {
            List {
                Section("Your TVs") {
                    ForEach(appModel.deviceStore.devices) { device in
                        Button {
                            appModel.deviceStore.select(device)
                            appModel.refreshSelection()
                            dismiss()
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
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section {
                    Button {
                        if appModel.purchases.isPremium || appModel.deviceStore.devices.isEmpty {
                            showAddTV = true
                        } else {
                            showPremium = true
                        }
                    } label: {
                        Label("Add TV", systemImage: "plus")
                    }
                }

                if !appModel.purchases.isPremium {
                    Section {
                        Text("Free includes 1 saved TV. Orbit Premium adds multiple TVs and rooms.")
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
        }
    }
}
