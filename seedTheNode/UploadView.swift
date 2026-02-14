//
//  UploadView.swift
//  seedTheNode
//
//  Created by Darrion Johnson on 2/14/26.
//

import AVFoundation
import Speech
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Audio Source Mode

enum AudioSourceMode: String, CaseIterable, Identifiable {
    case file
    case record

    var id: String { rawValue }

    var label: String {
        switch self {
        case .file: "File"
        case .record: "Record"
        }
    }
}

// MARK: - Upload View

struct UploadView: View {
    @Environment(NodeService.self) private var node
    @Environment(AppRouter.self) private var router
    @Environment(TrackSuggestionService.self) private var ai

    // User preferences from Settings
    @AppStorage("defaultArtistName") private var defaultArtistName = ""
    @AppStorage("useDefaultArtist") private var useDefaultArtist = true
    @AppStorage("extractFileMetadata") private var extractFileMetadata = true
    @AppStorage("afterUpload") private var afterUpload = AfterUploadAction.stay

    // Form state
    @State private var trackTitle = ""
    @State private var artistName = ""
    @State private var showArtistField = false
    @State private var acceptedTags: [String] = []
    @State private var audioMode: AudioSourceMode = .file
    @State private var isUploading = false
    @State private var showSuccess = false
    @State private var showFilePicker = false
    @State private var selectedFileURL: URL?
    @State private var selectedFileName: String?
    @State private var recorder = VoiceRecorder()

    private var resolvedArtist: String {
        if showArtistField || !useDefaultArtist || defaultArtistName.isEmpty {
            return artistName
        }
        return defaultArtistName
    }

    private var canUpload: Bool {
        !trackTitle.isEmpty && !resolvedArtist.isEmpty && audioReady && !isUploading
    }

