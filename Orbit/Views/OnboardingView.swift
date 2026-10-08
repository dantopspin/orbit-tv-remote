import SwiftUI

struct OnboardingFlowView: View {
    @AppStorage(AppSettings.Keys.onboardingCompleted) private var onboardingCompleted = false
    @AppStorage(AppSettings.Keys.tvSetupDeferred) private var tvSetupDeferred = true
    @State private var page = 0

    private let count = 4

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                WelcomePage().tag(0)
                NavigationTutorialPage().tag(1)
                KeyboardTutorialPage().tag(2)
                LocalNetworkPage().tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 7) {
                ForEach(0..<count, id: \.self) { index in
                    Circle()
                        .fill(index == page ? Color.primary : Color.secondary.opacity(0.25))
                        .frame(width: 6, height: 6)
                        .animation(.easeInOut(duration: 0.18), value: page)
                }
            }
            .padding(.bottom, 20)

            VStack(spacing: 10) {
                Button(page == count - 1 ? "Set Up My TV" : "Continue") {
                    Haptics.shared.selection()

                    if page < count - 1 {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            page += 1
                        }
                    } else {
                        tvSetupDeferred = false
                        onboardingCompleted = true
                    }
                }
                .buttonStyle(OrbitPrimaryButtonStyle())

                if page == count - 1 {
                    Button("Later") {
                        Haptics.shared.selection()
                        tvSetupDeferred = true
                        onboardingCompleted = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .accessibilityHint(
                        "Finish setup later from Orbit."
                    )
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
        }
        .background(Color.orbitBackground)
    }
}

private struct WelcomePage: View {
    var body: some View {
        OnboardingPage(
            title: "Welcome to Orbit",
            subtitle: "Your TV remote, on iPhone."
        ) {
            OrbitMark(size: 116)
                .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 10) {
                FeatureLine(icon: "iphone", text: "A simple, powerful remote for your TV.")
                FeatureLine(icon: "person.crop.circle.badge.xmark", text: "No account required.")
                FeatureLine(icon: "wifi", text: "Works on your local network.")
            }
            .frame(maxWidth: 300)
        }
    }
}

private struct NavigationTutorialPage: View {
    var body: some View {
        OnboardingPage(
            title: "Easy to navigate",
            subtitle: "Use the D-pad or touchpad to move around your TV."
        ) {
            DPadView(onCommand: { _, _ in })
                .frame(width: 225, height: 225)
                .allowsHitTesting(false)
        }
    }
}

private struct KeyboardTutorialPage: View {
    var body: some View {
        OnboardingPage(
            title: "Type with ease",
            subtitle: "Use your iPhone keyboard to type on your TV."
        ) {
            VStack(spacing: 14) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("Search on TV…")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
                .orbitRaisedPanel(
                    cornerRadius: 16
                )

                Image(systemName: "keyboard")
                    .font(.system(size: 74, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(height: 130)
            }
            .frame(maxWidth: 300)
        }
    }
}

private struct LocalNetworkPage: View {
    var body: some View {
        OnboardingPage(
            title: "Connect to your TV",
            subtitle: "Next, your iPhone will ask for Local Network access."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                FeatureLine(
                    icon: "checkmark.circle",
                    text: "Tap Allow so Orbit can find your TV."
                )
                FeatureLine(
                    icon: "tv",
                    text: "Supports Samsung Tizen, LG webOS, and Google TV / Android TV."
                )
                FeatureLine(
                    icon: "wifi",
                    text: "Your iPhone and TV need to be on the same Wi-Fi."
                )
                FeatureLine(
                    icon: "lock.shield",
                    text: "Remote commands stay on your Wi-Fi."
                )
            }
            .frame(maxWidth: 310)
        }
    }
}

private struct OnboardingPage<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 40)
            content

            Text(title)
                .font(.system(size: 30, weight: .bold, design: .default))
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)

            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

private struct FeatureLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 15,
                        weight: .semibold
                    )
                )
                .frame(
                    width: 34,
                    height: 34
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
                .foregroundStyle(.primary)

            Text(text)
                .font(
                    .subheadline.weight(.medium)
                )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .orbitRaisedPanel(
            cornerRadius: 17,
            shadowOpacity: 0.035
        )
    }
}

struct OrbitMark: View {
    var size: CGFloat = 92

    var body: some View {
        Canvas { context, canvasSize in
            let diameter = min(
                canvasSize.width,
                canvasSize.height
            )
            let center = CGPoint(
                x: canvasSize.width / 2,
                y: canvasSize.height / 2
            )
            let orbitRadius = diameter * 0.42
            let orbitWidth = diameter * 0.155
            let centerDiameter = diameter * 0.335

            let centerRect = CGRect(
                x: center.x - centerDiameter / 2,
                y: center.y - centerDiameter / 2,
                width: centerDiameter,
                height: centerDiameter
            )

            context.fill(
                Path(ellipseIn: centerRect),
                with: .color(.primary)
            )

            for quarterTurn in 0..<4 {
                var segment = Path()
                let rotation = Double(
                    quarterTurn * 90
                )

                segment.addArc(
                    center: center,
                    radius: orbitRadius,
                    startAngle: .degrees(
                        -119 + rotation
                    ),
                    endAngle: .degrees(
                        -61 + rotation
                    ),
                    clockwise: false
                )

                context.stroke(
                    segment,
                    with: .color(.primary),
                    style: StrokeStyle(
                        lineWidth: orbitWidth,
                        lineCap: .round
                    )
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
