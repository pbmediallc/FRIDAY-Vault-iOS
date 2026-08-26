// swiftlint:disable file_length

import BitwardenKit
import BitwardenResources
import SwiftUI

// MARK: - FridayVaultDesign

/// Semantic F.R.I.D.A.Y. Vault visual tokens.
///
/// The concrete light and dark values live in `BitwardenResources/Colors.xcassets` so views keep
/// following the app's selected appearance instead of freezing a color scheme in Swift code.
enum FridayVaultDesign {
    static var void: Color { SharedAsset.Colors.backgroundPrimary.swiftUIColor }
    static var deep: Color { SharedAsset.Colors.backgroundSecondary.swiftUIColor }
    static var panel: Color { SharedAsset.Colors.backgroundSecondary.swiftUIColor.opacity(0.9) }
    static var elevated: Color { SharedAsset.Colors.backgroundTertiary.swiftUIColor }
    static var cyan: Color { SharedAsset.Colors.tintPrimary.swiftUIColor }
    static var electric: Color { SharedAsset.Colors.textInteraction.swiftUIColor }
    static var ice: Color { SharedAsset.Colors.textPrimary.swiftUIColor }
    static var green: Color { SharedAsset.Colors.statusGood.swiftUIColor }
    static var text: Color { SharedAsset.Colors.textPrimary.swiftUIColor }
    static var secondary: Color { SharedAsset.Colors.textSecondary.swiftUIColor }
    static var edge: Color { SharedAsset.Colors.strokeBorder.swiftUIColor }
    static var separator: Color { SharedAsset.Colors.strokeDivider.swiftUIColor }

    static let cornerCard: CGFloat = 10
    static let cornerControl: CGFloat = 8

    static var background: LinearGradient {
        LinearGradient(
            colors: [
                elevated.opacity(0.96),
                deep,
                deep.opacity(0.98),
                void,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing,
        )
    }
}

// MARK: - FridayVaultBackdrop

/// The non-interactive ambient background shared by F.R.I.D.A.Y. Vault screens.
struct FridayVaultBackdrop: View {
    // MARK: Properties

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase

    @SwiftUI.State private var primaryDrift = false
    @SwiftUI.State private var secondaryDrift = false

    private let motionEnabled: Bool

    private var ambientMotionAllowed: Bool {
        motionEnabled && !reduceMotion && !reduceTransparency && scenePhase == .active
    }

    // MARK: View

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                FridayVaultDesign.void
                FridayVaultDesign.background

