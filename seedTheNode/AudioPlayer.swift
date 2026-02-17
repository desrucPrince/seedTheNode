//
//  AudioPlayer.swift
//  seedTheNode
//
//  Created by Darrion Johnson on 2/14/26.
//

import AVFoundation
import Accelerate
import MediaPlayer
import Observation

@Observable
final class AudioPlayer: NSObject {

    // MARK: - Public State

    var isPlaying = false
    var isBuffering = false
    var currentTrackId: String?
    var currentTrackTitle: String?
    var currentArtistName: String?
    var currentTrackCID: String?
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var error: String?

    let queue = PlayQueue()

    // Spectrum
    var spectrumData: [Float] = Array(repeating: 0, count: 32)
    var isVisualizationActive = false {
        didSet {
            if isVisualizationActive { installSpectrumTap() }
            else { removeSpectrumTap() }
        }
    }

    var hasTrack: Bool { currentTrackId != nil }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    var formattedCurrentTime: String { formatTime(currentTime) }
    var formattedDuration: String { formatTime(duration) }

    // MARK: - Audio Engine

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    private var seekFrameOffset: AVAudioFramePosition = 0
    private var displayLink: CADisplayLink?
    private var downloadTask: URLSessionDownloadTask?
    private(set) var tempFileURL: URL?
    private var baseURL: String = ""
    private var hasSetupRemoteCommands = false
    private var spectrumTapInstalled = false
    var downloadProgress: Double = 0
    private var _downloadSession: URLSession?
    private var downloadSession: URLSession {
        if let session = _downloadSession { return session }
        let session = URLSession(configuration: .default,
                                 delegate: DownloadDelegate(player: self),
                                 delegateQueue: nil)
        _downloadSession = session
        return session
    }

    // Generation counter — incremented on every new playback or seek.
    // Completion callbacks capture the current value; if it doesn't match
    // when the callback fires, the callback is stale and ignored.
    private var playbackGeneration: Int = 0

    // FFT
    private var fftSetup: vDSP_DFT_Setup?
    private let fftSize = 2048

    // MARK: - Init

    override init() {
        super.init()
        setupEngine()
        setupInterruptionHandling()
    }

    // MARK: - Engine Setup

