//
//  CatalogView.swift
//  seedTheNode
//
//  Created by Darrion Johnson on 2/14/26.
//

import SwiftUI

struct CatalogView: View {
    @Environment(NodeService.self) private var node
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        NavigationStack {
            Group {
                if node.tracks.isEmpty {
                    ContentUnavailableView(
                        "No Tracks Yet",
                        systemImage: "music.note",
                        description: Text("Upload your first track to get started.")
                    )
                } else {
                    List {
                        ForEach(node.tracks) { track in
                            TrackRow(track: track)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if track.ipfsCid != nil {
                                        player.play(track: track, baseURL: node.baseURL)
                                    }
                                }
                        }
                        .onDelete { indexSet in
                            Task {
                                for index in indexSet {
                                    let track = node.tracks[index]
                                    _ = await node.deleteTrack(track.id)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Catalog")
            .refreshable {
                await node.fetchTracks()
            }
            .task {
                await node.fetchTracks()
            }
        }
    }
}

struct TrackRow: View {
    let track: Track
    @Environment(AudioPlayer.self) private var player

    private var isCurrentTrack: Bool {
        player.currentTrackId == track.id
    }

    var body: some View {
        HStack(spacing: 12) {
            // Play/pause indicator
            if track.ipfsCid != nil {
                if isCurrentTrack && player.isBuffering {
                    ProgressView()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: isCurrentTrack && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundColor(isCurrentTrack ? .accentColor : .secondary)
                }
            } else {
                Image(systemName: "circle.dashed")
                    .font(.title2)
                    .foregroundStyle(.quaternary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.headline)
                    .foregroundColor(isCurrentTrack ? .accentColor : .primary)
                HStack {
                    Text(track.artistName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if track.ipfsCid != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    CatalogView()
        .environment(NodeService())
        .environment(AudioPlayer())
}
