import SwiftUI

// MARK: - NodeOrbView (Entry Point)

/// A Siri-like organic orb that communicates node status through color, movement, and glow.
/// Green = online, gray-blue = loading, deep red = offline.
struct NodeOrbView: View {
    let isOnline: Bool
    let isLoading: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)

                // Wandering center: slow sine drift so the "hot spot" moves
                let cx = 0.5 + 0.08 * sin(time * 0.23)
                let cy = 0.5 + 0.08 * cos(time * 0.17)

                ZStack {
                    // Layer 1: Background gradient with slow hue drift
                    LinearGradient(
                        colors: stateColors,
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .hueRotation(.degrees(sin(time * 0.105) * 12))

                    // Layer 2: Wandering radial underglow
                    RadialGradient(
                        colors: [glowColor.opacity(0.55), .clear],
                        center: UnitPoint(x: cx, y: cy),
                        startRadius: size * 0.03,
                        endRadius: size * 0.48
                    )
                    .blendMode(.plusLighter)

                    // Layer 3: Base depth glow (slow, counterclockwise)
                    OrbRotatingGlow(
                        color: glowColor,
                        speed: 12 * speedMultiplier,
                        direction: .counterClockwise
                    )
                    .padding(size * 0.03)
                    .blur(radius: size * 0.10)
                    .rotationEffect(.degrees(180))

                    // Layer 4: Primary wavy blob
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

                    // Layer 5: Secondary wavy blob
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

                    // Layer 6: Tertiary wavy blob
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

                    // Layer 7: Core glow (fast, heavily blurred)
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

                    // Layer 8: Specular highlight (glass sphere "hot spot")
                    OrbSpecularHighlight(time: time, size: size)

                    // Layer 9: Floating particle motes
                    OrbParticleCanvas(time: time, size: size, glowColor: glowColor)

                    // Layer 10: Rim glow (glass-sphere edge)
                    OrbRimGlow()
                }
                .mask { Circle() }
                .glassEffect(.clear.tint(glassTint), in: .circle)
                .modifier(OrbShadowModifier(colors: stateColors, radius: size * 0.10))
            }
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
/// High-frequency shimmer layered on top of slow deformation
/// creates micro-energy that reads as "alive."
private struct OrbBlobCanvas: View {
    let cycleDuration: Double
    let amplitudeScale: Double

    private struct BlobPoint {
        let amplitude: Double
        let timeScale: Double
        let phaseOffset: Double
        let shimmerFreq: Double   // High-frequency micro-jitter
        let shimmerAmp: Double    // Very small amplitude
    }

