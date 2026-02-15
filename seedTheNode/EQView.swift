//
//  EQView.swift
//  seedTheNode
//
//  Created by Darrion Johnson on 2/14/26.
//

import SwiftUI

struct EQView: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        VStack(spacing: 16) {
            // Preset picker
            Picker("Preset", selection: Binding(
                get: { player.eqPreset },
                set: { player.eqPreset = $0 }
            )) {
                ForEach(EQPreset.allCases) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .pickerStyle(.menu)

            // Band sliders
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<10, id: \.self) { index in
                    EQBandSlider(
                        gain: Binding(
                            get: { player.eqBands[index] },
                            set: { player.setEQBand(index: index, gain: $0) }
                        ),
                        label: AudioPlayer.eqLabels[index]
                    )
                }
            }
            .frame(height: 140)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct EQBandSlider: View {
    @Binding var gain: Float
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            // Gain label
            Text(String(format: "%+.0f", gain))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)

            // Vertical slider
            GeometryReader { geo in
                let height = geo.size.height
                let normalized = CGFloat((gain + 12) / 24) // -12...+12 → 0...1
                let thumbY = height * (1 - normalized)

                ZStack {
                    // Track
                    Capsule()
                        .fill(.quaternary)
                        .frame(width: 3)

                    // Center line
                    Rectangle()
                        .fill(.tertiary)
                        .frame(width: 7, height: 1)
                        .position(x: geo.size.width / 2, y: height / 2)

                    // Filled portion from center
                    let centerY = height / 2
                    let fillHeight = abs(thumbY - centerY)
                    let fillY = min(thumbY, centerY)

                    Rectangle()
                        .fill(.tint)
                        .frame(width: 3, height: fillHeight)
                        .position(x: geo.size.width / 2, y: fillY + fillHeight / 2)

                    // Thumb
                    Circle()
                        .fill(.tint)
                        .frame(width: 14, height: 14)
                        .position(x: geo.size.width / 2, y: thumbY)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = 1 - (value.location.y / height)
                            let clamped = max(0, min(1, fraction))
                            gain = Float(clamped) * 24 - 12
                        }
                )
            }

            // Frequency label
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    EQView()
        .environment(AudioPlayer())
}