                if !reduceTransparency {
                    directionalLight(in: proxy.size)
                    primaryGlow(in: proxy.size)
                    secondaryGlow(in: proxy.size)
                    networkField()
                    microTexture()

                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.045),
                            Color.clear,
                            FridayVaultDesign.void.opacity(0.48),
                        ],
                        startPoint: .top,
                        endPoint: .bottom,
                    )

                    vignette(in: proxy.size)
                } else {
                    LinearGradient(
                        colors: [
                            FridayVaultDesign.elevated.opacity(0.5),
                            FridayVaultDesign.void,
                        ],
                        startPoint: .top,
                        endPoint: .bottom,
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
        .task(id: ambientMotionAllowed) {
            if ambientMotionAllowed {
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
                    primaryDrift = true
                }
                withAnimation(.easeInOut(duration: 23).repeatForever(autoreverses: true)) {
                    secondaryDrift = true
                }
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    primaryDrift = false
                    secondaryDrift = false
                }
            }
        }
    }

    // MARK: Initialization

    init(motionEnabled: Bool = false) {
        self.motionEnabled = motionEnabled
    }

    // MARK: Private views

    private func directionalLight(in size: CGSize) -> some View {
        let diameter = max(max(size.width, size.height) * 1.45, 720)

        return RadialGradient(
            colors: [
                FridayVaultDesign.electric.opacity(0.12),
                FridayVaultDesign.cyan.opacity(0.055),
                FridayVaultDesign.cyan.opacity(0.016),
                Color.clear,
            ],
            center: .center,
            startRadius: 0,
            endRadius: diameter / 2,
        )
        .frame(width: diameter, height: diameter)
        .scaleEffect(x: 1.55, y: 0.34)
        .rotationEffect(.degrees(-24))
        .position(x: size.width * 0.25, y: size.height * 0.04)
        .opacity(primaryDrift ? 0.82 : 1)
    }

    private func primaryGlow(in size: CGSize) -> some View {
        let diameter = max(max(size.width, size.height) * 1.05, 560)

        return RadialGradient(
            colors: [
                FridayVaultDesign.cyan.opacity(0.22),
                FridayVaultDesign.cyan.opacity(0.075),
                FridayVaultDesign.deep.opacity(0.025),
                Color.clear,
            ],
            center: .center,
            startRadius: 0,
            endRadius: diameter / 2,
        )
        .frame(width: diameter, height: diameter)
        .scaleEffect(x: 1.06, y: 0.88)
        .position(x: size.width * 0.2, y: size.height * 0.12)
        .scaleEffect(primaryDrift ? 1.035 : 0.99)
        .offset(x: primaryDrift ? 10 : -5, y: primaryDrift ? 5 : -3)
        .opacity(primaryDrift ? 1 : 0.82)
    }

    private func secondaryGlow(in size: CGSize) -> some View {
        let diameter = max(max(size.width, size.height) * 0.9, 480)

        return RadialGradient(
            colors: [
                FridayVaultDesign.electric.opacity(0.16),
                FridayVaultDesign.cyan.opacity(0.05),
                FridayVaultDesign.deep.opacity(0.018),
                Color.clear,
            ],
            center: .center,
            startRadius: 0,
            endRadius: diameter / 2,
        )
        .frame(width: diameter, height: diameter)
        .scaleEffect(x: 0.94, y: 1.08)
        .position(x: size.width * 0.86, y: size.height * 0.32)
        .scaleEffect(secondaryDrift ? 0.985 : 1.025)
        .offset(x: secondaryDrift ? -8 : 6, y: secondaryDrift ? 7 : -4)
        .opacity(secondaryDrift ? 0.74 : 0.98)
    }

    private func networkField() -> some View {
        Canvas { context, size in
            let points: [CGPoint] = [
                .init(x: size.width * 0.03, y: size.height * 0.16),
                .init(x: size.width * 0.2, y: size.height * 0.06),
                .init(x: size.width * 0.42, y: size.height * 0.18),
                .init(x: size.width * 0.64, y: size.height * 0.07),
                .init(x: size.width * 0.95, y: size.height * 0.2),
                .init(x: size.width * 0.08, y: size.height * 0.5),
                .init(x: size.width * 0.46, y: size.height * 0.42),
                .init(x: size.width * 0.92, y: size.height * 0.48),
                .init(x: size.width * 0.72, y: size.height * 0.66),
            ]

            var path = Path()
            for pair in [
                (0, 1), (1, 2), (2, 3), (3, 4), (0, 5), (2, 5), (2, 6),
                (4, 7), (6, 7), (6, 8), (7, 8),
            ] {
                path.move(to: points[pair.0])
                path.addLine(to: points[pair.1])
            }
            context.stroke(path, with: .color(FridayVaultDesign.cyan.opacity(0.12)), lineWidth: 0.7)

            for (index, point) in points.enumerated() {
                let diameter: CGFloat = index.isMultiple(of: 2) ? 3.4 : 2.4
                context.fill(
                    Path(
                        ellipseIn: CGRect(
                            x: point.x - diameter / 2,
                            y: point.y - diameter / 2,
                            width: diameter,
                            height: diameter,
                        ),
                    ),
                    with: .color(FridayVaultDesign.electric.opacity(index.isMultiple(of: 2) ? 0.34 : 0.2)),
                )
            }
        }
        .mask(
            LinearGradient(
                colors: [Color.white, Color.white.opacity(0.88), Color.clear],
                startPoint: .top,
                endPoint: .bottom,
            ),
        )
    }

    private func microTexture() -> some View {
        Canvas { context, size in
            for index in 0 ..< 44 {
                let xSeed = (index * 47 + 13) % 101
                let ySeed = (index * 67 + 29) % 103
                let horizontalPosition = size.width * CGFloat(xSeed) / 100
                let verticalPosition = size.height * CGFloat(ySeed) / 102
                let diameter: CGFloat = index.isMultiple(of: 7) ? 1.8 : 1
                let opacity = index.isMultiple(of: 5) ? 0.18 : 0.09

                context.fill(
                    Path(
                        ellipseIn: CGRect(
                            x: horizontalPosition - diameter / 2,
                            y: verticalPosition - diameter / 2,
                            width: diameter,
                            height: diameter,
                        ),
                    ),
                    with: .color(FridayVaultDesign.electric.opacity(opacity)),
                )
            }
        }
        .mask(
            LinearGradient(
                colors: [Color.white.opacity(0.95), Color.white.opacity(0.45), Color.clear],
                startPoint: .top,
                endPoint: .bottom,
            ),
        )
    }

    private func vignette(in size: CGSize) -> some View {
        RadialGradient(
            colors: [
                Color.clear,
                Color.clear,
                FridayVaultDesign.void.opacity(0.54),
            ],
            center: UnitPoint(x: 0.48, y: 0.32),
            startRadius: min(size.width, size.height) * 0.12,
            endRadius: max(size.width, size.height) * 0.82,
        )
    }
}

