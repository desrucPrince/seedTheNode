//
//  UploadView.swift
//  seedTheNode
//
//  Created by Darrion Johnson on 2/14/26.
//

import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct UploadView: View {
    @Environment(NodeService.self) private var node
    @Environment(AppRouter.self) private var router

    // User preferences from Settings
    @AppStorage("defaultArtistName") private var defaultArtistName = ""
    @AppStorage("useDefaultArtist") private var useDefaultArtist = true
    @AppStorage("extractFileMetadata") private var extractFileMetadata = true
    @AppStorage("afterUpload") private var afterUpload = AfterUploadAction.stay

    // Form state
    @State private var trackTitle = ""
    @State private var artistName = ""
    @State private var showArtistField = false
    @State private var isUploading = false
    @State private var showSuccess = false
    @State private var showFilePicker = false
    @State private var selectedFileURL: URL?
    @State private var selectedFileName: String?
    @State private var recorder = VoiceRecorder()

    /// The resolved artist: uses the override field if shown, otherwise the default
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
                trackInfoSection
                audioSection
                uploadSection

                if let error = node.lastError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
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

    // MARK: - Track Info Section

    @ViewBuilder
    private var trackInfoSection: some View {
        Section {
            TextField("Track Title", text: $trackTitle)
                .textContentType(.none)

            // Conditional artist field
            if showArtistField || !useDefaultArtist || defaultArtistName.isEmpty {
                // Full editable field
                HStack {
                    TextField("Artist Name", text: $artistName)
                        .textContentType(.name)

                    if useDefaultArtist && !defaultArtistName.isEmpty {
                        Button("Use Default") {
                            artistName = defaultArtistName
                            showArtistField = false
                        }
                        .font(.caption)
                    }
                }
            } else {
                // Collapsed: show default with override option
                HStack {
                    Label(defaultArtistName, systemImage: "person.fill")
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Change") {
                        artistName = defaultArtistName
                        showArtistField = true
                    }
                    .font(.caption)
                }
            }
        } header: {
            Text("Track Info")
        } footer: {
            if useDefaultArtist && !defaultArtistName.isEmpty && !showArtistField {
                Text("Using default artist from Settings.")
            }
        }
    }

    // MARK: - Audio Section

    @ViewBuilder
    private var audioSection: some View {
        Section("Audio") {
            // File picker
            Button {
                showFilePicker = true
            } label: {
                HStack {
                    Label("Choose File", systemImage: "waveform")
                    Spacer()
                    if let name = selectedFileName {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            // Voice recorder
            Button {
                if recorder.isRecording {
                    recorder.stop()
                } else {
                    selectedFileURL = nil
                    selectedFileName = nil
                    recorder.start()
                }
            } label: {
                HStack {
                    Label(
                        recorder.isRecording ? "Stop Recording" : "Record Voice Note",
                        systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.fill"
                    )
                    .foregroundStyle(recorder.isRecording ? .red : .accentColor)
                    Spacer()
                    if recorder.isRecording {
                        Text(recorder.formattedDuration)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.red)
                    } else if recorder.hasRecording {
                        Text("Voice note ready")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Status row
            if audioReady {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(audioSourceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear", role: .destructive) {
                        clearAudio()
                    }
                    .font(.caption)
                }
            }
        }
    }

    // MARK: - Upload Section

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
                        Text("Uploading...")
                            .font(.headline)
                    } else {
                        Label("Upload to Node", systemImage: "arrow.up.circle.fill")
                            .font(.headline)
                    }
                    Spacer()
                }
            }
            .disabled(!canUpload)
        }
    }

    // MARK: - Audio State

    private var audioReady: Bool {
        selectedFileURL != nil || recorder.hasRecording
    }

    private var audioSourceLabel: String {
        if let name = selectedFileName {
            return "File: \(name)"
        } else if recorder.hasRecording {
            return "Voice note (\(recorder.formattedDuration))"
        }
        return ""
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
            // Metadata extraction is best-effort — don't surface errors
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
        clearAudio()
    }

    private func handleAfterUpload() {
        switch afterUpload {
        case .stay:
            break
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

// MARK: - Voice Recorder

@Observable
final class VoiceRecorder {
    var isRecording = false
    var hasRecording = false
    var duration: TimeInterval = 0
    var recordingURL: URL?

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?

    var formattedDuration: String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    func start() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
        } catch {
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice_note_\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            recordingURL = url
            isRecording = true
            hasRecording = false
            duration = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.duration += 1
            }
        } catch {
            return
        }
    }

    func stop() {
        audioRecorder?.stop()
        timer?.invalidate()
        timer = nil
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
    }
}

#Preview {
    UploadView()
        .environment(NodeService())
        .environment(AppRouter())
}
