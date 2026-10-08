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
                        NavigationLink {
                            CustomRemoteView()
                        } label: {
                            Label(
                                "Customize Remote",
                                systemImage:
                                    "slider.horizontal.3"
                            )
                        }
                    } else {
                        Button {
                            showPremium = true
                        } label: {
                            Label(
                                "Customize Remote",
                                systemImage:
                                    "slider.horizontal.3"
                            )
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
                    NavigationLink {
                        FAQView()
                    } label: {
                        Label(
                            "FAQ",
                            systemImage:
                                "questionmark.circle"
                        )
                    }

                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label(
                            "Privacy Policy",
                            systemImage:
                                "hand.raised"
                        )
                    }

                    NavigationLink {
                        TermsOfServiceView()
                    } label: {
                        Label(
                            "Terms of Service",
                            systemImage:
                                "doc.text"
                        )
                    }

                    NavigationLink {
                        AcknowledgementsView()
                    } label: {
                        Label(
                            "Acknowledgements",
                            systemImage:
                                "shippingbox"
                        )
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
            .scrollContentBackground(.hidden)
            .background(Color.orbitBackground)
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
        .scrollContentBackground(.hidden)
        .background(Color.orbitBackground)
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
        .scrollContentBackground(.hidden)
        .background(Color.orbitBackground)
        .navigationTitle("FAQ")
    }
}

private struct PaywallLayout {
    let availableHeight: CGFloat
    let constrained: Bool
    let fillsAvailableHeight: Bool

    private var progress: CGFloat {
        guard !constrained else { return 0 }

        return min(
            max(
                (availableHeight - 560) / 280,
                0
            ),
            1
        )
    }

    var horizontalPadding: CGFloat {
        constrained ? 16 : 18 + (4 * progress)
    }

    var verticalPadding: CGFloat {
        constrained ? 4 : 6 + (2 * progress)
    }

    var sectionMinimumGap: CGFloat {
        constrained ? 4 : 8 + (2 * progress)
    }

    var minorMinimumGap: CGFloat {
        constrained ? 3 : 5 + (2 * progress)
    }

    var headerSpacing: CGFloat {
        constrained ? 2 : 3 + (2 * progress)
    }

    var markSize: CGFloat {
        constrained ? 32 : 40 + (6 * progress)
    }

    var featureSpacing: CGFloat {
        constrained ? 4 : 6 + (4 * progress)
    }

    var planSpacing: CGFloat {
        constrained ? 5 : 7 + (2 * progress)
    }

    var purchaseSpacing: CGFloat {
        constrained ? 6 : 8 + (5 * progress)
    }

    var footerSpacing: CGFloat {
        constrained ? 1 : 2 + (4 * progress)
    }

    var planVerticalPadding: CGFloat {
        constrained ? 7 : 9 + (2 * progress)
    }

    var ctaHeight: CGFloat {
        constrained ? 46 : 48 + (4 * progress)
    }

}

