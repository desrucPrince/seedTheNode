//
//  SpectrumView.swift
//  seedTheNode
//
//  Created by Darrion Johnson on 2/14/26.
//

import SwiftUI

struct SpectrumView: View {
    @Environment(AudioPlayer.self) private var player
    let barCount: Int

    init(barCount: Int = 24) {
        self.barCount = barCount
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
            Canvas { context, size in
                let data = player.spectrumData
                let count = min(data.count, barCount)
                guard count > 0 else { return }

                let gap: CGFloat = 3
                let totalGaps = CGFloat(count - 1) * gap
                let barWidth = (size.width - totalGaps) / CGFloat(count)
                let capsuleRadius = barWidth / 2

                for i in 0..<count {
                    // Sample from spectrum data spread across 32 bins
                    let dataIndex = Int(Float(i) / Float(count) * Float(min(data.count, 32)))
                    let safeIndex = min(dataIndex, data.count - 1)
                    let magnitude = CGFloat(max(0, min(1, data[safeIndex])))

                    // Minimum capsule height is the width (a circle), max is full height
                    let minHeight = barWidth
                    let barHeight = minHeight + magnitude * (size.height - minHeight)

                    let x = CGFloat(i) * (barWidth + gap)
                    let y = size.height - barHeight

                    let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                    let path = Path(roundedRect: rect, cornerRadius: capsuleRadius)

                    // Subtle white, fading with magnitude
                    let opacity = 0.15 + Double(magnitude) * 0.35
                    context.fill(path, with: .color(.white.opacity(opacity)))
                }
            }
        }
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        SpectrumView()
            .padding(20)
    }
    .frame(width: 280, height: 280)
    .clipShape(.rect(cornerRadius: 20))
    .environment(AudioPlayer())
}
