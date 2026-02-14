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
    @State private var trackTitle = ""
    @State private var artistName = ""
    @State private var isUploading = false
    @State private var showSuccess = false
    @State private var showFilePicker = false
    @State private var selectedFileURL: URL?
    @State private var selectedFileName: String?
    @State private var recorder = VoiceRecorder()

    var body: some View {
        NavigationStack {
            Form {
                Section("Track Info") {
                    TextField("Track Title", text: $trackTitle)
                    TextField("Artist Name", text: $artistName)
                }

                Section("Audio File") {
                    // File picker button
                    Button {
                        showFilePicker = true
                    } label: {
                        HStack {
                            Label("Choose Audio File", systemImage: "doc.badge.plus")
                            Spacer()
                            if let name = selectedFileName {
                                Text(name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    // Voice recorder button
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

                    // Show what's selected
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
                    .disabled(trackTitle.isEmpty || artistName.isEmpty || isUploading)
                }

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
                Button("OK") { }
            } message: {
                Text("Your track has been added to your catalog and pinned to IPFS.")
            }
        }
    }

    // MARK: - Audio state

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

    // MARK: - File picker handling

    private func handleFilePick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            recorder.deleteRecording()
            selectedFileURL = url
            selectedFileName = url.lastPathComponent
        case .failure(let error):
            // Don't show error when user simply cancels the picker
            if (error as NSError).code == CocoaError.userCancelled.rawValue { return }
            node.lastError = error.localizedDescription
        }
    }

    // MARK: - Upload

    private func upload() async {
        isUploading = true
        node.lastError = nil

        // 1. Create the track record
        guard let track = await node.createTrack(title: trackTitle, artistName: artistName) else {
            isUploading = false
            return
        }

        // 2. Upload audio if we have it
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
        trackTitle = ""
        artistName = ""
        clearAudio()
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
}
