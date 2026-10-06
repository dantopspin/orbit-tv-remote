import SwiftUI
import StoreKit

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(.dismiss) private var dismiss

    @AppStorage(AppSettings.Keys.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(AppSettings.Keys.keepScreenAwake) private var keepScreenAwake = true
    @AppStorage(AppSettings.Keys.darkMode) private var darkMode = false

    @State private var showPremium = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Haptic Feedback", isOn: $hapticsEnabled)
                    Toggle("Keep Screen Awake", isOn: $keepScreenAwake)
                    Toggle("Dark Mode", isOn: $darkMode)
                }
                .tint(.primary)

                Section("Plan") {
                    HStack {
                        Text("Current plan")
                        Spacer()
                        Text(appModel.purchases.isPremium ? "Premium" : "Free")
                            .foregroundStyle(.secondary)
                    }

                    Button("View Plans") {
                        showPremium = true
                    }

                    Button("Restore Purchases") {
                        Task {
                            await appModel.purchases.restore()
                        }
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
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0 (1)")
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
        }
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
                Text("Make sure the TV is powered on, connected to the same Wi-Fi network, and allows local control or mobile remote access in its settings.")
            }
        }
        .navigationTitle("FAQ")
    }
}

struct PremiumView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(.dismiss) private var dismiss
    @State private var selectedID = PurchaseManager.monthlyID

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    OrbitMark(size: 66)
                        .padding(.top, 12)

                    VStack(spacing: 6) {
                        Text("Orbit Premium")
                            .font(.largeTitle.bold())

                        Text("More control for homes with more than one TV.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        PremiumFeature(
                            icon: "tv.and.mediabox",
                            title: "Multiple TVs & Rooms",
                            detail: "Save and switch between all your TVs."
                        )

                        PremiumFeature(
                            icon: "slider.horizontal.3",
                            title: "Custom Remote",
                            detail: "Arrange controls and pin the things you use most."
                        )

                        PremiumFeature(
                            icon: "square.grid.2x2",
                            title: "Favorite Apps & Inputs",
                            detail: "Keep your most-used destinations close."
                        )
                    }

                    VStack(spacing: 10) {
                        planRow(
                            id: PurchaseManager.weeklyID,
                            fallback: "$3.99 / week",
                            badge: nil
                        )

                        planRow(
                            id: PurchaseManager.monthlyID,
                            fallback: "$7.99 / month",
                            badge: "Best value"
                        )
                    }

                    Button("Continue") {
                        guard let product = appModel.purchases.product(id: selectedID) else {
                            return
                        }

                        Task {
                            await appModel.purchases.purchase(product)
                        }
                    }
                    .buttonStyle(OrbitPrimaryButtonStyle())
                    .disabled(appModel.purchases.product(id: selectedID) == nil)

                    Button("Restore Purchases") {
                        Task {
                            await appModel.purchases.restore()
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)

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
        }
    }

    @ViewBuilder
    private func planRow(
        id: String,
        fallback: String,
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

                    Text(
                        product.map {
                            "\($0.displayPrice) / \(id == PurchaseManager.weeklyID ? "week" : "month")"
                        } ?? fallback
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                        "If you contact [email], information you voluntarily send may be used to respond to your request."
                    ),
                    (
                        "6. Controller",
                        "Controller: [Your Name / Company]\nContact: [email]"
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
                        "Paid subscriptions are offered through Apple’s App Store. Available pricing and billing terms are shown before purchase. Orbit currently plans weekly and monthly subscription options."
                    ),
                    (
                        "5. Availability",
                        "Local network conditions and television state can affect whether commands are delivered. Orbit cannot guarantee continuous connectivity to third-party television software."
                    ),
                    (
                        "6. Contact",
                        "Controller: [Your Name / Company]\nContact: [email]"
                    )
                ]
            )
        }
        .navigationTitle("Terms of Service")
        .navigationBarTitleDisplayMode(.inline)
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

            ForEach(Array(sections.enumerated()), id: .offset) { _, section in
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
