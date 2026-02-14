//
//  TrackSuggestionService.swift
//  seedTheNode
//
//  Created by Darrion Johnson on 2/14/26.
//

import FoundationModels
import Observation

// MARK: - Generable Output

/// Defines the structured output the on-device model returns.
/// Each @Guide description steers the 3B-param model toward useful,
/// artist-friendly results — creative shorthand, not industry taxonomy.
@Generable
struct TrackSuggestion: Equatable {

    @Guide(description: "A clean, human-readable track title derived from the filename or voice note context. Remove version numbers, underscores, and file extensions. Keep it concise and musical.")
    let suggestedTitle: String

    @Guide(description: "2 to 4 short creative tags describing the mood, energy, or purpose of this track idea. Use artist shorthand like 'late night vibe', 'hook idea', 'needs drums', 'aggressive flow' — not formal genre labels.")
    let tags: [String]
}

// MARK: - Suggestion Service

@Observable
final class TrackSuggestionService {

    /// The latest suggestion (nil until generated, cleared between uploads)
    var suggestion: TrackSuggestion?

    /// True while the model is generating
    var isGenerating = false

    /// Whether the on-device model is ready to use
    var isAvailable: Bool { model.availability == .available }

    private let model = SystemLanguageModel.default
    private var session: LanguageModelSession?

    init() {
        if model.availability == .available {
            session = LanguageModelSession {
                """
                You are a creative assistant for an independent music artist using a
                decentralized audio platform. Your job is to suggest clean track titles
                and short mood/vibe tags based on filenames, voice note descriptions,
                or existing metadata. Think like an artist in the studio — use casual,
                creative language, not formal music industry categories.
                """
            }
        }
    }

    /// Generate suggestions from whatever context is available.
    /// The `transcript` parameter provides speech-to-text from a voice recording,
    /// giving the model rich creative context instead of just a UUID filename.
    /// Best-effort — failures are silent and never block the upload flow.
    func suggest(filename: String?, existingTitle: String?, artistName: String?, transcript: String? = nil) async {
        guard let session, isAvailable else { return }

        isGenerating = true
        suggestion = nil

        var prompt = "Suggest a track title and mood tags for this upload:\n"

        if let filename, !filename.isEmpty {
            prompt += "- Filename: \(filename)\n"
        }
        if let existingTitle, !existingTitle.isEmpty {
            prompt += "- Current title: \(existingTitle)\n"
        }
        if let artistName, !artistName.isEmpty {
            prompt += "- Artist: \(artistName)\n"
        }
        if let transcript, !transcript.isEmpty {
            prompt += "- Voice note transcript: \"\(transcript)\"\n"
            prompt += "- Use the transcript to understand the mood, intent, and creative direction of this idea.\n"
        } else if filename?.hasPrefix("voice_note_") == true {
            prompt += "- This is a voice recording / idea capture, not a finished track.\n"
        }

        do {
            let response = try await session.respond(to: prompt, generating: TrackSuggestion.self)
            suggestion = response.content
        } catch {
            suggestion = nil
        }

        isGenerating = false
    }

    /// Clear the current suggestion (called on form reset)
    func clear() {
        suggestion = nil
    }
}