// MARK: - FridayVaultShieldMark

/// The F.R.I.D.A.Y. shield mark rendered entirely in SwiftUI.
struct FridayVaultShieldMark: View {
    // MARK: Properties

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @SwiftUI.State private var primaryOrbiting = false
    @SwiftUI.State private var secondaryOrbiting = false

    private let motionEnabled: Bool
    private let size: CGFloat

    private var ambientMotionAllowed: Bool {
        motionEnabled && !reduceMotion && scenePhase == .active
    }

    // MARK: View

    var body: some View {
        ZStack {
            staticRings
            orbitLayer
            shieldCore
        }
        .frame(width: size, height: size)
        .shadow(color: FridayVaultDesign.cyan.opacity(0.34), radius: size * 0.17)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: ambientMotionAllowed) {
            if ambientMotionAllowed {
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(.linear(duration: 32).repeatForever(autoreverses: false)) {
                    primaryOrbiting = true
                }
                withAnimation(.linear(duration: 41).repeatForever(autoreverses: false)) {
                    secondaryOrbiting = true
                }
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    primaryOrbiting = false
                    secondaryOrbiting = false
                }
            }
        }
    }

    // MARK: Private views

    private var staticRings: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            FridayVaultDesign.electric.opacity(0.15),
                            FridayVaultDesign.cyan.opacity(0.045),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.56,
                    ),
                )

            Circle().stroke(FridayVaultDesign.cyan.opacity(0.38), lineWidth: 1)
            Circle()
                .stroke(FridayVaultDesign.cyan.opacity(0.22), lineWidth: 1)
                .padding(size * 0.095)
            Circle()
                .stroke(FridayVaultDesign.cyan.opacity(0.13), lineWidth: 1)
                .padding(size * 0.2)

            ForEach(0 ..< 8, id: \.self) { index in
                Capsule()
                    .fill(index.isMultiple(of: 2)
                        ? FridayVaultDesign.cyan.opacity(0.62)
                        : FridayVaultDesign.cyan.opacity(0.18))
                        .frame(width: 1, height: index.isMultiple(of: 2) ? 5 : 3)
                        .offset(y: -size * 0.45)
                        .rotationEffect(.degrees(Double(index) * 45))
            }
        }
    }

    private var orbitLayer: some View {
        ZStack {
            Circle()
                .trim(from: 0.015, to: 0.2)
                .stroke(
                    LinearGradient(
                        colors: [FridayVaultDesign.cyan, FridayVaultDesign.electric],
                        startPoint: .leading,
                        endPoint: .trailing,
                    ),
                    style: StrokeStyle(lineWidth: 2.35, lineCap: .round),
                )
                .rotationEffect(.degrees(-18 + (primaryOrbiting ? 360 : 0)))
                .shadow(color: FridayVaultDesign.electric.opacity(0.58), radius: 4)

            Circle()
                .trim(from: 0.46, to: 0.69)
                .stroke(
                    FridayVaultDesign.cyan.opacity(0.74),
                    style: StrokeStyle(lineWidth: 1.9, lineCap: .round),
                )
                .rotationEffect(.degrees(12 + (secondaryOrbiting ? -360 : 0)))

            Circle()
                .trim(from: 0.16, to: 0.35)
                .stroke(
                    FridayVaultDesign.electric.opacity(0.58),
                    style: StrokeStyle(lineWidth: 1.15, lineCap: .round),
                )
                .padding(size * 0.095)
                .rotationEffect(.degrees(54 + (primaryOrbiting ? 360 : 0)))

            Circle()
                .fill(FridayVaultDesign.electric)
                .frame(width: max(3, size * 0.038), height: max(3, size * 0.038))
                .shadow(color: FridayVaultDesign.electric.opacity(0.7), radius: 5)
                .offset(y: -size * 0.36)
                .rotationEffect(.degrees((primaryOrbiting ? 360 : 0) + 105))
        }
    }

    private var shieldCore: some View {
        ZStack {
            FridayVaultShieldShape()
                .fill(
                    LinearGradient(
                        colors: [
                            FridayVaultDesign.cyan.opacity(0.2),
                            FridayVaultDesign.electric.opacity(0.035),
                        ],
                        startPoint: .top,
                        endPoint: .bottom,
                    ),
                )
                .frame(width: size * 0.34, height: size * 0.42)

            FridayVaultShieldShape()
                .stroke(
                    LinearGradient(
                        colors: [FridayVaultDesign.electric, FridayVaultDesign.cyan],
                        startPoint: .top,
                        endPoint: .bottom,
                    ),
                    style: StrokeStyle(lineWidth: max(1.8, size * 0.025), lineJoin: .round),
                )
                .frame(width: size * 0.34, height: size * 0.42)
                .shadow(color: FridayVaultDesign.cyan.opacity(0.52), radius: 7)

            VStack(spacing: 0) {
                Circle()
                    .stroke(FridayVaultDesign.electric, lineWidth: max(1.1, size * 0.013))
                    .frame(width: size * 0.09, height: size * 0.09)
                Capsule()
                    .fill(FridayVaultDesign.electric)
                    .frame(width: max(1.5, size * 0.017), height: size * 0.105)
                    .offset(y: -1)
            }
            .offset(y: size * 0.012)
            .shadow(color: FridayVaultDesign.electric.opacity(0.62), radius: 4)
        }
    }

    // MARK: Initialization

    init(size: CGFloat = 88, motionEnabled: Bool = true) {
        self.size = size
        self.motionEnabled = motionEnabled
    }

}

