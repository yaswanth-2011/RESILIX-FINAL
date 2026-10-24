import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Resilix design tokens
// Semantic colors, spacing, and radii. Brand identity: black, blue-gray, cyan.
// Pure black background, dark navy surfaces, cyan/teal accents, white text.

enum ResilixTheme {

    // MARK: - Dynamic color helper
    /// Opaque colour components (0...1).
    struct RGB {
        var r: Double, g: Double, b: Double
    }
    /// Colour components with alpha (0...1).
    struct RGBA {
        var r: Double, g: Double, b: Double, a: Double
    }
    static func rgb(_ r: Double, _ g: Double, _ b: Double) -> RGB { RGB(r: r, g: g, b: b) }
    static func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: a) }

    #if canImport(UIKit)
    private static func adaptive(_ light: RGB, _ dark: RGB) -> Color {
        Color(UIColor { trait in
            let v = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: v.r, green: v.g, blue: v.b, alpha: 1)
        })
    }
    private static func adaptive(_ light: RGBA, _ dark: RGBA) -> Color {
        Color(UIColor { trait in
            let v = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: v.r, green: v.g, blue: v.b, alpha: v.a)
        })
    }
    #else
    private static func adaptive(_ light: RGB, _ dark: RGB) -> Color {
        Color(red: light.r, green: light.g, blue: light.b)
    }
    private static func adaptive(_ light: RGBA, _ dark: RGBA) -> Color {
        Color(red: light.r, green: light.g, blue: light.b, opacity: light.a)
    }
    #endif

    // MARK: - Surfaces & backgrounds
    // Light: soft off-white background, white cards. Dark: PURE BLACK, near-black surfaces.
    static var backgroundPrimary: Color { adaptive(rgb(0.965, 0.968, 0.975), rgb(0.00, 0.00, 0.00)) }    // Off-white / pure black
    static var backgroundSecondary: Color { adaptive(rgb(0.93, 0.935, 0.95), rgb(0.04, 0.045, 0.055)) }  // Slightly elevated
    static var surfacePrimary: Color { adaptive(rgb(1.00, 1.00, 1.00), rgb(0.055, 0.06, 0.075)) }       // Card surfaces
    static var surfaceSecondary: Color { adaptive(rgb(0.945, 0.95, 0.96), rgb(0.085, 0.09, 0.105)) }    // Secondary surfaces
    static var surfaceElevated: Color { adaptive(rgb(1.00, 1.00, 1.00), rgb(0.11, 0.12, 0.14)) }        // Elevated surfaces
    static var separator: Color { adaptive(rgb(0.85, 0.86, 0.89), rgb(0.16, 0.175, 0.20)) }             // Subtle borders

    // MARK: - Text
    static var textPrimary: Color { adaptive(rgb(0.09, 0.12, 0.18), rgb(1.00, 1.00, 1.00)) }          // Deep navy / white
    static var textSecondary: Color { adaptive(rgb(0.38, 0.43, 0.50), rgb(0.65, 0.69, 0.75)) }        // Steel blue-grey / cool grey
    static var textTertiary: Color { adaptive(rgb(0.55, 0.59, 0.66), rgb(0.45, 0.49, 0.55)) }         // Muted grey
    static var textOnAccent: Color { adaptive(rgb(1.00, 1.00, 1.00), rgb(0.02, 0.03, 0.05)) }         // On-accent text

    // MARK: - Brand — grey-blue palette (NO cyan/teal)
    static var brandNavy: Color { adaptive(rgb(0.16, 0.23, 0.35), rgb(0.13, 0.19, 0.30)) }            // Deep navy / grey-blue
    static var brandBlueGray: Color { adaptive(rgb(0.42, 0.51, 0.62), rgb(0.52, 0.60, 0.70)) }        // Muted steel blue
    static var brandCyan: Color { adaptive(rgb(0.33, 0.44, 0.57), rgb(0.56, 0.66, 0.77)) }            // Legacy token → grey-blue accent
    static var brandTeal: Color { adaptive(rgb(0.30, 0.41, 0.54), rgb(0.52, 0.62, 0.73)) }            // Legacy token → grey-blue accent
    static var brandTealSoft: Color { adaptive(rgb(0.87, 0.90, 0.94), rgb(0.13, 0.16, 0.21)) }        // Soft grey-blue background
    static var brandSlate: Color { adaptive(rgb(0.38, 0.45, 0.54), rgb(0.42, 0.49, 0.58)) }           // Slate for secondary
    static var brandAmber: Color { adaptive(rgb(0.82, 0.56, 0.18), rgb(0.87, 0.64, 0.28)) }           // Muted amber
    static var emergencyRed: Color { adaptive(rgb(0.85, 0.25, 0.25), rgb(0.92, 0.32, 0.32)) }        // Red for SOS only
    static var successGreen: Color { adaptive(rgb(0.22, 0.62, 0.42), rgb(0.30, 0.68, 0.48)) }        // Muted green
    static var warningYellow: Color { adaptive(rgb(0.85, 0.62, 0.18), rgb(0.92, 0.70, 0.26)) }       // Muted yellow

    static var destructiveText: Color { emergencyRed }
    static var destructiveSurface: Color { adaptive(rgb(0.25, 0.08, 0.08), rgb(0.20, 0.06, 0.06)) }

    // MARK: - Liquid Glass
    static var glassBackground: Color { adaptive(rgba(0.92, 0.94, 0.98, 0.65), rgba(0.08, 0.09, 0.11, 0.18)) }
    static var glassBorder: Color { adaptive(rgba(0.10, 0.13, 0.18, 0.22), rgba(1.00, 1.00, 1.00, 0.18)) }
    static var glassHighlight: Color { adaptive(rgba(1.00, 1.00, 1.00, 0.70), rgba(1.00, 1.00, 1.00, 0.12)) }

    // MARK: - Accent glow (grey-blue; legacy name kept for existing call sites)
    static var cyanGlow: Color { adaptive(rgba(0.33, 0.44, 0.57, 0.25), rgba(0.56, 0.66, 0.77, 0.35)) }
    static var cyanGlowStrong: Color { adaptive(rgba(0.33, 0.44, 0.57, 0.4), rgba(0.56, 0.66, 0.77, 0.5)) }

    // MARK: - Typography (Avenir Next)
    enum FontWeight {
        case regular, medium, semibold, bold, heavy
        var face: String {
            switch self {
            case .regular: return "Avenir Next"
            case .medium: return "Avenir Next Medium"
            case .semibold: return "Avenir Next Demi Bold"
            case .bold: return "Avenir Next Bold"
            case .heavy: return "Avenir Next Heavy"
            }
        }
        /// System fallback if Avenir Next is unavailable
        var fallback: Font.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            case .heavy: return .heavy
            }
        }
    }

    static func font(_ size: CGFloat, _ weight: FontWeight = .regular) -> Font {
        .custom(weight.face, size: size, relativeTo: .body)
    }
    static var largeTitleFont: Font { font(30, .bold) }
    static var titleFont: Font { font(20, .bold) }
    static var sectionHeaderFont: Font { font(13, .semibold) }
    static var bodyFont: Font { font(15, .regular) }
    static var captionFont: Font { font(12, .regular) }

    // MARK: - Corner radius
    static let cornerRadiusSmall: CGFloat = 8
    static let cornerRadiusMedium: CGFloat = 12
    static let cornerRadiusLarge: CGFloat = 16
    static let cornerRadiusXLarge: CGFloat = 24
    static let cornerRadiusPill: CGFloat = 100

    // MARK: - Spacing (4-point grid)
    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space10: CGFloat = 10
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32
    static let space40: CGFloat = 40
    static let space48: CGFloat = 48

    // MARK: - Animation
    static let animationFast: Animation = .easeOut(duration: 0.15)
    static let animationMedium: Animation = .easeOut(duration: 0.25)
    static let animationSlow: Animation = .easeOut(duration: 0.4)
    static let animationSpring: Animation = .spring(response: 0.4, dampingFraction: 0.8)

    // MARK: - Convenience aliases used across views
    static var bgPrimary: Color { backgroundPrimary }
    static var bgSecondary: Color { backgroundSecondary }
    static var cardPrimary: Color { surfacePrimary }
    static var cardSecondary: Color { surfaceSecondary }
    static var cardElevated: Color { surfaceElevated }
}