    private func setupEngine() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
    }

    // MARK: - Playback

    func play(track: Track, baseURL: String) {
        self.baseURL = baseURL

        if currentTrackId == track.id, audioFile != nil {
            // Track is loaded — just toggle play/pause
            togglePlayPause()
            return
        }

        // Either new track or previous download failed — (re)download
        stopEngine()
        currentTrackId = track.id
        currentTrackTitle = track.title
        currentArtistName = track.artistName
        currentTrackCID = track.ipfsCid
        isBuffering = true
        error = nil

        configureAudioSession()
        setupRemoteCommandsIfNeeded()
        downloadAndPlay(track: track, baseURL: baseURL)
    }

    func playFromQueue(track: Track) {
        stopEngine()
        currentTrackId = track.id
        currentTrackTitle = track.title
        currentArtistName = track.artistName
        currentTrackCID = track.ipfsCid
        isBuffering = true
        error = nil

        downloadAndPlay(track: track, baseURL: baseURL)
    }

    func playCatalog(tracks: [Track], startingAt index: Int, baseURL: String) {
        self.baseURL = baseURL

        let target = tracks[index]
        if currentTrackId == target.id, audioFile != nil {
            togglePlayPause()
            return
        }

        queue.play(tracks: tracks, startingAt: index)
        configureAudioSession()
        setupRemoteCommandsIfNeeded()

        if let track = queue.currentTrack {
            stopEngine()
            currentTrackId = track.id
            currentTrackTitle = track.title
            currentArtistName = track.artistName
            currentTrackCID = track.ipfsCid
            isBuffering = true
            error = nil
            downloadAndPlay(track: track, baseURL: baseURL)
        }
    }

    func togglePlayPause() {
        if isPlaying {
            playerNode.pause()
            isPlaying = false
            stopDisplayLink()
        } else if audioFile != nil {
            try? engine.start()
            playerNode.play()
            isPlaying = true
            startDisplayLink()
        } else {
            // No audio loaded (download failed) — nothing to resume
            return
        }
        updateNowPlayingInfo()
    }

    func stop() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadProgress = 0
        stopEngine()
        cleanupTempFile()
        queue.clear()

        currentTrackId = nil
        currentTrackTitle = nil
        currentArtistName = nil
        currentTrackCID = nil
        currentTime = 0
        duration = 0
        error = nil

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        deactivateAudioSession()
    }

    func seek(to fraction: Double) {
        guard duration > 0, let audioFile else { return }

        let targetTime = fraction * duration
        let targetFrame = AVAudioFramePosition(targetTime * audioFile.processingFormat.sampleRate)
        let framesRemaining = AVAudioFrameCount(audioFile.length - targetFrame)
        guard framesRemaining > 0 else { return }

        // Bump generation so the old schedule's completion is ignored
        playbackGeneration += 1
        let gen = playbackGeneration

        playerNode.stop()
        seekFrameOffset = targetFrame

        playerNode.scheduleSegment(
            audioFile,
            startingFrame: targetFrame,
            frameCount: framesRemaining,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            self?.handlePlaybackCompletion(generation: gen)
        }

        if isPlaying {
            playerNode.play()
        }
        currentTime = targetTime
        updateNowPlayingInfo()
    }

    func skipNext() {
        guard let nextTrack = queue.next() else {
            stopEngine()
            isPlaying = false
            currentTime = 0
            stopDisplayLink()
            updateNowPlayingInfo()
            return
        }
        playFromQueue(track: nextTrack)
    }

    func skipPrevious() {
        guard let prevTrack = queue.previous(currentTimeInTrack: currentTime) else { return }
        if prevTrack.id == currentTrackId {
            seek(to: 0)
        } else {
            playFromQueue(track: prevTrack)
        }
    }

    // MARK: - Private Playback

    private func downloadAndPlay(track: Track, baseURL: String) {
        guard let cid = track.ipfsCid else {
            isBuffering = false
            error = "Track has no audio"
            return
        }

        guard let url = URL(string: "\(baseURL)/api/stream/\(cid)") else {
            isBuffering = false
            error = "Invalid stream URL"
            return
        }

        downloadProgress = 0
        downloadTask = downloadSession.downloadTask(with: url)
        downloadTask?.resume()
    }

    func handleDownloadCompletion(fileURL: URL) {
        downloadTask = nil
        downloadProgress = 1.0

        guard let cid = currentTrackCID else {
            isBuffering = false
            error = "Track CID missing after download"
            return
        }

        let stableName = FileManager.default.temporaryDirectory
            .appendingPathComponent("playback_\(cid).m4a")
        try? FileManager.default.removeItem(at: stableName)

        do {
            try FileManager.default.moveItem(at: fileURL, to: stableName)
        } catch {
            isBuffering = false
            self.error = "Failed to save audio: \(error.localizedDescription)"
            return
        }

        startPlayback(fileURL: stableName, cid: cid)
    }

    func handleDownloadError(_ err: Error) {
        downloadTask = nil
        isBuffering = false
        downloadProgress = 0
        error = err.localizedDescription
    }

    private func startPlayback(fileURL: URL, cid: String) {
        tempFileURL = fileURL

        do {
            let file = try AVAudioFile(forReading: fileURL)
            audioFile = file

            let fileSampleRate = file.processingFormat.sampleRate
            duration = Double(file.length) / fileSampleRate

            guard duration > 0 else {
                isBuffering = false
                error = "Could not read audio file"
                return
            }

            // Reconnect with the file's native processing format
            let format = file.processingFormat

            engine.disconnectNodeOutput(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)

            seekFrameOffset = 0
            playbackGeneration += 1
            let gen = playbackGeneration

            playerNode.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                self?.handlePlaybackCompletion(generation: gen)
            }

            // Install spectrum tap BEFORE engine.start() — adding it to the
            // initial graph avoids the crackle from live graph reconfiguration.
            if isVisualizationActive && !spectrumTapInstalled {
                installSpectrumTap()
            }

            try engine.start()
            playerNode.play()

            isBuffering = false
            isPlaying = true
            startDisplayLink()
            updateNowPlayingInfo()
        } catch {
            isBuffering = false
            self.error = error.localizedDescription
        }
    }

    private func handlePlaybackCompletion(generation: Int) {
        Task { @MainActor in
            // Ignore stale completions from a previous track or seek
            guard generation == self.playbackGeneration else { return }

            if self.queue.repeatMode == .one {
                self.seek(to: 0)
                return
            }

            if let nextTrack = self.queue.next() {
                if nextTrack.id == self.currentTrackId {
                    self.seek(to: 0)
                } else {
                    self.playFromQueue(track: nextTrack)
                }
            } else {
                self.isPlaying = false
                self.currentTime = 0
                self.stopDisplayLink()
                self.updateNowPlayingInfo()
            }
        }
    }

    private func stopEngine() {
        // Bump generation so any pending completion callbacks are ignored
        playbackGeneration += 1

        // Remove spectrum tap BEFORE stopping engine to avoid graph inconsistency
        if spectrumTapInstalled {
            spectrumTapInstalled = false
            engine.mainMixerNode.removeTap(onBus: 0)
        }
        playerNode.stop()
        engine.stop()
        stopDisplayLink()
        isPlaying = false
        isBuffering = false
        audioFile = nil
        seekFrameOffset = 0
    }

    private func cleanupTempFile() {
        if let tempFileURL {
            try? FileManager.default.removeItem(at: tempFileURL)
        }
        tempFileURL = nil
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            self.error = "Audio session error: \(error.localizedDescription)"
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func setupInterruptionHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleInterruption(notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        Task { @MainActor in
            switch type {
            case .began:
                if self.isPlaying {
                    self.playerNode.pause()
                    self.isPlaying = false
                    self.stopDisplayLink()
                    self.updateNowPlayingInfo()
                }
            case .ended:
                if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        try? self.engine.start()
                        self.playerNode.play()
                        self.isPlaying = true
                        self.startDisplayLink()
                        self.updateNowPlayingInfo()
                    }
                }
            @unknown default:
                break
            }
        }
    }

    @objc private func handleRouteChange(notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        Task { @MainActor in
            if reason == .oldDeviceUnavailable, self.isPlaying {
                self.playerNode.pause()
                self.isPlaying = false
                self.stopDisplayLink()
                self.updateNowPlayingInfo()
            }
        }
    }

    // MARK: - Now Playing Info Center

    private func updateNowPlayingInfo() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentTrackTitle ?? "Unknown",
            MPMediaItemPropertyArtist: currentArtistName ?? "",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]

        if let trackId = currentTrackId {
            let image = renderTrackArtwork(id: trackId, size: CGSize(width: 300, height: 300))
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func renderTrackArtwork(id: String, size: CGSize) -> UIImage {
        let palettes: [(UIColor, UIColor)] = [
            (.systemPurple, .systemBlue),
            (.systemOrange, .systemPink),
            (.systemTeal, .systemMint),
            (.systemIndigo, .systemPurple),
            (.systemRed, .systemOrange),
            (.systemBlue, .systemCyan),
            (.systemPink, .systemYellow),
            (.systemGreen, .systemTeal),
        ]
        let hash = abs(id.hashValue)
        let pair = palettes[hash % palettes.count]

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let colors = [pair.0.cgColor, pair.1.cgColor]
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 1]) else { return }
            ctx.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )

            let noteConfig = UIImage.SymbolConfiguration(pointSize: size.width * 0.3, weight: .semibold)
            if let noteImage = UIImage(systemName: "music.note", withConfiguration: noteConfig) {
                let noteSize = noteImage.size
                let origin = CGPoint(x: (size.width - noteSize.width) / 2, y: (size.height - noteSize.height) / 2)
                noteImage.withTintColor(.white.withAlphaComponent(0.8), renderingMode: .alwaysOriginal)
                    .draw(at: origin)
            }
        }
    }

    // MARK: - Remote Command Center

    private func setupRemoteCommandsIfNeeded() {
        guard !hasSetupRemoteCommands else { return }
        hasSetupRemoteCommands = true

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                if !self.isPlaying { self.togglePlayPause() }
            }
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                if self.isPlaying { self.togglePlayPause() }
            }
            return .success
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.skipNext() }
            return .success
        }

        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.skipPrevious() }
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let fraction = self.duration > 0 ? posEvent.positionTime / self.duration : 0
            Task { @MainActor in self.seek(to: fraction) }
            return .success
        }
    }

    // MARK: - Spectrum Analysis (FFT)

    private func installSpectrumTap() {
        guard !spectrumTapInstalled else { return }

        // If the engine is running, pause playback briefly so the tap
        // can be installed without an audible glitch from graph reconfiguration.
        let wasPlaying = engine.isRunning && isPlaying
        if wasPlaying { playerNode.pause() }

        spectrumTapInstalled = true
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD)

        let mixer = engine.mainMixerNode
        let format = mixer.outputFormat(forBus: 0)

        mixer.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: format) { [weak self] buffer, _ in
            self?.processFFT(buffer: buffer)
        }

        if wasPlaying { playerNode.play() }
    }

    private func removeSpectrumTap() {
        guard spectrumTapInstalled else { return }
        spectrumTapInstalled = false
        engine.mainMixerNode.removeTap(onBus: 0)

        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
            fftSetup = nil
        }

        Task { @MainActor in
            self.spectrumData = Array(repeating: 0, count: 32)
        }
    }

    private func processFFT(buffer: AVAudioPCMBuffer) {
        guard let setup = fftSetup,
              let channelData = buffer.floatChannelData?[0] else { return }

        let frameCount = Int(buffer.frameLength)
        let n = min(frameCount, fftSize)

        var windowed = [Float](repeating: 0, count: n)
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        vDSP_vmul(channelData, 1, window, 1, &windowed, 1, vDSP_Length(n))

        var realInput = [Float](repeating: 0, count: fftSize)
        var imagInput = [Float](repeating: 0, count: fftSize)
        for i in 0..<n { realInput[i] = windowed[i] }

        var realOutput = [Float](repeating: 0, count: fftSize)
        var imagOutput = [Float](repeating: 0, count: fftSize)

        vDSP_DFT_Execute(setup, &realInput, &imagInput, &realOutput, &imagOutput)

        let halfSize = fftSize / 2
        var magnitudes = [Float](repeating: 0, count: halfSize)
        for i in 0..<halfSize {
            magnitudes[i] = sqrt(realOutput[i] * realOutput[i] + imagOutput[i] * imagOutput[i])
        }

        var dbMagnitudes = [Float](repeating: 0, count: halfSize)
        var one: Float = 1.0
        vDSP_vdbcon(magnitudes, 1, &one, &dbMagnitudes, 1, vDSP_Length(halfSize), 1)

        let bars = consolidateToBars(dbMagnitudes, binCount: halfSize, barCount: 32)

        Task { @MainActor in
            for i in 0..<32 {
                let target = max(0, min(1, bars[i]))
                if target > self.spectrumData[i] {
                    self.spectrumData[i] = target
                } else {
                    self.spectrumData[i] = self.spectrumData[i] * 0.8 + target * 0.2
                }
            }
        }
    }

    private func consolidateToBars(_ db: [Float], binCount: Int, barCount: Int) -> [Float] {
        var bars = [Float](repeating: 0, count: barCount)
        let minFreq: Float = 20
        let maxFreq: Float = 20000
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let logStep = (logMax - logMin) / Float(barCount)

        // Use actual mixer output sample rate for accurate bin mapping
        let sampleRate = Float(engine.mainMixerNode.outputFormat(forBus: 0).sampleRate)
        let binWidth = sampleRate / Float(fftSize)

        for bar in 0..<barCount {
            let lowFreq = pow(10, logMin + Float(bar) * logStep)
            let highFreq = pow(10, logMin + Float(bar + 1) * logStep)
            let lowBin = max(0, Int(lowFreq / binWidth))
            let highBin = min(binCount - 1, Int(highFreq / binWidth))

            if lowBin <= highBin {
                var sum: Float = 0
                var count = 0
                for bin in lowBin...highBin {
                    sum += db[bin]
                    count += 1
                }
                let avg = count > 0 ? sum / Float(count) : -160
                bars[bar] = (avg + 80) / 80
            }
        }

        return bars
    }

    // MARK: - Display Link

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
        guard isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              let audioFile else { return }

        let sampleRate = audioFile.processingFormat.sampleRate
        let elapsedSamples = playerTime.sampleTime
        currentTime = (Double(seekFrameOffset) / sampleRate) + (Double(elapsedSamples) / sampleRate)

        if currentTime > duration { currentTime = duration }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Download Delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    weak var player: AudioPlayer?

    init(player: AudioPlayer) {
        self.player = player
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor [weak player] in
            player?.downloadProgress = progress
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // URLSession deletes the file after this method returns — move it now
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".m4a")
        do {
            try FileManager.default.moveItem(at: location, to: dest)
        } catch {
            Task { @MainActor [weak player] in
                player?.handleDownloadError(error)
            }
            return
        }
        Task { @MainActor [weak player] in
            player?.handleDownloadCompletion(fileURL: dest)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error, (error as NSError).code != NSURLErrorCancelled else { return }
        Task { @MainActor [weak player] in
            player?.handleDownloadError(error)
        }
    }
}