// MARK: - FridayVaultProfileAvatar

/// The canonical F.R.I.D.A.Y. account avatar used by every profile switcher surface.
///
/// Profile colors from the upstream account model are intentionally not rendered here. A single
/// dark core, cyan edge, and restrained glow keep account identity consistent between the main
/// app and credential-provider extension while the initials remain the identifying content.
struct FridayVaultProfileAvatar: View {
    // MARK: Properties

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let fontWeight: SwiftUI.Font.Weight
    private let initials: String?
    private let size: CGFloat
    private let textStyle: StyleGuideFont

    // MARK: View

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            FridayVaultDesign.elevated.opacity(0.98),
                            FridayVaultDesign.deep.opacity(0.98),
                            FridayVaultDesign.void,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing,
                    ),
                )

            if !reduceTransparency {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                FridayVaultDesign.electric.opacity(0.13),
                                FridayVaultDesign.cyan.opacity(0.035),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.34, y: 0.22),
                            startRadius: 0,
                            endRadius: size * 0.64,
                        ),
                    )

                Circle()
                    .stroke(FridayVaultDesign.cyan.opacity(0.2), lineWidth: max(3, size * 0.11))
                    .blur(radius: max(3, size * 0.1))
            }

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [FridayVaultDesign.electric, FridayVaultDesign.cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing,
                    ),
                    lineWidth: max(1, size * 0.045),
                )

            Circle()
                .stroke(FridayVaultDesign.electric.opacity(0.18), lineWidth: 0.75)
                .padding(max(2.5, size * 0.09))

            avatarContent
        }
        .frame(width: size, height: size)
        .shadow(
            color: reduceTransparency ? .clear : FridayVaultDesign.cyan.opacity(0.3),
            radius: max(3, size * 0.12),
        )
    }

    // MARK: Private views

    @ViewBuilder private var avatarContent: some View {
        if let initials, !initials.isEmpty {
            Text(initials)
                .tracking(size * 0.012)
                .styleGuide(
                    textStyle,
                    weight: fontWeight,
                    includeLinePadding: false,
                    includeLineSpacing: false,
                )
                .foregroundStyle(FridayVaultDesign.electric)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .padding(.horizontal, size * 0.16)
        } else {
            SharedAsset.Icons.horizontalDots16.swiftUIImage
                .imageStyle(.accessoryIcon16(color: FridayVaultDesign.electric))
                .scaleEffect(size / 32)
                .accessibilityHidden(true)
        }
    }

    // MARK: Initialization

    init(
        initials: String?,
        size: CGFloat = 30,
        textStyle: StyleGuideFont = .caption2Monospaced,
        fontWeight: SwiftUI.Font.Weight = .light,
    ) {
        self.initials = initials
        self.size = size
        self.textStyle = textStyle
        self.fontWeight = fontWeight
    }
}

