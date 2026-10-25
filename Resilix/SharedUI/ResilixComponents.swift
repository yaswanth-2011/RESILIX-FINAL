import SwiftUI

// MARK: - Reusable component kit
// Small composable components only. Native controls are preferred elsewhere.

struct ResilixCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(ResilixTheme.space16)
            .background(ResilixTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusMedium)
                    .stroke(ResilixTheme.separator, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
            .shadow(color: ResilixTheme.cyanGlow, radius: 6, x: 0, y: 0)
            .padding(.horizontal, ResilixTheme.space16)
    }
}

struct ResilixSectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(ResilixTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

struct ResilixStatusBadge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, ResilixTheme.space8)
            .padding(.vertical, ResilixTheme.space4)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusSmall))
            .accessibilityLabel(text)
    }
}

struct MeshStatusIndicator: View {
    let connected: Bool
    var body: some View {
        HStack(spacing: ResilixTheme.space4) {
            Circle()
                .fill(connected ? ResilixTheme.brandTeal : ResilixTheme.textTertiary)
                .frame(width: 8, height: 8)
            Text(connected ? L("Connected") : L("Offline"))
                .font(.caption)
                .foregroundStyle(ResilixTheme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(connected ? Text(L("Mesh connected")) : Text(L("Mesh offline")))
    }
}

struct ResilixPrimaryButton: View {
    let title: String
    var isDestructive: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isDestructive ? ResilixTheme.emergencyRed : ResilixTheme.brandTeal)
                .clipShape(RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusMedium))
                .shadow(color: (isDestructive ? ResilixTheme.emergencyRed : ResilixTheme.brandCyan).opacity(0.35), radius: 8, x: 0, y: 3)
                .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct ResilixSecondaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ResilixTheme.brandTeal)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusMedium)
                        .stroke(ResilixTheme.brandTeal, lineWidth: 1)
                )
                .shadow(color: ResilixTheme.cyanGlow, radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct ResilixRow: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var body: some View {
        HStack(spacing: ResilixTheme.space12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(ResilixTheme.brandTeal)
                    .frame(width: 24)
            }
            VStack(alignment: .leading, spacing: ResilixTheme.space4) {
                Text(title).font(.subheadline).foregroundStyle(ResilixTheme.textPrimary)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(ResilixTheme.textSecondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(ResilixTheme.textTertiary)
        }
        .padding(.vertical, ResilixTheme.space8)
        .contentShape(Rectangle())
    }
}

struct EmptyStateView: View {
    let title: String
    let subtitle: String
    let icon: String
    var body: some View {
        VStack(spacing: ResilixTheme.space12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(ResilixTheme.brandSlate)
            Text(title).font(.headline).foregroundStyle(ResilixTheme.textPrimary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(ResilixTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(ResilixTheme.space32)
        .accessibilityElement(children: .combine)
    }
}

struct ErrorStateView: View {
    let message: String
    var retryLabel: String { L("Retry") }
    let retry: () -> Void
    var body: some View {
        VStack(spacing: ResilixTheme.space8) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(ResilixTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button(retryLabel, action: retry)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ResilixTheme.brandTeal)
                .frame(minHeight: 44)
        }
        .padding(ResilixTheme.space12)
        .accessibilityElement(children: .contain)
    }
}

struct LoadingStateView: View {
    var body: some View {
        HStack(spacing: ResilixTheme.space8) {
            ProgressView()
            Text(L("Loading…"))
                .font(.subheadline)
                .foregroundStyle(ResilixTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(ResilixTheme.space16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(L("Loading")))
    }
}

struct SeverityBadge: View {
    let severity: SOSSeverity
    private var color: Color {
        switch severity {
        case .critical: return ResilixTheme.emergencyRed
        case .high: return ResilixTheme.brandAmber
        case .moderate: return ResilixTheme.warningYellow
        case .low: return ResilixTheme.brandSlate
        }
    }
    var body: some View {
        ResilixStatusBadge(text: severity.label, color: color)
            .accessibilityLabel(L("ui.severity") + " \(severity.label)")
    }
}

struct DeliveryStateView: View {
    let state: DeliveryState
    private var color: Color {
        switch state {
        case .delivered: return ResilixTheme.successGreen
        case .relaying, .sending, .queued: return ResilixTheme.brandTeal
        case .failed, .expired: return ResilixTheme.brandAmber
        case .cancelled, .draft: return ResilixTheme.textTertiary
        }
    }
    var body: some View {
        ResilixStatusBadge(text: state.label, color: color)
    }
}

// Compact static route path: A -> B -> C with thin connectors.
struct RoutePathView: View {
    let hops: [String]
    var isSimulated: Bool = false
    var animating: Bool = false

    var body: some View {
        HStack(spacing: ResilixTheme.space8) {
            ForEach(Array(hops.enumerated()), id: \.offset) { index, hop in
                VStack(spacing: ResilixTheme.space4) {
                    Circle()
                        .fill(isSimulated ? ResilixTheme.brandAmber : ResilixTheme.brandTeal)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(hop)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                        )
                    if index == 0 { Text(L("Source")) }
                    else if index == hops.count - 1 { Text(L("Destination")) }
                    else { Text(L("Relay")) }
                }
                .font(.caption2)
                .foregroundStyle(ResilixTheme.textSecondary)
                if index < hops.count - 1 {
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(ResilixTheme.brandTeal)
                        .symbolEffect(.pulse, isActive: animating)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("ui.route") + " " + hops.joined(separator: " " + L("ui.through") + " "))
    }
}
