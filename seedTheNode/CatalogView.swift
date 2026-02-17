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

    @State private var trackToDelete: Track?

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
                        ForEach(Array(node.tracks.enumerated()), id: \.element.id) { index, track in
                            TrackRow(track: track)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if track.ipfsCid != nil {
                                        player.playCatalog(
                                            tracks: node.tracks,
                                            startingAt: index,
                                            baseURL: node.baseURL
                                        )
                                    }
                                }
                                .contextMenu {
                                    if track.ipfsCid != nil {
                                        Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                                            player.queue.insert(track, position: .afterCurrent)
                                        }
                                        Button("Play Later", systemImage: "text.line.last.and.arrowtriangle.forward") {
                                            player.queue.insert(track, position: .end)
                                        }
                                        Divider()
                                    }
                                    Button("Delete Track", systemImage: "trash", role: .destructive) {
                                        trackToDelete = track
                                    }
                                }
                        }
                        .onDelete { indexSet in
                            if let index = indexSet.first {
                                trackToDelete = node.tracks[index]
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
            .alert("Delete Track?", isPresented: .init(
                get: { trackToDelete != nil },
                set: { if !$0 { trackToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) {
                    trackToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let track = trackToDelete {
                        deleteTrack(track)
                        trackToDelete = nil
                    }
                }
            } message: {
                if let track = trackToDelete {
                    Text("\(track.title) will be removed from the node and unpinned from IPFS.")
                }
            }
        }
    }

    private func deleteTrack(_ track: Track) {
        // If deleting the currently playing track, skip to next (or stop)
        if player.currentTrackId == track.id {
            player.skipNext()
        }
        // Also remove from the play queue
        player.queue.remove(trackId: track.id)

        Task {
            _ = await node.deleteTrack(track.id)
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
