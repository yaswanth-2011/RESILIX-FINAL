import SwiftUI
import UIKit

/// Replaceable logo view.
/// Drop your assets into:
/// - `ResilixLogoPlaceholder` → full precomposed logo (vertical: icon top, text bottom)
/// - `ResilixMarkPlaceholder` → compact mark / icon (used to compose stacked & inline variants)
/// Fallback uses SF Symbol + Text so the app never crashes if assets are missing.
struct LogoView: View {
    @Environment(\.colorScheme) private var colorScheme

    enum Variant {
        case full          // Single image ResilixLogoPlaceholder (vertical full logo)
        case stacked       // Icon top, text bottom (vertical) — composes mark + text
        case inline        // Icon left, text right (horizontal)
        case mark          // Icon only
    }
    var variant: Variant = .full
    var height: CGFloat = 28
    /// For stacked/inline, the text to show under / beside the mark
    var showTagline: Bool = false

    var body: some View {
        Group {
            switch variant {
            case .full:
                if let ui = fullLogo {
                    Image(uiImage: ui).resizable().scaledToFit().frame(height: height)
                } else {
                    // Fallback vertical full logo
                    VStack(spacing: 4) {
                        Image(systemName: "shield.lefthalf.filled").font(.title2).foregroundStyle(ResilixTheme.brandTeal)
                        Text(L("Resilix")).font(.headline.weight(.bold)).foregroundStyle(ResilixTheme.textPrimary)
                        if showTagline {
                            Text(L("Survival & Resilience")).font(.caption2.weight(.medium)).foregroundStyle(ResilixTheme.textTertiary)
                        }
                    }
                }
            case .stacked:
                // 1) Icon on top, text on bottom (vertical)
                if let ui = fullLogo {
                    // If full logo exists, show it vertically scaled - but prefer composed for clarity
                    Image(uiImage: ui).resizable().scaledToFit().frame(height: height * 1.6)
                } else {
                    VStack(spacing: 6) {
                        markImage(size: height)
                        Text(L("Resilix")).font(.headline.weight(.bold)).foregroundStyle(ResilixTheme.textPrimary)
                        if showTagline {
                            Text(L("Survival & Resilience Solutions")).font(.caption2).foregroundStyle(ResilixTheme.textTertiary)
                        }
                    }
                }
            case .inline:
                // 2) Icon on left, text on right (horizontal)
                if fullLogo != nil {
                    // Try to use full logo if it exists, but render horizontally
                    // If you have a dedicated horizontal asset, replace this branch to load it
                    HStack(spacing: 8) {
                        markImage(size: height * 0.85)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L("Resilix")).font(.headline.weight(.bold)).foregroundStyle(ResilixTheme.textPrimary)
                            if showTagline {
                                Text(L("Survival & Resilience")).font(.caption2.weight(.medium)).foregroundStyle(ResilixTheme.textTertiary)
                            }
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        markImage(size: height * 0.85)
                        Text(L("Resilix")).font(.headline.weight(.bold)).foregroundStyle(ResilixTheme.textPrimary)
                    }
                }
            case .mark:
                markImage(size: height)
            }
        }
        accessibilityLabel(Text(L("Resilix logo")))
        .accessibilityAddTraits(.isImage)
    }

    /// Full logo asset — dark variant preferred in dark mode, falls back to light asset.
    private var fullLogo: UIImage? {
        if colorScheme == .dark, let dark = UIImage(named: "ResilixLogoPlaceholderDark") { return dark }
        return UIImage(named: "ResilixLogoPlaceholder")
    }

    /// Mark asset — dark variant preferred in dark mode, falls back to light asset.
    private var markLogo: UIImage? {
        if colorScheme == .dark, let dark = UIImage(named: "ResilixMarkPlaceholderDark") { return dark }
        return UIImage(named: "ResilixMarkPlaceholder")
    }

    @ViewBuilder
    private func markImage(size: CGFloat) -> some View {
        if let ui = markLogo {
            Image(uiImage: ui).resizable().scaledToFit().frame(height: size).clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            // Placeholder mark: same footprint in both color schemes,
            // recolored for dark mode so it stays visible on black.
            MeshMarkPlaceholder()
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Helpers for previews

struct LogoVariantPreview: View {
    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Text(L("1) Icon top • Text bottom (stacked)")).font(.caption2.weight(.semibold)).foregroundStyle(ResilixTheme.textSecondary)
                LogoView(variant: .stacked, height: 56, showTagline: true)
                    .padding().background(ResilixTheme.surfacePrimary).clipShape(RoundedRectangle(cornerRadius: 12)).shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                Text(L("ResilixLogoPlaceholder → vertical")).font(.caption2).foregroundStyle(ResilixTheme.textTertiary)
            }
            VStack(spacing: 8) {
                Text(L("2) Icon left • Text right (inline)")).font(.caption2.weight(.semibold)).foregroundStyle(ResilixTheme.textSecondary)
                LogoView(variant: .inline, height: 32, showTagline: false)
                    .padding(.horizontal, 16).padding(.vertical, 10).background(ResilixTheme.surfacePrimary).clipShape(RoundedRectangle(cornerRadius: 12)).shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                Text(L("ResilixMarkPlaceholder + Text → horizontal")).font(.caption2).foregroundStyle(ResilixTheme.textTertiary)
            }
            Text(L("Drop new assets into Assets.xcassets to replace — no code change needed."))
                .font(.caption2).foregroundStyle(ResilixTheme.textTertiary).multilineTextAlignment(.center).padding(.horizontal)
        }.padding().background(ResilixTheme.bgSecondary)
    }
}

