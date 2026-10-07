import SwiftUI
import StoreKit

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppSettings.Keys.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(AppSettings.Keys.keepScreenAwake) private var keepScreenAwake = true
    @AppStorage(AppSettings.Keys.darkMode) private var darkMode = false

    @State private var showPremium = false
    @State private var showManageSubscriptions = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Haptic Feedback", isOn: $hapticsEnabled)
                    Toggle("Keep Screen Awake", isOn: $keepScreenAwake)
                    Toggle("Dark Mode", isOn: $darkMode)
                } footer: {
                    Text(
                        "When Dark Mode is off, Orbit follows your iPhone appearance."
                    )
                }

                Section("Remote") {
                    if appModel.purchases.isPremium {
                        NavigationLink("Customize Remote") {
                            CustomRemoteView()
                        }
                    } else {
                        Button("Customize Remote") {
                            showPremium = true
                        }
                    }
                }

                Section("Orbit Pro") {
                    HStack {
                        Text("Current plan")
                        Spacer()
                        Text(currentPlanLabel)
                            .foregroundStyle(.secondary)
                    }

                    Button(appModel.purchases.isPremium ? "View Plan" : "View Orbit Pro") {
                        if appModel.purchases.isPremium {
                            showManageSubscriptions = true
                        } else {
                            showPremium = true
                        }
                    }

                    Button("Restore Purchases") {
                        Task {
                            await appModel.purchases.restore()

                            if appModel.purchases.isPremium {
                                appModel.resumePendingProSelection()
                                dismiss()
                            }
                        }
                    }
                    .disabled(appModel.purchases.isPurchasing)

                    if appModel.purchases.isPremium {
                        Button("Manage Subscription") {
                            showManageSubscriptions = true
                        }
                    }

                    if let error = appModel.purchases.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Support & Legal") {
                    NavigationLink("FAQ") {
                        FAQView()
                    }

                    NavigationLink("Privacy Policy") {
                        PrivacyPolicyView()
                    }

                    NavigationLink("Terms of Service") {
                        TermsOfServiceView()
                    }

                    NavigationLink("Acknowledgements") {
                        AcknowledgementsView()
                    }
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showPremium) {
                PremiumView()
            }
            .manageSubscriptionsSheet(
                isPresented:
                    $showManageSubscriptions
            )
        }
    }

    private var currentPlanLabel: String {
        guard appModel.purchases.isPremium else {
            return "Free"
        }

        switch appModel.purchases.activeProductID {
        case PurchaseManager.monthlyID:
            return "Monthly"
        case PurchaseManager.weeklyID:
            return "Weekly"
        default:
            return "Pro"
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"

        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "—"

        return "\(version) (\(build))"
    }
}