    private static let points: [BlobPoint] = [
        BlobPoint(amplitude: 0.16, timeScale: 1.00, phaseOffset: 0,              shimmerFreq: 7.3, shimmerAmp: 0.018),
        BlobPoint(amplitude: 0.24, timeScale: 0.65, phaseOffset: .pi / 3,        shimmerFreq: 8.7, shimmerAmp: 0.022),
        BlobPoint(amplitude: 0.18, timeScale: 1.25, phaseOffset: 2 * .pi / 3,    shimmerFreq: 6.1, shimmerAmp: 0.015),
        BlobPoint(amplitude: 0.22, timeScale: 0.85, phaseOffset: .pi,            shimmerFreq: 9.2, shimmerAmp: 0.020),
        BlobPoint(amplitude: 0.17, timeScale: 1.15, phaseOffset: 4 * .pi / 3,    shimmerFreq: 7.8, shimmerAmp: 0.017),
        BlobPoint(amplitude: 0.25, timeScale: 0.75, phaseOffset: 5 * .pi / 3,    shimmerFreq: 8.3, shimmerAmp: 0.024),
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let baseRadius = min(size.width, size.height) * 0.40

                // Slow breathing (~21s cycle)
                let breathFactor = 0.75 + 0.25 * sin(time * 0.3)

                // Main oscillation phase
                let angle = (time / cycleDuration) * 2 * .pi

                let animated: [CGPoint] = (0..<6).map { i in
                    let baseAngle = Double(i) * (.pi / 3)
                    let cfg = Self.points[i]

                    let effectiveAmp = cfg.amplitude * amplitudeScale * breathFactor

                    // Slow primary motion + fast micro-shimmer
                    let xOff = sin(angle * cfg.timeScale + cfg.phaseOffset) * effectiveAmp
                        + sin(time * cfg.shimmerFreq + cfg.phaseOffset) * cfg.shimmerAmp
                    let yOff = cos(angle * cfg.timeScale + cfg.phaseOffset) * effectiveAmp
                        + cos(time * cfg.shimmerFreq + cfg.phaseOffset * 1.3) * cfg.shimmerAmp

                    return CGPoint(
                        x: center.x + cos(baseAngle) * baseRadius * (1.0 + xOff),
                        y: center.y + sin(baseAngle) * baseRadius * (1.0 + yOff)
                    )
                }

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

// MARK: - OrbSpecularHighlight

/// A small bright ellipse that slowly orbits near the top of the sphere,
/// simulating a light source reflecting off glass.
private struct OrbSpecularHighlight: View {
    let time: Double
    let size: CGFloat

    var body: some View {
        // Orbit near the upper hemisphere
        let orbitRadius = size * 0.18
        let angle = time * 0.4  // Slow orbit (~16s full rotation)
        let x = size / 2 + cos(angle) * orbitRadius
        let y = size * 0.30 + sin(angle) * orbitRadius * 0.5  // Flattened ellipse orbit

        // Subtle pulsing brightness
        let pulse = 0.6 + 0.4 * sin(time * 1.3)

        Canvas { context, canvasSize in
            let highlight = Path(
                ellipseIn: CGRect(
                    x: x - size * 0.07,
                    y: y - size * 0.04,
                    width: size * 0.14,
                    height: size * 0.08
                )
            )
            context.fill(highlight, with: .color(.white.opacity(0.55 * pulse)))
        }
        .blur(radius: size * 0.04)
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

// MARK: - OrbParticleCanvas

/// Tiny bright motes that drift outward from the center,
/// creating a sense of energy emanating from the orb.
private struct OrbParticleCanvas: View {
    let time: Double
    let size: CGFloat
    let glowColor: Color

    // 8 particles with deterministic parameters (no @State needed)
    private static let particleSeeds: [(phase: Double, speed: Double, angle: Double, size: Double)] = [
        (0.0,  0.8,  0.4,   2.5),
        (1.2,  1.1,  1.7,   2.0),
        (2.5,  0.6,  2.9,   3.0),
        (3.7,  0.9,  4.1,   1.8),
        (4.9,  1.3,  5.3,   2.2),
        (6.1,  0.7,  0.8,   2.8),
        (7.3,  1.0,  3.5,   1.5),
        (8.5,  0.85, 2.1,   2.3),
    ]

    private static let cycleDuration: Double = 5.0

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let maxDrift = size * 0.38

            for seed in Self.particleSeeds {
                // Each particle loops independently based on its phase offset
                let t = ((time * seed.speed + seed.phase)
                    .truncatingRemainder(dividingBy: Self.cycleDuration)) / Self.cycleDuration

                // Ease-out drift: starts near center, decelerates outward
                let drift = maxDrift * (1 - pow(1 - t, 2.0))

                // Fade in quickly, fade out slowly
                let alpha: Double
                if t < 0.15 {
                    alpha = t / 0.15
                } else {
                    alpha = 1.0 - ((t - 0.15) / 0.85)
                }

                let x = center.x + cos(seed.angle) * drift
                let y = center.y + sin(seed.angle) * drift

                let rect = CGRect(
                    x: x - seed.size / 2,
                    y: y - seed.size / 2,
                    width: seed.size,
                    height: seed.size
                )

                context.fill(
                    Circle().path(in: rect),
                    with: .color(.white.opacity(alpha * 0.6))
                )
            }
        }
        .blur(radius: 1.5)
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

// MARK: - OrbRotatingGlow (Crescent Light)

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
