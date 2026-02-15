import SwiftUI

// MARK: - NodeOrbView (Entry Point)

/// A Siri-like organic orb that communicates node status through color, movement, and glow.
/// Green = online, gray-blue = loading, deep red = offline.
struct NodeOrbView: View {
    let isOnline: Bool
    let isLoading: Bool

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)

            ZStack {
                // Layer 1: Background gradient fill
                LinearGradient(
                    colors: stateColors,
                    startPoint: .bottom,
                    endPoint: .top
                )

                // Layer 2: Soft radial underglow (adds depth behind everything)
                RadialGradient(
                    colors: [glowColor.opacity(0.5), .clear],
                    center: .center,
                    startRadius: size * 0.05,
                    endRadius: size * 0.45
                )
                .blendMode(.plusLighter)

                // Layer 3: Base depth glow (slow, counterclockwise, heavier blur)
                OrbRotatingGlow(
                    color: glowColor,
                    speed: 12 * speedMultiplier,
                    direction: .counterClockwise
                )
                .padding(size * 0.03)
                .blur(radius: size * 0.10)
                .rotationEffect(.degrees(180))

                // Layer 4: Primary wavy blob (large, offset down)
                OrbRotatingGlow(
                    color: .white.opacity(0.8),
                    speed: 18 * speedMultiplier,
                    direction: .clockwise
                )
                .mask {
                    OrbBlobCanvas(
                        cycleDuration: 4.5 / speedMultiplier,
                        amplitudeScale: amplitudeScale
                    )
                    .frame(maxWidth: size * 1.6)
                    .offset(y: size * 0.22)
                }
                .blur(radius: size * 0.05)
                .blendMode(.plusLighter)

                // Layer 5: Secondary wavy blob (medium, offset up, rotated)
                OrbRotatingGlow(
                    color: .white,
                    speed: 9 * speedMultiplier,
                    direction: .counterClockwise
                )
                .mask {
                    OrbBlobCanvas(
                        cycleDuration: 6.0 / speedMultiplier,
                        amplitudeScale: amplitudeScale
                    )
                    .frame(maxWidth: size * 1.15)
                    .rotationEffect(.degrees(90))
                    .offset(y: size * -0.22)
                }
                .opacity(0.6)
                .blur(radius: size * 0.04)
                .blendMode(.plusLighter)

                // Layer 6: Tertiary wavy blob (adds overlap complexity)
                OrbRotatingGlow(
                    color: .white.opacity(0.7),
                    speed: 14 * speedMultiplier,
                    direction: .clockwise
                )
                .mask {
                    OrbBlobCanvas(
                        cycleDuration: 7.5 / speedMultiplier,
                        amplitudeScale: amplitudeScale * 0.85
                    )
                    .frame(maxWidth: size * 1.3)
                    .rotationEffect(.degrees(45))
                    .offset(x: size * 0.12, y: size * 0.08)
                }
                .opacity(0.45)
                .blur(radius: size * 0.06)
                .blendMode(.plusLighter)

                // Layer 7: Core glow (fast rotation, heavily blurred)
                ZStack {
                    OrbRotatingGlow(
                        color: glowColor,
                        speed: 36 * speedMultiplier,
                        direction: .clockwise
                    )
                    .blur(radius: size * 0.12)
                    .opacity(coreGlowIntensity)

                    OrbRotatingGlow(
                        color: glowColor,
                        speed: 27 * speedMultiplier,
                        direction: .clockwise
                    )
                    .blur(radius: size * 0.08)
                    .opacity(coreGlowIntensity)
                    .blendMode(.plusLighter)

                    // Extra slow counter-rotating glow for fluid core
                    OrbRotatingGlow(
                        color: glowColor.opacity(0.6),
                        speed: 20 * speedMultiplier,
                        direction: .counterClockwise
                    )
                    .blur(radius: size * 0.14)
                    .opacity(coreGlowIntensity * 0.7)
                    .blendMode(.plusLighter)
                }
                .padding(size * 0.06)

                // Layer 8: Rim glow (glass-sphere edge)
                OrbRimGlow()
            }
            .mask { Circle() }
            .glassEffect(.clear.tint(glassTint), in: .circle)
            .modifier(OrbShadowModifier(colors: stateColors, radius: size * 0.10))
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.easeInOut(duration: 0.8), value: isOnline)
        .animation(.easeInOut(duration: 0.8), value: isLoading)
    }

    // MARK: - State-Driven Properties

    private static let onlineColors: [Color] = [
        Color(.sRGB, red: 0.03, green: 0.25, blue: 0.12),
        Color(.sRGB, red: 0.08, green: 0.55, blue: 0.30),
        Color(.sRGB, red: 0.12, green: 0.70, blue: 0.38),
    ]

    private static let loadingColors: [Color] = [
        Color(.sRGB, red: 0.20, green: 0.22, blue: 0.28),
        Color(.sRGB, red: 0.30, green: 0.35, blue: 0.42),
        Color(.sRGB, red: 0.25, green: 0.28, blue: 0.35),
    ]

    private static let offlineColors: [Color] = [
        Color(.sRGB, red: 0.35, green: 0.06, blue: 0.06),
        Color(.sRGB, red: 0.65, green: 0.12, blue: 0.10),
        Color(.sRGB, red: 0.50, green: 0.08, blue: 0.08),
    ]

    private var stateColors: [Color] {
        if isLoading { return Self.loadingColors }
        return isOnline ? Self.onlineColors : Self.offlineColors
    }

    private var glowColor: Color {
        if isLoading { return .white.opacity(0.5) }
        return isOnline ? .white : Color(.sRGB, red: 1.0, green: 0.6, blue: 0.5)
    }

    private var coreGlowIntensity: Double {
        if isLoading { return 0.5 }
        return isOnline ? 1.2 : 0.8
    }

    private var speedMultiplier: Double {
        if isLoading { return 0.6 }
        return isOnline ? 1.0 : 0.5
    }

    private var amplitudeScale: Double {
        if isLoading { return 0.7 }
        return isOnline ? 1.0 : 0.6
    }

    private var glassTint: Color {
        if isLoading { return .gray }
        return isOnline ? .green : .red
    }
}