// MARK: - View Extensions for common styling
extension View {
    func resilixCard(cornerRadius: CGFloat = ResilixTheme.cornerRadiusMedium) -> some View {
        self
            .background(ResilixTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(ResilixTheme.separator, lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
            .shadow(color: ResilixTheme.cyanGlow, radius: 5, x: 0, y: 0)
    }

    func resilixGlassCard(cornerRadius: CGFloat = ResilixTheme.cornerRadiusMedium) -> some View {
        self
            .background(ResilixTheme.glassBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(ResilixTheme.glassBorder, lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

    func cyanGlow(radius: CGFloat = 8) -> some View {
        self.shadow(color: ResilixTheme.cyanGlow, radius: radius, x: 0, y: 0)
    }

    func pressScale() -> some View {
        self.buttonStyle(PressScaleStyle())
    }

    /// Native Liquid Glass on iOS 26+, custom glass fallback on older iOS.
    @ViewBuilder
    func liquidGlassCapsule(interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            self.liquidGlassCapsuleNative(interactive: interactive)
        } else {
            self
                .background(ResilixTheme.glassBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(ResilixTheme.glassBorder, lineWidth: 0.8)
                )
                .overlay(
                    Capsule()
                        .stroke(ResilixTheme.glassHighlight, lineWidth: 0.5)
                        .blendMode(.overlay)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 2)
                .shadow(color: ResilixTheme.cyanGlow.opacity(0.35), radius: 6, x: 0, y: 0)
        }
    }

    @available(iOS 26.0, *)
    @ViewBuilder
    private func liquidGlassCapsuleNative(interactive: Bool) -> some View {
        self.modifier(LiquidGlassNativeModifier(shape: .capsule, interactive: interactive, cornerRadius: nil))
    }

    @ViewBuilder
    func liquidGlassRounded(cornerRadius: CGFloat = ResilixTheme.cornerRadiusMedium, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.modifier(LiquidGlassNativeModifier(shape: .rounded(cornerRadius), interactive: interactive, cornerRadius: cornerRadius))
        } else {
            self
                .background(ResilixTheme.glassBackground)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(ResilixTheme.glassBorder, lineWidth: 0.8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(ResilixTheme.glassHighlight, lineWidth: 0.5)
                        .blendMode(.overlay)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 2)
                .shadow(color: ResilixTheme.cyanGlow.opacity(0.35), radius: 6, x: 0, y: 0)
        }
    }

    @available(iOS 26.0, *)
    @ViewBuilder
    private func liquidGlassRoundedNative(cornerRadius: CGFloat, interactive: Bool) -> some View {
        self.modifier(LiquidGlassNativeModifier(shape: .rounded(cornerRadius), interactive: interactive, cornerRadius: cornerRadius))
    }

    @ViewBuilder
    func liquidGlassCircle(interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            self.modifier(LiquidGlassNativeModifier(shape: .circle, interactive: interactive, cornerRadius: nil))
        } else {
            self
                .background(ResilixTheme.glassBackground)
                .clipShape(Circle())
                .overlay(Circle().stroke(ResilixTheme.glassBorder, lineWidth: 0.8))
                .overlay(Circle().stroke(ResilixTheme.glassHighlight, lineWidth: 0.5).blendMode(.overlay))
                .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 2)
                .shadow(color: ResilixTheme.cyanGlow.opacity(0.35), radius: 6, x: 0, y: 0)
        }
    }

    @available(iOS 26.0, *)
    @ViewBuilder
    private func liquidGlassCircleNative(interactive: Bool) -> some View {
        self.modifier(LiquidGlassNativeModifier(shape: .circle, interactive: interactive, cornerRadius: nil))
    }
}

/// MARK: - Liquid Glass Native Modifier (iOS 26+)
@available(iOS 26.0, *)
private struct LiquidGlassNativeModifier: ViewModifier {
    enum ShapeType { case capsule, circle, rounded(CGFloat) }
    let shape: ShapeType
    let interactive: Bool
    let cornerRadius: CGFloat?
    
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        let glass = interactive ? Glass.regular.interactive() : Glass.regular
        let tintOpacity: CGFloat = colorScheme == .dark ? 0.03 : 0.45
        
        switch shape {
        case .capsule:
            content.glassEffect(glass.tint(Color.white.opacity(tintOpacity)), in: Capsule())
        case .circle:
            content.glassEffect(glass.tint(Color.white.opacity(tintOpacity)), in: Circle())
        case .rounded(let r):
            content.glassEffect(glass.tint(Color.white.opacity(tintOpacity)), in: RoundedRectangle(cornerRadius: r, style: .continuous))
        }
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Color extensions for hex initialization
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}