// MARK: - FridayVaultBrandHeader

/// A reusable, Dynamic Type-aware F.R.I.D.A.Y. Vault heading for authentication and privacy views.
struct FridayVaultBrandHeader: View {
    // MARK: Properties

    @ScaledMetric(relativeTo: .largeTitle)
    private var markScale: CGFloat = 1

    @ScaledMetric(relativeTo: .body)
    private var contentSpacing: CGFloat = 14

    private let motionEnabled: Bool
    private let status: String?
    private let statusColor: Color
    private let statusSymbol: String
    private let subtitle: String?
    private let title: String

    // MARK: View

    var body: some View {
        VStack(spacing: min(contentSpacing, 24)) {
            FridayVaultShieldMark(
                size: min(72 * markScale, 112),
                motionEnabled: motionEnabled,
            )

            VStack(spacing: 4) {
                Text(title)
                    .tracking(1.4)
                    .styleGuide(.title2, weight: .semibold)
                    .foregroundStyle(FridayVaultDesign.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(subtitle)
                        .styleGuide(.body)
                        .foregroundStyle(FridayVaultDesign.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let status {
                FridayVaultStatusPill(
                    text: status,
                    color: statusColor,
                    symbol: statusSymbol,
                )
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Initialization

    init(
        title: String = "F.R.I.D.A.Y. VAULT",
        subtitle: String? = nil,
        status: String? = nil,
        statusSymbol: String = "checkmark.shield.fill",
        statusColor: Color = FridayVaultDesign.green,
        motionEnabled: Bool = false,
    ) {
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.statusSymbol = statusSymbol
        self.statusColor = statusColor
        self.motionEnabled = motionEnabled
    }
}

// MARK: - Private types

private struct FridayVaultStatusPill: View {
    let text: String
    let color: Color
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)

            Text(text)
                .styleGuide(.caption1, weight: .semibold)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(FridayVaultDesign.panel)
                .overlay(Capsule().stroke(color.opacity(0.32), lineWidth: 1)),
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

private struct FridayVaultShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX * 0.91, y: rect.minY + rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.maxX * 0.91, y: rect.minY + rect.height * 0.57))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX * 0.89, y: rect.minY + rect.height * 0.76),
            control2: CGPoint(x: rect.maxX * 0.68, y: rect.minY + rect.height * 0.91),
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.09, y: rect.minY + rect.height * 0.57),
            control1: CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.91),
            control2: CGPoint(x: rect.minX + rect.width * 0.11, y: rect.minY + rect.height * 0.76),
        )
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.09, y: rect.minY + rect.height * 0.18))
        path.closeSubpath()
        return path
    }
}