    var body: some View {
        NavigationStack {
            Form {
                // Step 1: Name it
                titleSection

                // AI suggestions — only when available and audio is attached
                if ai.isAvailable, ai.suggestion != nil || ai.isGenerating {
                    suggestionSection
                }

                // Step 2: Add audio
                audioSection

                // Step 3: Ship it
                uploadSection
            }
            .navigationTitle("Upload")
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: audioTypes,
                allowsMultipleSelection: false
            ) { result in
                handleFilePick(result)
            }
            .alert("Track Uploaded", isPresented: $showSuccess) {
                Button("OK") {
                    handleAfterUpload()
                }
            } message: {
                Text("Your track has been pinned to IPFS and added to the catalog.")
            }
            .sensoryFeedback(.success, trigger: showSuccess)
        }
    }

    // MARK: - Step 1: Title & Artist

    @ViewBuilder
    private var titleSection: some View {
        Section {
            TextField("Track Title", text: $trackTitle)

            if showArtistField || !useDefaultArtist || defaultArtistName.isEmpty {
                HStack {
                    TextField("Artist Name", text: $artistName)
                        .textContentType(.name)

                    if useDefaultArtist && !defaultArtistName.isEmpty {
                        Button("Default") {
                            artistName = defaultArtistName
                            showArtistField = false
                        }
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } else {
                HStack {
                    Label(defaultArtistName, systemImage: "person.fill")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Change") {
                        artistName = defaultArtistName
                        showArtistField = true
                    }
                    .font(.subheadline)
                }
            }
        } header: {
            Label("Track Info", systemImage: "music.note")
        } footer: {
            if useDefaultArtist && !defaultArtistName.isEmpty && !showArtistField {
                Text("Artist auto-filled from Settings.")
            }
        }
    }

    // MARK: - AI Suggestions

    @ViewBuilder
    private var suggestionSection: some View {
        Section {
            if ai.isGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Thinking…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let suggestion = ai.suggestion {
                // Title suggestion — tap to accept
                if !suggestion.suggestedTitle.isEmpty && suggestion.suggestedTitle != trackTitle {
                    Button {
                        trackTitle = suggestion.suggestedTitle
                    } label: {
                        HStack {
                            Label(suggestion.suggestedTitle, systemImage: "text.badge.star")
                            Spacer()
                            Text("Use")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .tint(.primary)
                }

                // Tag chips — tap to toggle
                if !suggestion.tags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mood / Tags")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        FlowLayout(spacing: 8) {
                            ForEach(suggestion.tags, id: \.self) { tag in
                                TagChip(
                                    label: tag,
                                    isSelected: acceptedTags.contains(tag)
                                ) {
                                    if acceptedTags.contains(tag) {
                                        acceptedTags.removeAll { $0 == tag }
                                    } else {
                                        acceptedTags.append(tag)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } header: {
            Label("Suggestions", systemImage: "sparkles")
        } footer: {
            Text("On-device AI · Private · No data leaves your phone")
        }
    }

    // MARK: - Step 2: Audio (Segmented)

    @ViewBuilder
    private var audioSection: some View {
        Section {
            Picker("Source", selection: $audioMode) {
                ForEach(AudioSourceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
            .onChange(of: audioMode) {
                if audioMode == .file && recorder.hasRecording {
                    recorder.deleteRecording()
                } else if audioMode == .record && selectedFileURL != nil {
                    selectedFileURL = nil
                    selectedFileName = nil
                }
            }

            switch audioMode {
            case .file:
                filePickerRow

            case .record:
                voiceRecorderRow
            }

            if audioReady {
                readyRow
            }
        } header: {
            Label("Audio", systemImage: "waveform")
        }
    }

    // File mode content
    @ViewBuilder
    private var filePickerRow: some View {
        Button {
            showFilePicker = true
        } label: {
            HStack {
                Label(
                    selectedFileName ?? "Choose Audio File",
                    systemImage: selectedFileURL != nil ? "doc.fill" : "doc.badge.plus"
                )
                Spacer()
                if selectedFileURL != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
    }

    // Record mode content
    @ViewBuilder
    private var voiceRecorderRow: some View {
        Button {
            if recorder.isRecording {
                recorder.stop()
                requestSuggestions()
            } else {
                recorder.start()
            }
        } label: {
            HStack {
                Label(
                    recorder.isRecording
                        ? "Stop · \(recorder.formattedDuration)"
                        : recorder.hasRecording
                            ? "Re-record"
                            : "Start Recording",
                    systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.fill"
                )
                .foregroundStyle(recorder.isRecording ? .red : .accentColor)

                Spacer()

                if recorder.isRecording {
                    recordingIndicator
                } else if recorder.hasRecording {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }

        // Live transcript while recording
        if recorder.isRecording, recorder.isTranscribing {
            let displayText = recorder.finalTranscript + recorder.liveTranscript
            if !displayText.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "text.bubble")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .padding(.top, 2)
                    Text(displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                        .lineLimit(3)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeInOut(duration: 0.3), value: displayText)
            }
        }

        if recorder.hasRecording && !recorder.isRecording {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "waveform")
                        .foregroundStyle(.secondary)
                    Text("Voice note · \(recorder.formattedDuration)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear", role: .destructive) {
                        recorder.deleteRecording()
                        ai.clear()
                        acceptedTags = []
                    }
                    .font(.subheadline)
                }

                // Show final transcript after recording
                if !recorder.finalTranscript.trimmingCharacters(in: .whitespaces).isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "text.bubble.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .padding(.top, 2)
                        Text(recorder.finalTranscript.trimmingCharacters(in: .whitespaces))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                }
            }
        }
    }

    private var recordingIndicator: some View {
        Circle()
            .fill(.red)
            .frame(width: 8, height: 8)
            .phaseAnimator([false, true]) { content, phase in
                content.opacity(phase ? 1 : 0.3)
            } animation: { _ in
                .easeInOut(duration: 0.6)
            }
    }

    @ViewBuilder
    private var readyRow: some View {
        if audioMode == .file, let name = selectedFileName {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Clear", role: .destructive) {
                    clearAudio()
                    ai.clear()
                    acceptedTags = []
                }
                .font(.subheadline)
            }
        }
    }

    // MARK: - Step 3: Upload

    @ViewBuilder
    private var uploadSection: some View {
        Section {
            Button {
                Task { await upload() }
            } label: {
                HStack {
                    Spacer()
                    if isUploading {
                        ProgressView()
                            .controlSize(.small)
                        Text("Uploading…")
                            .font(.headline)
                    } else {
                        Label("Upload to Node", systemImage: "arrow.up.circle.fill")
                            .font(.headline)
                    }
                    Spacer()
                }
            }
            .disabled(!canUpload)
        } footer: {
            if let error = node.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    // MARK: - AI Suggestions Trigger

    private func requestSuggestions() {
        guard ai.isAvailable else { return }

        // Grab the transcript if we have one (from voice recording)
        let transcript = recorder.finalTranscript.trimmingCharacters(in: .whitespaces)

        Task {
            await ai.suggest(
                filename: selectedFileName ?? recorder.recordingURL?.lastPathComponent,
                existingTitle: trackTitle.isEmpty ? nil : trackTitle,
                artistName: resolvedArtist.isEmpty ? nil : resolvedArtist,
                transcript: transcript.isEmpty ? nil : transcript
            )
        }
    }

    // MARK: - Audio State

    private var audioReady: Bool {
        selectedFileURL != nil || recorder.hasRecording
    }

    private var audioTypes: [UTType] {
        [.mp3, .mpeg4Audio, .aiff, .wav, .audio]
    }

    private func clearAudio() {
        selectedFileURL = nil
        selectedFileName = nil
        recorder.deleteRecording()
    }

    // MARK: - File Picker

    private func handleFilePick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            recorder.deleteRecording()

            let accessing = url.startAccessingSecurityScopedResource()
            selectedFileURL = url
            selectedFileName = url.lastPathComponent

            if extractFileMetadata {
                Task { await extractMetadata(from: url) }
            }

            // Trigger AI suggestions from the filename
            requestSuggestions()

            if accessing { url.stopAccessingSecurityScopedResource() }

        case .failure(let error):
            if (error as NSError).code == CocoaError.userCancelled.rawValue { return }
            node.lastError = error.localizedDescription
        }
    }

    // MARK: - Metadata Extraction

    private func extractMetadata(from url: URL) async {
        let asset = AVURLAsset(url: url)
        do {
            let metadata = try await asset.load(.metadata)
            for item in metadata {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if trackTitle.isEmpty, let title = try? await item.load(.stringValue) {
                        trackTitle = title
                    }
                case .commonKeyArtist:
                    if !useDefaultArtist || defaultArtistName.isEmpty {
                        if artistName.isEmpty, let artist = try? await item.load(.stringValue) {
                            artistName = artist
                        }
                    }
                default:
                    break
                }
            }
        } catch {
            // Best-effort — don't surface metadata errors
        }
    }

    // MARK: - Upload

    private func upload() async {
        isUploading = true
        node.lastError = nil

        guard let track = await node.createTrack(title: trackTitle, artistName: resolvedArtist) else {
            isUploading = false
            return
        }

        if let fileURL = selectedFileURL {
            let accessing = fileURL.startAccessingSecurityScopedResource()
            let mimeType = mimeTypeFor(fileURL)
            _ = await node.uploadAudio(trackId: track.id, fileURL: fileURL, mimeType: mimeType)
            if accessing { fileURL.stopAccessingSecurityScopedResource() }
        } else if let recordingURL = recorder.recordingURL {
            _ = await node.uploadAudio(trackId: track.id, fileURL: recordingURL, mimeType: "audio/mp4")
        }

        isUploading = false
        showSuccess = true
    }

    private func clearForm() {
        trackTitle = ""
        artistName = ""
        showArtistField = false
        acceptedTags = []
        ai.clear()
        clearAudio()
    }

    private func handleAfterUpload() {
        switch afterUpload {
        case .stay:
            clearForm()
        case .clearForm:
            clearForm()
        case .catalog:
            clearForm()
            router.selectedTab = .catalog
        }
    }

    private func mimeTypeFor(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp3": "audio/mpeg"
        case "m4a", "mp4", "aac": "audio/mp4"
        case "wav": "audio/wav"
        case "aiff", "aif": "audio/aiff"
        case "flac": "audio/flac"
        case "ogg": "audio/ogg"
        default: "audio/mpeg"
        }
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

// MARK: - Flow Layout (wrapping horizontal layout for tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (positions, CGSize(width: maxWidth, height: y + rowHeight))
    }
}

// MARK: - Voice Recorder (AVAudioEngine + Live Transcription)

@Observable
final class VoiceRecorder {

    // Public state (UI-facing — same API as before)
    var isRecording = false
    var hasRecording = false
    var duration: TimeInterval = 0
    var recordingURL: URL?

    // Live transcript from SpeechAnalyzer (new)
    var liveTranscript = ""
    var finalTranscript = ""
    var isTranscribing = false

    var formattedDuration: String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // Audio engine (replaces AVAudioRecorder)
    private let engine = AVAudioEngine()
    private var outputFile: AVAudioFile?
    private var timer: Timer?

    // Speech transcription
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var analyzerFormat: AVAudioFormat?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var audioConverter: AVAudioConverter?
    private var transcriptionTask: Task<Void, Never>?

    func start() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            return
        }

        // Prepare output file (AAC .m4a)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice_note_\(UUID().uuidString).m4a")

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { return }

        // AAC output settings for the file
        let outputSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        guard let aacFormat = AVAudioFormat(settings: outputSettings) else { return }

        do {
            outputFile = try AVAudioFile(forWriting: url, settings: aacFormat.settings)
        } catch {
            return
        }

        recordingURL = url

        // Set up speech transcription (best-effort)
        setupTranscription()

        // Install tap — split buffers to file writer + speech analyzer
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // 1. Write to file
            try? self.outputFile?.write(from: buffer)

            // 2. Feed to speech analyzer (if available)
            self.feedToAnalyzer(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            return
        }

        // Start reading transcription results
        startTranscriptionResults()

        isRecording = true
        hasRecording = false
        liveTranscript = ""
        finalTranscript = ""
        duration = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.duration += 1
        }
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        outputFile = nil

        timer?.invalidate()
        timer = nil

        // Finalize transcription
        inputContinuation?.finish()
        isTranscribing = false

        isRecording = false
        hasRecording = recordingURL != nil
    }

    func deleteRecording() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        hasRecording = false
        duration = 0
        liveTranscript = ""
        finalTranscript = ""
        teardownTranscription()
    }

    // MARK: - Speech Transcription Setup

    private func setupTranscription() {
        guard SpeechTranscriber.isAvailable else { return }

        let speechTranscriber = SpeechTranscriber(
            locale: .current,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )

        transcriber = speechTranscriber
        analyzer = SpeechAnalyzer(modules: [speechTranscriber])

        isTranscribing = true

        // Get the best format and start the analyzer with an async stream
        Task {
            analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [speechTranscriber])

            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            inputContinuation = continuation

            do {
                try await analyzer?.start(inputSequence: stream)
            } catch {
                isTranscribing = false
            }
        }
    }

    private func feedToAnalyzer(_ buffer: AVAudioPCMBuffer) {
        guard let analyzerFormat, let inputContinuation else { return }

        let converted: AVAudioPCMBuffer
        do {
            converted = try convertBuffer(buffer, to: analyzerFormat)
        } catch {
            return
        }

        inputContinuation.yield(AnalyzerInput(buffer: converted))
    }

    private func startTranscriptionResults() {
        guard let transcriber else { return }

        transcriptionTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    let text = String(result.text.characters)
                    if result.isFinal {
                        self.finalTranscript += text + " "
                        self.liveTranscript = ""
                    } else {
                        self.liveTranscript = text
                    }
                }
            } catch {
                // Transcription errors are non-fatal
            }
        }
    }

    private func teardownTranscription() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        inputContinuation?.finish()
        inputContinuation = nil

        Task { [weak self] in
            await self?.analyzer?.cancelAndFinishNow()
        }

        analyzer = nil
        transcriber = nil
        audioConverter = nil
        isTranscribing = false
    }

    // MARK: - Audio Format Conversion

    private func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat != format else { return buffer }

        if audioConverter == nil || audioConverter?.outputFormat != format {
            audioConverter = AVAudioConverter(from: inputFormat, to: format)
            audioConverter?.primeMethod = .none
        }

        guard let converter = audioConverter else { return buffer }

        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))

        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else {
            return buffer
        }

        var processed = false
        let status = converter.convert(to: output, error: nil) { _, statusPtr in
            defer { processed = true }
            statusPtr.pointee = processed ? .noDataNow : .haveData
            return processed ? nil : buffer
        }

        return status == .error ? buffer : output
    }
}

#Preview {
    UploadView()
        .environment(NodeService())
        .environment(AppRouter())
        .environment(TrackSuggestionService())
}
