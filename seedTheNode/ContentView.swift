//
//  ContentView.swift
//  seedTheNode
//
//  Created by Darrion Johnson on 2/14/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(AppRouter.self) private var router
    @Environment(TranscriptService.self) private var transcriptService
    @Namespace private var playerAnimation
    @State private var expandPlayer = false

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            Tab("Overview", systemImage: "bolt.fill", value: .overview) {
                OverviewView()
            }

            Tab("Catalog", systemImage: "music.note.list", value: .catalog) {
                CatalogView()
            }

            Tab("Upload", systemImage: "square.and.arrow.up.fill", value: .upload) {
                UploadView()
            }

            Tab("Settings", systemImage: "gearshape.fill", value: .settings) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: player.hasTrack) {
            NowPlayingAccessory(expandPlayer: $expandPlayer, animation: playerAnimation)
        }
        .fullScreenCover(isPresented: $expandPlayer) {
            NowPlayingFullScreen(animation: playerAnimation)
                .navigationTransition(.zoom(sourceID: "NOWPLAYING", in: playerAnimation))
        }
        .onChange(of: player.currentTrackId) { _, newId in
            if newId == nil {
                transcriptService.clear()
            }
        }
    }
}

// MARK: - Now Playing Accessory (Liquid Glass)

struct NowPlayingAccessory: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Binding var expandPlayer: Bool
    var animation: Namespace.ID

    var body: some View {
        Button {
            expandPlayer = true
        } label: {
            HStack(spacing: 12) {
                TrackGradient(id: player.currentTrackId ?? "")
                    .frame(width: 30, height: 30)
                    .clipShape(.rect(cornerRadius: 6, style: .continuous))

                if placement == .expanded {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.currentTrackTitle ?? "Unknown")
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        if let error = player.error {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .lineLimit(1)
                        } else if player.isBuffering {
                            HStack(spacing: 6) {
                                if player.downloadProgress > 0 {
                                    ProgressView(value: player.downloadProgress)
                                        .progressViewStyle(.linear)
                                        .frame(width: 60)
                                        .tint(.secondary)
                                    Text("\(Int(player.downloadProgress * 100))%")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Connecting...")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Text(player.currentArtistName ?? "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }

                // Skip back
                Button {
                    player.skipPrevious()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.caption)
                }

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.body)
                }

                // Skip forward
                Button {
                    player.skipNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.caption)
                }

                Button {
                    player.stop()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: "NOWPLAYING", in: animation)
        .contextMenu {
            Button {
                player.queue.toggleShuffle()
            } label: {
                Label(
                    player.queue.shuffleMode ? "Shuffle On" : "Shuffle Off",
                    systemImage: "shuffle"
                )
            }
            Button {
                let modes = RepeatMode.allCases
                if let idx = modes.firstIndex(of: player.queue.repeatMode) {
                    player.queue.repeatMode = modes[(idx + 1) % modes.count]
                }
            } label: {
                Label(
                    repeatLabel,
                    systemImage: repeatIcon
                )
            }
            Button("Stop Playback", systemImage: "stop.fill", role: .destructive) {
                player.stop()
            }
        }
    }

    private var repeatLabel: String {
        switch player.queue.repeatMode {
        case .off: "Repeat Off"
        case .one: "Repeat One"
        case .all: "Repeat All"
        }
    }

    private var repeatIcon: String {
        switch player.queue.repeatMode {
        case .off: "repeat"
        case .one: "repeat.1"
        case .all: "repeat"
        }
    }
}

// MARK: - Now Playing Full Screen

struct NowPlayingFullScreen: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(TranscriptService.self) private var transcriptService
    @Environment(\.dismiss) private var dismiss
    @State private var showTranscript = false
    var animation: Namespace.ID

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("PLAYING FROM QUEUE")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(player.queue.count) tracks")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            Spacer()

            // Artwork / Transcript toggle area
            Group {
                if showTranscript {
                    LyricsTranscriptView()
                        .frame(width: 300, height: 300)
                        .clipShape(.rect(cornerRadius: 20, style: .continuous))
                } else {
                    TrackGradient(id: player.currentTrackId ?? "")
                        .overlay(alignment: .bottom) {
                            if player.isVisualizationActive && player.isPlaying {
                                SpectrumView()
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 16)
                                    .frame(height: 120)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(width: 280, height: 280)
                        .clipShape(.rect(cornerRadius: 20, style: .continuous))
                        .shadow(radius: 20, y: 10)
                }
            }
            .onAppear { player.isVisualizationActive = !showTranscript }
            .onDisappear { player.isVisualizationActive = false }
            .onChange(of: showTranscript) { _, showing in
                player.isVisualizationActive = !showing
            }

            // Track info
            VStack(spacing: 6) {
                Text(player.currentTrackTitle ?? "Unknown")
                    .font(.title2.bold())
                Text(player.currentArtistName ?? "")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            // Seek bar
            VStack(spacing: 4) {
                Slider(value: Binding(
                    get: { player.progress },
                    set: { player.seek(to: $0) }
                ))
                .tint(.primary)

                HStack {
                    Text(player.formattedCurrentTime)
                    Spacer()
                    Text(player.formattedDuration)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            // Transport controls
            HStack(spacing: 40) {
                // Shuffle
                Button {
                    player.queue.toggleShuffle()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.title3)
                        .foregroundStyle(player.queue.shuffleMode ? .primary : .tertiary)
                }

                // Previous
                Button { player.skipPrevious() } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }

                // Play/Pause
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 60))
                }

                // Next
                Button { player.skipNext() } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }

                // Repeat
                Button {
                    let modes = RepeatMode.allCases
                    if let idx = modes.firstIndex(of: player.queue.repeatMode) {
                        player.queue.repeatMode = modes[(idx + 1) % modes.count]
                    }
                } label: {
                    Image(systemName: player.queue.repeatMode == .one ? "repeat.1" : "repeat")
                        .font(.title3)
                        .foregroundStyle(player.queue.repeatMode != .off ? .primary : .tertiary)
                }
            }

            // Transcript toggle
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showTranscript.toggle()
                }
            } label: {
                Label("Transcript", systemImage: "quote.bubble.fill")
                    .font(.subheadline)
                    .foregroundStyle(showTranscript ? .primary : .secondary)
            }

            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
        .interactiveDismissDisabled(false)
        .onAppear {
            if let cid = player.currentTrackCID,
               let fileURL = player.tempFileURL {
                transcriptService.loadTranscript(cid: cid, audioFileURL: fileURL)
            }
        }
        .onChange(of: player.tempFileURL) { _, newURL in
            // Trigger on tempFileURL change — this fires AFTER download completes,
            // so both the CID and file are guaranteed to be for the same track.
            if let cid = player.currentTrackCID, let fileURL = newURL {
                transcriptService.loadTranscript(cid: cid, audioFileURL: fileURL)
            }
        }
    }
}

// MARK: - Deterministic Gradient from Track ID

struct TrackGradient: View {
    let id: String

    private var colors: [Color] {
        let palettes: [(Color, Color)] = [
            (.purple, .blue),
            (.orange, .pink),
            (.teal, .mint),
            (.indigo, .purple),
            (.red, .orange),
            (.blue, .cyan),
            (.pink, .yellow),
            (.green, .teal),
        ]
        let hash = abs(id.hashValue)
        let pair = palettes[hash % palettes.count]
        return [pair.0, pair.1]
    }

    var body: some View {
        LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "music.note")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

#Preview {
    ContentView()
        .environment(NodeService())
        .environment(AudioPlayer())
        .environment(AppRouter())
        .environment(TranscriptService())
}
