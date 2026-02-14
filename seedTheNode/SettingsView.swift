//
//  SettingsView.swift
//  seedTheNode
//
//  Created by Darrion Johnson on 2/14/26.
//

import SwiftUI

struct SettingsView: View {
    @Environment(NodeService.self) private var node
    @AppStorage("defaultArtistName") private var defaultArtistName = ""
    @AppStorage("useDefaultArtist") private var useDefaultArtist = true
    @AppStorage("extractFileMetadata") private var extractFileMetadata = true
    @AppStorage("afterUpload") private var afterUpload = AfterUploadAction.stay

    var body: some View {
        NavigationStack {
            List {
                Section("Artist Profile") {
                    TextField("Artist Name", text: $defaultArtistName)
                        .textContentType(.name)

                    Toggle("Auto-fill on uploads", isOn: $useDefaultArtist)
                }

                Section {
                    Toggle("Extract metadata from files", isOn: $extractFileMetadata)

                    Picker("After upload", selection: $afterUpload) {
                        ForEach(AfterUploadAction.allCases) { action in
                            Text(action.label).tag(action)
                        }
                    }
                } header: {
                    Text("Upload Defaults")
                } footer: {
                    Text("Metadata extraction auto-fills title and artist from audio file tags when available.")
                }

                Section("Node") {
                    InfoRow(label: "Address", value: node.hostname)
                    InfoRow(label: "API Port", value: "\(node.port)")
                    InfoRow(label: "API URL", value: node.baseURL)
                    InfoRow(label: "Status", value: node.isOnline ? "Connected" : "Disconnected")
                }

                Section("IPFS") {
                    if let ipfs = node.ipfsInfo {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Peer ID")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(ipfs.peerId ?? "Unknown")
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .textSelection(.enabled)
                        }
                        InfoRow(label: "Version", value: ipfs.agentVersion ?? "--")
                        InfoRow(label: "Peers", value: "\(ipfs.peers)")
                    } else {
                        InfoRow(label: "Status", value: "Not connected")
                    }
                }

                Section("App") {
                    InfoRow(label: "Version", value: "0.1.0")
                    InfoRow(label: "Build", value: "1")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - After Upload Behavior

enum AfterUploadAction: String, CaseIterable, Identifiable {
    case stay
    case clearForm
    case catalog

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stay: "Stay on Upload"
        case .clearForm: "Clear & Start New"
        case .catalog: "Go to Catalog"
        }
    }
}

#Preview {
    SettingsView()
        .environment(NodeService())
}