#Preview {
    LogoVariantPreview()
}

// MARK: - Mesh mark placeholder
/// Code-drawn mesh mark used when no asset is provided.
/// Light: navy / steel-blue. Dark: bright cyan with glow — same dimensions.
struct MeshMarkPlaceholder: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(colorScheme == .dark
                      ? LinearGradient(colors: [Color(red: 0.0, green: 0.0, blue: 0.0),
                                                Color(red: 0.06, green: 0.08, blue: 0.12)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                      : LinearGradient(colors: [Color.white, Color(red: 0.94, green: 0.95, blue: 0.98)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(colorScheme == .dark ? ResilixTheme.brandCyan.opacity(0.6) : ResilixTheme.brandNavy.opacity(0.35),
                                lineWidth: 0.8)
                )

            Canvas { ctx, size in
                let w = size.width, h = size.height
                let center = CGPoint(x: w / 2, y: h / 2)
                let radius = min(w, h) * 0.28
                let nodeColor: Color = colorScheme == .dark ? ResilixTheme.brandCyan : ResilixTheme.brandNavy

                // Connector triangle
                var path = Path()
                path.move(to: CGPoint(x: w * 0.25, y: h * 0.28))
                path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.32))
                path.addLine(to: CGPoint(x: w * 0.55, y: h * 0.82))
                path.closeSubpath()
                ctx.stroke(path,
                           with: .color(nodeColor.opacity(colorScheme == .dark ? 0.7 : 0.45)),
                           lineWidth: 0.8)

                // Nodes
                let nodes: [CGPoint] = [
                    CGPoint(x: w * 0.25, y: h * 0.28),
                    CGPoint(x: w * 0.78, y: h * 0.32),
                    CGPoint(x: w * 0.55, y: h * 0.82)
                ]
                for n in nodes {
                    let dot = Path(ellipseIn: CGRect(x: n.x - 2, y: n.y - 2, width: 4, height: 4))
                    ctx.fill(dot, with: .color(nodeColor))
                }
                // Center "you" node — brighter in dark mode
                let centerDot = Path(ellipseIn: CGRect(x: center.x - radius,
                                                        y: center.y - radius,
                                                        width: radius * 2, height: radius * 2))
                ctx.stroke(centerDot,
                           with: .color(nodeColor.opacity(colorScheme == .dark ? 0.95 : 0.6)),
                           lineWidth: 1.0)
            }
            .padding(2)
        }
        .shadow(color: colorScheme == .dark ? ResilixTheme.cyanGlowStrong : Color.black.opacity(0.1),
                radius: colorScheme == .dark ? 6 : 3, x: 0, y: 0)
    }
}
