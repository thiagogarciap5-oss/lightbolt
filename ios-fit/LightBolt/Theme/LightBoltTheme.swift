import SwiftUI

/// Global visual language for LightBolt: absolute black canvas, electric yellow accent,
/// compressed athletic typography.
enum LightBoltTheme {
    // MARK: Surfaces
    static let void = Color(hex: 0x000000)
    static let obsidian = Color(hex: 0x09090A)
    static let charcoal = Color(hex: 0x1C1C1E)
    static let charcoalHigh = Color(hex: 0x26262A)
    static let hairline = Color(hex: 0x2E2E33)

    // MARK: Accents
    static let volt = Color(hex: 0xFFF500)
    static let voltSoft = Color(hex: 0xFFDE4D)
    static let voltDim = Color(hex: 0x6B6600)

    // MARK: Text
    static let ink = Color(hex: 0xFFFFFF)
    static let inkMuted = Color(hex: 0x8E8E93)
    static let inkFaint = Color(hex: 0x5A5A5F)

    // MARK: Semantics
    static let alert = Color(hex: 0xFF453A)

    static let cardRadius: CGFloat = 22
    static let tileRadius: CGFloat = 18

    /// Deep vignette used behind every screen so pure black never reads as flat.
    static var backdrop: some View {
        ZStack {
            void
            RadialGradient(
                colors: [Color(hex: 0x141410).opacity(0.9), .clear],
                center: .init(x: 0.5, y: -0.05),
                startRadius: 8,
                endRadius: 520
            )
            RadialGradient(
                colors: [volt.opacity(0.07), .clear],
                center: .init(x: 1.05, y: 0.92),
                startRadius: 4,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Typography

extension Font {
    /// Massive compressed display type — the app's headline signature.
    static func fitDisplay(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .default).width(.compressed)
    }

    static func fitTitle(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .default).width(.condensed)
    }

    static func fitLabel(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }

    static func fitBody(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }

    static func fitNumeric(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Reusable modifiers

/// Small uppercase eyebrow label with wide tracking.
struct EyebrowText: View {
    let text: String
    var color: Color = LightBoltTheme.inkMuted

    var body: some View {
        Text(text.uppercased())
            .font(.fitLabel(10))
            .tracking(2.4)
            .foregroundStyle(color)
    }
}

struct LightBoltCard: ViewModifier {
    var radius: CGFloat = LightBoltTheme.cardRadius
    var stroke: Color = LightBoltTheme.hairline
    var fill: Color = LightBoltTheme.charcoal

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
            .clipShape(.rect(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func fitCard(
        radius: CGFloat = LightBoltTheme.cardRadius,
        stroke: Color = LightBoltTheme.hairline,
        fill: Color = LightBoltTheme.charcoal
    ) -> some View {
        modifier(LightBoltCard(radius: radius, stroke: stroke, fill: fill))
    }

    /// Yellow-on-black gradient text wash used for hero numerals.
    func voltWash() -> some View {
        foregroundStyle(
            LinearGradient(
                colors: [LightBoltTheme.volt, LightBoltTheme.voltSoft, LightBoltTheme.volt.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

/// Spring-loaded press feedback used on every interactive surface.
struct VoltPressStyle: ButtonStyle {
    var scale: CGFloat = 0.955

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

/// Primary call-to-action: solid volt slab, black label, hard edges.
struct VoltButton: View {
    let title: String
    var systemImage: String?
    var isEnabled: Bool = true
    var isBusy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isBusy {
                    RunningWaveLoader(height: 12, tint: .black)
                        .frame(width: 34)
                } else if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 15, weight: .heavy))
                }
                Text(title.uppercased())
                    .font(.fitTitle(17))
                    .tracking(1.6)
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isEnabled ? LightBoltTheme.volt : LightBoltTheme.charcoalHigh)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(LightBoltTheme.volt.opacity(isEnabled ? 0.0 : 0.15), lineWidth: 1)
            )
        }
        .buttonStyle(VoltPressStyle())
        .disabled(!isEnabled || isBusy)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

/// Secondary, low-emphasis action drawn as an outlined charcoal slab.
struct GhostButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 14, weight: .bold))
                }
                Text(title.uppercased())
                    .font(.fitTitle(15))
                    .tracking(1.4)
            }
            .foregroundStyle(LightBoltTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LightBoltTheme.charcoal)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(LightBoltTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(VoltPressStyle())
    }
}
