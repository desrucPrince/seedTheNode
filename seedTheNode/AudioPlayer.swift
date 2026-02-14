//
//  AudioPlayer.swift
//  seedTheNode
//
//  Created by Darrion Johnson on 2/14/26.
//

import AVFoundation
import Observation

@Observable
final class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    var isPlaying = false
    var isBuffering = false
    var isLooping = false
    var currentTrackId: String?
    var currentTrackTitle: String?
    var currentArtistName: String?
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var error: String?

    private var audioPlayer: AVAudioPlayer?
    private var displayLink: CADisplayLink?
    private var downloadTask: URLSessionDataTask?
    private var tempFileURL: URL?

    var hasTrack: Bool { currentTrackId != nil }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    var formattedCurrentTime: String {
        formatTime(currentTime)
    }

    var formattedDuration: String {
        formatTime(duration)
    }

    func play(track: Track, baseURL: String) {
        guard let cid = track.ipfsCid else { return }

        // If tapping the same track, toggle pause/resume
        if currentTrackId == track.id, let audioPlayer {
            if isPlaying {
                audioPlayer.pause()
                isPlaying = false
                stopDisplayLink()
            } else {
                audioPlayer.play()
                isPlaying = true
                startDisplayLink()
            }
            return
        }

        // New track — stop current and start new
        stop()
        currentTrackId = track.id
        currentTrackTitle = track.title
        currentArtistName = track.artistName
        isBuffering = true
        error = nil

        // Configure audio session to interrupt/duck other audio (e.g. Apple Music)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            self.error = "Audio session error: \(error.localizedDescription)"
            isBuffering = false
            return
        }

        guard let url = URL(string: "\(baseURL)/api/stream/\(cid)") else {
            error = "Invalid stream URL"
            isBuffering = false
            return
        }

        // Download the audio, write to temp file, then play
        downloadTask = URLSession.shared.dataTask(with: url) { [weak self] data, response, err in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.downloadTask = nil

                if let err {
                    self.isBuffering = false
                    self.error = err.localizedDescription
                    return
                }

                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    self.isBuffering = false
                    self.error = "Server returned HTTP \(http.statusCode)"
                    return
                }

                guard let data, !data.isEmpty else {
                    self.isBuffering = false
                    self.error = "No audio data received"
                    return
                }

                // Write to temp file with .m4a extension so AVAudioPlayer detects the codec
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("playback_\(cid).m4a")
                do {
                    try data.write(to: tempURL, options: .atomic)
                    self.tempFileURL = tempURL

                    let player = try AVAudioPlayer(contentsOf: tempURL)
                    player.delegate = self
                    player.prepareToPlay()

                    guard player.duration > 0 else {
                        self.isBuffering = false
                        self.error = "Could not read audio file"
                        return
                    }

                    self.audioPlayer = player
                    self.duration = player.duration
                    self.isBuffering = false
                    player.play()
                    self.isPlaying = true
                    self.startDisplayLink()
                } catch {
                    self.isBuffering = false
                    self.error = error.localizedDescription
                }
            }
        }
        downloadTask?.resume()
    }

    func togglePlayPause() {
        guard let audioPlayer else { return }
        if isPlaying {
            audioPlayer.pause()
            isPlaying = false
            stopDisplayLink()
        } else {
            audioPlayer.play()
            isPlaying = true
            startDisplayLink()
        }
    }

    func stop() {
        downloadTask?.cancel()
        downloadTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        stopDisplayLink()
        // Clean up temp file
        if let tempFileURL {
            try? FileManager.default.removeItem(at: tempFileURL)
        }
        tempFileURL = nil
        isPlaying = false
        isBuffering = false
        currentTrackId = nil
        currentTrackTitle = nil
        currentArtistName = nil
        currentTime = 0
        duration = 0
        error = nil

        // Deactivate session so other audio can resume
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func seek(to fraction: Double) {
        guard duration > 0, let audioPlayer else { return }
        audioPlayer.currentTime = fraction * duration
        currentTime = audioPlayer.currentTime
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.isLooping {
                player.currentTime = 0
                player.play()
                self.currentTime = 0
            } else {
                self.isPlaying = false
                self.currentTime = 0
                self.stopDisplayLink()
            }
        }
    }

    // MARK: - Display Link for time updates

    private func startDisplayLink() {
        stopDisplayLink()
        let link = CADisplayLink(target: self, selector: #selector(updateTime))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 4, maximum: 15, preferred: 8)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func updateTime() {
        guard let audioPlayer, isPlaying else { return }
        currentTime = audioPlayer.currentTime
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
