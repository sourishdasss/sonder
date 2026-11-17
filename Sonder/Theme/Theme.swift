import SwiftUI
import UIKit

// MARK: - Palette
//
// Light: the V2 warm-neutral palette (parchment, terracotta, sage).
// Dark:  the original "deep navy + warm amber" direction.
// Every colour is dynamic, so the app follows the system appearance.

extension Color {
    static let sonderBackground  = Color.dynamic(light: 0xF5F0EB, dark: 0x0E131D)
    static let sonderSurface     = Color.dynamic(light: 0xFFFFFF, dark: 0x1A2130)
    static let sonderSurfaceAlt  = Color.dynamic(light: 0xFBF8F4, dark: 0x232C3D)
    static let sonderDivider     = Color.dynamic(light: 0xE0D9D2, dark: 0x2E384B)

    /// Terracotta in light mode, amber-gold in dark mode.
    static let sonderAccent      = Color.dynamic(light: 0xC0622F, dark: 0xE9A552)
    /// Foreground colour for content placed on top of `sonderAccent`.
    static let sonderOnAccent    = Color.dynamic(light: 0xFFFFFF, dark: 0x1B1305)
    static let sonderSage        = Color.dynamic(light: 0x4A7C6F, dark: 0x82BBAA)

    static let sonderTextPrimary = Color.dynamic(light: 0x1C1C1E, dark: 0xF3EFE9)
    static let sonderTextSecond  = Color.dynamic(light: 0x6B6B6B, dark: 0x9BA4B4)
    static let sonderDanger      = Color.dynamic(light: 0xB3261E, dark: 0xF2A29B)

    /// Score/accent colour for text drawn over photography (always bright, regardless of appearance).
    static let sonderScoreOnPhoto = Color(hex: 0xF2B56B)

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Typography (Georgia, scaled with Dynamic Type)

extension Font {
    static func georgia(_ size: CGFloat) -> Font {
        .custom("Georgia", size: size, relativeTo: textStyle(for: size))
    }

    static func georgiaBold(_ size: CGFloat) -> Font {
        .custom("Georgia-Bold", size: size, relativeTo: textStyle(for: size))
    }

    static func georgiaItalic(_ size: CGFloat) -> Font {
        .custom("Georgia-Italic", size: size, relativeTo: textStyle(for: size))
    }

    /// Picks the Dynamic Type style closest to a design size so custom fonts scale sensibly.
    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: return .caption2
        case ..<12.5: return .caption
        case ..<14: return .footnote
        case ..<15.5: return .subheadline
        case ..<16.5: return .callout
        case ..<18: return .body
        case ..<21: return .title3
        case ..<25: return .title2
        case ..<31: return .title
        default: return .largeTitle
        }
    }
}

// MARK: - Layout constants

enum SonderMetrics {
    static let cornerRadius: CGFloat = 18
    static let smallCornerRadius: CGFloat = 12
    static let screenPadding: CGFloat = 16
}

// MARK: - Global UIKit appearance

enum SonderAppearance {
    /// Applies Georgia to navigation titles and the brand tint to bars. Call once at launch.
    static func apply() {
        let titleColor = UIColor(Color.sonderTextPrimary)

        func styled(_ appearance: UINavigationBarAppearance) -> UINavigationBarAppearance {
            if let large = UIFont(name: "Georgia-Bold", size: 32) {
                appearance.largeTitleTextAttributes = [
                    .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large),
                    .foregroundColor: titleColor
                ]
            }
            if let inline = UIFont(name: "Georgia-Bold", size: 17) {
                appearance.titleTextAttributes = [
                    .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline),
                    .foregroundColor: titleColor
                ]
            }
            return appearance
        }

        // At the top of a scroll view the bar is transparent, so the page background shows
        // through and the large title sits directly on it. Once content scrolls underneath,
        // the system's default bar material takes over.
        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()
        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()

        UINavigationBar.appearance().standardAppearance = styled(standard)
        UINavigationBar.appearance().compactAppearance = styled(standard)
        UINavigationBar.appearance().scrollEdgeAppearance = styled(scrollEdge)
        UINavigationBar.appearance().tintColor = UIColor(Color.sonderAccent)
    }
}

// MARK: - Reusable styling

struct SonderCardModifier: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = SonderMetrics.cornerRadius

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sonderSurface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 3)
    }
}

extension View {
    /// Surface-coloured rounded card with a soft shadow.
    func sonderCard(padding: CGFloat = 16, radius: CGFloat = SonderMetrics.cornerRadius) -> some View {
        modifier(SonderCardModifier(padding: padding, radius: radius))
    }

    /// Standard text-field chrome used across forms.
    func sonderField() -> some View {
        self
            .font(.georgia(16))
            .foregroundStyle(Color.sonderTextPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color.sonderSurface)
            .clipShape(RoundedRectangle(cornerRadius: SonderMetrics.smallCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SonderMetrics.smallCornerRadius, style: .continuous)
                    .stroke(Color.sonderDivider, lineWidth: 1)
            )
    }

    /// Section heading used on scrolling screens.
    func sonderSectionTitle() -> some View {
        self
            .font(.georgiaBold(20))
            .foregroundStyle(Color.sonderTextPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Filled, full-width call-to-action button.
struct SonderPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.georgiaBold(16))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .padding(.horizontal, 16)
            .background(isEnabled ? Color.sonderAccent : Color.sonderDivider)
            .foregroundStyle(isEnabled ? Color.sonderOnAccent : Color.sonderTextSecond)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Tinted, lower-emphasis button (outlined capsule).
struct SonderSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.georgiaBold(14))
            .padding(.vertical, 9)
            .padding(.horizontal, 16)
            .background(Color.sonderAccent.opacity(configuration.isPressed ? 0.2 : 0.12))
            .foregroundStyle(Color.sonderAccent)
            .clipShape(Capsule())
    }
}

extension ButtonStyle where Self == SonderPrimaryButtonStyle {
    static var sonderPrimary: SonderPrimaryButtonStyle { SonderPrimaryButtonStyle() }
}

extension ButtonStyle where Self == SonderSecondaryButtonStyle {
    static var sonderSecondary: SonderSecondaryButtonStyle { SonderSecondaryButtonStyle() }
}

// MARK: - Shimmer

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.35), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.6)
                        .offset(x: phase * proxy.size.width * 1.6)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    /// Animated loading highlight for placeholders.
    func shimmer() -> some View { modifier(ShimmerModifier()) }
}

// MARK: - Formatting

enum ScoreFormat {
    /// "8.4" style score label.
    static func string(_ score: Double) -> String {
        String(format: "%.1f", min(10, max(0, score)))
    }
}