struct PremiumView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var selectedID = PurchaseManager.monthlyID
    @State private var showReplaceConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    ScrollView {
                        paywallContent(
                            layout: PaywallLayout(
                                availableHeight: 0,
                                constrained: true,
                                fillsAvailableHeight: false
                            )
                        )
                    }
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    GeometryReader { proxy in
                        ViewThatFits(in: .vertical) {
                            paywallContent(
                                layout: PaywallLayout(
                                    availableHeight:
                                        proxy.size.height,
                                    constrained: false,
                                    fillsAvailableHeight: true
                                )
                            )

                            paywallContent(
                                layout: PaywallLayout(
                                    availableHeight:
                                        proxy.size.height,
                                    constrained: true,
                                    fillsAvailableHeight: true
                                )
                            )
                        }
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height,
                            alignment: .center
                        )
                    }
                }
            }
            .background(Color.orbitBackground)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
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
    private func paywallContent(
        layout: PaywallLayout
    ) -> some View {
        VStack(spacing: 0) {
            paywallHeader(layout: layout)

            sectionSpace(layout)

            if let context =
                appModel.proGateContextMessage {
                proGateContext(
                    context,
                    layout: layout
                )

                sectionSpace(layout)
            }

            premiumBenefits(layout: layout)

            sectionSpace(layout)

            freeReassurance(layout: layout)

            minorSpace(layout)

            plansSection(layout: layout)

            minorSpace(layout)

            purchaseButton(layout: layout)

            minorSpace(layout)

            purchaseMeta(layout: layout)

            sectionSpace(layout)

            paywallFooter(layout: layout)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight:
                layout.fillsAvailableHeight
                ? .infinity
                : nil,
            alignment: .top
        )
        .padding(
            .horizontal,
            layout.horizontalPadding
        )
        .padding(
            .vertical,
            layout.verticalPadding
        )
    }

    @ViewBuilder
    private func sectionSpace(
        _ layout: PaywallLayout
    ) -> some View {
        if layout.fillsAvailableHeight {
            Spacer(
                minLength:
                    layout.sectionMinimumGap
            )
        } else {
            Color.clear
                .frame(
                    height:
                        layout.sectionMinimumGap
                )
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func minorSpace(
        _ layout: PaywallLayout
    ) -> some View {
        if layout.fillsAvailableHeight {
            Spacer(
                minLength:
                    layout.minorMinimumGap
            )
        } else {
            Color.clear
                .frame(
                    height:
                        layout.minorMinimumGap
                )
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func paywallHeader(
        layout: PaywallLayout
    ) -> some View {
        VStack(spacing: layout.headerSpacing) {
            OrbitMark(size: layout.markSize)
                .padding(
                    .bottom,
                    layout.constrained ? 0 : 2
                )

            Text("Orbit Pro")
                .font(
                    layout.constrained
                    ? .caption.weight(.semibold)
                    : .subheadline.weight(.semibold)
                )
                .foregroundStyle(.secondary)

            Text("Get more from Orbit.")
                .font(
                    layout.constrained
                    ? .title3.bold()
                    : .title2.bold()
                )
                .multilineTextAlignment(.center)

            Text(
                "More TVs, custom controls, favorite shortcuts."
            )
            .font(
                layout.constrained
                ? .caption
                : .subheadline
            )
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.88)
        }
    }

    @ViewBuilder
    private func proGateContext(
        _ context: String,
        layout: PaywallLayout
    ) -> some View {
        VStack(
            spacing:
                layout.constrained ? 4 : 7
        ) {
            Text(context)
                .font(
                    layout.constrained
                    ? .caption2
                    : .caption
                )
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if appModel
                .canReplaceFreeTVWithPendingCandidate {
                Button("Replace My Current TV") {
                    showReplaceConfirmation = true
                }
                .font(
                    .caption.weight(.semibold)
                )
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(
            layout.constrained ? 7 : 10
        )
        .frame(maxWidth: .infinity)
        .orbitRaisedPanel(
            cornerRadius:
                layout.constrained ? 12 : 15,
            shadowOpacity: 0.035
        )
    }

    @ViewBuilder
    private func premiumBenefits(
        layout: PaywallLayout
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: layout.featureSpacing
        ) {
            PremiumFeature(
                icon: "tv.and.mediabox",
                title: "Multiple TVs & Rooms",
                compact: layout.constrained
            )

            PremiumFeature(
                icon: "slider.horizontal.3",
                title: "Custom Remote",
                compact: layout.constrained
            )

            PremiumFeature(
                icon: "star",
                title: "Favorites",
                compact: layout.constrained
            )
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }

    @ViewBuilder
    private func freeReassurance(
        layout: PaywallLayout
    ) -> some View {
        Text(
            "The complete remote stays available on Free."
        )
        .font(
            layout.constrained
            ? .caption2
            : .footnote
        )
        .foregroundStyle(.secondary)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }

    @ViewBuilder
    private func plansSection(
        layout: PaywallLayout
    ) -> some View {
        VStack(
            spacing: layout.planSpacing
        ) {
            planRow(
                id: PurchaseManager.weeklyID,
                badge: nil,
                layout: layout
            )

            planRow(
                id: PurchaseManager.monthlyID,
                badge: "Great Value",
                layout: layout
            )
        }
    }

    @ViewBuilder
    private func purchaseButton(
        layout: PaywallLayout
    ) -> some View {
        Button(
            selectedID ==
                PurchaseManager.monthlyID
            ? "Continue with Monthly"
            : "Continue with Weekly"
        ) {
            guard let product =
                    appModel.purchases.product(
                        id: selectedID
                    ) else {
                return
            }

            Task {
                if await appModel.purchases.purchase(
                    product
                ) {
                    appModel
                        .resumePendingProSelection()
                    dismiss()
                }
            }
        }
        .buttonStyle(
            OrbitPrimaryButtonStyle(
                height: layout.ctaHeight
            )
        )
        .disabled(
            appModel.purchases.product(
                id: selectedID
            ) == nil ||
            appModel.purchases.isPurchasing
        )
        .overlay {
            if appModel.purchases.isPurchasing {
                ProgressView()
                    .tint(
                        Color(
                            uiColor: .systemBackground
                        )
                    )
            }
        }
    }

    @ViewBuilder
    private func purchaseMeta(
        layout: PaywallLayout
    ) -> some View {
        VStack(
            spacing:
                layout.footerSpacing
        ) {
            Text(
                "Cancel anytime • Managed through Apple"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            purchaseStatus(
                compact: layout.constrained
            )
        }
    }

    @ViewBuilder
    private func paywallFooter(
        layout: PaywallLayout
    ) -> some View {
        VStack(
            spacing: layout.footerSpacing
        ) {
            Button("Restore Purchases") {
                Task {
                    await appModel.purchases.restore()

                    if appModel.purchases.isPremium {
                        appModel
                            .resumePendingProSelection()
                        dismiss()
                    }
                }
            }
            .disabled(
                appModel.purchases.isPurchasing
            )
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
            .contentShape(Rectangle())

            Text(
                "Charged to your Apple ID. Renews automatically unless canceled at least 24 hours before renewal. Manage in App Store Subscriptions."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(3)

            HStack(spacing: 20) {
                NavigationLink {
                    TermsOfServiceView()
                } label: {
                    Text("Terms")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }

                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    Text("Privacy")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func purchaseStatus(
        compact: Bool
    ) -> some View {
        if appModel.purchases.isLoading &&
            appModel.purchases.products.isEmpty {
            ProgressView("Loading plans…")
                .font(.caption)
        }

        if appModel.purchases.purchasePending {
            Text(
                compact
                ? "Purchase pending Apple approval."
                : "Purchase pending approval. Orbit Pro will activate automatically when Apple completes it."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(compact ? 1 : 2)
        }

        if let error =
            appModel.purchases.errorMessage {
            VStack(spacing: 4) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(compact ? 2 : 3)

                if appModel.purchases.products.isEmpty,
                   !appModel.purchases.isLoading {
                    Button("Try Loading Prices Again") {
                        Task {
                            await appModel
                                .purchases.refresh()
                        }
                    }
                    .font(
                        .caption.weight(.semibold)
                    )
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private func planRow(
        id: String,
        badge: String?,
        layout: PaywallLayout
    ) -> some View {
        let product =
            appModel.purchases.product(id: id)

        Button {
            selectedID = id
            Haptics.shared.selection()
        } label: {
            HStack(
                spacing:
                    layout.constrained ? 9 : 12
            ) {
                Image(
                    systemName:
                        selectedID == id
                        ? "largecircle.fill.circle"
                        : "circle"
                )
                .font(
                    layout.constrained
                    ? .body
                    : .title3
                )

                VStack(
                    alignment: .leading,
                    spacing:
                        layout.constrained ? 0 : 1
                ) {
                    Text(
                        id ==
                            PurchaseManager.weeklyID
                        ? "Weekly"
                        : "Monthly"
                    )
                    .font(
                        layout.constrained
                        ? .subheadline.weight(
                            .semibold
                        )
                        : .headline
                    )

                    if let product {
                        Text(
                            "\(product.displayPrice) / \(id == PurchaseManager.weeklyID ? "week" : "month")"
                        )
                        .font(
                            layout.constrained
                            ? .caption
                            : .subheadline
                        )
                        .foregroundStyle(.secondary)
                    } else {
                        Text("Loading price…")
                            .font(
                                layout.constrained
                                ? .caption
                                : .subheadline
                            )
                            .foregroundStyle(
                                .secondary
                            )
                    }
                }

                Spacer()

                if let badge {
                    Text(badge)
                        .font(
                            .caption.weight(
                                .semibold
                            )
                        )
                        .padding(
                            .horizontal,
                            layout.constrained
                            ? 8 : 10
                        )
                        .padding(
                            .vertical,
                            layout.constrained
                            ? 3 : 5
                        )
                        .background(
                            Capsule()
                                .fill(
                                    Color.primary
                                        .opacity(0.08)
                                )
                        )
                }
            }
            .padding(
                .horizontal,
                layout.constrained ? 13 : 16
            )
            .padding(
                .vertical,
                layout.planVerticalPadding
            )
            .background(
                RoundedRectangle(
                    cornerRadius:
                        layout.constrained
                        ? 15 : 18,
                    style: .continuous
                )
                .fill(Color.orbitSurface)
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius:
                        layout.constrained
                        ? 15 : 18,
                    style: .continuous
                )
                .stroke(
                    selectedID == id
                    ? Color.primary
                    : Color.orbitSeparator,
                    lineWidth:
                        selectedID == id
                        ? 1.5
                        : 0.5
                )
            )
            .shadow(
                color: Color.black.opacity(
                    selectedID == id
                    ? 0.055
                    : 0.035
                ),
                radius:
                    selectedID == id
                    ? 8
                    : 5,
                x: 0,
                y: 3
            )
        }
        .buttonStyle(
            OrbitPressStyle(
                cornerRadius:
                    layout.constrained ? 15 : 18
            )
        )
        .foregroundStyle(.primary)
        .disabled(
            product == nil ||
            appModel.purchases.isPurchasing
        )
    }
}

private struct PremiumFeature: View {
    let icon: String
    let title: String
    let compact: Bool

    var body: some View {
        HStack(
            alignment: .center,
            spacing: compact ? 10 : 12
        ) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: compact ? 14 : 16,
                        weight: .semibold
                    )
                )
                .frame(
                    width: compact ? 30 : 34,
                    height: compact ? 30 : 34,
                    alignment: .center
                )
                .background(
                    Circle()
                        .fill(
                            Color.primary.opacity(0.045)
                        )
                )
                .overlay(
                    Circle()
                        .stroke(
                            Color.primary.opacity(0.07),
                            lineWidth: 0.7
                        )
                )

            Text(title)
                .font(
                    compact
                    ? .subheadline.weight(.semibold)
                    : .headline
                )

            Spacer(minLength: 0)
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
        .background(Color.orbitBackground)
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
        .background(Color.orbitBackground)
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
        .background(Color.orbitBackground)
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
