import SwiftUI

struct OnboardingFlowView: View {
    @AppStorage(AppSettings.Keys.onboardingCompleted) private var onboardingCompleted = false
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
                ForEach(0..<count, id: .self) { index in
                    Circle()
                        .fill(index == page ? Color.primary : Color.secondary.opacity(0.25))
                        .frame(width: 6, height: 6)
                        .animation(.easeInOut(duration: 0.18), value: page)
                }
            }
            .padding(.bottom, 20)

            Button(page == count - 1 ? "Find My TV" : "Continue") {
                Haptics.shared.selection()

                if page < count - 1 {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        page += 1
                    }
                } else {
                    onboardingCompleted = true
                }
            }
            .buttonStyle(OrbitPrimaryButtonStyle())
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

            VStack(alignment: .leading, spacing: 18) {
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
            DPadView(onCommand: { _ in })
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
                .background(Color.orbitSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

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
            title: "Works on your local network.",
            subtitle: "Orbit connects directly to supported TVs over Wi-Fi."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                FeatureLine(icon: "wifi", text: "Commands stay on your local network.")
                FeatureLine(icon: "person.crop.circle.badge.xmark", text: "No account required.")
                FeatureLine(icon: "shield", text: "No ads and no remote-command cloud relay.")
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
        VStack(spacing: 20) {
            Spacer(minLength: 48)
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
        HStack(spacing: 14) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.primary)

            Text(text)
                .font(.subheadline)

            Spacer(minLength: 0)
        }
    }
}

struct OrbitMark: View {
    var size: CGFloat = 92

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary, lineWidth: max(5, size * 0.075))
                .frame(width: size, height: size)

            Circle()
                .fill(Color.primary)
                .frame(width: size * 0.18, height: size * 0.18)
        }
        .accessibilityHidden(true)
    }
}
