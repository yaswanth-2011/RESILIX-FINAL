import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var app: ResilixAppModel
    @State private var page = 0
    @State private var meshAnimating = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Subtle animated mesh background
            GeometryReader { geo in
                ZStack {
                    // Faint connections
                    Path { p in
                        p.move(to: CGPoint(x: geo.size.width*0.2, y: geo.size.height*0.3))
                        p.addLine(to: CGPoint(x: geo.size.width*0.5, y: geo.size.height*0.35))
                        p.addLine(to: CGPoint(x: geo.size.width*0.8, y: geo.size.height*0.3))
                        p.addLine(to: CGPoint(x: geo.size.width*0.65, y: geo.size.height*0.45))
                        p.addLine(to: CGPoint(x: geo.size.width*0.35, y: geo.size.height*0.42))
                    }.stroke(ResilixTheme.brandCyan.opacity(0.12), lineWidth: 0.6)

                    // Nodes
                    ForEach(0..<6, id: \.self) { i in
                        let angle = Double(i) * (360.0/6) * .pi/180 - 90 * .pi/180
                        Circle()
                            .fill(ResilixTheme.brandCyan.opacity(0.18))
                            .frame(width: 3, height: 3)
                            .position(x: geo.size.width/2 + cos(angle) * 80,
                                      y: geo.size.height/2 + sin(angle) * 80)
                    }
                }
                .ignoresSafeArea()
            }
            .onAppear { meshAnimating = true }

            VStack(spacing: 0) {
                // Page content
                TabView(selection: $page) {
                    OnboardPage1()
                        .tag(0)
                    OnboardPage2()
                        .tag(1)
                    OnboardPage3()
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)

                // Bottom controls
                VStack(spacing: 16) {
                    // Page indicator
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { idx in
                            Circle()
                                .fill(page == idx ? ResilixTheme.brandCyan : Color.white.opacity(0.15))
                                .frame(width: page == idx ? 10 : 7, height: page == idx ? 10 : 7)
                                .animation(.easeOut(duration: 0.25), value: page)
                        }
                    }
                    .padding(.bottom, 8)

                    HStack(spacing: 16) {
                        Button {
                            complete()
                        } label: {
                            Text(L("SKIP"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.55))
                        }
                        .accessibilityLabel(Text(L("Skip onboarding")))

                        Button {
                            if page < 2 {
                                withAnimation(.easeOut(duration: 0.3)) { page += 1 }
                            } else {
                                complete()
                            }
                        } label: {
                            Text(page < 2 ? L("NEXT") : L("GET STARTED"))
                                .font(.system(size: 15, weight: .heavy))
                                .tracking(0.5)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(
                                        colors: [ResilixTheme.brandCyan, ResilixTheme.brandTeal],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .accessibilityLabel(page < 2 ? Text(L("Next page")) : Text(L("Get started")))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 34)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

    func complete() {
        var s = app.settings
        s.onboardingCompleted = true
        app.settings = s
        Task { try? await app.persistence.saveSettings(s) }
        dismiss()
    }
}

// MARK: - Onboarding Pages

private struct OnboardPage1: View {
    @State private var pulse = false
    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // 3D mesh visualization
            GeometryReader { geo in
                ZStack {
                    // Connections
                    Path { p in
                        let center = CGPoint(x: geo.size.width/2, y: geo.size.height/2)
                        let nodes = [
                            CGPoint(x: geo.size.width*0.5, y: geo.size.height*0.35),
                            CGPoint(x: geo.size.width*0.25, y: geo.size.height*0.55),
                            CGPoint(x: geo.size.width*0.75, y: geo.size.height*0.55),
                            CGPoint(x: geo.size.width*0.5, y: geo.size.height*0.75),
                        ]
                        for node in nodes {
                            p.move(to: center)
                            p.addLine(to: node)
                        }
                    }.stroke(ResilixTheme.brandCyan.opacity(0.18), lineWidth: 1)

                    // Nodes
                    ForEach(0..<4, id: \.self) { i in
                        let angle = Double(i) * 90 * .pi/180 - 90 * .pi/180
                        let x = geo.size.width/2 + cos(angle) * 100
                        let y = geo.size.height/2 + sin(angle) * 100
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(ResilixTheme.separator.opacity(0.3), lineWidth: 1))
                            .overlay(
                                Image(systemName: "iphone")
                                    .font(.caption)
                                    .foregroundStyle(ResilixTheme.brandTeal)
                            )
                            .position(x: x, y: y)
                    }

                    // Center YOU node
                    VStack(spacing: 4) {
                        ZStack {
                            Circle().fill(ResilixTheme.brandNavy).frame(width: 44, height: 44)
                                .shadow(color: ResilixTheme.brandNavy.opacity(0.3), radius: 8)
                            Image(systemName: "shield.lefthalf.filled").font(.title3).foregroundStyle(.white)
                        }
                        Text(L("YOU")).font(.caption2.weight(.heavy)).tracking(0.6).foregroundStyle(.white)
                    }
                    .position(x: geo.size.width/2, y: geo.size.height/2)
                }
                .onAppear { pulse = true }
            }
            .frame(height: 280)

            Spacer(minLength: 20)

            VStack(spacing: 12) {
                Text(L("MEET RESILIX"))
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(L("Communicate with nearby people even when normal networks are unavailable."))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            .padding(.horizontal, 24)
        }
    }
}

