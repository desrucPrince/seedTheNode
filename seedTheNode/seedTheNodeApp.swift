//
//  seedTheNodeApp.swift
//  seedTheNode
//
//  Created by Darrion Johnson on 2/14/26.
//

import SwiftUI

@main
struct seedTheNodeApp: App {
    @State private var nodeService = NodeService()
    @State private var audioPlayer = AudioPlayer()
    @State private var router = AppRouter()
    @State private var suggestionService = TrackSuggestionService()
    @State private var transcriptService = TranscriptService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(nodeService)
                .environment(audioPlayer)
                .environment(router)
                .environment(suggestionService)
                .environment(transcriptService)
        }
    }
}