private struct CustomRemoteView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Form {
            Section("Default Control") {
                Picker(
                    "Open with",
                    selection: Binding(
                        get: { appModel.customization.preferences.defaultMode },
                        set: { appModel.customization.setDefaultMode($0) }
                    )
                ) {
                    ForEach(RemoteControlMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

            Section("Visible Controls") {
                Toggle(
                    "Input",
                    isOn: Binding(
                        get: { appModel.customization.preferences.showInput },
                        set: { appModel.customization.setShowInput($0) }
                    )
                )

                Toggle(
                    "Playback",
                    isOn: Binding(
                        get: { appModel.customization.preferences.showPlayback },
                        set: { appModel.customization.setShowPlayback($0) }
                    )
                )

                Toggle(
                    "Keyboard",
                    isOn: Binding(
                        get: { appModel.customization.preferences.showKeyboard },
                        set: { appModel.customization.setShowKeyboard($0) }
                    )
                )

                Toggle(
                    "Apps",
                    isOn: Binding(
                        get: { appModel.customization.preferences.showApps },
                        set: { appModel.customization.setShowApps($0) }
                    )
                )
            }

            Section {
                Button("Reset to Default") {
                    appModel.customization.reset()
                }
            } footer: {
                Text("Core navigation, Home, Back and volume controls remain available when the connected TV supports them.")
            }
        }
        .navigationTitle("Customize Remote")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FAQView: View {
    var body: some View {
        List {
            Section("How does Orbit connect?") {
                Text("Orbit controls supported TVs over your local Wi-Fi network. Your iPhone and TV need to be on the same local network for normal control.")
            }

            Section("Do I need an account?") {
                Text("No. Orbit does not require an Orbit account.")
            }

            Section("Why can’t Orbit find my TV?") {
                Text(
                    "Make sure the TV is powered on and using the same Wi-Fi as your iPhone. If it still doesn’t appear, scan again or use Enter TV Address."
                )
            }

            Section("Where do I find my TV address?") {
                Text(
                    "Samsung: Settings → Connection or General → Network → Network Status → IP Settings.\n\nLG: Settings → Network → Wi-Fi Connection → your Wi-Fi network.\n\nGoogle TV: Settings → Network & Internet → your Wi-Fi network.\n\nMenu names can vary by model."
                )
            }

            Section("I pressed Deny on my Samsung TV") {
                Text(
                    "On the TV, open Settings → General (or General & Privacy) → External Device Manager → Device Connection Manager → Device List, remove Orbit, then return to Orbit, tap Reconnect, and choose Allow."
                )
            }

            Section("Why can’t Orbit turn my TV on?") {
                Text(
                    "If Orbit can’t reach a TV that is off, turn it on with the TV’s own remote or power button. Orbit will reconnect automatically when the TV becomes available."
                )
            }

            Section("I denied Local Network access") {
                Text(
                    "Open iPhone Settings → Orbit → Local Network and turn it on. Return to Orbit and it will search again automatically."
                )
            }
        }
        .navigationTitle("FAQ")
    }
}

struct PremiumView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID = PurchaseManager.monthlyID
    @State private var showReplaceConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    OrbitMark(size: 66)
                        .padding(.top, 12)

                    VStack(spacing: 7) {
                        Text("Orbit Pro")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Text("Make Orbit yours.")
                            .font(.largeTitle.bold())

                        Text("More TVs, your preferred layout, and the shortcuts you use most.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if let context =
                        appModel.proGateContextMessage {
                        VStack(spacing: 10) {
                            Text(context)
                                .font(.subheadline)
                                .multilineTextAlignment(.center)

                            if appModel
                                .canReplaceFreeTVWithPendingCandidate {
                                Button("Replace My Current TV") {
                                    showReplaceConfirmation = true
                                }
                                .font(.subheadline.weight(.semibold))
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(
                                cornerRadius: 16,
                                style: .continuous
                            )
                            .fill(Color.orbitSurface)
                        )
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        PremiumFeature(
                            icon: "tv.and.mediabox",
                            title: "Multiple TVs & Rooms",
                            detail: "Keep every TV ready and label each one by room."
                        )

                        PremiumFeature(
                            icon: "slider.horizontal.3",
                            title: "Custom Remote",
                            detail: "Choose your default control mode and keep only the controls you use."
                        )

                        PremiumFeature(
                            icon: "star",
                            title: "Favorites",
                            detail: "Keep favorite apps and inputs one tap away."
                        )
                    }

                    Text("The complete remote stays available on Free.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 10) {
                        planRow(
                            id: PurchaseManager.weeklyID,
                            badge: nil
                        )

                        planRow(
                            id: PurchaseManager.monthlyID,
                            badge: "Great Value"
                        )
                    }

                    Button(
                        selectedID == PurchaseManager.monthlyID
                        ? "Continue with Monthly"
                        : "Continue with Weekly"
                    ) {
                        guard let product = appModel.purchases.product(id: selectedID) else {
                            return
                        }

                        Task {
                            if await appModel.purchases.purchase(product) {
                                appModel.resumePendingProSelection()
                                dismiss()
                            }
                        }
                    }
                    .buttonStyle(OrbitPrimaryButtonStyle())
                    .disabled(
                        appModel.purchases.product(id: selectedID) == nil ||
                        appModel.purchases.isPurchasing
                    )
                    .overlay {
                        if appModel.purchases.isPurchasing {
                            ProgressView()
                                .tint(Color(uiColor: .systemBackground))
                        }
                    }

                    Text("Cancel anytime • Managed through Apple")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if appModel.purchases.isLoading &&
                        appModel.purchases.products.isEmpty {
                        ProgressView("Loading plans…")
                            .font(.footnote)
                    }

                    if appModel.purchases.purchasePending {
                        Text("Purchase pending approval. Orbit Pro will activate automatically when Apple completes it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if let error = appModel.purchases.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        if appModel.purchases.products.isEmpty,
                           !appModel.purchases.isLoading {
                            Button("Try Loading Prices Again") {
                                Task {
                                    await appModel.purchases.refresh()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Button("Restore Purchases") {
                        Task {
                            await appModel.purchases.restore()

                            if appModel.purchases.isPremium {
                                appModel.resumePendingProSelection()
                                dismiss()
                            }
                        }
                    }
                    .disabled(appModel.purchases.isPurchasing)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)

                    Text("Payment is charged to your Apple ID at confirmation. Subscriptions renew automatically until canceled at least 24 hours before the end of the current period. You can manage or cancel in your App Store subscription settings.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 16) {
                        NavigationLink("Terms") {
                            TermsOfServiceView()
                        }

                        NavigationLink("Privacy") {
                            PrivacyPolicyView()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(22)
            }
            .background(Color.orbitBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Replace your current Free TV?",
                isPresented: $showReplaceConfirmation,
                titleVisibility: .visible
            ) {
                Button("Replace TV", role: .destructive) {
                    if appModel
                        .replaceFreeTVWithPendingCandidate() {
                        dismiss()
                    }
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Orbit will forget your current Free TV and use \(appModel.pendingProCandidateName ?? "this TV") instead. You can add multiple TVs with Orbit Pro."
                )
            }
            .task {
                await appModel.purchases.refreshForForeground()
            }
            .onDisappear {
                appModel.clearPendingProSelection()
            }
        }
    }

    @ViewBuilder
    private func planRow(
        id: String,
        badge: String?
    ) -> some View {
        let product = appModel.purchases.product(id: id)

        Button {
            selectedID = id
            Haptics.shared.selection()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selectedID == id ? "largecircle.fill.circle" : "circle")
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(id == PurchaseManager.weeklyID ? "Weekly" : "Monthly")
                        .font(.headline)

                    if let product {
                        Text(
                            "\(product.displayPrice) / \(id == PurchaseManager.weeklyID ? "week" : "month")"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("Loading price…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let badge {
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.orbitSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        selectedID == id ? Color.primary : Color.orbitSeparator,
                        lineWidth: selectedID == id ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(OrbitPressStyle(cornerRadius: 18))
        .foregroundStyle(.primary)
        .disabled(product == nil || appModel.purchases.isPurchasing)
    }
}

private struct PremiumFeature: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .frame(width: 24)
                .font(.headline)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            LegalDocument(
                title: "Privacy Policy",
                updated: "October 6, 2026",
                sections: [
                    (
                        "1. Overview",
                        "Orbit is designed to control supported televisions on your local network. Orbit does not require an Orbit account."
                    ),
                    (
                        "2. Local Network Access",
                        "Orbit uses local network access to discover supported televisions and send remote-control commands. These commands stay on your local network and are not routed through an Orbit remote-control server."
                    ),
                    (
                        "3. Information We Do Not Collect",
                        "Orbit does not require your name, profile, or account to use the core remote. Device pairing credentials, when required, are stored on your device."
                    ),
                    (
                        "4. Purchases",
                        "Subscriptions are processed by Apple through the App Store and StoreKit. Orbit does not receive your full payment-card information."
                    ),
                    (
                        "5. Support",
                        "If you contact Orbit through the support method listed on the App Store product page, information you voluntarily send may be used to respond to your request."
                    ),
                    (
                        "6. Controller",
                        "Controller: the Orbit developer identified on the App Store product page.\nSupport: use the contact method listed on Orbit’s App Store product page."
                    )
                ]
            )
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            LegalDocument(
                title: "Terms of Service",
                updated: "October 6, 2026",
                sections: [
                    (
                        "1. Acceptance of Terms",
                        "By using Orbit, you agree to these Terms of Service."
                    ),
                    (
                        "2. Description of Service",
                        "Orbit provides local remote-control functionality for compatible smart televisions and streaming TV devices on your Wi-Fi network."
                    ),
                    (
                        "3. Compatibility",
                        "Compatibility can vary by manufacturer, model, firmware, television settings, and local network configuration."
                    ),
                    (
                        "4. Subscriptions",
                        "Paid subscriptions are offered through Apple’s App Store. Available pricing and billing terms are shown before purchase. Orbit offers weekly and monthly subscription options where available."
                    ),
                    (
                        "5. Availability",
                        "Local network conditions and television state can affect whether commands are delivered. Orbit cannot guarantee continuous connectivity to third-party television software."
                    ),
                    (
                        "6. Contact",
                        "Controller: the Orbit developer identified on the App Store product page.\nSupport: use the contact method listed on Orbit’s App Store product page."
                    )
                ]
            )
        }
        .navigationTitle("Terms of Service")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AcknowledgementsView: View {
    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 18
            ) {
                Text("Third-Party Software")
                    .font(.largeTitle.bold())

                Text("AndroidTVRemoteControl")
                    .font(.headline)

                Text(
                    "Copyright © 2023 Roman Odyshew"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Text(
                    "Orbit uses AndroidTVRemoteControl for Google / Android TV Remote Service v2 session and wire-protocol support. The package is pinned to a reviewed revision and distributed under the MIT License."
                )
                .font(.body)
                .foregroundStyle(.secondary)

                Text(mitLicense)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }
            .padding(22)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var mitLicense: String {
        """
        MIT License

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
    }
}

private struct LegalDocument: View {
    let title: String
    let updated: String
    let sections: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(title)
                .font(.largeTitle.bold())

            Text("Last updated: \(updated)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 7) {
                    Text(section.0)
                        .font(.headline)

                    Text(section.1)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
