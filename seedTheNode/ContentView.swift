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
                            Text("Buffering...")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(player.currentArtistName ?? "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.body)
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
                player.isLooping.toggle()
            } label: {
                Label(
                    player.isLooping ? "Repeat On" : "Repeat Off",
                    systemImage: "repeat"
                )
            }
            Button("Stop Playback", systemImage: "stop.fill", role: .destructive) {
                player.stop()
            }
        }
    }
}

// MARK: - Now Playing Full Screen

struct NowPlayingFullScreen: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss
    var animation: Namespace.ID

    var body: some View {
        VStack(spacing: 32) {
            // Drag indicator + close
            HStack {
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

            // Large artwork
            TrackGradient(id: player.currentTrackId ?? "")
                .frame(width: 280, height: 280)
                .clipShape(.rect(cornerRadius: 20, style: .continuous))
                .shadow(radius: 20, y: 10)

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

            // Controls
            HStack(spacing: 44) {
                Button {
                    player.isLooping.toggle()
                } label: {
                    Image(systemName: "repeat")
                        .font(.title3)
                        .foregroundStyle(player.isLooping ? .primary : .tertiary)
                }

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 60))
                }

                Button {
                    player.stop()
                    dismiss()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
        .interactiveDismissDisabled(false)
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
}