// MARK: - OrbBlobCanvas (Organic Morphing Shape)

/// Draws a 6-point morphing blob using cubic Bezier curves.
/// Each control point oscillates with unique amplitude, speed, and phase offset
/// so the shape never looks synchronized or mechanical.
private struct OrbBlobCanvas: View {
    let cycleDuration: Double
    let amplitudeScale: Double

    private struct BlobPoint {
        let amplitude: Double
        let timeScale: Double
        let phaseOffset: Double
    }

    // Higher amplitudes + wider spread for more dramatic deformation
    private static let points: [BlobPoint] = [
        BlobPoint(amplitude: 0.16, timeScale: 1.00, phaseOffset: 0),
        BlobPoint(amplitude: 0.24, timeScale: 0.65, phaseOffset: .pi / 3),
        BlobPoint(amplitude: 0.18, timeScale: 1.25, phaseOffset: 2 * .pi / 3),
        BlobPoint(amplitude: 0.22, timeScale: 0.85, phaseOffset: .pi),
        BlobPoint(amplitude: 0.17, timeScale: 1.15, phaseOffset: 4 * .pi / 3),
        BlobPoint(amplitude: 0.25, timeScale: 0.75, phaseOffset: 5 * .pi / 3),
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let baseRadius = min(size.width, size.height) * 0.40

                // Wider breathing range for more dramatic pulsing (~21s cycle)
                let breathFactor = 0.75 + 0.25 * sin(time * 0.3)

                // Phase angle drives the main oscillation
                let angle = (time / cycleDuration) * 2 * .pi

                // Compute animated positions for all 6 control points
                let animated: [CGPoint] = (0..<6).map { i in
                    let baseAngle = Double(i) * (.pi / 3)
                    let cfg = Self.points[i]

                    let effectiveAmp = cfg.amplitude * amplitudeScale * breathFactor
                    let xOff = sin(angle * cfg.timeScale + cfg.phaseOffset) * effectiveAmp
                    let yOff = cos(angle * cfg.timeScale + cfg.phaseOffset) * effectiveAmp

                    return CGPoint(
                        x: center.x + cos(baseAngle) * baseRadius * (1.0 + xOff),
                        y: center.y + sin(baseAngle) * baseRadius * (1.0 + yOff)
                    )
                }

                // Build closed Bezier path with perpendicular tangent handles
                var path = Path()
                path.move(to: animated[0])

                for i in 0..<6 {
                    let current = animated[i]
                    let next = animated[(i + 1) % 6]

                    let currentAngle = atan2(current.y - center.y, current.x - center.x)
                    let nextAngle = atan2(next.y - center.y, next.x - center.x)
                    let handleLength = baseRadius * 0.36

                    let cp1 = CGPoint(
                        x: current.x + cos(currentAngle + .pi / 2) * handleLength,
                        y: current.y + sin(currentAngle + .pi / 2) * handleLength
                    )
                    let cp2 = CGPoint(
                        x: next.x + cos(nextAngle - .pi / 2) * handleLength,
                        y: next.y + sin(nextAngle - .pi / 2) * handleLength
                    )

                    path.addCurve(to: next, control1: cp1, control2: cp2)
                }

                context.fill(path, with: .color(.white))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - OrbRotatingGlow (Crescent Light)

/// A crescent-shaped glow that rotates continuously via Core Animation.
/// The crescent is created by masking a circle with a larger offset circle
/// using `.destinationOut` blend mode.
private struct OrbRotatingGlow: View {
    let color: Color
    let speed: Double
    let direction: RotationDir

    @State private var rotation: Double = 0

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)

            Circle()
                .fill(color)
                .mask {
                    ZStack {
                        Circle()
                            .frame(width: size, height: size)
                            .blur(radius: size * 0.18)

                        Circle()
                            .frame(width: size * 1.35, height: size * 1.35)
                            .offset(y: size * 0.33)
                            .blur(radius: size * 0.18)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    guard speed > 0 else { return }
                    withAnimation(
                        .linear(duration: 360 / speed)
                        .repeatForever(autoreverses: false)
                    ) {
                        rotation = 360 * direction.multiplier
                    }
                }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - OrbRimGlow (Glass-Sphere Edge)

/// Triple-layer circle strokes with increasing blur to simulate
/// a glass sphere's rim lighting, lit from above.
private struct OrbRimGlow: View {
    var body: some View {
        let gradient = LinearGradient(
            colors: [.white.opacity(0.9), .clear],
            startPoint: .bottom,
            endPoint: .top
        )

        ZStack {
            Circle().stroke(gradient, lineWidth: 8)
                .blur(radius: 28)
                .blendMode(.plusLighter)
            Circle().stroke(gradient, lineWidth: 4)
                .blur(radius: 12)
                .blendMode(.plusLighter)
            Circle().stroke(gradient, lineWidth: 1.5)
                .blur(radius: 4)
                .blendMode(.plusLighter)
        }
        .padding(1)
    }
}

// MARK: - OrbShadowModifier

/// Adds a colored shadow beneath the orb to ground it visually.
private struct OrbShadowModifier: ViewModifier {
    let colors: [Color]
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blur(radius: radius)
                    .offset(y: radius * 0.5)
                    .opacity(0.5)
            }
    }
}

// MARK: - RotationDir

private enum RotationDir {
    case clockwise, counterClockwise

    var multiplier: Double {
        switch self {
        case .clockwise: 1.0
        case .counterClockwise: -1.0
        }
    }
}

// MARK: - Preview

#Preview("All States") {
    VStack(spacing: 40) {
        NodeOrbView(isOnline: true, isLoading: false)
            .frame(width: 180, height: 180)

        NodeOrbView(isOnline: false, isLoading: true)
            .frame(width: 180, height: 180)

        NodeOrbView(isOnline: false, isLoading: false)
            .frame(width: 180, height: 180)
    }
    .padding()
    .background(.black)
}