private struct OnboardPage2: View {
    @State private var packetProgress: CGFloat = 0

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // Animated routing
            GeometryReader { geo in
                ZStack {
                    // Path
                    Path { p in
                        let points = [
                            CGPoint(x: geo.size.width*0.15, y: geo.size.height*0.5),
                            CGPoint(x: geo.size.width*0.35, y: geo.size.height*0.35),
                            CGPoint(x: geo.size.width*0.65, y: geo.size.height*0.35),
                            CGPoint(x: geo.size.width*0.85, y: geo.size.height*0.5),
                        ]
                        p.move(to: points[0])
                        for pt in points.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 12], dashPhase: 0))
                    .foregroundStyle(ResilixTheme.brandCyan.opacity(0.25))

                    // Moving packet
                    Circle()
                        .fill(ResilixTheme.brandCyan)
                        .frame(width: 10, height: 10)
                        .shadow(color: ResilixTheme.brandCyan, radius: 8)
                        .position(
                            x: lerp(geo.size.width*0.15, geo.size.width*0.85, packetProgress),
                            y: interpolateY(packetProgress, height: geo.size.height)
                        )
                        .animation(.linear(duration: 3.0).repeatForever(autoreverses: false), value: packetProgress)

                    // Nodes
                    let nodes = [
                        ("YOU", geo.size.width*0.15, geo.size.height*0.5),
                        (L("Device A"), geo.size.width*0.35, geo.size.height*0.35),
                        (L("Device B"), geo.size.width*0.65, geo.size.height*0.35),
                        ("RECIPIENT", geo.size.width*0.85, geo.size.height*0.5),
                    ]
                    ForEach(0..<nodes.count, id: \.self) { i in
                        let (label, x, y) = nodes[i]
                        VStack(spacing: 4) {
                            Circle()
                                .fill(i == 0 || i == 3 ? ResilixTheme.brandNavy : ResilixTheme.textSecondary.opacity(0.3))
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Image(systemName: i == 0 ? "shield.lefthalf.filled" : "iphone")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(i == 0 || i == 3 ? .white : ResilixTheme.brandTeal)
                                )
                            Text(label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        .position(x: x, y: y)
                    }
                }
                .onAppear {
                    withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                        packetProgress = 1.0
                    }
                }
            }
            .frame(height: 220)

            Spacer(minLength: 16)

            VStack(spacing: 10) {
                Text(L("YOUR DEVICES BECOME THE NETWORK"))
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(L("Messages can travel from device to device using available relay paths."))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            .padding(.horizontal, 24)
        }
    }

    private func interpolateY(_ t: CGFloat, height: CGFloat) -> CGFloat {
        let y1: CGFloat = 0.5
        let y2: CGFloat = 0.35
        let y3: CGFloat = 0.35
        let y4: CGFloat = 0.5
        let fraction: CGFloat
        if t < 0.33 { fraction = lerp(y1, y2, t/0.33) }
        else if t < 0.66 { fraction = lerp(y2, y3, (t-0.33)/0.33) }
        else { fraction = lerp(y3, y4, (t-0.66)/0.34) }
        return fraction * height
    }
}

private struct OnboardPage3: View {
    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 16) {
                ZStack {
                    Circle().fill(ResilixTheme.brandCyan.opacity(0.12)).frame(width: 100, height: 100)
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(ResilixTheme.brandCyan)
                }

                Text(L("NO INTERNET REQUIRED"))
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(L("Resilix can communicate through nearby devices when Wi-Fi and mobile data aren't available."))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                // handled by parent
            } label: {
                Text(L("GET STARTED"))
                    .font(.system(size: 15, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [ResilixTheme.brandCyan, ResilixTheme.brandTeal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
}

// Helper
private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * t
}

#Preview {
    OnboardingView().environmentObject(ResilixAppModel())
}
