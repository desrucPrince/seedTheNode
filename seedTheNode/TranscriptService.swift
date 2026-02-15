//
//  TranscriptService.swift
//  seedTheNode
//
//  Created by Darrion Johnson on 2/14/26.
//

import AVFoundation
import CoreMedia
import Observation
import Speech

// MARK: - Data Models

struct TranscriptWord: Codable, Identifiable {
    let id: Int
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}

struct TranscriptLine: Codable, Identifiable {
    let id: Int
    let text: String
    let words: [TranscriptWord]

    var startTime: TimeInterval { words.first?.startTime ?? 0 }
    var endTime: TimeInterval { words.last?.endTime ?? 0 }
}

struct TrackTranscript: Codable {
    let cid: String
    let locale: String
    let lines: [TranscriptLine]
    let createdAt: Date
}

enum TranscriptError: LocalizedError {
    case localeNotSupported(String)

    var errorDescription: String? {
        switch self {
        case .localeNotSupported(let locale):
            "Speech transcription not supported for \(locale)"
        }
    }
}

/// Thread-safe accumulator so partial results survive task cancellation.
/// collectWords appends here incrementally; the timeout race reads whatever
/// has been collected so far.
final class WordAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var _words: [TranscriptWord] = []

    var words: [TranscriptWord] {
        lock.withLock { _words }
    }

    func append(_ word: TranscriptWord) {
        lock.withLock { _words.append(word) }
    }
}

// MARK: - TranscriptService

@Observable
final class TranscriptService {

    // MARK: - Public State

    var currentTranscript: TrackTranscript?
    var isTranscribing = false
    var transcriptionError: String?

    private(set) var currentCID: String?

    var isAvailable: Bool { SpeechTranscriber.isAvailable }

    // MARK: - Private

    private var transcriptionTask: Task<Void, Never>?

    // MARK: - Cache

