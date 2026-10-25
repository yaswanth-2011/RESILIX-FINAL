import SwiftUI

/// Paywall shown once when the app is first opened.
///
/// Matches Resilix's existing dark liquid-glass design: pure black
/// background, cyan brand accents, liquid-glass cards, white text.
/// A "Skip for now" button lets the user enter the app without
/// subscribing, so the paywall never blocks usage.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    let onDismiss: () -> Void

    @State private var selectedPlan: String? = nil

    /// Subscription tiers shown on the paywall.
    private struct Plan: Identifiable, Hashable {
        let id: String
        let title: String
        let subtitle: String
        let price: String
        let period: String
        let features: [String]
        let isPopular: Bool
    }

    private let plans: [Plan] = [
        Plan(
            id: "monthly",
            title: "Monthly",
            subtitle: "Flexible, cancel anytime.",
            price: "$4.99",
            period: "/month",
            features: [
                "Offline mesh networking",
                "Offline first-aid AI",
                "Offline maps (MBTiles)",
                "Peer-to-peer chats"
            ],
            isPopular: false
        ),
        Plan(
            id: "yearly",
            title: "Yearly",
            subtitle: "Best value — save 40%.",
            price: "$49.99",
            period: "/year",
            features: [
                "Offline mesh networking",
                "Offline first-aid AI",
                "Offline maps (MBTiles)",
                "Peer-to-peer chats",
                "Priority relay routing"
            ],
            isPopular: true
        ),
        Plan(
            id: "lifetime",
            title: "Lifetime",
            subtitle: "One-time payment, own it forever.",
            price: "$99.99",
            period: "",
            features: [
                "Offline mesh networking",
                "Offline first-aid AI",
                "Offline maps (MBTiles)",
                "Peer-to-peer chats",
                "Priority relay routing",
                "All future updates"
            ],
            isPopular: false
        )
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header — matches the big dark logo style of the welcome flow.
                VStack(spacing: 16) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(ResilixTheme.brandCyan)
                    Text("Resilix Pro")
                        .font(ResilixTheme.font(34, .bold))
                        .foregroundStyle(.white)
                    Text("Unlock offline mesh, AI, maps and chats — no internet required.")
                        .font(ResilixTheme.font(14, .regular))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 44)
                }
                .padding(.top, 50)
                .padding(.bottom, 34)

                // Plans
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        ForEach(plans) { plan in
                            PlanCard(
                                plan: plan,
                                isSelected: selectedPlan == plan.id,
                                onSelect: { selectedPlan = plan.id }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }

                // Subscribe button — cyan, same style as auth primary buttons.
                Button {
                    // StoreKit purchase would go here; for now dismiss the paywall.
                    onDismiss()
                } label: {
                    Text(selectedPlan == nil ? "Subscribe" : "Subscribe to \(selectedPlan ?? "")")
                        .font(ResilixTheme.font(17, .semibold))
                        .tracking(0.4)
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(ResilixTheme.brandCyan)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            LinearGradient(
                                colors: [Color.white.opacity(0.45), Color.white.opacity(0.0)],
                                startPoint: .top, endPoint: .center
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .blendMode(.overlay)
                        )
                        .liquidGlassRounded(cornerRadius: 18, interactive: true)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)

                // Skip for now — ghost text button, same style as "Continue as Guest".
                Button {
                    onDismiss()
                } label: {
                    Text("Skip for now")
                        .font(ResilixTheme.font(15, .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                .padding(.top, 12)
                .padding(.bottom, 34)
                .accessibilityLabel(Text("Skip for now"))
            }
        }
    }

    // MARK: - Plan Card (liquid glass, same style as Assist / Nearby cards)

    private struct PlanCard: View {
        let plan: Plan
        let isSelected: Bool
        let onSelect: () -> Void

        var body: some View {
            Button(action: onSelect) {
                cardContent
            }
            .buttonStyle(.plain)
        }

        @ViewBuilder
        private var cardContent: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(plan.title)
                        .font(ResilixTheme.font(17, .semibold))
                        .foregroundStyle(.white)
                    if plan.isPopular {
                        Text("Popular")
                            .font(ResilixTheme.font(10, .bold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(ResilixTheme.brandCyan)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isSelected ? ResilixTheme.brandCyan : Color.white.opacity(0.25))
                }
                Text(plan.subtitle)
                    .font(ResilixTheme.font(13, .regular))
                    .foregroundStyle(Color.white.opacity(0.5))
                HStack(alignment: .center, spacing: 4) {
                    Text(plan.price)
                        .font(ResilixTheme.font(34, .bold))
                        .foregroundStyle(.white)
                    if !plan.period.isEmpty {
                        Text(plan.period)
                            .font(ResilixTheme.font(13, .regular))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(plan.features, id: \.self) { feature in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(ResilixTheme.brandCyan)
                            Text(feature)
                                .font(ResilixTheme.font(13, .regular))
                                .foregroundStyle(Color.white.opacity(0.85))
                        }
                    }
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(isSelected ? ResilixTheme.brandCyan.opacity(0.5) : Color.white.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
                    )
            )
            .liquidGlassRounded(cornerRadius: 20, interactive: true)
        }
    }
}

#Preview {
    PaywallView(onDismiss: {})
        .environmentObject(ResilixAppModel())
}
