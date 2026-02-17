//
//  PlayQueue.swift
//  seedTheNode
//
//  Created by Darrion Johnson on 2/14/26.
//

import Foundation
import Observation

enum RepeatMode: String, CaseIterable {
    case off
    case one
    case all
}

enum InsertPosition {
    case afterCurrent
    case end
}

@Observable
final class PlayQueue {
    private(set) var tracks: [Track] = []
    private(set) var currentIndex: Int = 0
    var shuffleMode = false
    var repeatMode: RepeatMode = .off

    // Shuffled order — indices into `tracks`
    private var shuffledIndices: [Int] = []
    // Position within shuffledIndices
    private var shuffledPosition: Int = 0

    var currentTrack: Track? {
        guard !tracks.isEmpty else { return nil }
        let idx = effectiveIndex
        guard idx >= 0, idx < tracks.count else { return nil }
        return tracks[idx]
    }

    var isEmpty: Bool { tracks.isEmpty }
    var count: Int { tracks.count }

    var hasNext: Bool {
        if repeatMode == .all || repeatMode == .one { return !tracks.isEmpty }
        if shuffleMode {
            return shuffledPosition < shuffledIndices.count - 1
        }
        return currentIndex < tracks.count - 1
    }

    var hasPrevious: Bool {
        if repeatMode == .all { return !tracks.isEmpty }
        if shuffleMode {
            return shuffledPosition > 0
        }
        return currentIndex > 0
    }

    // The actual index in `tracks` accounting for shuffle
    private var effectiveIndex: Int {
        if shuffleMode, !shuffledIndices.isEmpty {
            return shuffledIndices[shuffledPosition]
        }
        return currentIndex
    }

    // MARK: - Queue Management

    func play(tracks: [Track], startingAt index: Int) {
        // Only include playable tracks (have IPFS CID)
        let playable = tracks.filter { $0.ipfsCid != nil }
        guard !playable.isEmpty else { return }

        self.tracks = playable

        // Find the requested track in the filtered list
        let requestedTrack = tracks[index]
        let startIndex = playable.firstIndex(where: { $0.id == requestedTrack.id }) ?? 0

        currentIndex = startIndex

        if shuffleMode {
            buildShuffledOrder(anchoring: startIndex)
        }
    }

    func next() -> Track? {
        guard !tracks.isEmpty else { return nil }

        if repeatMode == .one {
            return currentTrack
        }

        if shuffleMode {
            if shuffledPosition < shuffledIndices.count - 1 {
                shuffledPosition += 1
            } else if repeatMode == .all {
                buildShuffledOrder(anchoring: nil)
            } else {
                return nil
            }
            currentIndex = shuffledIndices[shuffledPosition]
        } else {
            if currentIndex < tracks.count - 1 {
                currentIndex += 1
            } else if repeatMode == .all {
                currentIndex = 0
            } else {
                return nil
            }
        }

        return currentTrack
    }

    func previous(currentTimeInTrack: TimeInterval = 0) -> Track? {
        guard !tracks.isEmpty else { return nil }

        // If more than 3 seconds into track, restart current track
        if currentTimeInTrack > 3 {
            return currentTrack
        }

        if shuffleMode {
            if shuffledPosition > 0 {
                shuffledPosition -= 1
            } else if repeatMode == .all {
                shuffledPosition = shuffledIndices.count - 1
            } else {
                return currentTrack // restart current
            }
            currentIndex = shuffledIndices[shuffledPosition]
        } else {
            if currentIndex > 0 {
                currentIndex -= 1
            } else if repeatMode == .all {
                currentIndex = tracks.count - 1
            } else {
                return currentTrack // restart current
            }
        }

        return currentTrack
    }

    func insert(_ track: Track, position: InsertPosition) {
        guard track.ipfsCid != nil else { return }

        switch position {
        case .afterCurrent:
            let insertIdx = currentIndex + 1
            tracks.insert(track, at: min(insertIdx, tracks.count))
            if shuffleMode {
                // Insert right after current position in shuffle order
                let nextShufflePos = shuffledPosition + 1
                shuffledIndices.insert(insertIdx, at: min(nextShufflePos, shuffledIndices.count))
                // Adjust indices for the insertion
                for i in shuffledIndices.indices {
                    if shuffledIndices[i] >= insertIdx, i != min(nextShufflePos, shuffledIndices.count - 1) {
                        shuffledIndices[i] += 1
                    }
                }
            }
        case .end:
            tracks.append(track)
            if shuffleMode {
                shuffledIndices.append(tracks.count - 1)
            }
        }
    }

    func remove(trackId: String) {
        guard let idx = tracks.firstIndex(where: { $0.id == trackId }) else { return }

        // Adjust currentIndex if the removed track is before or at the current position
        let wasBeforeCurrent = idx < currentIndex
        let wasAtCurrent = idx == currentIndex

        tracks.remove(at: idx)

        if shuffleMode {
            // Remove from shuffled indices and adjust remaining
            shuffledIndices.removeAll { $0 == idx }
            for i in shuffledIndices.indices {
                if shuffledIndices[i] > idx {
                    shuffledIndices[i] -= 1
                }
            }
            if shuffledPosition >= shuffledIndices.count {
                shuffledPosition = max(0, shuffledIndices.count - 1)
            }
        }

        if wasBeforeCurrent {
            currentIndex = max(0, currentIndex - 1)
        } else if wasAtCurrent {
            currentIndex = min(currentIndex, max(0, tracks.count - 1))
        }
    }

    func toggleShuffle() {
        shuffleMode.toggle()
        if shuffleMode {
            buildShuffledOrder(anchoring: currentIndex)
        } else {
            shuffledIndices = []
            shuffledPosition = 0
        }
    }

    func clear() {
        tracks = []
        currentIndex = 0
        shuffledIndices = []
        shuffledPosition = 0
    }

    // MARK: - Shuffle

    private func buildShuffledOrder(anchoring anchorIndex: Int?) {
        var indices = Array(tracks.indices)

        // Fisher-Yates shuffle
        for i in stride(from: indices.count - 1, through: 1, by: -1) {
            let j = Int.random(in: 0...i)
            indices.swapAt(i, j)
        }

        if let anchor = anchorIndex {
            // Move anchor to front so current track plays first
            if let pos = indices.firstIndex(of: anchor) {
                indices.remove(at: pos)
                indices.insert(anchor, at: 0)
            }
            shuffledPosition = 0
        } else {
            shuffledPosition = 0
        }

        shuffledIndices = indices
    }
}