    private var cacheDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("Transcripts", isDirectory: true)
    }

    private func cacheURL(for cid: String) -> URL {
        cacheDirectory.appendingPathComponent("\(cid).json")
    }

    // MARK: - Public API

    func loadTranscript(cid: String, audioFileURL: URL) {
        // Already loaded or actively transcribing this track — skip
        if currentCID == cid, (currentTranscript != nil || isTranscribing) { return }

        transcriptionTask?.cancel()
        currentTranscript = nil
        currentCID = cid
        transcriptionError = nil

        transcriptionTask = Task {
            // Try cache first
            if let cached = readCache(cid: cid) {
                print("[Transcript] Cache hit for \(cid) — \(cached.lines.count) lines")
                self.currentTranscript = cached
                return
            }

            print("[Transcript] Cache miss — isAvailable: \(isAvailable)")

            guard isAvailable else {
                transcriptionError = "Speech recognition not available on this device"
                return
            }

            isTranscribing = true
            // Guarantee spinner stops even if task is cancelled or throws
            defer { isTranscribing = false }

            do {
                print("[Transcript] Starting transcription of \(audioFileURL.lastPathComponent)")
                let words = try await transcribeFile(at: audioFileURL)
                print("[Transcript] Got \(words.count) words")
                let lines = groupWordsIntoLines(words)
                let transcript = TrackTranscript(
                    cid: cid,
                    locale: Locale.current.identifier,
                    lines: lines,
                    createdAt: Date()
                )

                if !Task.isCancelled {
                    self.currentTranscript = transcript
                    // Cache even empty transcripts — avoids re-transcribing
                    // instrumental tracks every time the player opens
                    writeCache(transcript)
                }
            } catch {
                print("[Transcript] Error: \(error)")
                if !Task.isCancelled {
                    transcriptionError = error.localizedDescription
                }
            }
        }
    }

    func clear() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        currentTranscript = nil
        currentCID = nil
        isTranscribing = false
        transcriptionError = nil
    }

    // MARK: - File Transcription

    /// Ensures the speech model for the given locale is downloaded and ready.
    private func ensureModelInstalled(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        let supported = await SpeechTranscriber.supportedLocales
        let supportedBCP47 = supported.map { $0.identifier(.bcp47) }
        let localeBCP47 = locale.identifier(.bcp47)

        guard supportedBCP47.contains(localeBCP47) else {
            print("[Transcript] Locale \(localeBCP47) not in supported: \(supportedBCP47)")
            throw TranscriptError.localeNotSupported(localeBCP47)
        }

        let installed = await SpeechTranscriber.installedLocales
        let installedBCP47 = Set(installed.map { $0.identifier(.bcp47) })

        if installedBCP47.contains(localeBCP47) {
            print("[Transcript] Model for \(localeBCP47) already installed")
            return
        }

        print("[Transcript] Downloading model for \(localeBCP47)...")
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
            print("[Transcript] Model download complete")
        }
    }

    /// Transcribes a file by manually reading buffers and feeding them to
    /// SpeechAnalyzer via AsyncStream. We avoid `analyzeSequence(from:)` because
    /// it creates an internal AVAudioEngine that conflicts with the playback
    /// engine (causes -10868 format errors during graph reconfiguration).
    private func transcribeFile(at url: URL) async throws -> [TranscriptWord] {
        // Use BCP47-normalized locale to match what SpeechAnalyzer expects internally
        let bcp47 = Locale.current.identifier(.bcp47)
        let locale = Locale(identifier: bcp47)
        print("[Transcript] Using locale: \(bcp47)")

        let speechTranscriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )

        // Ensure the on-device speech model is downloaded before starting
        try await ensureModelInstalled(for: speechTranscriber, locale: locale)

        let analyzer = SpeechAnalyzer(modules: [speechTranscriber])

        // Get the optimal format the analyzer wants — fall back to file format
        let audioFile = try AVAudioFile(forReading: url)
        let fileFormat = audioFile.processingFormat
        let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [speechTranscriber]
        ) ?? fileFormat

        print("[Transcript] File format: \(fileFormat), analyzer format: \(analyzerFormat)")

        // Set up format converter if needed
        var converter: AVAudioConverter?
        if fileFormat != analyzerFormat {
            converter = AVAudioConverter(from: fileFormat, to: analyzerFormat)
            converter?.primeMethod = .none
        }

        // Create the async stream to feed buffers
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()

        // Start the analyzer listening to our stream FIRST — it must be
        // processing before we start collecting results or feeding buffers.
        let analyzerTask = Task {
            try await analyzer.start(inputSequence: stream)
        }

        // Give the analyzer time to initialize its internal audio graph
        // before we start feeding buffers or iterating results.
        await Task.yield()

        // Start collecting results IMMEDIATELY — must be iterating the
        // results AsyncSequence BEFORE and DURING buffer feeding, not after.
        // The analyzer emits results as buffers arrive; if we wait until all
        // buffers are fed, the results stream may have already closed.
        //
        // Use WordAccumulator so partial results survive cancellation.
        let accumulator = WordAccumulator()
        let collectTask = Task {
            await self.collectWords(from: speechTranscriber, into: accumulator)
        }

        // Feed all audio buffers to the analyzer, then signal end of input.
        var framesRead: Int64 = 0
        let bufferSize: AVAudioFrameCount = 4096
        while audioFile.framePosition < audioFile.length {
            guard !Task.isCancelled else { break }

            let remaining = AVAudioFrameCount(audioFile.length - audioFile.framePosition)
            let framesToRead = min(bufferSize, remaining)

            guard let readBuffer = AVAudioPCMBuffer(
                pcmFormat: fileFormat,
                frameCapacity: framesToRead
            ) else { break }

            try audioFile.read(into: readBuffer)
            framesRead += Int64(readBuffer.frameLength)

            // Convert to analyzer format if needed
            let feedBuffer: AVAudioPCMBuffer
            if let converter {
                let ratio = analyzerFormat.sampleRate / fileFormat.sampleRate
                let capacity = AVAudioFrameCount(
                    (Double(readBuffer.frameLength) * ratio).rounded(.up)
                )
                guard let output = AVAudioPCMBuffer(
                    pcmFormat: analyzerFormat,
                    frameCapacity: capacity
                ) else { break }

                var processed = false
                nonisolated(unsafe) let buf = readBuffer
                let status = converter.convert(to: output, error: nil) { _, statusPtr in
                    defer { processed = true }
                    statusPtr.pointee = processed ? .noDataNow : .haveData
                    return processed ? nil : buf
                }

                feedBuffer = (status == .error) ? readBuffer : output
            } else {
                feedBuffer = readBuffer
            }

            continuation.yield(AnalyzerInput(buffer: feedBuffer))

            // Yield to avoid blocking
            await Task.yield()
        }

        print("[Transcript] Fed \(framesRead) frames to analyzer")

        // Signal end of input — this tells the analyzer no more buffers are coming.
        continuation.finish()

        // Wait for results with a short timeout. The SpeechAnalyzer processes
        // faster than real-time, so after all buffers are fed and continuation
        // is finished, results should arrive within seconds. The "unallocated
        // locales" beta bug can cause the stream to hang indefinitely.
        let timeoutSeconds: Double = 8.0
        print("[Transcript] Waiting for results (timeout: \(Int(timeoutSeconds))s)...")

        // Race: collectTask (already running) vs timeout.
        // Either way, we read from the accumulator which has partial results.
        let _: Void = await withTaskGroup(of: Void.self) { group in
            group.addTask { await collectTask.value }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                if !Task.isCancelled {
                    print("[Transcript] Timeout after \(Int(timeoutSeconds))s — using partial results")
                }
            }
            // Wait for whichever finishes first
            await group.next()
            group.cancelAll()
            collectTask.cancel()
        }
        let collectedWords = accumulator.words
        print("[Transcript] Collected \(collectedWords.count) words, cleaning up analyzer")

        // Clean up: cancel the analyzer task and tear down gently.
        // Use cancelAndFinishNow wrapped in a detached task to avoid
        // the -10868 crash — the analyzer's internal audio graph teardown
        // can conflict with our playback AVAudioEngine on the main actor.
        analyzerTask.cancel()
        let detachedAnalyzer = analyzer
        Task.detached {
            await detachedAnalyzer.cancelAndFinishNow()
        }

        return collectedWords
    }

    /// Iterates the transcriber's results stream, appending words to the
    /// accumulator as they arrive. If cancelled (by timeout), partial results
    /// are preserved in the accumulator.
    private func collectWords(from transcriber: SpeechTranscriber, into accumulator: WordAccumulator) async {
        var wordIndex = 0
        var resultCount = 0

        do {
            for try await result in transcriber.results {
                resultCount += 1
                let isFinal = result.isFinal
                let text = String(result.text.characters)
                print("[Transcript] Result #\(resultCount) final=\(isFinal): \(text.prefix(60))")

                guard isFinal else { continue }

                let attrString = result.text
                for run in attrString.runs {
                    let wordText = String(attrString[run.range].characters)
                        .trimmingCharacters(in: .whitespaces)
                    guard !wordText.isEmpty else { continue }

                    if let timeRange = run.audioTimeRange {
                        let start = CMTimeGetSeconds(timeRange.start)
                        let end = CMTimeGetSeconds(timeRange.end)
                        accumulator.append(TranscriptWord(
                            id: wordIndex,
                            text: wordText,
                            startTime: start,
                            endTime: end
                        ))
                        wordIndex += 1
                    } else {
                        let estimatedTime = accumulator.words.last?.endTime ?? 0
                        accumulator.append(TranscriptWord(
                            id: wordIndex,
                            text: wordText,
                            startTime: estimatedTime,
                            endTime: estimatedTime + 0.3
                        ))
                        wordIndex += 1
                        print("[Transcript] Word '\(wordText)' missing audioTimeRange, using estimate")
                    }
                }
            }
        } catch {
            // CancellationError or other — partial results are in accumulator
            print("[Transcript] collectWords interrupted: \(error)")
        }

        print("[Transcript] collectWords done: \(accumulator.words.count) words from \(resultCount) results")
    }

    // MARK: - Line Grouping

    private func groupWordsIntoLines(_ words: [TranscriptWord]) -> [TranscriptLine] {
        guard !words.isEmpty else { return [] }

        var lines: [TranscriptLine] = []
        var currentLineWords: [TranscriptWord] = []
        var lineIndex = 0

        for word in words {
            if let lastWord = currentLineWords.last {
                let gap = word.startTime - lastWord.endTime
                let lineSpan = word.endTime - (currentLineWords.first?.startTime ?? 0)

                // Break on: pause > 0.5s, line exceeds ~4s, or 8+ words
                if gap > 0.5 || lineSpan > 4.0 || currentLineWords.count >= 8 {
                    let text = currentLineWords.map(\.text).joined(separator: " ")
                    lines.append(TranscriptLine(
                        id: lineIndex,
                        text: text,
                        words: currentLineWords
                    ))
                    lineIndex += 1
                    currentLineWords = []
                }
            }

            currentLineWords.append(word)
        }

        // Flush remaining
        if !currentLineWords.isEmpty {
            let text = currentLineWords.map(\.text).joined(separator: " ")
            lines.append(TranscriptLine(
                id: lineIndex,
                text: text,
                words: currentLineWords
            ))
        }

        return lines
    }

    // MARK: - Cache I/O

    private func readCache(cid: String) -> TrackTranscript? {
        let url = cacheURL(for: cid)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TrackTranscript.self, from: data)
    }

    private func writeCache(_ transcript: TrackTranscript) {
        let url = cacheURL(for: transcript.cid)
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(transcript) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
