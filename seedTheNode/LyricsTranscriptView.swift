//
//  LyricsTranscriptView.swift
//  seedTheNode
//
//  Created by Darrion Johnson on 2/14/26.
//

import SwiftUI

struct LyricsTranscriptView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(TranscriptService.self) private var transcriptService

    private var activeLineIndex: Int? {
        guard let transcript = transcriptService.currentTranscript else { return nil }
        let time = player.currentTime

        var bestIndex: Int?
        for (i, line) in transcript.lines.enumerated() {
            if time >= line.startTime && time <= line.endTime {
                return i
            }
            if time > line.endTime {
                bestIndex = i
            }
        }
        return bestIndex
    }

    var body: some View {
        Group {
            if transcriptService.isTranscribing {
                transcribingPlaceholder
            } else if let transcript = transcriptService.currentTranscript,
                      !transcript.lines.isEmpty {
                transcriptScrollView(transcript)
            } else if transcriptService.transcriptionError != nil {
                errorPlaceholder
            } else {
                emptyPlaceholder
            }
        }
    }

    // MARK: - Transcript Scroll

    @ViewBuilder
    private func transcriptScrollView(_ transcript: TrackTranscript) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                Spacer().frame(height: 100)

                LazyVStack(spacing: 16) {
                    ForEach(transcript.lines) { line in
                        Text(line.text)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .id(line.id)
                            .foregroundStyle(
                                line.id == activeLineIndex ? .primary : .secondary
                            )
                            .opacity(line.id == activeLineIndex ? 1.0 : 0.4)
                            .scaleEffect(line.id == activeLineIndex ? 1.0 : 0.92)
                            .animation(.easeInOut(duration: 0.35), value: activeLineIndex)
                            .scrollTransition { content, phase in
                                content
                                    .blur(radius: phase.isIdentity ? 0 : 2)
                                    .opacity(phase.isIdentity ? 1 : 0.5)
                            }
                            .onTapGesture {
                                if player.duration > 0 {
                                    player.seek(to: line.startTime / player.duration)
                                }
                            }
                    }
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 100)
            }
            .scrollIndicators(.hidden)
            .onChange(of: activeLineIndex) { _, newIndex in
                guard let newIndex else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    // MARK: - Placeholders

    private var transcribingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Transcribing...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Generating word-by-word transcript")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var errorPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Transcript unavailable")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            if transcriptService.currentTranscript != nil {
                // Transcript exists but has no lines — no speech detected
                Text("No speech detected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("This track may be instrumental")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("No transcript")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    LyricsTranscriptView()
        .environment(AudioPlayer())
        .environment(TranscriptService())
}
